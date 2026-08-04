# task_v10_02：RV32IM M 扩展乘法器 RTL 架构工单

作者：GPT-5 Codex | thinking: high | agent: Codex
时间戳：2026-07-07 19:20 CST
状态：ready-for-rtl-gen

## 版本更新 log

- v0.1，2026-07-07 19:20 CST：结合现有 `de/core` 流水线和 `devSpec_mExten_multiplier_guidance.md`，形成乘法器 Phase 1 RTL 实施架构任务。

## 1. Architecture scope

本工单面向 `work/my-RISCV-Projs/10_rv32im/de` 的 RV32 顺序单发射流水核，在已有 `task_v10_01_vld_rdy.md` valid/ready 骨架基础上加入整数乘法功能。

当前阶段只实现乘法子集：

- `MUL`
- `MULH`
- `MULHSU`
- `MULHU`

该阶段应声明为 Zmmul 乘法子集，不声明完整 RV32M。`DIV/DIVU/REM/REMU` 保持未实现，后续另立除法器工单。

指导 SPEC：

- `doc/dev_log/devSpec_mExten_multiplier_guidance.md`

现有设计观察：

- 流水线为 `IFU -> IDU -> EXU -> MAU -> WBU`。
- `idu.sv` 已经解出 `dec_rv32m_mul/mulh/mulhsu/mulhu/div/divu/rem/remu`，但当前 `dec_oper_dispatch_alu` 排除了 `func7=0000001`，因此 M 指令不会进入可执行 datapath。
- `exu.sv` 已经有 ID/EX 和 EX/MA valid/ready，当前 `ex_result_done = 1'b1`，尚无多周期执行单元。
- 写回和 forwarding 走 `EXU -> MAU -> WBU -> regfile`，MAU forwarding 数据为 `r_wb_data_exu_d1`，WBU forwarding 数据为 `wb_data_wbu`。
- redirect/exception 由 EX 级产生，`ctrl_hazard.sv` 对 redirect flush IF/ID 和 ID/EX。

## 2. RTL framework

采用可替换实现的 MDU/乘法器分层：

```text
exu.sv
└── exu_mul.sv              // EX 集成封装，拥有请求一次性发射、响应接入、kill 映射
    └── mul_unit.sv         // 稳定 req/rsp 公共封装，可参数选择实现
        └── mul_radix2.sv   // Phase 1 默认实现，32 次迭代
```

Phase 1 只要求 `mul_radix2.sv`。`mul_unit.sv` 的端口语义必须稳定，为后续 Phase 2 17x17 MAC 替换内部实现预留边界。不要把乘法器算法直接写入 `exu.sv`。

推荐文件：

- `de/core/exu_mul.sv`
- `de/core/mul_unit.sv`
- `de/core/mul_radix2.sv`

可选做法：

- Phase 1 若希望减少文件数量，可以先合并 `mul_unit.sv` 和 `mul_radix2.sv`，但必须保持外部 req/rsp/kill 协议不变，并在文件内清楚分隔公共封装与算法状态机。

## 3. Module responsibilities

### `idu.sv`

负责把四条乘法指令分派到新的 MDU group 或等价 ALU-MUL 子类型。

建议扩展 `config.v`：

- 增加 `DECINFO_GRP_MDU`，值建议为 `3'd4`。
- 增加 MDU 子字段：
  - `DECINFO_MDU_MUL`
  - `DECINFO_MDU_MULH`
  - `DECINFO_MDU_MULHSU`
  - `DECINFO_MDU_MULHU`
  - 可预留 `DECINFO_MDU_DIV/DIVU/REM/REMU`，但本阶段不要执行。
- `DECINFO_BUS_WIDTH` 仍可保持为 CSR 的 28 位最大宽度，只要 MDU bus 不超过该宽度。

`idu.sv` 修改点：

- `dec_oper_dispatch_mdu = dec_rv32m_mul | dec_rv32m_mulh | dec_rv32m_mulhsu | dec_rv32m_mulhu`。
- `dec_oper_dispatch_alu` 保持排除 `func7=0000001`。
- `dec_oper_dispatch_*` 最终 OR 中加入 MDU bus。
- 对 `DIV/DIVU/REM/REMU` 当前不要 silently 当作 NOP。建议按现有异常机制补 illegal instruction 之前，先保持不分派且记录风险；更优实现是新增非法指令异常，但这会超出乘法器最小闭环。

