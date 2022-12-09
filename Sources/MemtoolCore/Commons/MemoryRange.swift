public typealias MemoryRange = Range<UInt>

public extension MemoryRange {
    var unsignedCount: UInt {
        upperBound - lowerBound
    }
}

public extension MemoryRange {
    func contains(_ other: MemoryRange) -> Bool {
        lowerBound <= other.lowerBound && upperBound >= other.upperBound
    }
}
