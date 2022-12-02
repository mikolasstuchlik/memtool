import Foundation
import MemtoolCore
import Cutils

@main
enum memtool {
    static func main() throws {
        var context = Context(operations: operations, session: nil, shouldStop: false)

        while context.shouldStop == false {
            print("?", terminator: " ")
            while true {
                let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let line = line, !line.isEmpty {
                    context.resolve(input: line)
                    break
                }
            }
        }
    }
}

let operations: [Operation] = [
    attachOperation,
    detachOperation,
    statusOperation,
    mapOperation,
    symbolOperation,
    helpOperation,
    exitOperation,
    lookupOperation,
    peekOperation,
    addressOperation,
    analyzeOperation,
    chunkOperation,
    tcbOperation,
    wordOperation,
    tbssSymbolOperation,
    errnoGotOperation
]

let helpOperation = Operation(keyword: "help", help: "Shows available commands on stdout.") { input, ctx -> Bool in
    guard input == "help" else {
        return false
    }

    print("Available operations:")
    let max = ctx.operations.map(\.keyword.count).max() ?? 0

    for op in ctx.operations {
        let line = "  \(op.keyword)" 
            + String(repeating: " ", count: max - op.keyword.count)
            + " - "
            + op.help
        print(line) 
    }

    return true
}

let exitOperation = Operation(keyword: "exit", help: "Stops the execution") { input, ctx -> Bool in
    guard input == "exit" else {
        return false
    }

    ctx.shouldStop = true

    return true
}

let attachOperation = Operation(keyword: "attach", help: "[PID] attempts to attach to a process.") { input, ctx -> Bool in
    guard input.hasPrefix("attach"), let pid = Int32(input.trimmingPrefix("attach").trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return false
    }

    if ctx.session != nil {
        MemtoolCore.error("Error: Already attached to a process.")
        return true
    }

    ctx.session = Session(pid: pid)

    return true
}

let detachOperation = Operation(keyword: "detach", help: "Detached from attached process.") { input, ctx -> Bool in
    guard input == "detach" else {
        return false
    }

    ctx.session = nil

    return true
}

