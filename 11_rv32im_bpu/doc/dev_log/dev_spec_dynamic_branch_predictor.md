# RV32IM 基础动态分支预测器功能 SPEC

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-07-10 00:00
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-08-16 22:41): 按 `11_rv32im_bpu` 当前 valid/ready 与流水 payload 更新语义校正实现约束，补充 EX 唯一提交事件、版本 filelist 隔离及从 v10 预实现迁移时的差异检查。
- **v1.0** (2026-07-10 00:00): 初版基础动态分支预测器功能规格。

---

## 1. 目标与范围

为 `11_rv32im_bpu/de` 的 5 级顺序单发射流水线增加一个最基础、可综合、可关闭的动态分支预测器。预测器采用经典的小容量结构：

- 直接映射 BTB（Branch Target Buffer）：保存控制流指令 PC 的 tag、目标地址和类型。
- 独立 BHT（Branch History Table）：每项为 2-bit 饱和计数器，只预测条件分支方向。
- EX 级解析和训练：BRU 给出真实方向与目标，EX 比较预测 next-PC 与真实 next-PC，误判时沿现有 redirect/flush 通路恢复。

本期覆盖 RV32I 的 `BEQ/BNE/BLT/BGE/BLTU/BGEU/JAL/JALR`。不实现全局历史、gshare、RAS、间接跳转多目标预测、预测队列、投机更新、I-cache 或多发射支持，也不改变核对外取指接口。

## 2. 当前设计事实

- 流水为 `IFU -> IDU -> EXU -> MAU -> WBU`，各级已有 `vld/rdy` 语义。
- ITCM 指令读为固定一拍返回；`ifu.sv` 的 `pc_r/o_instr_pc` 与当前 `i_if_instr` 对齐，`o_fetch_pc` 表示下一次请求地址。
- IF 接收事件为 `if_accept = o_if_id_vld && i_if_id_rdy && !i_stall && !i_redirect_req`；预测器必须查询 `pc_r`，不能查询已经过 redirect/预测 mux 的 `if_req_pc/o_fetch_pc`。
- 当前 v11 的 IDU/EXU payload 寄存器仅在“输入 valid && 本级 ready && !flush”的真实接收事件更新；空泡、仅 ready、stall 和 flush 均不得改写与有效指令关联的 payload。新增预测元数据必须沿用这一语义，不能照抄 v10 预实现中仅以 `o_*_rdy` 为条件的写法。
- 分支、跳转在 `exu_bru.sv` 解析，现有 `exu.sv` 统一仲裁 branch、exception、`mret` 等 redirect。
- `ctrl_hazard.sv` 收到 redirect 后清除 IF/ID 与 ID/EX 的年轻指令。
- EX 当前完成条件为 `ex_result_done`，`o_ex_ma_vld = r_ex_vld && ex_result_done`，因此向 MAU 的唯一移交事件是 `o_ex_ma_vld && i_ex_ma_rdy`。预测训练、invalidate 和预测恢复必须绑定该真实 valid/ready fire。
- 当前 `filelists/filelist_sim_sram.f` 与 `filelist_syn_sram.f` 仍引用 `../10_rv32im`，属于 v11 实施前必须修正的路径隔离问题；验证不能只看 PASS 汇总，必须确认编译输入来自 `11_rv32im_bpu`。
- 全核只有 `clk` 一个时钟域，状态寄存器使用低有效异步复位 `rst_n`。

`10_rv32im_copy` 的实现与回归结果仅作为行为参考，不作为可直接覆盖 v11 RTL 的补丁来源。已验证的 v10 预实现实际把 BTB/BHT 深度配置为 4，与其文档所写默认 16 不一致；v11 仍以本 SPEC 的默认 16 为准，并必须验证实际编译宏值。

## 3. 总体结构

```text
                       EX resolution/update
                  +----------------------------+
                  | pc/type/taken/target/fence.i|
                  v                            |
Fetch PC ----> +------------------+            |
               | branch_predictor |            |
               |  BTB + BHT(2bit) |            |
               +--------+---------+            |
                        | predicted next PC     |
                        v                       |
                 +-------------+                |
                 |     IFU     |-- request PC --+--> ITCM
                 +------+------+                |
                        | instruction PC + predicted next PC
                        v
                      IDU -> EXU/BRU
                              |
                              +-- compare actual next PC
                                  mismatch -> existing redirect/flush
```

