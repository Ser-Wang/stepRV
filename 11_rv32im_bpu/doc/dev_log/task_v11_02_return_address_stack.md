# task_v11_02：返回地址栈（RAS）RTL 实现工单

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-18 01:13
**Current Version**: v2.1
**Status**: RAS Compile-time Switch Scheme Under Discussion (2026-08-23) | Completed (2026-08-18 23:30) | Ready for Execution (2026-08-18 01:13)

**Version Changelog**:
- **v2.1** (2026-08-23): 回退并删除原 v2.1 的性能 A/B 验收内容；讨论将宏改名为 `BPU_HAS_RAS`，并比较 IFU next-PC 单点选择与条件例化两种编译期开关方案，等待确认后再执行。
- **v2.0** (2026-08-18 23:30): 完成双完整栈 RTL、IF/EX 集成、独立定向 DV、DC 前端检查和公共回归，工单功能验收完成。
- **v1.2** (2026-08-18 22:44): 批准双完整栈首版实现，模块改名为 `ras_dual_full_stack`，并明确未来 C906 风格模块须保持同接口以支持直接替换实验。
- **v1.1** (2026-08-18 22:32): 将易与 specification/退休混淆的 spec/commit state 改名为“前端预测栈/后端确认栈”，并增加逐拍维护示例及相应接口命名。
- **v1.0** (2026-08-18 01:13): 初版 RAS 实现工单，明确接口、修改范围、状态更新次序、风险与验收要求。

---

功能依据：[`dev_spec_return_address_stack.md`](dev_spec_return_address_stack.md)

结构决策：[`decision_log_ras.md`](decision_log_ras.md)

参考资料：

- [`log_dev_v11.md`](log_dev_v11.md)：当前 BTB+BHT 完成状态与回归基线。
- [C906 分支预测分析](../../../../openc906/my_docs/C906_Branch_Prediction.md)：C906 分支预测分析。实际实现时还应对照 `aq_ifu_ras.v`、`aq_ifu_pre_decd.v`、`aq_ifu_pred.v` 和 `aq_iu_bju.v`。
- [`rule_ai_acceptance.md`](rule_ai_acceptance.md)：本版本公共验收要求。

## 1. 任务目标与边界

在 v11 已完成的 BTB+BHT 基础上实现默认 4 项 RAS。返回预测必须在 IF 当前指令被接受时即可参与 next-PC 选择；call/return 对前端预测栈的更新必须能在错路径 redirect 后精确撤销；EX 侧确认必须绑定现有唯一 `ex_commit_fire`。

允许修改 RAS/BPU 相关 RTL、配置、filelist、DV 和必要注释。本任务不改变 core 对外取指/访存协议，不加入 RVC、通用 checkpoint 队列、PMU/CSR、操作系统上下文切换支持，也不重构现有 redirect 仲裁或 BTB/BHT 算法。

## 2. 当前实现约束与设计决策

### 2.1 必须保持的现状

- `core.sv` 中的 `i_if_instr` 与 IFU 的 `pc_r/o_instr_pc` 构成送入 IDU 的同一 IF payload；当前 `ifu.sv` 尚无 instruction 输入，接入 RAS 时需要补充。`if_accept` 是推进预测 PC 的唯一普通事件。
- `pred_next_pc` 已作为 32-bit payload 经 IDU 传到 EXU；RAS 不需要新增 `ras_hit` 等流水元数据才能判断正确性。
- `exu.sv` 已以 `ex_commit_fire = o_ex_ma_vld && i_ex_ma_rdy` 统一产生 BTB/BHT update、invalidate 和 prediction recovery。
- redirect 当拍 `o_if_id_vld` 被压低，`ctrl_hazard` 清 IF/ID 与 ID/EX 年轻指令。
- 当前 EXU 已保存 `rd`、`rs1` index，BRU decode bus 已区分 `JAL/JALR`，无需把完整 instruction 再传入 EXU。

