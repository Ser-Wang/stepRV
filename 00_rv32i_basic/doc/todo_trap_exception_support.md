# TODO: Trap & Exception Support for RV32I Compliance

## 背景说明
当前的处理器内核能够跑通基础的数据运算（如 `I-ADD-01`），但在运行以下四个 Compliance 测试用例时失败：
- `I-EBREAK-01`
- `I-ECALL-01`
- `I-MISALIGN_JMP-01`
- `I-MISALIGN_LDST-01`

失败的根本原因是当前处理器尚未实现**异常与陷入（Trap / Exception）机制**。上述用例的 Signature 检查依赖于处理器正确捕获异常、跳转异常向量（`mtvec`），并通过 `mret` 返回。

为支持完整异常处理，需在 RTL 中补充以下模块的支持：

## 1. 指令解码支持 (IDU)
**目标文件**：`idu.sv` (可能需要更新 `config.v` 或 `calc_decinfo.py`)
- [ ] **解码 SYSTEM 指令**：支持识别 `Opcode = 7'b1110011`。
- [ ] **解码 `ecall`**：`funct3=3'b000`, `funct12=12'h000`。
- [ ] **解码 `ebreak`**：`funct3=3'b000`, `funct12=12'h001`。
- [ ] **解码 `mret`**：`funct3=3'b000`, `funct12=12'h302`。

## 2. 异常源检测逻辑 (Exception Detection)
**目标文件**：`idu.sv`, `exu.sv`, `exu_bru.sv`, `exu_lsu.sv`
- [ ] **Environment Call**：在译码或执行阶段识别 `ecall` 指令，上报异常（Exception Code = 11）。
- [ ] **Breakpoint**：在译码或执行阶段识别 `ebreak` 指令，上报异常（Exception Code = 3）。
- [ ] **Instruction Address Misaligned**：在 `exu_bru.sv` 中，分支或跳转目标地址 `target_pc[1:0] != 2'b00` 时，上报异常（Exception Code = 0）。
- [ ] **Load Address Misaligned**：在 `exu_lsu.sv` 中，内存加载不满足对齐要求时（如 `lw` 但 `addr[1:0]!=0`），上报异常（Exception Code = 4）。
- [ ] **Store Address Misaligned**：在 `exu_lsu.sv` 中，内存存储不满足对齐要求时，上报异常（Exception Code = 6）。
- [ ] *(可选)* **Illegal Instruction**：遇到未实现或解码失败的指令时，上报异常（Exception Code = 2）。

## 3. CSR 硬件主动更新逻辑 (CSR Hardware Updates)
**目标文件**：`csr_regs.sv`
- [ ] 增加硬件异常触发接口（如 `i_exc_valid`, `i_exc_cause`, `i_exc_pc`）。
- [ ] **更新 `mepc`**：当发生异常时，硬件自动将当前引发异常的指令 PC 写入 `mepc`。
- [ ] **更新 `mcause`**：当发生异常时，硬件自动将对应的 Exception Code 写入 `mcause`。
- [ ] *(扩展)* 更新 `mstatus` 的 `MIE` 和 `MPIE`（如果将来需要支持中断）。

## 4. 流水线控制与 PC 重定向 (Trap Control & Flush)
**目标文件**：`ctrl_hazard.sv`, `ifu.sv`, `exu.sv`
- [ ] **流水线冲刷 (Flush)**：当检测到有效异常时，立刻产生 Flush 信号，清空 IFU 和当前译码/执行状态，防止错误指令继续写回（Write-Back）。
- [ ] **异常跳转 (Trap Jump)**：发生异常时，通知取指单元（IFU）将下一拍的 PC 强行指向 `mtvec` 寄存器中的值。
- [ ] **异常返回 (mret Jump)**：执行 `mret` 指令时，通知取指单元（IFU）将下一拍的 PC 强行指向 `mepc` 寄存器中的值。

## 5. 验证与联调
- [ ] 在 `tb_soctop_isatest.sv` 再次运行上述 4 个失败的测试用例。
- [ ] 查看波形，确认发生异常的周期中，`mcause`, `mepc` 的写入行为，以及随后一拍 PC 是否跳向 `mtvec` 的地址。
