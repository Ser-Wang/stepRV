# task_v12_02：Phase 0 S2 IFU / LSU 事务吞吐优化工单

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 16:05
**Current Version**: v1.4
**Status**: Completed — Public Regression Accepted, CoreMark_10 78 ms (2026-09-06 20:10) | Implementation Complete — User Acceptance Found Two Regressions (2026-09-06 19:45) | Implementation Complete — User Acceptance Pending (2026-09-06 16:47) | Ready for Execution (2026-09-06 16:31) | Ready for Review after Scope Reduction (2026-09-06 16:27) | Ready for Review (2026-09-06 16:05)

**Version Changelog**:
- **v1.4** (2026-09-06 20:10): 合并记录并修复用户验收发现的 `rv32ui-p-ld_st` 与 `I-MISALIGN_LDST-01` 两项问题；单例复测及用户手动公共回归验收通过，CoreMark_10 为78 ms，工单关闭。
- **v1.3** (2026-09-06 19:45): 用户开始手动公共验收，发现 `rv32ui-p-ld_st` 与 `I-MISALIGN_LDST-01` 两项功能问题，进入定位修复。
- **v1.2** (2026-09-06 16:47): 完成 IFU/MAU elastic throughput RTL与两个16-entry短流测试；Phase0和BPU/RAS轻量定向及v12全SoC编译通过，用户保留rvtests、Compliance、CoreMark和完整验收运行。
- **v1.1** (2026-09-06 16:27): 按 review 限定 IFU 每拍吞吐成立条件，明确 MA ingress 复用现有 EX/MA holding 而非新增流水级，区分 LSU transaction throughput、completion latency/throughput，降低 RAS preview 优先级，禁止扩大事务资源，并将长流及绝大部分 corner DV 移入 deferred 文档。
- **v1.0** (2026-09-06 16:05): 基于 Phase 0 实现与 CoreMark 性能回退分析，定义 IFU/LSU 单 outstanding 下的 elastic pipeline、稳态每拍一笔事务目标及专项验收。

---

功能依据：

- [`../mainSpec_Cache_Mem-subsys_Feature.md`](../mainSpec_Cache_Mem-subsys_Feature.md)
- [`../phaseSpec_Cache_Mem-Subsys_Roadmap.md`](../phaseSpec_Cache_Mem-Subsys_Roadmap.md)
- [`../uarch_phase0_s2_ifu_lsu_throughput.md`](../uarch_phase0_s2_ifu_lsu_throughput.md)
- [`task_v12_01_phase0_variable_latency_memory_baseline.md`](task_v12_01_phase0_variable_latency_memory_baseline.md)
- [`rule_ai_acceptance.md`](rule_ai_acceptance.md)

## 1. 任务目标

在不改变 Phase 0 IF/LSU req/rsp 外部合同、仍保持每通道最多一个 unanswered request 的前提下，
消除 IFU 与 MAU 当前互斥状态机引入的固定空拍。在 backend request ready持续为 1、固定一拍
response、下游 ready持续为 1、无 redirect/exception、无 data dependency 或 RAS-dependent bubble 的
steady-state 条件下，使独立 hit-like 访问达到：

- IFU warm-up 后每拍一个 request、每拍一个 response、每拍向 IF/ID 交付一条指令；
- LSU warm-up 后每拍一个独立 memory request和每拍一个 response；MA/WB completion允许相对
  response 增加固定 pipeline latency，但 warm-up 后的 completion throughput 仍为每拍一笔；
- response A 被接收与 request B 被接收可以发生在同一边沿；
- response/completion buffer 的旧 payload 被消费与新 payload 写入可以发生在同一边沿；
- variable latency、request/response backpressure、redirect、RAS、load dependency 和 store exactly-once
  正确性不回退。

本任务解决的是 Phase 0 事务 owner 内部吞吐，不加入 Cache。Phase 1/2 的 I/D Cache 仍直接接管
本任务优化后的 CPU-side req/rsp 接口。当前 transitional backing memory 不演化为 Cache，最终仍按
既定决策移除 ITCM/DTCM 名义并形成 Cache + backing memory。

