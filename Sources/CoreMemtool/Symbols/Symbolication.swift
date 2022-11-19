import Foundation
import RegexBuilder
import _StringProcessing

/*
{ man objdump }
       -t
       --syms
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
*/

/*
{man elf}
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
*/

extension Symbolication {

    private static let locationRef = Reference(Substring.self)
    private static let flagsRef = Reference(Substring.self)
    private static let segmentRef = Reference(Substring.self)
    private static let sizeRef = Reference(Substring.self)
    private static let nameRef = Reference(Substring.self)
    private static let regex: Regex = {
        let hexadec = Regex {
            Optionally {
                "0x"
            }
            OneOrMore(.hexDigit)
        }
        
        return Regex {
            Capture(as: locationRef) {
                hexadec
            }
            One(.horizontalWhitespace)
            Capture(as: flagsRef) {
                ChoiceOf {
                    " "
                    "l"
                    "g"
                    "u"
                    "!"
                }
                ChoiceOf {
                    " "
                    "w"
                }
                ChoiceOf {
                    " "
                    "C"
                }
                ChoiceOf {
                    " "
                    "W"
                }
                ChoiceOf {
                    " "
                    "i"
                    "I"
                }
                ChoiceOf {
                    " "
                    "d"
                    "D"
                }
                ChoiceOf {
                    " "
                    "f"
                    "F"
                    "O"
                }
            }
            OneOrMore(.horizontalWhitespace)
            Capture(as: segmentRef) {
                OneOrMore(.whitespace.inverted)
            }
            One(.horizontalWhitespace)
            Capture(as: sizeRef) {
                hexadec
            }
            One(.horizontalWhitespace)
            Capture(as: nameRef) {
                OneOrMore(.anyNonNewline)
            }
        }
    }()

    private static func getElfDescription(file: String, filter: String? = nil) -> String {
        let process = Process()
        let aStdout = Pipe()
        let aStderr = Pipe()

        var buffer = Data()

        process.executableURL = URL(fileURLWithPath: "/bin/env")
        process.standardOutput = aStdout
        //process.standardError = aStderr
        // `objdump -tL [file]`
        // objdump  : program for dumping object file information
        // -t       : dump symbol table
        // -L       : follow links (for example when binary is stripped) 1313
        process.arguments = ["bash", "-c", "objdump -tL \(file) " + (filter.flatMap { " | grep \($0)" } ?? "") ]

        try! process.run()

        while process.isRunning {
            buffer.append(aStdout.fileHandleForReading.readDataToEndOfFile())
        }

        guard process.terminationStatus == 0 else {
            error("Error: Map failed to load. Path: \(process.executableURL?.path ?? ""), arguments: \(process.arguments ?? []), termination status: \(process.terminationStatus), stderr: \(String(data: aStderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")") 
            return ""
        }
        let result = String(data: buffer, encoding: .utf8)

        return result!
    }

    public static func loadSymbols(for file: String) -> [UnloadedSymbolInfo] {
        return getElfDescription(file: file).components(separatedBy: "\n").compactMap { line -> UnloadedSymbolInfo? in
            guard !line.isEmpty else {
                return nil
            }
            guard let result = try? regex.firstMatch(in: line) else {
                error("Warning: Symbol failed to match regex: \(line)")
                return nil
            }
            return UnloadedSymbolInfo(
                file: file,
                location: UInt64(String(result[locationRef]), radix: 16)!,
                flags: SymbolFlags(rawValue: String(result[flagsRef])),
                segment: SymbolSection(rawValue: String(result[segmentRef])),
                size: UInt64(String(result[sizeRef]), radix: 16)!,
                name: String(result[nameRef])
            )
        }
    }

    public static func loadSymbol(named symbolName: String, for file: String) -> UnloadedSymbolInfo? {
        let entry = getElfDescription(file: file, filter: symbolName)
        guard !entry.isEmpty else {
            return nil
        }
        guard let result = try? regex.firstMatch(in: entry) else {
            error("Warning: Symbol failed to match regex: \(entry)")
            return nil
        }
        return UnloadedSymbolInfo(
            file: file,
            location: UInt64(String(result[locationRef]), radix: 16)!,
            flags: SymbolFlags(rawValue: String(result[flagsRef])),
            segment: SymbolSection(rawValue: String(result[segmentRef])),
            size: UInt64(String(result[sizeRef]), radix: 16)!,
            name: String(result[nameRef])
        )
    }
}