### 2.2 采用的 RAS 结构

本工单已批准新增 `ras_dual_full_stack.sv`，module 名为 `ras_dual_full_stack`，内部维护两套完整状态：

```text
pred_entries[0:DEPTH-1]     + pred_count      // 前端预测栈
resolved_entries[0:DEPTH-1] + resolved_count  // 后端确认栈
```

- **前端预测栈（prediction state）**：IFU 实际用于预测 return target 的栈；在 call/return 通过 `if_accept` 进入流水线时立即更新，因此包含尚未到 EX 的年轻指令，也可能暂时包含错路径指令。
- **后端确认栈（resolved state）**：只记录已经在 EX 解析、确认无异常并通过 `ex_commit_fire` 的 call/return；它不直接预测当前 return，而是 redirect 时重建前端预测栈的可靠基线。

这里不是让同一条指令连续修改同一个栈两次，而是让它在不同流水阶段分别推进两份副本。以下时序包含 call A、A 后面的 branch C，以及 C 后面的错路径 call B：

| 时刻 | 前端预测栈 | 后端确认栈 | 含义 |
|---|---|---|---|
| IF 接受 call A | push `A+4` | 不变 | 后续年轻 return 已能使用 A 的返回地址 |
| IF 接受 branch C | 不变 | 不变 | C 尚未到 EX，不产生 RAS 动作 |
| EX 确认 A；同拍 IF 接受 B | push `B+4` | push `A+4` | A 成为恢复基线；B 暂时进入预测栈 |
| EX 发现 C 误判并 redirect | 复制后端确认栈，仅保留 `A+4` | 保持 `A+4` | C 后面的错路径 B 被撤销 |

若发生 redirect 的正是 call A 自身，则本拍先把 A 更新到“下一后端确认栈”，再用该结果恢复前端预测栈，所以 A 保留、A 后面的年轻操作被撤销。

`entry[0]` 固定为 top，push/pop 使用移位实现。深度仅 4，优先保证状态和恢复语义清晰，不使用 C906 的共享 entry + 双 one-hot pointer 结构。双完整状态可避免错路径 push 覆盖环形 entry 后仅恢复指针仍读到污染内容的问题，增加的默认存储量为 8 × 32 bit 加两个小计数器。

该命名是实验边界的一部分。未来 C906 风格实现建议命名为 `ras_shared_entry_dual_pointer.sv` / `ras_shared_entry_dual_pointer`；两个实现必须使用相同参数和端口语义。IFU 不得依赖任一实现的内部数组、count 或 pointer，后续实验只需替换实例 module 与对应 filelist 项，不改 IF/EX 业务逻辑。

实现必须先组合得到 `resolved_next`，再按以下时序优先级更新：

```text
reset
  -> 前端预测栈、后端确认栈均为空
otherwise
  -> 后端确认栈接收本拍有效 resolve action，形成 resolved_next
  -> if recover，前端预测栈 := resolved_next
  -> else if pred_update，前端预测栈执行本拍 IF pop/push
```

该次序是同拍“当前 call/return 确认并因目标误判 redirect”能够恢复到包含当前指令效果的后端确认状态的关键要求。

## 3. 接口设计

### 3.1 `ras_dual_full_stack.sv` 端口

端口名称可按最终代码微调，但事件语义不得合并或弱化：

