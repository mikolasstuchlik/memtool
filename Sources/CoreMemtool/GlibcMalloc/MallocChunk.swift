import Cutils

extension malloc_chunk {
    /// Allocated Arena - the main arena uses the application's heap. Other arenas use mmap'd heaps. To map a chunk to a heap, you need to know which case applies. If this bit is 0, the chunk comes from the main arena and the main heap. If this bit is 1, the chunk comes from mmap'd memory and the location of the heap can be computed from the chunk's address.
    var isAllocatedArena: Bool {
        unsafeBitCast(self.mchunk_size, to: UInt64.self) & 0b100 > 0
    }

    /// Allocated Arena - the main arena uses the application's heap. Other arenas use mmap'd heaps. To map a chunk to a heap, you need to know which case applies. If this bit is 0, the chunk comes from the main arena and the main heap. If this bit is 1, the chunk comes from mmap'd memory and the location of the heap can be computed from the chunk's address.
    var isPreviousMmapped: Bool {
        unsafeBitCast(self.mchunk_size, to: UInt64.self) & 0b10 > 0
    }

    /// Previous chunk is in use - if set, the previous chunk is still being used by the application, and thus the prev_size field is invalid. Note - some chunks, such as those in fastbins (see below) will have this bit set despite being free'd by the application. This bit really means that the previous chunk should not be considered a candidate for coalescing - it's "in use" by either the application or some other optimization layered atop malloc's original code :-)
    var isPreviousInUse: Bool {
        unsafeBitCast(self.mchunk_size, to: UInt64.self) & 0b1 > 0
    }

    var size: UInt64 {
        unsafeBitCast(self.mchunk_size, to: UInt64.self) & (0xffffffffffffffff ^ 0b111)
    }
}

public struct Chunk {
    public let header: malloc_chunk
    public let content: RawRemoteMemory

    public init(pid: Int32, baseAddress: UInt64) {
        self.header = BoundRemoteMemory<malloc_chunk>(pid: pid, load: baseAddress).buffer
        self.content = RawRemoteMemory(pid: pid, load: baseAddress..<(baseAddress + header.size))
    }
}
