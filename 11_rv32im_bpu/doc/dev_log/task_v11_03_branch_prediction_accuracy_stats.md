# task_v11_03：CoreMark 分支预测准确率统计工单

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-20 00:26
**Current Version**: v1.4
**Status**: Implementation Complete; Runtime Verification Pending User Run (2026-08-20 01:50) | Ready for Execution (2026-08-20 00:26)

**Version Changelog**:
- **v1.4** (2026-08-20 01:50): 完成 TB/Makefile 实现及 VCS compile/elaboration 检查；针对预编译 10-iteration 镜像保留的官方时长检查增加 `PASS_BRINGUP` 判定，按用户要求未实际运行 CoreMark。
- **v1.3** (2026-08-20 01:41): 要求 `make sim_userprog name=coremark_10` 自动启用已核验默认窗口、进度和完成检测；plusarg 改为可选覆盖，其他 user program 保持静默。
- **v1.2** (2026-08-20 01:40): 明确统计在 `stop_time` 入口立即打印，并增加 armed/start/heartbeat/benchmark-done/UART validation 两阶段完成检测及分阶段超时，避免 bring-up 故障只能等待全局 watchdog。
- **v1.1** (2026-08-20 01:35): 将验证 workload 固定为已编译的 `coremark_10`，记录其与现有 CoreMark 镜像/dump 的一致性、已核验统计窗口地址及直接运行命令，不再要求重新编译 benchmark。
- **v1.0** (2026-08-20 00:26): 初版工单，明确 CoreMark 统计窗口、EX 提交口径、分类指标、输出格式、A/B 配置与验收标准。

---

相关文档：

- [`task_v11_01_dynamic_branch_prediction.md`](task_v11_01_dynamic_branch_prediction.md)：BTB+BHT 实现及 next-PC 正确性定义。
- [`task_v11_02_return_address_stack.md`](task_v11_02_return_address_stack.md)：RAS 实现、return 分类及已有 return-only monitor。
- [`dev_spec_dynamic_branch_predictor.md`](dev_spec_dynamic_branch_predictor.md)：预测 payload、EX resolve 和 recovery 语义。
- [`rule_ai_acceptance.md`](rule_ai_acceptance.md)：发生 RTL 行为修改时必须执行的公共验收要求。

## 1. 任务目标与边界

在 `dv/tb_soctop_userprog.sv` 使用已编译的 `tests/programs/coremark_10/coremark_10.data` 作为 SoC 仿真 workload，增加只读分支预测统计。在不改变 RTL、架构状态和 CoreMark 执行结果的前提下，输出 BTB+BHT+RAS 的整体及分类 next-PC 预测准确率，并支持下列三种配置使用同一份 `coremark_10.data` 做 A/B 对比：

1. `BPU_ENABLE=1, BPU_RAS_ENABLE=1`；
2. `BPU_ENABLE=1, BPU_RAS_ENABLE=0`；
3. `BPU_ENABLE=0`。

本任务默认只修改 DV 与必要的仿真入口，不新增 PMU/CSR，不修改 BPU/RAS RTL，不改变 CoreMark 核心源码，也不把统计信号加入 core/soc 对外端口。统计通过 testbench 层次只读访问 EXU 已有信号完成。

已有 `dv/monitor_ras_stats.sv` 仅统计 return resolve/recovery，可继续服务 RAS 小程序 A/B；本任务的 CoreMark 综合统计以 `tb_soctop_userprog.sv` 内的新 monitor 为准，避免两个 monitor 的窗口和分母含义混用。

## 2. 统计口径

### 2.1 唯一采样事件

所有计数均在 EXU 当前 payload 真正通过 EX/MA 握手时采样，基础事件为：

```text
normal_resolve_event = ex_commit_fire
                    && !o_exc_req
                    && !o_trap_ret_req
                    && !bru_fence_i

control_resolve_event = normal_resolve_event && bru_is_control
```

必须直接复用 `u_soc_top.u_core.u_exu` 内部现有组合量，不能以 PC 变化、redirect 电平或 IF 请求数代替。这样 EX/MA backpressure、乘除法多周期等待和 flush 均不会重复计数。

预测正确的统一判定为：

