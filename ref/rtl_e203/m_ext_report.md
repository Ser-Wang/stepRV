# rtl_e203 M扩展（乘除法器）调研报告

## 1. 乘法器 (Multiplier)
* **源码位置**: [core/e203_exu_alu_muldiv.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/rtl_e203/core/e203_exu_alu_muldiv.v)
* **设计架构**: 采用 Booth-4 乘法算法。为了达成极低面积的设计目标，乘法器与除法器、主ALU完全共享加法器数据通路，通过状态机迭代控制完成计算（Booth-4乘法逻辑始于 `e203_exu_alu_muldiv.v` 第 262 行，共享ALU加法器请求 `muldiv_req_alu_res` 的逻辑在第 287-296 行以及第 485-518 行附近）。
* **执行周期数**: 17 个周期（1个准备周期 + 16个执行周期。由 `e203_exu_alu_muldiv.v` 第 238 行的 `localparam EXEC_CNT_16 = 6'd16;` 等逻辑控制）。
* **流水线停顿与提交**: **会stall住流水线**。由于复用了普通ALU的硬件资源及写回通道（`e203_exu_alu_muldiv.v` 第 531 行中 `assign muldiv_i_longpipe = 1'b0;` 将长流水线通道请求置死为0），在乘法执行周期内，EXU（执行单元）由于等待模块内部的握手而阻塞，无法执行下一条指令。计算完成后，通过握手接口（`muldiv_o_valid` 信号，第 470 行）进行普通写回顺序同步提交。

## 2. 除法器 (Divider)
* **源码位置**: [core/e203_exu_alu_muldiv.v](file:///d:/Academic/myProjects/my-RISCV-Projs/ref/rtl_e203/core/e203_exu_alu_muldiv.v)
* **设计架构**: 采用不恢复余数法（Non-restoring division）的有符号除法算法（逻辑始于第 321 行 `// The Divider Implementation, using the non-restoring signed division`）。同样与乘法器复用共享的加法器数据通路进行迭代（第 340-344 行使用共享加法器）。
* **执行周期数**: 33 个周期（1个准备周期 + 32个执行周期 + 可能的修正周期。由第 239 行 `localparam EXEC_CNT_32 = 6'd32;` 及后方除法修正状态机逻辑共同控制）。
* **流水线停顿与提交**: **会stall住流水线**。与乘法器行为相同，执行期间阻塞EXU级主路径，等待全部几十个周期计算结束及修正状态后，向EXU流水线正常写回端发起 `muldiv_o_valid`（第 470 行）进行顺序同步提交。
