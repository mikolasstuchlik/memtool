import Foundation
import Cutils
import Glibc

public protocol Session {
    var ptraceId: Int32 { get }

    var map: [MapRegion]? { get set }
    var executableFileBasePoints: [String: UInt]? { get set }
    var unloadedSymbols: [String: [UnloadedSymbolInfo]]? { get set }
    var symbols: [SymbolRegion]? { set get }
}

public final class ProcessSession: Session {
    public var ptraceId: Int32 { pid }

    public let pid: Int32

    public var map: [MapRegion]?
    public var executableFileBasePoints: [String: UInt]?
    public var unloadedSymbols: [String: [UnloadedSymbolInfo]]?
    public var symbols: [SymbolRegion]?
    public var threadSessions: [ThreadSession] = []

    public init(pid: Int32) {
        swift_inspect_bridge__ptrace_attach(pid)
        self.pid = pid
    }

    deinit {
        swift_inspect_bridge__ptrace_syscall(pid)
    }

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
                    ProcessSession.sectionsToResolve.contains(known) 
                else {
                    continue
                }
                SymbolRegion(unloadedSymbol: symbol, executableFileBasePoints: maps).flatMap { symbols?.append($0) }
            }
        }
    }

    public func loadThreads() {
        let threads = ThreadLoader(pid: pid)
        threadSessions = threads.threads.map { ThreadSession(tid: $0, owner: self) }
    }
}

public final class ThreadSession: Session {
    public var ptraceId: Int32 { tid }
    public let tid: Int32
    public unowned let owner: ProcessSession

    public var map: [MapRegion]? {
        get {
            owner.map
        }
        set {
            owner.map = newValue
        }
    }

    public var executableFileBasePoints: [String : UInt]? {
        get {
            owner.executableFileBasePoints
        }
        set {
            owner.executableFileBasePoints = newValue
        }
    }

    public var unloadedSymbols: [String : [UnloadedSymbolInfo]]? {
        get {
            owner.unloadedSymbols
        }
        set {
            owner.unloadedSymbols = newValue
        }
    }

    public var symbols: [SymbolRegion]? {
        get {
            owner.symbols
        }
        set {
            owner.symbols = newValue
        }
    }

    public init(tid: Int32, owner: ProcessSession) {
        swift_inspect_bridge__ptrace_attach(tid)
        self.owner = owner
        self.tid = tid
    }

    deinit {
        swift_inspect_bridge__ptrace_syscall(tid)
    }
}
