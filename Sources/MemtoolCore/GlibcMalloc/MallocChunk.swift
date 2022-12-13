import Cutils

extension malloc_chunk {
    /// Allocated Arena - the main arena uses the application's heap. Other arenas use mmap'd heaps. To map a chunk to a heap, you need to know which case applies. If this bit is 0, the chunk comes from the main arena and the main heap. If this bit is 1, the chunk comes from mmap'd memory and the location of the heap can be computed from the chunk's address.
    ///
    /// Source: The glibc source code [4]
    var isAllocatedArena: Bool {
        self.mchunk_size & 0b100 > 0
    }

    /// Allocated Arena - the main arena uses the application's heap. Other arenas use mmap'd heaps. To map a chunk to a heap, you need to know which case applies. If this bit is 0, the chunk comes from the main arena and the main heap. If this bit is 1, the chunk comes from mmap'd memory and the location of the heap can be computed from the chunk's address.
    ///
    /// Source: The glibc source code [4]
    var isMmapped: Bool {
        self.mchunk_size & 0b10 > 0
    }

    /// Previous chunk is in use - if set, the previous chunk is still being used by the application, and thus the prev_size field is invalid. Note - some chunks, such as those in fastbins (see below) will have this bit set despite being free'd by the application. This bit really means that the previous chunk should not be considered a candidate for coalescing - it's "in use" by either the application or some other optimization layered atop malloc's original code :-)
    /// 
    /// Source: The glibc source code [4]
    var isPreviousInUse: Bool {
        self.mchunk_size & 0b1 > 0
    }

    var size: UInt {
        UInt(bitPattern: self.mchunk_size) & 0xfffffffffffffff8 
    }
}

/// Chunk is a container, that represents single chunk of `glibc malloc`-allocated memory in the
/// remote process. It also stores the bytes copied from the remote memory into the memory
/// of the tracing process.
public struct Chunk {
    /// Standard malloc chunk header. Notice, the some of the fields may not be valid, depending on
    /// the state of the chunk.
    public let header: malloc_chunk

    /// Raw bytes found in the *user space*.
    public let content: RawRemoteMemory

    /// Chunk content begins at 3nd word of the malloc chunk and ends 1 word after the base address + size of the chunk
    public var chunkAllocatedRange: MemoryRange {
        (content.segment.lowerBound - Chunk.chunkContentOffset)..<(content.segment.upperBound - Chunk.chunkContentEndOffset)
    }

    /// Offset of the user space of the malloc chunk from it's base address [1]
    public static let chunkContentOffset: UInt = UInt(MemoryLayout<size_t>.size * 2)

    /// End offset of the content (overlaps with the next malloc chunk) [1]
    public static let chunkContentEndOffset: UInt = UInt(MemoryLayout<size_t>.size)

}

public extension Chunk {
    /// Performs *unsafe and unchecked* load from the remote process. If misaligned, may attempts
    /// to load 2^64 - 1 bytes of memory and crash.
    /// - Parameters:
    ///   - pid: The PID of the remote process
    ///   - baseAddress: The base address of the malloc chunk (not the user space!)
    init(pid: Int32, baseAddress: UInt) {
        self.header = BoundRemoteMemory<malloc_chunk>(pid: pid, load: baseAddress).buffer
        self.content = RawRemoteMemory(
            pid: pid, 
            load: (baseAddress + Chunk.chunkContentOffset)..<(baseAddress + header.size + Chunk.chunkContentEndOffset)
        )
    }
}
