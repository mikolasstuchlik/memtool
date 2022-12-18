import Foundation
import RegexBuilder
import _StringProcessing

extension Symbolication {

    private static let firstLine = "SYMBOL TABLE:"

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
            buffer.append(aStdout.fileHandleForReading.availableData)
        }

        guard process.terminationStatus == 0 else {
            error("Error: Map failed to load. Path: \(process.executableURL?.path ?? ""), arguments: \(process.arguments ?? []), termination status: \(process.terminationStatus), stderr: \(String(data: aStderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")") 
            return ""
        }
        let result = String(data: buffer, encoding: .utf8)

        return result!
    }

    public static func loadSymbols(for file: String) -> [UnloadedSymbolInfo] {
        // This is just a workaround, so the program does not output Warnings where parsing is expected to fail
        var iteratingSymbolTable = false
        return getElfDescription(file: file).components(separatedBy: "\n").compactMap { line -> UnloadedSymbolInfo? in
            if line.hasPrefix(firstLine) {
                iteratingSymbolTable = true
                return nil
            }
            guard !line.isEmpty else {
                iteratingSymbolTable = false
                return nil
            }
            guard iteratingSymbolTable else {
                return nil
            }
            guard let result = try? regex.firstMatch(in: line) else {
                error("Warning: Symbol for file \(file) failed to match regex: \(line)")
                return nil
            }
            return UnloadedSymbolInfo(
                file: file,
                location: UInt(String(result[locationRef]), radix: 16)!,
                flags: SymbolFlags(rawValue: String(result[flagsRef])),
                segment: SymbolSection(rawValue: String(result[segmentRef])),
                size: UInt(String(result[sizeRef]), radix: 16)!,
                name: String(result[nameRef]).trimmingCharacters(in: .whitespacesAndNewlines)
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
            location: UInt(String(result[locationRef]), radix: 16)!,
            flags: SymbolFlags(rawValue: String(result[flagsRef])),
            segment: SymbolSection(rawValue: String(result[segmentRef])),
            size: UInt(String(result[sizeRef]), radix: 16)!,
            name: String(result[nameRef]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
