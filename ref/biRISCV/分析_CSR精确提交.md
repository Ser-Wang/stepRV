# biRISC-V CSR 精确提交架构分析

本文针对 `00_rv32i_basic/doc/spec_架构设计备忘录：CSR 写入逻辑与访存的精确异常冲突.md` 中提出的问题，分析 `ref/biRISCV` 的 CSR 写入、异常处理和访存完成之间的微架构关系。

## 结论摘要

biRISC-V 采用的是“CSR 在 E1 读和计算，在 WB/Commit 阶段写 CSR 物理寄存器”的方案，接近备忘录中的“方案三：真正的精确提交”。同时，它还对 CSR 指令做了序列化：CSR 只能走 pipe0，发射后 `csr_pending_q` 会阻止后续指令继续发射，直到该 CSR 指令到达 WB。因此它用“后延写入 + CSR 串行化”避免了 EX 级 CSR 早写和前序 MEM 异常同周期冲突，也避免了实现复杂 CSR forwarding。

这意味着：biRISC-V 不需要从 MEM 异常到 EX 级 CSR 写使能的组合强杀路径，因为 CSR 写使能本来就不会在 E1/EX 阶段直接作用到 CSR 寄存器。

## 相关流水级命名

从 `biriscv_pipe_ctrl.v` 看，单条指令大致经过：

- Issue：选择指令并分派到 pipe0/pipe1。
- E1：执行初段，CSR 在这里读旧值、计算写回值、产生早期异常。
- E2：访存/乘法等结果汇合，LSU 的 late exception 在这里进入流水。
- WB/Commit：普通寄存器写回、CSR 写回、异常提交入口。

代码中直接把 WB 标为 `Writeback / Commit`，说明该级被当作架构状态提交边界。

## CSR 模块：E1 只计算，不直接提交

`src/core/biriscv_csr.v` 的 CSR 顶层接口分成两部分：

- 当前 CSR 指令输入：`opcode_valid_i`、`opcode_opcode_i`、操作数等。
- 来自 WB 的提交输入：`csr_writeback_write_i`、`csr_writeback_waddr_i`、`csr_writeback_wdata_i`、`csr_writeback_exception_i`、`csr_writeback_exception_pc_i`、`csr_writeback_exception_addr_i`。

CSR register file 的写口只接收 WB 信号：

```verilog
// Exception (WB)
.exception_i(csr_writeback_exception_i)

// CSR register writes (WB)
.csr_waddr_i(csr_writeback_write_i ? csr_writeback_waddr_i : 12'b0)
.csr_wdata_i(csr_writeback_wdata_i)
```

见 `src/core/biriscv_csr.v:170` 到 `src/core/biriscv_csr.v:177`。

而 E1 阶段只锁存 CSR 读结果、CSR 写数据和 CSR 早期异常：

- `rd_result_e1_q <= csr_rdata_w`
- `csr_wdata_e1_q <= data_r / csr_rdata_w | data_r / csr_rdata_w & ~data_r`
- `exception_e1_q <= EXCEPTION_*`
- 输出为 `csr_result_e1_value_o`、`csr_result_e1_write_o`、`csr_result_e1_wdata_o`、`csr_result_e1_exception_o`

见 `src/core/biriscv_csr.v:203` 到 `src/core/biriscv_csr.v:259`。

所以 CSR 指令在 E1 只是形成“待提交事务”：旧值作为 rd 写回结果，更新值作为后续 WB 的 CSR 写数据，异常作为流水异常向后传递。

## pipe_ctrl：CSR 写数据随流水推进到 WB

`src/core/biriscv_pipe_ctrl.v` 中，E1 到 E2 会保存 CSR 写意图：

```verilog
csr_wr_e2_q    <= csr_result_write_e1_i;
csr_wdata_e2_q <= csr_result_wdata_e1_i;
```

见 `src/core/biriscv_pipe_ctrl.v:264` 到 `src/core/biriscv_pipe_ctrl.v:267`。

E2 到 WB 再保存成：

```verilog
csr_wr_wb_q    <= csr_wr_e2_q;
csr_wdata_wb_q <= csr_wdata_e2_q;
```

见 `src/core/biriscv_pipe_ctrl.v:401` 到 `src/core/biriscv_pipe_ctrl.v:402`。

最终输出到 CSR 文件：

```verilog
assign csr_write_wb_o = csr_wr_wb_q;
assign csr_waddr_wb_o = opcode_wb_q[31:20];
assign csr_wdata_wb_o = csr_wdata_wb_q;
```

见 `src/core/biriscv_pipe_ctrl.v:428` 之后的 WB 输出逻辑。

这条路径说明 CSR 物理寄存器更新发生在 WB 侧，而不是 E1 侧。

## 异常优先级：CSR 写与异常在 CSR regfile 内互斥

`src/core/biriscv_csr_regfile.v` 的 next-state 组合逻辑按优先级处理：

1. interrupt
2. xRET
3. delegated exception
4. machine exception
5. 普通 CSR 写

普通 CSR 写位于最后的 `else begin case (csr_waddr_i)` 中，见 `src/core/biriscv_csr_regfile.v:416` 到 `src/core/biriscv_csr_regfile.v:449`。异常处理分支在它之前，见 `src/core/biriscv_csr_regfile.v:264` 到 `src/core/biriscv_csr_regfile.v:415`。

因此如果 WB 同周期带有 `exception_i`，CSR regfile 会执行异常提交，例如写 `mepc/mcause/mtval/mstatus`，不会执行普通 CSR 写。这正是精确异常需要的“异常优先于年轻指令副作用”语义。

## 访存异常进入流水的位置

`src/core/biriscv_lsu.v` 对访存 late response 建模为：

