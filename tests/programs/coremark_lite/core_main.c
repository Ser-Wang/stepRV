/*
 * Lightweight CoreMark bring-up entry.
 *
 * This is not an official CoreMark run. It keeps the CoreMark port layer,
 * UART printing, cycle timer, static memory block, and list initialization,
 * while skipping the full benchmark scheduler and matrix/state workloads.
 */
#include "coremark.h"

#if (MEM_METHOD != MEM_STATIC)
#error "core_main_lite.c expects MEM_STATIC."
#endif

static ee_u8 static_memblk[TOTAL_DATA_SIZE];

#if MAIN_HAS_NOARGC
MAIN_RETURN_TYPE
main(void)
{
    int   argc = 0;
    char *argv[1];
#else
MAIN_RETURN_TYPE
main(int argc, char *argv[])
{
#endif
    core_results results;
    list_head *  node;
    ee_u16       crc = 0;
    ee_u32       count = 0;
    CORE_TICKS   total_time;

    portable_init(&results.port, &argc, argv);

    results.seed1      = 0;
    results.seed2      = 0;
    results.seed3      = 0x66;
    results.iterations = 1;
    results.execs      = ID_LIST;
    results.memblock[0] = static_memblk;
    results.memblock[1] = static_memblk;
    results.memblock[2] = 0;
    results.memblock[3] = 0;
    results.size        = TOTAL_DATA_SIZE;
    results.crc         = 0;
    results.crclist     = 0;
    results.crcmatrix   = 0;
    results.crcstate    = 0;
    results.err         = 0;

    ee_printf("CoreMark Lite Start\n");
    ee_printf("Data size         : %lu\n", (long unsigned)results.size);

    start_time();
    results.list = core_list_init(results.size, results.memblock[1], results.seed1);

    node = results.list;
    while (node != 0)
    {
        crc = crc16(node->info->idx, crc);
        crc = crc16(node->info->data16, crc);
        count++;
        node = node->next;
    }
    stop_time();

    total_time = get_time();

    ee_printf("List nodes        : %lu\n", (long unsigned)count);
    ee_printf("List crc          : 0x%04x\n", crc);
    ee_printf("Total ticks       : %lu\n", (long unsigned)total_time);
    ee_printf("CoreMark Lite Done\n");

    portable_fini(&results.port);

    return MAIN_RETURN_VAL;
}
