# 当前版本关键路径分析

日期：2026-07-01 11:15 CST

## 结论摘要

当前版本以 `SRAM_IMPL=macro` 综合结果为主分析对象，报告目录为：

```text
/home/moxiao/work/my-RISCV-Projs/syn/output/syn_macro_fwd_fix_20260701
```

在 `20.0 ns` 时钟约束、`0.2 ns` clock uncertainty、SMIC55 `ss_v1p08_125c` 角下：

- setup 最差路径 slack：`2.68 ns`
- hold 最差路径 slack：`0.06 ns`
- `report_constraints -all_violators`：无违例
- setup 等效临界周期约为 `17.32 ns`
- 理论最高频率约为 `57.7 MHz`

当前 setup 关键路径已经不是 SRAM macro 输出到 MAU/EXU forwarding 的 load 组合路径，而是：

```text
EXU 源寄存器编号
-> hazard forwarding select
-> EXU forwarding operand mux
-> BRU subtract/比较与异常判断
-> redirect/flush
-> CSR exception state 写入选择
```

## 报告来源

主要参考：

```text
syn/output/syn_macro_fwd_fix_20260701/rpt/soc_top_timing_max.rpt
syn/output/syn_macro_fwd_fix_20260701/rpt/soc_top_timing_min.rpt
syn/output/syn_macro_fwd_fix_20260701/rpt/soc_top_constraints.rpt
syn/output/syn_macro_fwd_fix_20260701/rpt/soc_top_area_hierarchy.rpt
syn/output/syn_macro_fwd_fix_20260701/rpt/soc_top_fanout.rpt
syn/output/syn_macro_fwd_fix_20260701/rpt/soc_top_power_hierarchy.rpt
```

约束文件：

```tcl
set clk_period 20.0
create_clock -name clk -period $clk_period [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]
set_input_delay  2.0 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 2.0 -clock clk [all_outputs]
set_max_transition 1.0 [current_design]
```

## Setup 关键路径

### 路径头尾

```text
Startpoint: u_core/u_exu/r_rs1idx_exu_reg[2]
Endpoint  : u_core/u_csr_regs/r_mcause_reg[0]
Path group: clk
Path type : max
Slack     : 2.68 ns
```

关键 timing 数字：

```text
data arrival time : 16.93 ns
data required time: 19.61 ns
slack             :  2.68 ns
```

required time 来自：

```text
20.00 ns clock period
-0.20 ns clock uncertainty
-0.19 ns setup time
= 19.61 ns required time
```

等效临界周期估算：

```text
Tcrit ~= data arrival + uncertainty + setup
      ~= 16.93 + 0.20 + 0.19
      ~= 17.32 ns

Fmax ~= 1 / 17.32 ns ~= 57.7 MHz
```

该 Fmax 是基于本轮 DC single worst path 的估算值，不是完整 PVT signoff 结论。

### 逻辑链路拆解

该路径可以分成 5 段：

1. `r_rs1idx_exu_reg[2]` 输出当前 EX 阶段源寄存器编号。
2. `ctrl_hazard` 根据 EX 源寄存器编号与 MAU/WBU 目的寄存器编号比较，生成 `o_fwding_rs1_sel[1]`。
3. `exu` 使用 forwarding select 选择 BRU 的 `rs1` 操作数，路径进入 `bru_rs1[0]`。
4. `exu_bru` 内部经过 33-bit subtract/比较链，形成分支/跳转相关结果和 `o_exc_req_instr_addr_misaligned_bru`。
5. EXU 输出 redirect/异常相关控制，经 `ctrl_hazard` 生成 `flush[1]`，进入 `csr_regs` 的 CSR/异常提交选择逻辑，最终到 `r_mcause_reg[0]/D`。

从 report 中可以看到几个主要阶段的累计延迟：

| 阶段 | 累计路径延迟 |
| --- | ---: |
| EXU 源寄存器 Q 输出 | `0.37 ns` |
| hazard 比较并生成 `fwding_rs1_sel[1]` | `1.22 ns` |
| EXU forwarding mux 到 BRU `rs1[0]` | `2.33 ns` |
| BRU subtract/比较链结束 | `12.95 ns` |
| BRU misalign/redirect 控制形成 | `14.58 ns` |
| ctrl_hazard 生成 `flush[1]` | `14.98 ns` |
| CSR 写入选择到 `r_mcause_reg[0]/D` | `16.93 ns` |

## 为什么它成为当前关键路径

这条路径跨越了多个组合控制域：

- forwarding hazard 比较逻辑
- EXU operand forwarding mux
- BRU 地址/比较/异常判断
- redirect/flush 控制
- CSR exception state 写入选择

本质上，它把“EX 阶段数据相关选择”和“控制流/异常提交控制”串在同一个周期内。BRU 内部的 subtract/比较链是主要延迟主体，后面又接了 redirect、flush 和 CSR state mux，因此成为当前 single worst setup path。

这也说明上一轮 load forwarding false path 修复已经生效：当前关键路径没有从 SRAM macro 输出起步，也没有经过 MAU load data 选择进入 EXU forwarding。

## Hold 关键路径

