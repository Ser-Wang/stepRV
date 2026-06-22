# RISC-V CSR 与异常/中断机制学习笔记

本文面向 RV32I/RV32IM 这类教学或微控制器风格的 RISC-V core 实现。目标不是复制完整手册，而是把 RISC-V 标准中和 CSR、异常、trap、中断有关的要求整理成便于学习和指导 RTL 实现的结构。

参考标准：RISC-V ISA Manual, Volume I Unprivileged Architecture 与 Volume II Privileged Architecture, official release 20260120。阅读时要注意：标准分配了很多 CSR 地址，但“分配地址”不等于“所有实现都必须实现”。具体需要哪些 CSR，取决于实现支持的权限模式、扩展、计数器、PMP、虚拟内存、Hypervisor 等特性。

特别注意：`RV32I` base integer ISA 本身不包含 CSR 访问指令。要执行 `csrrw/csrrs/csrrc` 等指令，需要实现 `Zicsr` 扩展；privileged architecture 依赖 `Zicsr` 来访问特权 CSR。

## 1. 基本概念

### 1.1 CSR 是什么

CSR 是 Control and Status Register。RISC-V 为每个 hart 定义一个 12-bit CSR 地址空间，所以最多可编码 4096 个 CSR。

CSR 主要服务于以下功能：

- 描述 hart 和 ISA 能力，例如 `misa`, `mvendorid`, `marchid`。
- 配置 trap/异常/中断入口，例如 `mtvec`, `stvec`。
- 记录 trap 原因和返回地址，例如 `mepc`, `mcause`, `mtval`。
- 控制中断使能和中断挂起状态，例如 `mie`, `mip`, `sie`, `sip`。
- 控制权限、内存保护和地址转换，例如 `mstatus`, `pmpcfgN`, `pmpaddrN`, `satp`。
- 提供计数器和性能监控，例如 `cycle`, `instret`, `mcycle`, `minstret`。

### 1.2 权限模式

RISC-V privileged architecture 以权限模式组织 CSR：

| 模式 | 编码 | 典型用途 | 备注 |
| --- | --- | --- | --- |
| U-mode | `00` | 用户程序 | 可选。没有特权控制能力。 |
| S-mode | `01` | 操作系统内核 | 可选。需要 M-mode 支持委托和虚拟内存等机制。 |
| H extension | - | Hypervisor/虚拟化 | 可选扩展，不是普通权限编码里的一个简单模式。 |
| M-mode | `11` | 机器固件、裸机运行时、最高权限 | 所有 hart 都从 M-mode 管理开始；最小 MCU 可以只实现 M-mode。 |

高权限模式可以访问同级和低级别可访问的 CSR；低权限模式访问高权限 CSR 会触发 illegal-instruction exception。

### 1.3 CSR 地址编码惯例

CSR 地址高 4 位带有访问权限惯例：

- `csr[11:10]`：`11` 表示 read-only，其余编码表示 read/write。
- `csr[9:8]`：最低可访问权限级别。`00` 为 U-level，`01` 为 S-level，`10` 为 H/VS 相关，`11` 为 M-level。

这个编码可帮助硬件快速判断非法 CSR 访问：

- 访问不存在 CSR：非法指令异常。
- 当前权限不足：非法指令异常。
- 写 read-only CSR：非法指令异常。
- 写 read/write CSR 中的只读字段：通常忽略只读字段写入，不一定异常。

### 1.4 常见字段属性

| 属性 | 含义 | RTL 实现提示 |
| --- | --- | --- |
| WARL | Write Any, Read Legal | 软件可写任意值，读回必须是合法值。硬件可规范化或屏蔽不支持的位。 |
| WLRL | Write Legal, Read Legal | 软件应只写合法值；硬件只保证读回合法值。常见于 cause code。 |
| WPRI | Writes Preserve, Reads Ignore | 保留字段。软件写时应保持原值，读时不要依赖。 |
| W1C | Write One to Clear | 写 1 清除对应位。常用于某些 pending/status 位，但不是所有 CSR 都如此。 |
| RO | Read Only | 写会非法，或字段硬连为只读。 |

