import Foundation
import CoreMemtool

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
    exitOperation
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

let statusOperation = Operation(keyword: "status", help: "Prints current session to stdout.") { input, ctx -> Bool in
    guard input == "status" else {
        return false
    }

    if let session = ctx.session {
        print(session.cliPrint)
    } else {
        print("idle")
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

    return true
}

let symbolOperation = Operation(keyword: "symbol", help: "Requires maps. Loads all symbols for all object files in memory.") { input, ctx -> Bool in
    guard input == "symbol" else {
        return false
    }

    guard let session = ctx.session else {
        print("Error: Not attached to a session!")
        return true
    }

    guard let maps = session.map else {
        print("Error: Need to load map first!")
        return true
    }

    print("Loading symbols.")
    let potentialFiles = Set(maps.map(\.properties.pathname)).filter { !$0.isEmpty }
    print("Maps read.")
    let suffixSo = potentialFiles.filter {
        guard let last = $0.components(separatedBy: "/").last else {
            return false
        }

        return last.contains(".so.") || last.hasSuffix(".so")
    }
    print("Searching symbols for files: \(suffixSo)")

    var unloaded = [UnloadedSymbolInfo]()
    for file in suffixSo {
        print("Loading symbols for file \(file) ...", terminator: " ")
        let sym = Symbolication.loadSymbols(for: file)
        print("\(sym.count) symbols loaded.")
        unloaded.append(contentsOf: sym)
    }

    session.unloadedSymbols = unloaded

    print("Applyiong symbols to regions...", terminator: " ")
    session.symbols = unloaded.compactMap { symbol in
        SymbolRegion(unloadedSymbol: symbol, map: maps)
    }
    print("[done]")

    return true
}
