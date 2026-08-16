# task_v11_01：基础动态分支预测器 RTL 实现工单

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-07-10 00:00
**Current Version**: v2.0
**Status**: Completed (2026-08-16 23:30) | Ready for Execution (2026-08-16 22:41) | ready-for-rtl (2026-07-10 00:00)

**Version Changelog**:
- **v2.0** (2026-08-16 23:30): 完成 BPU RTL、v11 握手适配、独立 DV/SVA、双模式公共回归及 DC 前端检查，并记录交付结果。
- **v1.1** (2026-08-16 23:15): 按 v11 valid/ready 与流水寄存器语义细化实现和验收要求，补充 filelist 隔离、本地 DV 与安全清理约束，并明确复用 `10_rv32im_copy` 已有 BPU RTL/DV 时必须适配不同 feature 基线。
- **v1.0** (2026-07-10 00:00): 初版动态分支预测 RTL 实现工单。

---

功能依据：[`dev_spec_dynamic_branch_predictor.md`](dev_spec_dynamic_branch_predictor.md)

## 1. 任务目标

按功能 SPEC 为当前 RV32IM 5 级流水实现最基础的动态分支预测：直接映射 BTB、独立 BHT、2-bit 饱和计数器，在 EX 解析/训练并复用现有 redirect/flush 恢复。

本工单允许修改 RTL、filelist 和 DV；不得改变 core 对外取指/访存协议，不实现 RAS、全局历史、gshare、I-cache 或多发射。鼓励优先参考和复用 `10_rv32im_copy` 中已经实现过一次的 BPU RTL、定向 TB、验证辅助代码及构建经验，不必重复造轮子。`10_rv32im_copy` 与 `11_rv32im_bpu` 虽都从 `10_rv32im` 复制而来，但复制时的 feature 状态不同，且 v11 后续调整了 valid/ready 与流水寄存器更新行为；因此复用前必须逐项审查接口、时序、写使能和验证假设并完成适配，禁止未经审查整文件覆盖，最终正确性与代码质量不得低于独立实现。

## 2. 预期文件范围

| 文件 | 要求 |
|---|---|
| `de/core/branch_predictor.sv` | 新增；拥有 BTB/BHT、组合查表、同步训练与 invalidate |
| `de/defines/config.v` | 增加 `BPU_ENABLE/BPU_BTB_ENTRIES/BPU_BHT_ENTRIES/BPU_BHT_INIT` 默认配置 |
| `de/core/ifu.sv` | 实例化预测器；PC mux 接入 `pred_next_pc`；接收 EX 训练/失效反馈；输出随指令对齐的预测 next-PC |
| `de/core/idu.sv` | 将 `pred_next_pc` 加入 IF/ID payload；仅在 `i_if_id_vld && o_if_id_rdy && !i_flush` 时更新 |
| `de/core/exu_bru.sv` | 明确输出真实 control-flow 类型、taken 和 target，或提供 EXU 生成这些信息所需信号 |
| `de/core/exu.sv` | 保存预测 next-PC；仅在有效 ID/EX 接收事件更新；在唯一 EX/MA valid-ready fire 上训练/失效/恢复；修改 redirect 仲裁 |
| `de/core/core.sv` | 连接 IFU、IDU、EXU 的预测 payload 与训练反馈，不放入表或计数器逻辑 |
| `de/core/ctrl_hazard.sv` | 原则上复用现有 redirect flush；仅在信号语义/注释确有需要时改动 |
| `filelists/filelist_rtl.f` | 加入 `core/branch_predictor.sv`，顺序满足依赖 |
| `filelists/filelist_sim_sram.f`、`filelist_syn_sram.f` | 先把遗留的 `../10_rv32im` 引用切换为 `../11_rv32im_bpu`，确保仿真/综合确实编译本版本 |
| `dv/*` | 所有新增 BPU TB、SVA、验证辅助文件及必要的新验证说明 Markdown 均放在 `11_rv32im_bpu/dv`；优先移植和适配 `10_rv32im_copy` 已有 BPU 验证代码，避免重复实现或复制整套 SoC TB |

若实现需要改 `soc_top/soc_bus/mem_itcm` 外部协议，应停止并汇报；该变化超出本任务。

新增定向验证若产生独立构建产物，必须提供可用的 `make clean` 逻辑。执行 clean 前必须先解析并检查目标路径确实位于本验证目录、待删内容只包含明确列出的生成物且不包含 RTL/TB/Markdown/Makefile 等源文件；禁止对未解析变量、宽泛 glob、仓库根目录或版本目录执行递归删除。

## 3. 必须实现的行为

### 3.1 Predictor

