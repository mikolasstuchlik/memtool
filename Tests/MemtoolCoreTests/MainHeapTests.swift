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
        memcpy(&ptr[i], "ABCD", sizeof(int));
    }
    return ptr;
}

int * cl2(long long capacity) {
    int * ptr = malloc(capacity * sizeof(int));
    for(long long i = 0; i < capacity; i++) {
        memcpy(&ptr[i], "HIJK", sizeof(int));
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
    int * a = cl2(0x12);
    int * b = cl2(0x102);
    int * c = cl2(0x12);
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

private let freesMain =
#"""
int main(void) {
    void * ptrs[COUNT];

    for(int i = 0; i < COUNT; i++) {
        ptrs[i] = cl(SIZE);
    }

    for(int i = 0; i < FREE; i = i + STEP) {
        free(ptrs[i]);
    }

    while(1) {}
    return 0;
}     

"""#

private let mallocManySmallFrees = commons +
#"""
#define COUNT 10
#define FREE 9
#define STEP 1
#define SIZE 0x12

"""# + freesMain

private let mallocManyFrees = commons +
#"""
#define COUNT 10
#define FREE 10
#define STEP 2
#define SIZE 0x250

"""# + freesMain

final class MainHeapTests: XCTestCase {
    func testMallocNoFrees() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: mallocNoFrees
        )

        let output = program.readStdout(until: ";")

        let pointers = output.components(separatedBy: " ").dropLast().compactMap { UInt($0, radix: 16)}
        XCTAssertEqual(pointers.count, 6)

        let session = MemtoolCore.ProcessSession(pid: program.runningProgram.processIdentifier)
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

    func testMallocWithTCacheFrees() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: mallocInnerFrees
        )

        let output = program.readStdout(until: ";")

        let pointers = output.components(separatedBy: " ").dropLast().compactMap { UInt($0, radix: 16)}
        XCTAssertEqual(pointers.count, 6)

        let session = MemtoolCore.ProcessSession(pid: program.runningProgram.processIdentifier)
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

        XCTAssertEqual(analyzer.exploredHeap[1].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[2].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[3].properties.rebound, .mallocChunk(.heapTCache))
        checkChunk(index: 4, asciiContent: String(repeating: "ABCD", count: 0x12) + #""#)
        checkChunk(index: 5, asciiContent: String(repeating: "ABCD", count: 0x1) + #"\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"#)
        checkChunk(index: 6, asciiContent: String(repeating: "ABCD", count: 0x10) + #"\0\0\0\0\0\0\0\0"#)

        let stdoutChunk = Chunk(pid: program.runningProgram.processIdentifier, baseAddress: analyzer.exploredHeap[7].range.lowerBound)
        XCTAssertTrue(stdoutChunk.content.asAsciiString.hasPrefix(output))
    }

    func testMallocFastbinFrees() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: mallocManySmallFrees
        )

        sleep(3)

        let session = MemtoolCore.ProcessSession(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)

        let analyzer = try GlibcMallocAnalyzer(session: session)
        try analyzer.analyze()

        XCTAssertEqual(analyzer.exploredHeap[1].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[2].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[3].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[4].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[5].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[6].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[7].properties.rebound, .mallocChunk(.heapTCache))
        XCTAssertEqual(analyzer.exploredHeap[8].properties.rebound, .mallocChunk(.heapFastBin))
        XCTAssertEqual(analyzer.exploredHeap[9].properties.rebound, .mallocChunk(.heapFastBin))
        XCTAssertEqual(analyzer.exploredHeap[10].properties.rebound, .mallocChunk(.heapActive))
    }

    func testMallocBinFrees() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: mallocManyFrees
        )

        sleep(3)

        let session = MemtoolCore.ProcessSession(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)

        let analyzer = try GlibcMallocAnalyzer(session: session)
        try analyzer.analyze()

        XCTAssertEqual(analyzer.exploredHeap[1].properties.rebound, .mallocChunk(.heapBin))
        XCTAssertEqual(analyzer.exploredHeap[2].properties.rebound, .mallocChunk(.heapActive))
        XCTAssertEqual(analyzer.exploredHeap[3].properties.rebound, .mallocChunk(.heapBin))
        XCTAssertEqual(analyzer.exploredHeap[4].properties.rebound, .mallocChunk(.heapActive))
        XCTAssertEqual(analyzer.exploredHeap[5].properties.rebound, .mallocChunk(.heapBin))
        XCTAssertEqual(analyzer.exploredHeap[6].properties.rebound, .mallocChunk(.heapActive))
        XCTAssertEqual(analyzer.exploredHeap[7].properties.rebound, .mallocChunk(.heapBin))
        XCTAssertEqual(analyzer.exploredHeap[8].properties.rebound, .mallocChunk(.heapActive))
        XCTAssertEqual(analyzer.exploredHeap[9].properties.rebound, .mallocChunk(.heapBin))
        XCTAssertEqual(analyzer.exploredHeap[10].properties.rebound, .mallocChunk(.heapActive))
    }
}
