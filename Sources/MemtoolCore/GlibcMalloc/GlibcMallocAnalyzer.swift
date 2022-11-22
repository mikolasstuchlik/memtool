import Cutils

public final class GlibcMallocAnalyzer {
    public enum Error: Swift.Error {
        case initializeSessionWithMapAndSymbols
        case mainArenaDebugSymbolNotFound
        case onlySupportsGlibcMalloc
    }

    public let pid: Int32

    // Main arena is excluded from `exploredHeap`, because it is located in the Glibc .data section.
    public let mainArena: BoundRemoteMemory<malloc_state>

    public private(set) var map: [GlibcMallocMapAnalysis]
    public private(set) var exploredHeap: [GlibcMallocRegion]

    public init(session: Session) throws {
        guard 
            let map = session.map, 
            let unloadedSymbols = session.unloadedSymbols,
            let symbols = session.symbols 
        else {
            throw Error.initializeSessionWithMapAndSymbols
        }

        guard let mainArena = symbols.first(where: { $0.properties.name == "main_arena"}) else {
            throw Error.mainArenaDebugSymbolNotFound
        }

        guard 
            let mainArenaInMap = map.first(where: { $0.range.contains(mainArena.range.lowerBound) }),
            case let .file(mainArenaFile) = mainArenaInMap.properties.pathname,
            unloadedSymbols[mainArenaFile]?.contains(where: { $0.name.hasPrefix("GLIBC_2.") && $0.segment == .known(.abs) }) == true 
        else {
            throw Error.onlySupportsGlibcMalloc
        }

        self.pid = session.pid
        self.mainArena = BoundRemoteMemory<malloc_state>(pid: pid, load: mainArena.range.lowerBound)
        self.map = map.map { GlibcMallocMapAnalysis(flag: .notYetAnalyzed, mapRegion: $0) }
        self.exploredHeap = []
    }

    public func analyze() {
        if !exploredHeap.isEmpty {
            error("Warning: Discarding previous explored Glibc heap.")
            exploredHeap = []
        }

        localizeThreadArenas()
        analyzeThreadArenas()
        traverseMainArenaChunks()
        traverseThreadArenaChunks()
    }

    func localizeThreadArenas() {
        var currentBase = UInt64(UInt(bitPattern: mainArena.buffer.next))
        while currentBase != mainArena.segment.lowerBound {
            let threadArena = BoundRemoteMemory<malloc_state>(pid: pid, load: currentBase)
            exploredHeap.append(GlibcMallocRegion(
                range: threadArena.segment, 
                properties: GlibcMallocInfo(rebound: .mallocState, explored: false)
            ))
            currentBase = UInt64(UInt(bitPattern: threadArena.buffer.next))
        }
    }

    func analyzeThreadArenas() {
        let exploredCopy = exploredHeap
        for (index, region) in exploredCopy.enumerated() {
            guard 
                !region.properties.explored,
                case .mallocState = region.properties.rebound
            else {
                continue
            }

            let threadArena = BoundRemoteMemory<malloc_state>(pid: pid, load: region.range.lowerBound)
            let heapInfoBlocks = getAllHeapBlocks(for: threadArena)

            for heapInfo in heapInfoBlocks {
                exploredHeap.append(GlibcMallocRegion(
                    range: heapInfo.segment, 
                    properties: GlibcMallocInfo(rebound: .heapInfo, explored: false)
                ))
            }

            exploredHeap[index].properties.explored = true
        }
    }

    func getAllHeapBlocks(for threadArena: BoundRemoteMemory<malloc_state>) -> [BoundRemoteMemory<heap_info>] {
        var result : [BoundRemoteMemory<heap_info>] = []
        
        guard threadArena.segment != mainArena.segment else {
            error("Error: \(#function) Main arena can not be treated as Thread arena!")
            return []
        }

        let topChunk = UInt64(Int(bitPattern: threadArena.buffer.top))
        guard let topPage = getMapIndex(for: topChunk) else {
            return []
        }

        result.append(BoundRemoteMemory<heap_info>(pid: pid, load: map[topPage].mapRegion.range.lowerBound))
        while let current = result.last?.buffer.prev.flatMap( { UInt64(Int(bitPattern: $0)) } ) {
            result.append(BoundRemoteMemory<heap_info>(pid: pid, load: current))
        }

        // Mark maps
        for heapInfo in result {
            guard let index = getMapIndex(for: heapInfo.segment.lowerBound) else {
                error("Error: Heap info base " + String(format: "0x%016lx", heapInfo.segment.lowerBound) + " outside mapped memory")
                continue
            }

            if map[index].flag != .threadHeap && map[index].flag != .notYetAnalyzed {
                error("Warning: Remapping map \(map[index]) to `thread heap`")
            }

            map[index].flag = .threadHeap
        }

        return result
    }

