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

coremark estimate: iterations / iteration_time / clk_freq * 1000

## 满10s所需ITERATIONS 估算

CoreMark 的有效成绩要求 benchmark 主体运行时间至少 10 秒；

UART 打印结果发生在
`stop_time()` 之后，不计入 CoreMark 的 `Total ticks`，但 RTL 仿真等待完整输出时
需要把这段固定打印时间算进去。

数值计算：10 * 1000 / (iteration_time / iterations)