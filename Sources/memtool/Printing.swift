import CoreMemtool
import Foundation

protocol CLIPrint {
    var cliPrint: String { get }
}

extension UInt64: CLIPrint {
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
            return "Region(range: \(range.cliPrint), properties: \(printable.cliPrint))"
        } else {
            return "Region(range: \(range.cliPrint), properties: \(properties))"
        }
    }
}

extension MapInfo: CLIPrint {
    var cliPrint: String {
        "MapInfo(flags: \(flags.stringValue), offset: \(offset.cliPrint), device major: \(device.major), device minor: \(device.minor), inode: \(inode), pathname: \(pathname.rawValue))"
    }
}

extension UnloadedSymbolInfo: CLIPrint {
    var cliPrint: String {
        "UnloadedSymbolInfo(name: \(name), file: \(file), location: \(location.cliPrint), flags: \(flags.rawValue), segment: \(segment.rawValue), size: \(size.cliPrint))"
    }
}

extension LoadedSymbolInfo: CLIPrint {
    var cliPrint: String {
        "LoadedSymbolInfo(name: \(name), flags: \(flags.rawValue), segment: \(segment.rawValue))"
    }
}

extension Session: CLIPrint {
    var cliPrint: String {
"""
=== Session [\(pid)]
Map:
\(map?.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")

Unloaded Symbols:
\(unloadedSymbols?.flatMap({ $1 }).map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")

Symbols:
\(symbols?.map(\.cliPrint).joined(separator: "\n") ?? "[not loaded]")
=== 
"""
    }
}