实现时不要把所有 CSR 简单做成普通寄存器。很多字段需要硬连 0、硬连实现能力、写入屏蔽、或由硬件事件更新。

## 2. Zicsr 指令语义

Zicsr 定义 6 条 CSR 访问指令：

| 指令 | 功能 | 写入源 |
| --- | --- | --- |
| `CSRRW` | 原子读旧值到 `rd`，把 `rs1` 写入 CSR | `rs1` |
| `CSRRS` | 读旧值到 `rd`，用 `rs1` 作为 set mask | `old | rs1` |
| `CSRRC` | 读旧值到 `rd`，用 `rs1` 作为 clear mask | `old & ~rs1` |
| `CSRRWI` | `CSRRW` 的立即数形式 | zero-extended `uimm[4:0]` |
| `CSRRSI` | `CSRRS` 的立即数形式 | zero-extended `uimm[4:0]` |
| `CSRRCI` | `CSRRC` 的立即数形式 | zero-extended `uimm[4:0]` |

常见伪指令映射：

| 伪指令 | 等价真实指令 | 含义 |
| --- | --- | --- |
| `csrr rd, csr` | `csrrs rd, csr, x0` | 只读 CSR。 |
| `csrw csr, rs1` | `csrrw x0, csr, rs1` | 写 CSR，不读旧值。 |
| `csrs csr, rs1` | `csrrs x0, csr, rs1` | set CSR bits，不保留旧值到 GPR。 |
| `csrc csr, rs1` | `csrrc x0, csr, rs1` | clear CSR bits，不保留旧值到 GPR。 |
| `csrwi csr, imm` | `csrrwi x0, csr, imm` | 立即数写 CSR。 |

关键边界条件：

- `CSRRW rd=x0`：不读 CSR，因此不触发 CSR read side effect。
- `CSRRS/CSRRC rs1=x0`：只读，不写 CSR，也不触发 CSR write side effect。
- `CSRRSI/CSRRCI uimm=0`：只读，不写 CSR。
- `CSRRW rs1=x0`：不是只读，而是把 0 写入 CSR。
- 访问不存在、权限不足、写 read-only CSR 时，应产生 illegal-instruction exception。

硬件实现提示：

- CSR 指令应是“读-改-写”语义。若 CSR 写发生在 EX 级，要处理和异常精确性之间的冲突。
- 对 `CSRRS/CSRRC`，判断“是否写 CSR”必须看 `rs1` 寄存器编号是否为 `x0`，不是看 `rs1` 的数据值是否为 0。
- 对立即数形式，判断是否写 CSR 看 `uimm` 是否为 0。

## 3. 按权限模式划分的 CSR

### 3.1 U-mode / Unprivileged CSR

U-mode 本身没有 trap 控制权。常见 unprivileged CSR 来自具体扩展：

| CSR | 地址 | 来源 | 功能 |
| --- | --- | --- | --- |
| `fflags` | `0x001` | F/D/Q | 浮点 accrued exception flags。 |
| `frm` | `0x002` | F/D/Q | 浮点动态舍入模式。 |
| `fcsr` | `0x003` | F/D/Q | `fflags` 与 `frm` 的组合 CSR。 |
| `cycle` | `0xC00` | Zicntr | 周期计数器低 XLEN 位，只读。 |
| `time` | `0xC01` | Zicntr | 实时时间计数器低 XLEN 位，只读。 |
| `instret` | `0xC02` | Zicntr | 已退休指令计数器低 XLEN 位，只读。 |
| `cycleh` | `0xC80` | Zicntr, RV32 | `cycle` 高 32 位，只读。 |
| `timeh` | `0xC81` | Zicntr, RV32 | `time` 高 32 位，只读。 |
| `instreth` | `0xC82` | Zicntr, RV32 | `instret` 高 32 位，只读。 |

