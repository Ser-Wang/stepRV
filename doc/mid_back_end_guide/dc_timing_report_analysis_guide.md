# DC Timing Report 查看与补打指南

本文记录 Design Compiler 综合后如何查看 setup/hold timing report，以及如何从已有 `.ddc` 补打更详细的 timing path 报告。

## 基本报告文件

综合输出目录示例：

```text
syn/output/syn_macro/
```

常看文件：

- `rpt/soc_top_constraints.rpt`：约束违例汇总。
- `rpt/soc_top_timing_max.rpt`：setup，也就是 max delay timing。
- `rpt/soc_top_timing_min.rpt`：hold，也就是 min delay timing。
- `rpt/soc_top_timing.chk`：`check_timing` 结果。
- `soc_top_syn.ddc`：DC 保存的综合后数据库，可用于补打报告。

## 先看是否有违例

```bash
cd ~/work/my-RISCV-Projs
less syn/output/syn_macro/rpt/soc_top_constraints.rpt
```

如果看到：

```text
This design has no violated constraints.
```

说明当前 DC 报告到的约束没有违例。不过没有违例不等于裕量充足，还需要继续看 setup/hold slack。

## 查看最差 setup path

```bash
less syn/output/syn_macro/rpt/soc_top_timing_max.rpt
```

优先看这些字段：

- `Startpoint`：路径从哪里发射，通常是寄存器 CK/Q、macro clock/output、input port。
- `Endpoint`：路径在哪里捕获，通常是寄存器 D、macro input、output port。
- `Path Group`：路径所在时钟组。
- `Path Type: max`：setup 检查。
- `data arrival time`：数据实际到达时间。
- `data required time`：数据要求到达时间。
- `slack (MET)`：满足时序，数值越大裕量越大。
- `slack (VIOLATED)`：时序违例，负值大小就是违例量。

快速定位：

```bash
grep -n "Startpoint\\|Endpoint\\|data arrival time\\|data required time\\|slack" \
  syn/output/syn_macro/rpt/soc_top_timing_max.rpt
```

## 读 Point 表

`Point` 表中最重要的是：

- `Incr`：当前 pin/cell/lib arc 贡献的增量延迟。
- `Path`：从 startpoint 累计到当前位置的总延迟。
- `Fanout`：该 net 的扇出。
- `Cap`：该 net 的电容。

基本读法：

1. 从 `Startpoint` 向下读到 `Endpoint`。
2. 遇到层级名变化时，记录路径进入了哪个模块。
3. 遇到较大的 `Incr`，检查当前 cell 或 macro arc 是否是瓶颈。
4. 遇到长串相似单元，通常是在穿过加法器、比较器、mux tree 或优先级选择逻辑。
5. 最后用 `data required time - data arrival time` 对上 slack。

## `-max_paths 10` 的含义

`report_timing -max_paths 10` 表示在当前筛选条件下最多报告 10 条 timing path。

它通常按 slack 从差到好列出最差的 10 条路径。它不是“某一条路径里延迟最大的 10 个 cell”，也不单纯按 data arrival time 排序。setup 分析中最应关注的是 slack，因为 required time 也会受 endpoint、clock uncertainty、setup time、multicycle 等约束影响。


## 从 DDC 补打报告

如果已有 `rpt/soc_top_timing_max.rpt` 只报告了 1 条路径，可以不重新综合，直接读取 `.ddc` 补打更多报告。

```bash
cd ~/work/my-RISCV-Projs/syn
dc_shell-t
```

进入 DC 后执行：

```tcl
set search_path [list . /home/moxiao/pdk/smic55/lib \
  /home/moxiao/pdk/smic55/sram/generated/macros/smic55_4096x32_1rw/lib \
  /home/moxiao/pdk/smic55/sram/generated/macros/smic55_8192x32_2p/lib]

set target_library [list \
  scc55ulp_hdlp_rvt_ss_v1p08_125c_ccs.db \
  smic55_4096x32_1rw_ss_1.08_125.db \
  smic55_8192x32_2p_ss_1.08_125.db]

set link_library [concat [list "*"] $target_library]

read_ddc output/syn_macro/soc_top_syn.ddc
current_design soc_top
link

report_timing -delay max -path full -nets -capacitance -max_paths 10 \
  > output/syn_macro/rpt/soc_top_timing_max_top10.rpt

exit
```

这只读取已综合数据库并补打报告，不会重新综合，也不会改变已有网表。

## 常用筛选方式

只看从某个 macro 出发的路径：

```tcl
report_timing -delay max \
  -from [get_cells u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p] \
  -path full -nets -capacitance -max_paths 10
```

只看到某个寄存器：

```tcl
report_timing -delay max \
  -to [get_pins u_core/u_csr_regs/r_mtval_reg[31]/D] \
  -path full -nets -capacitance -max_paths 10
```

只看经过某段逻辑的路径：

```tcl
report_timing -delay max \
  -through [get_pins u_core/u_exu/u_exu_bru/*] \
  -path full -nets -capacitance -max_paths 10
```

常用选项：

- `-max_paths 10`：最多打印 10 条路径。
- `-from`：限制起点。
- `-to`：限制终点。
- `-through`：限制路径必须经过的 pin/cell。
- `-path full`：打印完整路径。
- `-nets`：把 net 也打印出来，便于看 fanout/cap。
- `-capacitance`：打印 cap 信息。

## 固化到综合流程

如果希望每次综合都自动输出 top10 setup path，可以在 `syn/scr/4_dc_report.tcl` 中增加：

```tcl
redirect $RPT_PATH/${DESIGN_TOP}_timing_max_top10.rpt {
  report_timing -delay max -path full -nets -capacitance -max_paths 10
}
```

这只增加报告输出，不改变综合优化内容。

## 判断路径是否需要处理

STA 默认偏保守。只要网表上有组合连通，工具通常就会分析这条路径，不会自动理解所有流水线状态、valid/flush/stall 互斥关系。

处理顺序建议：

1. 先读 timing report，确认 startpoint、endpoint、slack 和主要延迟段。
2. 回到 RTL，确认路径在真实功能状态下是否可达。
3. 如果路径真实可达，优先优化 RTL 结构或约束目标频率。
4. 如果路径功能不可达，优先考虑 RTL 上拆掉这条不该存在的物理组合通路。
5. 只有在 RTL 不适合修改、且能严格证明不可达或多周期关系时，再考虑 `set_false_path` 或 `set_multicycle_path`。

不要为了让报告好看随意加 false path。错误的时序豁免会掩盖真实问题。
