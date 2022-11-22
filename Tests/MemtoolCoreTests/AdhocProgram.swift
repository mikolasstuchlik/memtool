import Foundation

final class AdhocProgram {
    enum Erorr: Swift.Error {
        case processFailed(line: String, error: String)
    }

    private static let tmpFolder: URL = FileManager.default.temporaryDirectory

    let code: String
    let arguments: String
    let programName: String
    let programPath: URL
    let runningProgram: Process
    let programStdout: Pipe

    init(name: String, code: String, arguments: String = "") throws {
        self.code = code
        self.arguments = arguments
        self.programName = name
        
        let codePath = AdhocProgram.tmpFolder.appendingPathComponent("code" + name + ".c")
        let executablePath = AdhocProgram.tmpFolder.appendingPathComponent("exec" + name)
        self.programPath = executablePath

        try code.write(to: codePath, atomically: false, encoding: .utf8)
        _ = try AdhocProgram.execute(line: "clang \(codePath.path) -o \(executablePath.path) \(arguments)", wait: true)
        try FileManager.default.removeItem(at: codePath)

        self.runningProgram = Process()
        self.programStdout = Pipe()
        
        self.runningProgram.executableURL = self.programPath
        self.runningProgram.currentDirectoryURL = AdhocProgram.tmpFolder
        self.runningProgram.standardOutput = self.programStdout
        self.runningProgram.standardInput = Pipe()
        try self.runningProgram.run()
    }

    func readStdout(until sequence: String) -> String {
        var buffer = Data()
        var output = ""
        while output.isEmpty || output.last != ";" {
            buffer.append(programStdout.fileHandleForReading.availableData)
            output = String(data: buffer, encoding: .utf8) ?? ""
        }
        return output
    }

    private static func execute(line: String, wait: Bool) throws -> String? {
        let process = Process()
        let aStdout = Pipe()
        let aStderr = Pipe()

        var buffer = Data()

        process.executableURL = URL(fileURLWithPath: "/bin/env")
        process.standardOutput = aStdout
        process.arguments = ["bash", "-c", line]

        try! process.run()

        guard wait else {
            return nil
        }

        while process.isRunning {
            buffer.append(aStdout.fileHandleForReading.readDataToEndOfFile())
        }

        guard process.terminationStatus == 0 else {
            throw AdhocProgram.Erorr.processFailed(line: line, error: String(data: aStderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        }

        let result = String(data: buffer, encoding: .utf8)
        return result!
    }

    deinit {
        runningProgram.terminate()
        try? FileManager.default.removeItem(at: programPath)
    }
}