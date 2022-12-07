public enum SymbolScopeFlag: String {
    case local = "l"
    case global = "g"
    case uniqueGlobal = "u"
    case neither = " "
    case both = "!"
}

public enum SymbolWeakFlag: String {
    case `weak` = "w"
    case strong = " "
}

public enum SymbolConstructorFlag: String {
    case constructor = "C"
    case ordianry = " "
}

public enum SymbolWarningFlag: String {
    case warning = "W"
    case normal = " "
}

public enum SymbolReferenceFlag: String {
    case indirectReference = "I"
    case functionEvalOnRec = "i"
    case normal = " "
}

public enum SymbolDebuggingFlag: String {
    case debugging = "d"
    case `dynamic` = "D"
    case normal = " "
}

public enum SymbolTypeFlag: String {
    case function = "F"
    case file = "f"
    case object = "O"
    case normal = " "
}

public struct SymbolFlags: Hashable {
    public var scopeFlag: SymbolScopeFlag
    public var weakFlag: SymbolWeakFlag
    public var constructorFlag: SymbolConstructorFlag
    public var warningFlag: SymbolWarningFlag
    public var referenceFlag: SymbolReferenceFlag
    public var debuggingFlag: SymbolDebuggingFlag
    public var typeFlag: SymbolTypeFlag

    public init(rawValue: String) {
        self.scopeFlag = SymbolScopeFlag(rawValue: String(rawValue.dropFirst(0).prefix(1))) ?? .neither
        self.weakFlag = SymbolWeakFlag(rawValue: String(rawValue.dropFirst(1).prefix(1))) ?? .strong
        self.constructorFlag = SymbolConstructorFlag(rawValue: String(rawValue.dropFirst(2).prefix(1))) ?? .ordianry
        self.warningFlag = SymbolWarningFlag(rawValue: String(rawValue.dropFirst(3).prefix(1))) ?? .normal
        self.referenceFlag = SymbolReferenceFlag(rawValue: String(rawValue.dropFirst(4).prefix(1))) ?? .normal
        self.debuggingFlag = SymbolDebuggingFlag(rawValue: String(rawValue.dropFirst(5).prefix(1))) ?? .normal
        self.typeFlag = SymbolTypeFlag(rawValue: String(rawValue.dropFirst(6).prefix(1))) ?? .normal
    }

    public var rawValue: String {
        scopeFlag.rawValue
            + weakFlag.rawValue
            + constructorFlag.rawValue
            + warningFlag.rawValue
            + referenceFlag.rawValue
            + debuggingFlag.rawValue
            + typeFlag.rawValue
    }
}

public struct UnloadedSymbolInfo: Hashable {
    public var file: String
    public var location: UInt
    public var flags: SymbolFlags
    public var segment: SymbolSection
    public var size: UInt
    public var name: String
}

public struct LoadedSymbolInfo {
    public var flags: SymbolFlags
    public var segment: SymbolSection
    public var name: String
}

public enum KnownSymbolSection: String {
    /// Uninitialized program memory
    case bss = ".bss"   
    case tbss = ".tbss"
    case tbssPlt = ".tbss.plt"
    case comment = ".comment"
    case ctors = ".ctors"
    /// Initialized program memory
    case data = ".data"
    /// Initialized program memory
    case data1 = ".data1"
    case debug = ".debug"
    case dtors = ".dtors"
    case `dynamic` = ".dynamic"
    case dynstr = ".dynstr"
    case dynsym = ".dynsym"
    case fini = ".fini"
    case gnuversion = ".gnu.version"
    case gnuversiond = ".gnu.version_d"
    case gnuversionr = ".gnu.version_r"
    case got = ".got"
    case hash = ".hash"
    case `init` = ".init"
    case interp = ".interp"
    case line = ".line"
    case note = ".note"

    // Not needed at this time
    // .note.ABI-tag

    // Not needed at this time
    // .note.gnu.build-id

    // Not needed at this time
    // .note.GNU-stack

    case openbsdindent = ".note.openbsd.ident"
    case plt = ".plt"
    case relNAME = ".relNAME"
    case relaNAME = ".relaNAME"
    /// Read-only data
    case rodata = ".rodata"
    /// Read-only data
    case rodata1 = ".rodata1"
    case shstrtab = ".shstrtab"
    case strtab = ".strtab"
    case symtab = ".symtab"
    /// Executable instructions
    case text = ".text"
    case abs = "*ABS*"
}

public enum SymbolSection: RawRepresentable, Equatable, Hashable {
    public init(rawValue: String) {
        if let known = KnownSymbolSection(rawValue: rawValue) {
            self = .known(known)
        } else {
            self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case let .known(known):
            return known.rawValue
        case let .other(rawValue):
            return rawValue
        }
    }

    case known(KnownSymbolSection)
    case other(String)
}

public typealias SymbolRegion = MemoryRegion<LoadedSymbolInfo>

public extension SymbolRegion {
    init?(unloadedSymbol: UnloadedSymbolInfo, executableFileBasePoints: [String: UInt]) {
        guard let base = executableFileBasePoints[unloadedSymbol.file] else {
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

public extension [SymbolRegion] {
    func locate(knownSymbol: GlibcAssurances.KnownSymbols) -> [SymbolRegion] {
        filter { $0.properties.name == knownSymbol.name }
    }
}

// Workaround: Declaration in file with _StringProcessing was ignored.
public enum Symbolication { }
