import Cutils

/// Glibc analyzer is the most important classes of this project: it encapsulates the 
/// algorithm for traversing the heap of the remote process and locating active as well
/// as freed chunks.
/// 
/// This implementation is based on [1] and expanded for the tcache feature described in [2].
public final class GlibcMallocAnalyzer {
    public enum Error: Swift.Error {
        case initializeSessionWithMapAndSymbols
        case mainArenaDebugSymbolNotFound
        case onlySupportsGlibcMalloc
        case couldNotLocateTcacheInDebugSymbols
        case couldNotLocateThreadArenaInDebugSymbols
        case unknownSessionType
        case arenaForSessionNotFound
    }

    /// The process associated with this analysis
    private let session: ProcessSession

    // Main arena is excluded from `exploredHeap`, because it is located in the Glibc .data section.
    public let mainArena: BoundRemoteMemory<malloc_state>

    /// Tagging thread arenas is not necessary, but useful for troubleshooting and testing When set to `true`, all explored items have expanded information.
    public let tagThreadArenas: Bool
    /// Thread arenas and their corresponding TBSS heuristic that determined their location
    public private(set) var threadArenas: [Int32: (base: UInt, tlsResult: TbssSymbolGlibcLdHeuristic)]
    /// Keys are base addresses of the chunks located in any of the tcaches. Values are the PID/TID of the
    /// corresponding thread. 
    public private(set) var tcacheFreedChunks: [UInt: Int32]
    /// Base addresses of chunks found in any of the arena fastbins.
    public private(set) var fastbinFreedChunks: Set<UInt>
    /// Base addresses of chunks found in any of the arena bins.
    public private(set) var binFreedChunks: Set<UInt>

    /// The collection holding the working data and the result of the analysis.
    public private(set) var exploredHeap: [GlibcMallocRegion]

    /// Initializes the object with some of the data required for successful analysis.
    /// - Parameters:
    ///   - session: Process that shall be analyzed with maps and symbols loaded.
    ///   - tagThreadArenas: Tagging thread arenas is not necessary, but useful for troubleshooting and testing. When set to `true`, all explored items have expanded information.
    public init(session: ProcessSession, tagThreadArenas: Bool = false) throws {
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
            GlibcAssurances.isFileFromGlibc(mainArenaFile, unloadedSymbols: unloadedSymbols)
        else {
            throw Error.onlySupportsGlibcMalloc
        }

        self.tagThreadArenas = tagThreadArenas
        self.session = session
        self.mainArena = try session.checkedLoad(of: malloc_state.self, base: mainArena.range.lowerBound)
        self.threadArenas = [:]
        self.tcacheFreedChunks = [:]
        self.exploredHeap = []
        self.fastbinFreedChunks = []
        self.binFreedChunks = []
        self.threadArenas = [:]
    }

    /// Perform the analysis of the Glibc-malloc-allocated heap of the remote process.
    public func analyze() throws {
        if !exploredHeap.isEmpty {
            error("Warning: Discarding previous explored Glibc heap.")
            exploredHeap = []
        }

        try localizeThreadArenas()
        try localizeFreedThreadArenas()
        try analyzeThreadArenas()
        try analyzeFreed()
        try traverseMainArenaChunks()
        try traverseThreadArenaChunks()
    }

    /// Filters the results in the `exloredHeap` for a certain thread. Only produces 
    /// results if the `tagThreadArenas` is set to `true`.
    /// - Parameter session: Process or Thread session
    public func view(for session: Session) throws -> [GlibcMallocRegion] {
        let requestedOrigin: GlibcMallocStateOrigin
        if let session = session as? ThreadSession {
            guard let threadArena = threadArenas[session.tid] else {
                throw Error.arenaForSessionNotFound
            }
            requestedOrigin = .threadHeap(base: threadArena.base)
        } else if session is ProcessSession {
            requestedOrigin = .mainHeap
        } else {
            throw Error.unknownSessionType
        }
        return exploredHeap.filter { $0.properties.origin.contains(requestedOrigin) }
    }

