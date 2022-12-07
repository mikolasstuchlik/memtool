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

        XCTAssertFalse(GlibcAssurances.glibcOccurances(of: .mainArena, in: session.unloadedSymbols!).isEmpty)
        XCTAssertFalse(GlibcAssurances.glibcOccurances(of: .tCache, in: session.unloadedSymbols!).isEmpty)
        XCTAssertFalse(GlibcAssurances.glibcOccurances(of: .rDebug, in: session.unloadedSymbols!).isEmpty)
        XCTAssertFalse(GlibcAssurances.glibcOccurances(of: .errno, in: session.unloadedSymbols!).isEmpty)
    }
}
