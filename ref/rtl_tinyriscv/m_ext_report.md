# rtl_tinyriscv M扩展（乘除法器）调研报告

## 1. 乘法器 (Multiplier)
* **源码位置**: [core/ex.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/rtl_tinyriscv/core/ex.v)
* **设计架构**: 在EX（执行）阶段直接使用 `*` 运算符，综合为纯组合逻辑乘法器（位于 `ex.v` 的第 143 行 `assign mul_temp = mul_op1 * mul_op2;`）。
* **执行周期数**: 1 个周期（纯组合逻辑单拍完成）。
* **流水线停顿与提交**: **不会stall流水线**。在单周期内计算完成，与当前流水线的EX阶段同步继续向下流动并顺序提交。

## 2. 除法器 (Divider)
* **源码位置**: [core/div.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/rtl_tinyriscv/core/div.v) 和 控制逻辑在 [core/ex.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/rtl_tinyriscv/core/ex.v)
* **设计架构**: 采用经典的试商法（移位减法/恢复余数法）状态机实现（核心状态机逻辑位于 `div.v` 的第 71-211 行，包含 `STATE_CALC` 计算迭代）。
* **执行周期数**: 至少需要 33 个时钟周期完成一次计算（注释及 `div.v` 内有计数器初始赋值 `count <= 32'h40000000;` 第 122 行）。
* **流水线停顿与提交**: **会stall住流水线**。除法运算期间，除法模块会拉高 `busy_o` 信号（`div.v` 第 95, 121 等多行）。在执行阶段 `ex.v` 模块收到 `div_busy_i` 为 True 时，会将 `div_hold_flag` 设为 `HoldEnable`（`ex.v` 第 230 行），进而向全局控制模块产生 `hold_flag_o`（`ex.v` 第 162 行），暂停PC指针更新以及取指、译码阶段的流水线寄存器更新。等计算结束产生 `ready_o`（`div.v` 第 185 行）后，由 `ex.v` 在第 235 行采纳除法结果，流水线恢复运行并顺序提交结果。