    /// Uses the `main_arena` to localize thread arenas and schedule them for exploration.
    func localizeThreadArenas() throws {
        var currentBase = UInt(bitPattern: mainArena.buffer.next)
        while currentBase != mainArena.segment.lowerBound {
            let threadArena = try session.checkedLoad(of: malloc_state.self, base: currentBase)
            exploredHeap.append(GlibcMallocRegion(
                range: threadArena.segment, 
                properties: GlibcMallocInfo(rebound: .mallocState, explored: false, origin: [.threadHeap(base: currentBase)])
            ))
            currentBase = UInt(bitPattern: threadArena.buffer.next)
        }

        guard tagThreadArenas else { return }

        guard 
            let unloadedSymbols = session.unloadedSymbols,
            let threadArenaSymbol = GlibcAssurances.glibcOccurances(of: .threadArena, in: unloadedSymbols).first
        else {
            throw Error.couldNotLocateThreadArenaInDebugSymbols
        }

        for thread in session.threadSessions {
            let tlsValue = try TbssSymbolGlibcLdHeuristic(session: thread, fileName: threadArenaSymbol.file, tbssSymbolName: threadArenaSymbol.name)
            let arena = try session.checkedLoad(of: Optional<mstate>.self, base: tlsValue.loadedSymbolBase)
            if let base = arena.buffer.flatMap(UInt.init(bitPattern:)) {
                threadArenas[thread.tid] = (base, tlsValue)
            }
        }
    }

    /// Uses the `main_arena` to localize freed arenas and schedule them for exploration.
    func localizeFreedThreadArenas() throws {
        var nextBase = mainArena.buffer.next_free.flatMap(UInt.init(bitPattern:))
        while let currentBase = nextBase {
            let threadArena = try session.checkedLoad(of: malloc_state.self, base: currentBase)
            exploredHeap.append(GlibcMallocRegion(
                range: threadArena.segment, 
                properties: GlibcMallocInfo(rebound: .mallocState, explored: false, origin: [
                    .threadHeap(base: currentBase),
                    .freedArena
                ])
            ))
            nextBase = threadArena.buffer.next_free.flatMap(UInt.init(bitPattern:))
        }
    }

    /// Locates all the heap blocks for thread arenas. Those blocks are exclusive to the
    /// thread arenas and are necessary when trying to locate chunks belonging to thread arenas.
    func analyzeThreadArenas() throws {
        let exploredCopy = exploredHeap
        for (index, region) in exploredCopy.enumerated() {
            guard 
                !region.properties.explored,
                case .mallocState = region.properties.rebound
            else {
                continue
            }

            let threadArena = try session.checkedLoad(of: malloc_state.self, base: region.range.lowerBound)
            let heapInfoBlocks = try getAllHeapBlocks(for: threadArena)

            var origin = [GlibcMallocStateOrigin.threadHeap(base: threadArena.segment.lowerBound)]

            if region.properties.origin.contains(.freedArena) {
                origin.append(.freedArena)
            }

            for heapInfo in heapInfoBlocks {
                exploredHeap.append(GlibcMallocRegion(
                    range: heapInfo.segment, 
                    properties: GlibcMallocInfo(rebound: .heapInfo, explored: false, origin: origin)
                ))
            }

            exploredHeap[index].properties.explored = true
        }
    }

    func getAllHeapBlocks(for threadArena: BoundRemoteMemory<malloc_state>) throws -> [BoundRemoteMemory<heap_info>] {
        var result : [BoundRemoteMemory<heap_info>] = []
        
        guard threadArena.segment != mainArena.segment else {
            error("Error: \(#function) Main arena can not be treated as Thread arena!")
            return []
        }

        let topChunk = UInt(bitPattern: threadArena.buffer.top)
        guard let topPage = getMapIndex(for: topChunk) else {
            return []
        }

        result.append(try session.checkedLoad(of: heap_info.self, base: session.map![topPage].range.lowerBound))
        while let current = result.last?.buffer.prev.flatMap(UInt.init(bitPattern:)) {
            result.append(try session.checkedLoad(of: heap_info.self, base: current))
        }

        return result
    }