- request 被接受后置 `pending_lsu_e2_q`。
- `mem_ack_i && mem_error_i` 形成错误完成。
- `writeback_exception_o` 根据 unaligned、bus fault、page fault 形成 load/store exception。

关键位置：

- outstanding tracking：`src/core/biriscv_lsu.v:100` 到 `src/core/biriscv_lsu.v:118`
- LSU stall：`src/core/biriscv_lsu.v:320` 到 `src/core/biriscv_lsu.v:321`
- fault 地址和异常输出：`src/core/biriscv_lsu.v:368` 之后

`biriscv_pipe_ctrl.v` 在 E2 判断 load/store 完成时选择 `mem_exception_e2_i`：

```verilog
if (valid_e2_q && (ctrl_e2_q[`PCINFO_LOAD] || ctrl_e2_q[`PCINFO_STORE]) && mem_complete_i)
    exception_e2_r = mem_exception_e2_i;
else
    exception_e2_r = exception_e2_q;
```

见 `src/core/biriscv_pipe_ctrl.v:318` 到 `src/core/biriscv_pipe_ctrl.v:325`。

只要 `exception_e2_r` 非零，就产生 squash：

```verilog
assign squash_e1_e2_w = |exception_e2_r;
assign squash_e1_e2_o = squash_e1_e2_w | squash_e1_e2_q;
```

见 `src/core/biriscv_pipe_ctrl.v:327` 到 `src/core/biriscv_pipe_ctrl.v:337`。

这个 squash 会清掉 E1/E2 内更年轻的指令状态。因为 CSR 写还没有真正提交，年轻 CSR 的写意图会在流水寄存器中被清除，而不是已经落到 CSR 物理寄存器后再补救。

## 双发射下的 CSR 限制

bi-RISC-V 是双发射核心，但 CSR 被限制在 pipe0：

- pipe0 的 `issue_csr_i` 接 `issue_a_csr_w`，见 `src/core/biriscv_issue.v:381` 到 `src/core/biriscv_issue.v:386`。
- pipe1 的 `issue_csr_i` 固定为 `1'b0`，见 `src/core/biriscv_issue.v:503` 到 `src/core/biriscv_issue.v:509`。
- pipe1 的 CSR writeback 输出也未连接，见 `src/core/biriscv_issue.v:562` 到 `src/core/biriscv_issue.v:574`。

此外，CSR 发射后置 `csr_pending_q`，直到 pipe0 的 CSR 到 WB 才清除：

```verilog
else if (csr_opcode_valid_o && issue_a_csr_w)
    csr_pending_q <= 1'b1;
else if (pipe0_csr_wb_w)
    csr_pending_q <= 1'b0;
```

见 `src/core/biriscv_issue.v:615` 到 `src/core/biriscv_issue.v:625`。

调度逻辑在 `csr_pending_q` 为 1 时不再发射新指令：

```verilog
if (lsu_stall_i || stall_w || div_pending_q || csr_pending_q)
    ;
```

见 `src/core/biriscv_issue.v:685` 到 `src/core/biriscv_issue.v:687` 以及 `src/core/biriscv_issue.v:701` 到 `src/core/biriscv_issue.v:703`。

这相当于对 CSR 指令做了短暂的 pipeline serialization。好处是连续 CSR RAW 不需要额外 CSR bypass：下一条 CSR 读发生时，前一条 CSR 已经 WB 并写入 CSR regfile。

## 和备忘录中冲突场景的对应关系

备忘录中的危险场景是：

- 前一条 load/store 在 MEM 级发现 late exception。
- 后一条 CSR 指令在 EX 级同周期准备写 CSR 物理寄存器。
- 如果 CSR 写使能没有被 MEM 异常组合屏蔽，就会违反精确异常。

biRISC-V 中这个场景被结构性规避：

1. CSR 在 E1 不写物理 CSR，只产生 `csr_result_e1_*`。
2. load/store late exception 在 E2 形成 `exception_e2_r`，随即产生 squash。
3. squash 清掉更年轻指令的 E1/E2 状态。
4. 真正 CSR 写只有到 WB 后才送入 `biriscv_csr_regfile`。
5. CSR regfile 内异常分支优先于普通 CSR 写。
6. CSR 指令被序列化，避免了额外 CSR forwarding 和复杂同周期多 CSR 提交。

所以 biRISC-V 的选择不是“EX 级早写 + MEM 异常组合强杀”，而是“WB 提交 + CSR 串行化”。这是更干净的精确异常模型，但代价是 CSR 指令吞吐较低，代码注释也明确表示 CSR 操作低频，宁愿牺牲几拍来避免 CSR 流水复杂性。

## 对 00_rv32i_basic 的启发

如果当前设计希望保留 EX 级 CSR 直接写，那么需要实现备忘录方案一：从 MEM exception 到 EX CSR write enable 的组合屏蔽，并把这条路径作为时序重点审查。

如果希望学习 bi-RISC-V 的做法，可以改成：

- EX 级 CSR 单元仅读 CSR、计算 `csr_wdata`、产生 CSR 早期异常。
- 在 EX/MEM、MEM/WB 流水寄存器中携带 `csr_we/csr_addr/csr_wdata/csr_exception`。
- WB 级统一提交 CSR 写和异常写；异常优先级高于普通 CSR 写。
- 对 CSR 指令做简单序列化，直到 WB 后再允许下一条 CSR 进入 EX。这样可以暂时不做 CSR forwarding。

对于教学型五级流水，推荐的折中路线是：

1. 短期：采用 MEM exception 组合强杀 EX CSR 写，改动最小。
2. 中期：迁移到 bi-RISC-V 风格的 WB CSR commit，并先用 CSR 序列化避免 bypass。
3. 长期：如果要提升 CSR IPC，再补 CSR WB->EX forwarding 或更完整的提交/scoreboard 机制。

