# v12 开发日志

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 11:04

---

## 2026-09-07 01:08 — Phase 2 Basic D-Cache + MMIO Bypass

- 工单：[`task_v12_04_phase2_basic_dcache_mmio_bypass.md`](task_v12_04_phase2_basic_dcache_mmio_bypass.md)
- 实现4 KiB direct-mapped blocking D-Cache：8-word load refill、WT store hit、NWA store miss、byte mask、
  response holding/replacement；`mem_dtcm`重构为16 KiB事务化 `backing_dmem`。
- LSU router现将DMEM送入D-Cache，将executable IMEM data access和UART分别作为uncached/Device bypass，
  unmapped保持benign completion；preload/signature与filelist同步新层次。
- 修复 `ld_st` 暴露的load response/dependent store同拍replacement forwarding窗口：MAU直接暴露当拍
  response result及metadata给EX forwarding，不增加pipeline resource。
- 最小验证：Phase 2核心定向、`ld_st`、`jal`均PASS，无新增SVA/Assertion error。
- 用户公共验收：ISA `rv32ui` 41/42 PASS（仅既有允许项 `ma_data` FAIL）、`rv32um` 8/8 PASS；
  Compliance `rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
  synthesis check PASS；`coremark_10` 运行成绩为用户报告的 `103 ms`。任务Completed。

## 2026-09-07 00:42 — Phase 1 Basic I-Cache

- 工单：[`task_v12_03_phase1_basic_icache.md`](task_v12_03_phase1_basic_icache.md)
- 实现4 KiB、32 B line、128-line direct-mapped read-only blocking I-Cache；miss执行8个word whole-line
  refill，完整接收后原子install；hit response支持反压保持和response/request同拍replacement。
- 将取指侧过渡 `mem_itcm` 重构为32 KiB `backing_imem`，SoC、filelist及TB preload统一切换到
  I-Cache + backing IMEM，LSU executable-region data port保持直达backing array。
- 最小验证：I-Cache核心定向PASS；`add`、`jal` SoC smoke均PASS且无新增SVA/Assertion error。
- 用户公共验收：ISA `rv32ui` 41/42 PASS（仅既有允许项 `ma_data` FAIL）、`rv32um` 8/8 PASS；
  Compliance `rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
  synthesis check PASS；`coremark_10` 运行成绩为用户报告的 `81 ms`。任务Completed。

## 2026-09-06 20:10 — 修复 Phase 0 S2 两项公共回归

- 用户重跑rv32ui确认仅既有允许项 `ma_data` FAIL，`ld_st` 已通过组级验证。
- `rv32ui-p-ld_st` 首错定位到test 2的 `PC=0x00000044`：`lw tp,8(sp)`已正确返回 `0x10000050`，随后依赖store也发出
  正确请求；branch在EX受LSU backpressure保持时只短暂看到WBU forwarding，producer离开后退回进入EX
  时捕获的旧 `tp=0`，错误跳往fail。
- `de/core/exu.sv` 现会在EX payload保持期间把有效MAU/WBU forwarding值吸收到现有operand holding
  registers；未增加pipeline stage、FIFO或MAU transaction resource。
- 在 `work/my-RISCV-Projs/sim` 运行标准单例
  `make sim_isa test=ld_st DESIGN_NAME=../12_rv32im_bpu_cache`，结果 `[PASS]`，结束时间
  `23_970_000 ps`，无新增SVA/Assertion error。
- `I-MISALIGN_LDST-01` 首错为 `PC=0x000000b4` 的非对齐load：已产生cause=4/mtval，但在
  `ex_ma_rdy=0` 时被下一条依赖指令触发的无条件 `FLUSH_ID_EX` 清除，未能commit或进入trap handler。
- `ctrl_hazard.sv` 的load-use flush现以EX/MA ready为条件；MA backpressure期间继续使用现有EX holding
  保存load/exception，未增加pipeline stage、FIFO或transaction resource；`core.sv` 仅新增ready连接。
- 标准单例 `I-MISALIGN_LDST-01` PASS（`7_770_000 ps`），`ld_st` 复测PASS（`23_970_000 ps`）。完整
  rv32i Compliance group仍待用户重跑，其他公共验收无新增结果。
- 用户已确认完整rv32ui只剩既有允许项 `ma_data`；rv32um、完整Compliance、CoreMark和DC check未由
  AI运行。

## 2026-09-06 16:47 — Phase 0 S2 IFU / LSU Transaction Throughput

- 工单：[`task_v12_02_phase0_s2_memory_throughput.md`](task_v12_02_phase0_s2_memory_throughput.md)
- 实现：IFU response-derived successor request与response-buffer elastic replacement；RAS-dependent return局部bubble；MAU复用EX现有valid-ready holding并拆分single-outstanding metadata和MA/WB completion，实现同拍replacement且不新增流水级/FIFO/MSHR。
- 诊断性定向：Phase0 bus/IFU/MAU及两个16-entry throughput短流PASS；IF和LSU request/response/output均达到steady-state 1/cycle；BPU/RAS轻量回归PASS；v12全SoC VCS compile PASS。其后发现的两项公共回归已修复，且DV路径生成物已清理，最终状态以上方20:10记录为准。
- 用户已确认完整rv32ui除既有允许项 `ma_data` 外均通过；完整ISA/Compliance、CoreMark耗时对比、DC check及其他签核仍由用户手动验收。

## 2026-09-06 14:09 — Phase 0 review - Cache + Backing Memory 架构决策

- 最终拓扑确定为 I/D Cache + backing memory，不保留独立 ITCM/DTCM 或 TCM bypass path。
- Phase 0 IF/LSU req/rsp 合同分别由 Phase 1 I-Cache、Phase 2 D-Cache 直接继承；`mem_itcm`/`mem_dtcm` 同 Phase 重构/重命名为 Cache 下游 backing-memory model/adapter。
- 已同步更新 main spec、phase roadmap、Phase 0 工单、memory 配置与 deferred 记录。

## 2026-09-06 11:04 — Phase 0 Variable-Latency Memory Baseline

- 工单：[`task_v12_01_phase0_variable_latency_memory_baseline.md`](task_v12_01_phase0_variable_latency_memory_baseline.md)
- 实现：IF 与 LSU req/rsp valid-ready；IFU stale-response drain；MAU/MEM transaction FSM；store request-fire 单次副作用；RTL ITCM/DTCM；v12 sim/syn filelist；transaction SVA/scoreboard。
- 定向：Phase 0 IFU/MAU/local bus 全部 PASS；BPU/RAS 全套定向与 compile checks PASS；`add`、`lw` smoke PASS，无新增 SVA failure。
- 公共验收：完整公共回归与 DC check 结果由用户手动运行并确认。
- Deferred：精确地址/access fault、32 KiB backing DMEM、backing/cache SRAM macro/BRAM replacement，见 [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)。
