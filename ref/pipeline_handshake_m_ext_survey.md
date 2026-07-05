# biRISCV / panda_risc_v_2 / rtl_e203 流水握手与 M 扩展停顿调研

调研对象：

- `biRISCV`
- `panda_risc_v_2`
- `rtl_e203`

关注问题：

1. 流水级间是否存在握手？
2. 运行多周期 M 扩展指令时，如何处理流水线停顿？

## 结论总览

| 项目 | 级间握手形态 | M 扩展多周期处理 | 对流水线的影响 |
|---|---|---|---|
| `biRISCV` | 前端到 issue 有 `valid/accept`；执行流水内部主要是集中 `stall/hold`，不是每一级独立 `valid/ready`。 | 乘法是固定流水延迟，可被 `hold` 冻结；除法是 out-of-pipe 多周期单元，完成前全局阻塞 issue。 | 除法会停住整条 issue/执行流水；乘法通常不造成长时间全局停顿，除非被其他 stall 一起 hold。 |
| `panda_risc_v_2` | 大量使用 AXIS 风格 `valid/ready`，寄存器读取、发射队列、执行单元入口都有反压。 | 乘法器/除法器有输入 FIFO 和 `ready`，结果带 FU id / inst id 回写 ROB/监听网络。 | 不靠冻结整条流水等待 M 单元完成；只有对应入口 FIFO 满、操作数未就绪、发射队列满等局部条件会反压前级。 |
| `rtl_e203` | IFU 到 EXU、dispatch 到 ALU、ALU 内部子单元都使用 `valid/ready`。 | MULDIV 是 ALU 内共享数据通路的多周期单元，`muldiv_i_ready` 直到结果可被接收才拉高；该指令留在 ALU/EXU 当前槽位。 | MULDIV 执行期间通过 `ready` 反压 dispatch/IFU，形成顺序流水停顿；E203 的 OITF 主要管理 LSU/NICE 等 long-pipe，当前 MULDIV 实现未作为 long-pipe 入 OITF。 |

## biRISCV

### 级间是否有握手

`biRISCV` 不是全流水每级独立 `valid/ready` 的弹性流水。它的流控分两层：

- 前端/issue 边界有 `fetch*_valid_i` 和 `fetch*_accept_o`。`biriscv_issue.v` 中 issue 选中指令后通过 `fetch0_accept_o`、`fetch1_accept_o` 消费前端指令（见 `src/core/biriscv_issue.v:731`、`:732`）。
- issue 到每条执行 pipe 的入口有 `issue_valid_i` 和 `issue_accept_i`，`biriscv_pipe_ctrl` 只有在二者同时有效时把指令装入 E1（见 `src/core/biriscv_pipe_ctrl.v:165`）。
- 进入执行流水后，E1、E2、WB 的推进受集中 stall 控制。`issue_stall_i` 有效时 E1/E2 寄存器保持不变（见 `src/core/biriscv_pipe_ctrl.v:162`、`:243`），不是下游每一级分别返回 ready。

因此它有边界握手，但执行流水本身更接近“valid 位 + 全局 stall/hold”的顺序流水控制。

### 多周期 M 指令如何停顿

乘法和除法处理方式不同。

乘法：

- `biriscv_multiplier` 是固定流水乘法器，`MULT_STAGES = 2`，输入操作数进入 E1，结果在 E2/E3 寄存（见 `src/core/biriscv_multiplier.v:53`、`:100`、`:142`）。
- 乘法器带 `hold_i`，当流水 stall 时内部乘法流水寄存器也保持（见 `src/core/biriscv_multiplier.v:108`、`:133`、`:139`）。
- issue 侧把全局 `stall_w` 接给 `mul_hold_o`（见 `src/core/biriscv_issue.v:455`、`:456`）。
- 若开启 `SUPPORT_MUL_BYPASS`，E2 阶段可直接选择 `mul_result_e2_i` 作为旁路结果（见 `src/core/biriscv_pipe_ctrl.v:303` 到 `:306`）。

除法：

- `biriscv_divider` 是 out-of-pipe 迭代单元，用 `div_busy_q`、`q_mask_q` 做多周期除法，完成条件为 `!(|q_mask_q) & div_busy_q`（见 `src/core/biriscv_divider.v:90`、`:91`、`:155` 到 `:164`）。
- 完成后产生 `writeback_valid_o` 和结果（见 `src/core/biriscv_divider.v:178` 到 `:191`）。
- pipe 控制里，若 E1 是 DIV 且 `div_complete_i` 未到，`stall_o` 拉高（见 `src/core/biriscv_pipe_ctrl.v:315`、`:316`）。
- issue 顶层用 `div_pending_q` 记录除法未完成，注释明确写着 division 会 stall pipeline 直到 completed（见 `src/core/biriscv_issue.v:597` 到 `:613`）。
- 调度逻辑在 `lsu_stall_i || stall_w || div_pending_q || csr_pending_q` 为真时不发射新指令（见 `src/core/biriscv_issue.v:685` 到 `:687`、`:701` 到 `:703`）。

