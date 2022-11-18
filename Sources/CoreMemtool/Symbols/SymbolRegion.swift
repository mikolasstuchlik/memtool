public struct UnloadedSymbolInfo {
    public var file: String
    public var location: UInt64
    public var flags: String
    public var segment: String
    public var size: UInt64
    public var name: String
}

public struct LoadedSymbolInfo {
    public var flags: String
    public var segment: String
    public var name: String
}

public typealias SymbolRegion = MemoryRegion<LoadedSymbolInfo>

public extension SymbolRegion {
    init?(unloadedSymbol: UnloadedSymbolInfo, map: [MapRegion]) {
        for mapped in map where mapped.properties.pathname == unloadedSymbol.file {
            let unloadedRange = unloadedSymbol.location..<(unloadedSymbol.location + unloadedSymbol.size)
            let loadedSegmentSize = mapped.range.unsignedCount
            let loadedSegmentRange = mapped.properties.offset..<(mapped.properties.offset + loadedSegmentSize)

            if loadedSegmentRange.contains(unloadedRange) {
                self.range = (mapped.range.lowerBound + unloadedSymbol.location)..<(mapped.range.lowerBound + unloadedSymbol.location + unloadedSymbol.size) 
                self.properties = LoadedSymbolInfo(
                    flags: unloadedSymbol.flags, 
                    segment: unloadedSymbol.segment,
                    name: unloadedSymbol.name
                )
                return
            }
        }

        error("Error: Symbol \(unloadedSymbol) was not found")
        return nil
    }
}

// Workaround: Declaration in file with _StringProcessing was ignored.
public enum Symbolication { }