推荐新增 `de/core/branch_predictor.sv`，作为 `ifu` 的子模块。模块边界如下：

| 模块 | 负责 | 不负责 |
|---|---|---|
| `branch_predictor` | BTB/BHT 状态、查表、2-bit 更新、BTB 替换、invalidate | PC 寄存器、流水 flush、真实分支条件计算 |
| `ifu` | 当前 PC、顺序/预测/redirect PC 选择、取指与预测元数据对齐 | 修改预测表、判断误预测 |
| `idu` | 将 `pred_next_pc` 作为 IF/ID payload 随 PC/指令保持与传递 | 重新预测或训练 |
| `exu_bru` | 计算真实控制流类型、taken、target | 直接写表、直接控制 IFU |
| `exu` | 保存预测元数据、生成一次性训练事件、next-PC 比较、redirect 仲裁 | 拥有 BTB/BHT 存储 |
| `core` | 连接 EX 训练/失效反馈到 IFU，保持顶层只做集成 | 复制预测或计数器逻辑 |
| `ctrl_hazard` | 复用现有 redirect flush 机制 kill 年轻指令 | 判断预测是否正确 |

## 4. 配置项

默认值由 `de/defines/config.v` 统一定义，`branch_predictor` 消费这些编译期配置。表深度只影响模块内部索引和阵列大小，不改变模块端口宽度。

| 配置项 | 默认值 | 约束与含义 |
|---|---:|---|
| `BPU_ENABLE` | `1` | 为 `0` 时恒预测 `PC+4`，禁止训练；保留真实 redirect 功能 |
| `BPU_BTB_ENTRIES` | `16` | 直接映射 BTB 项数，必须为不小于 2 的 2 次幂 |
| `BPU_BHT_ENTRIES` | `16` | BHT 项数，必须为不小于 2 的 2 次幂 |
| `BPU_BHT_INIT` | `2'b01` | 复位初值：weakly not-taken |
| `XLEN` | 现有 `32` | 本期只支持 RV32；沿用已有配置 |

2-bit 计数器位宽固定为 2，不做可变位宽参数，避免配置名称与“经典 2-bit 预测器”语义不一致。实现中应集中派生 `BTB_INDEX_WIDTH/BHT_INDEX_WIDTH/BTB_TAG_WIDTH`，不得在多个模块重复计算。

## 5. BTB 与 BHT 组织

### 5.1 BTB

BTB 为直接映射表，每项包含：

```text
valid          1 bit
tag            PC[31 : 2 + BTB_INDEX_WIDTH]
target         32 bits
is_conditional 1 bit
```

- 查表索引：`fetch_pc[2 + BTB_INDEX_WIDTH - 1 : 2]`。
- tag 比较忽略恒为 `00` 的 RV32 指令字节偏移。
- `valid && tag_match` 才是 BTB hit；仅 index 相同不能命中。
- BTB 采用覆盖式直接映射替换，不需要 LRU。
- `is_conditional=1` 表示 B-type 条件分支；`JAL/JALR` 写为 0，命中后恒预测 taken。

### 5.2 BHT

BHT 为独立的 2-bit 计数器数组，索引为：

```text
bht_index = pc[2 + BHT_INDEX_WIDTH - 1 : 2]
```

允许不同 PC 在 BHT 中 alias；这是本基础结构的预期行为。状态定义与预测规则为：

| 状态 | 名称 | 预测 |
|---|---|---|
| `2'b00` | strongly not-taken | not-taken |
| `2'b01` | weakly not-taken | not-taken |
| `2'b10` | weakly taken | taken |
| `2'b11` | strongly taken | taken |

条件分支真实 taken 时计数器加 1并在 `11` 饱和；真实 not-taken 时减 1并在 `00` 饱和。`JAL/JALR` 不读写 BHT。

## 6. 预测算法

对当前与返回指令对齐的 `fetch_pc` 做组合查表：

```text
btb_hit         = btb_valid[index] && (btb_tag[index] == fetch_tag)
direction_taken = bht_counter[bht_index][1]
pred_taken      = BPU_ENABLE && btb_hit
                  && (!btb_is_conditional[index] || direction_taken)
pred_target     = btb_target[index]
pred_next_pc    = pred_taken ? pred_target : fetch_pc + 4
```

