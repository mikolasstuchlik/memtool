import Cutils

public enum GlibcAssurances {
    public struct KnownSymbols {
        public let name: String
        public let segment: SymbolSection

        public static let mainArena = KnownSymbols(name: "main_arena", segment: .known(.data))
        public static let tCache = KnownSymbols(name: "tcache", segment: .known(.tbss))
        public static let threadArena = KnownSymbols(name: "thread_arena", segment: .known(.tbss))
        public static let errno: GlibcAssurances.KnownSymbols = KnownSymbols(name: "errno", segment: .known(.tbss))
        public static let rDebug = KnownSymbols(name: "_r_debug", segment: .known(.bss))
    }

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

    public static func isFileFromGlibc(_ file: String, unloadedSymbols: [String: [UnloadedSymbolInfo]]) -> Bool {
        unloadedSymbols[file].flatMap(loadGlibcVersions(in:))?.isEmpty == false
    }

    public static func glibcFilePredicate(pair: (key: String, value: [UnloadedSymbolInfo])) -> Bool {
        loadGlibcVersions(in: pair.value).isEmpty == false
    }

    public static func glibcOccurances(of knownSymbol: KnownSymbols, in unloadedSymbols: [String: [UnloadedSymbolInfo]]) -> [UnloadedSymbolInfo] {
        unloadedSymbols.filter(glibcFilePredicate(pair:)).values.flatMap { $0 }.filter {
            $0.name == knownSymbol.name && $0.segment == knownSymbol.segment
        }
    }

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