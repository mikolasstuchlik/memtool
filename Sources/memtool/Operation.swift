import CoreMemtool

struct Context {
    let operations: [Operation]
    var session: Session?
    var glibcMallocExplorer: GlibcMallocAnalyzer?
    var shouldStop: Bool

    mutating func resolve(input: String) {
        if operations.first(where: { $0.resolve(input, &self) }) == nil {
            print("Error: Unrecognized input \(input)")
        }
    }
}

struct Operation {
    let keyword: String
    let help: String
    let resolve: (String, inout Context) -> Bool
}
