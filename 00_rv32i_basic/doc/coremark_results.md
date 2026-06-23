# CoreMark 结果记录与分析

本文同时记录当前 RV32I Core 的 CoreMark RTL 仿真与实际上板结果，并给出跑分
计算方法和简要有效性检查。
CoreMark 的使用配置见 `tests/programs/coremark/README_config.md`。

## 记录一：RV32I RTL 仿真

### 运行配置

| 项目 | 数值 |
| --- | --- |
| 运行类型 | `PERFORMANCE` |
| `TOTAL_DATA_SIZE` | 2000 bytes |
| `ITERATIONS` | 500 |
| `QUICK_RUN` | 0 |
| `PROGRESS_INTERVAL` | 0 |
| CPU 频率 | 50 MHz |
| 架构与 ABI | `rv32i / ilp32` |
| 编译器 | GCC 8.3.0 |
| 内存方式 | `STATIC` |

对应构建配置：

```bash
make clean all TOTAL_DATA_SIZE=2000 ITERATIONS=500 \
    RUN_TYPE=PERFORMANCE QUICK_RUN=0 PROGRESS_INTERVAL=0
```

`CPU_FREQ_HZ=50000000` 来自
`tests/programs/common/include/utils.h`。该值必须与 RTL 中实际提供给 CPU 的时钟
频率一致。

### 原始输出

```text
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 507703741
Total time (secs): 10
Iterations/Sec   : 50
Iterations       : 500
Compiler version : GCC8.3.0
Compiler flags   : -O2 -fno-common -funroll-loops -finline-functions --param max-inline-insns-auto=20 -falign-functions=4 -falign-jumps=4 -falign-loops=4
Memory location  : STATIC
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xa14c
Correct operation validated. See README.md for run and reporting rules.
```

### 跑分计算

实际运行时间：
```text
507703741 cycles / 50000000 Hz
= 10.15407482 s
```

CoreMark：
```text
Iterations * CPU_FREQ_HZ / Total ticks
= 500 * 50000000 / 507703741
= 49.241315 CoreMark
```

CoreMark/MHz：
```text
CoreMark / CPU frequency (MHz)
= 49.241315 / 50
= 0.984826 CoreMark/MHz
```

平均每次 iteration：
```text
507703741 / 500
= 1015407.482 cycles/iteration
```

本次结果汇总：

| 指标 | 结果 |
| --- | ---: |
| 实际计时时长 | 10.15407482 s |
| CoreMark | 49.241315 |
| CoreMark/MHz | 0.984826 |
| 平均周期数 | 1015407.482 cycles/iteration |

### 结果分析

- 标准 performance CRC 全部通过，实际计时时长约 10.154 秒。
- 打印的 `Total time (secs): 10` 和 `Iterations/Sec: 50` 都经过整数截断，精确
  结果必须使用 `Total ticks` 计算。
- 计算采用的 `CPU_FREQ_HZ=50000000` 来自
  `tests/programs/common/include/utils.h`，必须与实际 CPU 时钟一致。

## 记录二：RV32I 实际上板

### 原始输出

```text
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 507703741
Total time (secs): 10
Iterations/Sec   : 50
Iterations       : 500
Compiler version : GCC8.2.0
Compiler flags   : -O2 -fno-common -funroll-loops -finline-functions --param max-inline-insns-auto=20 -falign-functions=4 -falign-jumps=4 -falign-loops=4
Memory location  : STATIC
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xa14c
Correct operation validated. See README.md for run and reporting rules.
```

### 结果汇总

该上板记录的 `Total ticks`、迭代数和 CRC 与上述 RTL 仿真记录相同，因此在
50 MHz 时钟配置下计算结果也相同：

| 指标 | 结果 |
| --- | ---: |
| 实际计时时长 | 10.15407482 s |
| CoreMark | 49.241315 |
| CoreMark/MHz | 0.984826 |
| 平均周期数 | 1015407.482 cycles/iteration |

原始输出中的编译器版本为 GCC 8.2.0，与仿真记录中的 GCC 8.3.0 不同，应作为
两个运行环境的差异保留。上板结果同样存在整数秒和整数 `Iterations/Sec` 截断；
计算所用的 50 MHz 来自软件中的 `CPU_FREQ_HZ` 配置，并应与板上实际 CPU 时钟
核对一致。

## 简要结论

两份记录均通过标准 performance CRC 检查，并满足按 `Total ticks` 换算后至少
运行 10 秒的要求。打印字段的具体含义、配置要求和正式提交前检查项统一见
`tests/programs/coremark/README_config.md`。