```systemverilog
module ras_dual_full_stack #(
    parameter integer ENTRIES = `BPU_RAS_ENTRIES
)(
    input  wire        clk,
    input  wire        rst_n,

    output wire        o_top_vld,
    output wire [31:0] o_top_addr,

    input  wire        i_pred_update_fire,
    input  wire        i_pred_pop,
    input  wire        i_pred_push,
    input  wire [31:0] i_pred_push_addr,

    input  wire        i_resolve_fire,
    input  wire        i_resolve_pop,
    input  wire        i_resolve_push,
    input  wire [31:0] i_resolve_push_addr,

    input  wire        i_recover
);
```

约束：

- `i_pred_update_fire` 只表示一个已接受的 IF payload 确实带有 RAS 动作；pop/push 可同时为 1。
- `i_resolve_fire` 只表示一个无异常、已移交的 call/return 确实带有 RAS 动作；不得直接等同于所有 `ex_commit_fire`。
- `i_recover` 使用现有已提交 redirect 事件；它可与 `i_resolve_fire` 同拍。
- `o_top_vld=0` 时 `o_top_addr` 可为 0，但不得参与预测。
- `BPU_ENABLE=0` 或 `BPU_RAS_ENABLE=0` 时不得产生预测命中或改变两份状态。
- 增加 elaboration 检查，拒绝 `ENTRIES < 2`；无需限制为 2 的幂。

### 3.2 IF 侧预译码与预测接口

`ifu.sv` 新增与 `pc_r` 对齐的指令输入，例如 `i_instr_if`，由 `core.sv` 连接现有 `i_if_instr`。不得使用下一请求地址 `o_fetch_pc/if_req_pc` 对指令分类。

IF 预译码应集中定义并复用以下条件：

```text
is_jal       = instr[6:0] == 7'b1101111
is_jalr      = instr[6:0] == 7'b1100111 && instr[14:12] == 3'b000
rd_is_link   = instr[11:7]  inside {x1, x5}
rs1_is_link  = instr[19:15] inside {x1, x5}

ras_push = (is_jal && rd_is_link)
        || (is_jalr && rd_is_link)
ras_pop  = is_jalr && rs1_is_link
        && (!rd_is_link || instr[11:7] != instr[19:15])
```

由此自然得到 same-register `JALR` 只 push、different-link-register `JALR` 同时 pop+push。避免使用可能降低旧综合器兼容性的复杂 `inside` 写法时，可展开为显式比较。

投机事件：

```text
ras_pred_update_fire = if_accept && (ras_pop || ras_push)
ras_pred_push_addr = pc_r + 4
```

预测仲裁：

```text
ras_pred_hit = effective_ras_enable && is_jalr && ras_pop && ras_top_vld
o_pred_next_pc_if = ras_pred_hit ? ras_top_addr : bp_pred_next_pc
```

需把 `branch_predictor.o_pred_next_pc` 先接到 IFU 内部 wire，不能继续由其直接驱动 `o_pred_next_pc_if`。RAS 使用动作前的 top 形成本条 return 的目标，在时钟沿随 `if_accept` 完成 pop。

### 3.3 EX 侧确认接口

在 `exu.sv` 用已寄存且与当前 EX payload 对齐的信号生成动作：

- `bru_is_jump` 以及 BRU bus 中的 `JAL/JALR` 类型。
- `r_wb_rd_idx_exu` 作为 `rd`。
- `r_rs1idx_exu` 作为 `rs1`。
- `sequential_next_pc = r_pc_exu + 4` 作为 push 地址。

EX 分类公式必须与 IF 公式一致。建议新增局部 `ras_rd_is_link/ras_rs1_is_link/ras_resolve_pop_raw/ras_resolve_push_raw`，避免把 RAS hint 逻辑放入 `exu_bru.sv`；BRU 继续只负责控制流类型、方向和实际目标。

```text
ras_resolve_fire = ex_commit_fire
                 && !o_exc_req
                 && !o_trap_ret_req
                 && (ras_resolve_pop_raw || ras_resolve_push_raw)