冷启动、BTB miss、条件分支计数器 MSB 为 0 时均取顺序地址。BTB/BHT 使用小容量寄存器阵列和组合读，写入在时钟沿完成；不要求推断同步 SRAM。若同一拍 IF 查询与 EX 更新同一项，IF 观察旧状态，下一拍才观察更新结果，不增加写穿透 bypass。

IFU 的 PC 选择优先级必须是：

```text
EX redirect > 成功接受当前 IF payload 后的 pred_next_pc > 保持当前 PC
```

redirect 当拍不得把旧路径 payload 作为有效指令交给 IDU。`o_fetch_req/o_fetch_pc/i_if_instr` 的现有固定一拍协议保持不变。

`o_pred_next_pc_if` 是对 `pc_r/o_instr_pc/i_if_instr` 这一组当前 IF payload 的预测结果；IF 仅在 `if_accept` 时用它形成下一请求地址。redirect 时 `if_req_pc` 直接选择恢复地址，且 `o_if_id_vld` 被压低，不能把 redirect 地址的预测或旧路径预测错误地附着到当前返回指令。

## 7. 预测元数据随流水传递

每条进入流水线的指令必须携带当时实际采用的 `pred_next_pc`，并与 `instr_pc` 同步接收、保持和 flush：

```text
IFU: o_pred_next_pc_if
IDU IF/ID register: r_pred_next_pc_id
IDU: o_pred_next_pc_id
EXU ID/EX register: r_pred_next_pc_ex
```

只传一个 32-bit `pred_next_pc` 是必需接口；BTB hit、预测方向和目标可作为 IFU/BPU 内部 debug 信号，不要求扩大流水 payload。这样可以用一次比较同时识别：

- 方向误判：taken 与 not-taken 不一致。
- 目标误判：均为 taken，但 BTB 中目标已过时，例如 JALR 目标变化。
- 陈旧 BTB 命中：普通指令被错误预测为 taken。

v11 必须显式定义以下接收事件：

```text
if_id_fire = i_if_id_vld && o_if_id_rdy && !i_flush
id_ex_fire = i_id_ex_vld && o_id_ex_rdy && !i_flush
```

`r_pred_next_pc_id` 只在 `if_id_fire` 时写入，`r_pred_next_pc_ex` 只在 `id_ex_fire` 时写入，分别与本级已有 instruction/PC payload 条件完全相同。当下游 not-ready 时三者一起保持；输入无效但本级 ready 时保持旧 payload、仅由 valid 记录空泡；flush 时清 valid，payload 内容无需清零。禁止沿用 v10 预实现中预测 payload 在 `o_if_id_rdy/o_id_ex_rdy` 时无条件更新的行为。

## 8. EX 解析、训练与恢复

### 8.1 真实 next-PC

对无异常的有效 EX 指令定义：

```text
sequential_next_pc = ex_pc + 4

conditional branch:
    actual_next_pc = actual_taken ? branch_target : sequential_next_pc
JAL/JALR:
    actual_next_pc = jump_target
other instruction:
    actual_next_pc = sequential_next_pc
```

EXU 应对每条正常完成的指令比较 `r_pred_next_pc_ex != actual_next_pc`。因此即使 BTB 因代码变化在非控制流指令 PC 上产生陈旧命中，也能回到 `PC+4`，不能只比较 `pred_taken` 与 branch taken。

### 8.2 一次性解析事件

预测恢复、训练和 invalidate 必须绑定一次性 EX 完成/移交事件。按 v11 当前语义统一定义为：

```text
ex_commit_fire = o_ex_ma_vld && i_ex_ma_rdy
               = r_ex_vld && ex_result_done && i_ex_ma_rdy
```

该事件就是有效 EX payload 确实向 MAU 移交，而不是“BRU 组合结果已经可见”。不得仅用 `r_ex_vld`、`redirect_req_bru_raw` 或 `ex_result_done` 产生训练/失效脉冲；EX 被下游反压或 MDU 多周期等待期间不得重复更新、重复 invalidate 或连续产生同一恢复事件。被 flush、无效或发生指令地址异常的控制流指令不得训练预测器。

