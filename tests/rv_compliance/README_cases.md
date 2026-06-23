# Compliance 用例说明

作者：Codex  
时间戳：2026-06-22  
版本：v0.2，修正 `I-MISALIGN_JMP-01` 的 `mcause` 说明；v0.1 为最初版。

本文档用于记录需要额外说明的 RISC-V compliance 用例，后续可继续追加。

## I-EBREAK-01

- 测试 `ebreak` 是否触发 breakpoint exception。
- 期望硬件跳转到 `mtvec`，写入 `mcause=3`，trap handler 将 `mcause` 和保留寄存器值写入 signature。
- 当前若仅 decode 出 `ebreak`，但没有 dispatch/issue 到异常处理路径，该用例会 fail。

## I-ECALL-01

- 测试 M-mode 下 `ecall` 是否触发 environment call exception。
- 期望硬件跳转到 `mtvec`，写入 `mcause=11`，handler 记录异常信息后通过 `mret` 返回。
- 当前若 `ecall` 未被派发或没有 trap 控制流，该用例会 fail。

## I-MISALIGN_JMP-01

- 测试跳转/分支目标地址非对齐时是否抛出 instruction address misaligned exception。
- 该用例不是要求支持非对齐取指，而是期望对非对齐跳转目标抛异常。
- 期望记录 `mcause=0`，并在 `mtval` 中给出异常目标地址；handler 会先写 `mtval[1:0]`，再写 `mcause` 到 signature。
- `.ref` 中出现的 `00000002` 是 `mtval[1:0]`，表示目标地址低两位为 `2'b10`，不是 `mcause`。

## I-MISALIGN_LDST-01

- 测试非对齐 load/store 的处理，包括 `lw/lh/lhu/sw/sh` 在非对齐地址上的访问。
- 该 compliance 用例允许两类结果：对齐访问正常完成；非对齐 halfword/word 访问应抛 load/store address misaligned exception。
- 期望非对齐 load 记录 `mcause=4`，非对齐 store 记录 `mcause=6`，并记录 `mtval[1:0]`。
- 这与 `rv32ui-p-ma_data` 不同：`ma_data` 期望硬件完成非对齐访问；本用例期望或接受通过异常路径报告非对齐访问。