```text
next_pc_correct = (r_pred_next_pc_ex == actual_next_pc)
next_pc_wrong   = (r_pred_next_pc_ex != actual_next_pc)
```

不得只比较 taken/not-taken。完整 next-PC 比较同时覆盖方向错误、target 错误、RAS target 错误和 BTB 对普通指令的陈旧/alias 命中。

### 2.2 主指标与辅助指标

主指标为控制流指令准确率：

```text
control_accuracy = control_correct / control_total * 100%
```

同时报告：

```text
all_next_pc_accuracy = normal_correct / normal_total * 100%
mispredict_mpki      = normal_wrong / normal_total * 1000
```

`all_next_pc_accuracy` 会被大量顺序指令稀释，不能替代 `control_accuracy`；它用于捕获 BTB 在非控制流 PC 上错误改流。`mispredict_mpki` 的分母是本统计窗口内正常提交的指令数，不是 cycle 数。

### 2.3 互斥分类

每个 `control_resolve_event` 必须且只能进入以下一个桶：

| 分类 | 条件 | 主要反映的预测来源 |
|---|---|---|
| `COND` | `bru_is_cond` | BTB target + BHT direction 的联合 next-PC 结果 |
| `JAL` | `ras_is_jal` | BTB 对直接跳转的学习结果 |
| `JALR_RETURN` | `ras_is_jalr && ras_resolve_pop_raw` | RAS；关闭/空栈时包含 BTB fallback |
| `JALR_OTHER` | `ras_is_jalr && !ras_resolve_pop_raw` | BTB 对非 return 间接跳转的结果 |

`COND` 额外按真实 `bru_taken` 分为 taken/not-taken 两组，各自输出 total/correct/wrong。`JALR_RETURN` 使用未被 `BPU_RAS_ENABLE` 门控的 raw decode 分类，使 RAS on/off 的 denominator 可比。pop+push coroutine 归入 `JALR_RETURN`，因为其当前指令会消费 RAS top 形成预测目标。

另计 `non_control_wrong`：`normal_resolve_event && !bru_is_control && next_pc_wrong`。该值正常应为 0；非 0 表示普通指令发生错误 next-PC 预测，不能藏在控制流准确率之外。

本任务不宣称单次预测究竟来自 BTB 还是 RAS。当前流水只携带最终 `pred_next_pc`，没有携带 predictor-source metadata；RAS 的收益通过相同 CoreMark 下 RAS on/off 的 `JALR_RETURN` 准确率和 recovery 数差异证明。如未来需要 BTB hit/RAS hit 精确归因，应另立任务增加随流水传递的来源元数据。

## 3. CoreMark 统计窗口

### 3.1 为什么不能从 reset 一直统计到 `$finish`

当前 CoreMark 未使用 x26/x27 结束协议，`main` 返回后会进入 `start.S` 的永久 `j loop`；testbench 最终依靠长 watchdog 结束。若从 reset 统计到 watchdog，大量已训练的自旋 JAL 会人为把准确率推近 100%。UART 结果打印、初始化和 CRC 检查也不属于 CoreMark timed benchmark。

因此主报告只统计 `core_main.c` 中实际 `iterate(&results[0])` 的执行区间：

- EX 提交 `iterate` 入口 PC 时打开窗口；
- EX 提交 `stop_time` 入口 PC 时关闭并冻结窗口；
- stop marker 本身不计入窗口；`iterate` 的最终 return 已在 stop marker 之前提交，因此会被统计。

已核对 `tests/programs/coremark_10/coremark_10.data` 与 `tests/programs/coremark/coremark.data` 完全相同，SHA-256 均为：

```text
093319b2ba22d2a8bbdde6bd575139a0dc842e033868874e155820bae5ec9761
```

因此可使用对应 `tests/programs/coremark/coremark.dump` 中的符号地址：

```text
iterate   = 0x000008fc
stop_time = 0x00004638
```

这两个地址作为当前已编译 `coremark_10` 镜像的已核验默认值，但仍必须能由 plusarg 覆盖。若以后替换 `coremark_10.data`，必须先检查 SHA-256；hash 不再匹配时不得继续沿用旧地址，而应从新镜像对应的 ELF/dump 重新取得符号地址。

### 3.2 窗口配置接口

