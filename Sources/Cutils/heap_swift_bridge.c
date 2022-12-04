#include "include/heap_swift_bridge.h"

size_t macro_NFASTBINS() {
    return NFASTBINS;
}
size_t macro_NBINS_TOTAL() {
    return NBINS_TOTAL;
}

void * _Nullable swift_inspect_bridge__macro_PROTECT_PTR(const void * _Nonnull pos, const void * _Nonnull ptr) {
    return PROTECT_PTR(pos, ptr);
}

// Implementation based on reverse engineering of `REVEAL_PTR`
void * _Nullable swift_inspect_bridge__macro_REVEAL_PTR(const void * _Nonnull ptr, const void * _Nonnull ptr_addr) {
    return PROTECT_PTR(ptr_addr, ptr);
}

// We can not use this implementation, because the macro uses the address of the `ptr`
// void * _Nonnull swift_inspect_bridge__macro_REVEAL_PTR(void * _Nonnull ptr) {
//     return REVEAL_PTR(ptr);
// }
