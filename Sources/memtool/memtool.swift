import Foundation
import CoreMemtool
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
    peekOperation
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
        print("Error: Already attached to a process.")
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

let statusOperation = Operation(keyword: "status", help: "[-m|-u|-l] Prints current session to stdout. Use -m for map, -u for unloaded symbols and -l for loaded symbols.") { input, ctx -> Bool in
    guard input.hasPrefix("status") else {
        return false
    }
    let suffix = input.trimmingPrefix("status").trimmingCharacters(in: .whitespaces)
    guard suffix.isEmpty || suffix == "-m" || suffix == "-u" || suffix == "-l" else {
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
        print("Error: Not attached to a session!")
        return true
    }

    session.map = Map.getMap(for: session.pid)
    session.executableFileBasePoints = [:]
    for map in session.map ?? [] {
        guard case let .file(filename) = map.properties.pathname else {
            continue
        }

        let current = session.executableFileBasePoints?[filename]
        session.executableFileBasePoints?[filename] = current.flatMap { min($0, map.range.lowerBound) } ?? map.range.lowerBound
    }

    // Remove files that do not have executable page in memory
    session.executableFileBasePoints = session.executableFileBasePoints?.filter { key, _ -> Bool in
        for map in session.map ?? [] {
            if case let .file(filename) = map.properties.pathname, filename == key, map.properties.flags.contains(.execute) {
                return true
            }
        }
        return false
    }

    return true
}

let sectionsToResolve: Set<KnownSymbolSection> = [.bss, .data, .data1, .rodata, .rodata1, .text]
let symbolOperation = Operation(keyword: "symbol", help: "Requires maps. Loads all symbols for all object files in memory.") { input, ctx -> Bool in
    guard input == "symbol" else {
        return false
    }

    guard let session = ctx.session else {
        print("Error: Not attached to a session!")
        return true
    }

    guard let maps = session.executableFileBasePoints else {
        print("Error: Need to load map first!")
        return true
    }

    let files = Array(maps.keys)

    session.unloadedSymbols = [:]
    for file in files {
        let symbols = Symbolication.loadSymbols(for: file)
        // Remove duplicities
        let hashedSymbols = Array(Set(symbols))
        session.unloadedSymbols?[file] = hashedSymbols
    }

    session.symbols = []
    session.symbols?.reserveCapacity( session.unloadedSymbols?.values.map(\.count).reduce(0, +) ?? 0)
    for (file, unloaded) in session.unloadedSymbols ?? [:] {
        for symbol in unloaded {
            guard 
                case let .known(known) = symbol.segment, 
                sectionsToResolve.contains(known) 
            else {
                continue
            }
            SymbolRegion(unloadedSymbol: symbol, executableFileBasePoints: maps).flatMap { session.symbols?.append($0) }
        }
    }

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
        print("Error: Not attached to a session!")
        return true
    }

    if exact {
        print("Unloaded symbols: ")
        print(session.unloadedSymbols?.flatMap({ $1 }).filter { $0.name == textToSearch }.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
        print("Loaded symbols: ")
        print(session.symbols?.filter { $0.properties.name == textToSearch }.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
    } else {
        print("Unloaded symbols: ")
        print(session.unloadedSymbols?.flatMap({ $1 }).filter { $0.name.contains(textToSearch) }.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
        print("Loaded symbols: ")
        print(session.symbols?.filter { $0.properties.name.contains(textToSearch) }.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
    }

    return true
}

let peekableTypes: [Any.Type] = [malloc_state.self, malloc_chunk.self, heap_info.self]
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
        print("Error: Not attached to a session!")
        return true
    }

    switch components[0] {
    case String(describing: malloc_state.self):
        print(BoundRemoteMemory<malloc_state>(pid: session.pid, load: base))
    
    case String(describing: malloc_chunk.self):
        print(BoundRemoteMemory<malloc_chunk>(pid: session.pid, load: base))
    
    case String(describing: heap_info.self):
        print(BoundRemoteMemory<heap_info>(pid: session.pid, load: base))
    
    default:
        return false
    }

    return true
}