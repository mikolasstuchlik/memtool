import XCTest
@testable import MemtoolCore

private let emptyProgram = 
#"""
int main(void) {
    while(1);
    return 0;
}
"""#

final class AssurancesTests: XCTestCase {

    // FIXME: Rewrite symbol getters to allow for parted GLIBC
    func testGlibcSymbols() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: emptyProgram
        )

        let session = MemtoolCore.Session(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)

        let glibcCandidates = session.unloadedSymbols!.filter { key, _ in
            GlibcAssurances.fileFromGlibc(key, unloadedSymbols: session.unloadedSymbols!)
        }
        XCTAssertEqual(glibcCandidates.count, 1)

        let mainArena = session.unloadedSymbols![glibcCandidates.keys.first!]!.contains { 
            $0.name == "main_arena" && $0.segment == .known(.data)
        }

        let tCache = session.unloadedSymbols![glibcCandidates.keys.first!]!.contains { 
            $0.name == "tcache" && $0.segment == .known(.tbss)
        }

        let errno = session.unloadedSymbols![glibcCandidates.keys.first!]!.contains { 
            $0.name == "errno" && $0.segment == .known(.tbss)
        }

        let rDebug = session.unloadedSymbols![glibcCandidates.keys.first!]!.contains { 
            $0.name == "_r_debug" && $0.segment == .known(.tbss)
        }

        XCTAssertTrue(mainArena)
        XCTAssertTrue(tCache)
        XCTAssertTrue(errno)
        XCTAssertTrue(rDebug)
    }
}
