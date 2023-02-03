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

/**
Print the symbol table entries of the file.  This is similar to the information provided by the nm program, although the display format is different.  The format of the output depends upon the format of the file being
dumped, but there are two main types.  One looks like this:

        [  4](sec  3)(fl 0x00)(ty   0)(scl   3) (nx 1) 0x00000000 .bss
        [  6](sec  1)(fl 0x00)(ty   0)(scl   2) (nx 0) 0x00000000 fred

where the number inside the square brackets is the number of the entry in the symbol table, the sec number is the section number, the fl value are the symbol's flag bits, the ty number is the symbol's type, the scl
number is the symbol's storage class and the nx value is the number of auxiliary entries associated with the symbol.  The last two fields are the symbol's value and its name.

The other common output format, usually seen with ELF based files, looks like this:

        00000000 l    d  .bss   00000000 .bss
        00000000 g       .text  00000000 fred

Here the first number is the symbol's value (sometimes referred to as its address).  The next field is actually a set of characters and spaces indicating the flag bits that are set on the symbol.  These characters are
described below.  Next is the section with which the symbol is associated or *ABS* if the section is absolute (ie not connected with any section), or *UND* if the section is referenced in the file being dumped, but not
defined there.

After the section name comes another field, a number, which for common symbols is the alignment and for other symbol is the size.  Finally the symbol's name is displayed.

The flag characters are divided into 7 groups as follows:

"l"
"g"
"u"
"!" The symbol is a local (l), global (g), unique global (u), neither global nor local (a space) or both global and local (!).  A symbol can be neither local or global for a variety of reasons, e.g., because it is used
    for debugging, but it is probably an indication of a bug if it is ever both local and global.  Unique global symbols are a GNU extension to the standard set of ELF symbol bindings.  For such a symbol the dynamic
    linker will make sure that in the entire process there is just one symbol with this name and type in use.

"w" The symbol is weak (w) or strong (a space).

"C" The symbol denotes a constructor (C) or an ordinary symbol (a space).

"W" The symbol is a warning (W) or a normal symbol (a space).  A warning symbol's name is a message to be displayed if the symbol following the warning symbol is ever referenced.

"I"
"i" The symbol is an indirect reference to another symbol (I), a function to be evaluated during reloc processing (i) or a normal symbol (a space).

"d"
"D" The symbol is a debugging symbol (d) or a dynamic symbol (D) or a normal symbol (a space).

"F"
"f"
"O" The symbol is the name of a function (F) or a file (f) or an object (O) or just a normal symbol (a space).

Source: `man objdump` [6]
*/
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

