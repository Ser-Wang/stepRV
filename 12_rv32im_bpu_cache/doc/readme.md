# RV32I Basic 当前版本概览

This file is out-of-date, need update

`00_rv32i_basic` 是一个基于 RV32I + Zicsr 的简化处理器 SoC 设计。当前版本包含基础整数执行、CSR 与异常重定向、片上 TCM 存储系统、简单 SoC 总线和 UART MMIO 外设，可用于 RTL 仿真、FPGA 上板和后续 SoC 功能扩展。

## 设计组成

当前设计由 CPU core、片上存储器、SoC bus 和 UART 外设组成。

```text
soc_top
  |-- core
  |-- soc_bus
  |-- mem_itcm
  |-- mem_dtcm
  `-- uart
```

CPU core 的取指路径直接访问 ITCM；数据访存路径经 `soc_bus` 地址译码后访问 ITCM、DTCM 或 UART。SoC 顶层保持简单的片上系统结构，不包含 cache、复杂互连或中断控制器。

当前版本在存储模型与流水线握手协议上进行了演进，全面采用了“同步读、同步写”的物理 SRAM 模型：
- `mem_itcm` 取指端口升级为标准的同步读取 (`o_fetch_req` 和 `o_fetch_pc`)。IFU 增加了流水级状态寄存器，实现了取指请求和取指数据的 Pipeline 1拍完美对齐。
- `mem_dtcm` 的数据存取也已完全采用标准的同步 SRAM 时序。

## Core 能力

`core` 是一个顺序执行的 32-bit RISC-V core。寄存器堆包含 32 个通用寄存器，`x0` 固定为 0；流水线控制支持基础数据前递、load-use 停顿、分支/异常重定向刷新和寄存器堆同周期写回旁路。

当前实现面向 RV32I 和 Zicsr：

| 类型 | 支持内容 |
| --- | --- |
| RV32I | 基础整数算术逻辑、移位、比较、跳转分支、load/store、LUI/AUIPC |
| Zicsr | CSRRW、CSRRS、CSRRC 及立即数形式 |
| System | ECALL、EBREAK、MRET |
| Fence | FENCE、FENCE.I 的基础处理 |

其中 `FENCE.I` 当前通过重定向刷新取指路径，`MRET` 通过 `mepc` 产生返回重定向。

## 冒险检测与数据前递

流水线冒险控制集中在 `ctrl_hazard`，并以组合逻辑在当前周期生成 stall、flush 和前递选择信号。

- 普通 RAW 前递在消费者指令处于 EX 阶段的同一周期完成。`ctrl_hazard` 比较 EX 阶段源寄存器与 MAU/WBU 阶段目的寄存器，EXU 内部根据 `fwding_rs*_sel` 从本级寄存器值、`fwd_data_mau` 或 `wb_data_wbu` 中选择实际执行操作数。
- 对于 ALU/BRU/CSR 等非 load 结果，若生产者在 MAU、消费者在 EX，结果从 `fwd_data_mau` 前递；若生产者已到 WBU，则从 `wb_data_wbu` 前递。
- load-use 冒险在 load 指令处于 EX、后一条消费者仍处于 ID 的周期被检测。控制逻辑暂停 PC 与 IF/ID，并 flush ID/EX 插入一个气泡。
- load 数据在 load 进入 MAU 的周期由 MAU 根据 `i_mem_rd_data_mau`、地址偏移和符号扩展规则组合生成 `mau_load_data`，作为 `wb_data_mau` 输出到 WBU。MAU-stage 前递源 `fwd_data_mau` 不承载 load 数据；由于相邻消费者被插入一个气泡，消费者真正进入 EX 时 load 已推进到 WBU，因此相邻 load-use 场景实际通过 `wb_data_wbu` 前递给 EX 操作数。

## CSR 与异常

当前版本实现了一个基础机器模式 CSR 子集：

| CSR | 说明 |
| --- | --- |
| `mstatus` | 机器状态寄存器 |
| `misa` | 固定返回当前 ISA 能力 |
| `mtvec` | Trap 入口地址 |
| `mepc` | Trap 返回 PC |
| `mcause` | Trap 原因 |
| `mtval` | Trap 附加信息 |
| `mcycle/mcycleh` | 周期计数器 |
| `minstret/minstreth` | 指令退休计数器存储结构 |
| `cycle/cycleh` | `mcycle` 的只读 shadow view |

异常与重定向在 EX 阶段汇聚。当前已覆盖：

- `ecall`、`ebreak`
- 非法 CSR 访问
- 跳转目标地址非对齐
- load/store 地址非对齐
- `mret` 返回重定向

异常请求会更新 `mepc/mcause/mtval`，并重定向到 `mtvec`；`mret` 使用 `mepc` 作为返回地址。
`mcycle` 按周期递增，`minstret` 的计数入口目前保留，尚未接入完整指令退休事件。

## LSU 机制

当前 LSU 采用简单的一拍地址生成与字节写掩码机制：

- load/store 地址由 `rs1 + imm` 生成。
- `SB/SH/SW` 根据地址低位生成 4-bit byte mask，并对写数据做相应字节移位。
- `LB/LH/LW/LBU/LHU` 的读数据在 MA 阶段按地址偏移选取，并完成符号扩展或零扩展。
- byte 访问允许任意字节地址；halfword 要求 2 字节对齐，word 要求 4 字节对齐。
- halfword/word 非对齐 load/store 会触发 misalign 异常，并屏蔽对应的访存读写副作用。

当前 LSU 不做跨 word 的非对齐拆分访问，也不包含总线等待、重试或访问错误响应处理。

## 存储系统与 MMIO

当前内存图由 `de/defines/config.v` 定义：

| 地址范围 | 目标 | 大小 | 说明 |
| --- | --- | ---: | --- |
| `0x0000_0000` - `0x0000_7FFF` | ITCM | 32 KB | 指令存储，数据侧也可读写 |
| `0x1000_0000` - `0x1000_3FFF` | DTCM | 16 KB | 普通数据存储 |
| `0x3000_0000` - `0x3000_0FFF` | UART | 4 KB | 32-bit MMIO 窗口 |

ITCM 和 DTCM 当前采用 32-bit word 数组、同步读、同步写，并支持 byte mask 写入。时序表现已与真实的 FPGA Block RAM (BRAM) 或 ASIC SRAM Macro 完全一致。

ITCM 除取指端口外，还提供数据侧读写端口。该路径用于兼容当前部分测试程序将 `.data/signature` 放在 ITCM 窗口内的链接布局，也为 FENCE.I、自修改代码类测试保留基础通路。

UART 已接入 `soc_top`，寄存器定义见 `readme_peripherals.md`。

## 验证与运行状态

当前工程在 `sim/` 下提供 VCS 仿真流程，支持 ISA 单测、Compliance 单测、用户程序和批量回归入口。DV 中包含面向 LSU、SoC bus 和 CSR 的基础 SVA 检查；`makefile` 可从 `sim.log` 中整理 SVA 输出到独立 `sva.log`。

CoreMark 当前记录显示，在 50 MHz 配置下：

| 指标 | 结果 |
| --- | ---: |
| CoreMark | 49.241315 |
| CoreMark/MHz | 0.984826 |
| 平均周期数 | 1015407.482 cycles/iteration |

详细配置、原始输出和上板记录见 `coremark_results.md`。

## 当前边界

当前版本定位为简洁的 RV32I + Zicsr SoC 内核，主要边界如下：

- 不包含 ICache/DCache、分支预测或复杂总线互连。
- 不包含外部中断控制器、Timer MMIO、GPIO 等外设。
- CSR 支持为基础子集，特权架构功能未完整覆盖。
- `minstret` 尚未接入真实退休事件。
- 软件内存布局与正式 ITCM/DTCM 分区仍有进一步收敛空间。

## 可考虑改进方向

- **CSR 精确提交**：当前 CSR 写在执行侧较早形成写请求，虽已通过提交条件屏蔽 flush/stall，但仍不是完整的 WB/Commit 级 CSR 提交模型。后续可参考 biRISC-V 风格，将 CSR 读与写数据计算保留在执行阶段，把 CSR 写意图、写地址、写数据随流水推进到 WB/Commit 统一提交，并令异常提交优先于普通 CSR 写。
- **CSR 序列化或旁路**：若采用 WB 级 CSR 提交，可先对 CSR 指令做短暂序列化，避免连续 CSR RAW 需要额外 forwarding；之后再考虑 CSR WB-to-EX 旁路提升吞吐。
- **指令退休事件**：将 `minstret` 接入真实提交点，使性能计数器语义更完整。
- **外设与中断**：补充 Timer、GPIO、中断控制器和机器模式中断入口，完善 SoC 级运行环境。
- **软件内存布局**：进一步统一测试程序、用户程序和 SoC 内存图，减少对 ITCM 数据侧兼容路径的依赖。

## 相关文档

- `readme_peripherals.md`：UART MMIO 寄存器说明。
- `coremark_results.md`：CoreMark 仿真与上板结果。
- `static_analysis_report.md`：静态检查、命名和接口风险记录。