共享 `sim/makefile` 在 `name=coremark_10` 时自动为 testbench 定义 `PROG_COREMARK_10`。该宏启用统计，并使用已核验的默认地址 `0x000008fc/0x00004638`，所以正常使用无需增加参数：

```text
make sim_userprog name=coremark_10
```

同时保留运行时 plusarg，供手动启用或覆盖地址：

```text
+BPU_STATS
+BPU_STATS_START_PC=<hex>   // iterate
+BPU_STATS_STOP_PC=<hex>    // stop_time
```

要求：

- `PROG_COREMARK_10` 定义时自动启用统计并加载当前镜像默认 start/stop PC；plusarg 地址优先级高于默认值。
- 非 `coremark_10` 且未给 `+BPU_STATS` 时统计逻辑静默，不改变现有 user-program flow。
- 对其他程序手动给出 `+BPU_STATS` 时必须同时取得 start/stop PC，否则在仿真开始阶段 `$fatal`，禁止输出看似有效但窗口错误的结果。
- reset 期间清零全部计数和 `active/done` 状态。
- start 只接受一次；stop 仅在 active 后接受一次。重复 start、stop-before-start 或仿真结束仍未见 stop 均报告明确错误。
- stop 后冻结计数并立即打印一次结果；testbench 不因统计完成而提前 `$finish`，CoreMark 仍继续输出 CRC/validation 结果。
- watchdog/final 路径只在尚未成功打印时给出 incomplete 报告，不得把残缺窗口标成有效准确率。

### 3.3 Bring-up 进度与完成判定

当前 `tb_soctop_userprog.sv` 尚无 CoreMark 完成协议：`check_x26_x27()` 未启动，当前 CoreMark 镜像也未依赖 x26/x27，程序结束后会进入永久循环。现有 `print_sim_time` 只能证明仿真时间在推进，不能证明 core 或 CoreMark 在推进；12 秒全局 watchdog 也不适合作为快速 bring-up 的首个故障反馈。

启用 `+BPU_STATS` 后必须增加以下阶段报告：

```text
[COREMARK STAGE] ARMED start_pc=000008fc stop_pc=00004638
[COREMARK STAGE] BENCHMARK_START pc=000008fc
[COREMARK HEARTBEAT] cycles=... pc=... committed=... control=... recovery=...
[COREMARK STAGE] BENCHMARK_DONE pc=00004638
[BPU STATS] status=VALID ...
[COREMARK RESULT] PASS 或 PASS_BRINGUP
```

行为定义：

- plusarg 解析成功后立即打印 `ARMED`，证明统计器已启用且参数有效。
- EX 提交 `iterate` 入口时打印 `BENCHMARK_START` 并开启窗口。
- active 期间按可配置 cycle 间隔打印 heartbeat，至少包含当前 EX PC、累计正常提交数、控制流数和 recovery 数；同时记录相邻 heartbeat 的提交增量，用于识别“仿真时间前进但 core 无退休”的卡死。
- EX 提交 `stop_time` 入口时打印 `BENCHMARK_DONE`，冻结并**立即打印完整 `[BPU STATS]`**。这表示 benchmark timed body 已执行完，但还未证明后续 CRC 校验成功。
- UART monitor 按行解析输出；收到完整的 `Correct operation validated. See README.md for run and reporting rules.` 行后打印 `[COREMARK RESULT] PASS` 并主动 `$finish`，不再等待程序落入永久循环或全局 watchdog。UART 字符在接收时已通过 `$write` 实时输出到 terminal 和 `sim.log`，终态无需重复整段缓冲区。
- 收到 list/matrix/state CRC、数据类型、`Cannot validate operation...` 等功能错误时打印 `[COREMARK RESULT] FAIL` 并主动结束。当前 10-iteration 镜像仍保留官方最短 10 秒检查；单独出现 `ERROR! Must execute for at least 10 secs` 时记录预期 warning，若随后没有任何功能错误，则在 `Errors detected` 行输出 `PASS_BRINGUP`。该状态只表示快速功能 bring-up 通过，不是正式 CoreMark 成绩。