    func traverseMainArenaChunks() {
        let topChunk = UInt64(Int(bitPattern: mainArena.buffer.top))
        guard let mainHeapMap = getMapIndex(for: topChunk) else {
            error("Error: Top chunk of main arena is outside mapped memory!")
            return
        }

        let chunks = traverseChunks(
            in: map[mainHeapMap].mapRegion.range.lowerBound..<topChunk,
            assumeHasTopChunk: true,
            isMainArena: true
        )
        exploredHeap.append(contentsOf: chunks)
    }

    func traverseThreadArenaChunks() {
        let exploredCopy = exploredHeap
        for (index, region) in exploredCopy.enumerated() {
            guard 
                !region.properties.explored,
                case .heapInfo = region.properties.rebound
            else {
                continue
            }

            let heapInfo = BoundRemoteMemory<heap_info>(pid: pid, load: region.range.lowerBound)
            let arenaBase = UInt64(Int(bitPattern: heapInfo.buffer.ar_ptr))
            
            let threadArena = BoundRemoteMemory<malloc_state>(pid: pid, load: arenaBase)
            let topChunkBase = UInt64(Int(bitPattern: threadArena.buffer.top))

            var assumedRange = heapInfo.segment.upperBound..<(heapInfo.segment.upperBound + UInt64(heapInfo.buffer.size))

            if heapInfo.buffer.prev == nil, heapInfo.segment.upperBound == threadArena.segment.lowerBound {
                assumedRange = threadArena.segment.upperBound..<topChunkBase
            }

            let containsTopChunk: Bool
            if assumedRange.contains(topChunkBase) {
                assumedRange = assumedRange.lowerBound..<topChunkBase
                containsTopChunk = true
            } else {
                containsTopChunk = false
            }

            // TODO: Check alignment validity!
            if assumedRange.lowerBound % 16 != 0 {
                let alignment = assumedRange.lowerBound % 16
                assumedRange = (assumedRange.lowerBound + alignment)..<assumedRange.upperBound
            }

            let chunks = traverseChunks(in: assumedRange, assumeHasTopChunk: containsTopChunk)
            exploredHeap.append(contentsOf: chunks)

            exploredHeap[index].properties.explored = true
        }
    }

    func traverseChunks(in chunkArea: Range<UInt64>, assumeHasTopChunk hasTopChunk: Bool = false, isMainArena: Bool = false) -> [GlibcMallocRegion] {
        var chunks: [GlibcMallocRegion] = []
        var currentTop: UInt64 = chunkArea.lowerBound

        while chunkArea.contains(currentTop) {
            let chunk = BoundRemoteMemory<malloc_chunk>(pid: pid, load: currentTop)
            if chunk.buffer.isPreviousInUse == false, chunks.count > 0 {
                chunks[chunks.count - 1].properties.rebound = .mallocChunk(.heapFreed)
            }
            let chunkRange = currentTop..<(currentTop + chunk.buffer.size)
            guard chunkRange.count > 0 else {
                error("Error: Chunk \(chunkRange) with range 0 in area \(chunkArea)")
                break
            }
            chunks.append(GlibcMallocRegion(
                range: chunkRange, 
                properties: .init(rebound: .mallocChunk(.heapActive), explored: true)
            ))
            currentTop = chunkRange.upperBound
        }
        return chunks
    }

    func getMapIndex(for base: UInt64) -> Int? {
        guard let index = map.firstIndex(where: { $0.mapRegion.range.contains(base)} ) else {
            error("Warning: Didn't find map page for top chunk " + String(format: "0x%016lx", base))
            return nil 
        }
        return index
    }

}