/**
Various sections hold program and control information:

.bss   This section holds uninitialized data that contributes to
        the program's memory image.  By definition, the system
        initializes the data with zeros when the program begins to
        run.  This section is of type SHT_NOBITS.  The attribute
        types are SHF_ALLOC and SHF_WRITE.

.comment
        This section holds version control information.  This
        section is of type SHT_PROGBITS.  No attribute types are
        used.

.ctors This section holds initialized pointers to the C++
        constructor functions.  This section is of type
        SHT_PROGBITS.  The attribute types are SHF_ALLOC and
        SHF_WRITE.

.data  This section holds initialized data that contribute to the
        program's memory image.  This section is of type
        SHT_PROGBITS.  The attribute types are SHF_ALLOC and
        SHF_WRITE.

.data1 This section holds initialized data that contribute to the
        program's memory image.  This section is of type
        SHT_PROGBITS.  The attribute types are SHF_ALLOC and
        SHF_WRITE.

.debug This section holds information for symbolic debugging.
        The contents are unspecified.  This section is of type
        SHT_PROGBITS.  No attribute types are used.

.dtors This section holds initialized pointers to the C++
        destructor functions.  This section is of type
        SHT_PROGBITS.  The attribute types are SHF_ALLOC and
        SHF_WRITE.

.dynamic
        This section holds dynamic linking information.  The
        section's attributes will include the SHF_ALLOC bit.
        Whether the SHF_WRITE bit is set is processor-specific.
        This section is of type SHT_DYNAMIC.  See the attributes
        above.

.dynstr
        This section holds strings needed for dynamic linking,
        most commonly the strings that represent the names
        associated with symbol table entries.  This section is of
        type SHT_STRTAB.  The attribute type used is SHF_ALLOC.

.dynsym
        This section holds the dynamic linking symbol table.  This
        section is of type SHT_DYNSYM.  The attribute used is
        SHF_ALLOC.

.fini  This section holds executable instructions that contribute
        to the process termination code.  When a program exits
        normally the system arranges to execute the code in this
        section.  This section is of type SHT_PROGBITS.  The
        attributes used are SHF_ALLOC and SHF_EXECINSTR.

.gnu.version
        This section holds the version symbol table, an array of
        ElfN_Half elements.  This section is of type
        SHT_GNU_versym.  The attribute type used is SHF_ALLOC.

.gnu.version_d
        This section holds the version symbol definitions, a table
        of ElfN_Verdef structures.  This section is of type
        SHT_GNU_verdef.  The attribute type used is SHF_ALLOC.

.gnu.version_r
        This section holds the version symbol needed elements, a
        table of ElfN_Verneed structures.  This section is of type
        SHT_GNU_versym.  The attribute type used is SHF_ALLOC.

.got   This section holds the global offset table.  This section
        is of type SHT_PROGBITS.  The attributes are processor-
        specific.

.hash  This section holds a symbol hash table.  This section is
        of type SHT_HASH.  The attribute used is SHF_ALLOC.

.init  This section holds executable instructions that contribute
        to the process initialization code.  When a program starts
        to run the system arranges to execute the code in this
        section before calling the main program entry point.  This
        section is of type SHT_PROGBITS.  The attributes used are
        SHF_ALLOC and SHF_EXECINSTR.

.interp
        This section holds the pathname of a program interpreter.
        If the file has a loadable segment that includes the
        section, the section's attributes will include the
        SHF_ALLOC bit.  Otherwise, that bit will be off.  This
        section is of type SHT_PROGBITS.

.line  This section holds line number information for symbolic
        debugging, which describes the correspondence between the
        program source and the machine code.  The contents are
        unspecified.  This section is of type SHT_PROGBITS.  No
        attribute types are used.

.note  This section holds various notes.  This section is of type
        SHT_NOTE.  No attribute types are used.

.note.ABI-tag
        This section is used to declare the expected run-time ABI
        of the ELF image.  It may include the operating system
        name and its run-time versions.  This section is of type
        SHT_NOTE.  The only attribute used is SHF_ALLOC.

.note.gnu.build-id
        This section is used to hold an ID that uniquely
        identifies the contents of the ELF image.  Different files
        with the same build ID should contain the same executable
        content.  See the --build-id option to the GNU linker (ld
        (1)) for more details.  This section is of type SHT_NOTE.
        The only attribute used is SHF_ALLOC.

.note.GNU-stack
        This section is used in Linux object files for declaring
        stack attributes.  This section is of type SHT_PROGBITS.
        The only attribute used is SHF_EXECINSTR.  This indicates
        to the GNU linker that the object file requires an
        executable stack.

.note.openbsd.ident
        OpenBSD native executables usually contain this section to
        identify themselves so the kernel can bypass any
        compatibility ELF binary emulation tests when loading the
        file.

.plt   This section holds the procedure linkage table.  This
        section is of type SHT_PROGBITS.  The attributes are
        processor-specific.

.relNAME
        This section holds relocation information as described
        below.  If the file has a loadable segment that includes
        relocation, the section's attributes will include the
        SHF_ALLOC bit.  Otherwise, the bit will be off.  By
        convention, "NAME" is supplied by the section to which the
        relocations apply.  Thus a relocation section for .text
        normally would have the name .rel.text.  This section is
        of type SHT_REL.

.relaNAME
        This section holds relocation information as described
        below.  If the file has a loadable segment that includes
        relocation, the section's attributes will include the
        SHF_ALLOC bit.  Otherwise, the bit will be off.  By
        convention, "NAME" is supplied by the section to which the
        relocations apply.  Thus a relocation section for .text
        normally would have the name .rela.text.  This section is
        of type SHT_RELA.

.rodata
        This section holds read-only data that typically
        contributes to a nonwritable segment in the process image.
        This section is of type SHT_PROGBITS.  The attribute used
        is SHF_ALLOC.

.rodata1
        This section holds read-only data that typically
        contributes to a nonwritable segment in the process image.
        This section is of type SHT_PROGBITS.  The attribute used
        is SHF_ALLOC.

.shstrtab
        This section holds section names.  This section is of type
        SHT_STRTAB.  No attribute types are used.

.strtab
        This section holds strings, most commonly the strings that
        represent the names associated with symbol table entries.
        If the file has a loadable segment that includes the
        symbol string table, the section's attributes will include
        the SHF_ALLOC bit.  Otherwise, the bit will be off.  This
        section is of type SHT_STRTAB.

.symtab
        This section holds a symbol table.  If the file has a
        loadable segment that includes the symbol table, the
        section's attributes will include the SHF_ALLOC bit.
        Otherwise, the bit will be off.  This section is of type
        SHT_SYMTAB.

.text  This section holds the "text", or executable instructions,
        of a program.  This section is of type SHT_PROGBITS.  The
        attributes used are SHF_ALLOC and SHF_EXECINSTR.

Source: `man elf` [7]
*/
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
    /// For reference: https://stackoverflow.com/questions/7029734/what-is-the-data-rel-ro-used-for
    case dataRelRo = ".data.rel.ro"
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

/// Describes the section for which the symbol applies.
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

    /// The section is recognized by the tool
    case known(KnownSymbolSection)

    /// The section is not recognized by the tool
    case other(String)
}

public typealias SymbolRegion = MemoryRegion<LoadedSymbolInfo>

public extension SymbolRegion {
    /// Computes the location of the unloaded symbol in the LAP of the remote process
    /// - Parameters:
    ///   - unloadedSymbol: Symbol to be localized
    ///   - executableFileBasePoints: Base addresses for each executable file
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
