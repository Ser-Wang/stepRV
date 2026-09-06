# 记录不同配置下coremark运行时长 按仿真时间

| ISA | 微架构备注 | iterations | iteration_time | print_time | CoreMark/MHz estimate |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **rv32i** | | 1 | 20 |  |  |
| **rv32i** | | 5 | 102 | 50 |  |
| **rv32i** | | 10 | 203 | 51 | 0.985 |
| **rv32im** | mul: phase1 | 1 | 14 | 50 |  |
| **rv32im** | mul: phase1 | 5 | 69 | 50 |  |
| **rv32im** | mul: phase1 | 10 | 137 | 50 | 1.460 |
| **rv32im** | mul: phase2 | 10 | 79 | 50 | 2.532 |
| **rv32im** | mul: phase2, bpu | 10 | 74 | 50 | 2.702 |+6.7% BTB,BHT=4
| **rv32im** | mul: phase2, bpu | 10 | 73 | 50 | 2.740 |+8.2% BTB,BHT=8
| **rv32im** | mul: phase2, bpu | 10 | 72 | 50 | 2.778 |+9.7% BTB,BHT=16
| **rv32im** | mul: phase2, bpu | 10 | 71 | 50 | 2.817 |+11.3% BTB,BHT=32
| **rv32im** | mul: phase2, bpu | 10 | 70 | 50 | 2.857 |+12.8% BTB,BHT=64
| **rv32im** | mul: phase2, bpu | 10 | 70 | 50 | 2.857 |+12.8% BTB,BHT=128

coremark estimate: iterations / iteration_time / clk_freq * 1000

## 满10s所需ITERATIONS 估算

CoreMark 的有效成绩要求 benchmark 主体运行时间至少 10 秒；

UART 打印结果发生在
`stop_time()` 之后，不计入 CoreMark 的 `Total ticks`，但 RTL 仿真等待完整输出时
需要把这段固定打印时间算进去。

数值计算：10 * 1000 / (iteration_time / iterations)

## 性能对比

| ISA | 微架构备注 | CoreMark/MHz | 性能对比 |
| :---: | :---: | :---: | :---: |
| **rv32i** | | 0.985 | |
| **rv32im** | mul_v1 | 1.460 | +48.2% (baseline rv32i) |
| **rv32im** | mul_v2 | 2.532 | +157.1% (baseline rv32i) |
| **rv32im** | mul_v2, bpu, 16entries  | 2.778 | +9.7% (baseline rv32im_v2) |
| **rv32im** | mul_v2, bpu, 64entries | 2.857 | +12.8% (baseline rv32im_v2) |