let statusOperation = Operation(keyword: "status", help: "[-m|-u|-l|-a] Prints current session to stdout. Use -m for map, -u for unloaded symbols and -l for loaded symbols, -a for glibc malloc analysis result.") { input, ctx -> Bool in
    guard input.hasPrefix("status") else {
        return false
    }
    let suffix = input.trimmingPrefix("status").trimmingCharacters(in: .whitespaces)
    guard suffix.isEmpty || suffix == "-m" || suffix == "-u" || suffix == "-l" || suffix == "-a" else {
        return false
    }

    guard let session = ctx.session else {
        print("idle")
        return true
    }

    switch suffix {
    case "":
        print(session.cliPrint)
    case "-m":
        print(session.map?.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
    case "-u":
        print(session.unloadedSymbols?.flatMap({ $1 }).map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
    case "-l":
        print(session.symbols?.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
    case "-a":
        print(ctx.glibcMallocExplorer?.exploredHeap.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
    default:
        return false
    }


    return true
}

let mapOperation = Operation(keyword: "map", help: "Parse /proc/pid/maps file.") { input, ctx -> Bool in
    guard input == "map" else {
        return false
    }

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    session.loadMap()

    return true
}

let symbolOperation = Operation(keyword: "symbol", help: "Requires maps. Loads all symbols for all object files in memory.") { input, ctx -> Bool in
    guard input == "symbol" else {
        return false
    }

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    guard session.executableFileBasePoints != nil else {
        MemtoolCore.error("Error: Need to load map first!")
        return true
    }

    session.loadSymbols()

    return true
}

let lookupOperation = Operation(keyword: "lookup", help: "[-e] \"[text]\" searches symbols matching text. Use -e if you want only exact matches.") { input, ctx -> Bool in
    guard input.hasPrefix("lookup") else {
        return false
    }
    let exact = input.trimmingPrefix("lookup").trimmingCharacters(in: .whitespaces).hasPrefix("-e")
    let text = input.trimmingPrefix("lookup").trimmingCharacters(in: .whitespaces).trimmingPrefix("-e").trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("\""), text.hasSuffix("\"") else {
        return false
    }
    let textToSearch = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    guard !textToSearch.isEmpty else {
        return false
    }

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    let unloadedPredicate: (UnloadedSymbolInfo) -> Bool = {
        exact == true
            ? $0.name == textToSearch
            : $0.name.contains(textToSearch) 
    }

    let loadedPredicate: (SymbolRegion) -> Bool = {
        exact == true
            ? $0.properties.name == textToSearch
            : $0.properties.name.contains(textToSearch)
    }

    print("Unloaded symbols: ")
    let unloaded: String? = session.unloadedSymbols?
        .flatMap({ $1 })
        .filter(unloadedPredicate)
        .map(\.cliPrint)
        .joined(separator: "\n")
    print(unloaded ?? "[not loaded]")

    print("Loaded symbols: ")
    let loaded: String? = session.symbols?
        .filter(loadedPredicate)
        .map(\.cliPrint)
        .joined(separator: "\n")
    print(loaded ?? "[not loaded]")

    return true
}

let peekableTypes: [Any.Type] = [malloc_state.self, malloc_chunk.self, heap_info.self, tcbhead_t.self, dtv_pointer.self, link_map.self, r_debug.self, link_map_private.self]
let peekOperation = Operation(keyword: "peek", help: "[typename] [hexa pointer] Peeks ans bind a memory to any of following types: \(peekableTypes.map { String(describing: $0) })") { input, ctx -> Bool in
    guard input.hasPrefix("peek") else {
        return false
    }
    let payload = input.trimmingPrefix("peek").trimmingCharacters(in: .whitespaces)
    let components = payload.components(separatedBy: " ")

    guard components.count == 2, let base = UInt64(components[1].trimmingPrefix("0x"), radix: 16) else {
        return false
    }

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    switch components[0] {
    case String(describing: malloc_state.self):
        print(BoundRemoteMemory<malloc_state>(pid: session.pid, load: base))
    
    case String(describing: malloc_chunk.self):
        print(BoundRemoteMemory<malloc_chunk>(pid: session.pid, load: base))
    
    case String(describing: heap_info.self):
        print(BoundRemoteMemory<heap_info>(pid: session.pid, load: base))

    case String(describing: tcbhead_t.self):
        print(BoundRemoteMemory<tcbhead_t>(pid: session.pid, load: base))

    case String(describing: dtv_pointer.self):
        print(BoundRemoteMemory<dtv_pointer>(pid: session.pid, load: base))

    case String(describing: link_map.self):
        print(BoundRemoteMemory<link_map>(pid: session.pid, load: base))

    case String(describing: r_debug.self):
        print(BoundRemoteMemory<r_debug>(pid: session.pid, load: base))
    
    case String(describing: link_map_private.self):
        print(BoundRemoteMemory<link_map_private>(pid: session.pid, load: base))
        
    default:
        return false
    }

    return true
}

let addressOperation = Operation(keyword: "addr", help: "[hexa pointer] Prints all entities that contain given address with offsets.") { input, ctx -> Bool in
    guard input.hasPrefix("addr") else {
        return false
    }
    let payload = input.trimmingPrefix("addr").trimmingCharacters(in: .whitespaces)

    guard let base = UInt64(payload.trimmingPrefix("0x"), radix: 16) else {
        return false
    }

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    print("Examining address " + base.cliPrint)
    
    print("Map:")
    let map: String? = session.map?
        .filter {
            $0.range.contains(base)
        }
        .map {
            let offset = base - $0.range.lowerBound
            return $0.range.lowerBound.cliPrint + " + " + offset.cliPrint + " \t" + $0.cliPrint
        }
        .joined(separator: "\n")
    print(map ?? "[not loaded]")

    print("Loaded symbols: ")
    let loaded: String? = session.symbols?
        .filter {
            $0.range.contains(base)
        }
        .map {
            let offset = base - $0.range.lowerBound
            return $0.range.lowerBound.cliPrint + " + " + offset.cliPrint + " \t" + $0.cliPrint
        }
        .joined(separator: "\n")
    print(loaded ?? "[not loaded]")

    print("Glibc malloc analysis: ")
    let analyzed = ctx.glibcMallocExplorer?.exploredHeap
        .filter {
            $0.range.contains(base)
        }
        .map {
            let offset = base - $0.range.lowerBound
            return $0.range.lowerBound.cliPrint + " + " + offset.cliPrint + " \t" + $0.cliPrint
        }
        .joined(separator: "\n")
    print(analyzed ?? "[not loaded]")


    return true
}

let analyzeOperation = Operation(keyword: "analyze", help: "Attempts to enumerate heap chubnks") { input, ctx -> Bool in
    guard input == "analyze" else {
        return false
    }
    
    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    do {
        ctx.glibcMallocExplorer = try GlibcMallocAnalyzer(session: session)
        ctx.glibcMallocExplorer?.analyze()
    } catch {
        MemtoolCore.error("Error: Glibc exlorer ended with error: \(error)")
    }

    return true
}

let chunkOperation = Operation(keyword: "chunk", help: "[hexa pointer] Attempts to load address as chunk and dumps it") { input, ctx -> Bool in
    guard input.hasPrefix("chunk") else {
        return false
    }
    let payload = input.trimmingPrefix("chunk").trimmingCharacters(in: .whitespaces)

    guard let base = UInt64(payload.trimmingPrefix("0x"), radix: 16) else {
        return false
    }

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    let chunk = Chunk(pid: session.pid, baseAddress: base)
    print(chunk.cliPrint)
    print("Content as ascii:\n" + chunk.content.asAsciiString)

    return true
}

let tcbOperation = Operation(keyword: "tcb", help: "Locates and prints Thread Control Block for traced thread") { input, ctx -> Bool in
    guard input == "tcb" else {
        return false
    }

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    guard session.executableFileBasePoints != nil else {
        MemtoolCore.error("Error: Need to load map first!")
        return true
    }

    // The pointer to the TCB should be in the FS register at all times (but we need to use FS_BASE in order to read FS)
    let fsBase = UInt64(UInt(bitPattern: swift_inspect_bridge__ptrace_peekuser(session.pid, FS_BASE)))

    // Check, that we're not reading garbage and accessing the record wonn't cause crash
    guard session.map?.contains(where: { $0.range.contains(fsBase) && $0.properties.flags.contains([.read, .write])}) == true else {
        MemtoolCore.error("FS_BASE not in readable space")
        return true
    }

    let head = BoundRemoteMemory<tcbhead_t>(pid: session.pid, load: fsBase)

    print("FS_BASE content: \(fsBase.cliPrint)")
    print(head)

    return true
}

let wordOperation = Operation(keyword: "word", help: "[decimal count] [hex pointer] [-a] Dumps given amount of 64bit words; Use [-a] if you want the result in ASCII (`count` will load be 8*count bit instad of 64*count bit). (Note: data are not adjusted for Big Endian.)") { input, ctx -> Bool in
    guard input.hasPrefix("word") else {
        return false
    }
    let payload = input.trimmingPrefix("word").trimmingCharacters(in: .whitespaces)
    let components = payload.components(separatedBy: " ")
    guard 
        components.count >= 2,
        let count = UInt64(components[0], radix: 10),
        let base = UInt64(components[1].trimmingPrefix("0x"), radix: 16),
        components.count == 2 || (components.count == 3 && components[2] == "-a")
    else {
        return false
    }

    let ascii = components.count == 3 && components[2] == "-a"
    let bitSize = UInt64( ascii ? MemoryLayout<CChar>.size : MemoryLayout<UInt64>.size)

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    guard let maps = session.map else {
        MemtoolCore.error("Error: Need to load map first!")
        return true
    }

    let range = base..<(base + count * bitSize)

    guard let map = maps.first(where: { $0.range.lowerBound <= range.lowerBound && $0.range.upperBound >= range.upperBound }) else {
        MemtoolCore.error("Error: Failed to map segment for this memory")
        return true
    }

    let offset = base - map.range.lowerBound
    print(map.range.lowerBound.cliPrint + " + " + offset.cliPrint + " \t" + map.cliPrint)
    
    if ascii {
        let memory = RawRemoteMemory(pid: session.pid, load: range)
        print(memory.asAsciiString)
    } else {
        var memory = ContiguousArray<UInt64>(repeating: 0, count: Int(count))
        memory.withUnsafeMutableBufferPointer { ptr in
            swift_inspect_bridge__ptrace_peekdata_initialize(session.pid, base, UnsafeMutableRawBufferPointer(ptr))
        }

        print(memory.map(\.cliPrint).joined(separator: " "))
    }

    return true
}

let tbssSymbolOperation = Operation(keyword: "tbss", help: "\"symbol name\" \"file name\" Attempts to locate tbss symbol in a file") { input, ctx -> Bool in
    guard input.hasPrefix("tbss") else {
        return false
    }
    let payload = input.trimmingPrefix("tbss").trimmingCharacters(in: .whitespaces)
    let components = payload.components(separatedBy: " ")
    guard 
        components.count == 2,
        components[0].hasPrefix("\""), components[0].hasSuffix("\""),
        components[1].hasPrefix("\""), components[1].hasSuffix("\"")
    else {
        return false
    }

    let symbol = components[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    let file = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    do {
        let result = try TbssSymbolGlibcLdHeuristic(session: session, fileName: file, tbssSymbolName: symbol)
        print(result)
        print("Symbol base \(result.loadedSymbolBase.cliPrint)")
    } catch {
        MemtoolCore.error("Error: Failed to locate tbss symbol: \(error)")
    }

    return true
}

let errnoGotOperation = Operation(keyword: "errnoGot", help: "\"glibc file name\" Attempts to parse `errno` location from disassembly in order to verify results of other heuristics.") { input, ctx -> Bool in
    guard input.hasPrefix("errnoGot") else {
        return false
    }
    let payload = input.trimmingPrefix("errnoGot").trimmingCharacters(in: .whitespaces)
    let components = payload.components(separatedBy: " ")
    guard 
        components.count == 1,
        components[0].hasPrefix("\""), components[0].hasSuffix("\"")
    else {
        return false
    }

    let path = components[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))

    guard let session = ctx.session else {
        MemtoolCore.error("Error: Not attached to a session!")
        return true
    }

    do {
        let result = try GlibcErrnoAsmHeuristic(session: session, glibcPath: path)
        print(result)
        print("Errno base \(result.errnoLocation.cliPrint)")
    } catch {
        MemtoolCore.error("Error: Failed to locate tbss symbol: \(error)")
    }

    return true
}