说明：

- `cycle/time/instret` 不属于 RV32I base 的强制部分，而是 Zicntr 扩展。
- U-mode 能否读这些计数器，还受 `mcounteren` 和 `scounteren` 控制。
- 很多小 core 不实现 U-mode，但仍可在 M-mode 里通过 machine counter CSR 提供计数能力。

### 3.2 M-mode CSR

M-mode 是最高权限模式。只实现 M-mode 的 MCU 风格 core，通常从这一组开始。

#### 3.2.1 Machine Information

| CSR | 地址 | 功能 | 实现建议 |
| --- | --- | --- | --- |
| `mvendorid` | `0xF11` | Vendor ID | 可只读固定值，未知可为 0。 |
| `marchid` | `0xF12` | Architecture ID | 开源或教学 core 可先为 0，或申请/记录唯一 ID。 |
| `mimpid` | `0xF13` | Implementation ID | 表示实现版本。 |
| `mhartid` | `0xF14` | 当前 hart ID | 单核常为 0。 |
| `mconfigptr` | `0xF15` | 配置结构指针 | 不支持可为 0。 |

#### 3.2.2 Machine Trap Setup

| CSR | 地址 | 功能 | 最小实现关注点 |
| --- | --- | --- | --- |
| `mstatus` | `0x300` | 全局状态与权限栈 | 至少关注 `MIE`, `MPIE`, `MPP`, `MPRV`；只支持 M-mode 时很多位可硬连 0。 |
| `misa` | `0x301` | ISA base 和扩展位 | RV32I 应能反映 `MXL=1` 和 `I` 位；不支持动态开关时可只读或 WARL。 |
| `medeleg` | `0x302` | 异常委托到 S-mode | 仅 M-mode 可不实现或硬连 0。 |
| `mideleg` | `0x303` | 中断委托到 S-mode | 仅 M-mode 可不实现或硬连 0。 |
| `mie` | `0x304` | M-mode interrupt enable | 支持中断时必须实现对应 enable 位。 |
| `mtvec` | `0x305` | M-mode trap handler base | 包含 `BASE` 和 `MODE`。direct/vectored 入口由它决定。 |
| `mcounteren` | `0x306` | 允许低权限读计数器 | 无 U/S-mode 可硬连 0。 |
| `mstatush` | `0x310` | RV32 的 `mstatus` 高半部分 | 只实现简单 RV32 M-mode 时常可简化。 |

`mtvec` 的 `MODE`：

- `0`: Direct。所有 trap 跳到 `BASE`。
- `1`: Vectored。同步异常仍跳到 `BASE`；中断跳到 `BASE + 4 * cause`。
- 其他编码保留或由扩展定义。`BASE` 对齐要求和实现支持的 mode 有关。
- `BASE` 至少需要满足 4-byte 对齐；vectored mode 可能要求更严格对齐，因为硬件要在 `BASE + 4*cause` 处分发入口。

#### 3.2.3 Machine Trap Handling

| CSR | 地址 | 功能 | 硬件写入时机 |
| --- | --- | --- | --- |
| `mscratch` | `0x340` | M-mode trap handler 临时寄存器 | 软件读写，硬件通常不改。 |
| `mepc` | `0x341` | trap 返回 PC | trap 进入 M-mode 时写入被中断/异常指令 PC。 |
| `mcause` | `0x342` | trap 原因 | trap 进入 M-mode 时写入 interrupt bit 和 cause code。 |
| `mtval` | `0x343` | trap 附加值 | 地址异常可写 fault address；非法指令可写指令编码；不提供信息时可写 0。 |
| `mip` | `0x344` | M-mode interrupt pending | 外设/计时器/软件中断源置位，部分位可由软件写。 |
| `mtinst` | `0x34A` | transformed trap instruction | Hypervisor 相关，简单 core 可不实现。 |
| `mtval2` | `0x34B` | second trap value | Hypervisor 相关，简单 core 可不实现。 |

