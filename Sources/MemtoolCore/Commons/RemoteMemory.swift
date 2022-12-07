import Foundation

public struct RawRemoteMemory {
    public let segment: MemoryRange
    public let buffer: ContiguousArray<UInt8>

    public init(pid: Int32, load segment: MemoryRange) {
        self.segment = segment
        var buffer = ContiguousArray<UInt8>.init(repeating: 0, count: segment.count)
        swift_inspect_bridge__ptrace_peekdata_initialize(pid, segment.startIndex, &buffer)
        self.buffer = buffer
    }
}

extension RawRemoteMemory {
    public var asAsciiString: String {
        buffer.reduce(into: "") { result, current in
            result += Unicode.Scalar(current).escaped(asASCII: true)
        }
    }
}

/// - Warning: The buffer has to be C layouted struct! If you use Swift native type, youre in 
/// risk of memory corruption!
public struct BoundRemoteMemory<T> {
    public let segment: MemoryRange
    public let buffer: T

    public init(pid: Int32, load baseAddress: UInt, initialValue: T) {
        self.segment = baseAddress..<(baseAddress + UInt(MemoryLayout<T>.size))
        var buffer = initialValue
        swift_inspect_bridge__ptrace_peekdata_initialize(pid, baseAddress, &buffer)
        self.buffer = buffer
    }

    public init(pid: Int32, load baseAddress: UInt) {
        let segment = baseAddress..<(baseAddress + UInt(MemoryLayout<T>.size))
        let rawRemote = RawRemoteMemory(pid: pid, load: segment)
        self.init(bind: rawRemote)!
    }

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