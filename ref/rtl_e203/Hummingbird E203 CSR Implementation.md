# Hummingbird E203 CSR 实现机制分析

在 Hummingbird E203 (蜂鸟 E203) 项目中，CSR (控制和状态寄存器) 指令的实现可以清晰地划分为三个阶段：**指令译码 (Decode)**、**运算控制 (ALU & Datapath)** 和 **寄存器存储与维护 (CSR File)**。

这三个阶段分别对应了 `core/` 目录下的三个关键文件。以下是对其实现机制的详细分析：

## 1. 指令译码：`e203_exu_decode.v`
在这个模块中，指令首先被解析。系统指令（`SYSTEM`，`opcode = 7'b1110011`）中的 CSR 指令（排除 `ecall/ebreak/mret/wfi` 后）被识别出来。

核心逻辑如下：
*   **识别指令类型**：通过 `func3` 字段区分出具体的 6 条 CSR 指令（`csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci`）。
*   **信息打包**：译码模块生成了一组专用的 `csr_info_bus` 信息总线（基于 `E203_DECINFO_CSR_*` 宏定义），其中包括：
    *   **操作标志**：`CSRRW`, `CSRRS`, `CSRRC`。
    *   **操作数来源标志**：`RS1IMM` (指示是否是立即数 `*I` 结尾的指令)。
    *   **边界条件标志**：`RS1IS0` (指示 `rs1` 字段是否为 0，这在 RV 规范中对于 `csrrs/csrrc` 决定是否写入 CSR 至关重要)。
    *   **提取的值**：`ZIMMM` (由 `rs1` 字段提取的 5 位立即数) 和 `CSRIDX` (12 位 CSR 索引)。

## 2. 运算与读写控制：`e203_exu_alu_csrctrl.v`
这个模块位于执行单元 (EXU) 的 ALU 控制流中，负责具体执行 CSR 的位运算以及产生最终对 CSR 寄存器堆的读写控制信号。

核心逻辑如下：
*   **操作数准备 (`csr_op1`)**：判断译码传来的 `rs1imm`。如果是立即数类型，则将 5 位的 `zimm` 零扩展为 32 位；如果是寄存器类型，则直接使用 `rs1` 传来的值 (`csr_i_rs1`)。
*   **读写使能控制 (`csr_rd_en` / `csr_wr_en`)**：遵循 RISC-V 规范的边界情况：
    *   `csr_rd_en`：对于 `CSRRW`，只有在目标寄存器 `rd` 需要被写入（即 `rd != x0`）时才会触发读操作；对于 `CSRRS/RC` 则始终触发读操作。
    *   `csr_wr_en`：对于 `CSRRS/RC`，如果 `rs1` 字段为 0（由 `rs1is0` 指示），则不触发对 CSR 的写使能（变为纯读操作）；`CSRRW` 始终触发写使能。
*   **写回数据计算 (`wbck_csr_dat`)**：
    *   `csrrw` 模式下，直接写入：`csr_op1`
    *   `csrrs` 模式下，按位置 1：`csr_op1 | read_csr_dat`
    *   `csrrc` 模式下，按位清 0：`(~csr_op1) & read_csr_dat`
*   **NICE 协处理器扩展**：该模块还包含对自定义协处理器 (NICE) 的支持。如果访问的 CSR 地址落在特定区间 (`0xExx`)，它会将请求转发给外部的协处理器接口 (`nice_csr_*`)，而不是内部的 CSR 模块。

## 3. 寄存器存储与维护：`e203_exu_csr.v`
这个模块是真实的“CSR 寄存器堆”，存放并管理了所有的内部状态和特权模式机制。

核心逻辑如下：
*   **寄存器实例化**：实例化了 `mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`, `mscratch`, `mcycle`, `minstret` 等机器模式 (M-Mode) 下的核心寄存器（由于 E203 是精简版内核，通常不实现 U/S 模式，故相关寄存器硬连线或未实现）。
*   **更新机制冲突处理**：CSR 的值有两个来源可能发生改变。模块内部使用 MUX 处理了这些更新优先级：
    *   **软件显式写入**：即上方 ALU 计算出的 `wbck_csr_dat`（当 `csr_wr_en` 有效时）。
    *   **硬件事件隐式写入**：例如遇到异常跳入 Trap 时 (`cmt_status_ena` 等)，硬件会自动覆盖 `mstatus.MIE`、`mepc` (写入当前 PC)、`mcause` (写入异常码) 的值。
