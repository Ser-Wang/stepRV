# CoreMark 适配说明

本目录用于将 EEMBC 官方 CoreMark 适配到当前自研 RV32I SoC/RTL 环境。当前适配以 UART 打印作为主要观察方式，适用于仿真和上板快速验证。

## 文件来源

### 官方 CoreMark 源码

以下文件来自克隆的官方仓库：

```text
tests/programs/coremark/src_official/coremark/
```

复制到当前目录后作为本地构建的核心 benchmark 源码：

```text
coremark.h
core_main.c
core_list_join.c
core_matrix.c
core_state.c
core_util.c
```

这些文件尽量保持和官方版本一致。当前只对 `core_main.c` 做了少量快速验证相关改动，见后文。

### 官方 barebones port 层

以下文件以官方仓库的 barebones port 为来源：

```text
tests/programs/coremark/src_official/coremark/barebones/core_portme.c
tests/programs/coremark/src_official/coremark/barebones/core_portme.h
```

复制为：

```text
core_portme.c
core_portme.h
```

然后按本项目裸机环境修改。没有直接复制 `coremark_tinyrv` 的 `core_portme.c/.h`，目的是让 CoreMark 相关代码尽量和当前官方仓库版本一致。

### 本地工程构建文件

`Makefile` 参考已经在本核上跑通的：

```text
tests/programs/simple/Makefile
```

同时参考 `coremark_tinyrv/Makefile` 中 CoreMark 所需的源文件列表和优化参数。

## 本地适配改动

### Makefile

新增 `tests/programs/coremark/Makefile`：

- `RISCV_ARCH := rv32i`，匹配当前 RV32I 核，避免生成 M 扩展指令。
- `COMMON_DIR = ../common`，复用本项目公共启动和驱动代码。
- `include ../common/common.mk`，保持和 `simple`、`uart_tx` 相同的构建体系。
- `C_SRCS` 包含官方 CoreMark 5 个核心 `.c` 文件和本地适配后的 `core_portme.c`。
- 默认 `-DITERATIONS=1 -DPERFORMANCE_RUN=1`，用于 RTL 或上板快速功能验证。
- 默认 `-DCOREMARK_QUICK_RUN`，用于跳过 CoreMark 官方“必须运行至少 10 秒”的成绩规则。
- 保持 CoreMark 参考优化参数 `-O2 -fno-common -funroll-loops -finline-functions ...`。

当前没有定义 `SIMULATION`，因此公共启动代码不会使用 x26/x27 作为仿真结束或结果判定标志。

### core_portme.h

基于官方 barebones `core_portme.h` 修改：

- `HAS_FLOAT` 改为 `0`，避免软浮点和 `%f` 输出。
- `HAS_TIME_H`、`USE_CLOCK`、`HAS_STDIO`、`HAS_PRINTF` 设为 `0`，不依赖 hosted C 环境。
- `ee_printf` 映射到公共库中的 `xprintf`。
- `CORE_TICKS` 使用 `uint64_t`。
- `MEM_METHOD` 使用 `MEM_STATIC`，避免 malloc。
- `MAIN_HAS_NOARGC` 设为 `1`，匹配 `common/start.S` 直接 `call main` 的裸机入口。
- `MULTITHREAD` 固定为 `1`。

### core_portme.c

基于官方 barebones `core_portme.c` 修改：

- 删除官方预留的 `#error`。
- 使用 `get_cycle_value()` 读取 `cycle/cycleh` 作为 CoreMark 计时源。
- `time_in_secs()` 使用 `CPU_FREQ_HZ` 做 cycle 到秒的换算。
- `portable_init()` 中调用 `uart_init()`，让 `ee_printf/xprintf` 通过 UART 输出。
- 保留官方 CoreMark 需要的 volatile seed 变量：

```c
seed1_volatile
seed2_volatile
seed3_volatile
seed4_volatile
seed5_volatile
```

### core_main.c

官方 `core_main.c` 只做了快速验证相关的少量改动：

- 当定义 `COREMARK_QUICK_RUN` 时，跳过 CoreMark 官方“必须运行至少 10 秒”的成绩规则。
- 不再调用 `set_test_pass()` / `set_test_fail()`。
- 程序结果完全通过 UART 打印观察，例如 `Correct operation validated...`、`Errors detected` 或 `Cannot validate operation...`。

CRC 校验逻辑仍由官方 CoreMark 保持。

## 公共配置改动

官方 CoreMark 体积大于原 16KB ITCM，因此同步扩大了软件链接脚本和 RTL ITCM 配置：

```text
tests/programs/common/link.lds
```

```ld
flash (wxa!ri) : ORIGIN = 0x00000000, LENGTH = 32K
```

```text
00_rv32i_basic/de/defines/config.v
```

```verilog
`define ITCM_SIZE 32'h0000_8000
```

DTCM/RAM 仍保持 16KB：

```ld
ram (wxa!ri) : ORIGIN = 0x10000000, LENGTH = 16K
```

## 构建方法

在本目录执行：

```sh
make
```

会生成：

```text
coremark
coremark.bin
coremark.dump
```

若需要 testbench `$readmemh` 使用的 `.data` 文件，执行：

```sh
python ../../../tools/scripts/BinToMem_CLI.py coremark.bin coremark.data
```

## 仿真或上板使用

将程序初始化路径切换为：

```text
tests/programs/coremark/coremark.data
```

例如 `mem_itcm.sv` 或 testbench 中的 `$readmemh` 路径需要从其他测试程序的 `.data` 改为 `coremark.data`。

当前结果判断方式是直接观察 UART 打印。常见输出包括：

```text
CoreMark Size
Total ticks
Iterations
Compiler version
Compiler flags
Memory location
seedcrc
crclist / crcmatrix / crcstate
crcfinal
Correct operation validated...
Errors detected
Cannot validate operation...
```

如果使用较小的 `TOTAL_DATA_SIZE` 或只运行部分算法，CRC 可能无法匹配官方 known CRC。这通常不会阻止打印，只会在打印中提示无法验证或检测到错误。

## 可选：增加 x26/x27 仿真判定

当前适配不依赖 x26/x27。如果以后希望 testbench 自动判断程序结束和通过/失败，可以按以下方式增加：

1. 在 `Makefile` 中定义：

```makefile
CFLAGS += -DSIMULATION
```

2. 在 `core_main.c` 中包含公共工具头：

```c
#include "utils.h"
```

3. 在 `total_errors == 0` 的分支中调用：

```c
set_test_pass();
```

4. 在 `total_errors > 0` 或 `total_errors < 0` 的分支中调用：

```c
set_test_fail();
```

公共启动文件 `common/start.S` 在 `SIMULATION` 下会配合使用 x26/x27。具体约定由 `common/start.S` 和 `common/include/utils.h` 决定。

## 注意事项

- 当前配置主要用于快速功能验证，不用于提交正式 CoreMark 成绩。
- 若要得到正式 CoreMark 成绩，应增加 `ITERATIONS`，取消 `COREMARK_QUICK_RUN`，并确保计时频率、运行环境和报告格式满足 CoreMark 官方要求。
- 如果未来启用 RV32IM，可以将 `RISCV_ARCH` 改为 `rv32im`，但必须确认 RTL 已实现 M 扩展指令。
