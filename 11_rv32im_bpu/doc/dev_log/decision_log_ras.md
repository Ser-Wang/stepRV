# RV32IM RAS 设计决策记录

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-18 22:44
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-08-18 22:44): 建立 RAS 决策记录，批准首版双完整栈实现，并登记后续 C906 共享 entry + 双 pointer 对比实验。

---

本文记录 `11_rv32im_bpu` 的 RAS 结构选择、原因、影响和后续实验安排。新决策按时间逆序添加；已经被替代的决策保留原文并标记状态，不直接删除。

## 决策记录

### RAS-001 — 首版采用双完整栈，后续对比 C906 风格

- **Date**: 2026-08-18 22:44
- **Decision State**: Accepted
- **Related SPEC**: [`dev_spec_return_address_stack.md`](dev_spec_return_address_stack.md)
- **Related Task**: [`task_v11_02_return_address_stack.md`](task_v11_02_return_address_stack.md)

#### 背景

RAS 需要在 IF 接受 call/return 时立即更新预测状态，同时在 EX 解析后保留一个不含年轻错路径操作的恢复基线。候选结构为：

1. 双完整栈：前端预测栈和后端确认栈分别保存完整 entry 与有效深度。
2. C906 风格：共享一份 entry，使用前端预测 pointer 和后端确认 pointer；redirect 主要恢复 pointer。

双完整栈能在 redirect 时恢复全部 entry 内容；共享 entry 方案面积更小，但深错路径 push 可能覆盖确认 pointer 仍会引用的 entry，恢复 pointer 后内容不一定精确恢复。这种污染只影响后续预测率，执行级仍可保证架构正确性。

#### 决策

- 首版实现采用双完整栈，文件名为 `de/core/ras_dual_full_stack.sv`，module 名为 `ras_dual_full_stack`。
- 默认深度 4；前端预测栈和后端确认栈各保存 4 × 32-bit 返回地址，并各自维护有效深度。
- redirect 时使用包含本拍 EX 确认动作的 `resolved_next`，并行恢复前端预测栈的全部 entry 和 count。
- 不使用含糊的通用实现名 `return_address_stack`，模块名必须直接反映内部结构。
- 后续另行实现 C906 风格模块，建议命名为 `ras_shared_entry_dual_pointer.sv` / `ras_shared_entry_dual_pointer`。
- 两种模块必须保持相同参数、端口和外部事件语义。IFU/EXU 不得读取实现内部状态，使实验切换只涉及实例 module 与 filelist，不修改流水控制逻辑。

#### 选择原因

- 首版优先保证错路径恢复语义明确、实现容易审查、定向验证能够逐项覆盖。
- 默认深度只有 4，双完整栈相对共享 32-bit entry 多出的主要状态为 4 × 32 = 128 bit，绝对规模可先接受，再由综合数据判断是否值得优化。
- 先建立精确恢复版本，可作为后续共享 entry 版本的功能与性能参照。

#### 已接受影响

- 双完整栈的返回地址存储为 2 × 4 × 32 = 256 bit，高于共享 32-bit entry 的 128 bit，也高于 C906 4 × 24-bit entry 的 96 bit。
- 两个 count 在默认深度 4 时各需要覆盖 0～4，其开销小于 entry 复制的主要开销。
- 全栈恢复在一个时钟沿并行完成，不是逐项多周期复制；综合后需检查恢复 mux 的面积、时序和翻转功耗。

#### 后续实验

完成 `ras_dual_full_stack` 后，另立工单实现 `ras_shared_entry_dual_pointer`，并在相同配置和工作负载下比较：

- 公共回归及 call/return、错路径、overflow 定向测试结果。
- return prediction recovery 次数和整体周期数。
- 深错路径 push 覆盖后的恢复精度与重新收敛行为。
- DC 综合的 cell area、关键路径和可获得的功耗指标。
- RTL 状态位、控制复杂度、SVA 数量及调试难度。

对比实验完成前，`ras_dual_full_stack` 是 v11 RAS 的基准实现；不得仅凭预估面积提前改成共享 entry 结构。
