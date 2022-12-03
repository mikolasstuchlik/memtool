import XCTest
@testable import MemtoolCore

private let errnoSet = 
#"""
#include <errno.h>

int main(void) {
    errno = 0xabcdef;
    while(1);
    return 0;
}
"""#

final class ThreadLocalStorageTests: XCTestCase {
    func testTbssLoaderOnErrno() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: errnoSet
        )

        sleep(1)

        let session = MemtoolCore.Session(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)

        let libc = session.libcFile!

        let symbolLocation = try TbssSymbolGlibcLdHeuristic(session: session, fileName: libc, tbssSymbolName: "errno")

        let errno = BoundRemoteMemory<Int>(pid: session.pid, load: symbolLocation.loadedSymbolBase)
        XCTAssertEqual(errno.buffer, 0xabcdef)
    }

    func testErrnoDisassemblyHeuristic() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: errnoSet
        )

        sleep(1)

        let session = MemtoolCore.Session(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)

        let libc = session.libcFile!

        let symbolLocation = try GlibcErrnoAsmHeuristic(session: session, glibcPath: libc)

        let errno = BoundRemoteMemory<Int>(pid: session.pid, load: symbolLocation.errnoLocation)
        XCTAssertEqual(errno.buffer, 0xabcdef)
    }

    func testCrossBothHeuristicsSameResult() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: errnoSet
        )

        sleep(1)

        let session = MemtoolCore.Session(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)

        let libc = session.libcFile!

        let errnoDisassembly = try GlibcErrnoAsmHeuristic(session: session, glibcPath: libc)

        let ldPrivate = try TbssSymbolGlibcLdHeuristic(session: session, fileName: libc, tbssSymbolName: "errno")

        XCTAssertEqual(errnoDisassembly.errnoLocation, ldPrivate.loadedSymbolBase)
    }
}
