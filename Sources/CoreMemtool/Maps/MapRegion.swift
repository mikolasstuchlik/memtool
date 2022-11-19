public struct MapFlags: OptionSet {
    public var rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let read      = MapFlags(rawValue: 0b1)
    public static let write     = MapFlags(rawValue: 0b10)
    public static let execute   = MapFlags(rawValue: 0b100)
    public static let protected = MapFlags(rawValue: 0b1000)

    public init(rawValue: String) {
        self.rawValue = 0

        if rawValue.dropFirst(0).prefix(1) == "r" {
            self.insert(.read)
        }

        if rawValue.dropFirst(1).prefix(1) == "w" {
            self.insert(.write)
        }

        if rawValue.dropFirst(2).prefix(1) == "x" {
            self.insert(.execute)
        }

        if rawValue.dropFirst(3).prefix(1) == "p" {
            self.insert(.protected)
        }
    }

    public var stringValue: String {
        var str = ""
        str += contains(.read) ? "r" : "-"
        str += contains(.write) ? "w" : "-"
        str += contains(.execute) ? "e" : "-"
        str += contains(.protected) ? "p" : "-"
        return str
    }
}

public enum Pseudopath: String {
    case stack = "[stack]"
    case vdso = "[vdso]"
    case heap = "[heap]"
    case vsyscall = "[vsyscall]"
    case mmapped = ""
}

public enum MapPath: RawRepresentable, Equatable {
    case pseudopath(Pseudopath)
    case file(String)

    public init(rawValue: String) {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pseudopath = Pseudopath(rawValue: rawValue)  {
            self = .pseudopath(pseudopath)
        } else {
            self = .file(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case let .pseudopath(pseudopath):
            return pseudopath.rawValue
        case let .file(file):
            return file
        }
    }
}

public struct MapInfo {
    public var flags: MapFlags
    public var offset: UInt64
    public var device: (major: UInt64, minor: UInt64)
    public var inode: UInt64
    public var pathname: MapPath
}

public typealias MapRegion = MemoryRegion<MapInfo>

// Workaround: Declaration in file with _StringProcessing was ignored.
public enum Map { }
