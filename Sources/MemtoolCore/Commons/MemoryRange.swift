public typealias MemoryRange = Range<UInt>

extension MemoryRange {
    var unsignedCount: UInt {
        upperBound - lowerBound
    }
}