必须提供三个可覆盖的 cycle timeout：reset release 到 `BENCHMARK_START`、`BENCHMARK_START` 到 `BENCHMARK_DONE`、`BENCHMARK_DONE` 到 UART PASS/FAIL。任一超时立即打印当前 stage、PC、累计提交数和统计完整性状态后 `$fatal`，无需等 12 秒总 watchdog。默认值应按一次已成功的 `coremark_10` 运行实测后留出合理裕量，并允许通过 plusarg 调整。

预编译 `coremark_10` 的 data 尾部 seed4 为 `0x0000000a`，即 benchmark workload 为 10 iterations，且当前反汇编会直接跳过 `iterations==0` 的自动标定循环，只进入一次正式 `iterate()`。由于镜像未编译 iteration progress UART，本任务不通过脆弱的函数内部 PC 猜测“第 N/10 次”；heartbeat 用提交持续增长证明 liveness，`stop_time` 和 UART validation 分别证明 benchmark 完成与架构结果完成。

为支持用户指定的直接运行入口，共享 `sim/makefile` 必须在 `name=coremark_10` 时自动加入 `+define+PROG_COREMARK_10`；另增加只透传到 `./simv` 的 `SIMV_ARGS ?=` 供可选覆盖，以及用于 A/B 编译覆盖的 `EXTRA_VCS_DEFINES ?=`。不得改变 ISA/Compliance 或其他 user-program 的默认行为。默认 RAS-on 运行形式固定为：

```text
make sim_userprog name=coremark_10
```

## 4. Testbench 实现设计

### 4.1 层次信号

`tb_soctop_userprog.sv` 统一为下列 EXU 信号建立只读 alias wire；后续计数代码只使用 alias，避免散布长层次路径：

```text
u_soc_top.u_core.u_exu.ex_commit_fire
u_soc_top.u_core.u_exu.o_exc_req
u_soc_top.u_core.u_exu.o_trap_ret_req
u_soc_top.u_core.u_exu.bru_fence_i
u_soc_top.u_core.u_exu.bru_is_control
u_soc_top.u_core.u_exu.bru_is_cond
u_soc_top.u_core.u_exu.bru_taken
u_soc_top.u_core.u_exu.ras_is_jal
u_soc_top.u_core.u_exu.ras_is_jalr
u_soc_top.u_core.u_exu.ras_resolve_pop_raw
u_soc_top.u_core.u_exu.r_pc_exu
u_soc_top.u_core.u_exu.r_pred_next_pc_ex
u_soc_top.u_core.u_exu.actual_next_pc
u_soc_top.u_core.u_exu.prediction_recovery_req
```

这些名称是当前 RTL 的非端口内部实现细节。若实现时名称变化，只允许同步调整 TB alias，不为统计目的改 RTL 接口。

### 4.2 计数器与更新规则

- 使用至少 64-bit 无符号计数器，避免正式 CoreMark 多 iteration 溢出；不要使用 32-bit `integer` 作为长期计数器。
- 所有计数只在 `posedge clk`、`rst_n && stats_active` 下更新。
- 对 normal、control、各分类、COND taken/not-taken 分别维护 `total` 与 `correct`；`wrong` 在报告时用 `total-correct` 推导，减少状态和自相矛盾机会。
- 独立记录 `prediction_recovery_count` 和 `non_control_wrong`。
- 每个 `normal_resolve_event` 上检查 `prediction_recovery_req == next_pc_wrong`；每个 control event 上检查分类 one-hot。违反时增加 error counter 并打印首个错误的 PC、predicted/actual next-PC。
- 处理 stop PC 当拍时先完成该拍窗口边界判断，再冻结；stop marker 不计入 normal/control denominator。

准确率输出可用 `real` 临时变量，或使用整数缩放到 basis points 后格式化；无论采用哪种方式，denominator 为 0 时必须打印 `N/A`，不得除零或显示 0% 冒充有效数据。

### 4.3 报告格式

日志采用固定、便于 grep/脚本解析的前缀，至少输出：

