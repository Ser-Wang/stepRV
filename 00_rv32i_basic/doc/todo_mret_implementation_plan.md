# 分析：当前 `mret` 指令的处理状态

在目前的 `00_rv32i_basic\de\core\idu.sv` 中：
`mret` 指令（`opcode = 1110011`, `funct3 = 000`, `rs2 = 00010`）满足了 `dec_rv32i_system_type` 和 `dec_rv32_func3_000`。
因此，它被错误地笼统归类为了 `dec_rv32i_ecall_ebreak` (Line 147)。

但是，在向后级发射（Dispatch）时，`dec_oper_dispatch_alu/lsu/bru/csr` 均**没有**包含 `dec_rv32i_ecall_ebreak`。
**结果**：目前 `mret` 指令没有被发射到任何执行单元，它在译码阶段结束后就会被丢弃（对应总线为全 0），处理器无法正确执行跳回 `mepc` 的逻辑，也没有触发状态更新。

---

# `mret` 支持的实现方案 (Implementation Plan)

要完整支持 `mret`，不仅需要修正译码，还要处理两个核心行为：
1. **控制流跳转**：将 PC 恢复为 `mepc` 寄存器中的值。
2. **状态恢复**：更新 `mstatus` 寄存器（将 `MIE` 恢复为 `MPIE`，将 `MPIE` 置 1，将 `MPP` 置为 U-mode 等）。

对于其在流水线中的具体派发与执行，有两种架构取舍方案：

## 需要决定的架构权衡 (Open Questions)

### 方案 A：派发给分支执行单元 (BRU)
`mret` 是一条改变控制流的指令，理应由 BRU 处理跳转。
* **具体做法**：将 `mret` 译码后派发到 `exu_bru.sv`。`csr_regs` 需要新增一根输出线把 `mepc` 专线连给 BRU 作为跳转目标。同时，BRU 需要输出一根 `o_mret_exec` 的线去通知 `csr_regs` 更新 `mstatus`。
* **优点**：所有会导致 PC 跳转的逻辑（Branch, JAL, MRET）全部集中在 BRU 中，不需要在顶层额外引入新的 PC 仲裁逻辑。
* **缺点**：跨模块连线较多（需要把 `mepc` 拉到 BRU，再把 `mret_exec` 拉回 CSR），有点破坏模块的职责边界。

### 方案 B：派发给 CSR 执行单元 (EXU_CSR)
`mret` 是特权级相关的指令，和 CSR 的联系最为紧密。
* **具体做法**：将 `mret` 派发给 `exu_csr.sv`。`exu_csr` 直接在内部向 `csr_regs` 发出“我正在执行 mret”的信号，`csr_regs` 随之吐出 `mepc` 并更新 `mstatus`。
* **优点**：特权级与状态寄存器的更新逻辑完全收敛在 CSR 相关模块中。
* **缺点**：`exu_csr` 必须新增两个接口 `o_csr_jump_flag` 和 `o_csr_jump_pc`，并且在 `exu.sv` 层需要用一个选择器把 BRU 的跳转和 CSR 的跳转做一次“或”（OR）操作才能最终送给 PC 寄存器。

## 提议的变更文件清单 (Proposed Changes)

根据选择的方案，将修改以下文件：

### 1. `00_rv32i_basic\de\core\idu.sv`
* **[MODIFY]**: 新增 `dec_rv32i_mret` 独立译码。
* **[MODIFY]**: 将 `mret` 加入到你所选单元（BRU 或是 CSR）的 Dispatch 逻辑中。

### 2. `00_rv32i_basic\de\defines\config.v`
* **[MODIFY]**: 增加对应单元（BRU 或 CSR）控制总线上的 `MRET` 控制位宏定义。

### 3. `00_rv32i_basic\de\core\csr_regs.sv`
* **[MODIFY]**: 增加 `mstatus` 的硬件更新逻辑（捕获到 mret 时，`MIE <= MPIE`, `MPIE <= 1`）。

### 4. `00_rv32i_basic\de\core\exu.sv` & 执行单元
* **[MODIFY]**: 如果选方案 A，修改 `exu_bru.sv` 处理跳转，拉线通知 CSR。
* **[MODIFY]**: 如果选方案 B，修改 `exu_csr.sv` 输出跳转信号，在 `exu.sv` 顶层做 Mux 仲裁。
