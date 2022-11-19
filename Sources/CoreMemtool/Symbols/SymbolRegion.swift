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
    init?(unloadedSymbol: UnloadedSymbolInfo, fileBasePoints: [String: UInt64]) {
        guard let base = fileBasePoints[unloadedSymbol.file] else {
            error("Error: Symbol \(unloadedSymbol) was not found")
            return nil
        }

        self.range = (base + unloadedSymbol.location)..<(base + unloadedSymbol.location + unloadedSymbol.size) 
        self.properties = LoadedSymbolInfo(
            flags: unloadedSymbol.flags, 
            segment: unloadedSymbol.segment,
            name: unloadedSymbol.name
        )
    }
}

// Workaround: Declaration in file with _StringProcessing was ignored.
public enum Symbolication { }
