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

        print(analyzer)
        // XCTAssertEqual(analyzer.exploredHeap[1].properties.rebound, .mallocChunk(.heapTCache))
        // XCTAssertEqual(analyzer.exploredHeap[2].properties.rebound, .mallocChunk(.heapTCache))
        // XCTAssertEqual(analyzer.exploredHeap[3].properties.rebound, .mallocChunk(.heapTCache))
        // XCTAssertEqual(analyzer.exploredHeap[4].properties.rebound, .mallocChunk(.heapTCache))
        // XCTAssertEqual(analyzer.exploredHeap[5].properties.rebound, .mallocChunk(.heapTCache))
        // XCTAssertEqual(analyzer.exploredHeap[6].properties.rebound, .mallocChunk(.heapTCache))
        // XCTAssertEqual(analyzer.exploredHeap[7].properties.rebound, .mallocChunk(.heapTCache))
        // XCTAssertEqual(analyzer.exploredHeap[8].properties.rebound, .mallocChunk(.heapFastBin))
        // XCTAssertEqual(analyzer.exploredHeap[9].properties.rebound, .mallocChunk(.heapFastBin))
        // XCTAssertEqual(analyzer.exploredHeap[10].properties.rebound, .mallocChunk(.heapActive))
    }
}
