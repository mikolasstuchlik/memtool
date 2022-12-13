import Foundation
import Cutils
import Glibc

/// MemoryTag contains metadata of the remote memory collected during
/// various analysis steps. It is also used to determine, whether a load
/// of a remote memory is known to be problematic.
public struct MemoryTag {
    /// Type, that has been previously bound to the remote memory in the 
    /// tracing process.
    var type: Any.Type
}

/// Session is a reference-counted object, that manages (in a RAII way) the attachment
/// to a remote process. It provides storage for analysis metadata and API for safer
/// reading of the remote process. It represents a working unit for `ptrace`.
public protocol Session: AnyObject {
    /// The PID of the overall process.
    var pid: Int32 { get }
    /// The PID or TID of the session that is used to issue requests to `ptracer`.
    var ptraceId: Int32 { get }

    /// Map of the remote process memory containing all adresses that are valid for
    /// the LAP of the remote process, and metadata associated with those adresses.
    var map: [MapRegion]? { get set }

    /// Dictionary, that contains base address of the LAP of the remote process, to 
    /// which an executable file was loaded.
    var executableFileBasePoints: [String: UInt]? { get set }

    /// Symbols, that were obtained from ELF and DWARF for given executable file.
    var unloadedSymbols: [String: [UnloadedSymbolInfo]]? { get set }

    /// Symbols, that represent a region in the traced process memory.
    var symbols: [SymbolRegion]? { set get }

    /// Dictionary, that stores additional information for a given address of the 
    /// remote process memory. These records are created during analysis.
    var tag: [UInt: MemoryTag] { get set }
}

public enum SessionError: Error {
    case loadOutsideOfKnownMemory
    case loadingPreviouslyLoadedTypeMismatch
    case sizeAdditionOverflow
}

public extension Session {
    /// Use this method to load a BoundRemoteMemory in a safer manner. Data stored in the 
    /// `Session` object are consulted in order to determine, whether the load might be safe.
    /// - Parameters:
    ///   - type: Type bound to the data.
    ///   - base: Base of the data in the remote process. 
    ///   - skipMismatchTypeCheck: Set to true, in order to skip the checks, whether the type was previously bound to a different type.
    func checkedLoad<T>(of type: T.Type, base: UInt, skipMismatchTypeCheck: Bool = false) throws -> BoundRemoteMemory<T> {
        let range = base..<(base + UInt(MemoryLayout<T>.size))

        guard map?.contains(where: { $0.range.contains(range) }) == true else {
            throw SessionError.loadOutsideOfKnownMemory
        }

        if !skipMismatchTypeCheck {
            let existingTag = tag[base].flatMap({ $0.type == type })
            guard existingTag == nil || existingTag == true else {
                error("Error: Checked load of type \(type) at " + String(format: "%016lx", base) + " failed. Previously loaded a mismatching type \(tag[base]!.type).")
                throw SessionError.loadingPreviouslyLoadedTypeMismatch
            }
            tag[base] = MemoryTag(type: type)
        }

        return BoundRemoteMemory(pid: pid, load: base)
    }

    /// Use this method to load a Chunk in a safer manner. Data stored in the `Session` object 
    /// are consulted in order to determine, whether the load might be safe.
    /// - Parameter baseAddress: Base of the data in the remote process. 
    func checkedChunk(baseAddress: UInt) throws -> Chunk {
        let header = try checkedLoad(of: malloc_chunk.self, base: baseAddress).buffer
        let endAddress = (baseAddress + Chunk.chunkContentEndOffset).addingReportingOverflow(header.size)

        guard !endAddress.overflow else { 
            throw SessionError.sizeAdditionOverflow
        }

        let chunkContent = (baseAddress + Chunk.chunkContentOffset)..<endAddress.partialValue

        guard map?.contains(where: { $0.range.contains(chunkContent) }) == true else {
            throw SessionError.loadOutsideOfKnownMemory
        }

        return Chunk(header: header, content: RawRemoteMemory(pid: pid, load: chunkContent)
        )
    }
}

public final class ProcessSession: Session {
    public var ptraceId: Int32 { pid }

    public let pid: Int32

    public var map: [MapRegion]?
    public var executableFileBasePoints: [String: UInt]?
    public var unloadedSymbols: [String: [UnloadedSymbolInfo]]?
    public var symbols: [SymbolRegion]?
    public var threadSessions: [ThreadSession] = []
    public var tag: [UInt: MemoryTag] = [:]

    public init(pid: Int32) {
        swift_inspect_bridge__ptrace_attach(pid)
        self.pid = pid
    }

    deinit {
        swift_inspect_bridge__ptrace_syscall(pid)
    }

    /// Loads map of LAP of the remote process. Fills `map` and `executableFileBasePoints`.
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

    /// Symbol types, that are resolved against the base address of their file and their location.
    public static let sectionsToResolve: Set<KnownSymbolSection> = [.bss, .data, .data1, .rodata, .rodata1, .text]

    /// Loads symbols for executable files and computes their location in the LAP of the 
    /// remote process. Fills `unloadedSymbols` and `symbols`.
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

    /// Loads the TIDs of threads associated with this process and creates ThreadSession
    /// instances.
    public func loadThreads() {
        let threads = ThreadLoader(pid: pid)
        threadSessions = threads.threads.map { ThreadSession(tid: $0, owner: self) }
    }
}

public final class ThreadSession: Session {
    public var pid: Int32 { owner.pid }
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

    public var tag: [UInt: MemoryTag] {
        get {
            owner.tag
        }
        set {
            owner.tag = newValue
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