当前 hold 最差路径为 UART 内部短路径：

```text
Startpoint: u_uart/rx_q0_reg
Endpoint  : u_uart/rx_start_reg
Path type : min
Slack     : 0.06 ns
```

关键 timing 数字：

```text
data arrival time : 0.30 ns
data required time: 0.23 ns
slack             : 0.06 ns
```

该路径非常短：

```text
rx_q0_reg/Q
-> OAI33V2_HDLPR
-> rx_start_reg/D
```

当前 hold slack 为正，但裕量较小。由于本综合使用 ideal clock network，后续进入布局布线后仍需要关注 UART 这类短路径的 hold 修复。

## 面积和功耗侧观察

macro 版面积主要由 SRAM macro 主导：

| 层级 | 面积占比 |
| --- | ---: |
| `u_imem/u_itcm_sram_wrapper` | `72.9%` |
| `u_dmem/u_dtcm_sram_wrapper` | `21.6%` |
| `u_core` | `5.0%` |
| `u_core/u_exu` | `1.2%` |
| `u_core/u_csr_regs` | `0.8%` |

总 cell area：

```text
458799.559316
```

其中 macro/black-box area：

```text
433432.679688
```

功耗报告中，ITCM macro 同样是主要来源：

| 层级 | 总功耗占比 |
| --- | ---: |
| `u_imem/u_itcm_sram_wrapper` | `69.4%` |
| `u_core` | `26.3%` |
| `u_core/u_regfile` | `15.4%` |
| `u_core/u_exu` | `2.8%` |
| `u_dmem/u_dtcm_sram_wrapper` | `1.3%` |

因此，当前 timing 关键路径在 core 控制/执行逻辑中，但面积和功耗主导项仍是 SRAM macro。

## Fanout 观察

`soc_top_fanout.rpt` 中 fanout 超过 50 的主要网络：

| Net | Fanout | 说明 |
| --- | ---: | --- |
| `clk` | `1861` | ideal clock，高扇出正常，后端 CTS 处理 |
| `u_core/exc_cause_exu[4]` | `178` | 异常 cause bit 扇出较高 |
| `u_core/exc_req_exu` | `55` | EXU 异常请求参与多处控制 |
| `u_core/u_exu/n83` | `55` | EXU 内部控制网络 |
| `u_core/u_csr_regs/n423` | `57` | CSR 内部控制网络 |
| `u_core/u_exu/u_exu_alu/n468` | `64` | ALU 内部网络 |

其中 `exc_req_exu`、CSR 内部控制网络与当前关键路径后半段的异常/CSR 写入选择有关，后续优化时值得一起看。

## 与 RTL memory 版对比

已有 `syn_rtl` 报告中，RTL memory 版 setup 最差路径为：

```text
Startpoint: u_core/u_exu/r_rs1idx_exu_reg[2]
Endpoint  : u_imem/r_p0_rdata_reg[9]
Slack     : 0.15 ns
```

该路径从 EXU/hazard/BRU/redirect 进入 IFU，再驱动 RTL ITCM 读地址和大规模寄存器阵列/读数据逻辑。RTL memory 版的 ITCM 被综合成大量触发器和组合 mux，导致关键路径被存储器实现方式放大。

macro 版将 ITCM/DTCM 替换为 SRAM macro 后，存储器阵列不再以大量触发器/mux 形式进入逻辑关键路径，因此当前 macro 版的 setup slack 提升到 `2.68 ns`，关键路径回到 core 内部控制/BRU/CSR 链路。

## 优化建议

当前 setup slack 已满足 20 ns 约束，短期无需为当前频率继续优化。但如果目标频率继续提高，建议按以下顺序处理：

1. **拆分 redirect/flush 与 CSR 提交路径**：当前路径从 BRU 结果一路串到 CSR `mcause` 写入选择。后续可引入明确的 stage valid/kill/commit 信号，把异常提交边界收敛到更清晰的提交点。
2. **降低 BRU 比较链深度**：BRU subtract/比较链贡献了主要延迟，可考虑针对 branch compare 与 target misalign 检查拆开逻辑，避免所有控制结果共用一条长链。
3. **优化 forwarding select 到 BRU operand 的路径**：hazard 比较和 forwarding mux 当前在关键路径前端，可评估 MAU/WBU forwarding select 是否提前或局部寄存化。
4. **关注高扇出异常控制信号**：`exc_cause_exu[4]`、`exc_req_exu` 和 CSR 内部控制网络扇出较高，后续可结合真实布局后的 net delay 再做 buffer/结构优化。
5. **布局布线后复查 hold**：当前 UART hold slack 仅 `0.06 ns`，进入后端后需重新检查并由 CTS/hold buffer 修复。

## 当前状态

- 当前 macro 版 setup/hold 均满足约束。
- 当前 single worst setup path 为 EXU/hazard/BRU/flush/CSR 控制路径。
- 原先 SRAM load data 到 EXU forwarding 的路径已经不再是关键路径。
- 后续若要冲更高频率，核心工作应集中在 BRU 控制路径和 CSR/异常提交边界，而不是继续处理 MAU load data path。
