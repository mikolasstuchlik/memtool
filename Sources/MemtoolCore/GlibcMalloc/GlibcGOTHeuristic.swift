import Cutils
import Foundation
import RegexBuilder
import _StringProcessing

/*
Abbreviations:
TCB - Thread Control Block
PCB - Process Control Block
DTV - Dynamic Thread Vector
TLS - Thread Local Storage
GOT - Global Offset Table
DSO - Dynamic Shared Object
*/

/*
# Objective: Locate `statuc __thread tcache`.

# Resources:
https://fasterthanli.me/series/making-our-own-executable-packer/part-13#c-programs

# Notes:

## Getting the TLS:
(lldb) image lookup -rs 'pthread_self' -v // yields 0x7ffff6896c00 as a base address in RAM
(lldb) disassemble -s 0x7ffff6896c00 -c3
libc.so.6`:
    0x7ffff6896c00 <+0>:  endbr64 
    0x7ffff6896c04 <+4>:  movq   %fs:0x10, %rax
    0x7ffff6896c0d <+13>: retq

RAX is ABI return-value register. The asm code shifts content of FS register and moves it to RAX.
But reading FS yelds 0x0, FS_BASE has to be used. Notice, that FS_BASE is already shifted!

The pthread_self return the pointer to `pthread_t` which is an "opaque" (not in the technical term)
structure, that holds the "id of the calling thread" but this value is equal to the pointer to itself.
It does not corresponds to TID.

Under the hood, the pthread_self points to `tcbhead_t` which is not part of the API. Offset 0 and 
offset 16 should contain the so called "id of the thread," thus pointer to offset 0.

## __thread variables

### errno
The objective is locating `tcache` but we also consider well known variable `errno`. The `errno` name
is only a macro, that expands into something like this `*(void*) __errno_location()` aka. it replaces
occurances of "errno" with call to the "__errno_location" function and dereferencing it's result (this
is done probably in order to hide the location of errno).

Finding and disassembling __errno_location is fairly simple, since it is only "a getter function."
(lldb) image lookup -rs '__errno_location' -v // yields 0x00007ffff7c239d0  as a base address in RAM
(lldb) disassemble -s 0x00007ffff7c239d0
libc.so.6`:
    0x7ffff7c239d0 <+0>:  endbr64
    0x7ffff7c239d4 <+4>:  mov    rax, qword ptr [rip + 0x1d2405]
    0x7ffff7c239db <+11>: add    rax, qword ptr fs:[0x0]
    0x7ffff7c239e4 <+20>: ret

Offset 4 dereferences the sum of RIP (instruction pointer) and magic number 0x1d2405 and stores the 
pointed value in RAX. The address of 0x7ffff7c239d4 + 0x1d2405 should be pointer into GOT for the 
`errno` variable. At the end of the instruction, the RAX should contain the offset of the `errno`
storage in the TLS (probably negative offset to TCB).
Offset 11 sums the offset to `errno` with the pointer to TCB (content of FS).


### tcache
The `tcache` is very similar to `errno`. We just need to find some function where the `tcache`
is used. Such function is `_int_free` in glibc/malloc/malloc.c:4414 where on line 4445 `tcache` is
compared to NULL.

Tapping into LLDB yields followin result: 
(lldb) image lookup -rs 'int_free' -v // yields 0x00007ffff7c239d0  as a base address in RAM
The base is 0x00007ffff7c239d0 but the relevant test is on +91, therefore we call
(lldb) disassemble -s 0x7ffff7c9ddeb -c 5
libc.so.6`_int_free:
    0x7ffff7c9ddeb <+91>:  mov    rax, qword ptr [rip + 0x157f86]
    0x7ffff7c9ddf2 <+98>:  mov    rbp, rdi  
    0x7ffff7c9ddf5 <+101>: mov    rsi, qword ptr fs:[rax]
    0x7ffff7c9ddf9 <+105>: test   rsi, rsi
    0x7ffff7c9ddfc <+108>: je     0x7ffff7c9de3c            ; <+172> at malloc.c:4489:6

Since both pointers in GOT should be near, following result should be reasonably small:
errno                         tcache
(0x7ffff7c239d4 + 0x1d2405) - (0x7ffff7c9ddeb + 0x157f86) = 0x68

(lldb) image list // yields that libc is loaded at 0x00007ffff7c00000

## Approaching heuristic
Discussions [insert link] and papers https://chao-tic.github.io/blog/2018/12/25/tls I was able to find
largely confirm statements above. 

I'm not at the moment aware of better solution, so I'll implement following algorithm:
 - read relative offsets of `tcache`, `errno` and other possible clandidates from `objdump` .tbss
 - find methods which involve said variables and **disassemble them**
 - read their offset in the GOT from disassembly
 - the more variables and methods are available, the better `tcache` <- '_int_free', 'errno' <- '_errno_location'
 - compute tls offsets from GOT - discard misaligned results (dump to stderr)
 - from sane values, compute `tcache` offset

 
## With ld usage
 - Search for `.bss` symbol `r_debug`
 - Bind `r_debug` to `struct r_debug`
 - `r_debug.r_map` is a link map
 - You can bind `r_debug.r_map` to `struct link_map` but important fields lie in private part
 - Create aligned copy of source code version of `struct link_map` renamed to `struct link_map_private`
 - Get tls offset from `r_debug.r_map.l_tls_modid`
 - Obtain `struct tcbhead_t`
 - Beginning of tls for desired binary should be in `tcbhead.dtv[r_debug.r_map.l_tls_modid]`
*/

