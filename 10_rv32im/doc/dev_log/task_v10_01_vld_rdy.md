# task_v10_01：RV32IM 显式 vld/rdy 流水线改造工单

作者：GPT-5 Codex | thinking: medium | agent: Codex
时间戳：2026-07-07 15:57 CST
状态：done，完成时间：2026-07-07 17:31 CST

## 版本更新 log

- v0.6，2026-07-07 17:34 CST：监督复跑公共 DV 验收命令，结果达标。
- v0.5，2026-07-07 17:33 CST：监督复核后修正 ready allow-in 为 empty/downstream-ready 标准形式。
- v0.4，2026-07-07 17:31 CST：完成 RTL 握手骨架改造与 clean 后基础回归，记录交付结果。
- v0.3，2026-07-07 17:19 CST：保留模块端口 `i_/o_` 前缀，补充零额外停顿和 DV 验收要求。
- v0.2，2026-07-07 16:59 CST：统一边界握手命名，收窄 CSR 精确性要求，当前阶段只改握手不实现 M 执行。
- v0.1，2026-07-07 15:57 CST：初版，分析现有流水并规划 vld/rdy 反压改造。

## 1. 背景与目标

当前 `10_rv32im/de` 已经是简单 5 级顺序单发射流水：`IFU -> IDU -> EXU -> MAU -> WBU`。现有控制以 `stall[4:0]` / `flush[3:0]` 为主，`IFU` 内已有局部 `o_if_valid`，但 ID/EX/MA/WB 各级没有统一的 valid 位，也没有可由后级向前级传播的 ready 反压协议。

本工单目标是在各流水级之间增加显式 `vld/rdy` 握手，为后续引入 RV32M 多周期乘除法器提供反压能力：未来当 EX 级执行 `mul/div/rem` 等多周期指令时，EX 级可以保持当前 uop 不被覆盖，并向 ID/IF 级反压；未来接入 I-cache/D-cache miss、总线 wait、访存 replay 时也能复用同一控制框架。

本工单只做握手相关改造，不实现 M 扩展执行单元，不新增 MDU。

改造约束：

- 模块端口必须保留现有统一风格，输入使用 `i_` 前缀，输出使用 `o_` 前缀；边界名作为端口主体，例如 IDU 使用 `i_if_id_vld/o_if_id_rdy/o_id_ex_vld/i_id_ex_rdy`。
- 当前阶段所有新增 ready 默认不应引入额外停顿。运行相同汇编程序时，除 valid 机制替代 NOP/flush 表达外，停顿点和流水推进行为应与改造前一致；若出现额外停顿，默认视为不必要，需要修复或解释。

## 2. 当前设计观察

- `core.sv` 顶层连接了 `ifu/idu/exu/mau/wbu/ctrl_hazard/csr_regs`，流水寄存器分散在各 stage 模块内部。
- `ifu.sv` 已有 `if_valid_r` 和 `o_if_valid`，但 `core.sv` 用 `if_valid ? i_if_instr : INSTR_NOP` 将无效取指转成物理 NOP 后送入 `idu`。
- `idu.sv` 内部寄存 `r_instr_id/r_pc_id`，遇到 `i_flush` 时写入 `INSTR_NOP`，遇到 `i_stall` 时保持。
- `exu.sv` 内部寄存 ID/EX 数据、rs 索引、need_rs、rd 信息和 decinfo，遇到 `i_flush` 时只清部分控制位，遇到 `i_stall` 时保持。
- `mau.sv` / `wbu.sv` 当前每拍无条件采样前级输出，没有 `stall/flush/valid` 输入；这意味着一旦 EX 级需要多周期保持，后级可能重复采样同一结果或采到无效数据。
- `ctrl_hazard.sv` 当前只处理 forwarding、load-use 和 redirect：load-use 时 `stall = 5'b00011`，只冻结 PC/IF_ID，同时 flush ID_EX；redirect 时 flush IF_ID/ID_EX。该控制尚未表达“后级 not-ready 导致上游保持”的通用流控。
- `csr_regs.sv` 用 `~stall[STALL_ID_EX] & ~flush[FLUSH_ID_EX]` 作为 CSR commit enable 的一部分。当前阶段可仅做必要的 valid gating，避免无效指令写 CSR；精确 CSR/trap 提交点后续会随 writeback commit 架构再重构。

