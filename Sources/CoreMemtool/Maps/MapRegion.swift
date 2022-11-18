public struct MapInfo {
    public var flags: String
    public var offset: UInt64
    public var device: (major: UInt64, minor: UInt64)
    public var inode: UInt64
    public var pathname: String
}

public typealias MapRegion = MemoryRegion<MapInfo>

// Workaround: Declaration in file with _StringProcessing was ignored.
public enum Map { }
