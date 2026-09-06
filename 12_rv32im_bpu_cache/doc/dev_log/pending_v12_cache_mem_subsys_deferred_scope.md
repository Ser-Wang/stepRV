# v12 Cache / Memory Subsystem 搁置项与后续实现记录

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 03:37
**Current Version**: v1.3

**Version Changelog**:
- **v1.3** (2026-09-06 19:45): 记录Phase0 S2后 `rv32ui-p-ld_st` 新增FAIL/timeout、验收影响与后续恢复入口；按用户决策暂时不继续debug。
- **v1.2** (2026-09-06 16:27): 收录 Phase 0 S2 为快速功能迭代而搁置的长流、随机反压、RAS/dependency corner matrix、完整性能计数与严格 CoreMark 对比。
- **v1.1** (2026-09-06 14:09): 记录 Cache + backing memory 最终决策；撤销独立 DTCM 扩容/双 bank 作为目标，改为移除过渡 TCM wrapper，并在 backing-memory/cache-array 边界完成容量与物理实现收口。
- **v1.0** (2026-09-06 03:37): 从 Phase 0 工单迁入精确地址、Unmapped error、32 KiB DTCM 和 SRAM macro 分析，记录当前接受偏差、后续 Phase 归属与验收要点。

---

关联文档：

- [`../mainSpec_Cache_Mem-subsys_Feature.md`](../mainSpec_Cache_Mem-subsys_Feature.md)
- [`../phaseSpec_Cache_Mem-Subsys_Roadmap.md`](../phaseSpec_Cache_Mem-Subsys_Roadmap.md)
- [`task_v12_01_phase0_variable_latency_memory_baseline.md`](task_v12_01_phase0_variable_latency_memory_baseline.md)
- [`task_v12_02_phase0_s2_memory_throughput.md`](task_v12_02_phase0_s2_memory_throughput.md)

## 1. 记录目的

本文集中记录已经识别、但按当前开发节奏明确排除出 Phase 0 的工作。这样 Phase 0 工单只聚焦 variable-latency transaction 基线，同时保留后续修正所需的现状证据、设计约束和测试清单。

`Pending~` 在 Phase Roadmap 中表示“当前 Phase 暂不实现”，不表示问题不存在，也不表示最终 Feature Spec 被修改。

后续架构已经确定为 Cache + backing memory，不保留独立 ITCM/DTCM。因此本文早期记录的
TCM 容量、banking 与 macro 信息仅作为当前过渡 RTL 的迁移依据，不再代表最终模块规划。

## 2. 当前允许保留的临时偏差

### 2.1 地址 decode 不是精确范围

当前 `de/soc/soc_bus.sv` 只比较 `i_mem_addr[31:28]`：

```text
0x0xxx_xxxx -> ITCM
0x1xxx_xxxx -> DTCM
0x3xxx_xxxx -> UART
```

因此每个逻辑窗口被扩大到 256 MiB，越界地址会继续选中目标，并由 SRAM 低位 index 形成镜像。它与最终规格的精确窗口不一致：

```text
IMEM : 0x0000_0000 - 0x0000_7fff
DMEM : 0x1000_0000 - 0x1000_7fff
UART : 0x3000_0000 - 0x3000_0fff
```

Phase 0 允许继续使用当前粗粒度 decode，只需建立 `Cacheable/Device/Unmapped` 属性语义和不会死锁的 completion。精确上下界、access size 跨界检查和 alias 消除暂不验收。

### 2.2 Unmapped access 尚无架构错误

当前 core 只实现 instruction/load/store address-misaligned 等 EX 期异常，没有后端 instruction/load/store access fault 通路；`soc_bus` 对未选中地址也没有 error response。

Phase 0 的过渡行为为：

- unmapped load 返回一次零数据 completion；
- unmapped store 返回一次无目标副作用 completion；
- unsupported IF 地址返回一次 benign NOP completion；
- 不得因暂不报错而让 valid-ready transaction 永久 pending。