结论：`biRISCV` 中除法是会冻结 issue/执行推进的多周期阻塞操作；乘法是流水化操作，主要通过 scoreboard/bypass 和 hold 配合，不像除法那样持有 `div_pending_q` 长时间全局阻塞。

## panda_risc_v_2

### 级间是否有握手

`panda_risc_v_2` 明确采用 `valid/ready` 式反压。典型位置包括：

- 取指结果到寄存器读取/预取阶段：`s_regs_rd_valid = m_if_res_valid`，`m_if_res_ready = s_regs_rd_ready`（见 `core_rtl/panda_risc_v_core.v:646` 到 `:651`）。
- 操作数获取与译码阶段：`s_if_res_ready = (~on_rst_flush) & m_op_ftc_id_res_ready & op1_ready & op2_ready`，输出 `m_op_ftc_id_res_valid = (~on_rst_flush) & s_if_res_valid & op1_ready & op2_ready`（见 `core_rtl/panda_risc_v_op_fetch_idec.v:483` 到 `:485`、`:548` 到 `:550`）。
- 分发模块输入 ready 由目标执行单元 ready 组合得到，乘法指令要求 `m_mul_ready`，除法/求余要求 `m_div_ready`（见 `core_rtl/panda_risc_v_dispatch.v:194` 到 `:217`）。
- 乱序配置下，寄存器读取输出写入 IQ0/IQ1 也有 `m_wr_iq*_valid` / `m_wr_iq*_ready`（见 `core_rtl/panda_risc_v_core.v:687` 到 `:717`）。

结论：这是三者中最接近“弹性流水/队列化数据流”的设计，流水级间和功能单元入口都存在显式握手。

### 多周期 M 指令如何停顿

乘法器：

- `panda_risc_v_multiplier` 模块注释说明是多周期乘法器，带深度为 2 的输入缓存区；周期数为输入缓存 + 计算 + 输出寄存（见 `core_rtl/panda_risc_v_multiplier.v:27` 到 `:35`）。
- 输入端 `s_mul_req_valid/s_mul_req_ready`，ready 直接来自 FIFO 非满 `mul_in_buf_full_n`（见 `core_rtl/panda_risc_v_multiplier.v:56` 到 `:70`、`:91` 到 `:97`）。
- 结果端有 `m_mul_res_valid/m_mul_res_ready`，在 `panda_risc_v_func_units` 里结果 ready 固定为 `1'b1`，结果进入统一 FU result bus（见 `core_rtl/panda_risc_v_func_units.v:416` 到 `:437`、`:463` 到 `:468`）。

除法器：

- `panda_risc_v_divider` 注释说明是多周期除法器，输入 FIFO 深度为 2，计算约 20 cycle，再经过输出寄存（见 `core_rtl/panda_risc_v_divider.v:27` 到 `:35`）。
- 输入端 `s_div_req_ready = div_in_buf_full_n`，即除法 FIFO 不满才接受新请求（见 `core_rtl/panda_risc_v_divider.v:55` 到 `:69`、`:90` 到 `:97`）。
- 结果端 `m_div_res_valid`，在 `panda_risc_v_func_units` 中 `m_div_res_ready` 固定为 `1'b1`，结果同样进入 FU result bus（见 `core_rtl/panda_risc_v_func_units.v:440` 到 `:460`、`:467` 到 `:468`）。

与流水停顿的关系：

- 入口若 FIFO 满，`m_mul_ready`/`m_div_ready` 会变低，dispatch 的 `fu_ready` 变低，从而 `s_dsptc_ready` 变低，反压上游（见 `core_rtl/panda_risc_v_dispatch.v:194` 到 `:217`）。
- 在乱序发射队列中，M 指令通过 IQ 输出给乘法器/除法器。代码注释说明 `m_mul_valid`、`m_div_valid` 虽依赖 ready，但因 M 单元输入处有 FIFO，因此安全（见 `core_rtl/panda_risc_v_issue_queue.v:407` 到 `:431`）。
- 执行结果带 `inst_id` 返回，`fu_res_vld/fu_res_tid/fu_res_data` 广播给 ROB/监听逻辑（见 `core_rtl/panda_risc_v_func_units.v:463` 到 `:475`）。后续依赖指令等待对应操作数就绪，而不需要全局冻结。

结论：`panda_risc_v_2` 的多周期 M 指令通过“入口 ready 反压 + FIFO 缓冲 + 结果广播/ROB 唤醒”处理。它不是 biRISCV 那种除法 pending 后全局停发的模型，而是局部资源满或数据未就绪才停相应前级。

## rtl_e203

### 级间是否有握手

`rtl_e203` 使用清晰的 `valid/ready` 握手：

