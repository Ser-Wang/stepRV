# task_v10_04：M 扩展乘法器 Phase2 RTL 任务

状态：done

完成时间：2026-07-10 CST

## Result

- `mul_fast17.sv`：Phase2 默认实现，单个 muxed 17x17 signed multiplier，`MUL` 3 compute cycles，`MULH/MULHSU/MULHU` 4 compute cycles。
- `mul_radix2.sv`：Phase1 baseline 保留落盘。
- `exu_muldiv.sv`：M 扩展执行封装，直接路由 mul/div；默认例化 `mul_fast17`，保留已注释 `mul_radix2` 例化用于切换对比；直接例化 `div_radix2`。
- 已取消 `mul_unit.sv` / `div_unit.sv` wrapper 层。
- 已更新 `filelist_rtl.f` / `filelist_sim_sram.f`。

## Verified

```text
make sim_isa_all type=isa group=rv32um      -> 8/8 PASS
make sim_isa_all type=compli group=rv32im   -> 8/8 PASS
make sim_isa_all type=isa group=rv32ui      -> 41/42 PASS，仅允许 ma_data FAIL
make sim_isa_all type=compli group=rv32i    -> 48/48 PASS
make sim_isa_all type=compli group=rv32Zicsr    -> 6/6 PASS
make sim_isa_all type=compli group=rv32Zifencei -> 1/1 PASS
```

未跑综合/时序。

## Scope

- 保留 Phase1/Phase2 两个乘法器文件，通过 `exu_muldiv.sv` 中例化切换。
- 默认启用 `mul_fast17`，注释保留 `mul_radix2` 例化。
- `exu_muldiv.sv` 直接例化乘法器与除法器，不保留 `mul_unit/div_unit` 透传 wrapper。
- 保持现有端口、req/rsp/kill 协议、单请求在途、响应寄存语义不变。

## Required Behavior

- 支持 `MUL/MULH/MULHSU/MULHU`。
- `DIV/DIVU/REM/REMU` 不属于本任务。
- `req_rdy` 仅 IDLE 为 1。
- `rsp_vld && !rsp_rdy` 时保持 `rsp_result`。
- `i_kill` 取消计算和等待响应，回 IDLE，不产生幽灵响应。
- reset/kill 优先级高于响应握手和请求握手。

## Datapath

- 单个 17x17 signed multiplier expression，输入由状态 mux 选择。
- 32 位操作数拆分：
  - `a_l = A[15:0]`
  - `a_h = A[31:16]`
  - `b_l = B[15:0]`
  - `b_h = B[31:16]`
- 低半块始终 unsigned：`{1'b0, half_l}`。
- 高半块符号：
  - A signed for `MULH/MULHSU`
  - B signed for `MULH`
  - `MUL/MULHU` 高半块 unsigned。

## FSM

```text
IDLE
ALBL
ALBH
AHBL
AHBH
RESPONSE
```

- `ALBL`：计算 `A_L * B_L`，保存 `result_low16 = p[15:0]`，初始化 signed pending accumulator 为 `p[31:16]`。
- `ALBH`：累加 `A_L * B_H`。
- `AHBL`：累加 `A_H * B_L`。
  - 若 `MUL`，写 `rsp_result = {acc_next[15:0], result_low16}` 并进 `RESPONSE`。
  - 否则保存 `acc_next` 并进 `AHBH`。
- `AHBH`：计算 `A_H * B_H`，写 `rsp_result = ((acc_q >>> 16) + p)[31:0]` 并进 `RESPONSE`。

## Cycle Target

- `MUL`：3 个计算周期：`ALBL -> ALBH -> AHBL`。
- `MULH/MULHSU/MULHU`：4 个计算周期：`ALBL -> ALBH -> AHBL -> AHBH`。
- RESPONSE 等待下游 ready，不计入计算周期。

## Verification

必须通过：

```text
make sim_isa_all type=isa group=rv32um
make sim_isa_all type=compli group=rv32im
```

并确认基础回归不退化：

```text
make sim_isa_all type=isa group=rv32ui
make sim_isa_all type=compli group=rv32i
make sim_isa_all type=compli group=rv32Zicsr
make sim_isa_all type=compli group=rv32Zifencei
```

本任务不跑综合；不得因未跑综合而修改外部接口或放宽协议。
