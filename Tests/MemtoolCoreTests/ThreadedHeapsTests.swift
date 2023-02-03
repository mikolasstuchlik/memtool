import XCTest
@testable import MemtoolCore

private let commons = 
#"""
#include <stdlib.h>
#include <pthread.h>
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

private let freesMain =
#"""

void *threadexec(void *) {
    void * ptrs[COUNT];

    for(int i = 0; i < COUNT; i++) {
        ptrs[i] = cl(SIZE);
    }

    for(int i = 0; i < FREE; i = i + STEP) {
        free(ptrs[i]);
    }

    while(1);
    return NULL;
}

int main(void) {
    pthread_t threads[THREADS];

    for (int i = 0; i < THREADS; i++) {
        pthread_create(&threads[i], NULL, threadexec, NULL);
    }

    threadexec(NULL);

    while(1);
    return 0;
}     

"""#

private let mallocManySmallFrees = commons +
#"""
#define THREADS 3
#define COUNT 10
#define FREE 9
#define STEP 1
#define SIZE 0x12

"""# + freesMain

private let mallocManyFrees = commons +
#"""
#define THREADS 3
#define COUNT 10
#define FREE 10
#define STEP 2
#define SIZE 0x250

"""# + freesMain

// TODO: Create tests for freed thread arenas
final class ThreadedHeapsTests: XCTestCase {
    func testMallocFastbinFrees() throws {
        let program = try AdhocProgram(
            name: String(describing: Self.self) + #function, 
            code: mallocManySmallFrees
        )

        sleep(3)

        let session = MemtoolCore.ProcessSession(pid: program.runningProgram.processIdentifier)
        session.loadMap()
        session.loadSymbols()
        session.loadThreads()

        XCTAssertNotNil(session.map)
        XCTAssertNotNil(session.unloadedSymbols)
        XCTAssertNotNil(session.symbols)
        XCTAssertEqual(session.threadSessions.count, 3)

        let analyzer = try GlibcMallocAnalyzer(session: session)
        try analyzer.analyze()

        for thread in session.threadSessions {
            let view = try analyzer.view(for: thread)
            XCTAssertEqual(view[0].properties.rebound, .mallocState)
            XCTAssertEqual(view[1].properties.rebound, .heapInfo)
            XCTAssertEqual(view[2].properties.rebound, .mallocChunk(.heapActive)) // unknown chunk
            XCTAssertEqual(view[3].properties.rebound, .mallocChunk(.heapTCache))
            XCTAssertEqual(view[4].properties.rebound, .mallocChunk(.heapTCache))
            XCTAssertEqual(view[5].properties.rebound, .mallocChunk(.heapTCache))
            XCTAssertEqual(view[6].properties.rebound, .mallocChunk(.heapTCache))
            XCTAssertEqual(view[7].properties.rebound, .mallocChunk(.heapTCache))
            XCTAssertEqual(view[8].properties.rebound, .mallocChunk(.heapTCache))
            XCTAssertEqual(view[9].properties.rebound, .mallocChunk(.heapTCache))
            XCTAssertEqual(view[10].properties.rebound, .mallocChunk(.heapFastBin))
            XCTAssertEqual(view[11].properties.rebound, .mallocChunk(.heapFastBin))
            XCTAssertEqual(view[12].properties.rebound, .mallocChunk(.heapActive))
        }
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

        for thread in session.threadSessions {
            let view = try analyzer.view(for: thread)
            XCTAssertEqual(view[0].properties.rebound, .mallocState)
            XCTAssertEqual(view[1].properties.rebound, .heapInfo)
            XCTAssertEqual(view[2].properties.rebound, .mallocChunk(.heapActive)) // unknown chunk
            XCTAssertEqual(view[3].properties.rebound, .mallocChunk(.heapBin))
            XCTAssertEqual(view[4].properties.rebound, .mallocChunk(.heapActive))
            XCTAssertEqual(view[5].properties.rebound, .mallocChunk(.heapBin))
            XCTAssertEqual(view[6].properties.rebound, .mallocChunk(.heapActive))
            XCTAssertEqual(view[7].properties.rebound, .mallocChunk(.heapBin))
            XCTAssertEqual(view[8].properties.rebound, .mallocChunk(.heapActive))
            XCTAssertEqual(view[9].properties.rebound, .mallocChunk(.heapBin))
            XCTAssertEqual(view[10].properties.rebound, .mallocChunk(.heapActive))
            XCTAssertEqual(view[11].properties.rebound, .mallocChunk(.heapBin))
            XCTAssertEqual(view[12].properties.rebound, .mallocChunk(.heapActive))
        }
    }
}