- `e203_core` 中 IFU 输出 `ifu_o_valid/ifu_o_ready` 连接 EXU 输入 `i_valid/i_ready`（见 `core/e203_core.v:339`、`:340`、`:540`、`:541`）。
- EXU 内 `i_valid/i_ready` 直接进入 dispatch（见 `core/e203_exu.v:347` 到 `:355`）。
- dispatch 到 ALU 使用 `disp_o_alu_valid/disp_o_alu_ready`，并由 `disp_condition` 控制是否可继续（见 `core/e203_exu_disp.v:37` 到 `:39`、`:140` 到 `:142`、`:205` 到 `:226`）。
- ALU 内部根据具体子单元 ready 产生总 `i_ready`，MULDIV ready 是其中一项（见 `core/e203_exu_alu.v:221` 到 `:232`）。

结论：E203 的级间存在握手，尤其是 IFU->EXU、dispatch->ALU 和 ALU 子单元入口均为 `valid/ready` 风格。

### 多周期 M 指令如何停顿

E203 的 MULDIV 单元是 ALU 内共享数据通路的多周期单元：

- 文件注释说明 `e203_exu_alu_muldiv` 实现 17 cycles MUL 和 33 cycles DIV，并与 ALU datapath 共享以节省面积（见 `core/e203_exu_alu_muldiv.v:23` 到 `:25`）。
- MULDIV 入口有 `muldiv_i_valid/muldiv_i_ready`，出口有 `muldiv_o_valid/muldiv_o_ready`（见 `core/e203_exu_alu_muldiv.v:37` 到 `:57`）。
- FSM 使用 `MULDIV_STATE_EXEC`、`REMD_CHCK`、`QUOT_CORR`、`REMD_CORR` 等状态，计数到 16 cycle 判定乘法末周期，32 cycle 判定除法末周期（见 `core/e203_exu_alu_muldiv.v:120` 到 `:140`、`:236` 到 `:255`）。
- 输出 ready/valid 的关键逻辑是：只有 back-to-back/special case 或执行到末周期/修正完成时 `wbck_condi` 才为真；`muldiv_o_valid = wbck_condi & muldiv_i_valid`，`muldiv_i_ready = wbck_condi & muldiv_o_ready`（见 `core/e203_exu_alu_muldiv.v:460` 到 `:471`）。
- ALU 顶层把 `mdv_i_ready` 纳入 `i_ready`，因此 MULDIV 未完成时 ALU 输入不 ready，反压 dispatch 和 IFU（见 `core/e203_exu_alu.v:221` 到 `:232`、`core/e203_exu_disp.v:225`、`:226`）。

OITF/long-pipe 的关系：

- `e203_exu_disp` 会检查 OITF RAW/WAW 依赖，CSR/FENCE 等还会等待 OITF empty（见 `core/e203_exu_disp.v:176` 到 `:199`、`:205` 到 `:223`）。
- 但当前共享 MULDIV 实现中 `muldiv_i_longpipe = 1'b0`（见 `core/e203_exu_alu_muldiv.v:531`），所以 MULDIV 不作为 long-pipe 分配 OITF 项。
- ALU 输出通路也说明非 long-pipe 指令需要在 ALU 当前输出路径写回；long-pipe 才由 long-pipe writeback 处理（见 `core/e203_exu_alu.v:845` 到 `:857`）。

结论：E203 的 M 扩展不是排入 OITF 后异步返回的 long-pipe，而是在 ALU/MULDIV 当前路径内保持 `valid`，等待多周期 FSM 完成后 `ready` 才放行。因此运行普通 MULDIV 时，前端到 EXU 会被 ready 反压停住；这是顺序、阻塞式停顿，但停顿是通过标准握手传播的。

## 横向对比

1. `biRISCV` 的除法最“硬阻塞”：`div_pending_q` 加 `stall_w` 会让 issue 不再发射，pipe 寄存器 hold，直到 `writeback_div_valid_i` 到来。
2. `panda_risc_v_2` 最“队列化”：M 指令进入乘/除法器 FIFO 后，核心可以继续处理其他可发射指令；依赖者由 ROB/监听网络等待结果。
3. `rtl_e203` 介于二者之间但更偏顺序：它有握手，但共享 MULDIV 不进 long-pipe/OITF，而是在 ALU 内把 `ready` 压低到结果完成，因此前级自然停顿。

如果用于新设计借鉴：

- 简单顺序核可参考 E203：用 `valid/ready` 传播停顿，MULDIV 在执行槽内多周期保持，控制简单。
- 双发射顺序核可参考 biRISCV：乘法流水化、除法全局 pending，配合 scoreboard 避免 RAW。
- 想支持乱序/非阻塞 M 执行，可参考 Panda：M 单元入口 FIFO + 结果广播/ROB 唤醒，避免单条长延迟指令冻结全核。
