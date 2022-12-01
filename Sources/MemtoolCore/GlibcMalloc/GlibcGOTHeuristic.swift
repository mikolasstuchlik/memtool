import Cutils

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

        // Locate r_debug
        let rDebugLocation = symbols.first { symbol in
            if 
                symbol.properties.name == "r_debug",
                case let .other(file) = symbol.properties.segment,
                GlibcAssurances.fileFromGlibc(file, unloadedSymbols: unloadedSymbols)
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
            guard nameString != file else {
                return link
            }
            nextLink = link.buffer.l_next
        } while (nextLink != rDebugContent.buffer.r_map)

        return nil
    }
}

public final class GlibcErrnoAsmHeuristic {

}