import Foundation
import RegexBuilder
import _StringProcessing

extension Map {

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

    private static func getMaps(for pid: Int32) -> String {
        let process = Process()
        let aStdout = Pipe()
        let aStderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/env")
        process.standardOutput = aStdout
        process.standardError = aStderr
        // more info in `man proc`
        process.arguments = ["bash", "-c", "cat /proc/\(pid)/maps"]

        try! process.run()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            error("Error: Map failed to load. Path: \(process.executableURL?.path ?? ""), arguments: \(process.arguments ?? []), termination status: \(process.terminationStatus), stderr: \(String(data: aStderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")") 
            return "" 
        }
        let result = String(data: aStdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

        return result!
    }

    public static func getMap(for pid: Int32) -> [MapRegion] {
        return getMaps(for: pid).components(separatedBy: "\n").compactMap { line -> MapRegion? in
            guard !line.isEmpty else {
                return nil
            }
            guard let result = try? regex.firstMatch(in: line) else {
                error("Warning: Map failed to match regex: \(line)")
                return nil
            }
            return MapRegion(
                range: UInt(String(result[startRef]), radix: 16)!..<UInt(String(result[endRef]), radix: 16)!, 
                properties: MapInfo(
                    flags: MapFlags(rawValue: String(result[flagsRef])),
                    offset: UInt(String(result[offsetRef]), radix: 16)!,
                    device: (major: UInt(String(result[deviceMajorRef]), radix: 10)!, minor: UInt(String(result[deviceMinorRef]), radix: 10)!),
                    inode: UInt(String(result[inodeRef]), radix: 10)!,
                    pathname: MapPath(rawValue: String(result[pathnameRef]).trimmingCharacters(in: .whitespacesAndNewlines))
                )
            )
        }
    }
}
