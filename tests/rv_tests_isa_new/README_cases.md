# ISA 用例说明

本文档用于记录需要额外说明的 ISA 用例，后续可继续追加。

## 版本记录

- 2026-09-06 v0.2：新增 `rv32ui-p-ld_st` 用例说明。
- 2026-06-22 v0.1：最初版，新增 `rv32ui-p-ma_data` 用例说明。

## rv32ui-p-ld_st

- 综合测试对齐的整数 load/store：`sb/lb/lbu`、`sh/lh/lhu` 和 `sw/lw`，覆盖不同合法 byte lane、
  halfword/word offset及多组数据 pattern。
- 检查 byte/halfword 写 mask、读回数据选择，以及 `lb/lh` 的符号扩展和 `lbu/lhu` 的零扩展。
- 每个子测试包含紧邻的 store→load、load→store、load→compare等相关序列；还会先从内存加载指针，
  随即把该指针作为下一次访存的基地址，因此会直接检查 load-use interlock/forwarding、response metadata
  对齐和 store副作用是否正确。
- `gp/x3` 保存当前子测试编号，任一读回或地址结果不匹配便跳到 `fail`；全部子测试通过后进入
  `pass`。该用例只测试按访问宽度合法对齐的地址，不测试非对齐 halfword/word访问。

## rv32ui-p-ma_data

- 测试 `lh/lhu/lw/sh/sw` 的非对齐数据访问，例如访问 `base+1`、`base+2`、`base+3`。
- 该用例期望核能够完成非对齐访问，并读写出正确的按字节拼接结果。
- 对不支持非对齐访问的核，抛出 load/store address-misaligned exception 在架构上允许，但该用例会判 fail。
- 如果当前核明确不支持非对齐 halfword/word 访问，批量 ISA 测试中应跳过或标记该用例为 unsupported。
