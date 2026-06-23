# CoreMark 使用与配置说明

本文面向 CoreMark 的编译、仿真和结果检查，说明使用过程中需要选择的配置项及其
影响。移植时做出的源码、构建和 RTL 修改见 `README_porting.md`；官方规则原文
见只读副本 `README_official.md`。

## TOTAL_DATA_SIZE 是否可以修改

`TOTAL_DATA_SIZE` 技术上可以修改，但不同用途有不同约束：

- 标准 `PERFORMANCE` 和 `VALIDATION` 运行使用 `2000`，以匹配官方 2K 种子和已知 CRC。
- `PROFILE` 运行必须配套使用 `1200`（需手动配置），仅用于生成 PGO profile，不用于报告 CoreMark 分数。
- 其他大小可用于调试或实验，但通常不能与官方标准结果直接比较，也可能没有已知 CRC。
- 数值过小可能导致算法数据结构无法建立，而不只是 CRC 不匹配。

选择 `RUN_TYPE=PROFILE` 时，当前 Makefile 只定义 `PROFILE_RUN=1` 来选择
`8, 8, 8` 种子，不会自动覆盖 `TOTAL_DATA_SIZE`。因此需要显式使用：

```bash
make clean all RUN_TYPE=PROFILE TOTAL_DATA_SIZE=1200
```

`core_portme.h` 中确实存在“未显式定义任何 RUN_TYPE 宏时，根据
`TOTAL_DATA_SIZE` 推断运行类型”的兼容逻辑，但当前 Makefile 总会显式定义一种
运行类型，因此该逻辑不会替代上述配置。

此前使用的 `128` 会先被三个算法平均分配，每个算法只得到 42 字节。链表使用
`size = (blksize / 20) - 2` 计算可用元素数；42 字节会得到 0，无法创建必要的
头尾节点，后续访问空指针。

按照当前 32 位、三个算法全部启用的实现推算，总数据区至少约为 `300` 字节，
才能让每个算法获得 100 字节并越过链表初始化的直接失败条件。但这只是避免
当前崩溃的源码级下限，不代表算法结果有效、CRC 已知或运行稳定，不应作为推荐
配置。功能验证仍使用 `2000`，PROFILE 使用 `1200`。

该参数也会影响运行速度：数据区越大，链表元素和矩阵规模通常越大，每次
iteration 的工作量随之增加，因此总周期会上升；变化并非严格线性。它不能作为
正式运行时任意缩短耗时的手段，因为标准结果要求固定的数据区大小。

## Makefile 配置项

### TOTAL_DATA_SIZE

所有算法共享的数据区总大小，单位为字节。

```makefile
TOTAL_DATA_SIZE ?= 2000
```

正式 performance/validation 保持为 `2000`。

### ITERATIONS

CoreMark timed section 的循环次数。它直接影响总运行周期和运行时间，但不会改变所选种子。

- `1`：适合 RTL 快速功能和 CRC 检查，不是正式成绩。
- `457`：根据当前约 `1,015,420 cycles/iteration`、50 MHz 的测量结果估算，
  约可达到 9.28 秒，仍未满足 10 秒要求。
- `500`：同一估算下约为 10.15 秒，留有少量余量，适合正式 performance
  运行；最终仍以实际打印的 `Total ticks` 为准。
- validation 没有固定迭代数；快速 CRC 检查可使用 `1`，正式合规运行仍应满足官方运行规则。

### RUN_TYPE

选择输入种子和运行用途：

- `PERFORMANCE`：种子 `0, 0, 0x66`，用于产生性能分数。
- `VALIDATION`：种子 `0x3415, 0x3415, 0x66`，用于独立验证官方 CRC。
- `PROFILE`：种子 `8, 8, 8`，用于 PGO profile，并且必须手动配置
  `TOTAL_DATA_SIZE=1200`；当前编译参数未启用 PGO。

PGO（Profile-Guided Optimization，基于运行剖面的优化）通常分两次编译：
第一次生成带采样/计数功能的程序，用 PROFILE 数据集运行并收集热点信息；第二次
让编译器利用这些信息重新优化分支布局、内联等。只有编译器参数真正启用了
profile generate/use 流程时，`RUN_TYPE=PROFILE` 才是在生成 PGO 所需数据；
仅切换该 RUN_TYPE 本身不会自动启用 PGO。

### QUICK_RUN

控制本地增加的 10 秒检查旁路：

- `1`：定义 `COREMARK_QUICK_RUN`，跳过至少运行 10 秒的检查，仅用于调试。
- `0`：启用运行时长检查，用于正式 performance 配置。

### PROGRESS_INTERVAL

控制 benchmark iteration 的 UART 进度打印，默认值为 `0`，表示关闭。例如设置为
`10` 后，每完成 10 次循环打印一次，并在最后一次循环完成时打印：

```text
[CoreMark Progress] Iteration 10 / 100 completed
```

