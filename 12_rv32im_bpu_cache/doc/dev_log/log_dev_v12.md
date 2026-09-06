# v12 开发日志

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 11:04

---

## 2026-09-06 19:45 — Phase 0 S2 验证未闭环，`rv32ui-p-ld_st` 暂时搁置

- 用户手动运行 `type=isa group=rv32ui`，反馈新增 `rv32ui-p-ld_st` FAIL；公共验收要求只允许既有
  `ma_data` FAIL，因此当前S2工单不能标记Completed。
- AI在规定的 `work/my-RISCV-Projs/sim` 路径单独运行 `ld_st`，用例在
  `1_000_000_000 ps` timeout，未进入其PASS/FAIL handler。
- 调试期间发现初版S2 MAU把逻辑MA ingress误做成实际新增register，导致普通ALU forwarding晚一拍；
  已删除该寄存级，memory request改为直接使用EX现有valid-ready holding，non-memory恢复原五级时序。
- 修正后Phase0与S2短流、BPU/RAS用例曾作诊断性运行并通过，但因错误地在设计 `dv` 路径生成结果，
  build目录已全部清理，这些结果不作为最终公共验收证据；后续只在统一 `sim` 路径执行。
- `ld_st` 剩余根因尚未确认，按用户决策暂时搁置；工单状态更新为
  `Implementation Frozen — Acceptance Incomplete`，具体见
  [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)。
- `rv32um`、Compliance、CoreMark和DC check无新结果，记为 `Not Run/Not Reported`。

## 2026-09-06 16:47 — Phase 0 S2 IFU / LSU Transaction Throughput

- 工单：[`task_v12_02_phase0_s2_memory_throughput.md`](task_v12_02_phase0_s2_memory_throughput.md)
- 实现：IFU response-derived successor request与response-buffer elastic replacement；RAS-dependent return局部bubble；MAU复用EX现有valid-ready holding并拆分single-outstanding metadata和MA/WB completion，实现同拍replacement且不新增流水级/FIFO/MSHR。
- 诊断性定向：Phase0 bus/IFU/MAU及两个16-entry throughput短流PASS；IF和LSU request/response/output均达到steady-state 1/cycle；BPU/RAS轻量回归PASS；v12全SoC VCS compile PASS。其后发现公共回归问题，且DV路径生成物已清理，最终状态以上方19:45记录为准。
- 用户手动验收待运行：rvtests ISA、Compliance、CoreMark耗时对比、DC check及其他完整签核；当前工单不标记Completed。

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
