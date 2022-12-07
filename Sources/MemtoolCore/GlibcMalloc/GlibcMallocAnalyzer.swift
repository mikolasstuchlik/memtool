import Cutils

public final class GlibcMallocAnalyzer {
    public enum Error: Swift.Error {
        case initializeSessionWithMapAndSymbols
        case mainArenaDebugSymbolNotFound
        case onlySupportsGlibcMalloc
        case couldNotLocateTcacheInDebugSymbols
    }

    private let session: Session
    public var pid: Int32 { session.pid }

    // Main arena is excluded from `exploredHeap`, because it is located in the Glibc .data section.
    public let mainArena: BoundRemoteMemory<malloc_state>

    public private(set) var map: [GlibcMallocMapAnalysis]
    public private(set) var tcacheFreedChunks: Set<UInt64>
    public private(set) var fastbinFreedChunks: Set<UInt64>
    public private(set) var binFreedChunks: Set<UInt64>
    public private(set) var exploredHeap: [GlibcMallocRegion]

    public init(session: Session) throws {
        guard 
            let map = session.map, 
            let unloadedSymbols = session.unloadedSymbols,
            let symbols = session.symbols 
        else {
            throw Error.initializeSessionWithMapAndSymbols
        }

        guard let mainArena = symbols.locate(knownSymbol: .mainArena).first else {
            throw Error.mainArenaDebugSymbolNotFound
        }

        guard 
            let mainArenaInMap = map.first(where: { $0.range.contains(mainArena.range.lowerBound) }),
            case let .file(mainArenaFile) = mainArenaInMap.properties.pathname,
            GlibcAssurances.fileFromGlibc(mainArenaFile, unloadedSymbols: unloadedSymbols)
        else {
            throw Error.onlySupportsGlibcMalloc
        }

        self.session = session
        self.mainArena = BoundRemoteMemory<malloc_state>(pid: session.pid, load: mainArena.range.lowerBound)
        self.map = map.map { GlibcMallocMapAnalysis(flag: .notYetAnalyzed, mapRegion: $0) }
        self.tcacheFreedChunks = []
        self.exploredHeap = []
        self.fastbinFreedChunks = []
        self.binFreedChunks = []
    }

