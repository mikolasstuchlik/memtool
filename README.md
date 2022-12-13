# memtool

Memtool (libMemtoolCore) is a Linux library, that utilizes `ptrace` and other techniques in order to read dynamic memory allocated via `glibc malloc`.

## Description

This package contains three modules:

 - `Memtool` - a rudimentary interactive shell interface that is used mainly for prototyping, development and testing of the Memtool itself
 - `MemtoolCore` - the most important part of the project - allows to read and analyze remote process
 - `Cutils` - contains either function calls and macros that are impossible in Swift and copy-pasted private type definitions of `glibc`

The main goal of this package is to provide babis for successful implementation of `swift-inspect` on Linux and the equivalent of "Memory Graph" on Linux in future.

## Important considerations
The project is at early stages of development, probably closer to "proof of concept" than "minimal viable product". Various tasks (around reading ELF and DWARF) are done via calls to other programs, like `bash`, `readelf`, `objdump`, `ls`, `cat` and `grep`. **The tests are invoking `clang`, compiling and executing code shipped in the test files.**
This saved a lot of time during early stages of development but is not ideal.

Therefore **before running tests on this library, make sure you are fine with all the `Swift.Process` calls!**

The project is not yet capable of locating strictly speaking *all* of the malloc chunks. See *Status* section.

At this time, only Glibc x86-64 platform is targeted. There are no plans to implement support for any other platform right now.

## Installation
Make sure that debuggin symbols are part of your `libc` and `ld` libraries (or install packages containing the stripped version).

### CLI tool
Use `swift build` and run the product.
### As package dependency
Add this dependency into your `Package.swift` file:
```swift
.package(url: "https://github.com/mikolasstuchlik/memtool", .branch("master")),
```
include `MemtoolCore` as a dependency:
```swift
.target(name: "<target>", dependencies: [
    .product(name: "MemtoolCore", package: "memtool"),
]),
```

## Usage

Since the `memtool` CLI reflects the internal implementation of the `MemtoolCore`, the usage is similar for both CLI and API. You should always make following steps:
 
 - Attach to a process (via `PTRACE_ATTACH` and a bash call to `ls /proc/[pid]/task`)
 - Load memory map of the process (bash call to `cat /proc/[pid]/maps`)
 - Load symbols of the process (bash call to various executables `objdump -tL [executable]`)
 - Invoke Glibc analysis.

Assume traced program has PID `1234`

### CLI
Run the program with `sudo`:
```
sudo .build/debug/memtool
```

Available commands are listed when typing `help`. Notice, that **some commands require strings enclosed in " and some numbers are hexadecimal.**
Interactive mode usage:
```
? help
Available operations:
  attach   - [PID] attempts to attach to a process.
  detach   - Detached from attached process.
  status   - [-m|-u|-l|-a] Prints current session to stdout. Use -m for map, -u for unloaded symbols and -l for loaded symbols, -a for glibc malloc analysis result.
  map      - Parse /proc/pid/maps file.
  symbol   - Requires maps. Loads all symbols for all object files in memory.
  help     - Shows available commands on stdout.
  exit     - Stops the execution
  lookup   - [-e] "[text]" searches symbols matching text. Use -e if you want only exact matches.
  peek     - [typename] [hexa pointer] Peeks ans bind a memory to any of following types: ["malloc_state", "malloc_chunk", "_heap_info", "tcbhead_t", "dtv_pointer", "link_map", "r_debug", "link_map_private"]
  addr     - [hexa pointer] Prints all entities that contain given address with offsets.
  analyze  - Attempts to enumerate heap chubnks
  chunk    - [hexa pointer] Attempts to load address as chunk and dumps it
  tcb      - Locates and prints Thread Control Block for traced thread
  word     - [decimal count] [hex pointer] [-a] Dumps given amount of 64bit words; Use [-a] if you want the result in ASCII (`count` will load be 8*count bit instad of 64*count bit). (Note: data are not adjusted for Big Endian.)
  tbss     - "symbol name" "file name" Attempts to locate tbss symbol in a file
  errnoGot - "glibc file name" Attempts to parse `errno` location from disassembly in order to verify results of other heuristics.
  reveal   - [hexa pointer] Applies macro `REVEAL_PTR`
```