- BTB 直接映射，每项为 `valid/tag/target/is_conditional`；默认 16 项。
- BHT 独立索引，每项固定 2 bit；默认 16 项，reset 为 `01`。
- BTB hit 且为 `JAL/JALR` 时预测 taken；条件分支用 BHT counter MSB。
- BTB miss/tag miss 均预测 `PC+4`，不得只因 BHT taken 就跳转。
- 2-bit counter 为 `00 <-> 01 <-> 10 <-> 11` 饱和更新。
- 同拍查读和训练同一项时读旧值，不做 bypass。
- `fence.i` 清全部 BTB valid，并把 BHT 恢复初值；优先级为 reset > invalidate > update。
- `BPU_ENABLE=0` 时恒输出 `PC+4` 且不训练，便于 A/B 回归。
- 默认深度按 SPEC 为 BTB/BHT 各 16 项。不得照抄 v10 预实现中实际使用的 4 项配置；若确需缩减，必须先修订 SPEC。

### 3.2 IF/ID/EX 对齐

- IFU 预测器查询地址必须是与 `i_if_instr/o_instr_pc` 对齐的 `pc_r`，不得使用已选择下一请求地址的 `if_req_pc/o_fetch_pc`；仅在现有 `if_accept` 时以预测结果推进 PC。
- IDU 的预测 payload 仅在 `i_if_id_vld && o_if_id_rdy && !i_flush` 时更新，EXU 的预测 payload 仅在 `i_id_ex_vld && o_id_ex_rdy && !i_flush` 时更新，必须与 v11 当前 instruction/PC payload 写使能完全相同。
- 输入 valid=0 而 ready=1 时只允许 valid 记录空泡，不得改写预测 payload；not-ready 时保持；flush 时清 valid 即可。
- redirect 优先于预测 next-PC，redirect 当拍旧路径 `if_id_vld` 不得被接收。
- 不得改变现有同步 ITCM 一拍读接口。

### 3.3 解析、训练和恢复

- B-type：输出真实 taken、`PC+imm` target；`actual_next_pc = taken ? target : PC+4`。
- `JAL/JALR`：真实 taken 恒为 1；JALR target 保持 bit[0] 清零规则。
- 其他正常指令：`actual_next_pc = PC+4`，用于捕获陈旧 BTB 对普通指令的误命中。
- `mispredict = pred_next_pc != actual_next_pc`，不能只比较 taken 位。
- 所有正常解析的 B-type、`JAL/JALR` 更新 BTB；仅 B-type 更新 BHT。not-taken B-type 也写入可计算的 branch target。
- 统一定义 `ex_commit_fire = o_ex_ma_vld && i_ex_ma_rdy = r_ex_vld && ex_result_done && i_ex_ma_rdy`。更新、invalidate 和 prediction recovery 必须全部由该唯一事件派生；不得分别使用略有差异的门控条件。
- 不得照抄 v10 预实现额外拼接的 `!i_stall`：v11 的 `o_ex_ma_vld` 未受该信号门控，BPU 事件必须与真实 EX/MA 握手一致。若未来启用 `STALL_ID_EX`，应先整体修正 EX/MA 握手语义。
- EX 下游反压或 MDU busy 时 update/invalidate/recovery 均不得触发；解除阻塞并真实移交 MAU 的一拍恰好触发一次。
- 控制流目标未对齐并产生异常时不训练。
- 普通 branch/jump 只有 mispredict 才 redirect；正确预测 taken 不得再次 flush。
- redirect 优先级必须为 exception > `mret` > `fence.i` > prediction recovery，恢复地址按 SPEC。
- 继续由 `ctrl_hazard` kill IF/ID、ID/EX 的年轻错路径 valid；不得让错路径产生 RF/memory/CSR 副作用。

## 4. 推荐实施顺序

1. 先修正 `filelist_sim_sram.f/filelist_syn_sram.f` 的 v10 遗留路径，并从生成 filelist 或编译日志确认 v11 源码隔离。
2. 新增配置和 `branch_predictor.sv`，先做模块级查表、tag、counter、替换、invalidate 检查，并确认默认阵列实际为 16 项。
3. 在 IFU 以 `pc_r` 查询预测器并接入 PC mux，保持 `o_fetch_req/o_fetch_pc/i_if_instr` 时序不变。
4. 把 `pred_next_pc` 依次加入 IF/ID、ID/EX payload，严格复用 v11 的 valid && ready && !flush 写使能，先验证空泡/stall/flush 稳定性。
5. 扩充 BRU/EXU 的解析结果；先定义唯一 `ex_commit_fire`，再生成 `actual_next_pc`、训练脉冲与预测恢复请求。
6. 替换现有“actual taken 即 redirect”语义，并完成 exception/`mret`/`fence.i` 优先级仲裁。
7. 在 `core.sv` 连线并更新全部 filelist；检查端口均遵守项目 `i_/o_` 前缀。
8. 增加定向 DV/SVA，先跑关闭预测基线，再跑开启预测与公共回归；两组均核查实际解析的是 v11 RTL。

## 5. 定向验证清单

