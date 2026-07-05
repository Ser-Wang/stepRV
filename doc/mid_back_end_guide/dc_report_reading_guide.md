# Design Compiler 综合结果查看指南

综合结果默认放在：

```bash
syn/output/<run_name>/
```

## 顶层产物文件

常见文件：

- `syn.log`：DC 完整运行日志。先看这里确认是否出现 `Synthesis finished successfully`，以及是否有 fatal/error。
- `check_error_warning.log`：从 `syn.log` 过滤出的 warning/error 摘要，适合快速扫问题。
- `soc_top.svf`：SVF，即 Setup Verification for Formality 的文件，用于后续形式验证时指导 RTL 到 gate netlist 的等价检查。
- `soc_top_syn.ddc`：Synopsys Design Compiler 数据库，保存综合后的设计状态。可重新 `read_ddc` 打开，用于补打报告、继续分析或增量处理。
- `soc_top_syn.v`：门级 Verilog 网表，供后仿、形式验证、后端实现等使用。
- `soc_top_syn.sdf`：Standard Delay Format 延迟文件，供门级时序仿真标注延迟使用。
- `soc_top_syn.sdc`：综合后导出的约束文件，可给后端 APR 或 PrimeTime 作为约束参考。它不是原始输入 SDC 的简单复制，而是 DC 根据当前设计导出的版本。

如果某次只是运行 `make check`，通常不会生成 `*_syn.v/ddc/sdf/sdc`，只会生成日志和部分 check report。

## 时序

主要文件：

- `rpt/soc_top_timing_max.rpt`：setup timing，最大延迟路径。
- `rpt/soc_top_timing_min.rpt`：hold timing，最小延迟路径。
- `rpt/soc_top_constraints.rpt`：所有约束违例。
- `rpt/soc_top_timing.chk`：`check_timing` 的时序完整性检查。

最关键字段：

```text
slack (MET) ...
```

或：

```text
slack (VIOLATED) ...
```

含义：

- `slack > 0`：时序满足。
- `slack` 接近 0：刚好满足，裕量很小。
- `slack < 0`：时序违例。
- `data arrival time`：数据实际到达 endpoint 的时间。
- `data required time`：数据被要求到达的时间。
- `Startpoint`：路径起点，通常是发射寄存器、macro 输出或输入端口。
- `Endpoint`：路径终点，通常是捕获寄存器或输出端口。
- `Path Group`：路径所在时钟组。
- `Path Type: max`：setup 检查。
- `Path Type: min`：hold 检查。

快速查看：

```bash
grep -n "slack" syn/output/<run>/rpt/soc_top_timing_max.rpt
grep -n "slack" syn/output/<run>/rpt/soc_top_timing_min.rpt
```

判断是否整体有违例，优先看：

```bash
syn/output/<run>/rpt/soc_top_constraints.rpt
```

如果里面出现：

```text
This design has no violated constraints.
```

说明 DC 当前报告到的约束没有违例。

## 面积

主要文件：

- `rpt/soc_top_area.rpt`：顶层面积总览。
- `rpt/soc_top_area_hierarchy.rpt`：层级面积报告。

`soc_top_area.rpt` 常看字段：

- `Number of ports`：端口数量。
- `Number of nets`：net 数量。
- `Number of cells`：映射后的 cell 实例总数。
- `Number of combinational cells`：组合逻辑 cell 数量。
- `Number of sequential cells`：时序 cell 数量，如 flop/latch。
- `Number of macros/black boxes`：macro 或 black box 数量，例如 SRAM macro。
- `Combinational area`：组合逻辑面积。
- `Noncombinational area`：时序逻辑面积。
- `Macro/Black Box area`：macro/black box 面积，SRAM macro 面积通常在这里。
- `Total cell area`：总 cell 面积，是顶层面积最常看的数字。
- `Net Interconnect area`：线网互连面积。如果没有 wire load 或物理信息，可能显示 `undefined`。
- `Total area`：总面积。如果互连面积 undefined，这里也可能 undefined。

查看某个子模块面积：

```bash
syn/output/<run>/rpt/soc_top_area_hierarchy.rpt
```

如果旧 run 没有 `soc_top_area_hierarchy.rpt`，可不重跑综合，直接读取 `.ddc` 补打一份：

```bash
cd ~/work/my-RISCV-Projs/syn
dc_shell-t
```

进入 DC 后执行：

```tcl
read_ddc output/<run>/soc_top_syn.ddc
current_design soc_top
report_area -hierarchy > output/<run>/rpt/soc_top_area_hierarchy.rpt
exit
```

这只读取已综合数据库并打印报告，不会重新综合，也不会改变已有网表。

## 功耗

主要文件：

- `rpt/soc_top_power.rpt`：顶层功耗汇总。
- `rpt/soc_top_power_hierarchy.rpt`：层级功耗拆分。

常看字段：

- `Cell Internal Power`：标准单元或 macro 内部功耗。
- `Net Switching Power`：net 翻转带来的动态功耗。
- `Total Dynamic Power`：总动态功耗。
- `Cell Leakage Power`：静态漏电功耗。
- `Total` 行：汇总 internal、switching、leakage 和总功耗。
- `memory/register/combinational` 等 power group：按类型拆分的功耗。

注意：如果没有真实 SAIF/VCD 活动率标注，DC 会使用默认活动传播，功耗更适合做粗略对比，不适合作为最终功耗签核结果。

查看子模块功耗：

```bash
syn/output/<run>/rpt/soc_top_power_hierarchy.rpt
```

## 设计检查

主要文件：

- `rpt/soc_top_design.chk`：`check_design` 结果。
- `rpt/soc_top_timing.chk`：`check_timing` 结果。
- `rpt/soc_top_constraints.rpt`：约束违例。
- `check_error_warning.log`：warning/error 摘要。

常见 warning：

- `LINT-29`：input 直接 feedthrough 到 output。简单 bus wiring 中可能是预期行为。
- `LINT-31`：输出短接，需要确认是否为有意连接。
- `LINT-52`：常量输出，常见于 unused/tie-off 信号。
- `TIM-134`：high-fanout net。后续可能需要 buffer tree、约束或结构优化。
- `TIM-164`：不同库的 trip point 不一致。SRAM macro `.db` 和标准单元 `.db` 组合时可能出现，需要在更正式 signoff 前确认可接受性。
- `VO-4`：Verilog writer 写出了 `assign` 或 `tran` 语句。
- `VO-11`：Verilog writer 生成 `SYNOPSYS_UNCONNECTED_` net，通常来自未连接的输出或工具生成 pin。

## 推荐查看顺序

1. 看 `syn.log`，确认流程成功结束。
2. 看 `check_error_warning.log`，快速扫 fatal/error/warning。
3. 看 `rpt/soc_top_constraints.rpt`，确认无 violated constraints。
4. 看 `rpt/soc_top_timing_max.rpt` 的 setup slack。
5. 看 `rpt/soc_top_timing_min.rpt` 的 hold slack。
6. 看 `rpt/soc_top_area.rpt` 的总面积和分类面积。
7. 看 `rpt/soc_top_area_hierarchy.rpt` 的子模块面积。
8. 看 `rpt/soc_top_power.rpt` 和 `rpt/soc_top_power_hierarchy.rpt` 的功耗。