Example usage:
```bash
? attach 1234   # Sends `PTRACE_ATTACH` to the process and threads
? map           # Loads the memory map
? symbol        # Loads symbols of loaded executables
                # Probably some warning/errors will be printed to stderr
? analyze       # Performs Glibc malloc analysis
? status -a     # Prints the list of memory segments recognized by Glibc malloc analysis
```

### Swift API
The intended usage for this project is via the API. The library makes as much types `public` as possible. For basic usage, here are listed the most important types:

 - `class ProcessSession` - an instance of this class manages `ptrace` connection to a process
 - `class GlibcMallocAnalyzer` - an instance of this class analyzes the Glibc mallc
 - `struct BoundRemoteMemory<T>` - this struct descripbes region of memory of the remote process and allows the local process to read it's content **T is only valid as a C-based type!**
 - `struct RawRemoteMemory` - this struct describes the region of memory of the remote process and allows the local process to read it's content as a contiguous array of UInt8
 - `struct Chunk` - this struct loads a memory at a given address and attempts to load the chunk header as a `BoundRemoteMemory` and then the content of the chunk as a `RawRemoteMemory`

Notice, that the `ProcessSession` conforms to the `Session` protocol which allows for `checkedLoad<T>(of:base:) throws -> BoundRemoteMemory<T>` and `checkedChunk(baseAddress:) throws -> Chunk` that provides safer API. Direct, unchecked, acces via `*RemoteMemory` and especially `Chunk` may lead to the crash of either traced or tracee.

```swift
let session = ProcessSession(pid: 1234)
session.loadThreads()
session.loadMap()
session.loadSymbols()
let glibcMallocExplorer = try GlibcMallocAnalyzer(session: session)
glibcMallocExplorer.analyze()
for heapItem in exploredHeap {
  switch heapItem.rebound {
    case .mallocState: // DO STUFF
    case .heapInfo: // DO STUFF
    case let .mallocChunk(chunkState): // DO STUFF
  }
}
```

Notice, that `heapItem` may not be a `malloc chunk` in all cases. It may be one of the book-keeping structs.

## Status
The `swift-inspect` requires followin capabilities:
 - to peek memory [DONE]
 - to search for runtime address of a symbol [DONE]
 - to search for possible symbol names for a given runtime address [DONE]
 - to determine maximal length of string assuming provided pointer points at one [DONE]
 - to iterate heap blocks [DONE (with exceptions, see subsection *Mmapped*)].

Ordered TODO list:
 - Assuming `main_arena` is known, traverse all reachable malloc chunks in all arenas. [DONE]
 - Tag chunks as freed [DONE]
   - Tag fastbin chunks [DONE]
   - Tag bin chunks [DONE]
   - Tag tcache chunks [DONE]
     - Read values from TLS [DONE]
     - Read `tcache` [DONE]
     - Move from UInt64 to UInt [DONE]
     - Refactor workflow with session to support threads and make it more fluent [DONE]
     - Traverse all threads and all `tcache`s with tests [DONE]
   - Introduce tests for malloc [DONE]
 - Introduce best-effort algorithm for locating mmapped chunks (based on whitepaper). [DEFERRED DONE (see subsection *Mmapped*)]
   - Traverse and tag `free` arenas [DONE (Not covered by tests yet)]   
 - Package in a tester program, that will determine offset of `main_arena` for given `Glibc` if debug symbols are not present. [ABANDONED]
 - Add checks for validated and supported version of Glibc [DONE]
 - Incorporate libMemtoolCore into `swift-inspect`
 - Release version 1.0 of `memtool` and open PR on `apple/swift`
 - Using metadata from `swift-inspect`, create initial "Memory Graph" algorithm on Linux
 - Introduce system for heuristics for analyzing ARC retain cycles.
 - Expand interactive mode so it prints `.dot` graphs of memory
 - Create Plug-In system and create Plugin for `Glib/GObject` ARC
 - Replace `Swift.Process` calls with other possibilites (using `elf.h`, `dwarf.h`)

List of reminders:
 - Add `_isPOD(_:)` check to `BoundRemoteMemory`

## Discussion

