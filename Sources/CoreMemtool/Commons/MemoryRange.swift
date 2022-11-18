public typealias MemoryRange = Range<UInt64>

extension MemoryRange {
    var unsignedCount: UInt64 {
        upperBound - lowerBound
    }
}
