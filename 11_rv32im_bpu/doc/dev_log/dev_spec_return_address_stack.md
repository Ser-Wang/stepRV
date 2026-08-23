# RV32IM 返回地址栈（RAS）功能 SPEC

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-18 01:13
**Current Version**: v1.2

**Version Changelog**:
- **v1.2** (2026-08-18 22:44): 批准首版采用双完整栈结构，将实现模块明确命名为 `ras_dual_full_stack`，为后续同接口替换 C906 风格实现保留实验边界。
- **v1.1** (2026-08-18 21:32): 在指令识别章节先补充 JAL/JALR 各类寄存器用法对应的直接调用、间接调用、返回与 coroutine 语义，再给出精确 hint 对照。
- **v1.0** (2026-08-18 01:13): 初版 RAS 功能规格，定义调用/返回 hint、投机与确认状态、预测优先级及 redirect 恢复语义。

---

## 1. 目标与范围

在现有 BTB+BHT 动态分支预测器上增加小容量返回地址栈（Return Address Stack，RAS），用调用指令产生的 link 地址预测后续函数返回的 `JALR` 目标，改善同一返回指令对应多个动态调用点时 BTB 单目标预测效果差的问题。

本期面向当前 RV32IM、定长 32-bit 指令、5 级顺序单发射流水线：

- 默认 4 项 RAS，每项保存完整 32-bit 返回地址。
- 在 IF 对已返回且将被流水接受的指令做轻量预译码和投机 push/pop。
- 在 EX 的既有唯一移交事件上确认真实 call/return 操作。
- redirect 时撤销年轻错路径对 RAS 的影响。
- RAS 只影响预测 next-PC，不改变 `JAL/JALR` 的架构行为、异常行为或 BTB 训练。

不增加 RVC、多发射、线程/进程标识、地址空间标识、软件可见 RAS 状态、性能 CSR 或通用预测 checkpoint 队列。

## 2. 指令识别与 RAS hint

RAS 按 RISC-V 使用整数寄存器 `x1`（`ra`）和 `x5`（alternate link register）表达的隐式 hint 工作。`link(reg)` 表示寄存器编号属于 `{x1, x5}`。

直观上，`JAL/JALR` 的用法与 RAS 动作对应如下：

- `JAL` 写 link register：直接函数调用，push 返回地址。
- `JALR` 写 link register，且不在 `x1/x5` 之间切换：间接函数调用，push 返回地址。
- `JALR` 从 link register 跳转、但不写 link register：函数返回，pop 返回地址。
- `JALR` 在 `x1/x5` 两个不同 link register 间切换：coroutine 调用，先 pop 再 push。
- 其他普通跳转：不操作 RAS。

具体寄存器条件与动作对照如下。

### 2.1 JAL

| 指令条件 | RAS 动作 |
|---|---|
| `JAL` 且 `link(rd)` | push `PC+4` |
| 其他 `JAL` | 无动作 |

### 2.2 JALR

`JALR` 必须是合法的 `opcode=7'b1100111, funct3=3'b000` 编码。其 RAS 动作如下：

| `link(rd)` | `link(rs1)` | `rd == rs1` | RAS 动作 |
|---:|---:|---:|---|
| 0 | 0 | 任意 | 无动作 |
| 0 | 1 | 任意 | pop |
| 1 | 0 | 任意 | push `PC+4` |
| 1 | 1 | 1 | push `PC+4` |
| 1 | 1 | 0 | 先 pop，再 push `PC+4` |

典型 `ret`（`jalr x0, 0(x1)`）属于 pop。pop+push 支持使用 `x1/x5` 切换 link register 的 coroutine 调用。hint 只由 opcode、`funct3`、`rd`、`rs1` 决定，不额外限制 immediate。

## 3. 栈功能模型

逻辑上 `entry[0]` 为栈顶。默认深度由 `BPU_RAS_ENTRIES=4` 配置，必须为不小于 2 的整数；本期不要求为 2 的幂。

- push：新地址成为栈顶，原有项目向深处移动；栈满时丢弃最深、最旧的一项。
- pop：返回原栈顶并移除它；空栈 pop 保持为空。
- pop+push：非空时以新 link 地址替换原栈顶，深层内容不变；空栈时等价于 push。
- reset：栈为空，entry 内容无功能意义。

RAS entry 保存完整 RV32 地址，不采用 C906 仅保存低位并与当前 PC 高位拼接的方式，避免跨地址区间返回时产生额外 alias。

