# SRAM Macro 版 Setup Slack 深入分析

分析时间：2026-06-30 CST

分析对象：

- 综合结果：`syn/output/syn_macro`
- 顶层：`soc_top`
- 约束：`syn/sdc/soc_top.sdc`
- 时钟周期：`20.0 ns`
- clock uncertainty：`0.2 ns`
- 工艺库：SMIC55 标准单元 ss corner + SRAM macro ss corner

## 结论

`SRAM_IMPL=macro` 版 STA 报告中的最差 setup path 位置为：

```text
syn/output/syn_macro/rpt/soc_top_timing_max.rpt
```

该路径：

- Startpoint：`u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p`
- Endpoint：`u_core/u_csr_regs/r_mtval_reg[31]`
- Path Group：`clk`
- Path Type：`max`
- data arrival time：`19.61 ns`
- data required time：`19.62 ns`
- slack：`0.01 ns`

直观地说，STA 看到一条从 ITCM SRAM macro 端口 B 读数据开始，经过 SoC bus、MAU load 数据选择、EXU/BRU 分支地址/异常判断、redirect/flush 控制，最后进入 CSR `mtval` 寄存器的组合路径。

这条路径不是单纯的“SRAM macro 太慢”问题。SRAM macro 的 `CLKB -> QB[8]` 延迟是一个很大的固定起步延迟，但后面还串了较深的 core 组合逻辑，尤其是 BRU 里的 32 位加减/比较链，以及 redirect/flush 到 CSR 写入选择逻辑。

不过结合 RTL 流水线控制看，这条 SRAM load data 到 EXU/BRU 的同周期前递路径很可能是功能不可达路径：load-use 型相关会在 ID 阶段 stall 1 拍并 flush ID/EX，使紧邻的依赖指令不会在 load 位于 MAU 且 SRAM 数据刚返回的同一周期进入 EXU 使用该数据。真实可用的 load 前递应来自下一拍 WBU 寄存后的 `wb_data_wbu`。

因此当前结论应分成两层：

- 从 STA 角度：这是 DC 在现有网表和约束下看到的最差 setup path。
- 从微架构角度：若 load-use stall 逻辑覆盖完整，这条 “SRAM macro -> MAU load data -> EXU forwarding -> BRU/CSR” 路径应当不是有效功能路径，需要用 RTL 或约束把它表达清楚。

## 路径拆解

从 `soc_top_timing_max.rpt` 可以按 `Path` 累计时间把路径切成几段：

| 阶段 | 结束点 | 累计时间 | 本段大致延迟 | 说明 |
|---|---:|---:|---:|---|
| SRAM macro 输出 | `u_smic55_8192x32_2p/QB[8]` | `4.05 ns` | `4.05 ns` | SRAM macro 端口 B 的 clock-to-Q |
| wrapper reset gating | `o_p1_rdata[8]` | `4.14 ns` | `0.09 ns` | wrapper 中 `rst_n ? macro_qb : ZERO_WORD` 综合出的门 |
| SoC bus 选择 | `u_soc_bus/o_mem_rd_data[8]` | `4.51 ns` | `0.37 ns` | ITCM/DTCM/外设读数据 mux |
| MAU load 数据选择 | `u_mau/o_wb_data_mau[0]` | `4.86 ns` | `0.35 ns` | load byte/half/word 及符号扩展相关选择 |
| EXU forward/BRU 输入 | `u_exu_bru/.../A[0]` | `5.37 ns` | `0.51 ns` | load 数据被前递到 BRU operand |
| BRU 32 位减法/比较链 | `DIFF[32]` | `15.96 ns` | `10.59 ns` | `exu_bru` 中 `i_bru_rs1 - i_bru_rs2` 的高位进位链 |
| BRU misaligned/redirect | `o_redirect_req` | `17.59 ns` | `1.63 ns` | 跳转地址 misaligned 异常与 redirect 请求 |
| ctrl_hazard flush | `flush[1]` | `18.01 ns` | `0.42 ns` | redirect 产生流水线 flush |
| CSR mtval 写入选择 | `r_mtval_reg[31]/D` | `19.61 ns` | `1.60 ns` | `i_flush`、异常写入、CSR 写入等选择逻辑 |

最终 required time 为：

```text
20.00 ns clock period
-0.20 ns clock uncertainty
-0.18 ns endpoint library setup time
= 19.62 ns data required time
```

arrival 为 `19.61 ns`，所以只剩：

```text
19.62 - 19.61 = 0.01 ns
```

## 为什么 STA 报告的 macro 版 slack 更紧

macro 版将 ITCM/DTCM 替换成真实 SRAM macro 后，ITCM 读口的数据发射点变成 SRAM macro 本身。报告中 DC 把 `u_smic55_8192x32_2p` 当作由 `clk` 触发的 sequential startpoint，并把 `CLKB -> QB[8]` 的 macro 时序 arc 计入路径。

这使路径一开始就带着 `4.05 ns` 的 SRAM macro clock-to-Q 延迟。之后设计又允许这笔读数据在同一个周期内继续经过：

