import Foundation
import Cutils

import Glibc

@main
public struct memtool {
    public static func main() {
        var session: Session?
        while let line = readLine() {
            let comps = line.components(separatedBy: " ")
            switch comps.first {
            case "map":
                session?.maps.forEach { print($0) }
            case "arena":
                print(session!.mainArenaBuffer.display())
            case "load":
                let address = UInt64(comps[1], radix: 16)!
                session?.loadChunk(at: address)
            case "display":
                session?.displayChunks()
            case "attach":
                let pid = Int32(comps[1], radix: 10)!
                session = Session(pid: pid)
            case "drop":
                session = nil
            default:
                print("Unknown")
            }
        }
    }
}
