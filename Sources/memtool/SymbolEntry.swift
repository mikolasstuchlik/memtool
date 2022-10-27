import Foundation
import RegexBuilder
import _StringProcessing

struct SymbolEntry {

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

    let file: String
    let location: UInt64
    let flags: String
    let segment: String
    let size: UInt64
    let name: String

    private static func getElfDescription(file: String, filter: String? = nil) -> String {
        let process = Process()
        let aStdout = Pipe()
        let aStderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/env")
        process.standardOutput = aStdout
        process.standardError = aStderr
        process.arguments = ["bash", "-c", "objdump -t \(file)" + (filter.flatMap { " | grep \($0)" } ?? "") ]

        try! process.run()

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fatalError() 
        }
        let result = String(data: aStdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

        return result!
    }

    static func loadSymbols(for file: String) -> [SymbolEntry] {
        return getElfDescription(file: file).components(separatedBy: "\n").compactMap { line -> SymbolEntry? in
            guard !line.isEmpty else {
                return nil
            }
            guard let result = try? regex.firstMatch(in: line) else {
                return nil
            }
            return SymbolEntry(
                file: file,
                location: UInt64(String(result[locationRef]), radix: 16)!,
                flags: String(result[flagsRef]),
                segment: String(result[segmentRef]),
                size: UInt64(String(result[sizeRef]), radix: 16)!,
                name: String(result[nameRef])
            )
        }
    }

    static func loadSymbol(named symbolName: String, for file: String) -> SymbolEntry? {
        let entry = getElfDescription(file: file, filter: symbolName)
        guard !entry.isEmpty else {
            return nil
        }
        guard let result = try? regex.firstMatch(in: entry) else {
            return nil
        }
        return SymbolEntry(
            file: file,
            location: UInt64(String(result[locationRef]), radix: 16)!,
            flags: String(result[flagsRef]),
            segment: String(result[segmentRef]),
            size: UInt64(String(result[sizeRef]), radix: 16)!,
            name: String(result[nameRef])
        )
    }

    var str: String {
        String(format: "SymbolEntry(file: %@, location: %016lx, flags: %@, segment: %@, size: %016lx, name: %@)", file, location, flags, segment, size, name)
    }

    static func findOffset(for symbol: SymbolEntry, in maps: [MapEntry]) -> UInt64? {
        for map in maps where map.pathname == symbol.file {
            let mapSize = map.end - map.start
            let loadedElfLocation = map.offset..<(map.offset + mapSize)

            if loadedElfLocation.contains(symbol.location) {
                return map.start - map.offset + symbol.location
            }
        }

        return nil
    }
}
