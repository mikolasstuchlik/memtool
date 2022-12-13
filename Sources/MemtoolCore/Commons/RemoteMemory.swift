import Foundation

/// RawRemoteMemory is a container for raw bytes stored in the memory of the
/// remote process, copied to the memory of tracing process.
public struct RawRemoteMemory {
    /// The region of the remote process memory
    public let segment: MemoryRange
    /// Buffer containing bytes copied from the remote process
    public let buffer: ContiguousArray<UInt8>

    /// This initializer performs **unchecked and unsafe** load from the memory of the remote process
    /// - Parameters:
    ///   - pid: The PID of the process attached by the tracing process 
    ///   - segment: Range of the memory that should be copied
    public init(pid: Int32, load segment: MemoryRange) {
        self.segment = segment
        var buffer = ContiguousArray<UInt8>.init(repeating: 0, count: segment.count)
        swift_inspect_bridge__ptrace_peekdata_initialize(pid, segment.startIndex, &buffer)
        self.buffer = buffer
    }
}

extension RawRemoteMemory {
    /// Prints bytes copied from remote process as ASCII string.
    public var asAsciiString: String {
        buffer.reduce(into: "") { result, current in
            result += Unicode.Scalar(current).escaped(asASCII: true)
        }
    }
}

/// BoundRemoteMemory is a container for data stored in the memory of the
/// remote process, that are copied and types to a type in the tracing process.
/// 
/// - Warning: The type T should be C layouted and **MUST NOT** have any Swift runtime
/// dependencies! The Swift runtime of the tracing process will try to perform 
/// the runtime operations on invalid data.
public struct BoundRemoteMemory<T> {
    /// The region of the remote process memory
    public let segment: MemoryRange
    /// Buffer containing bytes copied from the remote process bound to a type
    public let buffer: T

    /// This initializer performs **unchecked and unsafe** load from the memory of the remote process.
    /// - Parameters:
    ///   - pid: The PID of the process attached by the tracing process
    ///   - baseAddress: Base address of the memory (length is deduced from the size of the type T)
    ///   - initialValue: Initial value for the buffer in the local process.
    public init(pid: Int32, load baseAddress: UInt, initialValue: T) {
        self.segment = baseAddress..<(baseAddress + UInt(MemoryLayout<T>.size))
        var buffer = initialValue
        swift_inspect_bridge__ptrace_peekdata_initialize(pid, baseAddress, &buffer)
        self.buffer = buffer
    }

    /// This initializer performs **unchecked and unsafe** load from the memory of the remote process.
    /// This initializer first loads raw bytes from the remote proces and unsafely binds them to the 
    /// type requested in the tracing process.
    /// - Parameters:
    ///   - pid: The PID of the process attached by the tracing process
    ///   - baseAddress: Base address of the memory (length is deduced from the size of the type T)
    public init(pid: Int32, load baseAddress: UInt) {
        let segment = baseAddress..<(baseAddress + UInt(MemoryLayout<T>.size))
        let rawRemote = RawRemoteMemory(pid: pid, load: segment)
        self.init(bind: rawRemote)!
    }

    /// Unsafely binds the raw data to the type T. This initializer may fail if some expectations 
    /// are not fulfiled, **but is unsafe.**
    /// - Parameter rawMemory: 
    public init?(bind rawMemory: RawRemoteMemory) {
        guard rawMemory.buffer.count == MemoryLayout<T>.size else {
            error("Error: Attempted to bind \(rawMemory) to differently sized type \(String(describing: T.self))")
            error("Error: \(rawMemory.buffer.count) =/= \(MemoryLayout<T>.size)")
            return nil
        }

        self.segment = rawMemory.segment
        self.buffer = rawMemory.buffer.withUnsafeBufferPointer { ptr in
            return ptr.withMemoryRebound(to: T.self) {
                return $0.first!
            }    
        }
    }
    
    /// Unsafely binds the raw data to the type T. This initializer may fail if some expectations 
    /// are not fulfiled, **but is unsafe.** Allows for binding of raw data, that are larger than
    /// expected size.
    /// - Parameter rawMemory: 
    public init?(bindFromLarger rawMemory: RawRemoteMemory) {
        guard rawMemory.buffer.count >= MemoryLayout<T>.size else {
            error("Error: Attempted to bind \(rawMemory) to differently larger type \(String(describing: T.self))")
            error("Error: \(rawMemory.buffer.count) < \(MemoryLayout<T>.size)")
            return nil
        }

        self.segment = rawMemory.segment
        self.buffer = withUnsafeBytes(of: rawMemory.buffer) { ptr in
            let rebound = ptr.assumingMemoryBound(to: T.self)
            return rebound.first!    
        }
    }
}