## 3. 推荐握手语义

采用每级一个 payload valid、一级反向 ready 的同步握手：

- `if_id_vld/id_ex_vld/ex_ma_vld/ma_wb_vld/wb_vld` 表示该级寄存器中的 payload 有效。
- `if_id_rdy/id_ex_rdy/ex_ma_rdy/ma_wb_rdy/wb_rdy` 表示下游本拍能接受上游 payload。
- stage fire 条件统一为 `stage_fire = upstream_vld & downstream_rdy`。
- pipe register 更新规则：
  - reset：`vld <= 1'b0`。
  - flush/kill：对应级 `vld <= 1'b0`，payload 可不覆写为 NOP。
  - `downstream_rdy` 为 1：采样上游 payload，同时 `vld <= upstream_vld`。
  - `downstream_rdy` 为 0：保持本级 payload 和 `vld` 不变。
- 任何写 RF、写 memory、CSR/trap 更新、redirect 产生、forwarding 命中、load-use 检测都必须用对应 stage 的 `*_vld` gating。

建议保留旧 `stall/flush` 宏名作为过渡，但其来源应从固定 hazard 编码逐步改为 vld/rdy 推导。最终更推荐显式 `*_allowin`/`*_rdy`、`*_vld` 信号，旧 bit-vector 只作为兼容层或删除。

## 4. 顶层 `core.sv` 修改点

新增并连接各级握手信号：

- IF/ID 边界：顶层内部信号 `if_id_vld`, `if_id_rdy`；模块端口按方向写成 `o_if_id_vld/i_if_id_rdy` 或 `i_if_id_vld/o_if_id_rdy`。
- ID/EX 边界：顶层内部信号 `id_ex_vld`, `id_ex_rdy`；模块端口按方向写成 `o_id_ex_vld/i_id_ex_rdy` 或 `i_id_ex_vld/o_id_ex_rdy`。
- EX/MA 边界：顶层内部信号 `ex_ma_vld`, `ex_ma_rdy`；模块端口按方向写成 `o_ex_ma_vld/i_ex_ma_rdy` 或 `i_ex_ma_vld/o_ex_ma_rdy`。
- MA/WB 边界：顶层内部信号 `ma_wb_vld`, `ma_wb_rdy`；模块端口按方向写成 `o_ma_wb_vld/i_ma_wb_rdy` 或 `i_ma_wb_vld/o_ma_wb_rdy`。
- WB/commit：顶层内部信号 `wb_vld`, `wb_rdy`；单发射顺序核中 `wb_rdy` 可先常 1。

顶层需要统一生成或汇总：

- `redirect_flush`：来自 EX 的 branch/trap/mret/fence.i 等重定向请求，用于 kill IF/ID 和 ID/EX 的错路径 valid。
- `ex_busy` / `ex_ma_vld`：未来 MDU 多周期执行期间 EX 不 ready，直到结果可被 EX/MA 接受。
- `mem_busy`：未来 D-cache/bus wait 使用；当前 TCM/SoC bus 可先常 0。

当前 `instr_to_idu = if_valid ? i_if_instr : INSTR_NOP` 应删除或只作为仿真 debug fallback。IDU 应接收真实 `if_id_vld`，无效指令由 valid 位屏蔽，不再注入物理 NOP。

## 5. `ifu.sv` 修改点

IFU 当前有 `i_stall`、`o_if_valid` 和 PC 寄存器。建议改造成前端源端，端口保留 `i_/o_` 前缀：

- 输入：`i_if_id_rdy`、`i_redirect_req`、`i_redirect_pcnext`。
- 输出：`o_if_id_vld`、`o_fetch_req`、`o_fetch_pc`、`o_instr_pc`。
- PC 只在 `if_id_fire = if_id_vld & if_id_rdy` 或 redirect 时前进/改道。
- redirect 优先级高于普通 fire；redirect 当拍应 kill 旧路径 `if_id_vld` 或保证 IF/ID 不接收旧路径指令。
- 当前同步 ITCM 一拍读延迟语义要明确：`o_fetch_pc` 发起地址与下一拍 `i_if_instr` 的 PC 对齐关系需要通过 `o_instr_pc`/valid 保持，不再靠 NOP 掩码修补。

