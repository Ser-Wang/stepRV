# task_v12_04：Phase 2 Basic D-Cache + MMIO Bypass 实现工单

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-07 00:50
**Current Version**: v1.2
**Status**: Completed (2026-09-07 01:21) | Implementation Complete — Public Acceptance Pending User Run (2026-09-07 01:08) | Ready for Execution (2026-09-07 00:58) | Ready for Review (2026-09-07 00:50)

**Version Changelog**:
- **v1.2** (2026-09-07 01:21): 记录用户完成公共ISA、Compliance与synthesis验收，并补记 `coremark_10` 运行成绩103 ms；任务关闭为Completed。
- **v1.1** (2026-09-07 01:08): 完成Phase 2 D-Cache、属性路由、backing DMEM重构、依赖forwarding修复、核心定向及两个SoC smoke；公共验收等待用户运行。
- **v1.0** (2026-09-07 00:50): 定义4 KiB direct-mapped write-through/no-write-allocate D-Cache、cacheable/uncached路由、backing DMEM重构、核心定向验证和用户保留的公共验收。

---

# Part I — 任务制定与 Review

本部分是执行前的稳定输入，只记录目标、设计约束、范围、实施顺序和验收标准。Review修订继续更新
本部分及文档版本；开始执行后，不把实施过程、测试结果或bugfix混入本部分。

## A1. 任务目标

在Phase 0/Phase 0 S2的MAU request/response valid-ready合同上加入Phase 2基础D-Cache与
cacheable/uncached分流：

- 4 KiB、direct-mapped、32 B cache line、blocking；
- write-through、no-write-allocate，不维护dirty、不做writeback；
- DMEM region的load/store经过D-Cache；
- executable IMEM region的LSU data access走uncached backing IMEM data port；
- UART/MMIO作为Device请求绕过D-Cache；
- 将过渡 `mem_dtcm` 重构/重命名为D-Cache下游 `backing_dmem` transaction model/adapter；
- 保持byte/halfword/word load/store、response backpressure、同拍transaction replacement以及
  exactly-once store副作用正确；
- 用最少核心定向和两个SoC smoke尽快完成一轮可运行实现，其余corner分析后登记deferred。

本任务不加入write-back/write-allocate、dirty eviction、BIU、AXI/APB、组相联、non-blocking Cache、
精确地址fault或SRAM macro。

## A2. 依据与当前基线

- [`../mainSpec_Cache_Mem-subsys_Feature.md`](../mainSpec_Cache_Mem-subsys_Feature.md)
- [`../phaseSpec_Cache_Mem-Subsys_Roadmap.md`](../phaseSpec_Cache_Mem-Subsys_Roadmap.md)
- [`task_v12_01_phase0_variable_latency_memory_baseline.md`](task_v12_01_phase0_variable_latency_memory_baseline.md)
- [`task_v12_02_phase0_s2_memory_throughput.md`](task_v12_02_phase0_s2_memory_throughput.md)
- [`task_v12_03_phase1_basic_icache.md`](task_v12_03_phase1_basic_icache.md)
- [`rule_ai_acceptance.md`](rule_ai_acceptance.md)
- [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)

当前可复用基线：

- MAU已提供 `mem_req_vld/rdy`、address/load/store/size/wmask/wdata与
  `mem_rsp_vld/rdy/rdata`，最多一个unanswered request并允许response A/request B同拍replacement；
- MAU按已保存的address/size/signedness对返回的32-bit word做byte/halfword load格式化；D-Cache无需
  复制sign/zero extension；
- `soc_bus`已有粗粒度属性：`0x1` high nibble为cacheable DMEM，`0x0`为executable IMEM data
  access，`0x3`为UART，其他为unmapped benign completion；
- `mem_dtcm`当前为16 KiB同步RTL array；`backing_imem`提供LSU executable-region 1RW data port；
- Phase 1 I-Cache及其backing IMEM路径已完成公共验收，不得因D-Cache接入形成取指回归；
- TB通过 `u_dmem.r_dtcm` preload/signature读取，重命名时必须同步更新。