```text
[BPU STATS] status=VALID start_pc=... stop_pc=...
[BPU STATS] config BPU_ENABLE=1 BPU_RAS_ENABLE=1
[BPU STATS] NORMAL total=... correct=... wrong=... accuracy=... mpki=...
[BPU STATS] CONTROL total=... correct=... wrong=... accuracy=...
[BPU STATS] COND total=... correct=... wrong=... accuracy=...
[BPU STATS] COND_TAKEN total=... correct=... wrong=... accuracy=...
[BPU STATS] COND_NOT_TAKEN total=... correct=... wrong=... accuracy=...
[BPU STATS] JAL total=... correct=... wrong=... accuracy=...
[BPU STATS] JALR_RETURN total=... correct=... wrong=... accuracy=...
[BPU STATS] JALR_OTHER total=... correct=... wrong=... accuracy=...
[BPU STATS] RECOVERY total=... non_control_wrong=... consistency_errors=...
```

输出中的 `wrong` 必须与 prediction recovery 口径一致。总体 recovery 包含控制流错误和非控制流错误，因此应满足：

```text
normal_wrong == prediction_recovery_count
normal_wrong == control_wrong + non_control_wrong
control_total == cond_total + jal_total + jalr_return_total + jalr_other_total
```

任一等式不成立时报告 `status=INVALID`，并使专项仿真返回失败。

## 5. 预期修改范围

| 文件 | 修改要求 |
|---|---|
| `dv/tb_soctop_userprog.sv` | 增加 plusarg、CoreMark 窗口状态、64-bit 分类计数、heartbeat、UART 终态识别、分阶段 timeout、主动结束和固定格式报告 |
| `sim/makefile` | 对 `name=coremark_10` 自动定义 `PROG_COREMARK_10`，并增加 `SIMV_ARGS`/`EXTRA_VCS_DEFINES` 透传，使原命令可直接运行统计及三配置 A/B；保持其他默认 flow 不变 |
| `doc/dev_log/task_v11_03_branch_prediction_accuracy_stats.md` | 本工单；实施后补充实际命令、地址、结果和状态历史 |
| `doc/dev_log/log_dev_v11.md` | 任务完成后增加简短逆序记录 |

原则上不修改 `de/`、`filelists/`、CoreMark C/汇编源码或已有 `monitor_ras_stats.sv`。如果层次可见性受工具限制，应优先在 DV 中使用 bind/独立 monitor；不得仅为可见性给 EXU 增加架构或综合端口。

## 6. 实施步骤

1. 从当前 `exu.sv` 固化统计事件、next-PC 判定和四个互斥分类，在 TB 中建立短 alias wire。
2. 加入 `+BPU_STATS` 与 start/stop PC 解析、配置合法性检查和只触发一次的窗口状态机，输出 ARMED/START/DONE stage。
3. 加入 64-bit normal/control/分类计数器，以及 recovery、non-control wrong、分类 one-hot 和等式一致性检查。
4. 实现 heartbeat、三阶段 timeout 及 UART 按行 PASS/FAIL 识别；终态出现后打印结果并主动结束仿真。
5. 实现统一统计报告 task/function，处理 0 denominator，并保证 VALID/INVALID 可由日志稳定解析。
6. 给 `sim/makefile` 增加 `coremark_10` 自动宏及纯透传参数；确认 `sim_userprog name=simple` 无统计，而原始 `sim_userprog name=coremark_10` 无需附加参数即可进入统计模式。
7. 使用现成的 `coremark_10.data` 做首轮验证和三组 A/B；每组必须使用同一个 data、相同起止 PC、相同统计窗口，禁止在三组之间重新生成 benchmark。
8. 保存三组 stage/heartbeat、`[BPU STATS]`、CoreMark CRC 和 `[COREMARK RESULT]` 证据，更新本工单和 `log_dev_v11.md`。

## 7. 专项验证计划

### 7.1 静态与短仿真检查

- 不带 `+BPU_STATS`：现有 user-program 仿真无新报告、无 `$fatal`。
- 只给一个 PC 参数：仿真立即失败并指出缺失参数。
- 错误 start PC：到 watchdog/final 时报告 `INCOMPLETE`，不能报告 VALID。
- stop-before-start、重复 start/stop：报告 protocol error。
- start、run、UART-result 三种 timeout 分别用缩短阈值触发，均应在全局 watchdog 前 `$fatal`，且日志包含最后 PC/提交数。
- active heartbeat 的 committed delta 持续增长；人为停止有效提交时能够报告无进展，而非只打印仿真时间。
- stop marker 到达时 `[BPU STATS]` 立即出现；UART PASS 行到达后出现 `[COREMARK RESULT] PASS` 并正常结束。
- 注入 CRC/数据类型错误文本时出现 `[COREMARK RESULT] FAIL`，不得继续等待永久循环；只有官方时长不足 warning 时应输出 `PASS_BRINGUP`。
- 人为选择一个极短 PC 窗口：手工从波形/EX trace 核对 total、分类和 correct/wrong。
- 制造 0 denominator 分类时打印 `N/A`。
- EX/MA backpressure 存在时，同一 EX payload 只计一次。

