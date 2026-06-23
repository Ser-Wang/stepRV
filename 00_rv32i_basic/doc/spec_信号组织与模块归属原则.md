# RTL 信号组织与模块归属原则

作者：Codex | Chat-GPT 5.5 medium
时间戳：2026-06-23 11:24:20 CST
版本记录：
- v0.1：最初版，记录当前 RV32I 小核面向未来扩展的模块划分与信号组织原则。

## 设计目标

当前核心仍是简单顺序单发射 RV32I，但信号和模块边界应尽量避免把未来复杂度锁死。后续若引入 cache、分支预测、异常/中断、debug、多发射甚至乱序执行，控制流重定向、CSR/trap 状态更新、精确异常提交点都会变得更重要。因此当前命名和归属要优先表达“事件语义”和“流水线职责”，而不是只表达某一条指令的局部行为。

## 模块归属

- `alu_unit`：负责 add/sub、logic、shift、compare 等普通整数运算，不处理特权状态和控制流副作用。
- `bru_unit`：负责 branch/jal/jalr/fence.i 的目标地址、条件判断，以及分支类指令自身可能产生的 instruction address misaligned exception。
- `lsu_unit`：负责 load/store 地址生成、写掩码、写数据整理，以及访存地址非对齐异常上报；异常发生时禁止错误 dmem 写副作用。
- `csr_trap_unit`：未来目标模块，统一负责 CSR 读写、`ecall`、`ebreak`、`mret`、同步异常入口、interrupt/debug 入口、trap return、特权状态更新。
- `redirect_arb`：负责统一仲裁所有会改变取指 PC 的事件，优先级建议为 trap/debug/interrupt/mret 高于 branch mispredict/fence/cache replay 等普通前端重定向。

## 当前落地方式

当前代码中还没有独立拆出完整 `csr_trap_unit`。为了少改现有架构，先把 `ecall`、`ebreak`、`mret` 与 CSR 指令一起放在 `exu_csr`/CSR 相关通路中处理：

- `ecall`、`ebreak` 不写 `rd`，它们是同步 exception 请求。
- `mret` 不作为普通 branch，它是 trap return 请求，目标 PC 来自 `mepc`。
- CSR 指令读写仍走 CSR 访问通路，并保持 CSR 读写规范。
- 硬件异常写 `mepc/mcause/mtval/mstatus` 的动作集中在 CSR 寄存器模块中。

这个阶段可以把 `exu_csr` 理解为 `csr_trap_unit` 的早期形态。后续当 interrupt、debug、权限级、更多 CSR、流水线提交点变复杂时，应将它正式演进为独立 `csr_trap_unit`，并把 CSR/trap 状态更新约束在 commit/retire 点。

## 信号组织

跨模块信号优先表达事件类型，再表达信息类型和来源，避免把来源模块放在最前面导致语义不清。

- 异常请求：`exc_req_*`
- 异常原因：`exc_cause_*`
- 异常附加信息：`exc_tval_*`
- trap return 请求：`trap_ret_req_*`
- CSR 操作请求：`csr_op_req`
- PC 重定向请求：`redirect_req`
- PC 重定向的下一个 PC：`redirect_pcnext`

推荐示例：

- `exc_req_ecall`
- `exc_req_ebreak`
- `exc_req_instr_addr_misaligned_bru`
- `exc_tval_addr_misaligned_lsu`
- `exc_req_illegal_csr_access`
- `trap_ret_req_mret`
- `redirect_req_bru`

`valid` 后缀只用于有效数据握手或 valid/ready 协议，不用于表示“当前执行到某条指令”。对于执行事件，优先使用 `req`、`op_req`、`ret_req`、`redirect_req` 等更接近实际动作的后缀。

## Redirect 语义

`jump` 适合描述 branch/jal/jalr 的局部指令行为，但不适合覆盖 trap、mret、debug、interrupt、prediction recovery 等控制流事件。跨模块统一使用 `redirect`，表示“流水线要求取指 PC 改道”。

当前建议：

- BRU 内部仍可使用 `jump_taken`、`branch_taken` 等直观指令语义。
- EXU/core/IFU 边界使用 `redirect_req/redirect_pcnext`。
- 所有 redirect 来源先在 EXU 或未来 redirect arb 中仲裁，再送到 IFU。

## 面向未来的理由

- 对 cache/前端 replay 友好：I-cache miss、ITLB miss、fence.i、预测恢复都可以作为 redirect 来源接入同一仲裁口。
- 对多发射友好：CSR/trap 指令可先设计为 serializing operation，阻塞后续特权状态相关操作，保证实现简单可靠。
- 对乱序友好：异常和 CSR 状态更新必须在 commit/retire 点生效，统一 `csr_trap_unit` 更容易维护精确异常。
- 对调试友好：看到 `exc_req_*`、`trap_ret_req_*`、`redirect_req_*` 能直接判断这是异常、trap return 还是 PC 重定向，而不是从 `jump_flag` 或 `valid` 反推真实含义。