以上只用于 Phase 0 降低复杂度，不是最终架构保证。

### 2.3 过渡 DTCM model 物理容量仍为 16 KiB

当前配置为：

```text
DTCM_BASE = 0x1000_0000
DTCM_SIZE = 0x0000_4000
DTCM_DEPTH = 4096 words
```

最终 Feature Spec 的 backing DMEM window 为 32 KiB，但当前程序 linker 的 RAM LENGTH 为 16 KiB，已有回归不会访问上半 16 KiB。因此在完成 Cache/BIU/系统拓扑之前，暂时保留 16 KiB 过渡 model，不要求 `0x1000_4000`～`0x1000_7fff` 真正具有独立物理存储。

不得只把 `DTCM_SIZE` 改为 32 KiB 而保留单个 4096-word storage；这种修改会让宽地址被截断并形成上下半区镜像。

### 2.4 SRAM macro/BRAM 替换搁置

现有物理实现资源包括：

- ITCM：`smic55_8192x32_2p`，容量恰为 32 KiB；
- DTCM：`smic55_4096x32_1rw`，容量为 16 KiB；
- 相应 SRAM wrapper、macro model/db 和 Vivado BRAM 分支。

从 Phase 0 开始，新增或重构的 memory 先以 synthesizable RTL array/model 实现，并保留 wrapper 边界。当前不要求：

- 例化或验证 SRAM macro；
- 维护 RTL/macro/BRAM 三模式等价；
- 为最终 32 KiB backing DMEM 实现双 4096×32 bank；
- 修改 TB 的双 bank preload/signature 层次化路径；
- 运行 macro timing、banking 或 BRAM model 测试。

## 3. 后续 Phase 归属

| 搁置项 | 计划归属 | 说明 |
|---|---|---|
| 精确 IMEM/DMEM/UART decode | Phase 5 或其独立前置 task | 与最终 AXI interconnect、Error Slave 和 sparse address map 一并收口 |
| Unmapped/backend error 与 access fault | Phase 5 或其独立前置 task | 建立 instruction/load/store error propagation 和精确 trap |
| 删除 `mem_itcm`/`mem_dtcm` 与 TCM 语义 | Phase 1 / Phase 2 | I/D Cache 分别接管 Phase 0 CPU-side req/rsp，同 Phase 将过渡 arrays 重构/重命名为 backing-memory model/adapter |
| backing DMEM 16 KiB -> 32 KiB | Phase 6 | 最终 backing-memory physical capacity hardening |
| backing memory/cache array -> SRAM macro/BRAM | Phase 6 | 在功能稳定后做 adapter/wrapper replacement 和等价性验证 |

若后续 Cache phase 在进入 Phase 5 前必须依赖精确属性或错误传播，应单独创建前置 task，不得静默把这些内容重新塞回 Phase 0 工单。

## 4. 后续精确地址与错误实现要求

### 4.1 精确 decode

- 使用完整 base/size 上下界判断，禁止只比较高 nibble。
- 一次 access 的全部 byte 都必须落在同一合法 region；halfword/word 不得跨窗口末端。
- IF 只允许从 executable IMEM 成功取指。
- LSU routing 最终为：DMEM cacheable、IMEM data access uncached、UART device/uncached、其他 unmapped。
- UART 最终只支持 aligned 32-bit MMIO；非法 size/alignment 不得产生 UART 写副作用。
- 地址属性定义应集中、可复用，避免 core、Cache、BIU 和 interconnect 各自散落不同常量。

### 4.2 精确 access fault

| 失败类型 | `mcause` | `mepc` | `mtval` |
|---|---:|---|---|
| Instruction access fault | 1 | 故障 instruction PC | 故障取指地址 |
| Load access fault | 5 | 故障 load PC | load effective address |
| Store/AMO access fault | 7 | 故障 store PC | store effective address |

