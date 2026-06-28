# Memory 实现配置

本文档记录 `mem_itcm` 和 `mem_dtcm` 在不同实现方式下的关键配置，便于复现当前 SRAM/BRAM wrapper 行为。

## 宏选择

`mem_itcm` 和 `mem_dtcm` 是 SoC 侧稳定 wrapper。具体实现由 `de/defines/config.v` 中的宏选择：

- 不定义宏：使用通用可综合 RTL memory model
- `USE_BRAM`：例化 Vivado Block Memory Generator IP
- `USE_SRAM_MACRO`：例化 ASIC SRAM macro wrapper

如果 `USE_SRAM_MACRO` 和 `USE_BRAM` 同时定义，wrapper 优先选择 `USE_SRAM_MACRO`。这样可以降低 DC 综合时忘记关闭 `USE_BRAM`、误例化 Vivado IP 的风险。

## 共同约定

- 时钟：读写均在 `clk` 上升沿采样。
- 读延迟：固定 1 cycle。
- 写粒度：32-bit word，带 4-bit byte write mask。
- byte mask 映射：bit 0 写 `[7:0]`，bit 3 写 `[31:24]`。
- reset：memory 内容不由 reset 清零；reset 只约束 wrapper 输出。
- 同端口同地址读写：按 READ_FIRST 约定，读返回写入前的旧值。
- ITCM 跨端口同地址读写不作为架构保证。Port 0 读某地址、Port 1 同拍写同一地址时，RTL 和软件都不能依赖 Port 0 读到旧值还是新值。

## Vivado BRAM IP

使用 Block Memory Generator，Native port，读延迟固定为 1 cycle。

### ITCM IP

wrapper 实例名：`imem_bram_singleport`

- Memory type：true dual port RAM
- Common clock：yes
- Width/depth：`8192 x 32`
- Port A：IFU read-only
- Port B：LSU/preload read/write
- Byte write enable：两个端口都打开，4 bits
- Port A write enable 接法：`4'b0000`
- Port B write enable 接法：`i_p1_we ? i_p1_wmask : 4'b0000`
- Write mode A/B：READ_FIRST
- Output register：Port A/B 的 Primitive Output Register 和 Core Output Register 均关闭。当前 SoC 依赖 1 cycle 同步读返回；打开输出寄存器会多引入一级读数据延迟，导致取指或 LSU load 数据与流水线错位。
- ECC：disabled

### DTCM IP

wrapper 实例名：`dmem_bram_truedualport`

- Memory type：single port RAM
- Width/depth：`4096 x 32`
- Byte write enable：打开，4 bits
- Write enable 接法：`i_wr_en ? i_wr_mask : 4'b0000`
- Write mode：READ_FIRST
- Output register：Port A 的 Primitive Output Register 和 Core Output Register 均关闭。当前 SoC 依赖 1 cycle 同步读返回。
- ECC：disabled

## 初始化文件

RTL 仿真使用 `.data` 文件，一行一个 32-bit hex word。Vivado BRAM IP 初始化使用 `.coe` 文件：

```text
memory_initialization_radix=16;
memory_initialization_vector=
10001197,
87018193,
00000013;
```

在程序目录下执行：

```sh
make coe
```

该命令调用 `tools/scripts/BinToCoe_CLI.py`，从 `$(TARGET).bin` 生成 `$(TARGET).coe`。该脚本也可以直接把已有 `.data` 文件转换为 `.coe`。
