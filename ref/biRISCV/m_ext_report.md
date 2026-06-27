# biRISCV M扩展（乘除法器）调研报告

## 1. 乘法器 (Multiplier)
* **源码位置**: [src/core/biriscv_multiplier.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/biRISCV/src/core/biriscv_multiplier.v)
* **设计架构**: 直接使用 `*` 运算符，利用底层FPGA的DSP模块实现组合逻辑乘法（位于 `biriscv_multiplier.v` 的第 123 行 `assign mult_result_w = ... * ...`），并加入了寄存器切分为流水线设计。
* **执行周期数**: 可通过参数配置为 2 个或 3 个执行周期（由 `biriscv_multiplier.v` 的第 53 行 `localparam MULT_STAGES = 2;` 控制）。
* **流水线停顿与提交**: 乘法器采用全流水线设计，**不会stall住流水线**。它可以不断接收新的指令（1 cycle issue rate），与其他指令同时执行。执行完成后，利用其独立的写回端口将结果乱序写回寄存器（输出信号 `writeback_value_o` 在 `biriscv_multiplier.v` 的第 142 行赋值）。

## 2. 除法器 (Divider)
* **源码位置**: [src/core/biriscv_divider.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/biRISCV/src/core/biriscv_divider.v)
* **设计架构**: 采用基-1（Radix-1）的恢复余数法（移位减法，Shift-and-subtract），通过简单的迭代状态机完成（迭代计算逻辑位于 `biriscv_divider.v` 的第 158-164 行，包含 `dividend_q <= dividend_q - divisor_q[31:0];` 等逻辑）。
* **执行周期数**: 约 34 个周期（包含32次移位迭代计算以及首尾的状态转换）。
* **流水线停顿与提交**: **不强制stall整条流水线**。除法器也是独立的执行单元，当除法指令发射后，除法器进入busy状态（内部信号 `div_busy_q`，在 `biriscv_divider.v` 第 120, 131 行拉高）。只要后续指令不依赖除法器的结果（无数据冲突），且除法器不发生结构冲突，后续指令依然可以同时执行。完成后通过独立的写回总线乱序提交（握手信号 `writeback_valid_o` 和结果 `writeback_value_o` 在第 190-191 行输出）。
