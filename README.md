# memtool

Memtool (or rather libCoreMemtool) should provide babis for successful implementation of `swift-inspect` on Linux and beyond: the equivalent of "Memory Graph" on Linux. 

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
 - Assuming `main_arena` is known, traverse all reachable malloc chunks in all arenas.
 - Introduce best-effort algorithm for locating mmapped chunks (based on whitepaper).
 - Package in a tester program, that will determine offset of `main_arena` for given `Glibc` if debug symbols are not present.
 - Incorporate libCoreMemtool into `swift-inspect`
 - Release version 1.0 of `memtool` and open PR on `apple/swift`
 - Using metadata from `swift-inspect`, create initial "Memory Graph" algorithm on Linux
 - Introduce system for heuristics for analyzing ARC retain cycles.
 - Expand interactive mode so it prints `.dot` graphs of memory
 - Create Plug-In system and create Plugin for `Glib/GObject` ARC

## Limitations
At this time, only Glibc x86-64 platform is targeted. There are no plans to implement support for any other platform.

## Usage
Run using `swift run`. Note, that in order to attach to a running process you need to have a priviledge. Simplest way is to use `sudo`.

Interactive mode usage:
```
Available operations:
  attach - [PID] attempts to attach to a process.
  detach - Detached from attached process.
  status - [-m|-u|-l] Prints current session to stdout. Use -m for map, -u for unloaded symbols and -l for loaded symbols.
  map    - Parse /proc/pid/maps file.
  symbol - Requires maps. Loads all symbols for all object files in memory.
  help   - Shows available commands on stdout.
  exit   - Stops the execution
  lookup - [-e] "[text]" searches symbols matching text. Use -e if you want only exact matches.
  peek   - [typename] [hexa pointer] Peeks ans bind a memory to any of following types: ["malloc_state", "malloc_chunk", "_heap_info"]
  addr   - [hexa pointer] Prints all entities that contain given address with offsets.
```

## Note
I welcome any contribution at any stage of development.

I am aware, that there are tools and plugins for lldb and gdb (and other programs) that already acomplish similar results. I have tried many of them and none fits the purpose. I want this tool to be simple enought to be expanded by Swift developers. Having the requirement to understand (for example) lldb scripting, the scripting language itself and the issue itself seems to me like a big task. 
This tool is intended for Swift developers, it provides almost no value to other languages.
