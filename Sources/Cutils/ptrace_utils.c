#include <stdlib.h>
#include <string.h>
#include <malloc.h>
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

const void * swift_inspect_bridge__ptrace_peekdata_length(pid_t pid, uint64_t base_address, uint64_t length) {
    void * buffer = malloc(length);
    if (buffer == NULL) {
        // FIXME(stuchlej) Log error
        return NULL;
    }

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

    return buffer;
}