- failed refill 或 memory operation 不得被报告成功。
- 错误 load 禁止 rd writeback；错误 store 对本地非法目标必须零副作用。
- fault redirect、CSR trap state 和流水线 flush 必须绑定故障指令唯一 completion/commit fire，不能因 response/WB 反压重复。
- instruction error 需要与 PC/instruction metadata 对齐传到异常解析点，并隔离普通 opcode 副作用。
- 后续 AXI `SLVERR/DECERR` 和 APB `PSLVERR` 应复用同一 response-error/precise-trap 通路。

## 5. 后续 32 KiB Backing DMEM 与物理实现方案

目标逻辑容量：

```text
0x1000_0000 - 0x1000_7fff
8192 words × 32 bit = 32 KiB
```

最终对象是 Cache 下游的 backing DMEM，不是 software-visible DTCM。实现时必须删除或重命名
`mem_dtcm`，并通过 backing-memory adapter 接入 AXI memory slave/仿真 memory model。

可选物理实现：

1. 使用真实 `8192x32` 1RW macro；或
2. 例化两个现有 `smic55_4096x32_1rw`，用局部 word address 最高位选择 bank。

若 backing-memory adapter 使用双 bank，必须满足：

- request fire 时只 enable/write 被选 bank；
- 同步 read 的 bank select 打一拍，与 macro 返回数据对齐；
- 未选 bank 不得写；
- `0x1000_0000+x` 与 `0x1000_4000+x` 可保存不同数据；
- reset 不要求初始化 memory 内容；
- RTL、SRAM macro 与 BRAM wrapper 对外 latency/enable/read-during-write 合同一致。

Phase 6 应同步更新 filelist、综合 macro db、TB preload、signature helper、层次化路径和 memory 配置文档，并删除最终设计对 `mem_itcm`/`mem_dtcm` 层次名的依赖。

## 6. 搁置测试清单

以下测试不属于 Phase 0，后续对应 task 必须重新纳入：

- IMEM：`0x0000_0000`、`0x0000_7ffc` 成功；`0x0000_8000` 和远端同 nibble alias 失败。
- DMEM：`0x1000_0000`、`0x1000_3ffc`、`0x1000_4000`、`0x1000_7ffc` 独立可用；`0x1000_8000` 失败。
- UART：合法寄存器 word access 成功；`0x3000_1000`、subword 和 misaligned access 失败且无副作用。
- 从 DMEM/UART/Unmapped 取指得到 cause=1；Unmapped load/store 得到 cause=5/7，并检查 `mepc/mtval`。
- 对 backing DMEM 上下两个 bank 同 offset 写不同 pattern，读回证明无镜像。
- generic RTL、SRAM macro 和 BRAM 三种实现的容量、read latency、byte mask 与 READ_FIRST 行为等价。
- refill/backend error、response backpressure 和 trap commit 同拍组合不产生重复 redirect、CSR write 或架构副作用。

在这些测试真正执行前，开发记录只能标记为 `Deferred/Not Run`，不得写成 PASS。

## 7. Phase 0 S2 搁置的增强验证与性能闭环

Phase 0 S2 当前只保留16-entry IF/LSU短流、既有Phase0/BPU/RAS定向用例、CoreMark简化测试和公共
回归，以尽快进入 Cache feature。以下已经识别的增强验证不属于 S2 当前关闭条件：

### 7.1 长流与吞吐压力

- 64/256条及更长的连续 IF request/response/IF-ID stream；
- 64/256笔独立 load、store、load/store mixed stream；
- 长流中的每拍 response/request replacement 和 buffer pop/push replacement计数；
- 长时间运行下 PC、instruction、rd、size/sign、target select和response metadata的逐笔scoreboard；
- 同拍replacement时对所有store target、byte mask和read-data组合做完整验证。

### 7.2 Backpressure 与控制 corner matrix

- request-ready、response-valid、IF/ID-ready、MA/WB-ready分别以及交叉随机反压；
- response delay 1、2、7拍及随机有限延迟；
- redirect发生在request等待、outstanding等待、response replacement和buffer full等每个边界；
- stale response、redirect/recovery、reset/flush和新request同拍的组合；
- memory response与年轻non-memory completion collision的所有slot占用组合。

