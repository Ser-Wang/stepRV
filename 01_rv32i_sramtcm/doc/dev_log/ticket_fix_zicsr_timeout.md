# 工单：rv32Zicsr Compliance Tests Timeout

**时间戳**: 2026-06-26 18:10
**作者**: Antigravity | Gemini 3.1 Pro (High)
**状态**: ✅ 已解决

---

## 问题现象 (Issue Description)
运行 `make sim_isa_all type=compli group=rv32Zicsr` 时，该组所有的 compliance 测试（如 `I-CSRRC-01`, `I-CSRRCI-01`, `I-CSRRW-01` 等）全部以失败告终，并且日志中均提示 `Simulation Time Out.`（仿真超时）。

## 根本原因分析 (Root Cause Analysis)
经过排查 RTL 和测试程序的反汇编文件（dump），得出导致超时的完整链路如下：

1. **未实现 `mscratch` CSR 寄存器**
   查看 `tests/rv_compliance_new/rv32Zicsr/I-CSRRC-01.dump` 可以发现，标准的 Zicsr 兼容性测试频繁使用了 `mscratch`（地址 `0x340`）寄存器作为测试指令（如 `csrrc`, `csrrw`）的目标寄存器，以此验证 CSR 读写逻辑。
   但是，在目前的 `01_rv32i_sramtcm/de/core/csr_regs.sv` 设计中，只实现了 `mstatus`, `misa`, `mtvec`, `mepc`, `mcause`, `mtval`, `mcycle`, `minstret` 等寄存器，**并没有实现 `mscratch` 寄存器**。

2. **触发非法指令异常 (Illegal Instruction Exception)**
   由于 `mscratch` 不在 `is_supported_csr` 支持列表中，当执行 `csrw mscratch, t0` 时，`o_csr_illegal_access_raw` 信号被拉高，处理器触发非法指令异常，跳入测试程序设定好的 `trap_vector` 异常处理函数。

3. **陷入无限循环死锁 (Infinite Trap Loop)**
   异常处理程序捕获到非法指令后，会跳入 `write_tohost` 标签，将错误码 `1337`（十六进制 `0x539`）写入到 `tohost` 地址（`0x10000100`），然后通过 `j write_tohost` 指令不断原地跳转，陷入死循环。

4. **Testbench 监测地址不匹配导致超时**
   检查 `tb_soctop_isatest.sv` 的代码发现，当前的测试平台通过监听总线上对地址 `0x10000010` 的写入操作来作为测试结束的标志（`ex_end_flag`）。由于此时代码卡死在向 `0x10000100` (`tohost`) 写入异常错误码的死循环中，测试平台永远等不到向 `0x10000010` 的写入，因此一直挂起，直到 `#1000000` 仿真时间耗尽并强制退出。

## 解决方案探讨 (Proposed Solutions)

### 方案一：在 RTL 中增加 `mscratch` 寄存器的支持 (推荐)
`mscratch` 寄存器（`0x340`）是 RISC-V 机器模式中非常标准的一个暂存寄存器（Scratch Register）。
**作用简介与硬件行为**：
当处理器触发异常并进入机器模式的 Trap handler 时，处理程序需要使用通用寄存器来保存当前的运行上下文。为了不破坏已有的寄存器值，通常会使用 `csrrw` (CSR Read/Write) 指令将一个通用寄存器（如栈指针 `sp`）与 `mscratch` 的值进行原子交换。这样既把原先的栈指针安全地保存到了 `mscratch` 中，又从 `mscratch` 中取出了机器模式专用的异常处理栈指针，从而可以安全地开始压栈保存其他上下文。因此，它是实现标准异常上下文切换的关键硬件设施。

在硬件行为上，`mscratch` 是一个纯粹的“静态”读写寄存器。与会自动递增的 `mcycle` / `minstret` 或在异常发生时由硬件自动更新的 `mepc` / `mcause` 不同，**硬件底层绝对不会主动修改或依赖 `mscratch` 的值**。它完全受控于软件，仅在处理器执行特定的 CSR 指令（如 `csrrw`, `csrrc`, `csrrs`）时才会被动地进行读写操作。

**实施细节：**
- 修改 `csr_regs.sv`，添加一个简单的 32 位读写寄存器 `r_mscratch`。
- 添加地址解码 `wire csr_sel_mscratch = (i_csr_idx == 12'h340);`。
- 将其加入到 `is_supported_machine_csr` 列表。
- 在 `csr_wr_en` 条件下允许对其进行写入，并在 read 逻辑中返回该值。

### 方案二：完善 Testbench 的异常检测和提前退出机制
目前的仿真平台只会在测试正常结束时退出，而当测试程序遇到异常抛出错误码时，却会因为死循环白白浪费仿真时间直到超时。
**实施细节：**
- 修改 `tb_soctop_isatest.sv`，在 `p_compliance_bus_snoop` 块中加入对 `tohost` (`0x10000100`) 的监听。
- 如果检测到对 `tohost` 写入了非 0 且最低位为 1 的值（如本例的 `1337`），说明发生了异常或者 Test Fail，此时可以立即 `report_result(0, "COMPLIANCE")` 并 `$finish`，从而避免挂起超时，大幅提升 debug 效率。

---

## 执行操作记录 (Execution Records)

1. **改进 Testbench 监听逻辑**
   - **修改文件**：`01_rv32i_sramtcm/dv/tb_soctop_isatest.sv`
   - **操作内容**：在 `RVTEST_COMPLIANCE` 保护块下的总线监听逻辑中，新增对 `tohost`（地址 `0x10000100`）写操作的检测。若捕获到非0写入，则立刻 `$finish`。
   - **验证结果**：
     - Zicsr 测试能在仿真约 1us 时迅速拦截死循环并提前退出，打印 `!!! Exception/Trap detected!`。
     - rv32i 和 rv32ui 测试不受影响，均正常运行。向后兼容性验证通过。

2. **RTL 实现 `mscratch` CSR**
   - **修改文件**：`01_rv32i_sramtcm/de/defines/config.v`, `01_rv32i_sramtcm/de/core/csr_regs.sv`
   - **操作内容**：
     - `config.v` 增加宏定义 `` `define CSR_MSCRATCH 12'h340 ``。
     - `csr_regs.sv` 中增加 `r_mscratch` 32位寄存器，支持其相关选通信号，允许正常读写。
   - **验证结果**：
     - 运行命令 `make sim_isa_all type=compli group=rv32Zicsr`。
     - 原本失败的 6 个测试用例全部正常结束，结果显示 `6/6 Passed`。问题得到彻底解决。