#### 3.2.4 Machine Counters

| CSR | 地址 | 功能 | RV32 注意 |
| --- | --- | --- | --- |
| `mcycle` | `0xB00` | 周期计数器低 XLEN 位 | RV32 需要 `mcycleh` 组成 64-bit。 |
| `minstret` | `0xB02` | 退休指令计数器低 XLEN 位 | 异常未退休的指令不应计入。 |
| `mhpmcounter3..31` | `0xB03..0xB1F` | 性能事件计数器 | 可选。 |
| `mcycleh` | `0xB80` | `mcycle` 高 32 位 | RV32 only。 |
| `minstreth` | `0xB82` | `minstret` 高 32 位 | RV32 only。 |
| `mhpmevent3..31` | `0x323..0x33F` | 性能事件选择 | 可选。 |
| `mcountinhibit` | `0x320` | 抑制计数器递增 | 若实现 counters，建议实现基本位。 |

### 3.3 S-mode CSR

S-mode 面向操作系统。若不支持 S-mode，下面 CSR 不需要实现，访问应非法或被 M-mode 捕获。

| 分类 | CSR | 地址 | 功能 |
| --- | --- | --- | --- |
| Trap setup | `sstatus` | `0x100` | S-mode 可见的状态位子集。 |
| Trap setup | `sie` | `0x104` | S-mode interrupt enable。 |
| Trap setup | `stvec` | `0x105` | S-mode trap handler base。 |
| Trap setup | `scounteren` | `0x106` | 控制 U-mode 访问计数器。 |
| Trap handling | `sscratch` | `0x140` | S-mode handler 临时寄存器。 |
| Trap handling | `sepc` | `0x141` | S-mode exception PC。 |
| Trap handling | `scause` | `0x142` | S-mode trap cause。 |
| Trap handling | `stval` | `0x143` | S-mode trap value。 |
| Trap handling | `sip` | `0x144` | S-mode interrupt pending。 |
| Address translation | `satp` | `0x180` | S-mode 地址转换和保护。RV32 常见模式为 Bare 或 Sv32。 |
| Environment | `senvcfg` | `0x10A` | S-mode 环境配置。 |
| Timer compare | `stimecmp`, `stimecmph` | `0x14D`, `0x15D` | Sstc 扩展相关。 |

S-mode trap 与 M-mode trap 结构相似，但是否进入 S-mode 取决于 M-mode 的委托寄存器：

- 同步异常是否委托：看 `medeleg[cause]`。
- 中断是否委托：看 `mideleg[cause]`。
- 未委托的 trap 进入 M-mode。

### 3.4 Hypervisor / VS CSR

Hypervisor 扩展用于虚拟化。小型 RV32I core 通常不实现。文档中知道层次即可：

| CSR 族 | 例子 | 功能 |
| --- | --- | --- |
| H-mode trap setup | `hstatus`, `hedeleg`, `hideleg`, `hie`, `htvec`, `hcounteren` | 管理虚拟机 trap、委托、中断。 |
| H-mode trap handling | `hscratch`, `hepc`, `hcause`, `htval`, `hip`, `hvip`, `htinst` | Hypervisor trap 状态。 |
| Guest address translation | `hgatp` | guest physical 到 host physical 的二阶段地址转换。 |
| VS-mode CSR | `vsstatus`, `vstvec`, `vsepc`, `vscause`, `vstval`, `vsatp` | 给 guest OS 看到的虚拟 S-mode CSR。 |

## 4. 异常、trap 与中断

### 4.1 术语区分