不负责：

- 不在 IDU 内决定 stall、busy 或乘法周期数。
- 不在 IDU 内生成乘法结果。

### `exu.sv`

负责把 MDU 分派接入 EX 级长延时框架。

核心修改：

- 增加 `req_disp_mdu = r_ex_vld & (r_dec_info_bus_ex[DECINFO_GRP] == DECINFO_GRP_MDU)`。
- 增加 `dec_info_bus_mdu` 切片。
- 将 `ex_result_done` 从常 1 改为：

```verilog
wire ex_result_done = req_disp_mdu ? mul_rsp_vld : 1'b1;
```

- `o_ex_ma_vld = r_ex_vld & ex_result_done` 保持语义。
- `o_id_ex_rdy = !r_ex_vld | (i_ex_ma_rdy & ex_result_done & !i_stall)` 保持作为上游反压出口。
- `o_wb_data_exu` 增加 MDU 结果 mux：

```verilog
assign o_wb_data_exu =
    ({`XLEN{req_disp_alu}} & alu_wb_data)
  | ({`XLEN{req_disp_bru}} & bru_wb_data)
  | ({`XLEN{req_disp_csr}} & csr_wb_data)
  | ({`XLEN{req_disp_mdu}} & mul_rsp_result);
```

请求一次性发射：

- EX 中同一条乘法指令停留 30+ 周期，必须新增 `r_mdu_req_issued` 或等价状态。
- `mul_req_vld = req_disp_mdu & !r_mdu_req_issued & !i_flush`。
- 当 `mul_req_vld & mul_req_rdy` 时置位 `r_mdu_req_issued`。
- 当当前 EX payload 被 flush/kill 或成功离开 EX/MA 时清 `r_mdu_req_issued`。
- 不允许用 `req_disp_mdu` 直接驱动 `mul_req_vld`，否则会重复发起同一指令。

响应接入：

- `mul_rsp_rdy = req_disp_mdu & r_ex_vld & i_ex_ma_rdy`。
- 当 `mul_rsp_vld=1` 但 `i_ex_ma_rdy=0` 时，EX 继续保持当前指令，乘法器内部必须保持响应结果。
- 乘法结果进入正常 `o_wb_data_exu`，再由 MAU/WBU 复用既有写回和 forwarding。

kill 映射：

- `mul_kill = i_flush | (req_disp_mdu & r_ex_vld & o_redirect_req)` 不建议直接使用完整全局 redirect，因为当前 EX 指令自身产生 redirect 时不应 kill 自己的已完成结果。
- Phase 1 最小实现建议：`mul_kill = i_flush`，因为现有 redirect flush 只作用 IF/ID 与 ID/EX，不会 flush EX 本级。旧指令异常/中断 kill 在后续精确异常工单中补充。
- 若后续新增“older instruction kills EX”场景，必须在 EX 集成层生成事务限定 kill，而不是让乘法器自行解释全局 flush。

不负责：

- 不在 `exu.sv` 内写 Radix-2 迭代状态机。
- 不从乘法器内部中间结果 forwarding。

### `exu_mul.sv`

负责 EX 级乘法请求语义与乘法器公共协议之间的薄封装。

端口建议：

```verilog
module exu_mul(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_req_vld,
    output wire        o_req_rdy,
    input  wire [3:0]  i_req_op,
    input  wire [31:0] i_req_rs1,
    input  wire [31:0] i_req_rs2,
    input  wire        i_rsp_rdy,
    output wire        o_rsp_vld,
    output wire [31:0] o_rsp_result,
    input  wire        i_kill
);
```

`i_req_op` 可直接使用四个 one-hot 操作位，也可使用 2-bit enum：

- `00` MUL
- `01` MULH
- `10` MULHSU
- `11` MULHU

若使用 2-bit enum，需要在 `config.v` 中定义宏，避免 magic number。

### `mul_unit.sv`

负责稳定的乘法器外部协议：

- 单请求在途。
- `req_rdy` 只在空闲且无待消费响应时为 1。
- `rsp_vld && !rsp_rdy` 时保持 `rsp_result` 稳定。
- `kill` 可取消计算中请求和 RESPONSE 中响应。
- reset/kill 优先级为 `reset > kill > rsp_fire > req_fire > normal advance`。

Phase 2 替换 17x17 MAC 时只改 `mul_unit` 内部实例或参数，不改 `exu.sv` 与 `exu_mul.sv` 的协议。

### `mul_radix2.sv`

负责 Phase 1 Radix-2 迭代算法。

状态机：

```text
IDLE
PREPARE
ITERATE
FINAL
RESPONSE
```

寄存器建议：

```text
raw_operand_a_q[31:0]
raw_operand_b_q[31:0]
op_q
multiplicand_q[31:0]
multiplier_q[31:0]
acc_q[32:0]
iter_count_q[5:0]
result_neg_q
rsp_result_q[31:0]
```

算法要求：

- Phase 1 固定 32 次迭代，不做提前退出。
- 使用幅值化 + 无符号乘法 + FINAL 状态补码修正。
- `MUL` 按无符号低 32 位处理。
- `MULH` 为 signed x signed 高 32 位。
- `MULHSU` 为 signed x unsigned 高 32 位。
- `MULHU` 为 unsigned x unsigned 高 32 位。
- FINAL 状态独立完成 64 位符号修正和高/低位选择，不与最后一次迭代组合在同一周期。

不允许：

- 不共享普通 ALU 加法器。
- 不生成 64 位每周期部分积加法路径。
- 不做 Radix-4、Booth、17x17 MAC、提前退出或多请求队列。

## 4. Internal interface and parameter plan

### Decode bus

建议新增 group，而不是把乘法挤进 ALU group：

```text
DECINFO_GRP_MDU
DECINFO_BUS_MDU_WIDTH
DECINFO_MDU_MUL
DECINFO_MDU_MULH
DECINFO_MDU_MULHSU
DECINFO_MDU_MULHU
```

原因：

- 普通 ALU 是组合单周期，MDU 是多周期 req/rsp。
- 独立 group 能让 `ex_result_done`、请求一次性发射、kill 和后续 DIV/REM 边界更清晰。
- 后续 DIV/REM 可复用 MDU group，不需要再次破坏 ALU group。

### EX/MUL req-rsp

协议：

```text
mul_req_fire = mul_req_vld && mul_req_rdy
mul_rsp_fire = mul_rsp_vld && mul_rsp_rdy
```

EX 到乘法器：

- `req_vld`：仅同一 EX 乘法 payload 第一次发射。
- `req_rdy`：乘法器空闲。
- `req_op`：四条乘法操作之一。
- `req_operand_a/b`：使用 forwarding 后的 `rs1_fwded/rs2_fwded`。

乘法器到 EX：

- `rsp_vld`：结果寄存器有效。
- `rsp_rdy`：EX/MA 能接收当前乘法指令。
- `rsp_result`：已寄存 32 位结果。

### Pipeline result

乘法结果只作为 EX 结果 mux 的一个输入，复用：

- `o_wb_data_exu`
- `mau.sv` pass-through
- `wbu.sv` RF writeback
- `ctrl_hazard.sv` 既有 MAU/WBU forwarding

禁止从 `mul_radix2` 的 `acc_q/multiplier_q` 或 FINAL 组合结果直接前递。

### Parameter ownership

- `XLEN` 继续由 `config.v` 定义为 32。
- 乘法器当前固定 RV32，不建议引入泛化 `XLEN` 参数，除非同时补完整位宽验证。
- 实现选择可预留：

```verilog
`define MDU_MUL_IMPL_RADIX2 1
```

但 Phase 1 可以直接实例化 Radix-2，避免过早配置复杂度。

## 5. Reset, clock, and CDC ownership

时钟与复位：

- 全部在 `clk` 单时钟域。
- 复位沿用现有风格：`posedge clk or negedge rst_n`，异步低有效复位。
- `mul_unit/mul_radix2/exu_mul` 均不引入新 clock，不实例化手工 clock gate。

CDC：

- 当前无 CDC。
- 不允许为乘法器单独引入派生时钟或异步启动脉冲。

reset 行为：

- EX valid 清零时不得保留可见 MDU 响应。
- 乘法器 reset 后进入 IDLE，`req_rdy=1`，`rsp_vld=0`，`rsp_result` 可为 0。

flush/kill：

- `i_flush` 清 EX payload 时必须同步清 `r_mdu_req_issued` 并向乘法器发 `kill`。
- `kill` 后乘法器不得产生幽灵响应。

## 6. Scaffold direction

### Arithmetic slice

Phase 1 实现 Radix-2：

```text
acc_add = acc_q + (multiplier_q[0] ? {1'b0, multiplicand_q} : 33'b0)
{acc_q, multiplier_q} <= {acc_add, multiplier_q} >> 1
```

计算周期：

- PREPARE：1 周期。
- ITERATE：32 周期。
- FINAL：1 周期。
- RESPONSE：等待 EX/MA ready，不计入固定计算周期。

### Control slice

控制优先级：

```text
reset > kill/flush > rsp_fire > req_fire > normal advance
```

EX 级保持：

- 乘法请求发出后，`r_ex_vld` 保持为 1。
- `o_id_ex_rdy=0`，自然反压 ID/IF。
- `o_ex_ma_vld=0`，直到 `mul_rsp_vld=1`。
- 响应有效且 `i_ex_ma_rdy=1` 时，乘法指令向 MAU 前进。

### Interface slice

新增 MDU 不改变 `core.sv` 顶层 IO，不改变 DTCM/ITCM/SoC bus。

需要更新：

- `filelists/filelist_rtl.f` 加入新增 RTL 文件。
- 若仿真 filelist 分开维护，同步加入新增文件。

### Memory slice

乘法器不访问 memory。

需验证乘法结果可用于：

- store data
- load/store address
- branch compare

这些依赖应走既有 forwarding/stall 机制，不在 MDU 中特殊处理。

## 7. Implementation order

1. 扩展 `config.v` 的 `DECINFO_GRP_MDU` 和 MDU decinfo 字段。
2. 修改 `idu.sv`，四条乘法指令进入 MDU group，DIV/REM 暂不执行并记录非法指令风险。
3. 新建 `mul_radix2.sv`，先完成独立 req/rsp/kill 状态机。
4. 新建 `mul_unit.sv` 或等价公共封装，实例化 Radix-2，实现稳定接口。
5. 新建 `exu_mul.sv`，把 MDU op 与 `mul_unit` 协议封装起来。
6. 修改 `exu.sv`：
   - 增加 MDU dispatch。
   - 增加 `r_mdu_req_issued`。
   - 接入 `ex_result_done`。
   - 接入 `o_wb_data_exu` mux。
   - 接入 flush/kill 清理。
7. 更新 filelist。
8. 加模块级 testbench 或复用现有 DV 框架加入乘法 directed/random 测试。
9. 运行现有 RV32I/Zicsr/Zifencei 回归，确认没有破坏原功能。
10. 运行乘法处理器级测试，再做综合基线。

## 8. Verification task list

### 模块级

定向操作数至少覆盖：

```text
0x00000000
0x00000001
0xffffffff
0x7fffffff
0x80000000
0x80000001
0x0000ffff
0x00010000
0xffff0000
```

每条指令覆盖：

- `0 * X`
- `1 * X`
- `-1 * X`
- `INT_MIN * -1`
- `INT_MIN * INT_MIN`
- `INT_MAX * INT_MAX`
- `UINT_MAX * UINT_MAX`
- `MULHSU` 中 A 为负、B 大于 `INT_MAX`
- 低 32 位全 0 且高 32 位非 0
- 高 32 位全 1 的负乘积

随机测试：

- 每个 opcode 不少于 10,000 组。
- 参考模型必须先形成完整 64 位乘积，再选择 high/low 32。

协议测试：

- busy 时 `req_rdy=0`。
- `rsp_vld && !rsp_rdy` 时结果稳定。
- RESPONSE 后立即接下一请求。
- PREPARE/ITERATE/FINAL/RESPONSE 中 kill。
- reset 发生在每个状态。
- 同一 EX 指令只发一次 request。

### 处理器级

必须覆盖：

- 四条乘法指令写回。
- 写 `x0`。
- back-to-back 乘法。
- 乘法结果被下一条指令立即使用。
- 乘法结果作为 branch 比较源。
- 乘法结果作为 load/store 地址。
- 乘法结果作为 store data。
- 乘法前后夹 load/store。
- 分支 flush 与乘法请求边界。

### 建议断言

```systemverilog
// response hold
rsp_vld && !rsp_rdy |=> rsp_vld && $stable(rsp_result);

// no new request while busy
busy |-> !req_rdy;

// kill clears visible response until next accepted request
kill |=> !rsp_vld until_with req_fire;

// Phase 1 fixed iteration count
state_q == ITERATE && !kill |-> iter_count_q <= 6'd31;
```

断言文件位置可参考现有 `dv/sva_*.sv` 风格。

## 9. Synthesis and timing acceptance

目标：

- 55 nm SS 库。
- 75 MHz。
- period = 13.333 ns。
- 顶层完整核 WNS >= 0，TNS = 0。

必须检查：

- `mul_radix2` 内部 33 位加法路径。
- `req_operand` 到内部请求寄存器路径。
- `rsp_result_q` 到 EX/MEM 或 MAU pipe register 路径。
- `o_wb_data_exu` mux 是否扩大普通 ALU 关键路径。
- forwarding 路径是否意外串入乘法器组合逻辑。
- kill、状态译码和 `r_mdu_req_issued` 是否形成高扇出控制路径。

Phase 1 合入后保存：

- 总组合面积。
- 乘法器模块组合面积。
- 寄存器面积。
- WNS/TNS。
- 最差路径起点/终点/逻辑组成。
- 每条乘法指令固定计算周期。
- back-to-back 乘法总周期。

## 10. Architecture risks

### R1：非法 M 指令异常尚未完善

严重度：medium

`idu.sv` 已经能识别 DIV/REM，但本工单不实现。若它们既不分派也不触发 illegal instruction，软件执行除法时可能表现为无效写回或流水异常。建议后续在 ID/EX 异常路径补 illegal instruction，再声明未支持 DIV/REM。

### R2：EX 自身 redirect 与 MDU kill 语义不能混淆

严重度：high

现有 redirect flush younger stages，不 flush EX 本级。乘法器 kill 初版应只接 `i_flush`，不要直接接全局 `redirect_req_exu`，否则 EX 中已完成或正在提交的指令可能被错误 kill。

### R3：`r_mdu_req_issued` 是必须状态

严重度：high

EX 乘法 payload 会停留多个周期。若没有 request-issued 状态，同一指令会每拍重复发起请求，轻则乘法器拒绝导致协议混乱，重则重复覆盖请求。

### R4：MAU forwarding 对 load 的历史假设仍需保持

严重度：medium

乘法结果可经 MAU forwarding，但 load-use 仍依赖 hazard stall，不能把 MAU 的 pass-through 数据误用于 load 结果前递。新增 MDU 不应改变 `ctrl_hazard.sv` 现有 load-use 判定。

### R5：CSR/trap 精确提交仍是后续架构债

严重度：medium

当前 CSR side effect 仍偏 EX 阶段，乘法器期间中断/旧异常 kill 的精确定义不完整。本工单只实现同步流水内的乘法功能，不解决完整精确异常/中断进入策略。

## 11. Done criteria

Phase 1 RTL 可视为完成需要同时满足：

- 四条乘法指令功能正确。
- EX 乘法期间能自然反压 ID/IF，不重复请求。
- 乘法结果经 MAU/WBU 正常写回和 forwarding。
- `rsp_vld` 反压保持稳定。
- flush/kill 后无幽灵响应。
- 现有 RV32I 回归不退化。
- 乘法 directed/random/protocol 测试通过。
- 处理器级依赖测试通过。
- SS 75 MHz 综合通过并保存报告。

## 12. Recommended next step

下一步建议使用 `frontend-rtl-gen` 生成：

- `exu_mul.sv`
- `mul_unit.sv`
- `mul_radix2.sv`
- `config.v/idu.sv/exu.sv/filelist` 的最小补丁

并同步准备模块级和处理器级乘法测试。测试生成可与 RTL 生成并行推进。
