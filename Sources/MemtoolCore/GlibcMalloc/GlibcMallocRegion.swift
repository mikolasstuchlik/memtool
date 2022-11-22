public enum GlibcMallocAnalysisFlag {
    case mainHeap
    case threadHeap
    case mmappedChunkCandidate
    case sharedObjectBss
    case notYetAnalyzed
}

public struct GlibcMallocMapAnalysis {
    public var flag: GlibcMallocAnalysisFlag
    public var mapRegion: MapRegion
}

public enum GlibcMallocChunkState: Equatable {
    case mmapped, heapActive, heapFreed, topChunk
}

public enum GlibcMallocAssumedRebound: Equatable {
    case mallocState
    case mallocChunk(GlibcMallocChunkState)
    case heapInfo
}

public struct GlibcMallocInfo: Equatable {
    public var rebound: GlibcMallocAssumedRebound
    public var explored: Bool
}

public typealias GlibcMallocRegion = MemoryRegion<GlibcMallocInfo>