## 4. 预测行为

IF 使用与 `i_if_instr/o_instr_pc` 对齐的指令和 PC 预译码。只有同时满足下列条件时，RAS 命中并提供预测目标：

```text
ras_pred_hit = BPU_ENABLE && BPU_RAS_ENABLE
             && current instruction has pop hint
             && speculative RAS is not empty
```

最终预测 next-PC 的选择为：

```text
RAS return target > existing BTB/BHT predicted next-PC
```

RAS 未启用、非 pop-hint 指令或 RAS 为空时，完全沿用现有 BTB/BHT 结果；因此空栈 return 仍可由已训练的 BTB 预测，BTB miss 时则预测 `PC+4`。RAS 命中不要求 BTB hit。

最终实际采用的 next-PC 继续通过现有 `o_pred_next_pc_if` 随指令传至 ID/EX。EX 仍只比较 `pred_next_pc_ex` 与 `actual_next_pc`，因此 RAS 目标错误、空栈 fallback 错误和普通 BTB 错误使用同一 prediction recovery 通路，不新增恢复类别。

## 5. 投机更新、确认与恢复

RAS 维护两份逻辑状态：

- speculative state：服务 IF 查询，并在当前 IF payload 被真实接受时更新。
- committed state：只在无异常的 call/return 指令通过 `ex_commit_fire = o_ex_ma_vld && i_ex_ma_rdy` 时更新。

投机 push/pop 必须绑定当前 IF 的真实接受事件：

```text
if_accept = o_if_id_vld && i_if_id_rdy && !i_stall && !i_redirect_req
```

stall、下游反压、无效 IF payload 或 redirect 当拍均不得投机更新。EX 下游反压期间也不得重复更新 committed state。

任何现有 redirect（exception、`mret`、`fence.i` 或 prediction recovery）都把 speculative state 恢复为 committed state。若 redirect 指令自身是一个无异常 call/return，则恢复结果必须包含该指令在同一个 `ex_commit_fire` 上产生的 committed 更新，即恢复到 post-commit state；若指令产生异常，则不得确认其 RAS 动作。

`fence.i` 继续失效 BTB/BHT，但不清空 committed RAS；它只撤销被 flush 的年轻投机操作。exception 与 `mret` 同样不清空已确认的调用上下文。只有 reset 清空两份 RAS 状态。

## 6. 配置与模块归属

| 配置项 | 默认值 | 含义 |
|---|---:|---|
| `BPU_RAS_ENABLE` | `1` | RAS 功能开关；`BPU_ENABLE=0` 时其有效值也必须为 0 |
| `BPU_RAS_ENTRIES` | `4` | speculative/committed 两份逻辑栈各自的深度 |

首版新增 `de/core/ras_dual_full_stack.sv` 并由 `ifu.sv` 实例化。模块名显式表达“双完整栈”结构，避免把一种实现误认为唯一通用 RAS；后续 C906 风格实现使用不同模块名，但保持相同外部端口，以便直接替换实验。结构选择及后续实验见 [`decision_log_ras.md`](decision_log_ras.md)。

| 模块 | 职责 |
|---|---|
| `ras_dual_full_stack` | 前端预测栈与后端确认栈两份完整 entry、top 查询、push/pop/pop+push、同拍 resolve+recover 次序 |
| `ifu` | IF 指令预译码、`if_accept` 投机事件、RAS 与 BTB/BHT 预测仲裁 |
| `exu` | 根据真实 `JAL/JALR`、`rd/rs1` 和 `ex_commit_fire` 产生确认动作 |
| `core` | 传入 IF 指令并连接 EX 到 IFU 的 RAS 确认反馈 |

现有 `pred_next_pc` 流水 payload、BRU 实际目标计算、BTB/BHT 更新、redirect 仲裁和 `ctrl_hazard` flush 语义保持不变。

## 7. 参考设计取舍

C906 的 RAS 为 4 项，在前端预译码后投机更新 `ras_pop`，后端 BJU 以 `ras_bju` 维护确认位置，并在前端 flush、方向误判或目标误判时恢复投机位置。本设计沿用“小容量栈、前端投机、后端确认、错流恢复”的核心机制。

结合当前核规模，本期不照搬 C906 的低 24-bit entry、one-hot 环形指针、仅 `x1` 识别和时钟门控结构；采用完整 32-bit 地址、`x1/x5` 标准 hint，以及可精确恢复内容的 speculative/committed 双状态。
