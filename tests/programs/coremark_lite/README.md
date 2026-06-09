# CoreMark Lite

`coremark_lite` 是 `tests/programs/coremark` 的资源受限快速验证版本，不用于官方 CoreMark 成绩。

## 目的

这个版本用于快速验证：

- 裸机启动流程可进入 `main`
- `.data` / `.bss` 初始化正常
- UART 打印正常
- `cycle/cycleh` 计时可读
- CoreMark 的 port 层可工作
- CoreMark list 数据结构初始化和基本遍历可工作

它刻意跳过了普通 CoreMark 中体积和运行时间较大的部分。

## 文件来源

以下文件从并列目录 `tests/programs/coremark` 复制而来：

```text
coremark.h
core_list_join.c
core_util.c
core_portme.c
core_portme.h
```

`core_main.c` 来自此前在 `coremark` 目录中临时新增的 `core_main_lite.c`，现在已独立放到本目录。

`Makefile` 参考：

```text
tests/programs/simple/Makefile
tests/programs/coremark/Makefile
```

## 与普通 CoreMark 的区别

普通版目录：

```text
tests/programs/coremark
```

Lite 版目录：

```text
tests/programs/coremark_lite
```

Lite 版只编译：

```text
core_main.c
core_list_join.c
core_util.c
core_portme.c
```

不编译：

```text
core_matrix.c
core_state.c
tests/programs/coremark/core_main.c
```

Lite 版的 `main` 只做：

1. `portable_init()` 初始化 UART。
2. 打印启动信息。
3. 调用 `core_list_init()` 初始化 CoreMark 链表数据。
4. 遍历链表并计算一个简单 CRC。
5. 打印节点数、CRC、cycle ticks。

它不会运行官方完整 benchmark 调度、三算法组合、known CRC 规则和长报告。

## 构建

在本目录执行：

```sh
make
```

生成：

```text
coremark_lite
coremark_lite.bin
coremark_lite.dump
```

生成 testbench 可用的 `.data`：

```sh
python ../../../tools/scripts/BinToMem_CLI.py coremark_lite.bin coremark_lite.data
```

## 预期输出

当前默认配置：

```makefile
CFLAGS += -DTOTAL_DATA_SIZE=128
```

在板卡上直接运行，预期 UART 输出类似：

```text
CoreMark Lite Start
Data size         : 128
List nodes        : 3
List crc          : 0x5e84
Total ticks       : 0
CoreMark Lite Done
```

其中：

- `Data size : 128` 来自 `TOTAL_DATA_SIZE=128`。
- `List nodes : 3` 是当前 lite 程序和该数据规模下的预期链表节点数。
- `List crc : 0x5e84` 是当前 lite 程序遍历链表得到的本地观察 CRC，不对应官方 CoreMark known CRC。
- `Total ticks : 0` 表示当前上板环境中计时读数没有体现出这段代码的运行耗时。常见原因是 `cycle/cycleh` 未实现、未计数、读取路径还未接通，或者该段运行太短导致当前计时观测不到差值。它不影响 UART、启动流程和链表初始化是否跑通的判断。

如果修改 `TOTAL_DATA_SIZE`、`core_main.c` 的遍历逻辑、优化参数或 CoreMark 源文件，`List nodes` 和 `List crc` 都可能变化。

## 串口换行

如果串口助手中看到输出连在一行，例如：

```text
CoreMark Lite StartData size         : 128List nodes ...
```

这是因为公共打印库当前只发送 `\n`，而很多串口助手需要 `\r\n` 才会换行。相关配置在：

```text
tests/programs/common/include/xprintf.h
```

当前为：

```c
#define _CR_CRLF 0
```

如果希望所有 `xprintf("\n")` 自动转换为 CRLF，可以改为：

```c
#define _CR_CRLF 1
```

也可以只在局部打印语句中手动使用 `\r\n`，这样不会影响其他程序。

## 切换使用

普通版使用：

```text
tests/programs/coremark/coremark.data
```

Lite 版使用：

```text
tests/programs/coremark_lite/coremark_lite.data
```

在 `mem_itcm.sv` 或 testbench 的 `$readmemh` 路径中切换即可。

## 注意

- Lite 版打印的 CRC 只用于本地快速观察，不对应官方 CoreMark known CRC。
- 如果需要恢复完整 CoreMark 行为，请使用 `tests/programs/coremark`。
- 如果板卡 ITCM 资源有限，优先使用本目录版本。
