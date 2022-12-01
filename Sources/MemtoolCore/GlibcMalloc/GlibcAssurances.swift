import Cutils

public enum GlibcAssurances {
    public static func fileFromGlibc(_ file: String, unloadedSymbols: [String: [UnloadedSymbolInfo]]) -> Bool {
        unloadedSymbols[file]?.contains { $0.name.hasPrefix("GLIBC_2.") && $0.segment == .known(.abs) } == true
    }
}