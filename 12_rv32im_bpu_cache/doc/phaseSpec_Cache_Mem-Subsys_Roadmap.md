# RV32IM Cache / Memory Subsystem Phase Roadmap

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-05 15:52
**Current Version**: v1.4

**Version Changelog**:
- **v1.4** (2026-09-06 16:27): 收紧 Phase 0 S2 为不扩大事务资源/流水级的最小 elastic 优化；明确每拍吞吐成立条件，并将长流、corner matrix和完整性能计数标为 Pending。
- **v1.3** (2026-09-06 16:05): 新增 Phase 0 S2 吞吐收口阶段；在保持单 unanswered request 与可变延迟正确性的同时，要求一拍 backend 上的独立 IF/LSU stream 达到稳态每拍一笔。
- **v1.2** (2026-09-06 14:09): 固化 Cache + backing memory 路线；当前 TCM wrapper 仅为过渡实现，Phase 1/2 由 I/D Cache 直接接管既有 CPU-side 事务接口，最终移除 ITCM/DTCM。
- **v1.1** (2026-09-06 03:37): 明确 `Pending~` 表示排除出当前 Phase；Phase 0 聚焦事务基线并由 MA/MEM 拥有 LSU pending，精确地址/error 延后，新增最终 DTCM 容量与 SRAM macro hardening Phase。
- **v1.0** (2026-09-05 15:52): 初版 Cache / Memory Subsystem 分阶段开发路线，定义从可变延迟存储接口到最终 Cache、BIU、AXI 与 UART 系统拓扑的 Feature Phase。

---

## 1. Scope

本文定义从当前 RV32IM 五级顺序核演进到最终 Cache / BIU / AXI / MMIO 子系统的 Feature Phase。

每个 Phase 只描述该阶段需要实现的功能能力。具体模块划分、FSM、接口细节、SRAM mapping、时序与验证实现应在对应 Feature Task / Work Order 中定义。

最终目标以 [`mainSpec_Cache_Mem-subsys_Feature.md`](mainSpec_Cache_Mem-subsys_Feature.md) 为准。

标记为 `(Pending~)` 的条目明确表示暂时排除出所在 Phase 的实现与验收范围。相关现状分析和后续归属统一记录在 [`dev_log/pending_v12_cache_mem_subsys_deferred_scope.md`](dev_log/pending_v12_cache_mem_subsys_deferred_scope.md)。

最终拓扑固定为 Cache + backing memory，不保留独立 ITCM/DTCM。Phase 0 的 IF/LSU
valid-ready 接口是后续 I/D Cache 的 CPU-side 接口；当前 `mem_itcm`/`mem_dtcm` 只是 Cache
尚未加入时的过渡响应模型。

---

## 2. Phase 0 — Variable-Latency Memory Baseline

### Feature Goal

建立支持可变延迟 memory transaction 的基础接口。

### Features

- IF memory request / response 支持 valid-ready；
- LSU memory request / response 支持 valid-ready；
- request 等待期间 payload 保持稳定；
- load/store 只被接收一次；
- store 不产生重复副作用；
- IF/LSU 能等待 memory response；
- LSU memory transaction pending 由 MA/MEM stage 持有，EX 只产生并通过 EX/MA 传递请求信息；
- 支持 Cacheable、Device/uncached、Unmapped 地址属性；
- 新增或重构的 memory wrapper 先使用 synthesizable RTL model；
- 修正 IMEM/DMEM/UART 精确地址范围；(Pending~，排除出 Phase 0)
- Unmapped access 产生错误；(Pending~，排除出 Phase 0)
- backing DMEM 从当前过渡模型的 16 KiB 扩展到最终 32 KiB；(Pending~，排除出 Phase 0)
- backing memory/cache array 的 SRAM macro/BRAM replacement 与等价性验证；(Pending~，排除出 Phase 0)
- Cache disable 模式继续支持现有程序运行。

---

## 2A. Phase 0 S2 — Memory Transaction Throughput

### Feature Goal

在 Phase 0 可变延迟事务正确性基础上消除 IFU/LSU 固定握手空拍，为后续 Cache hit path
建立单 unanswered request 下的每拍事务吞吐基线。

### Features

- 保持 IF/LSU req/rsp 接口与每通道最多一个 unanswered request；
- 允许旧 response fire 与下一 request fire 同拍 replacement；
- IF returned-payload 与 MA/WB completion 使用 elastic pop/push；
- 一拍 response backend、上下游 ready、无 dependency/redirect/exception 时，独立 IF/LSU stream warm-up 后每拍一笔；
- 保留 variable latency、backpressure、redirect stale drain、RAS ordering、load dependency 与 store exactly-once；
- MA ingress复用现有EX/MA elastic holding，不增加architectural pipeline stage；
- 不增加 MSHR、request FIFO、第二个 request/response buffer或多个 unanswered request；
- 只要求最小短流吞吐、既有定向与公共回归；长流、corner matrix和完整性能计数；(Pending~)
- 运行同口径 CoreMark简化测试并记录改善；严格三版本benchmark-body与硬阈值；(Pending~)
- 不实现 Cache、多个 unanswered request、BIU/AXI 或 deferred memory-map/storage 工作。

详细结构和验收分别见
[`uarch_phase0_s2_ifu_lsu_throughput.md`](uarch_phase0_s2_ifu_lsu_throughput.md) 与
[`dev_log/task_v12_02_phase0_s2_memory_throughput.md`](dev_log/task_v12_02_phase0_s2_memory_throughput.md)。

---

## 3. Phase 1 — Basic I-Cache

### Feature Goal

加入最小 blocking I-Cache。

### Features