### 7.2 CoreMark_10 运行

本任务不重新编译 CoreMark，直接使用用户已准备好的 `coremark_10.data`。在 `work/my-RISCV-Projs/sim` 通过原始命令运行，Makefile 自动启用统计、进度和完成检测：

```text
make sim_userprog name=coremark_10
```

三配置的预期命令接口为：

```text
# BPU on, RAS on
make sim_userprog name=coremark_10 DESIGN_NAME=../11_rv32im_bpu

# BPU on, RAS off
make sim_userprog name=coremark_10 DESIGN_NAME=../11_rv32im_bpu \
  EXTRA_VCS_DEFINES="+define+BPU_RAS_ENABLE=0"

# BPU off（总开关关闭时 RAS 同时失效）
make sim_userprog name=coremark_10 DESIGN_NAME=../11_rv32im_bpu \
  EXTRA_VCS_DEFINES="+define+BPU_ENABLE=0"
```

实现后必须确认 compile log 中宏值实际生效。三组均复制同一份 `tests/programs/coremark_10/coremark_10.data`，确保动态路径和 denominator 可比较。

代表性结果至少满足：

- 三组均完成窗口并输出 `status=VALID`、`consistency_errors=0`。
- 三组均依次出现 ARMED、BENCHMARK_START、至少一个 heartbeat、BENCHMARK_DONE 和 `[COREMARK RESULT] PASS`/`PASS_BRINGUP`；统计结果必须在 BENCHMARK_DONE 时打印，最终结果必须等待 UART validation/error summary 行。
- CoreMark 输出 `Correct operation validated`，CRC 一致，并由 TB 主动结束而非全局 watchdog 结束。
- 三组 `NORMAL/CONTROL/COND/JAL/JALR_RETURN/JALR_OTHER` 的 total 完全一致。
- 每组均满足 `correct + wrong == total` 及第 4.3 节三条守恒关系。
- BPU on 相对 BPU off 的 `CONTROL` 准确率应提高；若未提高，必须定位并记录原因，不能只给百分比。
- RAS on 相对 RAS off 的 `JALR_RETURN` wrong/recovery 应减少或至少不增加；若 CoreMark 动态 return 深度/行为使结果不改善，应结合计数和波形如实说明，不虚报收益。

`coremark_10` 用于本核的仿真统计与配置对比，不把其结果表述为符合 EEMBC 正式提交规则的 CoreMark 分数。准确率报告必须记录 data 的 SHA-256、start/stop 地址、BPU/RAS 配置和 UART 输出的 `Total ticks`。

### 7.3 回归边界

若实施仅修改 TB/仿真参数透传，则至少执行：

- `sim_userprog name=simple` 的默认无统计 smoke；
- `coremark_10` 统计三配置，并核对三组 denominator 与 CRC。

纯 DV 修改无需运行 DC。若实现过程中修改任何 `de/` RTL、config 默认值或 filelist，则必须额外执行 [`rule_ai_acceptance.md`](rule_ai_acceptance.md) 的全部 ISA/Compliance 回归和 `syn/make check`，并在工单中记录结果。

## 8. 风险与处理要求

### 8.1 层次信号脆弱性

TB 读取 EXU internal wire 对重命名敏感，但不会污染综合接口。所有层次引用必须集中定义，并由 VCS 全设计编译验证。若 Icarus 不支持相关层次或 SystemVerilog 特性，可在 `IVERILOG` 下关闭该 monitor并明确提示；VCS CoreMark flow 必须工作。

### 8.2 窗口地址与二进制不匹配

硬编码旧 dump 地址会得到错误或 incomplete 结果。地址必须来源于本次实际加载的 binary；报告首行必须回显 start/stop PC。建议后续在仿真脚本中从 ELF symbol table 自动生成参数，但本任务不强制引入新的解析脚本。

