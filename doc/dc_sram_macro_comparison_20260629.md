# DC 综合 SRAM Macro 对比记录

实验时间：2026-06-29 至 2026-06-30 CST

## 目标

对比 `01_rv32i_sramtcm` 在 Design Compiler 中使用两种存储器实现时的综合结果：

- `SRAM_IMPL=rtl`：使用 `mem_itcm.sv` / `mem_dtcm.sv` 中的 RTL 行为数组。
- `SRAM_IMPL=macro`：使用 SRAM wrapper，并通过 SMIC55 SRAM macro `.db` 进行 link。

## 对比条件

- 顶层：`soc_top`
- 约束：`syn/sdc/soc_top.sdc`
- 时钟周期：`20.0 ns`
- 标准单元库：`scc55ulp_hdlp_rvt_ss_v1p08_125c_ccs.db`
- SRAM macro 库：
  - `smic55_4096x32_1rw_ss_1.08_125.db`
  - `smic55_8192x32_2p_ss_1.08_125.db`
- RTL filelist：
  - 基础 RTL：`01_rv32i_sramtcm/filelists/filelist_rtl.f`
  - SRAM wrapper：`01_rv32i_sramtcm/filelists/filelist_sram_wrapper.f`

## 运行命令

RTL 行为存储器完整综合：

```bash
cd ~/work/my-RISCV-Projs/syn
make syn SRAM_IMPL=rtl OUT_DIR=$PWD/output/syn_rtl
```

SRAM macro 完整综合：

```bash
cd ~/work/my-RISCV-Projs/syn
make syn SRAM_IMPL=macro OUT_DIR=$PWD/output/syn_macro
```

## 汇总对比

| 指标 | RTL 行为存储器 | SRAM macro | RTL / macro |
|---|---:|---:|---:|
| Setup slack | `0.15 ns` | `0.01 ns` | - |
| Hold/min slack | `0.06 ns` | `0.06 ns` | - |
| Constraint violations | 0 | 0 | - |
| Number of nets | `1476562` | `13903` | `106.2x` |
| Number of cells | `1472450` | `9427` | `156.2x` |
| Combinational cells | `1077253` | `7538` | `142.9x` |
| Sequential cells | `395170` | `1858` | `212.7x` |
| Macros/black boxes | `0` | `2` | - |
| Combinational area | `1914638.868471` | `14029.399868` | `136.5x` |
| Noncombinational area | `2103840.267246` | `11339.719760` | `185.5x` |
| Macro/Black Box area | `0.000000` | `433432.679688` | - |
| Total cell area | `4018479.135717` | `458801.799316` | `8.76x` |
| Total dynamic power | `139.7067 mW` | `2.1477 mW` | `65.0x` |
| Cell leakage power | `511.4983 uW` | `112.3642 uW` | `4.55x` |

## RTL 模式观察

RTL full synthesis 已完成：

```bash
syn/output/syn_rtl
```

该模式不 link SRAM macro。DC 将行为存储器综合成大量寄存器和 mux：

- ITCM 行为数组推断为 `r_itcm_reg`，共 `262144` bit flip-flop。
- DTCM 行为数组推断为 `r_dtcm_reg`，共 `131072` bit flip-flop。
- ITCM 读 mux：`8192 x 32`，两处。
- DTCM 读 mux：`4096 x 32`，一处。

层级面积中，存储器模块占绝对主导：

- `u_imem (mem_itcm)`：`2776572.9955`，约 `69.1%`
- `u_dmem (mem_dtcm)`：`1216444.9006`，约 `30.3%`
- `u_core`：`23256.7996`，约 `0.6%`

功耗也基本由行为存储器展开后的逻辑主导：

- `u_imem`：约 `93.034 mW`，约 `66.3%`
- `u_dmem`：约 `46.306 mW`，约 `33.0%`
- `u_core`：约 `0.583 mW`，约 `0.4%`

RTL 模式虽然在 `20 ns` 约束下也能 meet timing，但面积、cell 数、功耗都严重膨胀。该结果适合作为“行为存储器直接综合”的对照，不适合作为真实 TCM 物理实现评估。

## Macro 模式观察

Macro full synthesis 已完成：

```bash
syn/output/syn_macro
```

该模式读取：

- `filelist_rtl.f`
- `filelist_sram_wrapper.f`
- SRAM macro `.db`

不会读取仿真用的 `filelist_sram_macro_model.f`。

结果中 ITCM/DTCM 作为 2 个 SRAM macro/black-box 进入综合：

- Number of macros/black boxes：`2`
- Macro/Black Box area：`433432.679688`

面积中 macro 面积占主导，但标准单元逻辑保持在合理规模：

- Combinational area：`14029.399868`
- Noncombinational area：`11339.719760`
- Macro/Black Box area：`433432.679688`
- Total cell area：`458801.799316`

时序在 `20 ns` 下刚好满足：

- Setup slack：`0.01 ns`
- Hold/min slack：`0.06 ns`

功耗报告显示 macro 模式总动态功耗约 `2.1477 mW`，相比 RTL 行为存储器直接综合低约 `65x`。注意当前功耗未基于真实 SAIF/VCD 活动率标注，适合做相对比较，不适合做最终功耗签核。

## Warning 对比

两种模式共有 warning：

- `TIM-134`：存在 1 个 high-fanout net。
- `VO-4`：Verilog writer 写出了 `assign` 或 `tran`。
- `VO-11`：Verilog writer 在 `exu_bru` 和 `core` 中生成 `SYNOPSYS_UNCONNECTED_` nets。

Macro 模式额外有：

- `TIM-164`：SRAM macro `.db` 和标准单元 `.db` 的 trip point 不一致。

这些 warning 当前没有阻断综合，也没有造成约束违例。若进入更正式的后端/签核流程，应进一步确认 high-fanout 处理、库 trip point 差异是否可接受。

## 结论

`SRAM_IMPL=macro` 是该 SRAM TCM 设计用于面积、时序、功耗评估的正确综合路径。它能保持 CPU 核和外围逻辑规模合理，并把 ITCM/DTCM 作为真实 SRAM macro 计入面积和时序。

`SRAM_IMPL=rtl` 仅适合作为行为模型直接综合的对照。该模式会把 SRAM 行为数组展开为数十万 bit 的 flip-flop 和大规模 mux，导致：

- 总面积约为 macro 模式的 `8.76x`
- 总 cell 数约为 macro 模式的 `156x`
- sequential cell 数约为 macro 模式的 `213x`
- 动态功耗约为 macro 模式的 `65x`

后续做真实实现、面积预算、时序收敛和功耗评估时，应以 `SRAM_IMPL=macro` 的结果为主。