`ITERATIONS` 从 Makefile 通过 `-DITERATIONS` 传入 `core_portme.c` 的
`seed4_volatile`，再由 `core_main.c` 读入 `results[0].iterations`。实际循环位于
`core_main.c` 的 `iterate()`：

```c
for (i = 0; i < iterations; i++)
{
    core_bench_list(res, 1);
    core_bench_list(res, -1);
}
```

进度输出位于 CoreMark 的计时区间内。UART 发送和格式化会增加大量周期，因此启用
后得到的 `Total ticks`、Iterations/Sec 和 CoreMark 分数均无效，只适合确认长时间
RTL 仿真仍在前进。正式跑分必须使用 `PROGRESS_INTERVAL=0`。

## 常用命令

快速 performance 功能检查：
```bash
make clean all TOTAL_DATA_SIZE=2000 ITERATIONS=1 RUN_TYPE=PERFORMANCE QUICK_RUN=1
```
带 iteration 进度的调试运行：
```bash
make clean all TOTAL_DATA_SIZE=2000 ITERATIONS=100 RUN_TYPE=PERFORMANCE \
    QUICK_RUN=1 PROGRESS_INTERVAL=10
```
快速 validation CRC 检查：
```bash
make clean all TOTAL_DATA_SIZE=2000 ITERATIONS=1 RUN_TYPE=VALIDATION QUICK_RUN=1
```
PGO profile 数据集（还需要另行加入编译器的 profile-generate 参数）：
```bash
make clean all TOTAL_DATA_SIZE=1200 RUN_TYPE=PROFILE QUICK_RUN=1
```

正式 performance 运行：

```bash
make clean all TOTAL_DATA_SIZE=2000 ITERATIONS=500 RUN_TYPE=PERFORMANCE QUICK_RUN=0
```

生成仿真初始化文件：

```bash
python3 ../../../tools/scripts/BinToMem_CLI.py coremark.bin coremark.data
```

## 适配设置对使用的影响

以下平台适配会直接影响运行或结果解释；具体修改过程见 `README_porting.md`：

- `CPU_FREQ_HZ` 在 `common/include/utils.h` 中手工配置，必须与实际 CPU 时钟一致。
- `core_portme.c` 使用 `cycle/cycleh` 计时，因此 RTL 必须正确实现对应 CSR。
- `HAS_FLOAT=0` 且本地 `xprintf` 不支持 `%f`，UART 不会打印浮点成绩行。
- 程序采用静态数据区，且链接脚本与 RTL ITCM 当前按 32 KB 配套配置。
- 当前架构参数为 `rv32i`；更改它前必须确认 RTL 支持相应指令扩展。

## 为仿真与跑通流程所做的修改

为了让 CoreMark 能在当前裸机 RV32I RTL 仿真环境中编译、运行、计时并输出结果，
工程中做了以下修改。详细实现和文件来源见 `README_porting.md`。

### 软件与构建

- `Makefile` 增加 `TOTAL_DATA_SIZE`、`ITERATIONS`、`RUN_TYPE`、
  `QUICK_RUN` 和 `PROGRESS_INTERVAL`，便于切换快速验证与正式运行配置。
- `core_portme.c/.h` 改为裸机静态内存、UART 输出、单核运行，并使用
  `cycle/cycleh` 作为计时源，不依赖标准 C 时间库、stdio 或 malloc。
- `utils.c` 将原来的 `cycle`、`cycleh` 各读取一次改为
  `cycleh-cycle-cycleh` 重读，避免低 32 位翻转时得到不一致的 64 位周期数；
  原实现仍以注释形式保留。
- `HAS_FLOAT=0`，用于避免当前环境的软浮点和 `%f` 输出依赖。因此程序打印整数秒，
  小于 1 秒时显示为 0，精确成绩需要根据 `Total ticks` 在外部计算。

### CoreMark 核心源码中的调试改动

- `COREMARK_QUICK_RUN` 可旁路官方至少运行 10 秒的检查，用于短时间 RTL 仿真。
- `COREMARK_PROGRESS_INTERVAL` 可在 benchmark 循环内部通过 UART 打印 iteration
  进度，用于确认长仿真仍在执行。
- 上述改动在 `core_main.c` 中以 `// changed begin` 和
  `// changed end` 标记，方便正式提交前恢复。

iteration 进度打印位于计时区间内，会改变周期数；`QUICK_RUN=1` 也不满足官方
运行规则。因此正式跑分必须使用：

```makefile
QUICK_RUN=0
PROGRESS_INTERVAL=0
```

正式提交前还应删除 `core_main.c` 中标记的进度打印块，并去掉 10 秒检查外层的
条件编译包装，恢复官方核心源码。

### RTL 与 testbench

- `csr_regs.sv` 增加只读 `cycle/cycleh` CSR，作为 `mcycle/mcycleh` 的影子视图，
  使 CoreMark 能在非机器态 CSR 地址上读取周期计数。
