# 执行日志：拆分 Load 写回数据与 MAU 前递数据

提出日期：2026-07-01
完成日期：2026-07-01
状态：已完成

## STAR 总结

- **S（背景）**：SRAM macro 版综合后，DC 把 load 数据从 SRAM 输出经 MAU、EXU forwarding、BRU/flush 到 CSR 的组合链路报成接近临界的 setup path，20 ns 时钟约束下 slack 仅约 `0.01 ns`。
- **T（目标）**：在不改变 5 级流水功能行为的前提下，消除这条功能上不可达的 SRAM load 组合前递路径，并保留非 load 指令的 MAU-stage 前递能力。
- **A（动作）**：将 MAU 的写回数据和前递数据拆分：`o_wb_data_mau` 继续承载 load 写回数据到 WBU，新增 `o_fwd_data_mau` 只输出 EXU 结果延后一拍的非 load 前递数据，EXU 的 MAU forwarding 改接 `fwd_data_mau`。
- **R（结果）**：macro 版 DC 最差 setup path 不再从 SRAM macro 起点出发，single worst slack 从约 `0.01 ns` 提升到 `2.68 ns`，时序裕量增加约 `2.67 ns`。按 20 ns 约束下的 worst-path 反推，等效临界周期约从 `19.99 ns` 降到 `17.32 ns`，理论最高频率约从 `50.0 MHz` 提升到 `57.7 MHz`（约 `15.4%`）。该数值用于本轮综合结果说明，非完整 PVT signoff 结论。

## 背景

`SRAM_IMPL=macro` 综合后曾出现一条接近临界的 setup 路径：

```text
u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p
-> u_core/u_mau/o_wb_data_mau
-> u_core/u_exu forwarding
-> u_core/u_exu/u_exu_bru
-> u_core/u_ctrl_hazard/o_flush
-> u_core/u_csr_regs/r_mtval_reg[*]
```

从流水线功能看，紧邻 load 的相关指令会触发 1 拍 load-use stall，并 flush ID/EX。消费者真正进入 EXU 时，load 数据应已经进入 WBU，并通过 `wb_data_wbu` 前递；不应依赖 SRAM load data 在 MAU stage 同周期组合前递。

原 RTL 将 MAU 写回数据和 MAU 前递数据共用为 `wb_data_mau`，导致 DC 能看到 SRAM macro 输出经 MAU load 选择、EXU forwarding、BRU/flush 到 CSR 的组合路径。该路径在功能上不可达，但结构上暴露给了 STA。

## 修改内容

### `de/core/mau.sv`

新增 MAU stage 专用前递输出：

```systemverilog
output wire [31:0] o_fwd_data_mau
```

写回输出保持原语义：

```systemverilog
assign o_wb_data_mau = mau_req_load ? mau_load_data : r_wb_data_exu_d1;
```

新增前递输出只承载 EXU 结果延后一拍的 pass-through 数据，不承载 SRAM load data：

```systemverilog
assign o_fwd_data_mau = r_wb_data_exu_d1;
```

### `de/core/core.sv`

新增内部连线：

```systemverilog
wire [31:0] fwd_data_mau;
```

`mau` 实例连接新增输出：

```systemverilog
.o_fwd_data_mau (fwd_data_mau),
```

`exu` 的 MAU-stage forwarding 输入改接 `fwd_data_mau`：

```systemverilog
.i_fwd_wb_data_mau (fwd_data_mau),
```

`wbu` 仍保持接收 `wb_data_mau`，因此 load 写回路径不变。

## 功能影响确认

- load 写回路径保留：`mau_load_data -> o_wb_data_mau -> wbu -> regfile`。
- 非 load MAU-stage 前递保留：`r_wb_data_exu_d1 -> o_fwd_data_mau -> exu forwarding`。
- SRAM load data 不再进入 EXU 的 MAU-stage forwarding 输入。
- 相邻 load-use 仍依赖既有 hazard 逻辑插入 1 拍 bubble，消费者从 WBU 路径获得 load 数据。

## 验证记录

### VCS ISA 单测

```bash
cd /home/moxiao/work/my-RISCV-Projs/sim
make -f makefile sim_isa test=add SRAM_IMPL=rtl
make -f makefile sim_isa test=add SRAM_IMPL=macro
```

结果：

- `SRAM_IMPL=rtl`：`rv32ui/add` PASS。
- `SRAM_IMPL=macro`：`rv32ui/add` PASS。

### VCS ISA 批量回归

```bash
cd /home/moxiao/work/my-RISCV-Projs/sim
make -f makefile sim_isa_all type=isa group=rv32ui SRAM_IMPL=rtl
make -f makefile sim_isa_all type=isa group=rv32ui SRAM_IMPL=macro
```

结果：

- `SRAM_IMPL=rtl`：`41/42 Passed`。
- `SRAM_IMPL=macro`：`41/42 Passed`。
- 两种配置唯一失败项均为 `ma_data`。
- `sim_ma_data.fail.log` 显示失败来源为 `sva_exu_lsu.sv` 中 halfword misalign 断言，示例信息为 `PC: 0x00000018, Addr: 0x10000051`。该失败与本次 MAU load forwarding 拆分无直接关联，需在 misaligned access/SVA 策略工单中单独处理。

### DC macro synthesis

```bash
cd /home/moxiao/work/my-RISCV-Projs/syn
make syn SRAM_IMPL=macro OUT_DIR=/home/moxiao/work/my-RISCV-Projs/syn/output/syn_macro_fwd_fix_20260701
```

结果：

- 综合完成，无 fatal/error。
- `rpt/soc_top_constraints.rpt`：`This design has no violated constraints.`
- `rpt/soc_top_timing_max.rpt` 首条 setup path：
  - Startpoint：`u_core/u_exu/r_rs1idx_exu_reg[2]`
  - Endpoint：`u_core/u_csr_regs/r_mcause_reg[0]`
  - Slack：`2.68 ns`
- 当前 single worst setup path 已不再是 SRAM macro 输出经 MAU load data 到 EXU/BRU/CSR 的路径。

## 结论

本次 RTL 已从结构上拆分 MAU 写回数据与 MAU-stage 前递数据。load 数据仍可写回 WBU，但不再直接作为 EXU 的 MAU-stage 前递源，因此原先暴露给 STA 的 SRAM load data 组合前递路径被移除。

保留风险：

- `rv32ui/ma_data` 仍因 misaligned access SVA 失败，需要单独分析该测试预期、异常行为和 SVA 定义。
- 本次 DC 报告仅生成默认 single worst setup path；如需审计 top10/topN，可在当前 `.ddc` 基础上补打多路径 timing report。
