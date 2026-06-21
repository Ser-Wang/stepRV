# biRISC-V 存储器结构与地址分配简析

作者：GPT-5.5 Medium | Codex  
时间戳：2026-06-20 20:31:00 +08:00  
版本：v1.1

## 总体

biRISC-V 对外是 Harvard 风格接口：取指通路和数据通路分开。

项目提供两种主要顶层：

- `riscv_tcm_top`：CPU + TCM 紧耦合存储器。
- `riscv_top`：CPU + I-cache / D-cache + AXI 总线。

README 中提到：支持 64-bit instruction fetch、32-bit data access，并支持 cache、AXI 或 TCM。

## 地址分配

### TCM 版本

默认参数：

```verilog
BOOT_VECTOR  = 32'h00000000
TCM_MEM_BASE = 32'h00000000
```

因此默认 TCM 地址空间是：

```text
0x0000_0000 ~ 0x0000_FFFF   64KB TCM
```

这片 TCM 同时存放指令和数据，没有硬件强制划分“指令区”和“数据区”。

- 指令访问：取指 PC 直接进入 TCM 读端口，使用 `mem_i_pc_i[15:3]` 作为 64-bit RAM 索引。
- 数据访问：若地址满足 `TCM_MEM_BASE <= addr < TCM_MEM_BASE + 64KB`，走 TCM。
- 外设/外部访问：若数据地址不在 TCM 范围内，走外部 AXI-Lite master 接口 `axi_i_*`。

注意：TCM 版本的取指端没有额外判断 `TCM_MEM_BASE`，主要使用 PC 的低位索引 TCM。因此默认最自然的布局是程序从 `0x0000_0000` 启动，指令和数据都链接到这 64KB TCM 空间内。

### Cache 版本

`riscv_top` 没有内置固定 IMEM/DMEM 地址段，而是提供两条 AXI master：

- `axi_i_*`：指令访问，由 I-cache 发出。
- `axi_d_*`：数据和外设访问，由 D-cache/uncached 通路发出。

外部 SoC/interconnect 决定哪些地址对应 ROM、RAM、外设等。

D-cache 是否缓存由参数决定，默认：

```text
0x8000_0000 ~ 0x8FFF_FFFF   cacheable data memory
其他地址                      uncached data/peripheral access
```

指令侧通过 I-cache 访问 `axi_i_*`，没有在顶层 RTL 中固定限定某个 IMEM 地址段。

## TCM 存储器结构

`src/tcm/tcm_mem.v` 内部使用一个共享的双端口 RAM：

- Port 0：取指端口，只读，输出 64-bit 指令数据。地址来自 `mem_i_pc_i[15:3]`，本质上也是访问同一整片 TCM，只是该端口专供 IFetch 使用。
- Port 1：数据/外部访问端口，读写 32-bit 数据，通过地址 bit2 选择 64-bit RAM 的低/高 32-bit。CPU D-side 的 load/store 只要命中 TCM 地址窗口，就可以通过该端口访问整片 TCM 中的内容，包括存放指令的地址；外部 AXI TCM slave 访问也复用该端口。
- RAM 宽度为 64-bit，带 byte write enable。
- 指令和数据逻辑上分开，物理上共享同一个 TCM RAM。

底层 RAM 在 `src/tcm/tcm_mem_ram.v`：

- 注释标明 `Dual Port RAM 64KB`。
- 注释标明 `Mode: Read First`。
- 读数据经过寄存器输出。

简化时序：

```text
第 I 个时钟沿前：addr 稳定
第 I 个时钟沿：RAM 采样 addr，并把 ram[addr] 打入读数据寄存器
第 I 个时钟沿后：data_o 输出该地址的数据
```

所以物理 RAM 层面是典型同步 SRAM / FPGA BRAM 风格的一拍读时序。

## Cache 存储器结构

`riscv_top` 不直接接裸 IMEM/DMEM，而是：

- I-cache：16KB，2-way set associative。
- D-cache：16KB，2-way set associative，write-back，read/write allocate。
- I-cache 和 D-cache 后面分别接 AXI master port。

cache 内部的 data/tag array 也使用同步 RAM 风格：

- I-cache data RAM：单端口，64-bit，read-first。
- I-cache tag RAM：单端口，read-first。
- D-cache data RAM：双端口，32-bit，byte write enable，read-first。
- D-cache tag RAM：tag/valid/dirty 存储，write-first。

抛开 hit/miss/refill/writeback 控制逻辑，只看物理存储阵列，cache 版本同样是同步 SRAM 风格。

## 流片实现理解

FPGA 上这些 RAM 代码通常可推断成 BRAM。

ASIC 流片时，大容量 RAM 通常不会直接用普通逻辑综合成触发器阵列，而是需要替换成工艺库 SRAM macro：

- TCM RAM 应替换为对应的双端口 SRAM macro。
- I-cache / D-cache 的 data array 通常替换为 SRAM macro。
- tag RAM 容量较小，可根据工艺和面积时序选择 SRAM macro、寄存器阵列或 latch array。

替换 SRAM macro 时要保持 RTL 期望的行为一致，尤其是：

- 读延迟：同步一拍读。
- byte write enable。
- 端口数量。
- read-first / write-first 行为。
- 同地址读写冲突语义。
