enum MainArena {
    static func getElfSymbol(glibcPath: String) -> SymbolEntry {
        // TODO: Verify path contains GLIBC
        SymbolEntry.loadSymbol(named: "main_arena", for: glibcPath)!
    }
}