### 8.3 百分比看似正常但分母错误

只看 accuracy 数值不足以验收。必须同时报告原始 total/correct/wrong，并用三配置 denominator 一致性证明统计的是同一动态 CoreMark 路径。不得把全指令准确率标成分支准确率。

### 8.4 recovery 与控制流错误并非永远同义

`prediction_recovery_req` 会覆盖普通指令上的错误 BTB 命中，所以总体关系是 `normal_wrong == recovery`，不是简单的 `control_wrong == recovery`。控制流之外的差额必须落入 `non_control_wrong`。

### 8.5 仿真结束与报告完整性

统计窗口结束不代表 CoreMark CRC 已完成。monitor 在 stop marker 处冻结/打印，UART monitor 继续运行，最终验收同时检查 `[BPU STATS] status=VALID` 和 CoreMark validation 文本。license server 或 watchdog 阻塞时必须记录为未完成，不得依据部分计数下结论。

## 9. 交付判定

任务完成时应具备：

- `tb_soctop_userprog.sv` 中可关闭、窗口明确、不会影响 DUT 的统计逻辑；
- 固定格式的整体、分类、taken/not-taken、return、non-control 和 MPKI 数据；
- 三种 BPU/RAS 配置在同一 CoreMark binary 上的原始计数与准确率对照；
- 所有守恒检查通过，CoreMark 架构结果/CRC 一致；
- 对统计窗口、地址来源、构建参数和任何未执行项的明确记录。

完成后按仓库规范将新状态 prepend 到本工单 `Status`，保留 `Ready for Execution` 历史；在本工单追加实施与验收记录，并更新 [`log_dev_v11.md`](log_dev_v11.md)。

## 10. 实施与验证记录（2026-08-20）

### 10.1 已实现内容

- `dv/tb_soctop_userprog.sv` 已增加 `coremark_10` 自动统计模式；默认窗口为 `iterate=0x000008fc` 至 `stop_time=0x00004638`，并支持 plusarg 覆盖地址、heartbeat 和三阶段 timeout。
- 统计在 EX `ex_commit_fire` 上采样，输出 NORMAL、CONTROL、COND taken/not-taken、JAL、JALR return/other、recovery、non-control wrong、准确率和 MPKI，并执行分桶/计数守恒检查。
- 增加 ARMED、BENCHMARK_START、heartbeat、BENCHMARK_DONE 阶段输出；到达 stop marker 时立即冻结并打印统计。
- UART monitor 已增加行级终态识别：CRC/数据类型错误为 FAIL；正式 validation 文本为 PASS；仅官方最短时长警告导致的 `Errors detected` 为 `PASS_BRINGUP`。终态后主动 `$finish`，不等待启动汇编永久循环。
- `sim/makefile` 在 `name=coremark_10` 时自动加入 `PROG_COREMARK_10`，并支持 `SIMV_ARGS`、`EXTRA_VCS_DEFINES`；原命令 `make sim_userprog name=coremark_10` 可直接启用统计，输出由 `tee` 同时送往 terminal 和 `sim.log`。

### 10.2 已执行检查

- `make com_userprog name=coremark_10 DESIGN_NAME=../11_rv32im_bpu`：VCS compile/elaboration/link PASS，确认 `+define+PROG_COREMARK_10` 生效。
- `make com_userprog name=simple DESIGN_NAME=../11_rv32im_bpu`：VCS compile/elaboration/link PASS，确认非 CoreMark user program 不自动定义该宏。
- Make dry-run 确认 `EXTRA_VCS_DEFINES=+define+BPU_RAS_ENABLE=0` 和 `+define+BPU_ENABLE=0` 均正确进入 A/B 编译命令。
- `git diff --check` 对本任务修改文件通过；VCS 仅报告既有 WSL2 kernel 版本 warning。

### 10.3 待用户运行确认

按用户要求未执行 `./simv` 或完整 `make sim_userprog name=coremark_10`。因此实际 stage/heartbeat、统计数值、默认 timeout 裕量、UART `PASS_BRINGUP` 终态和主动结束行为仍待用户运行确认；在取得运行日志前不将本工单标记为 Completed，也暂不向 `log_dev_v11.md` 写入完成条目。
