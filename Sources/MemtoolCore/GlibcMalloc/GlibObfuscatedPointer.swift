import Cutils

public extension BoundRemoteMemory {
    func deobfuscate<U>(pointer field: KeyPath<T, U>) -> UnsafeMutableRawPointer? {
        guard MemoryLayout<U>.size == MemoryLayout<UnsafeRawPointer>.size else {
            error("Error: Type \(U.self) of size \(MemoryLayout<U>.size) can not be cast to `UnsafeRawPointer`")
            return nil
        }

        guard let offset = MemoryLayout<T>.offset(of: field).flatMap(UInt.init(_:)) else {
            error("Error: Offset of field \(field) of chunk \(self) can not be calculated")
            return nil
        }

        let pseudoPointer = UnsafeRawPointer(bitPattern: UInt(segment.lowerBound + offset))!

        return withUnsafePointer(to: buffer) { ptr in
            let fieldPtr = ptr.pointer(to: field)!
            return fieldPtr.withMemoryRebound(to: UnsafeRawPointer.self, capacity: 1) {
                swift_inspect_bridge__macro_REVEAL_PTR($0.pointee, pseudoPointer)
            }
        }
    }
}