## 2. 问题定义与完成判据

用户报告同一 CoreMark 简化测试的仿真时间由约 70 ms 增至约 172 ms。分析显示当前 backend 已允许
response pop 与下一 request push 同拍发生，但 producer/owner 没有利用该能力：

| 路径 | 当前结构 | 当前一拍 backend 下的典型间隔 | 本任务目标 |
|---|---|---:|---:|
| IFU | request、outstanding、response buffer 串行复用控制 | IF/ID 约每 3 拍一条 | warm-up 后 1 条/拍 |
| MAU | `EMPTY -> REQ -> WAIT_RSP -> DONE` 互斥 FSM | memory request 约每 3 拍一笔 | warm-up 后 1 笔/拍 |

任务完成满足以下最小判据：

1. **确定性微架构验收**：第 8 节短 zero-wait/one-cycle directed stream 达到无固定空拍的
   1 transaction/cycle；这是本吞吐工单的主判据。
2. **功能验收**：Phase 0 现有基础定向用例、BPU/RAS 现有用例和公共 ISA/Compliance 回归不回退。
3. **应用观察**：用同一 CoreMark 简化测试确认相对当前约 172 ms 有明显改善并记录结果；本轮不把
   70 ms pre-Phase0 数值或 1.10× 阈值设为硬性关闭条件。

若 70 ms 与 172 ms 是从仿真启动到退出的总时长，必须先把 UART 输出等 benchmark 外时间从两边
剥离后才能作严格性能结论。三版本同口径 benchmark-body、详细 stall breakdown 与硬阈值暂时搁置，
见 [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)。

## 3. 范围与非目标

### 3.1 本任务范围

- IFU request/outstanding/returned-payload 三部分的并行推进与 elastic replacement；
- IF response、IF/ID buffer、next-PC generation、redirect stale drain 和 RAS 顺序的一致性；
- 现有 EX/MA holding、LSU outstanding metadata、MA/WB completion 三个逻辑位置的并行推进；
- 不破坏现有 pending load hazard/forwarding、in-order completion 与 non-memory path；
- one-cycle backend 同拍 response-pop/request-push 的数据与 metadata 对齐；
- 最小短流吞吐观测与 CoreMark 简化测试记录。

### 3.2 非目标

- 不实现 I-Cache、D-Cache、cache hit/miss、refill、eviction 或 cache counter；
- 不实现多个 unanswered IF/LSU request、乱序 response 或 transaction ID；
- 不增加 MSHR、request FIFO、第二个 request buffer、第二个 response/completion buffer或预取队列；
- 不增加新的 architectural pipeline stage；
- 不实现 BIU、AXI、APB 或新的仲裁拓扑；
- 不修正精确地址范围、Unmapped error、16 KiB backing DMEM alias/容量；
- 不进行 SRAM macro/BRAM replacement；
- 不改变 ISA、BPU 算法、RAS 深度、UART 寄存器或软件可见 memory map。

