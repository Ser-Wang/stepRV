# task_v10_05：流水级 payload 仅在 vld/rdy 有效接收时更新

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-07-11 00:00
**Current Version**: v1.3

**Status**: Completed (2026-08-14 01:47)

**Version Changelog**:
- **v1.3** (2026-08-16 19:12): 合并复审必要结论，补充 control payload 的 valid 限定边界、实施状态和实际验证结果。
- **v1.2** (2026-08-14 01:37): 取消 `fire`/`accept` 信号抽象，payload 写条件直接使用 `vld & rdy`，有 flush 的级再直接限定 `!flush`。
- **v1.1** (2026-08-14 01:23): 根据复审结论区分接口握手 `fire` 与 flush/kill 限定后的有效接收 `accept`；payload 仅在 `accept` 时更新。
- **v1.0** (2026-07-11 00:00): 创建流水级 payload 握手更新语义工单。

---
## Goal

统一 `IDU -> EXU -> MAU -> WBU` 的 vld/rdy 寄存语义：stage valid 继续按 `rdy`/flush 规则更新，payload 写条件直接使用 upstream `vld` 与本级 `rdy`；存在 flush/kill 时再直接加入无效化条件。减少无效 payload 翻转并明确真实接收边界，不改变流水级接口、功能、停顿和吞吐。

本工单已完成 RTL 修改与功能回归，实施和验证结果记录在本文末尾。

## Required Semantics

不新增 `*_fire`、`*_accept` 或 `*_xfer` 等中间信号。payload 在时序块中直接使用对应接口的 `vld`、`rdy` 和必要的 flush/kill 条件：

```systemverilog
// IDU、EXU：接口握手且本拍未被 flush
if (i_if_id_vld & o_if_id_rdy & !i_flush)
    id_payload_regs <= if_payload;

if (i_id_ex_vld & o_id_ex_rdy & !i_flush)
    ex_payload_regs <= id_payload;

// MAU、WBU：无 flush 输入
if (i_ex_ma_vld & o_ex_ma_rdy)
    ma_payload_regs <= ex_payload;

if (i_ma_wb_vld & o_ma_wb_rdy)
    wb_payload_regs <= ma_payload;
```

`vld & rdy` 只表示接口层面的握手；IDU、EXU 必须在同一条件中直接加入 `!i_flush`，避免采样当拍被 kill 的输入。MAU、WBU 没有 flush 输入，直接使用各自的 `vld & rdy`。若某级的 `rdy` 已明确包含 stall 条件，不重复追加 `!stall`；只有 stall 未被 `rdy` 完整表达时，才在写条件中直接加入 `!stall`。

stage valid 必须保持现有 elastic-buffer 规则：

```systemverilog
if (reset_or_flush)
    stage_vld <= 1'b0;
else if (stage_rdy)
    stage_vld <= upstream_vld;
```

不得把 valid 更新条件改成 `upstream_vld & stage_rdy`；`stage_rdy=1 && upstream_vld=0` 时必须能接收 bubble 并清空 stage valid。

payload 规则：

```systemverilog
if (upstream_vld & stage_rdy & !stage_flush)
    payload_regs <= upstream_payload;
```

- 上述有效接收条件不成立时 payload 保持，包括 bubble、backpressure 和 flush/kill 周期。
- 当 `upstream_vld=1 && stage_rdy=1 && stage_flush=1` 时，接口层面虽然满足 `vld & rdy`，但 payload 不得更新。
- `valid=0` 时 payload 内容无架构语义，所有控制和副作用仍由对应 stage valid 限定。
- reset 时 payload 可初始化；flush 无需清零普通 payload，清除 valid 已足以使内容失去架构语义。
- vld/rdy 反压期间，valid 与 payload 必须稳定。

## Valid Gating Safety Boundary

普通数据 payload 和随指令传递的 control payload（例如 rd 写使能、decinfo、源寄存器需求标志）在 bubble、backpressure 或 flush 后可以保留旧值，但所有架构副作用与 hazard 判断必须由对应 stage valid 严格限定：

- EXU 的写回使能由 `o_ex_ma_vld` 限定，dispatch、memory、CSR、redirect 和 forwarding 相关控制由 `r_ex_vld` 或其派生请求限定。
- MAU、WBU 的 rd 写使能分别由 `r_ma_vld`、`r_wb_vld` 限定。
- 无效 stage 的 rd 索引、decinfo、`need_rs*`、写使能等内容均为 don't-care，不得被下游脱离 valid 单独使用。
- flush 时保留 control payload 不会产生副作用；若未来新增消费者绕过 stage valid 使用这些信号，必须同步补齐 valid 限定，否则属于协议破坏。
- 必须取消的 MDU/FSM/请求事务状态不适用上述规则，仍按各自 reset/flush/kill 和握手事件更新。

## RTL Scope

