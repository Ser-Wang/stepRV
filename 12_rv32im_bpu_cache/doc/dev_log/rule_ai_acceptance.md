# AI 开发通用验收要求

AI/Agent 完成 RTL 开发或修复后，必须执行本文件规定的公共回归。任务工单要求的定向测试、
断言检查或其他专项验证应在此基础上追加，不能替代公共回归。

在 `work/my-RISCV-Projs/sim` 路径运行以下测试，并显式指定当前设计版本：

```text
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../11_rv32im_bpu

make sim_isa_all type=compli group=rv32i DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../11_rv32im_bpu
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../11_rv32im_bpu
```

验收标准：

- ISA 回归：`rv32ui` 允许且仅允许既有 `ma_data` 用例 FAIL，其余用例必须 PASS；
  `rv32um` 必须全部 PASS。
- Compliance 回归：`rv32i`、`rv32im`、`rv32Zicsr`、`rv32Zifencei` 必须全部 PASS。
- 不得出现新的仿真、SVA 或断言失败。

开发日志中的公共回归结果保持简短，按以下顺序汇总即可：

```text
ISA：rv32ui 41/42 PASS（仅允许的既有 ma_data FAIL），rv32um 8/8 PASS。
Compliance：rv32i 48/48、rv32im 8/8、rv32Zicsr 6/6、rv32Zifencei 1/1 PASS。
```