| 术语 | 含义 |
| --- | --- |
| Exception | 当前指令执行导致的同步事件，如 illegal instruction, ecall, load misaligned。 |
| Interrupt | 外部或计时器等异步事件，与当前指令不直接绑定。 |
| Trap | exception 或 interrupt 被硬件接收后，切换到 handler 的总称。 |
| Precise trap | trap 发生时，之前指令都已提交，之后指令都没有架构副作用，`xepc` 指向明确的被中断/异常位置。 |

### 4.2 常见 exception cause

| Cause | 名称 | 常见触发 |
| --- | --- | --- |
| 0 | Instruction address misaligned | taken branch/jump 的目标地址不满足 IALIGN。 |
| 1 | Instruction access fault | 取指访问错误。 |
| 2 | Illegal instruction | 未实现指令、非法 CSR 访问、权限不足。 |
| 3 | Breakpoint | `EBREAK` 或断点。 |
| 4 | Load address misaligned | load 地址不满足访问宽度对齐，且实现选择抛异常。 |
| 5 | Load access fault | load 访问错误。 |
| 6 | Store/AMO address misaligned | store/AMO 地址不满足访问宽度对齐，且实现选择抛异常。 |
| 7 | Store/AMO access fault | store/AMO 访问错误。 |
| 8 | Environment call from U-mode | U-mode `ECALL`。 |
| 9 | Environment call from S-mode | S-mode `ECALL`。 |
| 11 | Environment call from M-mode | M-mode `ECALL`。 |
| 12 | Instruction page fault | 虚拟内存取指页错误。 |
| 13 | Load page fault | 虚拟内存 load 页错误。 |
| 15 | Store/AMO page fault | 虚拟内存 store/AMO 页错误。 |

RV32I 小核最先会遇到的通常是 0, 2, 3, 4, 6, 11。

### 4.3 中断类型与配置

RISC-V 标准 cause code 中常见中断：

| Cause | 名称 | Pending 位 | Enable 位 | 典型来源 |
| --- | --- | --- | --- | --- |
| 1 | Supervisor software interrupt | `sip.SSIP` / `mip.SSIP` | `sie.SSIE` / `mie.SSIE` | S-mode IPI。 |
| 3 | Machine software interrupt | `mip.MSIP` | `mie.MSIE` | 其他 hart 或 CLINT/ACLINT 软件中断。 |
| 5 | Supervisor timer interrupt | `sip.STIP` / `mip.STIP` | `sie.STIE` / `mie.STIE` | S-mode timer，常与 Sstc 或 M-mode 转发有关。 |
| 7 | Machine timer interrupt | `mip.MTIP` | `mie.MTIE` | `mtime >= mtimecmp`。`mtime/mtimecmp` 通常是 MMIO，不是普通 CSR。 |
| 9 | Supervisor external interrupt | `sip.SEIP` / `mip.SEIP` | `sie.SEIE` / `mie.SEIE` | PLIC/APLIC 转发给 S-mode。 |
| 11 | Machine external interrupt | `mip.MEIP` | `mie.MEIE` | PLIC/APLIC 转发给 M-mode。 |
| 13 | Counter-overflow interrupt | `mip.LCOFIP` 等 | 对应 enable | Sscofpmf/计数器溢出相关。 |
| >=16 | Platform/custom interrupts | 平台定义 | 平台定义 | SoC 自定义中断源。 |

一个中断被当前模式接收，通常需要同时满足：

1. 对应 pending 位为 1，例如 `mip.MTIP=1`。
2. 对应 enable 位为 1，例如 `mie.MTIE=1`。
3. 当前模式全局中断使能为 1，例如 M-mode 的 `mstatus.MIE=1`。
4. 若存在委托，目标模式和委托配置允许该中断进入对应 handler。
5. 若当前正在更高权限模式执行，低权限中断通常不会抢占高权限执行，除非相关标准机制允许。

### 4.4 Trap 入口硬件流程

以下以进入 M-mode 为例。S-mode 是同构流程，把 `m*` 换成 `s*`。

当硬件决定接受一个 trap：

