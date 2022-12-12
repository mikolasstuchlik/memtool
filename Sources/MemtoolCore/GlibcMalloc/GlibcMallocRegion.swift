public enum GlibcMallocChunkState: Equatable {
    case mmapped, heapActive, heapNoBinFree, heapBin, heapFastBin, heapTCache

    var isActive: Bool {
        switch self {
        case .mmapped, .heapActive:
            return true
        case .heapNoBinFree, .heapFastBin, .heapBin, .heapTCache:
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
    case tlsTCacge(pthreadId: Int32), mainHeap, threadHeap(base: UInt), freedArena
}

public struct GlibcMallocInfo: Equatable {
    public var rebound: GlibcMallocAssumedRebound
    public var explored: Bool
    public var origin: [GlibcMallocStateOrigin]
}

public typealias GlibcMallocRegion = MemoryRegion<GlibcMallocInfo>
