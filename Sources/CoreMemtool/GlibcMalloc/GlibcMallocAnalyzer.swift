import Cutils

public final class GlibcMallocAnalyzer {
    public let session: Session

    public private(set) var mainArena: BoundRemoteMemory<malloc_state>?
    public private(set) var mainHeap: MapRegion?


    public init(session: Session) {
        self.session = session
    }




}