*   **读出多路选择器 (Read Data MUX)**：`read_csr_dat` 信号是一个巨大的组合逻辑 MUX，通过传入的 `csr_idx` 地址进行匹配，将选中的内部寄存器的值送出，供 CSR 指令和流水线其它部件使用。
*   **自定义控制 (Self-defined CSRs)**：在此模块中还可以看到蜂鸟团队自定义的寄存器，如 `counterstop` (用于暂停计数器省电), `mcgstop` (禁用时钟门控机制以便 Debug) 等，它们占用 ISA 预留或非标准地址区间（如 `0xBFF`, `0xBFE`）。

## 总结：工作流示例
当一条例如 `csrrc x5, mstatus, x6` 进入流水线：
1. **Decode**：识别为 `csrrc`，提取出 CSR 索引 `0x300` (mstatus)，非立即数，生成 `csr_info_bus`。
2. **CSR Ctrl (ALU)**：发送地址 `0x300` 读请求，等待 `e203_exu_csr` 返回当前的 `mstatus` 值。接着使用 `x6` 的反码与读出的值进行按位与 (`&`) 运算，生成 `wbck_csr_dat`，随后发出写请求 `csr_wr_en`。
3. **CSR File**：`e203_exu_csr` 收到写使能和新数据，在时钟边沿更新内部真正的 `mstatus` 触发器，完成状态修改。

## 附：`csr_info_bus` 的传递路径 (Decode -> ALU)
在 `e203_exu_decode.v` 中打包生成的 `csr_info_bus` 并不会直接单飞，而是与其他指令组的信息一起被多路选择 (Multiplex) 进了全局译码总线 `dec_info` 中，其完整流转路径如下：

1. **并入全局总线 (Decode)**：
   在 `e203_exu_decode.v` (Line 985+) 中，`csr_info_bus` 会在指令确认为 CSR 操作 (`csr_op`) 时，被零扩展并与其它类型指令（如 ALU、BJP、LSU）的信息一起 `OR`（逻辑或）到统一的 `dec_info` 端口输出。
2. **经过分发模块 (Dispatch)**：
   `dec_info` 离开 Decode 后，会进入 `e203_exu_disp.v`。Dispatch 模块根据指令类型，将这个综合信息总线路由给后端具体的执行单元（通常是通过握手信号一起传递为 `i_info`）。
3. **提取回 CSR 信息 (ALU)**：
   当指令到达通用算术单元 `e203_exu_alu.v` 时，它会接收到 `i_info`。在 ALU 内部 (Line 263)，它会执行反向提取操作：
   `wire [\`E203_DECINFO_WIDTH-1:0] csr_i_info = {\`E203_DECINFO_WIDTH{csr_op}} & i_info;`
4. **送入 CSR 控制器**：
   最终在 `e203_exu_alu.v` 实例化 `e203_exu_alu_csrctrl` 的地方 (Line 335)，它将上面提取的信号截取低位，精准地传给了控制器的 `csr_i_info` 端口：
   `.csr_i_info (csr_i_info[\`E203_DECINFO_CSR_WIDTH-1:0])`。
至此，信息闭环，由译码端精准传达给了最终负责控制的部件。

---

## 4. CSR 寄存器实现清单

基于 `e203_exu_csr.v` 源码的逐行分析。E203 仅实现 M-Mode（`m_mode = 1'b1`，U/S/H 模式硬连线为 0），所有 User/Supervisor 级别的 CSR 均未实现。共计 **24 个寄存器**。

### 4.1 Trap 处理相关（9 个）

| 地址 | 名称 | 权限 | 实现方式 | 说明 |
|------|------|------|----------|------|
| `0x300` | `mstatus` | MRW | 寄存器（部分字段） | 仅 `MIE`(bit3)、`MPIE`(bit7) 有实际触发器；`MPP`=2'b11 硬连线；`FS`/`XS` 根据 FPU/NICE 配置硬连线为 0；`SD` 为只读导出位 |
| `0x301` | `misa` | MRO | 只读常量 | 根据编译宏静态生成，反映 I/E/M/C/A/F 扩展配置；**不可写** |
| `0x304` | `mie` | MRW | 寄存器 | 仅 `MEIE`(bit11)、`MTIE`(bit7)、`MSIE`(bit3) 可写，其余位硬连线为 0 |
| `0x305` | `mtvec` | MRW | 条件实现 | 定义 `E203_SUPPORT_MTVEC` 时为可写寄存器；否则为只读常量 `E203_MTVEC_TRAP_BASE` |
| `0x340` | `mscratch` | MRW | 条件实现 | 定义 `E203_SUPPORT_MSCRATCH` 时为 32-bit 可写寄存器；否则硬连线为 0 |
| `0x341` | `mepc` | MRW | 寄存器 | 可由 CSR 指令写入或 Trap 硬件自动写入；最低位强制为 0 |
| `0x342` | `mcause` | MRW | 寄存器 | 可由 CSR 指令或 Trap 硬件写入；仅 bit31（中断标志）和 bit[3:0]（异常码）有效，bit[30:4] 硬连线为 0 |
| `0x343` | `mbadaddr` | MRW | 寄存器 | 可由 CSR 指令或 Trap 硬件写入（即 `mtval`） |
| `0x344` | `mip` | MRO | 只读（硬件采样） | `MEIP`(bit11)、`MTIP`(bit7)、`MSIP`(bit3) 由外部中断源经 DFF 同步后反映；**不可软件写入** |