```

异常的 `JAL/JALR` 不得改变后端确认栈。当前 redirect 输出可直接作为 IFU/RAS 的 recover 事件，因为其已经被 `ex_commit_fire` 限定。普通 call/return 即使预测正确、不发生 redirect，也必须更新后端确认栈。

实现前需核对 IDU 的 `JALR` 合法编码条件。当前 `instr_jalr` 只按 opcode 识别，缺少 `funct3==000`；本任务应将 IDU 和 IF RAS 预译码统一为合法 JALR 条件，避免同一指令在 IF 与 EX 被分类成不同动作。若项目决定暂不补非法指令异常，至少也不能把保留的 JALR `funct3` 编码用于 RAS hint。

## 4. 预期修改范围

| 文件 | 修改要求 |
|---|---|
| `de/core/ras_dual_full_stack.sv` | 新增；实现前端预测栈/后端确认栈、top、push/pop/pop+push、resolve+recover 次序与参数检查 |
| `de/defines/config.v` | 增加可覆盖的 `BPU_RAS_ENABLE=1`、`BPU_RAS_ENTRIES=4` |
| `de/core/ifu.sv` | 接收当前 IF instruction，完成 hint 预译码、投机 fire、RAS 实例化与预测优先级仲裁 |
| `de/core/idu.sv` | 将 `JALR` decode 补齐 `funct3==000`，保证 IF/EX 分类一致；不增加 RAS payload |
| `de/core/exu.sv` | 根据现有 EX payload 生成确认 pop/push/address；确认事件绑定 `ex_commit_fire` 且异常不更新 |
| `de/core/core.sv` | 连接 `i_if_instr` 与 RAS resolve 信号；不承载 RAS 状态或分类逻辑 |
| `filelists/filelist_rtl.f` | 在 `ifu.sv` 前加入新 RAS RTL，保持 sim/syn 共用 filelist 正确 |
| `filelists/filelist_sim_sram.f` | 在 SRAM 仿真 filelist 中加入同一 RAS RTL |
| `dv/Makefile.bpu` | 增加 RAS 单元/前端定向目标，并保持所有产物位于受保护的 `dv/bpu_build` |
| `dv/tb_ras_dual_full_stack.sv` | 新增双完整栈 RAS 状态与恢复单测 |
| `dv/tb_bpu_frontend.sv` 或新前端 TB | 增加 instruction 对齐、预测仲裁、IF stall/redirect 测试 |
| `dv/sva_bpu_*.sv` | 增加 pred-update/resolve/recover exactly-once 与预测选择断言 |

`branch_predictor.sv` 原则上无需改变表结构和训练算法。`ctrl_hazard.sv`、外部 ITCM 协议、MAU/WBU 不应修改；如实现需要改变这些模块的行为，应停止并重新评估范围。

## 5. 实现步骤

1. 增加配置和 `ras_dual_full_stack.sv`，先完成独立单测，特别验证同拍 resolve+recover。
2. 修正/统一 `JALR` 合法编码判定；在 IFU 接入当前 instruction，生成纯组合 hint。
3. 将 branch predictor 输出改接内部 `bp_pred_next_pc`，增加 RAS top 优先 mux；保持 redirect > accepted prediction > hold 的 PC 选择不变。
4. 用 `if_accept` 门控前端预测栈更新，验证反压或 redirect 不会重复 push/pop。
5. 在 EXU 用当前 `rd/rs1` 与 jump 类型生成后端确认动作；用现有 redirect 驱动 recover。
6. 连接 core 和 filelist，分别以 RAS enable/disable 编译，检查端口与层次绑定。
7. 扩展定向 TB/SVA，运行启停配置定向测试、公共回归和 DC 前端检查。

## 6. 潜在风险与处理要求

### 6.1 同拍确认与恢复

最危险边界是 call/return 自身目标预测错误：EX 同拍既确认 RAS 动作又 redirect。若把前端预测栈恢复为旧的后端确认栈，会丢失当前刚确认的动作。必须用 `resolved_next` 恢复，并用定向测试覆盖 call mispredict、return target mispredict 和 pop+push mispredict。

### 6.2 错路径 entry 内容污染

只复制 C906 的“双指针、共享 entry”会允许错路径 push 覆盖尚属于后端确认栈的 entry。当前工单明确使用两套完整栈内容；若为面积改用共享 entry，必须先证明任意 overflow、嵌套和 recovery 下内容可恢复，并修订 SPEC/task，不能只恢复 count/pointer。

### 6.3 IF 对齐与重复更新

RAS predecode 必须读取与 `pc_r` 同拍的 `i_if_instr`。仅看到 call/return 组合信号不能更新；必须同时有 `if_accept`。特别检查 IDU 反压、load-use stall、redirect 当拍和 reset 后第一条有效指令。

### 6.4 预测优先级与空栈

非 return 不得读取 RAS 改流；空栈 return 不得使用无效 entry；RAS return 必须覆盖 BTB 的陈旧/alias target。空栈 fallback 使用原 BTB/BHT，功能正确性仍由 EX next-PC 比较保证。

### 6.5 深度溢出与恢复精度

满栈 push 丢弃最深项只允许降低超深嵌套返回的预测率，不能改变架构结果。测试需区分正常深度内精确恢复与超深度后的预期性能退化。

### 6.6 组合时序

新增路径为同步 ITCM 输出 → IF 轻量预译码 → RAS/BTB mux → `if_req_pc`。预译码只做 opcode/funct3/寄存器号比较，RAS top 为寄存器组合读。不得为了消除时序风险自行增加流水级或改变 ITCM 一拍对齐；若 DC 显示该路径成为瓶颈，记录数据后另立优化任务。

### 6.7 trap 与 `fence.i`

`fence.i` 只清 BTB/BHT，不清后端确认栈；exception/`mret` 也保留已确认调用上下文，但都会通过 redirect 撤销前端预测栈中的年轻操作。测试必须覆盖函数内部 `fence.i` 后 return，以及 trap handler 内部嵌套 call/return 后 `mret`。

## 7. 定向验证要求

### 7.1 模块级 RAS

- reset 后 `top_vld=0`；空栈 pop 保持为空。
- 单次和多次 push/pop 的 top、顺序与 count 正确。
- 满栈 push 丢弃最深项；连续 pop 到空后不下溢。
- pop+push：非空替换 top，空栈等价 push。
- 前端预测更新不改变后端确认栈；后端确认更新在无 redirect 时不应覆盖前端预测栈。
- recover 精确复制 `resolved_next` 的内容与 count，而不仅是 top。
- 同拍 resolve push + recover、resolve pop + recover、resolve pop+push + recover 均得到包含本拍确认动作的状态。
- disabled 配置不更新、不命中。

### 7.2 IF/EX 集成

- `JAL x1/x5` push；`JAL x0` 无动作。
- canonical `ret` 以及以 `x5` 为 base 的 return pop，并在非空时无需 BTB hit即可使用 RAS top。
- `JALR` 的五种 hint 组合全部覆盖，尤其 `rd==rs1` 只 push、`rd!=rs1` pop+push。
- `JALR funct3!=000` 不得产生 RAS 动作。
- RAS target 与 BTB target 冲突时选择 RAS；RAS 空时回退 BTB/BHT。
- IF 无效、IDU 反压、stall 时 state 稳定；解除阻塞后只更新一次。
- EX/MA 反压期间后端确认栈稳定，fire 后只更新一次。
- 错路径 call、return、pop+push 在 branch mispredict redirect 后被撤销。
- 当前 call/return 自身 prediction recovery 后保留其已确认动作。
- 目标未对齐异常不确认 RAS 动作，恢复后前端预测栈与异常前的后端确认栈一致。
- `fence.i` 后后端确认栈仍能恢复出可预测外层 return 的前端状态；exception/handler call/return/`mret` 不破坏被中断上下文。
- 嵌套调用和递归在深度不超过 4 时，训练后 return 的 `pred_next_pc_ex == actual_next_pc`。

建议增加或扩充 SVA：

```text
ras_pred_update_fire |-> if_accept && (pred_pop || pred_push)
ras_resolve_fire     |-> ex_commit_fire && !exception && (resolve_pop || resolve_push)
!if_accept           |=> 前端预测栈不因 IF hint 单独变化
recover              |=> 前端预测栈 == $past(resolved_next)
ras_pred_hit        |-> ras_top_vld && is_jalr && pop_hint
ras_pred_hit        |-> o_pred_next_pc_if == ras_top_addr
ras_disabled        |-> !ras_pred_hit
```

对内部数组做 SVA 若导致参数化绑定过度复杂，可在模块 TB 中逐项检查；不能因此省略 full-state recovery 验证。

## 8. 公共回归与交付判定

按 [`rule_ai_acceptance.md`](rule_ai_acceptance.md) 在 `work/my-RISCV-Projs/sim` 执行：

```text
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32i DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../11_rv32im_bpu
```

要求 ISA `rv32ui` 仅允许既有 `ma_data` FAIL、`rv32um` 全部 PASS；Compliance 四组全部 PASS；不得新增仿真或 SVA 错误。公共回归在默认 RAS 开启配置执行；关闭 RAS 和关闭整个 BPU 只要求编译及功能定向测试，不要求性能 A/B 对比或重复公共回归。

另执行：

```text
cd work/my-RISCV-Projs/11_rv32im_bpu/dv
make -f Makefile.bpu <新增的RAS目标>