    private func analyzeFreed() throws {
        try analyzeFastBins(arenaBase: mainArena.segment.lowerBound)
        try analyzeBins(arenaBase: mainArena.segment.lowerBound)
        try analyzeTcache()

        for region in exploredHeap {
            guard 
                case .mallocState = region.properties.rebound
            else {
                continue
            }

            try analyzeFastBins(arenaBase: region.range.lowerBound)
            try analyzeBins(arenaBase: region.range.lowerBound)
        }
    }

    /// Loads all fastbin chunk base addresses for given arena
    /// - Parameter arenaBase: Base address of an arena that should be looked into
    private func analyzeFastBins(arenaBase: UInt) throws {
        let firstOffset = MemoryLayout<malloc_state>.offset(of: \.fastbinsY.0)!
        let fastbinPtrSize = MemoryLayout<mfastbinptr>.size
        let fdOffset = MemoryLayout<malloc_chunk>.offset(of: \.fd)!
        let fastBinsCount = macro_NFASTBINS()

        let fastBinFirstChunkBases = try (0..<fastBinsCount).compactMap { index in
            let base = arenaBase + UInt(firstOffset - fdOffset + index * fastbinPtrSize)
            // Address of index 0 is the same as the index of the arena
            let chunk = try session.checkedLoad(of: malloc_chunk.self, base: base, skipMismatchTypeCheck: index == 0)
            return chunk.buffer.fd.flatMap { UInt(bitPattern: $0) }
        }

        try fastBinFirstChunkBases.forEach { currentFastbin in
            var nextChunk: UInt? = currentFastbin

            while let current = nextChunk {
                self.fastbinFreedChunks.insert(current)
                let chunk = try session.checkedLoad(of: malloc_chunk.self, base: current)
                nextChunk = chunk.deobfuscate(pointer: \.fd).flatMap(UInt.init(bitPattern:))

                guard current != nextChunk else {
                    error("Error: Endless cycle in chunk \(String(format: "%016lx", current)) while iterating bin  \(String(format: "%016lx", currentFastbin))")
                    return
                }
            }
        }
    }

    /// Loads all bin chunk base addresses for given arena
    /// - Parameter arenaBase: Base address of an arena that should be looked into
    private func analyzeBins(arenaBase: UInt) throws {
        let firstOffset = MemoryLayout<malloc_state>.offset(of: \.bins.0)!
        let binPtrSize = MemoryLayout<mchunkptr>.size * 2
        let fdOffset = MemoryLayout<malloc_chunk>.offset(of: \.fd)!
        let binsTotal = macro_NBINS_TOTAL() / 2

        let binFirstChunkBases: [(breaker: UInt, base: UInt)] = try (0..<binsTotal).compactMap { index -> (UInt, UInt)? in
            let base = UInt(firstOffset - fdOffset + index * binPtrSize) + arenaBase
            let chunk = try session.checkedLoad(of: malloc_chunk.self, base: base)
            guard 
                let fd = chunk.buffer.fd.flatMap(UInt.init(bitPattern:)),
                fd != base
            else {
                return nil
            }
            return (breaker: base, base: fd)
        }

        try binFirstChunkBases.forEach { item in
            var nextChunk: UInt? = item.base
            while let current = nextChunk, current != item.breaker {
                self.binFreedChunks.insert(current)
                let chunk = try session.checkedLoad(of: malloc_chunk.self, base: current)
                nextChunk = chunk.buffer.fd.flatMap(UInt.init(bitPattern:))
            }
        }
    }

