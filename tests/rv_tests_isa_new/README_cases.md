# ISA 用例说明

本文档用于记录需要额外说明的 ISA 用例，后续可继续追加。

## 版本记录

- 2026-06-22 v0.1：最初版，新增 `rv32ui-p-ma_data` 用例说明。

## rv32ui-p-ma_data

- 测试 `lh/lhu/lw/sh/sw` 的非对齐数据访问，例如访问 `base+1`、`base+2`、`base+3`。
- 该用例期望核能够完成非对齐访问，并读写出正确的按字节拼接结果。
- 对不支持非对齐访问的核，抛出 load/store address-misaligned exception 在架构上允许，但该用例会判 fail。
- 如果当前核明确不支持非对齐 halfword/word 访问，批量 ISA 测试中应跳过或标记该用例为 unsupported。