cd work/my-RISCV-Projs/syn
make check DESIGN_NAME=11_rv32im_bpu
```

交付记录必须包含：

- 修改文件、最终端口和配置默认值。
- RAS 三种配置模式的编译/定向结果：BPU off、BPU on/RAS off、BPU on/RAS on。
- full-state recovery 与同拍 resolve+recover 的测试证据。
- 公共回归和 DC `make check` 结果；若未跑完整综合需明确记录。
- 实际编译日志/filelist 路径来自 `11_rv32im_bpu` 的证据。
- 已知性能退化（如超过 4 层后的 RAS overflow）、未完成项及任何偏离 SPEC 的说明。

完成后按仓库规范更新本工单 `Status`（保留完整历史），补充完成记录，并在 [`log_dev_v11.md`](log_dev_v11.md) 顶部增加简短的逆序开发日志条目。

## 9. 实施与验收记录（2026-08-18）

### 9.1 RTL 与接口

- 新增 `de/core/ras_dual_full_stack.sv`；默认 `BPU_RAS_ENTRIES=4`，同时保存 4×32-bit 前端预测栈和 4×32-bit 后端确认栈。配置默认 `BPU_RAS_ENABLE=1`，并受总开关 `BPU_ENABLE` 共同控制。
- 最终模块端口沿用第 3.1 节定义的 `i_pred_*`、`i_resolve_*`、`i_recover` 和 `o_top_*` 接口，未向 IF/ID、ID/EX 增加 RAS 元数据。
- IFU 用与 `pc_r` 对齐的 `i_instr_if` 做合法 JAL/JALR 和 x1/x5 hint 识别；更新绑定 `if_accept`，预测优先级为 RAS top 高于 BTB/BHT，空栈自动回退原预测器。
- EXU 输出 `o_ras_resolve_fire/pop/push/push_addr`；确认 fire 绑定 `ex_commit_fire` 且屏蔽 exception/`mret`。redirect 恢复采用本拍 `resolved_next` 的完整 entries 和 count。
- IDU 的 JALR 判定补入 `funct3==000`。两个 RTL/simulation filelist 均已加入新模块；VCS 全设计编译确认源文件来自 `11_rv32im_bpu`。

### 9.2 独立 DV 结果

验证由与 RTL 实现不同的 agent 完成；`make -f Makefile.bpu all` 全部 PASS：

- 三种配置均通过模块级及 IFU 级定向测试：RAS on、BPU on/RAS off、BPU off。
- 模块级覆盖空栈、overflow、push/pop/pop+push、前端/确认状态分离、full-state recovery，以及 resolve push/pop/pop+push 与 recover 同拍。
- IFU 级覆盖 IF accept exactly-once、stall、RAS 高于 BTB、空栈 fallback、x1/x5、JALR 五类 hint、非法 funct3 和 resolve+redirect；SVA cover 观察到 push 4、pop 3、pop+push 1、RAS hit 5。
- EXU RAS resolve SVA 编译通过；公共回归同时带入 `sva_bpu_idu.sv`、`sva_bpu_exu.sv` 和 `sva_ras_ifu.sv`，无新增 `[BPU SVA]` 失败。

### 9.3 综合与公共回归

- `make check DESIGN_NAME=11_rv32im_bpu` PASS：analyze/elaborate/link/check_timing 完成；DC 识别 `pred_entries`、`resolved_entries` 各 128 bit，两个 count 各 3 bit。未执行完整 compile/面积时序报告。
- ISA：`rv32ui` 41/42 PASS（仅允许的既有 `ma_data` FAIL），`rv32um` 8/8 PASS。
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS。

### 9.4 已知边界

- 默认深度超过 4 时，满栈 push 会丢弃最深项，只影响预测率，不影响架构正确性。共享 entry + 双 pointer 的面积/时序对照仍按 `decision_log_ras.md` 留作后续实验。

## 10. v2.1：RAS 编译期开关方案讨论（2026-08-23）

### 10.1 当前问题

v2.0 在 `ras_dual_full_stack.sv`、`ifu.sv` 和 `exu.sv` 中分别计算
`` `BPU_ENABLE && `BPU_RAS_ENABLE ``。这使配置策略进入 RAS 状态机和预测数据路径，形成重复门控；从模块替换实验角度看，`ras_dual_full_stack` 也不再是只描述栈机制的纯模块。

两个配置宏当前始终在 `config.v` 中定义为数值 0 或 1，因此不能直接使用 `` `ifdef BPU_RAS_ENABLE ``：当宏被定义为 0 时，`ifdef` 条件仍然成立。除非把整个工程改成“是否定义即是否启用”的宏约定，否则直接改用 `ifdef` 会产生错误配置。

