import Cutils
import Foundation
import RegexBuilder
import _StringProcessing

/// Some of the variables required are stored in the *Thread local storage* which are those
/// variables declared with directive `__thread`. Such varibales are created for each thread
/// separately and finding them can not be achieved by mere computing of symbol offsets. This
/// class implement heuristic based on knowledge of implementation of Glibc malloc an linker.
/// 
/// Unlike following heuristic, that parses assembly and tries to get access to the GOT, this
/// heuristic looks for the offset of symbol inside the space reserved for it's library in the
/// Thread local storage.
/// The Thread local storage grows negatively from the `pthread_self`, which is known to be the 
/// pointer to `tcbhead_t`.
///  
/// ## Outline of the heuristic with the usage of ld
/// 
///  - Search for `.bss` symbol `r_debug`
///  - Bind `r_debug` to `struct r_debug`
///  - `r_debug.r_map` is a link map
///  - You can bind `r_debug.r_map` to `struct link_map` but important fields lie in private part
///  - Create aligned copy of source code version of `struct link_map` renamed to `struct link_map_private`
///  - Get tls offset from `r_debug.r_map.l_tls_modid`
///  - Obtain `struct tcbhead_t`
///  - Beginning of tls for desired binary should be in `tcbhead.dtv[r_debug.r_map.l_tls_modid]`
/// 
/// - Warning:
/// This is the most fragile part of the implementation. Heavy assumptions are made about the
/// internal implementation of not only glibc, but also glib linker. This heuristic should be
/// valiadated for every version of glibc.
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

    public let session: Session
    public let symbolName: String
    public let fileName: String

    public let symbol: UnloadedSymbolInfo
    public let rDebug: SymbolRegion
    public let privateLinkItem: BoundRemoteMemory<link_map_private>
    public let fsBase: UInt
    public let dtvBase: UInt
    public let indexDtv: BoundRemoteMemory<dtv_t>
    public let loadedSymbolBase: UInt

    public init(session: Session, fileName: String, tbssSymbolName: String) throws {
        self.session = session
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
        guard let rDebugLocation = symbols.locate(knownSymbol: .rDebug).first else {
            throw Error.couldNotfindGlibcRdebug
        }
        self.rDebug = rDebugLocation

        // Iterate link items in r_debug and locate item for this file
        guard let linkItem = try TbssSymbolGlibcLdHeuristic.iterateRDebug(session: session, symbol: rDebug, file: fileName) else {
            throw Error.couldNotLocateLinkItem
        }

        // Rebound to link_item_private. Following code braks Glibc guarentees and needs to be validated!
        let privateLinkItem = try session.checkedLoad(of: link_map_private.self, base: linkItem.segment.lowerBound, skipMismatchTypeCheck: true)
        self.privateLinkItem = privateLinkItem
        let index = privateLinkItem.buffer.l_tls_modid

        // Get FS register
        let fsBase = UInt(bitPattern: swift_inspect_bridge__ptrace_peekuser(session.ptraceId, FS_BASE))
        self.fsBase = fsBase
        guard map.contains(where: { $0.range.contains(fsBase) && $0.properties.flags.contains([.read, .write])}) == true else {
            throw Error.fsBaseNotInReadableSpace
        }

        let head = try session.checkedLoad(of: tcbhead_t.self, base: fsBase)
        guard head.buffer.dtv != nil else {
            throw Error.dtvNotInitialized
        }
        let dtvBase = UInt(bitPattern: head.buffer.dtv)
        self.dtvBase = dtvBase
        let dtvSizeBase = dtvBase - UInt(MemoryLayout<dtv_t>.size)
        let dtvCount =  try session.checkedLoad(of: dtv_t.self, base: dtvSizeBase)
        guard dtvCount.buffer.counter >= index else {
            throw Error.dtvTooSmall
        }

        let indexDtvBase = dtvBase + UInt(index * MemoryLayout<dtv_t>.size)
        self.indexDtv =  try session.checkedLoad(of: dtv_t.self, base: indexDtvBase)
        let loadedSymbolBase = UInt(bitPattern: indexDtv.buffer.pointer.val) + symbolReference.location
        self.loadedSymbolBase = loadedSymbolBase

        guard map.contains(where: { $0.range.contains(loadedSymbolBase) && $0.properties.flags.contains([.read, .write])}) == true else {
            throw Error.symbolNotInReadableSpace
        }
    }

    private static func iterateRDebug(session: Session, symbol: SymbolRegion, file: String) throws -> BoundRemoteMemory<link_map>? {
        let rDebugContent = try session.checkedLoad(of: r_debug.self, base: symbol.range.lowerBound)
        let loadLimit = UInt(file.utf8.count)

        var nextLink = rDebugContent.buffer.r_map
        repeat {
            guard let linkPtr = nextLink else {
                break
            }

            let linkBase = UInt(bitPattern: linkPtr)
            let link = try session.checkedLoad(of: link_map.self, base: linkBase)
            let nameBase = UInt(bitPattern: link.buffer.l_name)
            let name = RawRemoteMemory(pid: session.pid, load: nameBase..<(nameBase + loadLimit))
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

/// This uses heuristics in order to locate Thread Local Variable `errno`. This
/// serves no practical purpose for exploring Glibc, but it is used to verify and cross check,
/// that the method used to search for thread local variables returns correct values.
/// 
/// This heuristic uses commpon patterns found in the glibc assembly, parses them and deduces
/// the location of `errno` record in GOT. Then uses the record in GOT to access the correct value.
/// 
/// ## Further description
/// The objective is locating `tcache` but we also consider well known variable `errno`. The `errno` name
/// is only a macro, that expands into something like this `*(void*) __errno_location()` aka. it replaces
/// occurances of "errno" with call to the "__errno_location" function and dereferencing it's result (this
/// is done probably in order to hide the location of errno).
///
/// Finding and disassembling __errno_location is fairly simple, since it is only "a getter function."
/// (lldb) image lookup -rs '__errno_location' -v // yields 0x00007ffff7c239d0  as a base address in RAM
/// (lldb) disassemble -s 0x00007ffff7c239d0
/// 
///     libc.so.6`:
///         0x7ffff7c239d0 <+0>:  endbr64
///         0x7ffff7c239d4 <+4>:  mov    rax, qword ptr [rip + 0x1d2405]
///         0x7ffff7c239db <+11>: add    rax, qword ptr fs:[0x0]
///         0x7ffff7c239e4 <+20>: ret
///
/// Offset 4 dereferences the sum of RIP (instruction pointer) and magic number 0x1d2405 and stores the 
/// pointed value in RAX. The address of 0x7ffff7c239db + 0x1d2405 should be pointer into GOT for the 
/// `errno` variable. At the end of the instruction, the RAX should contain the offset of the `errno`
/// storage in the TLS (probably negative offset to TCB).
/// Offset 11 sums the offset to `errno` with the pointer to TCB (content of FS).
/// 
/// Source: [3]
/// 
/// ## Possible (but currently unused) heuristic for finding `tcache`
/// The `tcache` is very similar to `errno`. We just need to find some function where the `tcache`
/// is used. Such function is `_int_free` in glibc/malloc/malloc.c:4414 where on line 4445 `tcache` is
/// compared to NULL.
///
/// Tapping into LLDB yields followin result: 
/// (lldb) image lookup -rs 'int_free' -v // yields 0x00007ffff7c239d0  as a base address in RAM
/// The base is 0x00007ffff7c239d0 but the relevant test is on +91, therefore we call
/// (lldb) disassemble -s 0x7ffff7c9ddeb -c 5
/// 
///     libc.so.6`_int_free:
///         0x7ffff7c9ddeb <+91>:  mov    rax, qword ptr [rip + 0x157f86]
///         0x7ffff7c9ddf2 <+98>:  mov    rbp, rdi  
///         0x7ffff7c9ddf5 <+101>: mov    rsi, qword ptr fs:[rax]
///         0x7ffff7c9ddf9 <+105>: test   rsi, rsi
///         0x7ffff7c9ddfc <+108>: je     0x7ffff7c9de3c            ; <+172> at malloc.c:4489:6
///
/// Since both pointers in GOT should be near, following result should be reasonably small:
/// errno                         tcache
/// (0x7ffff7c239d4 + 0x1d2405) - (0x7ffff7c9ddeb + 0x157f86) = 0x68
///
/// (lldb) image list // yields that libc is loaded at 0x00007ffff7c00000
///
/// ### Approaching heuristic
/// Discussions [insert link] and papers [8] I was able to find
/// largely confirm statements above. 
///
/// I'm not at the moment aware of better solution, so I'll implement following algorithm:
/// 
///  - read relative offsets of `tcache`, `errno` and other possible clandidates from `objdump` .tbss
///  - find methods which involve said variables and **disassemble them**
///  - read their offset in the GOT from disassembly
///  - the more variables and methods are available, the better `tcache` <- '_int_free', 'errno' <- '_errno_location'
///  - compute tls offsets from GOT - discard misaligned results (dump to stderr)
///  - from sane values, compute `tcache` offset
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
        case additionFsandGotDidNotOverflow
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
    public let errnoLocation: UInt

    public init(session: Session, glibcPath: String) throws {
        self.pid = session.ptraceId
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

        // Via debugger I have determined, that the correct value requires `rip` to have the value of following instruction :thinking:
        guard let rip = UInt(assemblyLineComponents[2].address.trimmingCharacters(in: CharacterSet(charactersIn: ":")), radix: 16) else {
            throw Error.assemblyParsingFailed
        }

        guard 
            let result = try? GlibcErrnoAsmHeuristic.regex.firstMatch(in: assemblyLineComponents[1].argument),
            let address = UInt(String(result[GlibcErrnoAsmHeuristic.hexanumberRef]).trimmingPrefix("0x"), radix: 16)
        else {
            throw Error.assemblyParsingFailed
        }

        let gotOffset = address + rip

        let glibcBase: UInt? = map.reduce(nil) { prev, current -> UInt? in
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

        let fsOffsetToErrno = try session.checkedLoad(of: UInt.self, base: gotOffsetLocation)
        
        // Get FS register
        let fsBase = UInt(bitPattern: swift_inspect_bridge__ptrace_peekuser(session.ptraceId, FS_BASE))

        // This MUST overflow. errno should be located on lower address than FS
        let gotAddition = fsBase.addingReportingOverflow(fsOffsetToErrno.buffer)
        guard gotAddition.overflow else {
            throw Error.additionFsandGotDidNotOverflow
        }

        self.errnoLocation = gotAddition.partialValue
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
