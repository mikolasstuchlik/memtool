#ifndef HEAP_SWIFT_BRIDGE_H
#define HEAP_SWIFT_BRIDGE_H

#include <stddef.h>
#include "heap_utils.h"

size_t macro_NFASTBINS();
size_t macro_NBINS_TOTAL();

struct swift_inspect_bridge__tcache_perthread_t {
    struct tcache_perthread_struct * _Nullable tcache_ptr;
};

struct swift_inspect_bridge__tcache_entry_t {
    struct tcache_entry * _Nullable next;
};

#endif /* HEAP_SWIFT_BRIDGE_H */