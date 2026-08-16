# RV32IM v11 开发日志

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-16 22:06

---

## 开发记录

### 2026-08-16 23:30 — 基础动态分支预测器

- 完成 [`task_v11_01_dynamic_branch_prediction.md`](task_v11_01_dynamic_branch_prediction.md)：实现 16 项 BTB/BHT、预测元数据流水传递、EX/MA fire 一次性训练/恢复、`fence.i` 失效及 v11 filelist 隔离。
- 独立 DV 的预测器开关单测、前端握手测试和 BPU SVA PASS；`beq` 统计为 73 次控制流训练、36 次恢复、37 次正确预测。
- `BPU_ENABLE=1/0` 均通过公共验收：ISA `rv32ui` 41/42（仅既有 `ma_data`）、`rv32um` 8/8；Compliance `rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1。DC `make check` PASS，未执行完整综合。
