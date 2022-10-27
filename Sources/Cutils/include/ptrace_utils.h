#ifdef __linux__
#ifndef linux_bridge_H
#define  linux_bridge_H

#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <sys/reg.h>
#include <stdint.h>

long int swift_inspect_bridge__ptrace_attach(pid_t pid);
long int swift_inspect_bridge__ptrace_syscall(pid_t pid);
const void * swift_inspect_bridge__ptrace_peekdata_length(pid_t pid, uint64_t base_address, uint64_t length);

#endif /* linux_bridge_H */
#endif /* __linux__ */
