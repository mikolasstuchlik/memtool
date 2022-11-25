#include <stdlib.h>
#include <string.h>
#include <malloc.h>

#include <unistd.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <sys/ptrace.h>

#include "include/ptrace_utils.h"

#define WORD 8

typedef union {
    uint64_t word;
    char bytes[WORD];
} word_bytes_t;

long int swift_inspect_bridge__ptrace_attach(pid_t pid) {
    return ptrace(PTRACE_ATTACH, pid);
}

long int swift_inspect_bridge__ptrace_syscall(pid_t pid) {
    return ptrace(PTRACE_SYSCALL, pid);
}

void * _Nullable swift_inspect_bridge__ptrace_peekdata(pid_t pid, uint64_t base_address, uint64_t length) {
    void * buffer = malloc(length);

    if (buffer == NULL) {
        // FIXME(stuchlej) Log error
        return NULL;
    }

    swift_inspect_bridge__ptrace_peekdata_buffer(pid, base_address, length, buffer);
    return buffer;
}

void swift_inspect_bridge__ptrace_peekdata_buffer(pid_t pid, uint64_t base_address, uint64_t length, void * _Nonnull buffer) {
    uint64_t full_pointers = length / WORD;
    uint64_t remainder = length % WORD;

    for (uint64_t i = 0; i < full_pointers; i++) {
        word_bytes_t data;
        data.word = ptrace(PTRACE_PEEKDATA, pid, base_address + i * WORD);
        memcpy(buffer + i * WORD, data.bytes, WORD); 
    }

    if (remainder > 0) {
        word_bytes_t data;
        data.word = ptrace(PTRACE_PEEKDATA, pid, base_address + full_pointers * WORD);
        memcpy(buffer + full_pointers * WORD, data.bytes, remainder); 
    }
}

size_t swift_inspect_bridge__ptrace_peekuser(pid_t pid, int offset_in_words) {
    return ptrace(PTRACE_PEEKUSER, pid, WORD * offset_in_words);
}

long int swift_inspect_bridge__ptrace_get_thread_area(pid_t pid, size_t gdt_index, struct user_desc * _Nonnull buffer) {
    return ptrace(PTRACE_GET_THREAD_AREA, pid, gdt_index, buffer);
}
