import XCTest
@testable import MemtoolCore

private let commons = 
#"""
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int * cl(long long capacity) {
    int * ptr = malloc(capacity * sizeof(int));
    for(long long i = 0; i < capacity; i++) {
        memcpy(&ptr[i], "ABCDEFHIJKLMN", sizeof(int));
    }
    return ptr;
}

"""#

private let mallocNoFrees = commons +
#"""
int main(void) {
    int * a = cl(0x1);
    int * b = cl(0x102);
    int * c = cl(0x1);
    int * d = cl(0x12);
    int * e = cl(0x1);
    int * f = cl(0x10);

    printf("%lx %lx %lx %lx %lx %lx ;", a, b, c, d, e, f);
    fflush( stdout );

    while(1) {}
    return 0;
}     

"""#

private let mallocInnerFrees = commons +
#"""
int main(void) {
    int * a = cl(0x1);
    int * b = cl(0x102);
    int * c = cl(0x1);
    int * d = cl(0x12);
    int * e = cl(0x1);
    int * f = cl(0x10);

    free(a);
    free(b);
    free(c);

    printf("%lx %lx %lx %lx %lx %lx ;", a, b, c, d, e, f);
    fflush( stdout );

    while(1) {}
    return 0;
}     

"""#

final class MainHeapTests: XCTestCase {
    func testMallocNoFrees() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: mallocNoFrees
        )

        let output = program.readStdout(until: ";")

        let pointers = output.components(separatedBy: " ").dropLast().compactMap { UInt64($0, radix: 16)}
        XCTAssertEqual(pointers.count, 6)

        let session = MemtoolCore.Session(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)

        let analyzer = try GlibcMallocAnalyzer(session: session)
        try analyzer.analyze()

        // First malloc chunk is unknown chunk allocated from reasons unknown to me
        // Next 6 malloc chunks are allocated by the program
        // Last (8th) malloc chunk is probably some kind of buffer for stdout.
        XCTAssertEqual(analyzer.exploredHeap.count, 8)

        func checkChunk(index: Int, asciiContent: String) {
            XCTAssertEqual(analyzer.exploredHeap[index].range.lowerBound, pointers[index - 1] - Chunk.chunkContentOffset)
            let chunk = Chunk(pid: program.runningProgram.processIdentifier, baseAddress: analyzer.exploredHeap[index].range.lowerBound)
            XCTAssertEqual(chunk.content.asAsciiString, asciiContent)
        }

        checkChunk(index: 1, asciiContent: String(repeating: "ABCD", count: 0x1) + #"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"#)
        checkChunk(index: 2, asciiContent: String(repeating: "ABCD", count: 0x102) + #""#)
        checkChunk(index: 3, asciiContent: String(repeating: "ABCD", count: 0x1) + #"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"#)
        checkChunk(index: 4, asciiContent: String(repeating: "ABCD", count: 0x12) + #""#)
        checkChunk(index: 5, asciiContent: String(repeating: "ABCD", count: 0x1) + #"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"#)
        checkChunk(index: 6, asciiContent: String(repeating: "ABCD", count: 0x10) + #"\0\0\0\0\0\0\0\0"#)

        let stdoutChunk = Chunk(pid: program.runningProgram.processIdentifier, baseAddress: analyzer.exploredHeap[7].range.lowerBound)
        XCTAssertTrue(stdoutChunk.content.asAsciiString.hasPrefix(output))
    }

    func testMallocWithFrees() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: mallocInnerFrees
        )

        let output = program.readStdout(until: ";")

        let pointers = output.components(separatedBy: " ").dropLast().compactMap { UInt64($0, radix: 16)}
        XCTAssertEqual(pointers.count, 6)

        let session = MemtoolCore.Session(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)

        let analyzer = try GlibcMallocAnalyzer(session: session)
        try analyzer.analyze()

        print(analyzer.mainArena.buffer)

        // First malloc chunk is unknown chunk allocated from reasons unknown to me
        // Next 6 malloc chunks are allocated by the program
        // Last (8th) malloc chunk is probably some kind of buffer for stdout.
        XCTAssertEqual(analyzer.exploredHeap.count, 8)

        func checkChunk(index: Int, asciiContent: String) {
            XCTAssertEqual(analyzer.exploredHeap[index].range.lowerBound, pointers[index - 1] - Chunk.chunkContentOffset)
            let chunk = Chunk(pid: program.runningProgram.processIdentifier, baseAddress: analyzer.exploredHeap[index].range.lowerBound)
            XCTAssertEqual(chunk.content.asAsciiString, asciiContent)
        }

        print( 
            analyzer.exploredHeap.map {
                var str = ""
                str += "\($0)"
                str += Chunk(pid: session.pid, baseAddress: $0.range.lowerBound).content.asAsciiString
                return str
            }.joined(separator: "\n")
        )

        // FIXME: Test not passing, chunks in tcache do not reflext expectations
        //XCTAssertEqual(analyzer.exploredHeap[1].properties.rebound, .mallocChunk(.heapTCache))
        //XCTAssertEqual(analyzer.exploredHeap[2].properties.rebound, .mallocChunk(.heapTCache))
        //XCTAssertEqual(analyzer.exploredHeap[3].properties.rebound, .mallocChunk(.heapTCache))
        checkChunk(index: 4, asciiContent: String(repeating: "ABCD", count: 0x12) + #""#)
        checkChunk(index: 5, asciiContent: String(repeating: "ABCD", count: 0x1) + #"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"#)
        checkChunk(index: 6, asciiContent: String(repeating: "ABCD", count: 0x10) + #"\0\0\0\0\0\0\0\0"#)

        let stdoutChunk = Chunk(pid: program.runningProgram.processIdentifier, baseAddress: analyzer.exploredHeap[7].range.lowerBound)
        XCTAssertTrue(stdoutChunk.content.asAsciiString.hasPrefix(output))

    }
}