- `de/core/idu.sv`
  - 不新增握手中间信号。
  - `r_instr_id`、`r_pc_id` 使用 `i_if_id_vld & o_if_id_rdy & !i_flush` 更新。
  - `r_id_vld` 仍使用 `o_if_id_rdy` 更新。
- `de/core/exu.sv`
  - 不新增握手中间信号。
  - ID/EX payload：操作数、立即数、PC、decinfo、rd 信息、rs 索引、`need_rs*` 使用 `i_id_ex_vld & o_id_ex_rdy & !i_flush` 更新。
  - `r_ex_vld` 仍使用 `o_id_ex_rdy` 更新。
  - `r_mdu_req_issued` 是 MDU 事务状态，只能由 reset/flush、`mdu_req_vld & mdu_req_rdy`、MDU rsp 接收条件更新，不得并入 payload 机械改写。
- `de/core/mau.sv`
  - 不新增握手中间信号。
  - EX/MA payload：访存信息、地址、写回数据、rd 信息使用 `i_ex_ma_vld & o_ex_ma_rdy` 更新。
  - `r_ma_vld` 仍使用 `o_ex_ma_rdy` 更新。
- `de/core/wbu.sv`
  - 不新增握手中间信号。
  - MA/WB payload：写回数据和 rd 信息使用 `i_ma_wb_vld & o_ma_wb_rdy` 更新。
  - `r_wb_vld` 仍使用 `o_ma_wb_rdy` 更新。
- `de/core/ifu.sv` 仅审计现有 `if_accept`/PC 更新是否已使用真实握手；该信号属于既有 IFU 控制，不因本工单机械改名或删除，无必要不得修改。

## Constraints

- 不修改模块端口、指令行为、MDU req/rsp/kill 协议和现有 `rdy` 组合逻辑。
- 不把 stage valid 的更新条件改为 `upstream_vld & stage_rdy`；bubble 必须仍能在 `stage_rdy=1` 时进入并清空 valid。
- 不调整 MDU 计算期间 `o_need_rs1_exu/o_need_rs2_exu` 的精确关闭逻辑；该优化已在 `exu.sv` 留注释，不属于本工单。
- 不把副作用事件、请求状态或 FSM 状态视为普通流水 payload。
- 不引入额外 bubble、stall 或吞吐退化。
- 不修改与本语义统一无关的 RTL。

## Power Expectation

- 预期收益来自 bubble、flush 等无效周期中 payload 寄存器及其后级组合逻辑活动率降低。
- 满吞吐时 upstream `vld=1`，新旧写使能基本等价；本修改也不会自动降低时钟树功耗。
- 实际收益受综合后的寄存器使能实现、数据活动率和布局负载影响。当前流程无真实工作负载的 SAIF/VCD 回标，因此功耗收益仅作定性预期，不作为验收指标。

## Verification

静态检查：

- 普通流水 payload 不新增 `*_fire`、`*_accept` 或 `*_xfer` 中间信号，写条件直接使用对应的 `vld`、`rdy` 和必要的 `!flush`/`!kill`。
- 所有 stage valid 仍由 `rdy` 装载 upstream valid。
- payload 仅在 `upstream_vld & stage_rdy & !stage_flush`（无 flush 的级为 `upstream_vld & stage_rdy`）时更新，其他周期保持稳定。
- 满足上述有效接收条件后，payload 等于上一拍 upstream payload。
- `stage_rdy && !upstream_vld && !flush` 后 stage valid 清零。
- `rdy=0` 且无 flush 时 valid/payload 保持；flush 后对应 valid 清零且普通 payload 保持。
- 无效 stage 不产生 RF、memory、CSR、redirect、forwarding 或 MDU 请求副作用。

在 `work/my-RISCV-Projs/sim` 执行：

```text
make sim_isa test=add DESIGN_NAME=../10_rv32im
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../10_rv32im
make sim_isa_all type=compli group=rv32i DESIGN_NAME=../10_rv32im
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../10_rv32im
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../10_rv32im
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../10_rv32im
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../10_rv32im
```

必须显式指定 `DESIGN_NAME=../10_rv32im`，避免当前 makefile 默认编译 `10_rv32im_copy`。

## Verification Result

- VCS 编译：PASS。
- 定向 `riscv-tests/add`：PASS，SVA/断言日志未发现失败。
- ISA `rv32ui`：41/42 PASS；唯一失败为验收允许的既有 `ma_data`。
- Compliance `rv32i`：48/48 PASS。
- Compliance `rv32Zicsr`：6/6 PASS。
- Compliance `rv32Zifencei`：1/1 PASS。
- ISA `rv32um`：8/8 PASS。
- Compliance `rv32im`：8/8 PASS。
- 静态检查：payload 写条件、stage valid 独立更新、flush 保持和 valid-gated 副作用均符合本文要求；`git diff --check` PASS。

验收结论：通过。除允许的既有 `rv32ui/ma_data` FAIL 外，其余用例全部 PASS；本工单未要求综合、时序或功耗分析。
