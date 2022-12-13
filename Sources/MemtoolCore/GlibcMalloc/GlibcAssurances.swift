import Cutils

/// This enum contains some constants and checks, that have to be fulfiled to establish
/// a basic level of certainty, that heuristics and assumptions in this project will work
/// with the remote process.
public enum GlibcAssurances {

    /// Symbols commonly used in the heuristics. Most of the symbols are private.
    public struct KnownSymbols {
        /// Name of the symbol in the symbol table.
        public let name: String

        /// Segment, in which this symbol appears.
        public let segment: SymbolSection

        /// Main arena is the arena associated with the main thread. Unlike thread arenas (or any
        /// mmapped arenas more generally), this arena resides in the private memory allocated 
        /// for the `glibc` library.
        public static let mainArena = KnownSymbols(name: "main_arena", segment: .known(.data))

        /// `TCache` is a per-thread symbol, that contains chunks recently freed in this thread.
        /// It is located in the *Thread local storage* in section reserved for `glibc`.
        public static let tCache = KnownSymbols(name: "tcache", segment: .known(.tbss))

        /// Each thread can have one `thread_arena` wich the default arena for the thread. It is located
        /// in the *Thread local storage* in the section for `glibc`.
        public static let threadArena = KnownSymbols(name: "thread_arena", segment: .known(.tbss))

        /// Each thread had one `errno` value, which is an arbitrary integer used for reporting
        /// error states. It is located in the *Thread local storage* in section reserved for `glibc`.
        /// This project uses to it verify that *Thread local storage* heuristics work properly.
        public static let errno: GlibcAssurances.KnownSymbols = KnownSymbols(name: "errno", segment: .known(.tbss))

        /// The dynamic linker (ld, part of the `glibc` source code but different binary) contains
        /// value `_r_debug` that provides debugging information about loaded shared objects for 
        /// debuffer.
        public static let rDebug = KnownSymbols(name: "_r_debug", segment: .known(.bss))
    }

    /// Version is struct, that parses and desctibes Glibc versions based on the data from
    /// symbol tables of a binary file.
    public struct Version: Comparable {
        public static func < (lhs: GlibcAssurances.Version, rhs: GlibcAssurances.Version) -> Bool {
            if lhs.major != rhs.major {
                return lhs.major < lhs.major
            }
            
            if lhs.minor != rhs.minor {
                return lhs.minor < lhs.minor
            }

            return lhs.patch < rhs.patch
        }

        public static let validatedVersions: [Version] = [
            .init(rawValue: "GLIBC_2.36")!
        ]

        let raw: String
        let major: UInt
        let minor: UInt
        let patch: UInt

    }

    /// Checks, whether it can be reasonable assumed, that the file is a `glib` binary.
    /// (Either Glibc or ld).
    /// - Parameters:
    ///   - file: The investigated file.
    ///   - unloadedSymbols: Symbol loaded for each file in the remote process.
    /// - Returns: true if symbols contain the file and it has GLIBC version tags.
    public static func isFileFromGlibc(_ file: String, unloadedSymbols: [String: [UnloadedSymbolInfo]]) -> Bool {
        unloadedSymbols[file].flatMap(loadGlibcVersions(in:))?.isEmpty == false
    }

    /// Checks, whether it can be reasonable assumed, that the file is a `glib` binary.
    /// (Either Glibc or ld).
    /// - Parameter pair: File and symbols associated with the file
    /// - Returns: true if symbols contain the file and it has GLIBC version tags.
    public static func glibcFilePredicate(pair: (key: String, value: [UnloadedSymbolInfo])) -> Bool {
        loadGlibcVersions(in: pair.value).isEmpty == false
    }

    /// Locates unloaded symbol info for requested known symbol.
    /// - Parameters:
    ///   - knownSymbol: The searched symbol.
    ///   - unloadedSymbols: The list of unloaded symbol that is searched.
    /// - Returns: Candidates for the correct result.
    public static func glibcOccurances(of knownSymbol: KnownSymbols, in unloadedSymbols: [String: [UnloadedSymbolInfo]]) -> [UnloadedSymbolInfo] {
        unloadedSymbols.filter(glibcFilePredicate(pair:)).values.flatMap { $0 }.filter {
            $0.name == knownSymbol.name && $0.segment == knownSymbol.segment
        }
    }

    /// Searches, whether there are files, that contain `glibc` binary and that the 
    /// binary maximal version is among validated versions.
    /// - Parameter unloadedSymbols: The list of unloaded symbol that is searched.
    public static func isValidatedGlibcVersion(unloadedSymbols: [String: [UnloadedSymbolInfo]]) -> Bool {
        let versions = unloadedSymbols.values.map(loadGlibcVersions(in:)).filter { !$0.isEmpty }

        return !versions.isEmpty
            && versions.allSatisfy { versions in
                guard let current = versions.max() else {
                    return false
                }

                return Version.validatedVersions.contains(current)
            }
    }

    private static func loadGlibcVersions(in symbols: [UnloadedSymbolInfo]) -> [Version] {
        symbols.filter { $0.segment == .known(.abs) }.map(\.name).compactMap(Version.init(rawValue:))
    }
}

extension GlibcAssurances.Version {
    init?(rawValue: String) {
        guard rawValue.hasPrefix("GLIBC_") else { return nil }

        let versions = rawValue.trimmingPrefix("GLIBC_").components(separatedBy: ".").filter { !$0.isEmpty }

        guard versions.count <= 3 else { return nil }

        let major: UInt
        let minor: UInt
        let patch: UInt

        if versions.count > 0 {
            guard let parsedMajor = UInt(versions[0]) else { return nil }
            major = parsedMajor
        } else {
            return nil
        }

        if versions.count > 1 {
            guard let parsedMinor = UInt(versions[1]) else { return nil }
            minor = parsedMinor
        } else {
            minor = 0
        }

        if versions.count > 2 {
            guard let parsedPatch = UInt(versions[2]) else { return nil }
            patch = parsedPatch
        } else {
            patch = 0
        }

        self = .init(raw: rawValue, major: major, minor: minor, patch: patch)
    }
}