public final class TbssSymbolGlibcLdHeuristic {
    public enum Error: Swift.Error {
        case initializeSessionWithMapAndSymbols
        case noSuchTbssSymbolOrFile
        case couldNotfindGlibcRdebug
        case couldNotLocateLinkItem
        case fsBaseNotInReadableSpace
        case dtvNotInitialized
        case dtvTooSmall
        case symbolNotInReadableSpace
    }

    public let pid: Int32
    public let symbolName: String
    public let fileName: String

    public let symbol: UnloadedSymbolInfo
    public let rDebug: SymbolRegion
    public let privateLinkItem: BoundRemoteMemory<link_map_private>
    public let fsBase: UInt64
    public let dtvBase: UInt64
    public let indexDtv: BoundRemoteMemory<dtv_t>
    public let loadedSymbolBase: UInt64

    public init(session: Session, fileName: String, tbssSymbolName: String) throws {
        self.pid = session.pid
        self.symbolName = tbssSymbolName
        self.fileName = fileName

        // Assert, that everything is initialized
        guard 
            let map = session.map, 
            let unloadedSymbols = session.unloadedSymbols,
            let symbols = session.symbols 
        else {
            throw Error.initializeSessionWithMapAndSymbols
        }

        // Find that desired symbol exists in .tbss
        guard let symbolReference = unloadedSymbols[fileName]?.first(where: { $0.segment == .known(.tbss) && $0.name == tbssSymbolName }) else {
            throw Error.noSuchTbssSymbolOrFile
        }
        self.symbol = symbolReference

        // Locate r_debug TODO: Should probably verify that address belongs to glib
        let rDebugLocation = symbols.first { symbol in
            if 
                symbol.properties.name == "_r_debug"
            {
                return true
            }

            return false
        }
        guard let rDebugLocation else {
            throw Error.couldNotfindGlibcRdebug
        }
        self.rDebug = rDebugLocation

        // Iterate link items in r_debug and locate item for this file
        guard let linkItem = TbssSymbolGlibcLdHeuristic.iterateRDebug(pid: pid, symbol: rDebug, file: fileName) else {
            throw Error.couldNotLocateLinkItem
        }

        // Rebound to link_item_private. Following code braks Glibc guarentees and needs to be validated!
        let privateLinkItem = BoundRemoteMemory<link_map_private>(pid: pid, load: linkItem.segment.lowerBound)
        self.privateLinkItem = privateLinkItem
        let index = privateLinkItem.buffer.l_tls_modid

        // Get FS register
        let fsBase = UInt64(UInt(bitPattern: swift_inspect_bridge__ptrace_peekuser(session.pid, FS_BASE)))
        self.fsBase = fsBase
        guard map.contains(where: { $0.range.contains(fsBase) && $0.properties.flags.contains([.read, .write])}) == true else {
            throw Error.fsBaseNotInReadableSpace
        }

        let head = BoundRemoteMemory<tcbhead_t>(pid: session.pid, load: fsBase)
        guard head.buffer.dtv != nil else {
            throw Error.dtvNotInitialized
        }
        let dtvBase = UInt64(UInt(bitPattern: head.buffer.dtv))
        self.dtvBase = dtvBase
        let dtvSizeBase = dtvBase - UInt64(MemoryLayout<dtv_t>.size)
        let dtvCount = BoundRemoteMemory<dtv_t>(pid: pid, load: dtvSizeBase)
        guard dtvCount.buffer.counter >= index else {
            throw Error.dtvTooSmall
        }

        let indexDtvBase = dtvBase + UInt64(index * MemoryLayout<dtv_t>.size)
        self.indexDtv = BoundRemoteMemory<dtv_t>(pid: pid, load: indexDtvBase)
        let loadedSymbolBase = UInt64(UInt(bitPattern: indexDtv.buffer.pointer.val)) + symbolReference.location
        self.loadedSymbolBase = loadedSymbolBase

        guard map.contains(where: { $0.range.contains(loadedSymbolBase) && $0.properties.flags.contains([.read, .write])}) == true else {
            throw Error.symbolNotInReadableSpace
        }
    }


