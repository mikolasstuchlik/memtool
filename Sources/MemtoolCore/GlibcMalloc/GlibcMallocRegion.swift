public enum GlibcMallocChunkState: Equatable {
    /// Chunk is mmapped and not book-kept by any arena
    case mmapped
    /// Chunk is active
    case heapActive
    /// Chunk is marked as a next chunk as *free* but not part of any list
    case heapNoBinFree
    /// Chunk is marked as free and stored in a bin linked-list
    case heapBin 
    /// Chunk is marked as free and stored in a fastbin linked-list
    case heapFastBin
    /// Chunk is marked as free and stored in a liked list located in `tcache` TLS
    case heapTCache

    /// Chunk represents an active memory
    var isActive: Bool {
        switch self {
        case .mmapped, .heapActive:
            return true
        case .heapNoBinFree, .heapFastBin, .heapBin, .heapTCache:
            return false
        }
    }
}

/// Describes what C types are represented by given space in memory
public enum GlibcMallocAssumedRebound: Equatable {
    /// Represents `struct malloc_state`
    case mallocState
    /// Represents `struct malloc_chunk`, notice that some fields of `struct malloc_chunk`
    /// are not valid for some states
    case mallocChunk(GlibcMallocChunkState)
    /// Represents `struct _heap_info`
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
