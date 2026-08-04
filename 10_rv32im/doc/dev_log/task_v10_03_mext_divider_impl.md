# task_v10_03：RV32M 除法器实现 task

状态：ready-to-execute
输入 SPEC：`doc/dev_log/devSpec_mExten_divider_functional_guidance.md`
前置：乘法 MDU 已接入并通过四条 MUL 回归。

## Scope

实现 `DIV/DIVU/REM/REMU`，与现有 `MUL/MULH/MULHSU/MULHU` 一起完成 RV32M 功能闭环。

不跑综合/时序。本 task 只要求 RTL 功能与仿真回归。

## RTL work

1. `config.v`
   - 扩展 `DECINFO_MDU_DIV/DIVU/REM/REMU`。
   - MDU bus 容纳 8 个 one-hot op。
   - 定义除法 op enum，禁止 magic number。

2. `idu.sv`
   - `dec_oper_dispatch_mdu` 包含全部 8 条 M 指令。
   - `DIV/DIVU/REM/REMU` 不再作为 unsupported，不再屏蔽 rd 写回。

3. MDU wrapper
   - 复用现有 EX 长延时 req/rsp/kill 协议。
   - `exu.sv` 尽量不改协议，只继续看 `mdu_req_rdy/mdu_rsp_vld/mdu_wb_data`。
   - wrapper 根据 decinfo 将请求送入 mul 或 div，单请求在途。

4. 新增 `div_radix2.sv`
   - Radix-2 恢复式无符号核心，正常路径 32 轮。
   - 单请求在途，`rsp_vld && !rsp_rdy` 保持结果。
   - `kill` 立即回 IDLE，无幽灵响应。
   - 不使用 `/` 或 `%`。

5. ISA result
   - `DIV`: signed quotient, toward zero.
   - `DIVU`: unsigned quotient.
   - `REM`: signed remainder, sign follows rs1.
   - `REMU`: unsigned remainder.
   - divide by zero:
     - `DIV/DIVU -> 32'hffff_ffff`
     - `REM/REMU -> raw rs1`
   - signed overflow `0x8000_0000 / 0xffff_ffff`:
     - `DIV -> 0x8000_0000`
     - `REM -> 0`

6. Filelist
   - 新增 divider RTL 必须加入 `filelist_rtl.f` 和 `filelist_sim_sram.f`。

## Verification

必须跑：

```text
make sim_isa_all type=isa group=rv32um
make sim_isa_all type=compli group=rv32im
make sim_isa_all type=isa group=rv32ui
make sim_isa_all type=compli group=rv32i
make sim_isa_all type=compli group=rv32Zicsr
make sim_isa_all type=compli group=rv32Zifencei
```

Pass criteria：

- `rv32um`: 8/8 PASS。
- `rv32im`: 8/8 PASS。
- `rv32ui`: 仅允许 `ma_data` FAIL。
- `rv32i/rv32Zicsr/rv32Zifencei`: 全 PASS。

## Risks

- 首拍 request operand 必须使用 forwarding 后的 `mdu_rs1/mdu_rs2`。
- EX 中同一 MDU 指令只允许发一次 request。
- 特殊情况结果不得再做符号修正。
- `REM` 符号跟 rs1，不跟 rs2。
- 除零不是异常。