短期可保持 `o_fetch_req = 1'b1` 或由 `if_id_rdy` gating；未来 I-cache 接入时应演进成真正 request/response vld/rdy。

## 6. `idu.sv` 修改点

IDU 需要从“带局部 stall/flush 的寄存译码”改为 IF/ID pipe register owner：

- 新增边界握手端口 `i_if_id_vld`、`o_if_id_rdy`、`o_id_ex_vld`、`i_id_ex_rdy`。
- IF/ID 寄存器更新遵循 `id_ex_rdy` 规则；flush 只清 `r_valid_id`，不再写 `INSTR_NOP`。
- 所有 decode 输出可以继续组合从 `r_instr_id` 产生，但对外控制语义必须配合 `id_ex_vld` 使用。
- `o_dec_rd_wen_id`、`o_need_rs1_idu`、`o_need_rs2_idu` 建议在顶层或 IDU 内用 `id_ex_vld` gating，避免无效 payload 参与 load-use 或 scoreboard 判断。
- 当前阶段不新增 M 扩展 decinfo，也不改变 `dec_rv32m_*` 的执行路径；后续引入 MDU 时再补 `DECINFO_GRP_MDU` 或等价边界。

## 7. `exu.sv` 修改点

EXU 是本次反压的核心改造点。

接口建议：

- 新增边界握手端口 `i_id_ex_vld`、`o_id_ex_rdy`、`o_ex_ma_vld`、`i_ex_ma_rdy`。
- EX 内部 ID/EX 寄存器增加 `r_ex_vld`。
- `id_ex_rdy = (~r_ex_vld) | (ex_result_done & ex_ma_rdy)` 的类似语义；当前所有已实现执行路径都可先令 `ex_result_done=1`。
- 为未来 MDU 预留 `ex_busy/ex_result_done` 接入点，但本工单不新增 `exu_mdu.sv`，不实现乘除法。

EXU 内部副作用 gating：

- `o_mem_wr_en_exu` 必须 gated by `r_ex_vld & ex_fire_to_mau` 或至少 `r_ex_vld & !exception`，防止 EX 保持期间重复 store。更稳妥的方式是把 store request payload 送入 EX/MA，由 MAU 在有效 fire 时发起。
- `o_redirect_req` 必须 gated by `r_ex_vld & ex_result_done`，避免无效 payload 或 busy 中间态误重定向。
- `o_exc_req` / `o_trap_ret_req` 同样必须 gated by valid 和 done。
- forwarding 输出中的 `o_wb_rd_wen_exu` 必须 gated by `r_ex_vld`。未来多周期 MDU 未 done 前不能对后级声明可写回。

## 8. `mau.sv` 修改点

MAU 当前无条件打一拍，需要改为 EX/MA pipe register owner：

- 新增边界握手端口 `i_ex_ma_vld`、`o_ex_ma_rdy`、`o_ma_wb_vld`、`i_ma_wb_rdy`。
- `r_mem_addr_mau/r_mem_req_info_bus/r_wb_*` 只在 `ex_ma_rdy` 允许时采样；flush/kill 时清 `r_ma_vld`。
- 当前 TCM/SoC bus 固定一拍返回，`ma_busy` 可先为 0，`ex_ma_rdy = (~r_ma_vld) | ma_wb_rdy`。
- 未来 D-cache miss 或 MMIO wait 时，`ma_busy` 拉低 `ex_ma_rdy`，自然反压 EX/ID/IF。
- `o_wb_rd_wen_mau`、`o_fwd_data_mau`、load data select 均需受 `r_ma_vld` 约束；forwarding 比较也应只看 valid MAU 指令。

注意当前 `o_fwd_data_mau = r_wb_data_exu_d1` 对 load-use 已依靠 stall 避免从 MAU 前递 load data。引入 ready 后仍需保持规则：load 在 MA/WB 边界 valid 且数据可用前不可被当作可 forward 结果。可增加 `o_fwd_vld_mau` 或在 `ctrl_hazard` 使用 `ma_wb_vld & !ma_is_load_pending` 区分。

## 9. `wbu.sv` 修改点

WBU 需要成为 MA/WB pipe register owner：

