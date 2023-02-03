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

/// Tags, that specify where some of the information of the region was found
public enum GlibcMallocStateOrigin: Equatable {
    /// The chunk was found in a tcache belonging to a thread
    case tlsTCacge(pthreadId: Int32)
    /// The chunk is part of the main heap
    case mainHeap
    /// The chunk is part of a heap with following base address (might be used for troubleshooting, since
    /// chunks in mmapped arenas can compute it's arena location via it's own address.)
    case threadHeap(base: UInt)
    /// The chunk was found in a freed thread arena.
    case freedArena
}

/// Information associated with results of glibc malloc analysis.
public struct GlibcMallocInfo: Equatable {
    /// The C type represented by this memory region
    public var rebound: GlibcMallocAssumedRebound
    /// Whether the Glibc Malloc heuristic already performed all searches on this memory
    public var explored: Bool
    /// Some addition information about where the memory region is found and referenced.
    public var origin: [GlibcMallocStateOrigin]
}

public typealias GlibcMallocRegion = MemoryRegion<GlibcMallocInfo>