### 4.2 性能计数器（4 个，需定义 `E203_SUPPORT_MCYCLE_MINSTRET`）

| 地址 | 名称 | 权限 | 说明 |
|------|------|------|------|
| `0xB00` | `mcycle` | MRW | 使用 always-on 时钟 (`clk_aon`) 驱动，每拍 +1，可被 `counterstop[0]` 暂停 |
| `0xB80` | `mcycleh` | MRW | `mcycle` 高 32 位，`mcycle` 溢出时 +1 |
| `0xB02` | `minstret` | MRW | 每 commit 一条指令 +1，可被 `counterstop[2]` 暂停 |
| `0xB82` | `minstreth` | MRW | `minstret` 高 32 位 |

### 4.3 机器信息寄存器（4 个，只读）

| 地址 | 名称 | 固定值 | 说明 |
|------|------|--------|------|
| `0xF11` | `mvendorid` | `0x536` | 厂商 ID |
| `0xF12` | `marchid` | `0xE203` | 架构 ID |
| `0xF13` | `mimpid` | `0x1` | 实现 ID |
| `0xF14` | `mhartid` | 外部输入 | 来自 `core_mhartid` 端口 |

### 4.4 调试寄存器（3 个，仅 `dbg_mode` 下可访问）

| 地址 | 名称 | 说明 |
|------|------|------|
| `0x7B0` | `dcsr` | 调试控制与状态；寄存器实体在外部 Debug 模块，本模块仅转发读写使能 |
| `0x7B1` | `dpc` | 调试 PC |
| `0x7B2` | `dscratch` | 调试暂存 |

### 4.5 蜂鸟自定义寄存器（4 个）

| 地址 | 名称 | 有效位 | 功能 |
|------|------|--------|------|
| `0xBFF` | `counterstop` | [2:0] | bit0: 停止 `mcycle`；bit1: 停止 TIME 计数器；bit2: 停止 `minstret` |
| `0xBFE` | `mcgstop` | [1:0] | bit0: 停止 Core 时钟门控；bit1: 停止 TCM 时钟门控（调试用） |
| `0xBFD` | `itcmnohold` | [0] | bit0: 禁用 ITCM SRAM 输出保持特性 |
| `0xBF0` | `mdvnob2b` | [0] | bit0: 禁用乘除法 back-to-back 特性 |

### 4.6 未实现的标准 CSR

| 地址 | 名称 | 未实现原因 |
|------|------|------------|
| `0x000` | `ustatus` | 不支持 U-Mode Trap |
| `0x004` / `0x044` | `uie` / `uip` | 不支持用户级中断委托 |
| `0x005` / `0x041` / `0x042` / `0x043` | `utvec` / `uepc` / `ucause` / `ubadaddr` | 不支持 U-Mode Trap |
| `0xC00` / `0xC80` | `cycle` / `cycleh` | 代码中已注释掉，被 `mcycle`/`mcycleh` 替代 |
| `0x302` / `0x303` | `medeleg` / `mideleg` | 不支持中断/异常委托机制 |

## 5. 关键实现细节

### 5.1 硬件与软件更新优先级
对于 `mstatus`、`mepc`、`mcause`、`mbadaddr` 等同时受 CSR 指令和 Trap 硬件控制的寄存器，**Trap 硬件更新优先级高于 CSR 指令写入**。在 MUX 中 `cmt_*_ena` 条件被优先判断：
```verilog
// mepc 为例 (Line 497)
assign epc_nxt = cmt_epc_ena ? cmt_epc : wbck_csr_dat;
```

### 5.2 时钟域
- `mcycle` / `mcycleh`：使用 **always-on 时钟** (`clk_aon`)，确保核心睡眠时仍持续计数。
- 其余所有寄存器：使用核心时钟 (`clk`)。

### 5.3 访问合法性检查
`csr_access_ilgl` 信号被硬编码为 `1'b0`（Line 103），即 **E203 不检查 CSR 地址非法访问**。对不存在的 CSR 地址读取返回 0（read MUX 无匹配项），写入被忽略，不会触发非法指令异常。