### 10.2 共同原则与宏命名

开关宏建议由 `BPU_RAS_ENABLE` 改名为 `BPU_HAS_RAS`。`ENABLE` 容易让人理解为模块内部需要持续门控的运行时使能；`HAS_RAS` 表示当前编译配置是否让 BPU 的 next-PC 机制具备 RAS 能力，更符合本次“配置与机制分离”的目标。

`BPU_HAS_RAS` 仍建议保持数值 0/1 宏，以兼容现有 `+define+BPU_HAS_RAS=0` 构建方式。不能直接写 `` `ifdef BPU_HAS_RAS ``，因为宏取值为 0 时仍然属于已定义。需要使用常量 `generate if`，或者让以该常量为条件的组合选择在 elaboration/综合期折叠。

无论最终选择哪种 IFU 方案，都采用以下共同职责：

- `ras_dual_full_stack.sv` 删除 `ras_enable` 及所有配置判断，只根据输入事件维护栈；`BPU_RAS_ENTRIES` 只作为结构参数，不是机制开关。
- `exu.sv` 始终产生与配置无关的已确认 call/return 事件，删除 `ras_effective_enable`；EXU 只负责指令分类，不负责 feature 配置。
- `core.sv` 的事件连线和 IFU/EXU 端口保持稳定，避免配置改变接口，也便于以后直接替换 `ras_shared_entry_dual_pointer`。
- `BPU_ENABLE` 与 `BPU_HAS_RAS` 的组合只在 IFU 一处决定 RAS 预测结果能否进入 next-PC，不再散布到 RAS 和 EXU。

### 10.3 方案 A：保持 RAS 例化，仅在 IFU next-PC 仲裁处单点选择

这是当前更精简、建议优先采用的方案。`ras_dual_full_stack` 始终出现在 IFU 源代码层次中并正常接收预测/确认事件，但是否采用其预测结果只在最终 next-PC 仲裁处决定：

```systemverilog
localparam RAS_PREDICT_ACTIVE =
    (`BPU_ENABLE != 0) && (`BPU_HAS_RAS != 0);