v10 预实现把 `!i_stall` 额外并入 `ex_resolve_fire`，但 v11 当前 `o_ex_ma_vld` 并未受 `i_stall` 门控，且 `ctrl_hazard` 当前不会置位 `STALL_ID_EX`。因此 v11 不把 `i_stall` 写入 BPU 提交事件，避免 BPU 事件与真实 EX/MA 握手分裂。若未来要让 `STALL_ID_EX` 非零，必须先统一修正 EX 输出 valid、payload 保持和 MAU 接收语义，不能只改 BPU 脉冲。

为避免同一个控制流指令既因 redirect 清 EX valid、又因握手替换 payload 而产生边界歧义，所有 BPU 状态写事件和 prediction recovery redirect 都使用同一个 `ex_commit_fire`。实现应优先定义该 wire，再派生 `update_vld/invalidate/prediction_recovery_req`，不要在各输出上重复拼接不同的 valid/ready 条件。

### 8.3 训练接口

EXU 向预测器提供以下逻辑事件；端口可按项目 `i_/o_` 规范命名：

```text
update_vld       // 一拍脉冲，仅真实 BXX/JAL/JALR
update_pc        // 控制流指令 PC
update_is_cond   // B-type=1，JAL/JALR=0
update_taken     // B-type 比较结果；JAL/JALR 恒为 1
update_target    // B-type/JAL 为 PC+imm，JALR 为清零 bit[0] 后的 rs1+imm
invalidate       // fence.i 完成事件
```

训练规则：

- 所有正常解析的 B-type、`JAL`、`JALR` 都写/刷新 BTB，包括本次 not-taken 的条件分支；因为其分支目标在 EX 已经可计算。
- 只有 B-type 更新 BHT。
- `JAL/JALR` 写 `is_conditional=0`，以后 BTB 命中即预测 taken。
- 目标地址未按 RV32I 要求对齐并触发异常时，不写 BTB/BHT。
- `fence.i` 不作为 BTB 项训练；它使全部 BTB valid 清零，并将 BHT 恢复为 `BPU_BHT_INIT`，确保自修改代码后没有陈旧预测状态。
- 状态更新优先级：`!rst_n` > `invalidate` > `update_vld`。

### 8.4 redirect 仲裁

EXU 的 redirect 请求优先级定义为：

```text
exception > mret > fence.i > prediction recovery
```

对应地址分别为 `mtvec`、`mepc`、`ex_pc+4`、`actual_next_pc`。普通分支或跳转只有在 `pred_next_pc != actual_next_pc` 时才 redirect；预测正确的 taken 跳转不得再无条件 flush。`ctrl_hazard` 继续复用现有 redirect 行为，清除 IF/ID 和 ID/EX 中年轻的错路径 valid。

接入 BPU 后，现有 `redirect_req_bru_raw = actual taken/fence.i` 不能再直接成为普通 branch/jump 的 redirect 条件；BRU 应提供真实类型、方向和目标，EXU 用 next-PC mismatch 产生 prediction recovery。exception、`mret`、`fence.i` 和 prediction recovery 对 IFU/`ctrl_hazard` 的 redirect 均在 `ex_commit_fire` 上提交，地址仲裁仍保持上述优先级；异常/CSR 模块间既有状态更新接口不在本 SPEC 中另行改义。

## 9. 时钟、复位与 CDC

- 所有预测器状态位于现有 `clk` 域，不新增时钟或 CDC。
- 沿用低有效异步复位 `rst_n`：BTB valid 清 0，BHT 全部设为 `BPU_BHT_INIT`；tag/target/type 在 valid=0 时无需具有功能意义，可清零以利仿真确定性。
- 本期阵列规模较小，允许在复位分支使用循环初始化并综合为触发器阵列；若未来改成 SRAM，应另行定义初始化流程和读延迟，不属于本 SPEC。

## 10. 正确性约束

- `BPU_ENABLE=0` 时，执行结果必须与无预测基线一致：恒顺序取指，真实 taken branch/jump 由 EX 恢复。
- 预测器只能改变性能，不能改变任何架构可见结果。
- 预测错误路径上的 RF、memory、CSR 写和异常请求必须被现有 valid/flush 机制消除。
- BTB miss 不能使用 BHT 的 taken 结果跳转。
- BTB tag miss 不能使用该 index 中残留的 target/type。
- 训练 PC 必须是控制流指令自身 PC，而不是当前 IF PC 或 redirect target。
- 每个已完成控制流指令至多训练一次。
- 正确预测 taken、正确预测 not-taken 时都不能产生 prediction recovery。
- 目标错误即使方向正确也必须恢复。

