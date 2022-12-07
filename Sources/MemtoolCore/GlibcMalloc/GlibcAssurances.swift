import Cutils

public enum GlibcAssurances {
    public struct KnownSymbols {
        public let name: String
        public let segment: SymbolSection

        public static let mainArena = KnownSymbols(name: "main_arena", segment: .known(.data))
        public static let tCache = KnownSymbols(name: "tcache", segment: .known(.tbss))
        public static let errno: GlibcAssurances.KnownSymbols = KnownSymbols(name: "errno", segment: .known(.tbss))
        public static let rDebug = KnownSymbols(name: "_r_debug", segment: .known(.bss))
    }

    public static func fileFromGlibc(_ file: String, unloadedSymbols: [String: [UnloadedSymbolInfo]]) -> Bool {
        unloadedSymbols[file]?.contains { $0.name.hasPrefix("GLIBC_2.") && $0.segment == .known(.abs) } == true
    }

    public static func glibcFilePredicate(pair: (key: String, value: [UnloadedSymbolInfo])) -> Bool {
        pair.value.contains { $0.name.hasPrefix("GLIBC_2.") && $0.segment == .known(.abs) }
    }

    public static func glibcOccurances(of knownSymbol: KnownSymbols, in unloadedSymbols: [String: [UnloadedSymbolInfo]]) -> [UnloadedSymbolInfo] {
        unloadedSymbols.filter(glibcFilePredicate(pair:)).values.flatMap { $0 }.filter {
            $0.name == knownSymbol.name && $0.segment == knownSymbol.segment
        }
    }
}