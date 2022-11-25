#ifdef __linux__
#ifndef linux_bridge_H
#define  linux_bridge_H

#include <sys/types.h>
#include <sys/reg.h>
#include <stdint.h>
#include <asm/ldt.h>
#include <error.h>

long int swift_inspect_bridge__ptrace_attach(pid_t pid);
long int swift_inspect_bridge__ptrace_syscall(pid_t pid);
void * _Nullable swift_inspect_bridge__ptrace_peekdata(pid_t pid, uint64_t base_address, uint64_t length);
void swift_inspect_bridge__ptrace_peekdata_buffer(pid_t pid, uint64_t base_address, uint64_t length, void * _Nonnull buffer);

size_t swift_inspect_bridge__ptrace_peekuser(pid_t pid, int offset_in_words);
long int swift_inspect_bridge__ptrace_get_thread_area(pid_t pid, size_t gdt_index, struct user_desc * _Nonnull buffer);

#endif /* linux_bridge_H */
#endif /* __linux__ */
