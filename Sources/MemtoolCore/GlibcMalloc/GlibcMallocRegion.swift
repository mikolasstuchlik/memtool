public enum GlibcMallocChunkState: Equatable {
    case mmapped, heapActive, heapNoBinFree, topChunk, heapBin, heapFastBin, heapTCache

    var isActive: Bool {
        switch self {
        case .mmapped, .heapActive:
            return true
        case .heapNoBinFree, .heapFastBin, .heapBin, .topChunk, .heapTCache:
            return false
        }
    }
}

public enum GlibcMallocAssumedRebound: Equatable {
    case mallocState
    case mallocChunk(GlibcMallocChunkState)
    case heapInfo
}

public enum GlibcMallocStateOrigin: Equatable {
    case tls(pthreadId: Int32), mainHeap, threadHeap(base: UInt)
}

public struct GlibcMallocInfo: Equatable {
    public var rebound: GlibcMallocAssumedRebound
    public var explored: Bool
    public var origin: [GlibcMallocStateOrigin]
}

public typealias GlibcMallocRegion = MemoryRegion<GlibcMallocInfo>
