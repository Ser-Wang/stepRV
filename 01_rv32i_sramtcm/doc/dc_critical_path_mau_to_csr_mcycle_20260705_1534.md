# DC Critical Path Analysis: MAU rd_idx to CSR mcycle

分析时间：2026-07-05 15:34 CST

综合结果目录：
`/home/moxiao/work/my-RISCV-Projs/syn/output/syn_macro_bus_decode_uart_reg_20260702_1050`

参考报告：
`rpt/soc_top_timing_max.rpt`

## 结论摘要

当前 setup top path 已从之前的 SOC_bus/UART read-data 采样路径，转移到 core 内部控制路径：

```text
u_core/u_mau/r_wb_rd_idx_mau_reg[3]
  -> forwarding RAW hazard compare
  -> EXU rs1 forwarding mux
  -> BRU branch/jump redirect logic
  -> ctrl_hazard flush
  -> CSR commit/write gating
  -> u_core/u_csr_regs/r_mcycle_reg[43]
```

该路径的 DC timing 结果：

| 项目 | 数值 |
| --- | ---: |
| Startpoint | `u_core/u_mau/r_wb_rd_idx_mau_reg[3]` |
| Endpoint | `u_core/u_csr_regs/r_mcycle_reg[43]` |
| Data arrival time | 15.66 ns |
| Data required time | 19.60 ns |
| Slack | 3.93 ns |

在 20 ns 时钟约束下，按 `20 ns - slack` 粗略估算，该路径等效最小时钟周期约 16.07 ns，对应约 62.2 MHz。

## 路径含义

这不是单纯的 `mcycle + 1` 计数器进位链。`mcycle` 成为 endpoint，是因为 CSR 写入使能会决定 `r_mcycle` 本周期是正常递增，还是被 CSR 写覆盖。

真正拖长路径的是前半段控制链：

1. `mau.sv` 中 `r_wb_rd_idx_mau` 输出 MAU 阶段目的寄存器编号。
2. `ctrl_hazard.sv` 用该 rd index 和 EXU 阶段 rs index 做 RAW hazard 比较，生成 forwarding select。
3. `exu.sv` 使用 forwarding select 选择 `rs1_fwded`。
4. `exu_bru.sv` 使用 forwarded operand 做分支比较、JALR target 相关逻辑，并生成 redirect/exception 相关控制。
5. `ctrl_hazard.sv` 根据 redirect 生成 flush。
6. `csr_regs.sv` 用 flush/stall 生成 `csr_commit_en`，进而影响 `csr_wr_en` 和 `r_mcycle` D 端选择。

因此，这条路径可理解为：

```text
MAU forwarding dependency -> BRU redirect decision -> global flush -> CSR side-effect commit gating
```

## 可能优化方向

1. 缩短 forwarding compare 到 operand mux 的路径  
   可考虑对 MAU/WBU forwarding select 做更早生成或更局部化，减少 `rd_idx` 比较结果直接打到 EXU operand mux 的深度和扇出。

2. 优化 BRU 比较逻辑  
   当前大小比较仍通过 33-bit subtract 取符号/借位。后续可考虑专门的比较器结构，或把 equality 与 less-than 路径分开优化，降低 BRU redirect 的组合深度。

3. 解耦 redirect/flush 与 CSR side-effect commit  
   当前 redirect 组合结果会一路影响 CSR commit/write gating，再影响 `mcycle` D 端。可以评估是否将 CSR side-effect commit 控制寄存化，或调整 flush/commit 的时序边界。

4. 降低 CSR counter 写入 mux 影响面  
   `mcycle` 每周期递增，同时支持 CSR 写覆盖，导致写使能控制影响 counter D 端。可评估将 counter increment 和 CSR write path 分层，或减少 flush 对高位 counter D 端的直接组合影响。

5. 继续用 top10 report 观察路径族  
   当前 top10 大多集中在 `MAU rd_idx -> CSR mcycle/mcause` 族。优化时建议每次同时查看 `soc_top_timing_max_top10.rpt`，避免只修掉单 bit endpoint 后路径同族迁移。
