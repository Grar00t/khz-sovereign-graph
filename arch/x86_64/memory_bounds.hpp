#pragma once
#include <cstddef>
#include <cstdint>

extern "C" int khz_bounds_check(std::uintptr_t address, std::uintptr_t begin, std::uintptr_t end);

namespace khz {
inline bool in_bounds(const void* p, const void* begin, const void* end) noexcept {
    const auto address = reinterpret_cast<std::uintptr_t>(p);
    const auto first = reinterpret_cast<std::uintptr_t>(begin);
    const auto last = reinterpret_cast<std::uintptr_t>(end);
    return khz_bounds_check(address, first, last) == 0;
}
}
