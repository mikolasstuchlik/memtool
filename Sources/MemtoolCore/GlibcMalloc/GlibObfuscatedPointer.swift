import Cutils

public extension BoundRemoteMemory {
    /// Some linked lists use pointer protection to avoid pointer highjacking. This function
    /// returns "deobfusacted" content of the pointer. Use with causion - some of the pointers
    /// in the same linked lists may not be obfuscated while others are.
    /// 
    /// Source: See macro `PROTECT_PTR` in the Glibc source code [4]
    /// - Parameter field: The key path to the pointer in question. 
    /// - Returns: Deobfustaced value of the pointer (notice, that nil is a valid value).
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
