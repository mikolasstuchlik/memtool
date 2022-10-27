import Foundation
import Cutils
import Glibc

protocol PointerType {
    func display() -> String
}

extension PointerType {
    func display() -> String { "\(self)" }
}

extension UnsafePointer: PointerType {
    func display() -> String { "\(self.pointee)" }
}

extension UnsafeBufferPointer<UInt64>: PointerType {
    func display() -> String {
        self.prefix(upTo: 32).map { String(format: "%016lx", $0) }.joined(separator: " ") + {
            self.count > 32 
                ? "..."  
                : ""
        }() 
    }
}

struct RemoteMemory<T: PointerType> {
    let address: UInt64
    let size: UInt64
    let buffer: T

    func display() -> String {
"""
Address: \(String(address, radix: 16))
Size: \(String(size, radix: 16))
Type: \(type(of: T.self))
Payload: \(buffer.display())
"""
    }

    var end: UInt64 { address + size }
}

struct Chunk {
    let chunkHeader: RemoteMemory<UnsafePointer<malloc_chunk>>
    let chunk: RemoteMemory<UnsafeBufferPointer<UInt64>>


    init(pid: Int32, baseAddress: UInt64) {
        self.chunkHeader = RemoteMemory(
            address: baseAddress, 
            size: UInt64(MemoryLayout<malloc_chunk>.size), 
            buffer: Chunk.loadHeader(in: pid, from: baseAddress)
        )
        let data = UnsafeBufferPointer<UInt64>(
            start: swift_inspect_bridge__ptrace_peekdata_length(
                pid, 
                baseAddress, 
                chunkHeader.buffer.pointee.size
            ).assumingMemoryBound(to: UInt64.self),
            count: Int(chunkHeader.buffer.pointee.size / 8)
        )
        self.chunk = RemoteMemory(address: baseAddress, size: chunkHeader.buffer.pointee.size, buffer: data)
    }

    private static func loadHeader(in pid: Int32, from address: UInt64) -> UnsafePointer<malloc_chunk> {
        swift_inspect_bridge__ptrace_peekdata_length(
            pid, 
            address, 
            UInt64(MemoryLayout<malloc_chunk>.size)
        ).assumingMemoryBound(to: malloc_chunk.self)
    }

    func display() -> String {
"""
Header:
\(chunkHeader.display())
Buffer:
\(chunk.display())
"""
    }
}

final class Session {
    let pid: Int32

    let maps: [MapEntry]
    let glibcIndex: Int

    let mainArena: SymbolEntry
    let mainArenaBuffer: RemoteMemory<UnsafePointer<malloc_state>>

    var loadedChunks: [Chunk] = []

    init(pid: Int32) {
        swift_inspect_bridge__ptrace_attach(pid)
        self.pid = pid
        self.maps = Map.getMap(for: "\(pid)")
        self.glibcIndex = maps.firstIndex { $0.pathname.contains("libc.so") }!
        self.mainArena = MainArena.getElfSymbol(glibcPath: maps[glibcIndex].pathname)
        assert(MemoryLayout<malloc_state>.size == mainArena.size)
        let mainArenaBase = SymbolEntry.findOffset(for: mainArena, in: maps)! - 0x1000

        let buffer = swift_inspect_bridge__ptrace_peekdata_length(
            pid, 
            mainArenaBase, 
            UInt64(MemoryLayout<malloc_state>.size)
        )!.assumingMemoryBound(to: malloc_state.self)

        self.mainArenaBuffer = RemoteMemory(address: mainArenaBase, size: UInt64(MemoryLayout<malloc_state>.size), buffer: buffer)
    }

    func loadChunk(at address: UInt64) {
        loadedChunks.append(Chunk(pid: pid, baseAddress: address))

        print(loadedChunks.last!.display())
    }

    func displayChunks() {
        for item in loadedChunks {
            print(item.display())
        }
    }

    deinit {
        swift_inspect_bridge__ptrace_syscall(pid)
        mainArenaBuffer.buffer.deallocate()
        loadedChunks.forEach { 
            $0.chunk.buffer.deallocate()
            $0.chunkHeader.buffer.deallocate()
        }
    }
}