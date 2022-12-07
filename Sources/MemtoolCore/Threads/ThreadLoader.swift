import Foundation

public final class ThreadLoader {
    public let pid: Int32

    public private(set) var threads: [Int32]
    public init(pid: Int32) {
        self.pid = pid
        let taskString = ThreadLoader.getTids(pid: pid)
        let tids = taskString.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .compactMap { UInt($0) }
            .map { Int32(Int(bitPattern: $0)) }
            .filter { $0 != pid }
        self.threads = tids
    }

    private static func getTids(pid: Int32) -> String {
        let process = Process()
        let aStdout = Pipe()

        var buffer = Data()

        process.executableURL = URL(fileURLWithPath: "/bin/env")
        process.standardOutput = aStdout
        //process.standardError = aStderr
        // `objdump -tL [file]`
        // objdump  : program for dumping object file information
        // -t       : dump symbol table
        // -L       : follow links (for example when binary is stripped) 1313
        process.arguments = ["bash", "-c", "ls /proc/\(pid)/task/" ]

        try! process.run()

        while process.isRunning {
            buffer.append(aStdout.fileHandleForReading.availableData)
        }

        guard process.terminationStatus == 0 else { 
            error("Error: thread loader failes with error code \(process.terminationStatus)")
            return ""
        }
        let result = String(data: buffer, encoding: .utf8)

        return result!
    }

}