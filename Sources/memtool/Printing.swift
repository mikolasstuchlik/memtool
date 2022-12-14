import MemtoolCore
import Foundation

protocol CLIPrint {
    var cliPrint: String { get }
}

extension UInt: CLIPrint {
    var cliPrint: String {
        String(format: "0x%016lx", self)
    }
}

extension MemoryRange: CLIPrint {
    var cliPrint: String {
        lowerBound.cliPrint + " ..< " + upperBound.cliPrint
    }
}

extension MemoryRegion: CLIPrint {
    var cliPrint: String {
        if let printable = properties as? CLIPrint {
            return "Region(range: \(range.cliPrint), properties: \(printable.cliPrint))".removingMemtoolMentions()
        } else {
            return "Region(range: \(range.cliPrint), properties: \(properties))".removingMemtoolMentions()
        }
    }
}

extension MapInfo: CLIPrint {
    var cliPrint: String {
        "MapInfo(flags: \(flags.stringValue), offset: \(offset.cliPrint), device major: \(device.major), device minor: \(device.minor), inode: \(inode), pathname: \(pathname.rawValue))".removingMemtoolMentions()
    }
}

extension UnloadedSymbolInfo: CLIPrint {
    var cliPrint: String {
        "UnloadedSymbolInfo(name: \(name), file: \(file), location: \(location.cliPrint), flags: \(flags.rawValue), segment: \(segment.rawValue), size: \(size.cliPrint))".removingMemtoolMentions()
    }
}

extension LoadedSymbolInfo: CLIPrint {
    var cliPrint: String {
        "LoadedSymbolInfo(name: \(name), flags: \(flags.rawValue), segment: \(segment.rawValue))".removingMemtoolMentions()
    }
}

extension ProcessSession: CLIPrint {
    var cliPrint: String {
"""
=== Session [\(pid)]
Map:
\(map?.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")

Unloaded Symbols:
\(unloadedSymbols?.flatMap({ $1 }).map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")

Symbols:
\(symbols?.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")

Threads:
\(threadSessions.map(\.tid).map(String.init(_:)).joined(separator: " "))
=== 
""".removingMemtoolMentions()
    }
}

extension Chunk: CLIPrint {
    var cliPrint: String {
"""
=== Chunk [\(content.segment.lowerBound.cliPrint)]
Header:
\(header)
Payload:
\({
    content.buffer.map { String(format: "0x%02x", $0) }.joined(separator: " ")
}())
===
""".removingMemtoolMentions()
    }
}

private extension String {
    func removingMemtoolMentions() -> String {
        self.replacingOccurrences(of: "MemtoolCore.", with: "")
    }
}