wire ras_pred_hit_raw = o_if_id_vld && ras_pred_pop && ras_top_vld;

generate
    if (RAS_PREDICT_ACTIVE) begin : g_use_ras_prediction
        assign ras_pred_hit      = ras_pred_hit_raw;
        assign o_pred_next_pc_if = ras_pred_hit_raw
                                     ? ras_top_addr : bp_pred_next_pc;
    end
    else begin : g_ignore_ras_prediction
        assign ras_pred_hit      = 1'b0;
        assign o_pred_next_pc_if = bp_pred_next_pc;
    end
endgenerate
```

该方案的含义是“关闭 RAS 对架构可见预测结果的影响”，而不是“RTL 仿真层次中不存在 RAS”：

- `BPU_HAS_RAS=0` 时 next-PC 始终不采用 `ras_top_addr`，功能上完全回退 BTB/BHT。
- 关闭分支是 elaboration constant，不在启用配置的预测关键路径加入运行时 enable 与门。
- RTL 仿真中 RAS 实例和内部状态仍存在并可能翻转；因此 disabled 验收不再要求内部栈静止，只要求 `ras_pred_hit=0` 且 next-PC 不使用 RAS。
- 完整综合通常会因为 RAS 输出在关闭配置中无消费者而裁掉整个实例，但这依赖综合优化，不能仅凭 RTL 层次或 `make check` 的 elaboration 结果宣称面积已移除；如关心面积，需检查 compile 后网表/寄存器报告。

该方案只在 IFU 的预测出口出现一次 feature policy，代码改动最少，且未来替换不同 RAS 实现时无需改开关位置。

### 10.4 方案 B：在 IFU 例化边界条件例化

另一方案是在 `generate if` 的 enabled 分支例化 RAS，disabled 分支把 `ras_top_vld/addr` 绑为无效值。其优势是关闭配置在 elaboration 后就没有 RAS 实例，仿真不产生内部翻转，也不依赖综合器删除无消费者逻辑；代价是例化结构和 disabled stub 更复杂，层次路径也随配置变化。

若当前目标主要是让 feature 开关尽量少侵入 RTL，而不是保证关闭配置在 elaboration 层次立即消失，则方案 A 更合适。若后续需要严格的配置化面积构建或低功耗仿真，再转为方案 B，不影响纯 RAS 模块接口。

### 10.5 不建议的方案

- 不建议直接把数值宏换成 `ifdef`，因为 `BPU_HAS_RAS=0` 仍属于“已定义”。
- 不建议在 core、IFU 和 EXU 多处用条件编译删除端口或逻辑，这会产生多套接口组合，增加集成和模块替换成本。
- 不建议保留 RAS 内部 enable 输入或配置判断；它仍会把 feature 管理混入机制模块，并可能在状态机或预测路径留下额外门控。

### 10.6 v2.2 执行边界

方案确认后，v2.2 将宏改名为 `BPU_HAS_RAS`，修改 `ras_dual_full_stack.sv`、`ifu.sv`、`exu.sv` 及相应 DV/SVA。若采用当前建议的方案 A，验收 enabled 配置功能不变，`BPU_HAS_RAS=0` 或 `BPU_ENABLE=0` 时 `ras_pred_hit` 恒为 0、next-PC 完全回退原预测器；不再把 RTL 仿真中内部栈是否翻转作为 disabled 验收条件。随后执行 DC 前端检查和公共回归；若需要证明关闭配置面积已裁剪，应追加完整综合后的网表/寄存器检查，不能只使用 elaboration 结果。
