public protocol OpaqueRegion {
    var range: MemoryRange { get }
}

/// MemoryRegion is a struct that associates region of memory of the remote process
/// with metadata releavant for tracing process and analysis. 
public struct MemoryRegion<T>: OpaqueRegion {
    /// The region of the remote process memory
    public var range: MemoryRange
    /// Container for metadata
    public var properties: T
}