    /// Locates tcache symbols and performs tcache analysis for all threads.
    private func analyzeTcache() throws {
        guard 
            let unloadedSymbols = session.unloadedSymbols,
            let tCacheSymbol = GlibcAssurances.glibcOccurances(of: .tCache, in: unloadedSymbols).first
        else {
            throw Error.couldNotLocateTcacheInDebugSymbols
        }

        try analyzeTcacheFromTLS(of: self.session, tCacheSymbol: tCacheSymbol)

        for threadSession in self.session.threadSessions {
            try analyzeTcacheFromTLS(of: threadSession, tCacheSymbol: tCacheSymbol)
        }
    }

    /// Traverses array of potention tcache entries and if in any array item there is a chunk
    /// stored, calls a function to travers the linked list of the stored chunks.
    /// - Parameters:
    ///   - taskSession: The thread on which the tcache should be explored
    ///   - tCacheSymbol: The symbol representing the tcache used to compute its offset in TLS
    private func analyzeTcacheFromTLS(of taskSession: Session, tCacheSymbol: UnloadedSymbolInfo) throws {
        let tCacheLocation = try TbssSymbolGlibcLdHeuristic(session: taskSession, fileName: tCacheSymbol.file, tbssSymbolName: tCacheSymbol.name)
        let tCacheTLSPtr = try session.checkedLoad(of: swift_inspect_bridge__tcache_perthread_t.self, base: tCacheLocation.loadedSymbolBase)

        guard let tCachePtr = tCacheTLSPtr.buffer.tcache_ptr else {
            return
        }
        let tCachePtrBase = UInt(bitPattern: tCachePtr)
        
        let countsOffset = UInt(MemoryLayout<tcache_perthread_struct>.offset(of: \.counts.0)!)
        let countsSize: UInt = 2 // Size of uint16_t

        let entryOffset = UInt(MemoryLayout<tcache_perthread_struct>.offset(of: \.entries.0)!)
        let entrySize: UInt = 8 // Size of pointer

        for i in 0..<Cutils.TCACHE_MAX_BINS {
            let i = UInt(i)
            let count = try session.checkedLoad(of: UInt16.self, base: tCachePtrBase + countsOffset + i * countsSize)
            if count.buffer == 0 {
                continue // TODO: We could verify this as safety check
            }

            let firstChunkPtr = try session.checkedLoad(of: swift_inspect_bridge__tcache_entry_t.self, base: tCachePtrBase + entryOffset + i * entrySize)
            guard let firstChunkBase = firstChunkPtr.buffer.next.flatMap(UInt.init(bitPattern:)) else {
                error("Error: tcache " + String(format: "%016lx", tCachePtrBase) + " in index \(i) is null but count is greater than 0")
                continue
            }
            try iterateTcacheChunks(from: firstChunkBase, count: count.buffer, taskSession: taskSession)
        }
    }

