import Cutils

/// Peeks remote process memory and fills the content into existing buffer in this process.
/// - Parameters:
///   - pid: The PID of the peeked process
///   - baseAddress: The base address of the remote peeked memory
///   - buffer: Buffer in local process that will be filles with the data from remote process.
/// Length of loaded memory is determined by the `MemoryLayout.size` of the provided buffer.
/// 
/// - Warning: The buffer has to be C layouted struct! If you use Swift native type, youre in 
/// risk of memory corruption!
public func swift_inspect_bridge__ptrace_peekdata_initialize<T>(_ pid: pid_t, _ baseAddress : UInt, _ buffer: inout T) {
    withUnsafeMutableBytes(of: &buffer) { ptr in
        swift_inspect_bridge__ptrace_peekdata_buffer(
            pid, 
            UInt64(baseAddress), 
            UInt64(MemoryLayout<T>.size), 
            ptr.baseAddress!
        )
    }
}

public func swift_inspect_bridge__ptrace_peekdata_initialize(_ pid: pid_t, _ baseAddress : UInt, _ buffer: inout ContiguousArray<UInt8>) {
    buffer.withUnsafeMutableBufferPointer { ptr in
        swift_inspect_bridge__ptrace_peekdata_buffer(
            pid, 
            UInt64(baseAddress), 
            UInt64(ptr.count), 
            ptr.baseAddress!
        )
    }
}

public func swift_inspect_bridge__ptrace_peekdata_initialize(_ pid: pid_t, _ baseAddress : UInt, _ buffer: UnsafeMutableRawBufferPointer) {
    swift_inspect_bridge__ptrace_peekdata_buffer(
        pid, 
        UInt64(baseAddress), 
        UInt64(buffer.count), 
        buffer.baseAddress!
    )
}
