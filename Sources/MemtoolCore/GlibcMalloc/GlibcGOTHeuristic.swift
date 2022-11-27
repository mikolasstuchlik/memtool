import Cutils

/*
Abbreviations:
TCB - Thread Control Block
PCB - Process Control Block
DTV - Dynamic Thread Vector
TLS - Thread Local Storage
GOT - Global Offset Table
DSO - Dynamic Shared Object
*/

/*
# Objective: Locate `statuc __thread tcache`.

# Resources:
https://fasterthanli.me/series/making-our-own-executable-packer/part-13#c-programs

# Notes:

## Getting the TLS:
(lldb) image lookup -rs 'pthread_self' -v // yields 0x7ffff6896c00 as a base address in RAM
(lldb) disassemble -s 0x7ffff6896c00 -c3
libc.so.6`:
    0x7ffff6896c00 <+0>:  endbr64 
    0x7ffff6896c04 <+4>:  movq   %fs:0x10, %rax
    0x7ffff6896c0d <+13>: retq

RAX is ABI return-value register. The asm code shifts content of FS register and moves it to RAX.
But reading FS yelds 0x0, FS_BASE has to be used. Notice, that FS_BASE is already shifted!

The pthread_self return the pointer to `pthread_t` which is an "opaque" (not in the technical term)
structure, that holds the "id of the calling thread" but this value is equal to the pointer to itself.
It does not corresponds to TID.

Under the hood, the pthread_self points to `tcbhead_t` which is not part of the API. Offset 0 and 
offset 16 should contain the so called "id of the thread," thus pointer to offset 0.

## __thread variables

### errno
The objective is locating `tcache` but we also consider well known variable `errno`. The `errno` name
is only a macro, that expands into something like this `*(void*) __errno_location()` aka. it replaces
occurances of "errno" with call to the "__errno_location" function and dereferencing it's result (this
is done probably in order to hide the location of errno).

Finding and disassembling __errno_location is fairly simple, since it is only "a getter function."
(lldb) image lookup -rs '__errno_location' -v // yields 0x00007ffff7c239d0  as a base address in RAM
(lldb) disassemble -s 0x00007ffff7c239d0
libc.so.6`:
    0x7ffff7c239d0 <+0>:  endbr64
    0x7ffff7c239d4 <+4>:  mov    rax, qword ptr [rip + 0x1d2405]
    0x7ffff7c239db <+11>: add    rax, qword ptr fs:[0x0]
    0x7ffff7c239e4 <+20>: ret

Offset 4 dereferences the sum of RIP (instruction pointer) and magic number 0x1d2405 and stores the 
pointed value in RAX. The address of 0x7ffff7c239d4 + 0x1d2405 should be pointer into GOT for the 
`errno` variable. At the end of the instruction, the RAX should contain the offset of the `errno`
storage in the TLS (probably negative offset to TCB).
Offset 11 sums the offset to `errno` with the pointer to TCB (content of FS).


### tcache
The `tcache` is very similar to `errno`. We just need to find some function where the `tcache`
is used. Such function is `_int_free` in glibc/malloc/malloc.c:4414 where on line 4445 `tcache` is
compared to NULL.

Tapping into LLDB yields followin result: 
(lldb) image lookup -rs 'int_free' -v // yields 0x00007ffff7c239d0  as a base address in RAM
The base is 0x00007ffff7c239d0 but the relevant test is on +91, therefore we call
(lldb) disassemble -s 0x7ffff7c9ddeb -c 5
libc.so.6`_int_free:
    0x7ffff7c9ddeb <+91>:  mov    rax, qword ptr [rip + 0x157f86]
    0x7ffff7c9ddf2 <+98>:  mov    rbp, rdi  
    0x7ffff7c9ddf5 <+101>: mov    rsi, qword ptr fs:[rax]
    0x7ffff7c9ddf9 <+105>: test   rsi, rsi
    0x7ffff7c9ddfc <+108>: je     0x7ffff7c9de3c            ; <+172> at malloc.c:4489:6

Since both pointers in GOT should be near, following result should be reasonably small:
errno                         tcache
(0x7ffff7c239d4 + 0x1d2405) - (0x7ffff7c9ddeb + 0x157f86) = 0x68

(lldb) image list // yields that libc is loaded at 0x00007ffff7c00000

## Approaching heuristic
Discussions [insert link] and papers https://chao-tic.github.io/blog/2018/12/25/tls I was able to find
largely confirm statements above. 

I'm not at the moment aware of better solution, so I'll implement following algorithm:
 - read relative offsets of `tcache`, `errno` and other possible clandidates from `objdump` .tbss
 - find methods which involve said variables and **disassemble them**
 - read their offset in the GOT from disassembly
 - the more variables and methods are available, the better `tcache` <- '_int_free', 'errno' <- '_errno_location'
 - compute tls offsets from GOT - discard misaligned results (dump to stderr)
 - from sane values, compute `tcache` offset

 l_tls_modid
*/