    public func analyze() throws {
        if !exploredHeap.isEmpty {
            error("Warning: Discarding previous explored Glibc heap.")
            exploredHeap = []
        }

        localizeThreadArenas()
        analyzeThreadArenas()
        try analyzeFreed()
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

    private func analyzeFreed() throws {
        analyzeFastBins(arenaBase: mainArena.segment.lowerBound)
        analyzeBins(arenaBase: mainArena.segment.lowerBound)
        try analyzeTcache()

        for region in exploredHeap {
            guard 
                case .mallocState = region.properties.rebound
            else {
                continue
            }

            analyzeFastBins(arenaBase: region.range.lowerBound)
            analyzeBins(arenaBase: region.range.lowerBound)
        }
    }

    private func analyzeFastBins(arenaBase: UInt64) {
        let firstOffset = MemoryLayout<malloc_state>.offset(of: \.fastbinsY.0)!
        let fastbinPtrSize = MemoryLayout<mfastbinptr>.size
        let fdOffset = MemoryLayout<malloc_chunk>.offset(of: \.fd)!
        let fastBinsCount = macro_NFASTBINS()

        let fastBinFirstChunkBases = (0..<fastBinsCount).compactMap { index in
            let base = arenaBase + UInt64(firstOffset - fdOffset + index * fastbinPtrSize)
            let chunk = BoundRemoteMemory<malloc_chunk>(pid: self.pid, load: base)
            return chunk.buffer.fd.flatMap { UInt64(UInt(bitPattern: $0)) }
        }

        fastBinFirstChunkBases.forEach { currentFastbin in
            var nextChunk: UInt64? = currentFastbin

            while let current = nextChunk {
                self.fastbinFreedChunks.insert(current)
                let chunk = BoundRemoteMemory<malloc_chunk>(pid: self.pid, load: current)
                nextChunk = chunk.deobfuscate(pointer: \.fd).flatMap { UInt64(UInt(bitPattern: $0)) }

                guard current != nextChunk else {
                    error("Error: Endless cycle in chunk \(String(format: "%016lx", current)) while iterating bin  \(String(format: "%016lx", currentFastbin ?? 0))")
                    return
                }
            }
        }
    }

    private func analyzeBins(arenaBase: UInt64) {
        let firstOffset = MemoryLayout<malloc_state>.offset(of: \.bins.0)!
        let binPtrSize = MemoryLayout<mchunkptr>.size * 2
        let fdOffset = MemoryLayout<malloc_chunk>.offset(of: \.fd)!
        let binsTotal = macro_NBINS_TOTAL() / 2

        let binFirstChunkBases: [(breaker: UInt64, base: UInt64)] = (0..<binsTotal).compactMap { index -> (UInt64, UInt64)? in
            let base = UInt64(firstOffset - fdOffset + index * binPtrSize) + arenaBase
            let chunk = BoundRemoteMemory<malloc_chunk>(pid: self.pid, load: base)
            guard 
                let fd = chunk.buffer.fd.flatMap({ UInt64(UInt(bitPattern: $0)) }),
                fd != base
            else {
                return nil
            }
            return (breaker: base, base: fd)
        }

        binFirstChunkBases.forEach { item in
            var nextChunk: UInt64? = item.base
            while let current = nextChunk, current != item.breaker {
                self.binFreedChunks.insert(current)
                let chunk = BoundRemoteMemory<malloc_chunk>(pid: self.pid, load: current)
                nextChunk = chunk.buffer.fd.flatMap { UInt64(UInt(bitPattern: $0)) }
            }
        }
    }

    private func analyzeTcache() throws {
        // FIXME: Here we want to load ALL threads TIDs and perform the same operation. Current analyzers will require modification

        guard 
            let unloadedSymbols = session.unloadedSymbols,
            let tCacheSymbol = GlibcAssurances.glibcOccurances(of: .tCache, in: unloadedSymbols).first
        else {
            throw Error.couldNotLocateTcacheInDebugSymbols
        }

        let tCacheLocation = try TbssSymbolGlibcLdHeuristic(session: session, fileName: tCacheSymbol.file, tbssSymbolName: tCacheSymbol.name)
        let tCacheTLSPtr = BoundRemoteMemory<swift_inspect_bridge__tcache_perthread_t>(pid: pid, load: tCacheLocation.loadedSymbolBase)

        guard let tCachePtr = tCacheTLSPtr.buffer.tcache_ptr else {
            return
        }
        let tCachePtrBase = UInt64(UInt(bitPattern: tCachePtr))
        
        let countsOffset = UInt64(MemoryLayout<tcache_perthread_struct>.offset(of: \.counts.0)!)
        let countsSize: UInt64 = 2 // Size of uint16_t

        let entryOffset = UInt64(MemoryLayout<tcache_perthread_struct>.offset(of: \.entries.0)!)
        let entrySize: UInt64 = 8 // Size of pointer

        for i in 0..<Cutils.TCACHE_MAX_BINS {
            let i = UInt64(i)
            let count = BoundRemoteMemory<UInt16>(pid: pid, load: tCachePtrBase + countsOffset + i * countsSize)
            if count.buffer == 0 {
                continue // TODO: We could verify this as safety check
            }

            let firstChunkPtr = BoundRemoteMemory<swift_inspect_bridge__tcache_entry_t>(pid: pid, load: tCachePtrBase + entryOffset + i * entrySize)
            guard let firstChunkBase = firstChunkPtr.buffer.next.flatMap({ UInt64(UInt(bitPattern: $0)) }) else {
                error("Error: tcache " + String(format: "%016lx", tCachePtrBase) + " in index \(i) is null but count is greater than 0")
                continue
            }
            iterateTcacheChunks(from: firstChunkBase, count: count.buffer)
        }
    }

    private func iterateTcacheChunks(from baseChunk: UInt64, count: UInt16) {
        let chunkUserSpactOffset = UInt64(MemoryLayout<malloc_chunk>.offset(of: \.fd)!)

        var currentBase: UInt64? = baseChunk
        for i in 0..<(count + 1) {
            guard let base = currentBase else {
                if i != count {
                    error("Error: tcache entry " + String(format: "%016lx", baseChunk) + " ended iterating after \(i) steps, expected \(count) steps")
                }
                return
            }
            guard i < count else {
                error("Error: tcache entry " + String(format: "%016lx", baseChunk) + " exceeded the expected number of iterations!")
                return
            }
            let chunk = BoundRemoteMemory<tcache_entry>(pid: pid, load: base)
            let nextPointer = chunk.deobfuscate(pointer: \.next)

            currentBase = nextPointer.flatMap { UInt64(UInt(bitPattern: $0)) }
            tcacheFreedChunks.insert( base - chunkUserSpactOffset )
        }
    }

    func traverseMainArenaChunks() {
        let topChunk = UInt64(UInt(bitPattern: mainArena.buffer.top))
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
                if 
                    case let .mallocChunk(state) = chunks[chunks.count - 1].properties.rebound, 
                    ![GlibcMallocChunkState.heapFastBin, .heapBin, .heapTCache].contains(state)
                {
                    error("Error: Chunk \(chunks[chunks.count - 1].range) is before chunk marked as `previous is not active` and has state \(state)")
                    chunks[chunks.count - 1].properties.rebound = .mallocChunk(.heapNoBinFree)
                }
            }
            let chunkRange = currentTop..<(currentTop + chunk.buffer.size)
            guard chunkRange.count > 0 else {
                error("Error: Chunk \(chunkRange) with range 0 in area \(chunkArea)")
                break
            }

            var chunkState: GlibcMallocChunkState
            if tcacheFreedChunks.contains(chunkRange.lowerBound) {
                chunkState = .heapTCache
            }else if binFreedChunks.contains(chunkRange.lowerBound) {
                chunkState = .heapBin
            } else if fastbinFreedChunks.contains(chunkRange.lowerBound) {
                chunkState = .heapFastBin
            } else {
                chunkState = .heapActive
            }

            chunks.append(GlibcMallocRegion(
                range: chunkRange, 
                properties: .init(rebound: .mallocChunk(chunkState), explored: true)
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