- reset：无 BTB hit、BHT=`01`、首条 PC/指令/预测元数据对齐。
- counter：四状态 taken/not-taken 转移、`00/11` 饱和。
- BTB：hit、tag miss、同 index 不同 tag 替换、条件/无条件类型。
- branch：NT->T、T->NT、训练后正确 taken/正确 not-taken均不恢复。
- target：`JAL` 目标正确；同一 `JALR` PC 改变目标时能检测 target mismatch。
- stale entry：人为让普通指令携带 predicted target，EX 必须回到 `PC+4`。
- pipeline：IF/ID、ID/EX 输入无效但 ready 时预测 payload 不改写；not-ready 时稳定；redirect 后年轻 valid 被清除。
- exactly-once：强制 `i_ex_ma_rdy=0` 保持一个可解析控制流指令时 update/recovery 为 0；恢复 ready 后只脉冲一次。另覆盖 MDU 多周期等待；检查事件与 `o_ex_ma_vld && i_ex_ma_rdy` 逐拍等价。
- `fence.i`：强制 `PC+4` redirect，BTB/BHT 清空，不能同时写回旧训练。
- exception：misaligned control target 走 exception，禁止 predictor update。
- enable=0：恒顺序预测，所有 ISA 功能与当前基线一致。

建议 SVA：

```text
!ex_vld                  |-> !bp_update_vld
!if_id_fire              |=> $stable(pred_next_pc_id)
!id_ex_fire              |=> $stable(pred_next_pc_ex)
bp_update_vld            |-> ex_commit_fire
bp_invalidate            |-> ex_commit_fire
prediction_recovery_req  |-> ex_commit_fire
correct_prediction       |-> !prediction_recovery_req
btb_miss                 |-> pred_next_pc == fetch_pc + 4
```

## 6. 回归命令与交付判定

公共回归以 [`rule_ai_acceptance.md`](rule_ai_acceptance.md) 为准，在 `work/my-RISCV-Projs/sim` 执行并显式指定版本：

```text
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32i DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../11_rv32im_bpu
```

允许沿用已知 `rv32ui/ma_data` FAIL，其余已有用例必须 PASS。交付记录需包含：

- 修改文件列表和关键接口说明。
- 生成 filelist/编译日志中的路径证据，证明核心 RTL 和 `branch_predictor.sv` 均来自 `11_rv32im_bpu`，不存在 `../10_rv32im/de` 偷换。
- `BPU_ENABLE=0/1` 的功能回归结果。
- 实际编译的 `BPU_BTB_ENTRIES/BPU_BHT_ENTRIES` 值；默认验收应为 16/16。
- 至少一个循环分支从冷启动误判到稳定预测的波形或计数说明。
- 是否观察到 BTB/BHT alias；alias 只允许影响性能，不能影响架构结果。
- 未完成项、时序风险或偏离 SPEC 的明确说明。

本任务不要求跑综合，但不得以“未综合”为由改变接口或放宽正确性要求。若组合预测路径成为时序瓶颈，先报告数据与建议，不得自行增加会改变 ITCM 对齐关系的流水级。

## 7. 完成记录

- 已实现 16 项直接映射 BTB、16 项独立 2-bit BHT、可关闭配置、`fence.i` invalidate，以及 IF/ID/EX 预测 next-PC payload 传递。
- 已按 v11 语义适配：IDU/EXU payload 仅在有效输入握手且非 flush 时更新；训练、invalidate 和恢复统一绑定 `o_ex_ma_vld && i_ex_ma_rdy`。
- 已完成 BRU 真实类型/方向/目标输出、EX actual-next-PC 比较、目标错误恢复，以及 exception > `mret` > `fence.i` > prediction recovery 仲裁。
- 已修正 sim/syn filelist 的 v10 遗留路径；VCS 与 DC 日志确认核心 RTL、预测器和 BPU SVA 均来自 `11_rv32im_bpu`。
- 独立验证 Agent 新增预测器单测、IF/ID 前端握手定向测试和 IDU/EXU BPU SVA。`BPU_ENABLE=1/0` 单测及前端测试均 PASS；安全 clean 在检查绝对路径、非符号链接、顶层白名单和无源文件后仅删除 `dv/bpu_build`。
- `beq` 集成验证 PASS 且无 BPU SVA 错误：73 次控制流训练中包含 36 次 prediction recovery 和 37 次控制流正确预测，证明训练后预测能够命中并避免恢复。
- `BPU_ENABLE=1` 与 `BPU_ENABLE=0` 公共回归结果一致：ISA `rv32ui` 41/42 PASS（仅允许的既有 `ma_data` FAIL）、`rv32um` 8/8 PASS；Compliance `rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS。批处理会把任何 `[BPU SVA]` 报错计为失败，本次未发现此类报错。
- `make check DESIGN_NAME=11_rv32im_bpu` PASS，完成 analyze/elaborate/link/check_timing；未执行完整综合。BTB/BHT alias 仅在定向测试中作为替换行为覆盖，未观察到架构结果影响。