1. 选择目标权限模式。若支持 S-mode，并且 `medeleg/mideleg` 委托了该 cause，可能进入 S-mode；否则进入 M-mode。
2. 计算 trap PC：
   - 同步异常：`mepc = faulting instruction PC`。
   - 中断：`mepc = interrupted instruction PC`，通常是下一条将执行但尚未提交的 PC。
3. 写 `mcause`：
   - 最高位 interrupt bit：中断为 1，异常为 0。
   - 低位 exception code：写 cause 编号。
4. 写 `mtval`：
   - 地址异常：常写 fault address 或 misaligned target。
   - illegal instruction：可写非法指令编码。
   - 无附加信息时可写 0。
5. 更新 `mstatus` 权限栈：
   - `MPIE = MIE`
   - `MIE = 0`
   - `MPP = trap 前的权限模式`
6. 设置当前权限模式为 M-mode。
7. 计算 handler 入口：
   - `mtvec.MODE=Direct`：`pc = mtvec.BASE`
   - `mtvec.MODE=Vectored` 且 trap 是中断：`pc = mtvec.BASE + 4 * cause`
   - `mtvec.MODE=Vectored` 且 trap 是同步异常：`pc = mtvec.BASE`
8. flush pipeline 中所有 younger 指令，禁止 faulting 指令产生普通写回或访存副作用。

实现关键词：trap redirect 的优先级通常应高于普通 branch/jump；异常提交必须是 precise。

RISC-V trap 硬件不会自动保存通用寄存器 `x1..x31`。硬件只更新上述 CSR 和 PC；handler 入口处保存哪些 GPR、保存到哪里，是软件 ABI 和 trap handler 的责任。`mscratch/sscratch` 常用于帮助软件找到当前 hart 的上下文保存区。

### 4.5 Trap 返回：MRET/SRET

`MRET` 从 M-mode trap handler 返回，核心动作：

1. `pc = mepc`
2. 当前权限模式恢复为 `mstatus.MPP`
3. `MIE = MPIE`
4. `MPIE = 1`
5. `MPP` 被置为最低已支持权限模式；若只支持 M-mode，则可回到 M。
6. 若返回到低于 M-mode 的模式，还要清 `MPRV`。

`SRET` 同理使用 `sepc`, `SPP`, `SIE`, `SPIE`，但执行权限受当前模式和 `mstatus.TSR` 等控制。

## 5. 典型场景对应的硬件状态变化

### 5.1 `ECALL` in M-mode

指令：`ecall`

硬件行为：

1. ID/EX 识别 `ECALL`，且当前模式为 M。
2. 产生同步异常，cause = 11。
3. `mepc = ecall_pc`。
4. `mcause = 11`，interrupt bit = 0。
5. `mtval = 0`。
6. 更新 `mstatus.MPIE/MIE/MPP`。
7. PC 跳到 `mtvec`。
8. handler 若要跳过 `ecall`，软件通常执行 `mepc += 4`，然后 `mret`。

### 5.2 `EBREAK`

指令：`ebreak`

硬件行为：

1. 产生 breakpoint exception，cause = 3。
2. `mepc = ebreak_pc`。
3. `mcause = 3`。
4. `mtval` 一般可为 0，调试实现也可能有额外行为。
5. handler 返回前通常将 `mepc += 4`。

### 5.3 Instruction address misaligned

场景：不支持 C 扩展时 IALIGN=32，taken branch/jump 的目标地址不是 4-byte aligned。

硬件行为：

1. 在执行 branch/jump 的单元中计算 target。
2. 只有 taken control-flow 指令才检查 target alignment；not-taken branch 不应 trap。
3. 发现 misaligned target，产生 cause = 0。
4. `mepc = branch_or_jump_pc`。
5. `mtval = misaligned_target`。
6. PC 跳 `mtvec`，不得去取 misaligned target。

JALR 注意点：

