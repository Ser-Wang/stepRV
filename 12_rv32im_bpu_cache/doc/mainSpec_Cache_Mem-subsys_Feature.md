# RV32IM Cache / Memory Subsystem Feature Spec

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-05 15:52
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-09-06 14:09): 固化最终采用 Cache + backing memory，明确移除 ITCM/DTCM 架构与命名，Phase 0 事务接口作为 Cache CPU-side 接口直接继承。
- **v1.0** (2026-09-05 15:52): 初版 Cache / Memory Subsystem 最终功能规格，定义 I/D Cache、SRAM 组织、BIU、AXI、MMIO、UART 与系统总线目标能力。

---

## 1. Scope

本文定义 RV32IM 五级顺序核最终目标的 Cache、BIU、AXI、MMIO 与片上存储子系统 Feature。

本文只描述最终目标能力，不描述中间演进过程或具体 RTL/uArch 实现。

架构决策：最终系统采用 **I/D Cache + backing memory**，不保留独立 ITCM/DTCM。
Phase 0 建立的 IF/LSU request/response valid-ready 合同分别成为 I-Cache/D-Cache 的
CPU-side 合同；当前 `mem_itcm`/`mem_dtcm` 仅为过渡 RTL backend，不是最终模块，也不原地扩展成 Cache。

---

## 2. Target Architecture

```text
                               RV32IM Core
          +--------------------------------------------------+
          |                                                  |
 IFU ---> | I-Cache -- refill ------------------------+      |
          |                                           |      |
 LSU ---> | memory region / attribute decode          |      |
          |       |                                   |      |
          |       +-- Cacheable --> D-Cache ----------+      |
          |       |                  | refill/writeback      |
          |       +-- Device ------> uncached/MMIO ----+     |
          |       `-- Unmapped ----> access fault            |
          |                                           |      |
          |                                          BIU     |
          +-------------------------------------------+-------+
                                                      |
                                               one AXI Master
                                               32-bit address
                                               64-bit data
                                                      |
                                                      v
                                      +---------------------------+
                                      | 1-to-N AXI Interconnect   |
                                      +------+------------+-------+
                                             |            |
                                        AXI memory   AXI-to-APB
                                          slaves        bridge
                                                          |
                                                     APB fabric
                                                          |
                                                        UART