### 7.3 RAS 与 dependency corner

- back-to-back call/return、call/call/return/return及栈满/空边界；
- older IF/ID RAS action与younger return response同拍，分别验证preview和显式bubble实现；
- load-use、load-branch、load-store-data、load-address及多条依赖链；
- response当拍forwarding、completion后forwarding和WB反压的交叉组合。

当前 S2 仍必须保证功能正确：实现若不做same-cycle RAS preview，应对真实RAS-dependent pair插入
bubble；pending load数据不可用时必须保留现有interlock。搁置的是穷举覆盖，不是允许错误。

### 7.4 完整性能观测

- pre-Phase0、Phase0、Phase0 S2在同一binary、iterations、clock和BPU/RAS配置下的三版本对比；
- benchmark `start_time()` 到 `stop_time()` 的cycles/time、committed instruction、IPC；
- IF/LSU request、response、pipeline output数量；
- request-ready、response-wait、IF-buffer、EX/MA holding、MA/WB、dependency、redirect和RAS bubble cycles；
- Phase0 S2不超过1.10× pre-Phase0 benchmark-body基线的严格门槛。

若后续性能异常、准备签核当前Feature，或进入更复杂Cache hit/miss/refill优化时，应重新建立独立DV/
性能收口工单纳入这些项目。在执行前，记录为 `Deferred/Not Run`，不得写成 PASS。

## 8. Phase 0 S2 已知功能问题：`rv32ui-p-ld_st`

### 8.1 当前现象

- 用户于2026-09-06手动运行 `type=isa group=rv32ui`，反馈 `rv32ui-p-ld_st` FAIL。
- AI在统一 `work/my-RISCV-Projs/sim` 路径运行单例时，用例在仿真时间
  `1_000_000_000 ps` timeout，未进入PASS/FAIL handler。
- 该结果是超出允许项 `ma_data` 的新增failure，因此Phase0 S2不满足公共验收，不得记录为PASS或
  Completed。

用例内容简介见
[`../../../tests/rv_tests_isa_new/README_cases.md`](../../../tests/rv_tests_isa_new/README_cases.md)。它主要覆盖
对齐byte/halfword/word load/store、符号/零扩展、write mask，以及紧邻store→load、load→store和
load result立即作为下一访存地址/数据的依赖链。

### 8.2 已排除与尚未确认

- 初版S2 MAU曾误增加实际ingress register，造成普通ALU结果和forwarding晚一拍；该问题已经通过删除
  `r_ingress_*`、直接复用EX existing valid-ready holding修正，不能把它当作当前 `ld_st` 已知根因。
- Phase0/S2短流与BPU/RAS诊断性定向曾通过，但没有覆盖 `ld_st` 的完整load-use/store-load序列；且其
  DV路径生成物已经清理，不能替代公共回归。
- 当前尚未确认卡住的具体PC，也未确认根因位于same-cycle store/load replacement、load-use
  interlock/forwarding、response metadata/data对齐或其他流水控制。

### 8.3 后续恢复条件与最小调试入口

按用户决策，本bug当前停止debug。恢复时至少应：

1. 只在 `work/my-RISCV-Projs/sim` 路径运行 `ld_st` 单例并取得卡住PC及IF/EX/MA/WB valid-ready状态；
2. 从 `test_2` 的 `sb -> lb -> sb -> lb` 和加载指针后立即作为store/load base的序列开始逐拍检查；
3. 对照每笔 `mem_req_fire`、`mem_rsp_fire`、MA/WB rd/data以及DTCM target write，定位首个偏差；
4. 修复后先确认 `ld_st` PASS，再由用户重跑 `rv32ui`，且只允许既有 `ma_data` FAIL。

在用户明确恢复该问题前，状态保持 `Deferred — Known Functional Regression`。