- RISC-V 规定 JALR 目标地址最低 bit 清 0。
- 对 IALIGN=32 的实现，清 bit0 后若 bit1 仍为 1，则 instruction address misaligned。

### 5.4 Load/store address misaligned

场景：`lw` 地址不是 4-byte aligned，或 `lh/lhu/sh` 地址不是 2-byte aligned。

标准允许 execution environment 选择支持或不支持非对齐访问。简单 core 常选择抛 address-misaligned exception。

若选择抛异常：

1. LSU 计算 effective address。
2. 按访问宽度检查 alignment。
3. 发现 misaligned：
   - load cause = 4
   - store/AMO cause = 6
4. `mepc = load_or_store_pc`。
5. `mtval = effective_address`。
6. 禁止该 load 写回 rd。
7. 禁止该 store 修改内存。
8. PC 跳 `mtvec`。

若选择硬件支持非对齐访问：

- 需要拆分访问、拼接 load 数据、处理跨 word/page/总线边界、处理异常精确性。
- 对很多 compliance 测试环境，若参考签名期待 misaligned exception，硬件透明支持非对齐访问会导致测试结果不同。

### 5.5 Machine timer interrupt

典型平台配置：

1. 平台提供 `mtime` 和 `mtimecmp`，通常是 MMIO 寄存器，不是 base CSR。
2. 软件写 `mtimecmp = now + delta`。
3. 软件置 `mie.MTIE=1`。
4. 软件置 `mstatus.MIE=1`。
5. 当 `mtime >= mtimecmp`，平台置 `mip.MTIP=1`。
6. 若中断被接受：
   - `mcause` interrupt bit = 1，cause = 7。
   - `mepc` 写入被中断位置。
   - `mstatus` 保存/关闭全局中断。
   - PC 按 `mtvec` 跳到 handler。
7. handler 更新 `mtimecmp` 或清除中断条件，然后 `mret`。

## 6. 面向当前 RV32I core 的实现建议

如果目标是通过基础 RV32I compliance，并支持裸机程序、CoreMark、简单 trap handler，建议分阶段实现。

### 6.1 最小 M-mode CSR 子集

第一阶段建议支持：

| CSR | 地址 | 原因 |
| --- | --- | --- |
| `mstatus` | `0x300` | trap entry/return 需要 `MIE/MPIE/MPP`。 |
| `mstatush` | `0x310` | RV32 的 `mstatus` 高半部分；简单 M-mode 可大多硬连 0。 |
| `misa` | `0x301` | 软件/测试可能读取或尝试清扩展位；RV32I 应反映 IALIGN/扩展能力。 |
| `mie` | `0x304` | 若实现中断需要。无中断时可先硬连 0，但 CSR 访问策略要明确。 |
| `mtvec` | `0x305` | trap handler 入口。 |
| `mscratch` | `0x340` | handler 保存上下文常用。可软件读写。 |
| `mepc` | `0x341` | trap 返回地址。 |
| `mcause` | `0x342` | trap 原因。 |
| `mtval` | `0x343` | misalign/illegal instruction 测试常用。 |
| `mip` | `0x344` | 若实现中断需要。无中断时可先硬连 0。 |
| `mcycle/mcycleh` | `0xB00/0xB80` | benchmark 计时和基础性能观测。 |
| `minstret/minstreth` | `0xB02/0xB82` | retired instruction 计数。 |
| `cycle/cycleh` | `0xC00/0xC80` | 若实现 Zicntr，给软件读周期计数。可映射到 `mcycle`。 |
| `instret/instreth` | `0xC02/0xC82` | 若实现 Zicntr，可映射到 `minstret`。 |

`medeleg/mideleg/mcounteren` 在只支持 M-mode 时可先不实现或硬连 0；如果访问这些标准 CSR，建议明确选择“合法读写但 WARL 为 0”还是“非法 CSR”。为了兼容更多裸机库，读出 0 的方式通常更友好。

### 6.2 最小异常源

建议优先实现这些同步异常：