- `sva_csr.sv` 增加对应 CSR 合法性和只读写保护检查。
- 软件链接空间和 RTL ITCM 配套扩大至 32 KB，以容纳完整 CoreMark 程序；
  DTCM 仍为 16 KB。
- `tb_soctop_userprog.sv` 从 `INST_DATA_PATH` 加载程序，通过 UART monitor 解码
  CoreMark 输出，并增加每 20 ms 仿真时间一次的进度提示。
- testbench watchdog 被延长，以允许多 iteration 的 CoreMark 仿真完成；长时间
  正式运行仍更适合 FPGA 或其他实际硬件。
- `sva_exu_lsu.sv` 的错误信息增加 EXU 级 PC，便于根据反汇编定位访存异常。

这些 RTL 和 port 层修改属于当前处理器平台适配，不需要为了正常跑分全部撤销；
但必须保证计时频率、存储配置和编译参数与最终报告一致。需要恢复的是
`core_main.c` 中偏离官方核心源码的调试代码。

官方带小数的成绩行位于 `core_main.c` 的结果报告部分：

```c
#if HAS_FLOAT
ee_printf("CoreMark 1.0 : %f / %s %s", ...);
#endif
```

它只有在 `HAS_FLOAT=1`、识别为标准 2K performance 数据集且所有校验通过时
才会打印。当前 `core_portme.h` 配置为 `HAS_FLOAT=0`，本地 `xprintf` 也不支持
`%f`，所以 UART 不会打印这条官方带小数的 `CoreMark 1.0` 行。

当前程序会打印 `Total ticks` 和 `Iterations`，但下面的带小数公式尚未加入程序
自动计算，需要根据 UART 输出手动计算，或由外部脚本计算：

```text
CoreMark = ITERATIONS * CPU_FREQ_HZ / Total ticks
CoreMark/MHz = CoreMark / CPU frequency (MHz)
```

单核配置下公式中的 `ITERATIONS` 就是打印的迭代次数；若以后启用多 context，
应使用程序打印的总迭代次数。计算时 `CPU_FREQ_HZ` 必须等于实际处理器时钟频率。
例如当前频率为 50 MHz，得到 CoreMark 后直接除以 50 即可。等价公式中出现的
`1,000,000` 仅用于将 Hz 换算为 MHz，不是 CoreMark 的额外参数。

## 打印字段含义

| 字段 | 含义 |
| --- | --- |
| `2K performance/validation run parameters` | 当前种子与数据区被识别为标准 performance 或 validation 配置 |
| `CoreMark Size` | 总数据区平均分给当前启用算法后，每个算法得到的字节数 |
| `Total ticks` | CoreMark 计时区间消耗的 cycle 数，是计算精确时间和成绩的依据 |
| `Total time (secs)` | `Total ticks / CPU_FREQ_HZ`；当前为整数计算，小数部分会被截断 |
| `Iterations/Sec` | 当前为整数秒基础上的整数结果，也会截断，不应用作精确成绩 |
| `Iterations` | 所有运行 context 合计完成的 benchmark iteration 数 |
| `Compiler version/flags` | 本次程序使用的编译器版本和优化参数 |
| `Memory location` | benchmark 数据区的分配方式；当前为静态内存 |
| `seedcrc` | 用于识别种子和单算法数据区大小组合 |
| `crclist/crcmatrix/crcstate` | 三个算法首次运行结果的 CRC，用于与官方已知值校验 |
| `crcfinal` | 所有 iteration 累积后的最终 CRC，会受迭代次数影响 |
| `Correct operation validated` | 当前种子可识别且各算法 CRC 校验通过 |
| `Errors detected` | 时间规则、数据类型或 CRC 检查至少有一项失败 |
| `Cannot validate operation` | 当前种子或数据区组合没有匹配到内置已知 CRC |

`CPU_FREQ_HZ` 并非 CoreMark 自动检测，而是在
`tests/programs/common/include/utils.h` 中手动定义。程序输出中的
`See README.md` 是官方 `core_main.c` 固定文案；本工程的使用说明见
`README_config.md`，官方规则见只读的 `README_official.md`。

## 正式结果检查

- 将核心 benchmark 文件与相同版本的官方源码逐文件比较。
- performance 与 validation 两组官方 CRC 都必须通过。
- performance timed section 必须至少运行 10 秒。
- 所有核心源码使用相同编译选项。
- 报告实际编译器版本、编译参数、代码/数据存储位置和时钟条件。
- 若需要提交官方格式日志，应提供可靠的小数输出或在外部生成符合规则的报告。

核心源码中当前需要恢复的本地修改记录在 `README_porting.md`。正式运行不得使用
`QUICK_RUN=1` 或非零的 `PROGRESS_INTERVAL`。正式提交前还应移除
`core_main.c` 中由 `COREMARK_PROGRESS_INTERVAL` 控制的调试打印代码，以通过
官方核心源码一致性检查。
