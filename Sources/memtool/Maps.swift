import Foundation
import RegexBuilder
import _StringProcessing

struct MapEntry {
    let start: UInt64
    let end: UInt64
    let flags: String
    let offset: UInt64
    let device: (major: UInt64, minor: UInt64)
    let inode: UInt64
    let pathname: String

    var str: String {
        String(format: "SymbolEntry(start: %016lx end: %016lx flags: %@, offset: %016lx device: \(device), inode: %d pathname: %@)", start, end, flags, offset, inode, pathname)
    }
}

enum Map {

    private static let startRef = Reference(Substring.self)
    private static let endRef = Reference(Substring.self)
    private static let flagsRef = Reference(Substring.self)
    private static let offsetRef = Reference(Substring.self)
    private static let deviceMajorRef = Reference(Substring.self)
    private static let deviceMinorRef = Reference(Substring.self)
    private static let inodeRef = Reference(Substring.self)
    private static let pathnameRef = Reference(Substring.self)

    private static let regex: Regex = {
        let hexadec = Regex {
            Optionally {
                "0x"
            }
            OneOrMore(.hexDigit)
        }
        
        return Regex {
            Capture(as: startRef) {
                hexadec
            }
            "-"
            Capture(as: endRef) {
                hexadec
            }
            One(.horizontalWhitespace)
            Capture(as: flagsRef) {
                ChoiceOf {
                    "r"
                    "-"
                }
                ChoiceOf {
                    "w"
                    "-"
                }
                ChoiceOf {
                    "x"
                    "-"
                }
                ChoiceOf {
                    "p"
                    "-"
                }
            }
            OneOrMore(.horizontalWhitespace)
            Capture(as: offsetRef) {
                hexadec
            }
            OneOrMore(.horizontalWhitespace)
            Capture(as: deviceMajorRef) {
                OneOrMore(.digit)
            }
            ":"
            Capture(as: deviceMinorRef) {
                OneOrMore(.digit)
            }
            One(.horizontalWhitespace)
            Capture(as: inodeRef) {
                OneOrMore(.digit)
            }
            One(.horizontalWhitespace)
            Capture(as: pathnameRef) {
                Optionally { OneOrMore(.anyNonNewline) }
            }
        }
    }()

    private static func getMaps(for pid: String) -> String {
        let process = Process()
        let aStdout = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/env")
        process.standardOutput = aStdout
        process.arguments = ["bash", "-c", "cat /proc/\(pid)/maps"]

        try! process.run()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else { fatalError() }
        let result = String(data: aStdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

        return result!
    }

    static func getMap(for pid: String) -> [MapEntry] {
        return getMaps(for: pid).components(separatedBy: "\n").compactMap { line -> MapEntry? in
            guard !line.isEmpty else {
                return nil
            }
            guard let result = try? regex.firstMatch(in: line) else {
                return nil
            }
            return MapEntry(
                start: UInt64(String(result[startRef]), radix: 16)!,
                end: UInt64(String(result[endRef]), radix: 16)!,
                flags: String(result[flagsRef]),
                offset: UInt64(String(result[offsetRef]), radix: 16)!,
                device: (major: UInt64(String(result[deviceMajorRef]), radix: 10)!, minor: UInt64(String(result[deviceMinorRef]), radix: 10)!),
                inode: UInt64(String(result[inodeRef]), radix: 10)!,
                pathname: String(result[pathnameRef]).trimmingCharacters(in: .whitespaces)
            )
        }
    }
}
