# SDC 案例：用约束临时屏蔽 SRAM Load 前递假路径

日期：2026-07-01

## 案例背景

`SRAM_IMPL=macro` 综合后，DC 报告到一组 setup 近关键路径：

```text
ITCM SRAM macro QB
-> MAU load data select
-> EXU forwarding
-> BRU compare / redirect
-> ctrl_hazard flush
-> CSR mtval register
```

代表性路径：

```text
Startpoint: u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p
Endpoint:   u_core/u_csr_regs/r_mtval_reg[31]
slack:      0.01 ns
```

从微架构看，load-use 相关会 stall 1 拍，紧邻 load 的依赖指令不会在 load 位于 MAU 且 SRAM 数据刚返回的同周期进入 EXU 使用该数据。真实使用应来自下一拍 WBU 寄存后的前递。

因此该路径很可能是功能不可达路径。推荐长期方案是修改 RTL，拆分 “load 写回数据” 和 “MAU-stage 前递数据”。本文只作为 SDC 学习案例，说明如果想临时用约束屏蔽这类路径，应如何写、有什么风险。

## 重要原则

SDC 约束只告诉 STA 如何分析路径，不改变 RTL，也不改变网表功能。

错误的 `set_false_path` 或 `set_multicycle_path` 会隐藏真实时序问题。因此：

- 能改 RTL 表达真实结构时，优先改 RTL。
- 只有能证明路径功能不可达时，才考虑 `set_false_path`。
- 只有能证明路径确实跨多个周期传输时，才考虑 `set_multicycle_path`。
- 写约束时范围越窄越好。

## 方案 1：对特定终点设置 false path

如果只想屏蔽当前报告中 “ITCM macro 到 CSR `mtval`” 的这组路径，可以从 macro cell 到 `r_mtval_reg[*]/D` 设置 false path。

示例：

```tcl
set_false_path \
  -from [get_cells u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p] \
  -to   [get_pins  u_core/u_csr_regs/r_mtval_reg*/D]
```

含义：

- `-from` 指定从 ITCM SRAM macro 发射的 timing paths。
- `-to` 指定到 CSR `mtval` 寄存器 D 端的 timing paths。
- 被匹配到的路径不再做 setup/hold timing 检查。

优点：

- 范围相对窄，只屏蔽当前观察到的 endpoint 族。

缺点：

- 只屏蔽 `mtval` 终点。如果同一条 SRAM load 前递路径还影响其他 endpoint，仍会继续被报告。
- 如果未来真的存在 SRAM load data 同周期影响 `mtval` 的合法功能路径，这条约束会掩盖真实问题。

## 方案 2：对 SRAM macro 到 EXU/BRU 路径设置 false path

如果已经确认 “SRAM load data 不允许作为 MAU-stage 前递源进入 EXU” 是架构规则，可屏蔽从 ITCM/DTCM macro 到 EXU BRU 的路径。

示例：

```tcl
set_false_path \
  -from [get_cells u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p] \
  -through [get_pins u_core/u_exu/u_exu_bru/*]
```

如果 DTCM 也有同类路径，可补充：

```tcl
set_false_path \
  -from [get_cells u_dmem/u_dtcm_sram_wrapper/u_smic55_4096x32_1rw] \
  -through [get_pins u_core/u_exu/u_exu_bru/*]
```

含义：

- 从 SRAM macro 出发，并且经过 BRU 的路径不做 STA。

优点：

- 更接近本案例的假路径本质：load data 不应在同周期进入 EXU/BRU。

缺点：

- 比方案 1 范围更宽。
- `-through [get_pins .../*]` 匹配粒度较粗，可能误伤其他真实路径。
- 更适合作为临时探索，不适合作为长期签核约束。

## 方案 3：对 MAU load data 到 EXU forwarding 设置 false path

理论上最精准的是屏蔽：

```text
MAU load data mux output -> EXU forwarding input
```

但当前 RTL 中 `o_wb_data_mau` 同时表示：

- load 写回数据
- 非 load MAU-stage 前递数据

如果直接屏蔽 `u_core/u_mau/o_wb_data_mau[*]` 到 EXU，可能连非 load 前递真实路径也一起屏蔽。因此在当前 RTL 结构下不推荐这么写。

如果后续 RTL 已经拆出专用 `o_fwd_data_mau`，通常也不再需要这条 SDC 豁免，因为物理假路径已经不存在。

## 方案 4：multicycle path 示例

如果要表达 “这条路径允许两个周期完成”，可以用 `set_multicycle_path`。

示例：

```tcl
set_multicycle_path 2 -setup \
  -from [get_cells u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p] \
  -to   [get_pins  u_core/u_csr_regs/r_mtval_reg*/D]

set_multicycle_path 1 -hold \
  -from [get_cells u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p] \
  -to   [get_pins  u_core/u_csr_regs/r_mtval_reg*/D]
```

含义：

- `-setup 2`：setup 捕获沿放到第 2 个周期。
- `-hold 1`：hold 检查相应调整，避免 hold 被错误放松。

注意：

- 对 N 周期 setup multicycle，常见配套是 hold 设置为 `N-1`。
- multicycle 表示“路径真实存在，但允许多周期传输”。
- 如果路径功能上根本不可达，用 `set_false_path` 语义更直接。
- 本案例中，如果 load data 应该只能从 WBU 寄存后一拍被使用，更推荐改 RTL，而不是用 multicycle 描述一个本不该作为组合连接存在的路径。

## 如何确认约束是否生效

加入约束后重新综合或重新读 DDC 并 source 约束，再报告 timing：

```tcl
report_timing -delay max -path full -nets -capacitance -max_paths 10
report_exceptions -verbose
```

重点检查：

- 原来的 SRAM macro 到 `r_mtval_reg[*]` 路径是否消失。
- `report_exceptions` 是否列出了新增的 false/multicycle exception。
- 新的 top10 setup path 是否合理。
- 是否误屏蔽了其他应当收敛的真实路径。

也可以检查指定路径是否仍可被报告：

```tcl
report_timing -delay max \
  -from [get_cells u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p] \
  -to   [get_pins  u_core/u_csr_regs/r_mtval_reg*/D] \
  -path full -max_paths 5
```

如果设置了 false path，该路径通常不会再作为 timing path 被正常分析。

## 推荐结论

本案例的推荐处理顺序：

1. 优先改 RTL：拆分 `o_wb_data_mau` 和 MAU-stage 前递数据。
2. 用仿真验证 load-use、load-branch、load-jalr、非 load 前递。
3. 重新综合 macro 版，观察新的 top10 setup path。
4. 只有在学习、定位或临时实验时，才使用本文 false path/multicycle 写法。

长期签核约束中不建议保留宽范围的 SRAM macro 到 EXU/BRU false path，除非已有充分功能证明和 review 记录。