    private static func iterateRDebug(pid: Int32, symbol: SymbolRegion, file: String) -> BoundRemoteMemory<link_map>? {
        let rDebugContent = BoundRemoteMemory<r_debug>(pid: pid, load: symbol.range.lowerBound)
        let loadLimit = UInt64(file.utf8.count)

        var nextLink = rDebugContent.buffer.r_map
        repeat {
            guard let linkPtr = nextLink else {
                break
            }

            let linkBase = UInt64(UInt(bitPattern: linkPtr))
            let link = BoundRemoteMemory<link_map>(pid: pid, load: linkBase)
            let nameBase = UInt64(UInt(bitPattern: link.buffer.l_name))
            let name = RawRemoteMemory(pid: pid, load: nameBase..<(nameBase + loadLimit))
            let nameString = String(cString: Array(name.buffer))
            // While debugging, it was discovered, that ld string contains only part of the path, "/lib/x86_64-linux-gnu/libc.so.6" instead of "/usr/lib/x86_64-linux-gnu/libc.so.6"
            if !nameString.isEmpty, file.hasSuffix(nameString) {
                return link
            }
            nextLink = link.buffer.l_next
        } while (nextLink != rDebugContent.buffer.r_map)

        return nil
    }
}

public final class GlibcErrnoAsmHeuristic {

    private static let hexanumberRef = Reference(Substring.self)

    private static let regex: Regex = {
        let hexadec = Regex {
            Optionally {
                "0x"
            }
            OneOrMore(.hexDigit)
        }
        
        return Regex {
            "rax,QWORD PTR [rip+"
            Capture(as: hexanumberRef) {
                hexadec
            }
            "]"
        }
    }()


    public enum Error: Swift.Error {
        case initializeSessionWithMap
        case disassembleEmptyResult
        case assemblyParsingFailed
        case assemblyInvariantFailed
        case glibcNotLocatedInMemory
    }

    public struct AssemblyLine {
        public let address: String
        public let raw: String
        public let opcode: String
        public let argument: String

        public init(array: [String]) {
            self.address = array.count >= 1 ? array[0] : ""
            self.raw = array.count >= 2 ? array[1] : ""
            if array.count >= 3 { 
                let components = array[2].components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines )}.filter { !$0.isEmpty }
                