## A3. 目标结构与所有权

```text
MAU LSU req/rsp
      |
      v
LSU memory router / response owner
  |-- cacheable DMEM --> 4 KiB D-Cache --> backing_dmem
  |-- uncached IMEM ---------------------> backing_imem data port
  |-- Device UART ----------------------> UART native port
  `-- unmapped -------------------------> benign completion (temporary)
```

所有权约束：

- MAU继续拥有EX/MA请求、single-outstanding transaction metadata、load格式化和MA/WB completion；
- LSU memory router只做地址属性分类、request分发、目标记录与response归并，不保存Cache line状态；
- D-Cache只接收cacheable DMEM transaction，拥有lookup、miss/refill/install、write-through与CPU侧
  cacheable response；
- `backing_dmem`只保存后备数据并响应word transaction，不含tag/valid/FSM；
- uncached IMEM与UART请求不得查询、分配或修改D-Cache line；
- D-Cache不访问UART，不复制MAU的load sign/zero extension，不承担pipeline flush/exception状态；
- 本阶段继续使用可综合RTL arrays，不接SRAM macro或BRAM wrapper。

## A4. D-Cache几何、数据宽度与地址分解

4 KiB / 32 B = 128 lines，地址字段为：

```text
31                     12 11             5 4       2 1  0
+------------------------+----------------+---------+----+
|       tag[31:12]       | index[11:5]    | word    |byte|
+------------------------+----------------+---------+----+
          20 bits              7 bits       3 bits   2 bits
