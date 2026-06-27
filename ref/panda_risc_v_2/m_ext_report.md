# panda_risc_v_2 M扩展（乘除法器）调研报告

## 1. 乘法器 (Multiplier)
* **源码位置**: [core_rtl/panda_risc_v_multiplier.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/panda_risc_v_2/core_rtl/panda_risc_v_multiplier.v)
* **设计架构**: 使用 1 个 18位*18位有符号乘法器（DSP）和 48位累加器拼接实现 33位*33位有符号乘法。可通过参数 `sgn_period_mul` 配置为单周期乘法器直接相乘（第 249-252 行，直接生成 `sgn_prd_mul_res`），或者复用DSP的多周期乘法器（第 208-246 行例化了 `mul_add_dsp` 模块）。
* **执行周期数**: 
  * 单周期配置: 3 个周期（1个输入缓存区 + 1个计算 + 1个结果输出寄存器）。
  * 多周期配置: 8 个周期（1个输入缓存区 + 6个计算 + 1个结果输出寄存器）。在 `panda_risc_v_multiplier.v` 的文件头注释中有详细说明（第 26-36 行）。
* **流水线停顿与提交**: **不stall流水线**。模块例化了深度为 2 的指令输入FIFO缓存区（位于第 99-127 行，`fifo_based_on_regs`），作为乱序执行核心中独立的并发执行单元。前端向其发射计算请求时使用 `s_mul_req_valid` / `s_mul_req_ready` 握手。结果计算完成后，通过输出握手信号 `m_mul_res_valid` (第 149 行产生）将结果写回到物理寄存器/CDB，最终由乱序核心的重排序缓存（ROB）进行顺序提交（Commit），保证精确异常。

## 2. 除法器 (Divider)
* **源码位置**: [core_rtl/panda_risc_v_divider.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/panda_risc_v_2/core_rtl/panda_risc_v_divider.v)
* **设计架构**: 基于不恢复余数法（Non-restoring division）的多周期实现（核心计算在第 176 行之后，其中余数寄存器更新逻辑位于第 265-283 行，商寄存器更新逻辑位于第 286-302 行）。
* **执行周期数**: 22 个周期（1个输入缓存区 + 20个迭代计算 + 1个结果输出寄存器）。在 `panda_risc_v_divider.v` 的文件头注释中详细说明（第 34 行）。
* **流水线停顿与提交**: **不stall流水线**。同乘法器，具备深度为2的输入缓存区（位于第 98-126 行的 `fifo_based_on_regs` 例化），作为独立的功能单元（FU）并发执行。运算结束后在第 143 行产生 `m_div_res_valid` 输出给唤醒总线，不阻塞发射队列，由 ROB 按指令顺序进行提交。
