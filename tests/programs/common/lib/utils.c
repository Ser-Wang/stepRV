#include <stdint.h>

#include "../include/utils.h"



// uint64_t get_cycle_value()
// {
//     uint64_t cycle;

//     cycle = read_csr(cycle);
//     cycle += (uint64_t)(read_csr(cycleh)) << 32;

//     return cycle;
// }

uint64_t get_cycle_value()
{
    // The only purpose of the high-low-high sequence is to prevent an
    // inconsistent 64-bit value when cycle[31:0] rolls over from 0xffffffff
    // to 0 between reading cycle and cycleh. Retry if the two high reads differ.
    uint32_t cycle_lo;
    uint32_t cycle_hi;
    uint32_t cycle_hi_check;

    do {
        cycle_hi = read_csr(cycleh);
        cycle_lo = read_csr(cycle);
        cycle_hi_check = read_csr(cycleh);
    } while (cycle_hi != cycle_hi_check);

    return ((uint64_t)cycle_hi << 32) | cycle_lo;
}

void busy_wait(uint32_t us)
{
    uint64_t tmp;
    uint32_t count;

    count = us * CPU_FREQ_MHZ;
    tmp = get_cycle_value();

    while (get_cycle_value() < (tmp + count));
}
