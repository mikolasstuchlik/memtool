import Foundation
import Cutils
import Glibc


public final class Session {
    public let pid: Int32

    public var map: [MapRegion]?
    public var executableFileBasePoints: [String: UInt64]?
    public var unloadedSymbols: [String: [UnloadedSymbolInfo]]?
    public var symbols: [SymbolRegion]?

    public init(pid: Int32) {
        swift_inspect_bridge__ptrace_attach(pid)
        self.pid = pid
    }

    deinit {
        swift_inspect_bridge__ptrace_syscall(pid)
    }
}

extension Session {
    public func loadMap() {
        map = Map.getMap(for: pid)
        executableFileBasePoints = [:]
        for map in map ?? [] {
            guard case let .file(filename) = map.properties.pathname else {
                continue
            }

            let current = executableFileBasePoints?[filename]
            executableFileBasePoints?[filename] = current.flatMap { min($0, map.range.lowerBound) } ?? map.range.lowerBound
        }

        // Remove files that do not have executable page in memory
        executableFileBasePoints = executableFileBasePoints?.filter { key, _ -> Bool in
            for map in map ?? [] {
                if case let .file(filename) = map.properties.pathname, filename == key, map.properties.flags.contains(.execute) {
                    return true
                }
            }
            return false
        }
    }
}

extension Session {
    public static let sectionsToResolve: Set<KnownSymbolSection> = [.bss, .data, .data1, .rodata, .rodata1, .text]
    public func loadSymbols() {
        guard let maps = executableFileBasePoints else { return }
        let files = Array(maps.keys)

        unloadedSymbols = [:]
        for file in files {
            let symbols = Symbolication.loadSymbols(for: file)
            // Remove duplicities
            let hashedSymbols = Array(Set(symbols))
            unloadedSymbols?[file] = hashedSymbols
        }

        symbols = []
        symbols?.reserveCapacity( unloadedSymbols?.values.map(\.count).reduce(0, +) ?? 0)
        for (_, unloaded) in unloadedSymbols ?? [:] {
            for symbol in unloaded {
                guard 
                    case let .known(known) = symbol.segment, 
                    Session.sectionsToResolve.contains(known) 
                else {
                    continue
                }
                SymbolRegion(unloadedSymbol: symbol, executableFileBasePoints: maps).flatMap { symbols?.append($0) }
            }
        }

    }
}