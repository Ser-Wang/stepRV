# RTL 调整方案：支持 rv32i 异常类 compliance 用例

作者：Codex | Chat-GPT 5.5 medium
时间戳：2026-06-22 23:29:17 CST
版本记录：
- v0.4：补充异常/trap 信号命名与 redirect 归属重构。
- v0.3：记录本轮 RTL 实现与验证结果。
- v0.2：修正 `I-MISALIGN_JMP-01` 的 `mcause` 说明。
- v0.1：最初版。

## 调整目的

当前 `make sim_isa_all type=compli group=rv32i` 中有 4 个异常相关用例失败。调整目标是补齐最小必要的同步异常/trap 支持，使核能够在 `ebreak`、`ecall`、非对齐跳转、非对齐 load/store 时写入正确 CSR，跳转到 `mtvec`，并通过 `mret` 返回，从而让 compliance signature 与 `.ref` 匹配。

## 目标行为

- `I-EBREAK-01`：执行 `ebreak` 时触发 breakpoint exception，`mcause=3`。
- `I-ECALL-01`：M-mode 执行 `ecall` 时触发 environment call exception，`mcause=11`。
- `I-MISALIGN_JMP-01`：跳转/分支目标地址非 4 字节对齐时触发 instruction address misaligned exception，`mcause=0`，`mtval=异常目标地址`。
- `I-MISALIGN_LDST-01`：非对齐 load 触发 `mcause=4`，非对齐 store 触发 `mcause=6`，`mtval=异常访存地址`。

## RTL 调整建议

1. IDU 增加 SYSTEM 指令细分译码。
   - 独立识别 `ecall`、`ebreak`、`mret`。
   - 避免把它们只归入一个未派发的 system 类指令后被流水线吞掉。

2. 增加统一异常请求通路。
   - 在 ID/EX/LSU/BRU 相关路径产生 `exc_valid`、`exc_cause`、`exc_tval`、`exc_epc`。
   - 建议优先级：已有异常优先于普通写回和普通跳转，保证精确异常。

3. CSR 增加硬件异常写入能力。
   - `mcause <= exc_cause`。
   - `mepc <= exc_epc`，通常为触发异常的指令 PC。
   - `mtval <= exc_tval`，jump misalign 写目标 PC，load/store misalign 写访存地址。
   - 保留现有 CSR 指令读写路径，并处理硬件异常写和 CSR 指令写的优先级。

4. Trap 控制流与流水线 flush。
   - 异常发生时 flush 后续错误指令。
   - 下一取指 PC 重定向到 `mtvec`。
   - `mret` 执行时下一取指 PC 重定向到 `mepc`。

5. BRU 增加跳转目标非对齐检测。
   - 对实际 taken 的 branch/jal/jalr 检查目标地址。
   - 目标非对齐时不上报普通跳转成功，而是发出 instruction address misaligned exception。

6. LSU 增加非对齐异常上报。
   - `lw/sw` 要求 `addr[1:0]==0`，否则上报 load/store misalign。
   - `lh/lhu/sh` 要求 `addr[0]==0`，否则上报 load/store misalign。
   - 抛异常时禁止实际 dmem 写入，避免错误副作用。

## 验证建议

- 单独运行 `make sim_compli test=I-EBREAK-01` 和 `make sim_compli test=I-ECALL-01`，先打通最小 trap/return。
- 再运行 `I-MISALIGN_JMP-01`，确认 `mcause=0` 与 `mtval[1:0]` 被 handler 正确记录。
- 最后运行 `I-MISALIGN_LDST-01`，确认非对齐 load/store 分别写出 `mcause=4/6`。
- 四个单测通过后，再运行 `make sim_isa_all type=compli group=rv32i` 回归。

## 2026-06-22 实现记录

- 已在 CSR 控制通路中加入 `ecall`、`ebreak`、`mret` 派发。
- 已增加硬件 trap 写入 `mepc/mcause/mtval`，并通过 `mtvec` 与 `mepc` 实现 trap/mret PC 重定向。
- 已增加 BRU 跳转目标非对齐检测，`jalr` 先清 bit0 后再检查 4 字节对齐。
- 已增加 LSU 非对齐 load/store 异常上报，并在异常时禁止错误写回/写内存副作用。
- 已支持 `misa` 只读常量 `0x40000100`，用于 `I-MISALIGN_JMP-01` 中的 `csrci misa,4`。
- 已验证通过：`I-EBREAK-01`、`I-ECALL-01`、`I-MISALIGN_JMP-01`、`I-MISALIGN_LDST-01`、`I-ADD-01`。
- 进一步代表性回归运行时遇到 VCS runtime license 暂时不可用，需要 license 恢复后继续补跑。

## 2026-06-22 v0.4 重构记录

- 调整目的：让异常、trap-return、普通分支跳转都先在 EXU 内部完成 redirect 仲裁，core 顶层只接收统一 `redirect_req/redirect_pcnext`，为后续 cache、debug、interrupt、预测恢复等来源保留单一扩展口。
- 信号命名按“主对象/信息类型/异常类型/来源”组织，例如 `exc_req_instr_addr_misaligned_bru`、`exc_tval_addr_misaligned_lsu`、`exc_req_illegal_csr_access`，避免把 `bru/lsu/csr` 放在最前面掩盖异常语义。
- CSR/SYSTEM 执行事件不再使用 `valid` 后缀，改为 `csr_op_req`、`exc_req_ecall`、`exc_req_ebreak`、`trap_ret_req_mret`，表示 EXU 当前实际发起 CSR 操作、同步异常或 trap return。
- `ifu` 与 `ctrl_hazard` 的入口从 `jump_flag/pc_next_bru` 语义改为 `redirect_req/redirect_pcnext` 语义，避免把 trap/mret/debug 等非 branch 控制流误归类为普通 branch。
- 当前仍保持原有单发射、顺序流水结构；CSR 状态更新集中在 `csr_regs`，后续若扩展多发射或乱序，可进一步把该路径演进为独立 CSR/Trap/Privileged Unit，并在 commit/retire 点串行化特权状态更新。
- 重构后已运行 `make -f makefile sim_isa_all type=compli group=rv32i`，结果为 `48/48 Passed`，包含此前失败的 `I-EBREAK-01`、`I-ECALL-01`、`I-MISALIGN_JMP-01`、`I-MISALIGN_LDST-01`。