- 4 KiB;
- direct-mapped;
- 32 B cache line;
- read-only;
- blocking;
- single outstanding miss;
- whole-line refill;
- CPU-side 直接复用 Phase 0 IF req/rsp 合同;
- 本 Phase 将 `mem_itcm` 重构/重命名为 I-Cache 下游 backing-IMEM model/adapter；验收后不再存在 `mem_itcm` 模块或 ITCM bypass path;
- miss/refill 暂接 backing-memory adapter;
- `fence.i` invalidation;(Pending~)
- redirect 时错误路径 response 不提交;
- refill error 不安装 valid line.

---

## 4. Phase 2 — Basic D-Cache + MMIO Bypass

### Feature Goal

加入基础 D-Cache，并建立 Cacheable / uncached 分流。

### Features

- 4 KiB;
- direct-mapped;
- 32 B cache line;
- blocking;
- single outstanding miss;
- Write-through;
- No-write-allocate;
- load hit/miss;
- store hit/miss;
- byte / halfword / word access;
- DMEM backing-memory region cacheable;
- executable IMEM region 的 LSU data access uncached;
- UART/MMIO uncached;
- Device access bypass D-Cache.
- CPU-side 直接复用 Phase 0 LSU req/rsp 合同；
- 本 Phase 将 `mem_dtcm` 重构/重命名为 D-Cache 下游 backing-DMEM model/adapter；验收后不再存在 `mem_dtcm` 模块或 software-visible DTCM;

---

## 5. Phase 3 — Final L1 Cache

### Feature Goal

升级到最终 I/D Cache 配置。

### I-Cache Features

- 8 KiB;
- 2-way;
- 128 sets;
- 32 B cache line;
- per-set 1-bit round-robin replacement;
- blocking;
- single outstanding miss.

### D-Cache Features

- 8 KiB;
- 2-way;
- 128 sets;
- 32 B cache line;
- per-set 1-bit round-robin replacement;
- Write-back;
- Write-allocate;
- dirty state;
- dirty eviction writeback;
- blocking;
- single outstanding miss.

### Cache Array Features

- synchronous 1RW SRAM semantics;
- SRAM wrapper abstraction;
- 64-bit Data Array access granularity;
- per-way target organization: `512 × 64bit`.

### Performance Features

- I-Cache access/hit/miss counters;
- D-Cache access/hit/miss counters;
- dirty writeback counter;
- uncached access counter;
- miss stall cycle counter.

---

## 6. Phase 4 — BIU + 64-bit AXI

### Feature Goal

将 I/D Cache 与 uncached/MMIO 后端访问统一收敛到 BIU。

### Features

- introduce BIU;
- I-Cache refill -> BIU;
- D-Cache refill -> BIU;
- D-Cache dirty writeback -> BIU;
- uncached/MMIO -> BIU;
- one external AXI Master;
- AXI address width = 32 bit;
- AXI data width = 64 bit;
- 32 B cache line transferred as 4 × 64-bit beats;
- AXI burst for refill/writeback;
- single-beat AXI for MMIO/uncached;
- AXI back-pressure support;
- AXI error propagation;
- single outstanding BIU transaction.

---

## 7. Phase 5 — AXI Interconnect + AXI-to-APB UART

### Feature Goal

形成最终统一的 memory / peripheral system topology。

### Features

- 1-to-N AXI Interconnect;
- IMEM AXI memory slave;
- DMEM AXI memory slave;
- AXI-to-APB bridge;
- UART APB Slave;
- UART mapped as Device/uncached;
- UART access path:
  `LSU -> BIU -> AXI -> AXI-to-APB -> UART`;
- Error Slave;
- exact IMEM/DMEM/UART range decode;
- unmapped AXI access returns `DECERR`;
- APB error propagates to AXI/Core;
- retain sparse physical address map.

---

## 8. Phase 6 — Backing Memory Capacity + SRAM Hardening

### Feature Goal

在 Cache/BIU/系统互连功能稳定后，完成片上后备存储容量和物理 memory implementation 收口。

### Features

- verify no remaining RTL/DV/filelist dependency on transitional `mem_itcm`/`mem_dtcm` names;
- backing DMEM physical capacity: 16 KiB -> 32 KiB;
- full `0x1000_0000` - `0x1000_7FFF` storage without alias;
- replace intermediate backing-memory RTL models through stable adapters;
- backing-memory/cache-array SRAM macro mapping and banking;
- BRAM mapping where applicable;
- RTL / SRAM macro / BRAM contract equivalence;
- update preload, signature access, synthesis library and timing collateral.

---

## 9. Phase Summary

| Phase | Target |
|---|---|
| Phase 0 | Variable-latency memory transaction interface and attribute plumbing |
| Phase 0 S2 | One-unanswered IF/LSU elastic pipeline with 1 transaction/cycle steady-state throughput |
| Phase 1 | 4 KiB direct-mapped blocking I-Cache |
| Phase 2 | 4 KiB direct-mapped WT/NWA D-Cache + MMIO bypass |
| Phase 3 | 8 KiB 2-way I/D Cache, D$ WB/WA + dirty eviction |
| Phase 4 | Shared BIU + one 64-bit AXI Master |
| Phase 5 | AXI Interconnect + AXI-to-APB + UART + exact decode/Error Slave |
| Phase 6 | 32 KiB backing DMEM + backing/cache SRAM/BRAM hardening |

---

## 10. Task Boundary

Each Phase should be split into separate Feature Tasks / Work Orders.

The Phase document does not define:

- RTL module hierarchy;
- FSM states;
- cycle-level timing;
- SRAM macro port mapping;
- detailed arbitration;
- detailed refill/writeback control;
- detailed verification implementation.

These items belong to the corresponding Phase Task.