- 新增边界握手端口 `i_ma_wb_vld`、`o_ma_wb_rdy`、`o_wb_vld`、`i_wb_rdy`。
- 单发射顺序核短期 `wb_rdy = 1'b1`，WBU 每拍可提交。
- RF 写回：`rf_wb_rd_wen = wb_vld & wb_rd_wen_wbu`。
- `minstret` 未来可由 `wb_vld & commit_fire & !exception_kill` 驱动，而不是常 0。

## 10. `ctrl_hazard.sv` 修改点

`ctrl_hazard` 需要从“产生 stall/flush bit-vector”演进为“hazard + flush + ready 仲裁辅助”：

- forwarding 比较增加 valid gating：
  - MAU forwarding：`ma_wb_vld & wb_rd_wen_mau & rd_match`
  - WBU forwarding：`wb_vld & wb_rd_wen_wbu & rd_match`
- load-use 检测增加 valid gating：
  - `id_ex_vld & ex_is_load & if_id_vld & id_need_rs* & rd_match`
- load-use 的动作从旧 `stall PC/IF_ID + flush ID_EX` 改为：
  - ID/IF 保持，即 ID 不向 EX fire。
  - EX 插入 bubble 或让 EX 正常流向 MA 后 ID 再进入，具体取决于 ID/EX register owner 的实现。
- 未来多周期 MDU 反压不应由 `ctrl_hazard` 特判指令编码，而应由 EX 的 `id_ex_rdy=0` 自然传播。
- redirect flush 优先级应高于普通 ready 流动：redirect 发生时 kill IF/ID、ID/EX 中 younger 指令；EX 当前 redirect 指令本身按 done/fire 进入后级或直接完成，需在 RTL 中明确。

## 11. `csr_regs.sv` 修改点

CSR/trap 是副作用敏感路径，必须同步更新控制条件：

- 本阶段 CSR 可做得粗糙：只需保证无效指令不写 CSR，反压保持时尽量不重复写即可。
- 可先输入 `id_ex_vld` 或 `ex_stage_vld`，把当前 `csr_commit_en` 扩展为 `ex_stage_vld & ~flush/kill` 一类条件。
- 不建议在本工单投入大量精确 CSR/trap 提交改造；很快会把架构改为 writeback 时提交，届时再统一收敛 CSR 写、exception/trap entry、mret 的 side-effect enable。
- `misa` 的 M bit 暂不在本工单处理；等真正引入 M 执行时再更新。

## 12. `soc_top/soc_bus/mem_*` 修改点

本阶段目标主要是 core 内部 vld/rdy；SoC 访存接口可暂时保持固定延迟：

- I-side：`o_fetch_req/o_fetch_pc/i_if_instr` 暂不改外部协议，但 IFU 内部用 valid 对齐同步读数据。
- D-side：`o_mem_req_load/o_mem_wr_en/.../i_mem_rd_data` 暂不改外部协议，但 MAU 内部应为未来 `mem_req_vld/mem_req_rdy/mem_resp_vld` 预留边界。
- `soc_bus.sv` 当前 load select 打一拍，DTCM/ITCM/UART 均默认固定延迟；未来 cache/MMIO wait 接入时建议在 core 与 bus 间新增 ready/valid 或 request/response wrapper，不要把 wait 状态散落到 EXU。

## 13. 推荐实施顺序

1. 增加 pipeline valid 位，但先保持所有 ready 常 1，确保现有 RV32I 行为不变。
2. 删除物理 NOP 注入路径：`core.sv` 的 `instr_to_idu` NOP 掩码、`idu.sv` flush 写 NOP 改为清 valid。
3. 给 `mau.sv` / `wbu.sv` 补齐 valid 寄存和写回 gating，确保无效 payload 不写 RF、不参与 forwarding。
4. 将 `ctrl_hazard.sv` 的 forwarding/load-use 加 valid gating，并把 load-use 改造成基于 ID/EX fire 的保持/插泡。
5. 改造 EXU ready：当前先支持单周期 `id_ex_rdy`/`ex_ma_rdy` 传递，并预留未来 `ex_busy` 接入点。
6. 对 CSR/trap 只做最低限度 valid gating，避免无效指令副作用；精确提交留到 writeback commit 架构。
7. 补充仿真和 SVA，最后再把旧 `stall/flush` bit-vector 清理成兼容层或删除。
8. 确认新增握手默认不导致额外停顿：所有 ready 常态应为 1，仅现有 load-use/redirect 行为保持原样。

## 14. 验证清单