At the top level, there are two main approaches to keeping track of malloc chunks: introducing malloc/free hooks at the start of the process, or stopping the process at any time and analyzing memory belonging to it. This project attempts to implement the latter approach, because it fits more closely to the `swift-inspect` intended use.

The first approach may one day be used, but it should be always evaluated whether the project stays withing a reasonable bounds and whether similar/better results may not be reached using regular debugger.

The task of reaching all of the malloc chunks allocated by `glibc malloc` is constantly evolving. Chunks can be divided into several categories:
 
 - book-kept chunks
   - freed chunks
   - active chunks
 - mmapped chunks.

**Book-kept chunks** are chunks, that are reachable usign instances of `malloc_state` structs (also called *arena*s). Those chunks are guaranteed to be reached if the system provides debugging symbols for the `libc` and `ld`. However, book-kep chunks might be in either *freed* or *active* state.

**Freed chunks** are kept in the book-keeping `malloc_state` struct in either `fastbin` or `bin` lists. Tagging those chunks is as-easy as traversing the linked-lists. However, the chunks may also be kept in `tcache` which is a *thread local variable*. If `tcache` is not properly interpreted, the chunks may appear as active. Freed chunks might also be marged as free, if the **following** chunk has it's `isPreviousInUse` bit set.

**Active chunks** are all chunks, that were reached and are not known to be freed.

**Mmapped chunks** are chunks with large capacity (typically 128 ∗ 1024 bytes on x86 architectures)[1]. Those chunks are not book-kept by the `glibc`, but are directly requested from the OS. Reaching those chunks is non-trivial and may result in false-positives and false-negatives. It is unlikely, that any ARC object reaches this size, however. Therefore I feel comfortable deferring implementation of this feature at a later date.

## Resources, Literature, Links
*Notice, following literature is refered from the source code.*

[1] Linux Memory Forensics: Dissecting the User Space Process Heap *16th October 2017* [https://www.forensicfocus.com/articles/linux-memory-forensics-dissecting-the-user-space-process-heap/](https://www.forensicfocus.com/articles/linux-memory-forensics-dissecting-the-user-space-process-heap/)

[2] Malloc Internals, the Glibc wiki. *2022-08-09 17:51:50* [https://sourceware.org/glibc/wiki/MallocInternals](https://sourceware.org/glibc/wiki/MallocInternals)

[3] fasterthanlime: Thread-local storage *Apr 26, 2020* [https://fasterthanli.me/series/making-our-own-executable-packer/part-13#c-programs](https://fasterthanli.me/series/making-our-own-executable-packer/part-13#c-programs)

[4] The Glibc Source Code, generated *2022-Aug-24* [https://codebrowser.dev/glibc/glibc/](https://codebrowser.dev/glibc/glibc/)

[5] `man proc` Linux 5.13 release *2021-08-27* [https://www.kernel.org/doc/man-pages/](https://www.kernel.org/doc/man-pages/)

[6] `man objdump` binutils-2.39 *2022-12-01*

[7] `man elf` Linux 5.13 release *2021-03-22* [https://www.kernel.org/doc/man-pages/](https://www.kernel.org/doc/man-pages/)

[8] Chao-tic: A Deep dive into (implicit) Thread Local Storage *Dec 25, 2018* [Commit 046b398c85911835d89418c8d1b3098f740244a1](https://github.com/chao-tic/chao-tic.github.io/blob/master/_posts/2018-12-25-tls.markdown) [https://chao-tic.github.io/blog/2018/12/25/tls](https://chao-tic.github.io/blog/2018/12/25/tls)

## Note
I welcome any contribution at any stage of development.

I am aware, that there are tools and plugins for lldb and gdb (and other programs) that already acomplish similar results. I have tried many of them and none fits the purpose. I want this tool to be simple enought to be expanded by Swift developers. Having the requirement to understand (for example) lldb scripting, the scripting language itself and the issue itself seems to me like a big task. 
This tool is intended for Swift developers, it provides almost no value to other languages.


List of some abbrevations relevant to this topic:
 - TCB - Thread Control Block
 - PCB - Process Control Block
 - DTV - Dynamic Thread Vector
 - TLS - Thread Local Storage
 - GOT - Global Offset Table
 - DSO - Dynamic Shared Object
