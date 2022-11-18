import Foundation
import Cutils
import Glibc


public final class Session {
    public let pid: Int32

    public var map: [MapRegion]?
    public var unloadedSymbols: [UnloadedSymbolInfo]?
    public var symbols: [SymbolRegion]?

    public init(pid: Int32) {
        swift_inspect_bridge__ptrace_attach(pid)
        self.pid = pid
    }

    deinit {
        swift_inspect_bridge__ptrace_syscall(pid)
    }
}