```

- valid：128 × 1 bit；tag：128 × 20 bit；data：128 × 8 × 32 bit；无dirty array；
- reset只清valid和控制状态，不清tag/data/backing array；
- refill base为 `{request_addr[31:5], 5'b0}`，依次请求base + 0/4/.../28；
- cache array与backend transaction均以32-bit word为数据单元；store byte enable沿用MAU的4-bit wmask；
- aligned byte/halfword/word store只更新wmask覆盖的byte；misaligned access仍由既有EX异常路径拦截。

## A5. 必须实现的核心行为

### A5.1 Cacheable load

- 请求只在valid-ready fire时接收；等待ready期间payload稳定责任沿用Phase 0合同；
- load hit必须同时满足 `valid[index] && tag[index] == request_tag`，返回所选32-bit word给MAU；
- load miss期间blocking，不接受第二个D-Cache请求；line保持invalid直到8个refill response全部接收；
- backend request只在fire时推进request计数，response只在fire时写唯一word slot并推进response计数；
- 完整refill后原子写tag/valid，并为原请求返回正确word；不得跳beat、重复写或跨line污染；
- direct-mapped conflict覆盖同index旧line，无dirty writeback。

### A5.2 Write-through store hit

- store hit同时向backing DMEM发出一次带原始wmask/wdata的word write transaction；
- backend request等待ready时地址、wmask和wdata稳定；写副作用仅在backend request fire发生一次；
- 接受write transaction时同步以wmask更新cache中命中word，使随后load hit观察到新值；
- store只有在对应backend response fire后才向MAU返回一次completion；response反压不得重复backend写；
- 本阶段backend无error sideband，因此已接受的write-through store按成功完成处理。

### A5.3 No-write-allocate store miss

- store miss不得发起line refill，不得改变目标index的valid/tag/data；
- 只向backing DMEM发出一次原始word write transaction，并在其response后完成CPU transaction；
- 同一地址后续load仍必须miss并通过whole-line refill取得包含该store结果的数据；
- conflict store miss不得驱逐原有命中line。

### A5.4 CPU response与replacement

- load/store response的valid及load data在MAU接受前保持稳定；
- response A被接受时允许同拍接收request B；不得重新引入只为FSM切换的固定空拍；
- request/response同拍replacement时，A必须使用旧transaction metadata，B原子占用新transaction；
- D-Cache miss或write-through等待期间必须对cacheable上游施加blocking backpressure。

### A5.5 Cacheable / uncached / Device路由

- 本Phase保持当前粗粒度decode：DMEM `addr[31:28]==4'h1` 为cacheable，IMEM `4'h0`为uncached，
  UART `4'h3`为Device，其他为unmapped；精确base/size与跨界检查继续deferred；
- router只向命中的一个目标发request，并保存已接受transaction的target直到response完成；
- uncached IMEM load/store每次都直达 `backing_imem` data port，不查询或分配D-Cache；
- UART load/store每次都直达UART native port，不查询或分配D-Cache；
- unmapped load返回零、store无副作用，但均产生一次benign completion，不能死锁；
- 每个store无论cacheable/uncached/Device都必须保持exactly-once目标副作用；
- 任一目标response反压期间，router输出valid/data与target metadata必须稳定；
- 不要求不同目标并发；整个LSU memory subsystem继续以MAU single-outstanding合同为上界。

### A5.6 Reset与backing DMEM重构

- reset中止未完成lookup/refill/write-through/bypass/response并清所有D-Cache valid；
- 复位后首次DMEM load必须cold miss；backing memory内容不由reset清除；
- 删除 `mem_dtcm` 模块名及 `u_dmem.r_dtcm` 依赖，重命名后的 `backing_dmem` 使用word
  request/response valid-ready并支持byte write mask；
- `backing_dmem`逻辑容量本Phase仍保持16 KiB，32 KiB扩容继续归属Phase 6；
- filelist、SoC、TB preload/signature helper与memory配置文档同步新名称。

## A6. 极速迭代范围与deferred策略

### A6.1 本轮明确不实现

- write-back、write-allocate、dirty bit、eviction writeback；
- 2-way、replacement policy、8 KiB最终容量；
- 多miss、MSHR、hit-under-miss、store buffer、write combining、prefetch或critical-word-first；
- BIU、AXI/APB、burst refill、backend arbitration或error response；
- backing DMEM 16 KiB到32 KiB扩容；
- Cache/backing SRAM macro、BRAM wrapper和同步1RW物理时序收口；
- 精确region范围、跨边界检查、load/store access fault及严格UART size/alignment fault；
- D-Cache性能计数器和完整CoreMark性能分析；
- I-Cache/LSU self-modifying-code coherence与 `fence.i` invalidate。

### A6.2 已知边界但不作为本轮验证门槛

- backend无error sideband，无法激励refill/store/bypass error；保持valid只在完整refill后安装的结构边界；
- reset落在每个refill beat、store request/response与route response replacement拍的穷举组合；
- CPU/backend交叉随机反压、所有word offset、同index多tag长时间thrash与长流scoreboard；
- uncached IMEM与I-Cache并发访问backing IMEM双端口的read-during-write细节；
- LSU修改backing IMEM后I-Cache stale副本，仍受缺失 `fence.i` invalidate的已知限制；
- X态、非法size、非法wmask及被EX拦截的misaligned请求到达D-Cache时的防御行为。

执行中发现新边界时：影响核心定向或公共回归则当轮修复；不影响最小核心路径则在
[`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)
追加“现象/风险、当前接受行为、后续触发条件、建议验证”，本轮不扩展成corner matrix。

## A7. 预期文件范围

| 文件 | 预期修改 |
|---|---|
| `de/core/dcache.sv` | 新增4 KiB WT/NWA direct-mapped blocking D-Cache |
| `de/periphs/backing_dmem.sv` | 由 `mem_dtcm.sv` 重构/重命名为transaction backing model |
| `de/soc/soc_bus.sv`或小型router文件 | 重构为cacheable/uncached/Device request分流与response归并 |
| `de/soc/soc_top.sv` | 接入D-Cache、backing DMEM、backing IMEM data port与UART bypass |
| `filelists/filelist_rtl.f`、`filelist_sim_sram.f` | 纳入D-Cache/backing DMEM并删除 `mem_dtcm` |
| `dv/tb_dcache_basic.sv` | D-Cache与路由最小核心定向源文件 |
| `dv/tb_soctop_*.sv` | 更新backing DMEM preload/signature层次路径 |
| `../sim/makefile` | 从统一 `sim/` 启动Phase 2核心定向测试 |
| `doc/readme_mem_config.md` | 更新Phase 2结构、路由、backing DMEM和preload说明 |
| `doc/dev_log/pending_v12_cache_mem_subsys_deferred_scope.md` | 仅追加执行中分析后明确搁置的新边界 |
| `doc/dev_log/log_dev_v12.md` | Phase 2完成后追加简短实现与验收摘要 |

如实现需要新增小型router或transaction adapter文件，可以纳入；不得顺带重构MAU、I-Cache、BPU或
pipeline，除非最小验证暴露接口合同级功能错误。

## A8. 推荐实施顺序

1. 固定router、D-Cache CPU侧与backing DMEM端口，明确load/store response和target ownership。
2. 将 `mem_dtcm` 重构为valid-ready `backing_dmem`，先验证单word read/write与byte mask。
3. 新增D-Cache，先跑通cold load miss → 8-beat refill → install → response及warm load hit。
4. 加入write-through store hit与no-write-allocate store miss，验证exactly-once和cache一致性。
5. 加入response holding与response/request同拍replacement。
6. 重构LSU router，接通DMEM cacheable、IMEM uncached、UART Device和unmapped benign completion。
7. 更新SoC、filelist、TB preload/signature与memory配置，只从统一 `sim/` 运行A9最小验证。
8. 分析corner；核心错误当轮修复，其余登记pending后停止扩验。
9. 更新task执行记录与devlog，通知用户运行保留的公共验收与synthesis check。

## A9. 验证与验收

### A9.1 AI执行的最小核心验证

所有仿真命令必须从 `work/my-RISCV-Projs/sim` 运行。禁止在设计 `dv/` 目录运行make、仿真或生成
build结果；`dv/`仅保存TB/SVA源文件。

1. 一个Phase 2核心定向流，在同一TB中至少覆盖：

- reset后DMEM cold load miss、8个有序refill word及requested word返回；
- warm load hit无backend访问；
- byte/halfword/word store hit各一次write-through、cache byte-mask更新与exactly-once backend write；
- store miss no-write-allocate，随后load产生miss并取得已写入值；
- 同index不同tag load conflict replacement；
- 至少一次CPU response backpressure稳定和一次response A/request B同拍replacement；
- DMEM重复访问可命中，IMEM LSU data access与UART访问重复执行仍逐次bypass且不分配D-Cache；
- unmapped load/store各产生一次benign completion且无目标副作用。

```text
make sim_phase2_dcache DESIGN_NAME=../12_rv32im_bpu_cache
```

2. 两个SoC smoke单例：

```text
make sim_isa test=ld_st DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa test=jal DESIGN_NAME=../12_rv32im_bpu_cache
```

两者必须PASS、无新增SVA/Assertion error；`ld_st`覆盖真实load/store与subword路径，`jal`确认Phase 1
取指及redirect无回归。

除非上述最小用例失败并需要缩小根因，否则AI不主动扩跑其他ISA、Compliance、随机回归、CoreMark或
synthesis。

### A9.2 用户手动公共验收

最终验收遵循 [`rule_ai_acceptance.md`](rule_ai_acceptance.md)，ISA、Compliance和synthesis check由
用户手动运行并反馈，AI不得代跑。

用户在 `work/my-RISCV-Projs/sim` 手动运行并显式指定v12：

```text
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32i DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../12_rv32im_bpu_cache
```

标准为：

- ISA：`rv32ui` 41/42 PASS，仅允许既有 `ma_data` FAIL；`rv32um` 8/8 PASS；
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
- 不得出现新的simulation、SVA或assertion failure。

用户另在 `work/my-RISCV-Projs/syn` 手动运行：

```text
make check DESIGN_NAME=12_rv32im_bpu_cache
```

synthesis check必须PASS。AI完成RTL和A9.1后，状态更新为
`Implementation Complete — Public Acceptance Pending User Run`；只有用户反馈公共回归与synthesis
满足标准后，才能标记`Completed`。

## A10. Review记录

当前为v1.0初稿，等待Review。每轮Review在本小节追加独立条目，并同步更新header版本/状态；Review只
修改Part I，不提前填写执行结果。

---

# Part II — 执行、验证与后续修复记录

本部分从任务状态进入执行后开始填写。每轮实现、返修或bugfix使用独立的“Execution Round”，不得与
Part I任务定义混排，也不得把多轮结果堆在同一级连续编号中。

## E0. 记录规则

每轮至少记录：

- 开始原因与本轮目标；
- 实际修改文件和关键设计决策；
- 只在 `work/my-RISCV-Projs/sim` 执行的命令与结果；
- 首个错误时序和根因（若本轮是bugfix）；
- 新增deferred边界及其pending文档链接；
- 本轮结束状态和下一执行责任人。

## Execution Round 1 — 初始实现（2026-09-07 00:58）

### E1.1 实现

- 新增 `de/core/dcache.sv`：4 KiB、128-line、32 B line direct-mapped blocking D-Cache；实现
  load hit/miss、8-word refill、原子install、WT store hit、NWA store miss、byte mask更新、response
  holding及response/request同拍replacement。
- 将 `mem_dtcm.sv` 重构/重命名为valid-ready `backing_dmem.sv`，保留16 KiB RTL array并为read/write
  transaction统一返回一次response。
- 将 `soc_bus.sv` 重构为LSU属性router：DMEM进入D-Cache，executable IMEM data access走
  `backing_imem` uncached port，UART作为Device bypass，unmapped保持benign completion；router保存目标
  ownership并归并response。
- 更新 `soc_top.sv`、sim/syn filelist、SoC TB preload/signature路径、transaction SVA和memory配置文档；
  新增 `dv/tb_dcache_basic.sv` 及统一 `sim/makefile` 的 `sim_phase2_dcache` 目标。
- `ld_st`首轮在test #2失败：首个错误序列为load response A与依赖store B同拍replacement，B在A写入
  MA/WB holding前取得旧store operand `0`。根因是MAU forwarding只暴露已寄存completion，没有暴露
  当拍fire的memory response。`mau.sv`新增独立response-fire forwarding data/index/wen，`core.sv`
  将hazard forwarding选择接到该通路；不新增pipeline stage、FIFO或transaction resource。

### E1.2 最小验证

均于 `work/my-RISCV-Projs/sim` 执行：

- `make sim_phase2_dcache DESIGN_NAME=../12_rv32im_bpu_cache`：PASS；覆盖cold load miss、8个有序
  refill、warm hit、byte/halfword/word WT store、NWA conflict store、cache更新、exactly-once write、
  response backpressure/replacement、IMEM/UART bypass及unmapped benign completion。
- `make sim_isa test=ld_st DESIGN_NAME=../12_rv32im_bpu_cache`：修复后PASS，`66_490_000 ps`，
  无新增SVA/Assertion error。
- `make sim_isa test=jal DESIGN_NAME=../12_rv32im_bpu_cache`：PASS，`2_410_000 ps`，无新增
  SVA/Assertion error。

### E1.3 Deferred / 已知边界

本轮未新增deferred项。A6既定的backend error、精确地址/access fault、32 KiB backing DMEM、
SRAM/BRAM、随机corner matrix与self-modifying-code coherence继续保持deferred，本轮未扩验。

### E1.4 结果与状态

Phase 2 RTL及A9.1最小验证完成。状态为
`Implementation Complete — Public Acceptance Pending User Run`；完整ISA/Compliance与synthesis check
由用户按A9.2手动运行，满足标准后再更新为`Completed`。

### E1.5 用户公共验收（2026-09-07 01:21）

用户反馈A9.2手动验收全部通过：

- ISA：`rv32ui` 41/42 PASS（仅允许的既有 `ma_data` FAIL），`rv32um` 8/8 PASS；
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
- synthesis check：PASS；
- `coremark_10`：运行成绩 `103 ms`（用户报告）。

任务状态更新为`Completed`。