## 11. 验证与验收

定向验证至少覆盖：

- reset 后 BTB 全 miss，BHT 为 `01`，取指从 `RESET_PC` 顺序开始。
- 单一条件分支的四状态加减、上下饱和和 MSB 预测规则。
- BTB hit、tag miss、同 index 不同 tag 覆盖。
- 条件分支的 taken/not-taken 双向误判恢复，以及训练后的正确预测。
- `JAL` 恒 taken 预测；`JALR` 目标改变导致的 target mispredict。
- 普通指令携带陈旧 predicted target 时恢复到 `PC+4`。
- stall 时 `PC/instruction/pred_next_pc` 一致保持；redirect 时年轻预测元数据随 valid 一起 kill。
- IDU/EXU 输入 valid=0 而 ready=1 时，预测 payload 不更新；下一条有效指令到达后元数据仍与其 PC/指令同拍捕获。
- EX 反压/多周期 MDU 场景不重复训练。
- EX `r_ex_vld=1` 但 `ex_result_done=0` 或 `i_ex_ma_rdy=0` 时，update/invalidate/recovery 均为 0；真实 EX/MA fire 的提交拍恰好为 1。
- `fence.i` 清空 BTB/BHT 并从 `PC+4` 重新取指。
- 关闭 `BPU_ENABLE` 后功能回归不退化。

公共回归及验收标准统一按 [`rule_ai_acceptance.md`](rule_ai_acceptance.md) 执行，其中 RV32M
ISA/Compliance 已是常驻基线，不作为额外或可选验证。建议增加 SVA：无效 EX 不训练、
训练单脉冲、空泡不改写预测 payload、stall 时预测 payload 稳定、redirect kill 年轻 valid、正确预测不 redirect。

回归前后必须保存或检查生成的 `sim/filelist.f`/编译日志：所有 v11 可编辑 RTL（特别是 `core.sv/ifu.sv/idu.sv/exu.sv/branch_predictor.sv`）必须解析自 `11_rv32im_bpu`，不得出现以 `../10_rv32im/de` 替代 v11 RTL 的情况。`BPU_ENABLE=0/1` 两组都必须使用同一套 v11 源文件。

## 12. 实现顺序与架构风险

推荐顺序：先修正 v11 filelist 路径隔离，再实现并单测 `branch_predictor`；随后接 IF PC 选择和预测 payload，按 v11 的 valid-qualified fire 条件接入 ID/EX 元数据；最后改 EX 解析/redirect 并补定向和公共回归。

主要风险：

- **高：取指地址与同步 ITCM 返回错位。** 必须以当前 `pc_r/o_instr_pc` 所对应的指令生成并携带 `pred_next_pc`，不能把下一请求 PC 的预测元数据配给当前指令。
- **高：仍按 actual taken 无条件 redirect。** 接入后必须改为 next-PC mismatch 才恢复，否则预测正确也会冲刷流水。
- **高：训练重复。** EX 下游反压或 MDU busy 时只能在一次性 EX/MA fire 上更新。
- **高：错误沿用 v10 的 `!i_stall` 门控。** v11 应以 `o_ex_ma_vld && i_ex_ma_rdy` 为提交真值；额外门控会让 BPU 事件与真实 MAU 接收脱钩。
- **高：照抄 v10 payload 写使能。** v10 预实现的预测 payload 仅按 ready 更新，而 v11 的 instruction/PC payload 按 valid && ready && !flush 更新；照抄会破坏空泡/flush 后的元数据对齐。
- **高：回归误编译旧版本。** v11 当前 sim/syn filelist 仍引用 `../10_rv32im`；未先修正并核查编译日志时，PASS 不能证明 v11 实现正确。
- **中：规格与实际宏值漂移。** v10 文档写 16 项、验证实现实际为 4 项；v11 必须用编译时检查/波形确认默认 16 项，任何缩减都需先更新 SPEC 并记录理由。
- **中：组合时序。** `BTB tag compare + BHT read + next-PC mux` 会进入取指地址路径；默认 16 项寄存器阵列应可接受，若时序不足应先减小表或增加前端流水评审，不能私自改变 ITCM 对齐协议。
- **中：`fence.i` 与自修改代码。** 必须 invalidate，且 invalidate 优先于同拍训练。
- **低：BHT alias。** 属于基础预测器预期性能现象，不影响正确性。