| Cause | 异常 | 实现位置 |
| --- | --- | --- |
| 0 | Instruction address misaligned | BRU/JAL/JALR target 检查。 |
| 2 | Illegal instruction | IDU decode fail、非法 CSR 访问。 |
| 3 | Breakpoint | IDU/EXU 识别 `EBREAK`。 |
| 4 | Load address misaligned | LSU 地址检查。 |
| 6 | Store/AMO address misaligned | LSU 地址检查。 |
| 11 | Environment call from M-mode | IDU/EXU 识别 `ECALL`。 |

### 6.3 最小控制流

必须形成一条完整 trap 控制路径：

1. 异常源产生 `exc_valid`, `exc_cause`, `exc_tval`, `exc_pc`。
2. 仲裁多个异常源，保证优先级和精确性。
3. CSR 硬件写 `mepc/mcause/mtval/mstatus`。
4. PC redirect 到 `mtvec`。
5. flush younger pipeline stages。
6. faulting 指令不得执行普通写回或 store。
7. `MRET` 读取 `mepc`，更新 `mstatus`，PC redirect 到 `mepc`。

对于五级流水，关键设计问题是 CSR 写入发生在哪一级：

- 若 CSR 在 EX 级写，控制简单，但必须屏蔽被前序异常冲掉的 CSR 写。
- 若 CSR 在 WB/commit 级写，精确异常自然一些，但需要处理 CSR RAW forwarding。
- 教学 core 可先采用集中 trap 控制器，让所有异常在一个确定阶段提交，降低理解成本。

## 7. 常见误区

- 误区：实现 Zicsr 就等于必须实现所有 CSR。  
  正确：Zicsr 只定义访问 CSR 的指令；具体 CSR 来自 privileged architecture 和扩展。

- 误区：`CSRRS rs1=x0` 和 `CSRRS rs1!=x0 但值为 0` 等价。  
  正确：前者不写 CSR；后者仍是写 CSR 操作，只是 mask 为 0，可能触发 write side effect。

- 误区：`mepc` 应写下一条 PC。  
  正确：同步异常写 faulting instruction PC；handler 软件决定是否 `mepc += 4`。

- 误区：所有 trap 在 vectored `mtvec` 下都跳 `BASE + 4*cause`。  
  正确：vectored mode 只对中断使用 offset；同步异常仍跳 `BASE`。

- 误区：非对齐 load/store 一定非法。  
  正确：标准允许环境定义是否支持非对齐访问；简单 core 通常选择抛 misaligned exception。

- 误区：`mtime/mtimecmp` 是 CSR。  
  正确：常见平台中它们是 memory-mapped timer 寄存器；CSR 侧通过 `mip.MTIP` 和 `mie.MTIE` 接入中断。

## 8. 参考资料

- RISC-V ISA Manual, Volume I: Unprivileged Architecture, official release 20260120, Chapter 6 Zicsr.
- RISC-V ISA Manual, Volume I: Unprivileged Architecture, official release 20260120, Chapter 7 Zicntr/Zihpm.
- RISC-V ISA Manual, Volume II: Privileged Architecture, official release 20260120, Chapter 2 CSR address mapping and CSR listings.
- RISC-V ISA Manual, Volume II: Privileged Architecture, official release 20260120, Chapter 3 Machine-Level ISA.
- RISC-V ISA Manual, Volume II: Privileged Architecture, official release 20260120, Chapter 12 Supervisor-Level ISA.
- RISC-V ISA Manual, Volume II: Privileged Architecture, official release 20260120, Chapter 15 Hypervisor Extension.

官方在线版本：

- <https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html>
- <https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html>
- <https://docs.riscv.org/reference/isa/v20260120/priv/machine.html>
- <https://docs.riscv.org/reference/isa/v20260120/priv/supervisor.html>
- <https://docs.riscv.org/reference/isa/v20260120/priv/hypervisor.html>
