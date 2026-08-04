# CoreMark 结果记录

本文档记录 RV32IM Core 的 CoreMark RTL 仿真结果，并给出基于 `Total ticks`
的跑分计算。

## RTL 仿真结果

### 运行配置

| 项目 | 数值 |
| --- | --- |
| 运行类型 | `PERFORMANCE` |
| `TOTAL_DATA_SIZE` | 2000 bytes |
| `ITERATIONS` | 1300 |
| `QUICK_RUN` | 0 |
| `PROGRESS_INTERVAL` | 0 |
| CPU 频率 | 50 MHz |
| 架构与 ABI | `rv32im / ilp32` |
| 编译器 | GCC 8.3.0 |
| 内存方式 | `STATIC` |

对应构建配置：

```bash
make clean all TOTAL_DATA_SIZE=2000 ITERATIONS=1300 \
    RUN_TYPE=PERFORMANCE QUICK_RUN=0 PROGRESS_INTERVAL=0
```

`CPU_FREQ_HZ=50000000` 来自
`tests/programs/common/include/utils.h`，应与 RTL 中实际提供给 CPU 的时钟一致。

### 原始输出

```text
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 512780046
Total time (secs): 10
Iterations/Sec   : 130
Iterations       : 1300
Compiler version : GCC8.3.0
Compiler flags   : -O2 -fno-common -funroll-loops -finline-functions --param max-inline-insns-auto=20 -falign-functions=4 -falign-jumps=4 -falign-loops=4
Memory location  : STATIC
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0x382f
Correct operation validated. See README.md for run and reporting rules.
```

## 跑分计算

实际运行时间：

```text
512780046 cycles / 50000000 Hz
= 10.25560092 s
```

CoreMark：

```text
Iterations / (Total ticks / CPU_FREQ_HZ)
= 1300 / (512780046 * 50000000)
= 126.760003 CoreMark
```

CoreMark/MHz：

```text
CoreMark / CPU frequency (MHz)
= 126.760003 / 50
= 2.535200 CoreMark/MHz
```

平均每次 iteration：

```text
512780046 / 1300
= 394446.189 cycles/iteration
```

结果汇总：

| 指标 | 结果 |
| --- | ---: |
| 实际计时时长 | 10.25560092 s |
| CoreMark | 126.760003 |
| CoreMark/MHz | 2.535200 |
| 平均周期数 | 394446.189 cycles/iteration |


- `Total time (secs)` 和 `Iterations/Sec` 为程序打印的整数结果；正式计算以
  `Total ticks`、`ITERATIONS` 和 `CPU_FREQ_HZ` 为准。