                self.opcode = components.count >= 1 ? components[0] : ""
                self.argument = components.count >= 2 ? components[1] : ""
            } else {
                self.opcode = ""
                self.argument = ""
            }
        }
    }

    public let pid: Int32
    public let glibcPath: String

    public let rawProcessOutput: String
    public let errnoLocation: UInt64

    public init(session: Session, glibcPath: String) throws {
        self.pid = session.pid
        self.glibcPath = glibcPath

        // Assert, that everything is initialized
        guard 
            let map = session.map
        else {
            throw Error.initializeSessionWithMap
        }

        self.rawProcessOutput = GlibcErrnoAsmHeuristic.getErrnoLocationDisassembly(for: glibcPath)
        guard !rawProcessOutput.isEmpty else {
            throw Error.disassembleEmptyResult
        }

        let lines = rawProcessOutput.components(separatedBy: "\n")
        guard 
            let preambleEnd = lines.firstIndex(where: { $0.contains("<__errno_location")}),
            lines.endIndex > preambleEnd
        else {
            throw Error.assemblyParsingFailed
        }

        let assemblyLines = lines[lines.index(after: preambleEnd)...]

        guard assemblyLines.count >= 3 else {
            throw Error.assemblyParsingFailed
        }

        let assemblyLineComponents = assemblyLines.map { 
                $0.components(separatedBy: "\t")
                .filter { !$0.isEmpty }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } 
            }.map(AssemblyLine.init(array:))

        // Notice: we know there are at least 3 items in the array
        guard 
            assemblyLineComponents[0].opcode == "endbr64",
            assemblyLineComponents[1].opcode == "mov",
            assemblyLineComponents[2].opcode == "add", 
            assemblyLineComponents[2].argument == "rax,QWORD PTR fs:0x0"
        else {
            throw Error.assemblyInvariantFailed
        }

        guard let rip = UInt64(assemblyLineComponents[1].address.trimmingCharacters(in: CharacterSet(charactersIn: ":")), radix: 16) else {
            throw Error.assemblyParsingFailed
        }

        guard 
            let result = try? GlibcErrnoAsmHeuristic.regex.firstMatch(in: assemblyLineComponents[1].argument),
            let address = UInt64(String(result[GlibcErrnoAsmHeuristic.hexanumberRef]).trimmingPrefix("0x"), radix: 16)
        else {
            throw Error.assemblyParsingFailed
        }

        let gotOffset = address + rip

        let glibcBase: UInt64? = map.reduce(nil) { prev, current -> UInt64? in
            if case let .file(file) = current.properties.pathname, file == glibcPath {
                if let prev {
                    return min(prev, current.range.lowerBound)
                }
                return current.range.lowerBound
            }
            return prev
        }

        guard let glibcBase else { throw Error.glibcNotLocatedInMemory }

        let gotOffsetLocation = glibcBase + gotOffset

        // This access should be checked.
        let fsOffsetToErrno = BoundRemoteMemory<UInt64>(pid: pid, load: gotOffsetLocation)
        
        // Get FS register
        let fsBase = UInt64(UInt(bitPattern: swift_inspect_bridge__ptrace_peekuser(session.pid, FS_BASE)))

        // This MUST overflow. errno should be located on lower address than FS
        self.errnoLocation = fsOffsetToErrno.buffer + fsBase
    }

/* Example of disassembly
$ objdump --disassemble=__errno_location -j .text -M intel /usr/lib/x86_64-linux-gnu/libc.so.6

/usr/lib/x86_64-linux-gnu/libc.so.6:     file format elf64-x86-64


Disassembly of section .text:

00000000000239d0 <__errno_location@@GLIBC_2.2.5>:
   239d0:       f3 0f 1e fa             endbr64
   239d4:       48 8b 05 05 24 1d 00    mov    rax,QWORD PTR [rip+0x1d2405]        # 1f5de0 <h_errlist@@GLIBC_2.2.5+0xb80>
   239db:       64 48 03 04 25 00 00    add    rax,QWORD PTR fs:0x0
   239e2:       00 00
   239e4:       c3                      ret
*/
    private static func getErrnoLocationDisassembly(for glibcPath: String) -> String {
        let process = Process()
        let aStdout = Pipe()
        let aStderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/env")
        process.standardOutput = aStdout
        process.standardError = aStderr
        // more info in `man proc`
        process.arguments = ["bash", "-c", "objdump --disassemble=__errno_location -j .text -M intel \(glibcPath)"]

        try! process.run()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            error("Error: Map failed to load. Path: \(process.executableURL?.path ?? ""), arguments: \(process.arguments ?? []), termination status: \(process.terminationStatus), stderr: \(String(data: aStderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")") 
            return "" 
        }
        let result = String(data: aStdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

        return result!
    }
}
