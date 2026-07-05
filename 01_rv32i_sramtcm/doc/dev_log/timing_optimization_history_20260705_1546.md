# Timing Optimization History

记录时间：2026-07-05 15:46 CST

用途：简要记录近期几轮 DC 时序优化脉络，便于后续复盘或面试讲述。这里的频率按 20 ns 约束和 single worst path 粗略反推，不作为 signoff 结论。

## 一句话总结

近期优化先识别并修复了 SRAM load 数据被错误暴露到 MAU forwarding 的虚假关键路径，随后切到 `compile_ultra` 暴露出 SOC_bus/UART 读数据寄存路径，再通过简化地址译码和去掉 UART read-data flop 的无效 enable/reset，把关键路径推回 core 内部 BRU/CSR 控制链；setup slack 从最初约 `0.01 ns` 提升到当前 `3.93 ns`。

## 时间线

| 阶段 | 主要问题/动作 | Worst setup path | Slack | 粗略 Fmax |
| --- | --- | --- | ---: | ---: |
| 初始 macro 综合 | SRAM macro 输出经 MAU load data、EXU forwarding、BRU/flush 到 CSR，STA 可见但功能上偏虚假 | `ITCM SRAM -> CSR mtval` | `0.01 ns` | `50.0 MHz` |
| 修复 load forwarding false path | MAU 拆分 `o_wb_data_mau` 和 `o_fwd_data_mau`，load 数据不再进入 MAU-stage forwarding | `EXU rs1idx -> CSR mcause` | `2.68 ns` | `57.7 MHz` |
| 切到 `compile_ultra` | 优化裕量继续变大，同时新关键路径暴露在 SOC_bus/UART 读数据采样路径 | `WBU rd_idx -> SOC_bus r_uart_rd_data_d1` | `3.88 ns` | `62.0 MHz` |
| 优化 SOC_bus/UART 路径 | 地址译码由 32-bit range compare 改为高位判断；`r_uart_rd_data_d1` 去掉 `sel_uart/load` enable 并单独打一拍 | 当前 top path 变为 `MAU rd_idx -> CSR mcycle` | `3.93 ns` | `62.2 MHz` |

## 关键节点

### 1. 最初的 `0.01 ns` 裕量

初始 macro 版综合中，DC 报告的最差路径从 ITCM SRAM macro 输出开始，经过 SoC bus、MAU load 数据选择、EXU forwarding、BRU redirect/exception 控制，最后进入 CSR `mtval`。  
这个路径说明 RTL 结构上把 load 返回数据暴露给了 EXU 的 MAU-stage forwarding 输入；从流水语义看，相邻 load-use 会插入 bubble，消费者真正可用的是后续 WBU forwarding，因此这条路径偏虚假。

参考：`doc/dc_sram_macro_setup_slack_analysis_20260630.md`

### 2. 修复虚假 forwarding 路径

修复方式是把 MAU 写回数据和 MAU 前递数据拆开：

- `o_wb_data_mau`：继续承载 load 写回数据到 WBU。
- `o_fwd_data_mau`：只输出 EXU 结果延后一拍的非 load 前递数据。
- EXU 的 MAU forwarding 输入改接 `fwd_data_mau`。

修复后，SRAM macro 输出不再是 setup top path，slack 提升到 `2.68 ns`。

参考：`doc/dev_log/ticket_fix_load_forward_false_timing_path.md`

### 3. `compile_ultra` 后暴露 SOC_bus/UART 路径

将 DC 编译方式从普通 `compile` 调整为 `compile_ultra` 后，整体 slack 提升到 `3.88 ns`，但关键路径切换到：

```text
u_core/u_wbu/r_wb_rd_idx_wbu_reg[1]
-> u_soc_bus/r_uart_rd_data_d1_reg[1]
```

这条路径与访存地址路由和 UART read-data 寄存有关。原 RTL 中 `r_uart_rd_data_d1` 只有在 `i_mem_req_load & sel_uart` 时更新，而 `sel_uart` 又来自地址译码。综合后，该 enable 条件和地址路由逻辑被纳入寄存器 D/enable 相关路径，形成新的近关键路径。

### 4. 修复 SOC_bus 地址译码和 UART 数据寄存

根据当前 memory map：

- ITCM：`0x0...`
- DTCM：`0x1...`
- UART：`0x3...`

SOC_bus 地址译码无需完整 32-bit range compare，改为判断 `i_mem_addr[31:28]`。同时，`r_uart_rd_data_d1` 改为每拍直接采样 `i_uart_rd_data`，不再受 `sel_uart/load` enable 控制，也不 reset；有效性由已 reset 的 `rd_sel_uart_d1` 屏蔽。

修复后：

- 全局 worst setup slack：`3.93 ns`
- 当前 top path：`MAU rd_idx -> forwarding/BRU redirect -> flush -> CSR mcycle`
- 定向观察旧 `WBU -> UART` 路径：arrival 从 `15.70 ns` 降到 `7.72 ns`，slack 到 `11.91 ns`

参考：`doc/dc_critical_path_mau_to_csr_mcycle_20260705_1534.md`

## 当前状态

当前关键路径已经不是 SRAM load forwarding，也不是 SOC_bus/UART 路径，而是 core 内部控制路径：

```text
MAU rd_idx
-> forwarding RAW hazard compare
-> EXU rs1 forwarding mux
-> BRU branch/jump redirect
-> ctrl_hazard flush
-> CSR commit/write gating
-> CSR mcycle
```

后续若继续冲频，优先关注 BRU 比较/redirect、forwarding select 到 operand mux、以及 redirect/flush 到 CSR commit gating 的组合深度。
