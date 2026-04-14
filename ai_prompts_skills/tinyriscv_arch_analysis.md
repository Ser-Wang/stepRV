# TinyRISC-V 处理器架构分析 (Agent Skill)

## 简介 
本组件分析由资深架构师完成，旨在为后续 Agent 任务提供对 `tinyriscv` 开源 RISC-V 处理器核以及 SoC 的快速背景理解。后续涉及该代码库的修改、扩展、DEBUG、或者新指令添加时，请以本文档为重要参考。

## 目录结构
- **`core/`**：处理器核心代码（取指、译码、执行、总线控制、中断控制）。
- **`soc/`**：系统顶层模块，将处理器核（core）、片上总线（RIB）与各个外设进行互联。
- **`perips/`**：外设模块（ROM、RAM、Timer、UART、GPIO、SPI等）。
- **`debug/`**：调试模块，主要包含 JTAG 调试和 UART 串口调试实现。
- **`utils/`**：通用基础模块，如握手协议交互模块，以及触发器封装。

## CPU 核心架构特征 (Core Architecture)
该 CPU 采用精简的**三级流水线架构**（取指 IF -> 译码 ID -> 执行 EX），无单独访存及写回流水段，访存和寄存器写回逻辑合并在 EX 阶段完成，以实现更高的面积效益及简单的分支预测处理。

流水线详细模块：
1. **Instruction Fetch (IF) - 取指阶段**
   - `pc_reg.v`：程序计数器，处理普通 PC 递增以及基于分支（jump）或中断（hold/clint）的 PC 调整。
   - `if_id.v`：IF 和 ID 阶段之间的寄存器，对指令进行节拍同步。

2. **Instruction Decode (ID) - 译码阶段**
   - `id.v`：纯组合逻辑，包含指令解码。根据取得的指令，产生控制信号、读取通用寄存器（`regs.v`）以及控制状态寄存器 CSR 的操作数。
   - `id_ex.v`：ID 和 EX 阶段之间的寄存器传递数据。

3. **Execute (EX) - 执行阶段**
   - `ex.v`：执行单元（ALU），且兼顾总线访存（Load/Store）控制和最后的数据写回控制。
   - `div.v`：除法器单元，由 `ex.v` 调用进行多周期的除法运算。

4. **异常与寄存器 (Exception & Registers)**
   - `regs.v`：32个32位通用寄存器（x0-x31）。
   - `csr_reg.v`：控制和状态寄存器文件，用于特权态和异常处理。
   - `clint.v`：核心本地中断控制器（Core Local Interruptor），负责处理外部中断及系统异常导致的 PC 跳转与状态保存。
   - `ctrl.v`：流水线控制单元，负责流水线冲刷（flush）、暂停（stall）。如果遇到乘除法或跳转，需由其发出 hold 信号。

## SoC 互联架构与外设 (SoC & Bus Architecture)
整个 SoC 的顶层在 `soc/tinyriscv_soc_top.v`。
它采用了一个名为 **RIB (RISC-V Internal Bus)** 的自定义精简总线封装在 `core/rib.v` 中，这是一个支持多主多从交叉互联架构（Crossbar）。

**RIB 接口分布**：
- **Master 0**：CPU EX阶段的数据访存接口（`rib_ex_*`）
- **Master 1**：CPU IF阶段的指令抓取接口（`rib_pc_*`）
- **Master 2**：JTAG Debug 模块内存访问接口
- **Master 3**：UART Debug 模块直接下载接口
- **Slave 0**：ROM（指令存储，通常存放 Boot代码/主程序）
- **Slave 1**：RAM（数据存储）
- **Slave 2**：Timer 定时器
- **Slave 3**：UART 串口
- **Slave 4**：GPIO 控制器
- **Slave 5**：SPI 控制器

> **注**：Slave组件在分配地址空间时，由 `rib.v` 通过高位地址进行片选（Chip Select），并在核心的 `defines.v` 维护映射矩阵。

## 调试接口 (Debug System)
核心支持标准的 RISC-V 外部调试协议（通过 OpenOCD 接入）：
- `debug/jtag_top.v` 实现了基本的 JTAG TAP 控制状态机。
- JTAG 模块作为总线 Master 端，甚至可以在 CPU halt 时直接访问 SoC 上的全部内存或利用专用接口（`jtag_reg_addr_i` 等）直接读写 CPU 通用寄存器。

## 给后续 Agent 的任务建议 (Tips for subsequent tasks)
- **如果要在流水线上添加新指令**：
  1. 在 `core/defines.v` 中追加新指令的 Opcode 和 Func3/Func7 定义。
  2. 在 `core/id.v` 增加对 Opcode 的判读，并分配输出内部专用的操作数及操作标志。
  3. 如果是多周期指令（如自定义加速器），需要在 `core/ex.v` 添加运算逻辑，同时需与 `core/ctrl.v` 配合发出管线挂起请求（`hold_flag`）。
- **如果要在 SoC 增加新外设**：
  1. 需要扩充 `soc/tinyriscv_soc_top.v` 及其引脚。
  2. 需要在 `core/rib.v` 中扩展 Master 或 Slave 端口口径（如增加 s6_xxx），并重新编写基于地址范围的片选逻辑。 
- **关于代码风格**：本项目采用非常标准的 Verilog-2001 开源风格，模块中普遍由 Wire 直连，时序逻辑与组合逻辑严格物理分离设计，请遵循此代码风格以保持项目一致性。