    /// Iterates all chunks in the tcache linked list
    /// - Parameters:
    ///   - baseChunk: The first chunk in the tcache linked list
    ///   - count: The expected number of items
    ///   - taskSession: The session
    private func iterateTcacheChunks(from baseChunk: UInt, count: UInt16, taskSession: Session) throws {
        let chunkUserSpactOffset = UInt(MemoryLayout<malloc_chunk>.offset(of: \.fd)!)

        var currentBase: UInt? = baseChunk
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
            let chunk = try session.checkedLoad(of: tcache_entry.self, base: base)
            let nextPointer = chunk.deobfuscate(pointer: \.next)

            currentBase = nextPointer.flatMap(UInt.init(bitPattern:))
            tcacheFreedChunks[base - chunkUserSpactOffset] = taskSession.ptraceId
        }
    }

    /// Executed function that locates all chunks in main arena.
    func traverseMainArenaChunks() throws {
        let topChunk = UInt(bitPattern: mainArena.buffer.top)
        guard let mainHeapMap = getMapIndex(for: topChunk) else {
            error("Error: Top chunk of main arena is outside mapped memory!")
            return
        }

        let chunks = try traverseChunks(in: session.map![mainHeapMap].range.lowerBound..<topChunk)
        exploredHeap.append(contentsOf: chunks)
    }

    /// Executed function that locates all chunks in thread arenas.
    func traverseThreadArenaChunks() throws {
        let exploredCopy = exploredHeap
        for (index, region) in exploredCopy.enumerated() {
            guard 
                !region.properties.explored,
                case .heapInfo = region.properties.rebound
            else {
                continue
            }

            let heapInfo = try session.checkedLoad(of: heap_info.self, base: region.range.lowerBound)
            let arenaBase = UInt(bitPattern: heapInfo.buffer.ar_ptr)
            
            let threadArena = try session.checkedLoad(of: malloc_state.self, base: arenaBase)
            let topChunkBase = UInt(bitPattern: threadArena.buffer.top)

            var assumedRange = heapInfo.segment.upperBound..<(heapInfo.segment.upperBound + UInt(heapInfo.buffer.size))

            if heapInfo.buffer.prev == nil, heapInfo.segment.upperBound == threadArena.segment.lowerBound {
                assumedRange = threadArena.segment.upperBound..<topChunkBase
            }

            // The first chunk must have a specific offset [1]
            if assumedRange.lowerBound % 16 != 0 {
                let alignment = assumedRange.lowerBound % 16
                assumedRange = (assumedRange.lowerBound + alignment)..<assumedRange.upperBound
            }

            var chunks = try traverseChunks(in: assumedRange, threadHeapBase: threadArena.segment.lowerBound)
            if region.properties.origin.contains(.freedArena) {
                for i in 0..<chunks.count {
                    chunks[i].properties.origin.append(.freedArena)
                }
            }

            exploredHeap.append(contentsOf: chunks)

            exploredHeap[index].properties.explored = true
        }
    }

    /// Locates all the chunks in a specific region of memory. It is invariant, that there is a valid chunk
    /// exactly at the beginning of the searched area.
    /// - Parameters:
    ///   - chunkArea: The area which should contain chunks.
    ///   - threadHeapBase: If the arena which these chunks belong to is not main_arena, enter its base address.
    /// - Returns: List of chunks.
    func traverseChunks(in chunkArea: Range<UInt>, threadHeapBase: UInt? = nil) throws -> [GlibcMallocRegion] {
        var chunks: [GlibcMallocRegion] = []
        var currentTop: UInt = chunkArea.lowerBound

        while chunkArea.contains(currentTop) {
            let chunk = try session.checkedLoad(of: malloc_chunk.self, base: currentTop)
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
            var origin: [GlibcMallocStateOrigin] = [threadHeapBase == nil ? .mainHeap : .threadHeap(base: threadHeapBase!)]

            if let pthreadId = tcacheFreedChunks[chunkRange.lowerBound] {
                chunkState = .heapTCache
                origin.append(.tlsTCacge(pthreadId: pthreadId))
            }else if binFreedChunks.contains(chunkRange.lowerBound) {
                chunkState = .heapBin
            } else if fastbinFreedChunks.contains(chunkRange.lowerBound) {
                chunkState = .heapFastBin
            } else {
                chunkState = .heapActive
            }

            chunks.append(GlibcMallocRegion(
                range: chunkRange, 
                properties: .init(rebound: .mallocChunk(chunkState), explored: true, origin: origin)
            ))
            currentTop = chunkRange.upperBound
        }
        return chunks
    }

    /// Gets index of item in the map (stored in the Session) that contains the address.
    func getMapIndex(for base: UInt) -> Int? {
        guard let index = session.map!.firstIndex(where: { $0.range.contains(base)} ) else {
            error("Warning: Didn't find map page for top chunk " + String(format: "0x%016lx", base))
            return nil 
        }
        return index
    }

}