```

---

## 3. L1 Cache Configuration

| Feature | I-Cache | D-Cache |
|---|---:|---:|
| Capacity | 8 KiB | 8 KiB |
| Associativity | 2-way | 2-way |
| Cache line | 32 B | 32 B |
| Sets | 128 | 128 |
| Addressing | PIPT | PIPT |
| Replacement | per-set 1-bit round-robin | per-set 1-bit round-robin |
| Miss handling | Blocking | Blocking |
| Outstanding miss | 1 | 1 |
| Write policy | Read-only | Write-back |
| Write miss policy | N/A | Write-allocate |
| Dirty eviction | N/A | Supported |

32-bit address partition:

```text
31                     12 11             5 4               0
+------------------------+----------------+------------------+
|       Tag[31:12]       | Index[11:5]    | LineOffset[4:0]  |
+------------------------+----------------+------------------+
|        20 bits         |     7 bits     |      5 bits      |
+------------------------+----------------+------------------+
```

Address field definition:

- `addr[31:12]` : Tag, 20 bits;
- `addr[11:5]`  : Set Index, 7 bits;
- `addr[4:0]`   : Line Offset, 5 bits.

Within the 32 B cache line:

- `addr[4:2]` : word offset in the cache line;
- `addr[1:0]` : byte offset in the word.

---

## 4. I-Cache

I-Cache supports:

- 8 KiB, 2-way, 128 sets, 32 B cache line;
- blocking, single outstanding miss;
- whole-line refill;
- read-only operation;
- per-set 1-bit round-robin replacement;
- `fence.i` invalidation;
- refill error must not install a valid line;
- instruction access fault for invalid/unmapped accesses.

I-Cache hit accesses remain local to the Cache. Only refill requests enter the BIU.

---

## 5. D-Cache

D-Cache supports:

- 8 KiB, 2-way, 128 sets, 32 B cache line;
- blocking, single outstanding miss;
- write-back;
- write-allocate;
- byte / halfword / word load-store;
- dirty state tracking;
- dirty victim writeback before replacement;
- whole-line refill;
- per-set 1-bit round-robin replacement;
- access error propagation on backend failure.

Device/MMIO accesses do not enter or allocate D-Cache.

---

## 6. Cache SRAM Organization

Cache Tag/Data arrays use synchronous **1RW SRAM** semantics.

The physical SRAM macro organization is hidden behind a wrapper. Cache control logic depends only on logical set / way / line access semantics.

### 6.1 Data Array

Each way stores:

```text
128 sets × 32 B = 4 KiB
```

Target physical organization:

```text
Way0 Data SRAM : 512 × 64 bit, 1RW
Way1 Data SRAM : 512 × 64 bit, 1RW
```

One 32 B cache line occupies four consecutive 64-bit entries:

```text
chunk 0 : 64 bit
chunk 1 : 64 bit
chunk 2 : 64 bit
chunk 3 : 64 bit
```

Logical entry addressing:

```text
SRAM entry = {set_index, chunk_index}
```

where `chunk_index` is 2 bits.

### 6.2 Tag / Metadata

Each set maintains:

- two tags;
- two valid bits;
- one replacement bit.

D-Cache additionally maintains one dirty bit per way.

Reset clears valid state; Data SRAM contents do not require reset initialization.

---

## 7. AXI Interface

The Core exposes **one AXI Master** through the BIU.

AXI parameters:

| Parameter | Value |
|---|---:|
| Address width | 32 bit |
| Data width | 64 bit |
| Cache-line transfer | 4 beats × 64 bit |
| Outstanding transaction | 1 |

BIU request sources:

- I-Cache refill;
- D-Cache refill;
- D-Cache dirty writeback;
- uncached load/store;
- MMIO load/store.

Cache-line refill and writeback use 4-beat transfers. MMIO/uncached accesses use single-beat transactions.

The BIU supports AXI back-pressure and propagates AXI errors to the Core.

---

## 8. Memory Attributes

The physical address space distinguishes:

- Cacheable memory;
- Device / uncached;
- Unmapped.

LSU routing:

```text
Cacheable -> D-Cache
Device    -> bypass D-Cache -> BIU
Unmapped  -> load/store access fault
```

MMIO accesses must not allocate Cache lines or update dirty state.

---

## 9. SoC Bus Topology

The BIU AXI Master connects to a 1-to-N AXI Interconnect.

Target AXI slaves:

- executable backing-memory adapter;
- data backing-memory adapter;
- AXI-to-APB bridge;
- Error Slave.

The AXI-to-APB bridge connects the UART to the system address space.

UART access path:

```text
load/store
 -> LSU
 -> Device/uncached path
 -> BIU
 -> AXI
 -> AXI Interconnect
 -> AXI-to-APB bridge
 -> UART
```

UART is not accessed through a private LSU-to-APB path.

---

## 10. Address Map

| Address Range | Region | Attribute |
|---|---|---|
| `0x0000_0000` - `0x0000_7FFF` | IMEM | Cacheable / Executable |
| `0x1000_0000` - `0x1000_7FFF` | DMEM | Cacheable |
| `0x3000_0000` - `0x3000_0FFF` | UART / APB window | Device / Uncached |
| Other | Unmapped | Error |

Address decode uses exact region ranges. Unmapped addresses must not alias into SRAM.
IMEM/DMEM 是 backing-memory 地址区域，不表示存在 software-visible ITCM/DTCM bypass path。

---

## 11. UART / MMIO

UART is memory-mapped and accessed through normal RISC-V load/store instructions.

Target behavior:

- Device / uncached region;
- bypass D-Cache;
- aligned 32-bit MMIO access;
- single-beat AXI transaction;
- AXI-to-APB protocol conversion;
- APB error propagated back to the Core;
- MMIO load/store completes only after the corresponding system response.

---

## 12. Error Handling

The subsystem supports:

- instruction/load/store access fault for invalid accesses;
- AXI `SLVERR/DECERR` propagation;
- APB `PSLVERR` propagation through AXI-to-APB;
- Error Slave returning `DECERR` for unmapped AXI accesses;
- failed refill must not install a valid Cache line;
- failed memory operation must not be reported as successful.

---

## 13. Concurrency Boundary

The final target remains:

```text
blocking Cache
single outstanding Cache miss
single outstanding BIU transaction
one external AXI Master
```

No requirement for:

- non-blocking Cache;
- MSHR;
- prefetch;
- Store Buffer;
- Victim Buffer;
- multiple AXI outstanding transactions;
- separate I/D AXI Masters.
