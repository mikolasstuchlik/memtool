# memtool

Memtool (or rather libMemtoolCore) should provide babis for successful implementation of `swift-inspect` on Linux and beyond: the equivalent of "Memory Graph" on Linux. 

## Aims
The `swift-inspect` requires followin capabilities:
 - to peek memory [DONE]
 - to search for runtime address of a symbol [DONE]
 - to search for possible symbol names for a given runtime address [DONE]
 - to determine maximal length of string assuming provided pointer points at one [TODO: Glibc malloc]
 - to iterate heap blocks [TODO: Glibc malloc].

The most challenging part of this project is the ability "enumerate" malloc blocks. For this purpose it is assumed, that `Glibc` is the standard C library used. This project builds upon [whitepaper](
https://www.forensicfocus.com/articles/linux-memory-forensics-dissecting-the-user-space-process-heap/) which analyzed how the `Glibc` malloc works and how to read the content of dynamic memory.

Without introduction of malloc hooks, it can not be guaranteed, that all malloc blocks can be reached at all times. Especially mmapped blocks are the issue here.

Ordered TODO list:
 - Assuming `main_arena` is known, traverse all reachable malloc chunks in all arenas. [DONE]
 - Tag chunks as freed [IN PROGRESS]
   - Tag fastbin chunks [DONE]
   - Tag bin chunks [DONE]
   - Tag tcache chunks [IN PROGRESS]
     - Read values from TLS [DONE]
     - Read `tcache` [IN PROGRESS]
     - Traverse all threads and all `tcache`s
   - Introduce tests for malloc
 - Introduce best-effort algorithm for locating mmapped chunks (based on whitepaper).
 - Package in a tester program, that will determine offset of `main_arena` for given `Glibc` if debug symbols are not present.
 - Incorporate libMemtoolCore into `swift-inspect`
 - Release version 1.0 of `memtool` and open PR on `apple/swift`
 - Using metadata from `swift-inspect`, create initial "Memory Graph" algorithm on Linux
 - Introduce system for heuristics for analyzing ARC retain cycles.
 - Expand interactive mode so it prints `.dot` graphs of memory
 - Create Plug-In system and create Plugin for `Glib/GObject` ARC
 - Replace `Swift.Process` calls with other possibilites (using `elf.h`, `dwarf.h`)

## Limitations
At this time, only Glibc x86-64 platform is targeted. There are no plans to implement support for any other platform.

## Usage
Run using `swift run`. Note, that in order to attach to a running process you need to have a priviledge. Simplest way is to use `sudo`.

Interactive mode usage:
```
Available operations:
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
```

## Note
I welcome any contribution at any stage of development.

I am aware, that there are tools and plugins for lldb and gdb (and other programs) that already acomplish similar results. I have tried many of them and none fits the purpose. I want this tool to be simple enought to be expanded by Swift developers. Having the requirement to understand (for example) lldb scripting, the scripting language itself and the issue itself seems to me like a big task. 
This tool is intended for Swift developers, it provides almost no value to other languages.

### Example of usage
This example run show, how the main arena can be located at.
```
root@mikolas-pc:/home/mikolas/Developer/ptrace/memtool# .build/debug/memtool
? attach 73675
? status
=== Session [73675]
Map:
[not loaded]

Unloaded Symbols:
[not loaded]

Symbols:
[not loaded]
=== 
? map
? symbol
? lookup "main_arena"
Unloaded symbols: 
UnloadedSymbolInfo(name: main_arena, file: /usr/lib/x86_64-linux-gnu/libc.so.6, location: 00000000001f6c60, flags: l     O, segment: .data, size: 0000000000000898)
Loaded symbols: 
Region(range: 00007fcd7d1f6c60 ..< 00007fcd7d1f74f8, properties: LoadedSymbolInfo(name: main_arena, flags: l     O, segment: .data))
? peek malloc_state 00007fcd7d1f6c60
BoundRemoteMemory<malloc_state>(segment: Range(140520544234592..<140520544236792), buffer: __C.malloc_state(mutex: 0, flags: 0, have_fastchunks: 1, fastbinsY: (nil, nil, Optional(0x000055e8b94ea320), Optional(0x000055e8b94eabf0), nil, nil, nil, nil, nil, nil), top: Optional(0x000055e8b94eb280), last_remainder: nil, bins: (Optional(0x00007fcd7d1f6cc0), Optional(0x00007fcd7d1f6cc0), Optional(0x00007fcd7d1f6cd0), Optional(0x00007fcd7d1f6cd0), Optional(0x00007fcd7d1f6ce0), Optional(0x00007fcd7d1f6ce0), Optional(0x00007fcd7d1f6cf0), Optional(0x00007fcd7d1f6cf0), Optional(0x00007fcd7d1f6d00), Optional(0x00007fcd7d1f6d00), Optional(0x00007fcd7d1f6d10), Optional(0x00007fcd7d1f6d10), Optional(0x00007fcd7d1f6d20), Optional(0x00007fcd7d1f6d20), Optional(0x00007fcd7d1f6d30), Optional(0x00007fcd7d1f6d30), Optional(0x00007fcd7d1f6d40), Optional(0x00007fcd7d1f6d40), Optional(0x00007fcd7d1f6d50), Optional(0x00007fcd7d1f6d50), Optional(0x00007fcd7d1f6d60), Optional(0x00007fcd7d1f6d60), Optional(0x00007fcd7d1f6d70), Optional(0x00007fcd7d1f6d70), Optional(0x00007fcd7d1f6d80), Optional(0x00007fcd7d1f6d80), Optional(0x00007fcd7d1f6d90), Optional(0x00007fcd7d1f6d90), Optional(0x00007fcd7d1f6da0), Optional(0x00007fcd7d1f6da0), Optional(0x00007fcd7d1f6db0), Optional(0x00007fcd7d1f6db0), Optional(0x00007fcd7d1f6dc0), Optional(0x00007fcd7d1f6dc0), Optional(0x00007fcd7d1f6dd0), Optional(0x00007fcd7d1f6dd0), Optional(0x00007fcd7d1f6de0), Optional(0x00007fcd7d1f6de0), Optional(0x00007fcd7d1f6df0), Optional(0x00007fcd7d1f6df0), Optional(0x00007fcd7d1f6e00), Optional(0x00007fcd7d1f6e00), Optional(0x00007fcd7d1f6e10), Optional(0x00007fcd7d1f6e10), Optional(0x00007fcd7d1f6e20), Optional(0x00007fcd7d1f6e20), Optional(0x00007fcd7d1f6e30), Optional(0x00007fcd7d1f6e30), Optional(0x00007fcd7d1f6e40), Optional(0x00007fcd7d1f6e40), Optional(0x00007fcd7d1f6e50), Optional(0x00007fcd7d1f6e50), Optional(0x00007fcd7d1f6e60), Optional(0x00007fcd7d1f6e60), Optional(0x00007fcd7d1f6e70), Optional(0x00007fcd7d1f6e70), Optional(0x00007fcd7d1f6e80), Optional(0x00007fcd7d1f6e80), Optional(0x00007fcd7d1f6e90), Optional(0x00007fcd7d1f6e90), Optional(0x00007fcd7d1f6ea0), Optional(0x00007fcd7d1f6ea0), Optional(0x00007fcd7d1f6eb0), Optional(0x00007fcd7d1f6eb0), Optional(0x00007fcd7d1f6ec0), Optional(0x00007fcd7d1f6ec0), Optional(0x00007fcd7d1f6ed0), Optional(0x00007fcd7d1f6ed0), Optional(0x00007fcd7d1f6ee0), Optional(0x00007fcd7d1f6ee0), Optional(0x00007fcd7d1f6ef0), Optional(0x00007fcd7d1f6ef0), Optional(0x00007fcd7d1f6f00), Optional(0x00007fcd7d1f6f00), Optional(0x00007fcd7d1f6f10), Optional(0x00007fcd7d1f6f10), Optional(0x00007fcd7d1f6f20), Optional(0x00007fcd7d1f6f20), Optional(0x00007fcd7d1f6f30), Optional(0x00007fcd7d1f6f30), Optional(0x00007fcd7d1f6f40), Optional(0x00007fcd7d1f6f40), Optional(0x00007fcd7d1f6f50), Optional(0x00007fcd7d1f6f50), Optional(0x00007fcd7d1f6f60), Optional(0x00007fcd7d1f6f60), Optional(0x00007fcd7d1f6f70), Optional(0x00007fcd7d1f6f70), Optional(0x00007fcd7d1f6f80), Optional(0x00007fcd7d1f6f80), Optional(0x00007fcd7d1f6f90), Optional(0x00007fcd7d1f6f90), Optional(0x00007fcd7d1f6fa0), Optional(0x00007fcd7d1f6fa0), Optional(0x00007fcd7d1f6fb0), Optional(0x00007fcd7d1f6fb0), Optional(0x00007fcd7d1f6fc0), Optional(0x00007fcd7d1f6fc0), Optional(0x00007fcd7d1f6fd0), Optional(0x00007fcd7d1f6fd0), Optional(0x00007fcd7d1f6fe0), Optional(0x00007fcd7d1f6fe0), Optional(0x00007fcd7d1f6ff0), Optional(0x00007fcd7d1f6ff0), Optional(0x00007fcd7d1f7000), Optional(0x00007fcd7d1f7000), Optional(0x00007fcd7d1f7010), Optional(0x00007fcd7d1f7010), Optional(0x00007fcd7d1f7020), Optional(0x00007fcd7d1f7020), Optional(0x00007fcd7d1f7030), Optional(0x00007fcd7d1f7030), Optional(0x00007fcd7d1f7040), Optional(0x00007fcd7d1f7040), Optional(0x00007fcd7d1f7050), Optional(0x00007fcd7d1f7050), Optional(0x00007fcd7d1f7060), Optional(0x00007fcd7d1f7060), Optional(0x00007fcd7d1f7070), Optional(0x00007fcd7d1f7070), Optional(0x00007fcd7d1f7080), Optional(0x00007fcd7d1f7080), Optional(0x00007fcd7d1f7090), Optional(0x00007fcd7d1f7090), Optional(0x00007fcd7d1f70a0), Optional(0x00007fcd7d1f70a0), Optional(0x00007fcd7d1f70b0), Optional(0x00007fcd7d1f70b0), Optional(0x00007fcd7d1f70c0), Optional(0x00007fcd7d1f70c0), Optional(0x00007fcd7d1f70d0), Optional(0x00007fcd7d1f70d0), Optional(0x00007fcd7d1f70e0), Optional(0x00007fcd7d1f70e0), Optional(0x00007fcd7d1f70f0), Optional(0x00007fcd7d1f70f0), Optional(0x00007fcd7d1f7100), Optional(0x00007fcd7d1f7100), Optional(0x00007fcd7d1f7110), Optional(0x00007fcd7d1f7110), Optional(0x00007fcd7d1f7120), Optional(0x00007fcd7d1f7120), Optional(0x00007fcd7d1f7130), Optional(0x00007fcd7d1f7130), Optional(0x00007fcd7d1f7140), Optional(0x00007fcd7d1f7140), Optional(0x00007fcd7d1f7150), Optional(0x00007fcd7d1f7150), Optional(0x00007fcd7d1f7160), Optional(0x00007fcd7d1f7160), Optional(0x00007fcd7d1f7170), Optional(0x00007fcd7d1f7170), Optional(0x00007fcd7d1f7180), Optional(0x00007fcd7d1f7180), Optional(0x00007fcd7d1f7190), Optional(0x00007fcd7d1f7190), Optional(0x00007fcd7d1f71a0), Optional(0x00007fcd7d1f71a0), Optional(0x00007fcd7d1f71b0), Optional(0x00007fcd7d1f71b0), Optional(0x00007fcd7d1f71c0), Optional(0x00007fcd7d1f71c0), Optional(0x00007fcd7d1f71d0), Optional(0x00007fcd7d1f71d0), Optional(0x00007fcd7d1f71e0), Optional(0x00007fcd7d1f71e0), Optional(0x00007fcd7d1f71f0), Optional(0x00007fcd7d1f71f0), Optional(0x00007fcd7d1f7200), Optional(0x00007fcd7d1f7200), Optional(0x00007fcd7d1f7210), Optional(0x00007fcd7d1f7210), Optional(0x00007fcd7d1f7220), Optional(0x00007fcd7d1f7220), Optional(0x00007fcd7d1f7230), Optional(0x00007fcd7d1f7230), Optional(0x00007fcd7d1f7240), Optional(0x00007fcd7d1f7240), Optional(0x00007fcd7d1f7250), Optional(0x00007fcd7d1f7250), Optional(0x00007fcd7d1f7260), Optional(0x00007fcd7d1f7260), Optional(0x00007fcd7d1f7270), Optional(0x00007fcd7d1f7270), Optional(0x00007fcd7d1f7280), Optional(0x00007fcd7d1f7280), Optional(0x00007fcd7d1f7290), Optional(0x00007fcd7d1f7290), Optional(0x00007fcd7d1f72a0), Optional(0x00007fcd7d1f72a0), Optional(0x00007fcd7d1f72b0), Optional(0x00007fcd7d1f72b0), Optional(0x00007fcd7d1f72c0), Optional(0x00007fcd7d1f72c0), Optional(0x00007fcd7d1f72d0), Optional(0x00007fcd7d1f72d0), Optional(0x00007fcd7d1f72e0), Optional(0x00007fcd7d1f72e0), Optional(0x00007fcd7d1f72f0), Optional(0x00007fcd7d1f72f0), Optional(0x00007fcd7d1f7300), Optional(0x00007fcd7d1f7300), Optional(0x00007fcd7d1f7310), Optional(0x00007fcd7d1f7310), Optional(0x00007fcd7d1f7320), Optional(0x00007fcd7d1f7320), Optional(0x00007fcd7d1f7330), Optional(0x00007fcd7d1f7330), Optional(0x00007fcd7d1f7340), Optional(0x00007fcd7d1f7340), Optional(0x00007fcd7d1f7350), Optional(0x00007fcd7d1f7350), Optional(0x00007fcd7d1f7360), Optional(0x00007fcd7d1f7360), Optional(0x00007fcd7d1f7370), Optional(0x00007fcd7d1f7370), Optional(0x00007fcd7d1f7380), Optional(0x00007fcd7d1f7380), Optional(0x00007fcd7d1f7390), Optional(0x00007fcd7d1f7390), Optional(0x00007fcd7d1f73a0), Optional(0x00007fcd7d1f73a0), Optional(0x00007fcd7d1f73b0), Optional(0x00007fcd7d1f73b0), Optional(0x00007fcd7d1f73c0), Optional(0x00007fcd7d1f73c0), Optional(0x00007fcd7d1f73d0), Optional(0x00007fcd7d1f73d0), Optional(0x00007fcd7d1f73e0), Optional(0x00007fcd7d1f73e0), Optional(0x00007fcd7d1f73f0), Optional(0x00007fcd7d1f73f0), Optional(0x00007fcd7d1f7400), Optional(0x00007fcd7d1f7400), Optional(0x00007fcd7d1f7410), Optional(0x00007fcd7d1f7410), Optional(0x00007fcd7d1f7420), Optional(0x00007fcd7d1f7420), Optional(0x00007fcd7d1f7430), Optional(0x00007fcd7d1f7430), Optional(0x00007fcd7d1f7440), Optional(0x00007fcd7d1f7440), Optional(0x00007fcd7d1f7450), Optional(0x00007fcd7d1f7450), Optional(0x00007fcd7d1f7460), Optional(0x00007fcd7d1f7460), Optional(0x00007fcd7d1f7470), Optional(0x00007fcd7d1f7470), Optional(0x00007fcd7d1f7480), Optional(0x00007fcd7d1f7480), Optional(0x00007fcd7d1f7490), Optional(0x00007fcd7d1f7490), Optional(0x00007fcd7d1f74a0), Optional(0x00007fcd7d1f74a0)), binmap: (0, 0, 0, 0), next: Optional(0x00007fcd74000030), next_free: nil, attached_threads: 1, system_mem: 135168, max_system_mem: 135168))
? 
```
