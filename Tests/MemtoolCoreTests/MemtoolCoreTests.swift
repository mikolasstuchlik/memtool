import XCTest
@testable import MemtoolCore

extension Session {
    var libcFile: String? {
        map?.compactMap { region -> String? in
            if case let .file(file) = region.properties.pathname {
                return file
            }
            return nil
        }.first { file in
            unloadedSymbols?[file]?.contains { $0.name.hasPrefix("GLIBC_2.") && $0.segment == .known(.abs) } == true
        }
    }
}

final class MemtoolCoreTests: XCTestCase {
    func testExample() throws {
        
    }
}
