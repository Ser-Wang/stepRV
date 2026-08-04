# RV32IM v10 开发日志

## 开发记录

### 2026-07-10 CST - M 扩展乘法器 Phase 2（Fast17）实现

> 工单：[task_v10_04_mext_mul_phase2_fast17.md](task_v10_04_mext_mul_phase2_fast17.md)

**完成内容：**

- 新增默认乘法器实现 `mul_fast17.sv`，采用单个 muxed 17x17 signed multiplier；
  `MUL` 为 3 个计算周期，`MULH`、`MULHSU`、`MULHU` 为 4 个计算周期。
- 保留 `mul_radix2.sv` 作为 Phase 1 基线实现。
- 新增 `exu_muldiv.sv`，直接路由乘法器与除法器；默认例化 `mul_fast17`，保留已注释的
  `mul_radix2` 例化以便对比切换。
- 移除 `mul_unit.sv` 与 `div_unit.sv` wrapper 层，并更新 RTL 与仿真 SRAM filelist。

**DV：**

- `rv32um` 8/8 PASS，`rv32im` 8/8 PASS。
- 基础回归：`rv32ui` 41/42 PASS（仅允许 `ma_data` FAIL）、`rv32i` 48/48 PASS、
  `rv32Zicsr` 6/6 PASS、`rv32Zifencei` 1/1 PASS。

**备注：** 未跑综合/时序。

---
### 2026-07-07 20:26 CST - M 扩展除法器实现

> 工单：[task_v10_03_mext_divider_impl.md](task_v10_03_mext_divider_impl.md)

**完成内容：**

- 实现 M 扩展除法器，新增 `div_radix2.sv` 和 `div_unit.sv`。
- 扩展 MDU decinfo，支持 `DIV`、`DIVU`、`REM` 和 `REMU`。
- 复用 EX 长延时 req/rsp 通路。

**DV：**

- `rv32um` 8/8 PASS，`rv32im` 8/8 PASS。
- 基础回归：`rv32ui` 41/42 PASS（仅允许 `ma_data` FAIL）、`rv32i` 48/48 PASS、
  `rv32Zicsr` 6/6 PASS、`rv32Zifencei` 1/1 PASS。

---
### 2026-07-07 20:12 CST - M 扩展乘法器 Phase 1 实现

> 工单：[task_v10_02_mext_multiplier_arch.md](task_v10_02_mext_multiplier_arch.md)

**完成内容：**

- 实现 M 扩展乘法器 Phase 1，新增 `exu_mul.sv`、`mul_unit.sv` 和
  `mul_radix2.sv`。
- 接入 `DECINFO_GRP_MDU` 与 EX 长延时反压机制。
- 修正长延时 EX 首拍的 forwarding gating。

**DV：**

- `rv32um` 与 `rv32im` 的四条乘法指令均通过测试；DIV/REM 当时尚未实现。
- 基础回归：`rv32ui` 41/42 PASS（仅允许 `ma_data` FAIL）、`rv32i` 48/48 PASS、
  `rv32Zicsr` 6/6 PASS、`rv32Zifencei` 1/1 PASS。

---
### 2026-07-07 17:34 CST - 显式 vld/rdy 握手骨架

> 工单：[task_v10_01_vld_rdy.md](task_v10_01_vld_rdy.md)

**完成内容：**

- 完成 `de/core` 显式 vld/rdy 握手骨架改造，并保留模块端口的 `i_/o_` 前缀。
- 增加 IF/ID、ID/EX、EX/MA、MA/WB、WB 的 valid/ready 信号。
- 为副作用增加 valid gating；此阶段尚未实现 M 扩展执行。

**DV：**

- `rv32ui` 仅允许 `ma_data` FAIL，`rv32i` 48/48 PASS。
- `Zicsr/Zifencei` 当前测试集 0/0。