```text
ITCM read data
-> soc_bus read data mux
-> core/mau load data path
-> EXU forwarding
-> BRU compare/subtract
-> redirect / exception
-> ctrl_hazard flush
-> csr_regs mtval D
```

其中最重的不是 wrapper，也不是 SoC bus，而是 BRU 中的 32 位减法/比较链。从 `A[0]` 到 `DIFF[32]` 约 `10.59 ns`。因此 macro 版 slack 更差的直接原因可以概括为：

1. SRAM macro 读口 `CLKB -> QB` 固定延迟较大，路径起点已经到 `4.05 ns`。
2. 读出的 memory data 没有在 MAU/WB 边界被重新寄存，而是通过前递组合路径影响 EXU/BRU。
3. BRU 的 32 位减法/比较链较深。
4. BRU redirect/异常又继续组合影响 ctrl_hazard 的 flush，再影响 CSR `mtval` 写入选择。

所以这条路径的性质是：

```text
SRAM macro read C2Q + load forwarding + branch compare/redirect + CSR exception write
```

它是当前 macro 版 STA 报告中的最差路径；是否应作为真实需要优化的功能路径，还要结合 load-use stall 和 forwarding 选择来判断。

## 对照 RTL 理解路径是否有效

路径里的层级名可以回到源码中找对应逻辑：

- `sram_itcm_1r1rw_wrapper.sv`：`macro_qb` 到 `o_p1_rdata` 的 reset gating。
- `mau.sv`：`i_mem_rd_data_mau` 到 `o_wb_data_mau` 的 load 数据选择。
- `exu.sv`：forwarding、BRU operand、异常/redirect 汇总。
- `exu_bru.sv`：`adder_result = i_bru_rs1 - i_bru_rs2`、jump misaligned、redirect。
- `ctrl_hazard.sv`：`i_redirect_req` 生成 `flush`。
- `csr_regs.sv`：异常/CSR 写入 `r_mtval`。

这一步很重要：DC 报告给的是门级实例名，源码对照才能知道“为什么这条逻辑会连起来”，以及这条逻辑是否在真实流水线状态下可达。

本设计中：

- `ctrl_hazard.sv` 会对 EX 阶段 load 和 ID 阶段依赖指令产生 `stall_req_lduse_id`。
- load-use 时 PC/IF-ID stall，ID/EX flush。
- 因此紧邻 load 的依赖指令不会在 load 位于 MAU 的周期进入 EXU。
- 下一拍依赖指令进入 EXU 时，load 数据已经经过 WBU 寄存，可从 `wb_data_wbu` 前递。

所以“SRAM macro 输出 -> `o_wb_data_mau` -> EXU forwarding”这条路径，对于 load-use 型相关应当不需要作为单周期 setup 路径收敛。

更通用的 DC timing report 查看方法见：

```text
doc/dc_timing_report_analysis_guide.md
```

## 后续优化方向

如果确认 load-use stall 完整覆盖该场景，推荐优先修改 RTL，把 MAU 到 EXU 的前递数据和 MAU 到 WBU 的写回数据拆开：

- `o_wb_data_mau`：继续保留 load data，用于进入 WBU 寄存并最终写回。
- 新增类似 `o_fwd_data_mau`：只提供非 load 指令的 EX/MEM 阶段结果，不接 SRAM load data。
- EXU 的 `i_fwd_wb_data_mau` 改接 `o_fwd_data_mau`。

这样可以从结构上移除 SRAM load data 到 EXU/BRU 的组合路径，DC 不会再把它当作需要单周期收敛的真实物理路径。这比单纯写 SDC 更稳，因为它让 RTL 接口表达了真实微架构意图。

SDC 方案也可以考虑，但更适合作为辅助手段：

- 若要用 `set_false_path`，必须非常确定该路径在所有指令流、异常、flush、stall 组合下都不可达。
- 若要用 `set_multicycle_path`，必须明确 launch/capture 的周期关系，并同步设置 setup/hold 约束。
- 对这种由数据前递 mux 暴露出的路径，RTL 拆分通常比 SDC 豁免更不容易掩盖真实 bug。

如果目标是进一步优化真实路径，可继续关注：

1. 检查修改后新的 top10 setup path 是否仍集中在 BRU/CSR/flush。
2. 考虑在 MAU/WB 边界增加或利用已有寄存器，避免 load data 参与 EX 阶段同周期组合逻辑。
3. 优化 BRU 比较/加减结构，避免长 ripple-like carry chain 成为主导。
4. 检查异常 `mtval` 写入逻辑是否必须被 `flush` 组合控制到同一周期。
5. 如果只是探索极限频率，可用更详细的 `report_timing -max_paths` 找出是否还有多条同类近关键路径。

当前结论不是“SRAM macro 不能满足 20 ns”，而是“现有 RTL 连线让 STA 看见了一条 SRAM load data 到 redirect/CSR 的同周期组合链”。如果微架构上 load data 必须等 WBU 寄存后一拍再被前递使用，应优先让 RTL 结构反映这一点。
