import Glibc

private struct ErrorStream: TextOutputStream {
    public mutating func write(_ string: String) { fputs(string, stderr) }
}

private var errorStream = ErrorStream()

public func error(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    print(items, separator: separator, terminator: terminator, to: &errorStream)
}
