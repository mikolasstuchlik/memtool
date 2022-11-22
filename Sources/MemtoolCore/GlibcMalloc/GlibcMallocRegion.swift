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

public enum GlibcMallocChunkState {
    case mmapped, heapActive, heapFreed, topChunk
}

public enum GlibcMallocAssumedRebound {
    case mallocState
    case mallocChunk(GlibcMallocChunkState)
    case heapInfo
}

// TODO: Is this enum needed?
public enum GlibcMallocHeapAnalysisState {
    case explored(Bool)
}

public struct GlibcMallocInfo {
    public var rebound: GlibcMallocAssumedRebound
    public var state: GlibcMallocHeapAnalysisState
}

public typealias GlibcMallocRegion = MemoryRegion<GlibcMallocInfo>