- RV32I 现有 ISA/用户程序回归全部通过。
- reset 后所有 stage valid 为 0，首条有效指令 PC 与 instruction 对齐。
- redirect 当拍及后一拍错路径指令不会写 RF、写 memory、写 CSR。
- `valid=0` 的 payload 即使内容为 store/csr/branch 编码，也不能产生副作用。
- load-use：消费者不会在 load data 可用前进入 EX；非 load 的 ALU/BRU/CSR forwarding 不退化。
- 人工拉低 `ex_ma_rdy` 或 `ma_wb_rdy` 时：PC/IF/ID/EX 按边界 ready 正确保持，后级可继续排空。
- store 在 EX 或 MA 被反压时不能重复写。
- CSR 写、ecall/ebreak、mret 在本阶段至少不能由无效 payload 触发；精确一次性提交后续在 WB commit 阶段验证。
- 本工单不要求 M 扩展 directed tests。
- 代码完成后按 `commonSpec_devflow_dv.md` 在 `work/my-RISCV-Projs/sim` 路径运行：
  - `make sim_isa_all type=isa group=rv32ui`
  - `make sim_isa_all type=compli group=rv32i`
  - `make sim_isa_all type=compli group=rv32iZicsr`
  - `make sim_isa_all type=compli group=rv32iZifencei`
- 允许例外：
  - `type=isa group=rv32ui` 中 `ma_data` 已知可 FAIL。
  - 本任务允许 CSR 暂时不精确，`rv32iZicsr` 若不 PASS，可以只汇报不修复。
- 建议新增 SVA：
  - `!stage_vld |-> !side_effect`
  - `stage_vld && !downstream_rdy |=> $stable(stage_payload)`
  - `fire |-> one_pulse` for RF/mem/CSR side effects
  - redirect flush kills younger valid。

## 15. 架构风险与未决问题

- 当前各 stage 自己拥有 pipeline register，改造时容易出现“payload 保持了但 valid/控制位没保持”或相反的问题。建议逐模块集中整理寄存更新条件。
- 当前 CSR/trap 在 EX 级直接产生副作用，严格的精确异常/提交点后续会推到 WB/commit；本阶段只做必要 valid 防护，接受临时不精确。
- 取指 PC 与同步 ITCM 返回数据的 valid 对齐需要仔细仿真，不能简单把 `if_valid` 直通成 `if_id_vld`。
- MDU 的乘法延迟选择、M 指令旁路、`misa` 的 M bit 均不在本工单处理，但握手边界需要为这些后续工作留出 `ex_busy/ex_result_done` 接入点。
- 如果后续 cache 改造会改变 I/D 侧外部协议，本次 core 内部命名应避免绑定 TCM 固定一拍假设。

## 16. 交付判定

本工单完成后的 RTL 预期状态：

- 每个流水级都有可观测 valid。
- EX/MA 或 MA/WB 边界 not-ready 能通过 ready 反压冻结上游。
- 常态 ready 为 1 时不产生额外停顿，现有汇编程序的流水停顿行为与改造前一致。
- 后级能在上游反压时继续排空，且不会重复提交副作用。
- 旧 RV32I 程序行为保持。
- 为后续 RV32M 多周期乘除法接入预留清晰的 EX 级 busy/done 反压接口。

## 17. 完成记录

- 已完成 `de/core` 内 IF/ID、ID/EX、EX/MA、MA/WB、WB 边界 `vld/rdy` 端口与顶层连接。
- 当前 ready 常态为 1，继续沿用既有 load-use/redirect stall/flush 行为，不引入额外等待。
- 已对 RF 写回、MA/WB forwarding、load-use 检测、CSR 写/异常/redirect/store 等副作用路径增加 valid gating。
- 未实现 M 扩展执行单元，未新增 `exu_mdu`。
- DV 结果，2026-07-07 17:34 CST 监督复跑确认：
  - `make sim_isa_all type=isa group=rv32ui`：41/42 PASS，仅允许项 `ma_data` FAIL。
  - `make sim_isa_all type=compli group=rv32i`：48/48 PASS。
  - `make sim_isa_all type=compli group=rv32iZicsr`：0/0 PASS，当前测试集为空。
  - `make sim_isa_all type=compli group=rv32iZifencei`：0/0 PASS，当前测试集为空。
