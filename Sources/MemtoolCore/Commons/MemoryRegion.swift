public protocol OpaqueRegion {
    var range: MemoryRange { get }
}

public struct MemoryRegion<T>: OpaqueRegion {
    public var range: MemoryRange
    public var properties: T
}