长流、随机反压矩阵、详尽 redirect/RAS/dependency corner、完整性能计数等验证也暂不纳入本轮关闭条件。
上述 deferred 内容统一见
[`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)。

## 4. 共同事务合同与 slot 不变量

沿用 Phase 0 定义：

```text
req_fire = req_vld && req_rdy
rsp_fire = rsp_vld && rsp_rdy
```

“单 outstanding”在本任务中精确定义为最多一个 request 已 fire 但 response 尚未 fire；它不禁止：

```text
edge N: response A fire + request B fire
```

边沿 N 前 unanswered=A，边沿 N 后 unanswered=B，计数始终为 1。实现必须保持：

- `unanswered_count` 只能为 0 或 1；
- 没有 response replacement 时，旧 unanswered 清除后才允许新 request 成立；
- 有 response replacement 时，旧 metadata 被 response A 使用，新 metadata 原子替换为 request B；
- request valid 等 ready、response valid 等 ready时 payload 保持稳定；
- 每个 request 对应且只对应一个 response，metadata 不串笔；
- redirect/flush/reset 不产生 ghost response、重复 completion 或重复 store。

详细当前/目标结构、时序图和信号职责见
[`uarch_phase0_s2_ifu_lsu_throughput.md`](../uarch_phase0_s2_ifu_lsu_throughput.md)，本工单不重复维护两份
微架构说明。

## 5. IFU 必须实现的行为

### 5.1 Elastic fetch pipeline

- 保持最多一个 unanswered IF request，同时允许一个已返回但尚未进入 ID 的 response payload 与其并存。
- returned-payload slot 必须支持 `pop old + push new` 同拍 replacement。
- backend 一拍返回 A 时，使用 A 对应的 PC/prediction metadata 和 response instruction 生成 successor，
  允许 `if_rsp_fire(A) + if_req_fire(B)` 同拍发生。
- 只有在 `if_req_rdy=1`、固定一拍 response、`if_id_rdy=1`、无 redirect/exception、无
  RAS-dependent bubble 时才要求每拍 fire。registered response buffer可以保留一次启动延迟，
  但上述 steady-state 下不得在相邻 instruction之间插入固定气泡。
- 任一 downstream/back-end stall 解除后应立即恢复，不得再额外经过只用于状态切换的空闲拍。

### 5.2 Redirect、prediction 与 RAS

- 保留 Phase 0 对已 fire、不可取消的旧路径 request 的 stale-response drain；stale instruction 不得进入 ID。
- redirect 与 response/request replacement 同拍时，redirect 优先，禁止为错误 successor 发起新 request。
- 只有真实 `if_id_fire` 的 instruction 才更新 speculative RAS；stale response 不更新 RAS。
- 若 older buffered instruction A 在同拍 `if_id_fire` 并 push/pop RAS，而新 response B 是 return，
  必须保证 B 不使用错误 RAS top。以下两种实现地位相同：提供 same-cycle preview/旁路，或识别该
  RAS-dependent pair 并插入一个显式 bubble。
- 本任务不要求为吞吐强制增加 RAS preview 组合路径；普通顺序流和 BTB-neutral stream 不得因 RAS
  处理而降速。
- resolved redirect/recovery 优先级、prediction metadata 与 instruction/PC 的对应关系保持不变。

## 6. LSU/MAU 必须实现的行为

### 6.1 复用既有流水边界形成逻辑 slot

这里的 MA ingress 不是新增 pipeline stage或新增一深 FIFO，而是现有 EX/MA valid-ready register及其
holding capability在 MAU 入口处的逻辑称呼。数据路径仍是：

```text
EXU -> existing EX/MA elastic holding -> MA transaction owner -> existing MA/WB holding -> WBU
```

实现应让以下三个既有逻辑位置可并行推进，允许采用不同 RTL 编码但语义必须等价：

| Slot | 必须持有的内容 | 释放/替换条件 |
|---|---|---|
| Existing EX/MA holding | EX/MA instruction 与完整 LSU payload | 成功转为 request或 completion；若本拍释放，允许同拍接受下一 EX payload |
| LSU outstanding | 唯一已发 memory transaction 的 addr/type/size/rd 等 metadata | 对应 response fire；允许同拍由下一 request metadata 替换 |
| MA/WB completion | formatted result、rd、write enable 和 instruction metadata | `ma_wb_fire`；允许同拍写入旧指令的新 completion |

不得为了拆 slot 增加新的 architectural stage、额外 ingress register或 pipeline latency；也不得继续用
单个互斥 `REQ/WAIT_RSP/DONE` 状态阻止既有边界并行推进。

### 6.2 连续 stream 与 in-order

- memory response A fire 与 ingress 中下一 memory request B fire可以同拍。
- completion A 被 WBU 接受与 response B 产生新 completion 可以同拍。
- 连续互不依赖的 aligned load/store 在 one-cycle backend 下 warm-up 后，transaction层的
  `mem_req_fire` 与 `mem_rsp_fire` 各自保持每拍一笔。
- architectural completion可以相对 `mem_rsp_fire` 晚固定一拍或若干固定 pipeline latency；在
  `ma_wb_rdy=1` 时，warm-up 后相邻 `ma_wb_fire` 仍应保持每拍一笔，不要求 response与completion同拍。
- 年轻 non-memory instruction 不得越过 older memory transaction 完成；发生 completion collision 时，
  年轻 instruction 保留在 ingress，等待 older response先进入/离开 completion。
- 连续 non-memory instruction 仍保持既有一拍 pipeline throughput，不得因 LSU slot 常驻产生固定气泡。
- CSR、BPU update、redirect 和 exception side effect 仍绑定唯一有效 pipeline transfer。

### 6.3 Load dependency 与 store side effect

- hazard logic 必须识别尚未得到数据的 outstanding load rd 与年轻 instruction source register。
- 可以在 response 当拍提供 formatted load-data forwarding，或在数据进入 completion 后再放行依赖者；
  load-use dependency 允许产生必要 bubble，但不得全局阻塞无依赖 instruction stream。
- 不得让依赖 instruction 在 pending load value 可用前捕获旧 operand。
- misaligned load/store 不产生 memory request，cause=4/6 行为保持。
- target store write只绑定唯一 `mem_req_fire && mem_req_write && target_selected`；response 与 retry/hold
  不得再次产生写副作用。

## 7. 预期文件范围

| 文件 | 预期工作 |
|---|---|
| `de/core/ifu.sv` | fetch slots 并行推进、response buffer replacement、同拍 next request、redirect/stale 顺序 |
| `de/core/ras_dual_full_stack.sv` | 可选；只有选择 preview 方案时修改，允许 IFU 对 RAS-dependent pair 插 bubble |
| `de/core/mau.sv` | 让既有 EX/MA holding、outstanding、MA/WB holding 并行推进，不新增流水级/事务 FIFO |
| `de/core/ctrl_hazard.sv`、`de/core/core.sv` | 如需要，补齐 pending-load interlock/forwarding 和连接，不迁移 transaction ownership |
| `de/periphs/mem_itcm.sv`、`de/soc/soc_bus.sv` | 只在必要时修正同拍 pop/push metadata/data 对齐；不扩大地址/容量范围 |
| `dv/*` | 新增最小短流 throughput/replacement 测试，并复用现有 Phase0/BPU/RAS 回归 |
| `doc/uarch_phase0_s2_ifu_lsu_throughput.md` | 实现后按最终信号/slot 更新微架构说明 |
| `doc/dev_log/log_dev_v12.md` | 完成时倒序记录实现、吞吐证据、性能与验收结果 |

实现若需要修改超出上述列表的流水线控制文件，可以纳入，但交付记录必须说明原因和所有权未发生变化。

## 8. 最小定向 DV 与吞吐验收

### 8.1 IFU steady-state stream

建立 16 条连续 aligned、无 redirect/exception、无 RAS action、BTB-neutral instruction短流：

- `if_req_rdy=1`，backend 对每个 request 固定下一拍给 response，`if_id_rdy=1`；
- warm-up 后相邻 `if_req_fire` 间隔必须连续为 1 cycle；
- warm-up 后相邻 `if_rsp_fire` 间隔必须连续为 1 cycle；
- warm-up 后相邻 `if_id_fire` 间隔必须连续为 1 cycle；
- request address、response instruction、IF/ID PC 顺序严格对应，无跳号、重复或 metadata 串笔；
- 单 unanswered counter始终不超过 1；
- 至少观察到一次 `if_rsp_fire(A) + if_req_fire(B)` 和一次 response buffer `pop A + push B`。

redirect、backpressure 与 RAS 功能不新增穷举组合，只要求现有 Phase0 frontend/BPU/RAS 定向用例继续
PASS。长流和 corner matrix见 deferred 文档。

### 8.2 LSU steady-state stream

建立 16 笔互不依赖的 aligned memory operation短流；load或load/store mixed任选一种能直接验证
response data/metadata 对齐的序列：

- `mem_req_rdy=1`，backend 对每个 request 固定下一拍给 response，`ma_wb_rdy=1`；
- warm-up 后相邻 `mem_req_fire` 间隔必须连续为 1 cycle；
- warm-up 后相邻 `mem_rsp_fire` 间隔必须连续为 1 cycle；
- architectural completion允许固定延后，但 warm-up 后相邻 `ma_wb_fire` 间隔必须连续为 1 cycle；
- 至少观察到一次 `rsp_fire(A) + req_fire(B)` 和一次 `completion_pop(A) + completion_push(B)`；
- load data/rd metadata 与对应 request一致；若短流包含store，其目标写每 request恰好一次；
- 单 unanswered counter始终不超过 1。

load dependency、formatting、misaligned、store exactly-once和variable-latency功能只要求 Phase0 现有
定向用例继续 PASS。本轮不新增 mixed collision、随机反压、各种 dependency和backend replacement
的穷举矩阵；这些项目见 deferred 文档。

## 9. 最小观测与检查

复用 Phase 0 已有 payload-hold、outstanding、stale-response与store exactly-once检查。新增短流 TB
只需检查：

```text
if_unanswered_count  inside {0,1}
lsu_unanswered_count inside {0,1}

if_rsp_fire  |-> previous unmatched IF request exists
mem_rsp_fire |-> previous unmatched LSU request exists

16-entry expected address/data/rd sequence matches actual transfer
steady-state adjacent req/rsp/output fire interval == 1
at least one response/request and buffer pop/push same-cycle replacement
```

不强制新增复杂 SVA eligibility表达式、全套 stall-reason counter或通用 transaction scoreboard；不得为
通过短流测试绑死 ready、删除既有 backpressure逻辑或放宽原 Phase0断言。

## 10. CoreMark 性能测量

使用与用户当前约 172 ms结果相同的 RTL/testbench、binary、iterations、clock period和BPU/RAS配置，
运行一次 Phase0 S2 CoreMark简化测试。至少报告：

- 与此前 172 ms相同口径的仿真时间；
- 如果现成 testbench已有 benchmark start/stop cycles，同时记录该值；
- 是否正确完成及输出是否一致。

预期相对 172 ms明显改善，但本轮不设 77 ms或 1.10× pre-Phase0硬门槛，不要求为了性能测量新增
全套 RTL counters。严格三版本 benchmark-body/IPC/stall breakdown归入 deferred 工作。

用户按相同验收口径运行 `CoreMark_10`，结果为 **78 ms**：相对 Phase 0 的约172 ms明显改善，满足本
工单的应用观察判据。

## 11. 公共回归与交付判定

实现完成后按 [`rule_ai_acceptance.md`](rule_ai_acceptance.md) 执行公共回归，并显式使用 v12：

```text
cd work/my-RISCV-Projs/sim
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32i DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../12_rv32im_bpu_cache
```

公共验收标准：

- ISA：`rv32ui` 41/42 PASS，仅允许既有 `ma_data` FAIL；`rv32um` 8/8 PASS；
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
- 不得出现新的 simulation、SVA、assertion 或 scoreboard failure；
- 在 `work/my-RISCV-Projs/syn` 执行 `make check DESIGN_NAME=12_rv32im_bpu_cache` 并 PASS。

交付记录必须包含：

- 最终 IFU/MAU slot 与 fire/replace 条件，以及未新增 pipeline stage/transaction resource的说明；
- 第 8 节两个 16-entry短流吞吐结果；
- CoreMark简化测试结果；
- Phase0/BPU/RAS既有定向回归及公共回归/DC check结果；
- 修改文件列表与所有 deferred/non-goal 未被顺带改变的确认。

完成实现但等待用户执行其保留的公共验收时，状态只能更新为
`Implementation Complete — Public Acceptance Pending User Run`；全部必需证据确认后才能标记 `Completed`。

## 12. 推荐实施顺序

1. 先加入最小短流 zero-wait throughput TB，复现当前约 3-cycle transaction interval。
2. 将 IFU response buffer改为 elastic replacement，并实现 response-derived successor 的同拍 request。
3. RAS-dependent pair优先采用显式 bubble保证正确；只有实现自然简单时再做 preview。
4. 在不新增 pipeline stage的前提下，让现有 EX/MA holding、outstanding和MA/WB holding并行推进。
5. AI跑两个短流及既有Phase0/BPU/RAS定向用例，更新uArch文档、本工单状态和`log_dev_v12.md`。
6. 通知用户手动运行CoreMark、rvtests/Compliance、DC check及其余完整验收；收到结果后再关闭工单。

## 13. 实施与验证记录（2026-09-06 16:47）

已完成：

- IFU以正常response直接生成successor request；request被反压时回落到原holding register；
- IF response buffer支持同拍pop/push，response A与request B支持同拍replacement；
- redirect/stale-response语义保持，RAS-dependent return采用局部一拍response bubble保证正确；
- MAU直接复用EX现有valid-ready holding，拆分单outstanding metadata和MA/WB completion holding；
- EX holding、outstanding和completion支持同拍释放/替换，没有增加MSHR、request FIFO、第二个buffer或
  architectural pipeline stage；
- 初版S2实现曾误加入实际 `r_ingress_*` register，导致普通ALU forwarding整体晚一拍；该寄存级已删除，
  non-memory payload恢复直接进入既有MA/WB holding，memory request直接使用EX稳定payload；
- pending load尚未完成时保守反压年轻instruction；连续独立memory stream仍可同拍response/request替换；
- Phase0 MAU定向增加non-memory pass-through检查，SVA由旧FSM state检查改为outstanding合同检查；
- 新增IFU/MAU各16-entry one-cycle throughput TB及Makefile目标。

已执行的诊断性验证：

- `make -f Makefile.phase0 all`：PASS；bus、IFU variable-latency、MAU variable-latency以及IFU/MAU
  throughput五组均通过，无SVA/scoreboard failure；
- IFU短流：request/response/IF-ID warm-up后均1/cycle，并覆盖response/request和buffer pop/push同拍；
- MAU短流：request/response/MA-WB completion warm-up后均1/cycle，并覆盖outstanding与completion同拍替换；
- `make -f Makefile.bpu all`：PASS；BPU、RAS、frontend、disabled配置及compile checks全部通过；
- `make com_isa DESIGN_NAME=../12_rv32im_bpu_cache`：v12全SoC编译PASS，仅有工具既有Linux kernel warning。

`make -f Makefile.phase0 all` 与 `make -f Makefile.bpu all` 曾错误地在本设计 `dv` 路径生成build
目录；相关生成物已按用户要求全部清理。因此这些结果只作问题定位参考，不作为最终交付目录或公共验收
证据。后续仿真只允许在
`work/my-RISCV-Projs/sim` 路径执行。

## 14. 用户公共验收与问题发现（v1.3，2026-09-06 19:45）

- 用户在实现完成后手动运行公共验收，发现 `rv32ui-p-ld_st` FAIL；后续复核还发现rv32i Compliance
  的 `I-MISALIGN_LDST-01` FAIL，两项均进入定位修复。
- AI在规定的 `work/my-RISCV-Projs/sim` 路径定向运行 `make sim_isa test=ld_st
  DESIGN_NAME=../12_rv32im_bpu_cache`，结果未进入PASS/FAIL handler，而是在仿真时间
  `1_000_000_000 ps` timeout。
- `ld_st` 覆盖对齐 `sb/lb/lbu`、`sh/lh/lhu`、`sw/lw`及紧邻store/load、load-use address/data依赖；
  因此从transaction replacement、load forwarding/interlock及response metadata对齐开始逐拍定位。
- 本版本只记录验收发现问题并继续修复，不存在将功能问题转入deferred或停止debug的状态。

## 15. 两项公共回归修复与最终验收（v1.4，2026-09-06 20:10）

### 15.1 `rv32ui-p-ld_st`

在规定的 `work/my-RISCV-Projs/sim` 路径重新运行单例后，问题稳定表现为仿真时间 `1_110_000 ps`
进入FAIL handler，失败编号为test 2。逐拍检查确认same-cycle store/load replacement、DTCM response data
以及MAU addr/rd/size/sign metadata在首错之前均正确；第一处偏差是 `PC=0x00000044` 的
`bne tp,sp`。

关键时序如下：

- `PC=0x0000003c` 的 `lw tp,8(sp)` 在 `510_000 ps` 返回并格式化出正确的 `0x10000050`；
- `PC=0x00000040` 的依赖store在 `530_000 ps` 发出正确请求：地址 `0x10000050`、byte mask
  `0001`、写数据 `0x000000dd`；
- `PC=0x00000044` 的branch因older store response/completion占用MA路径而在EX保持；`550_000 ps`
  尚可从WBU forward `tp=0x10000050`，但该值未写入EX现有operand holding；
- `570_000 ps` forwarding valid消失后，branch退回进入EX时捕获的旧 `tp=0`，从而错误跳至
  `0x00000e70 <fail>`。

修复位于 `de/core/exu.sv`：当当前EX payload因valid-ready backpressure保持时，把有效的MAU/WBU
forwarding值吸收到现有 `rf_rs1_r_ex`/`rf_rs2_r_ex` operand holding registers。该修改不新增流水级、
FIFO或事务资源，也不改变MAU single-outstanding/replacement合同。

修复后使用标准命令：

```text
cd work/my-RISCV-Projs/sim
make sim_isa test=ld_st DESIGN_NAME=../12_rv32im_bpu_cache
```

结果为 `[PASS]`，在 `23_970_000 ps` 正常结束，无新增SVA/Assertion error。

### 15.2 `I-MISALIGN_LDST-01`

用户重跑rv32ui后确认仅 `ma_data` FAIL，符合当前允许项。随后用户报告rv32i Compliance中的
`I-MISALIGN_LDST-01` FAIL。AI只在统一 `work/my-RISCV-Projs/sim` 路径运行该单例，初始结果有14个
signature mismatch，全部位于load-misaligned exception记录区；store-misaligned cause=6记录正确。

第一处偏差位于 `PC=0x000000b4` 的非对齐 `lw tp,1(gp)`：

- `890_000 ps` 已正确组合产生cause=4、`mtval=0x10000301`，但older aligned store response使
  `ex_ma_rdy=0`，异常尚不能commit；
- 下一条store依赖load的 `tp`，旧load-use控制无条件产生 `FLUSH_ID_EX`，把仍在EX holding且尚未commit
  的异常load清除；
- 因未发生redirect/CSR trap update，trap handler未执行，对应signature保持初值 `0xffffffff`。

修复在 `de/core/ctrl_hazard.sv` 为load-use flush增加 `ex_ma_rdy` 条件，并由 `de/core/core.sv` 接入现有
EX/MA ready：MA backpressure期间保持older EX load/exception，仅在该payload能够实际离开EX时注入依赖
bubble。该修改不增加pipeline stage或buffer。

标准单例结果：

```text
make sim_compli case=I-MISALIGN_LDST-01 DESIGN_NAME=../12_rv32im_bpu_cache
COMPLIANCE [PASS], 7_770_000 ps

make sim_isa test=ld_st DESIGN_NAME=../12_rv32im_bpu_cache
ISA [PASS], 23_970_000 ps
```

### 15.3 最终验收结果

- 用户手动重跑公共回归，验收通过；`rv32ui` 仅保留既有允许项 `ma_data` FAIL，两个新增问题均已消除。
- `rv32ui-p-ld_st` 标准单例及修复后的复测均在 `23_970_000 ps` PASS；`I-MISALIGN_LDST-01` 标准
  单例在 `7_770_000 ps` PASS。
- 用户运行 `CoreMark_10` 得到 **78 ms**，相对约172 ms基线明显改善。
- 两项修复均复用现有valid-ready holding与pipeline控制，未增加MAU ingress register、pipeline stage、
  FIFO或transaction resource；工单公共回归与性能观察判据已满足，状态更新为 `Completed`。
