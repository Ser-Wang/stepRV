# ITCM/DTCM SRAM 化迭代影响分析

本文基于 `doc/readme.md` 和当前 `de/` RTL，对下一步将 ITCM/DTCM 从组合读 TCM 模型收敛为同步读 SRAM/BRAM 友好接口的影响进行分析。本文只作为下一轮 RTL 修改指导，不包含 RTL 变更。

## 当前基线

当前 SoC 结构为：

```text
soc_top_v0
  |-- core_rv32i_v0
  |-- soc_bus_v0
  |-- mem_itcm
  |-- mem_dtcm
  `-- uart
```

当前存储模型的关键假设是“组合读、同步写”：

- `mem_itcm` 取指端口 `i_rd_addr -> o_rd_data` 为组合读。
- `mem_itcm` 临时数据端口 `i_wr_addr -> o_data_rd_data` 也为组合读，写入同步。
- `mem_dtcm` `i_addr -> o_rd_data` 为组合读，写入同步。
- `mau` 将 EXU 的 LSU 地址/写控制打一拍后输出到 SoC bus；在组合读 DTCM 下，同一 MAU 周期即可用 `i_mem_rd_data_mau` 生成 load 写回数据。

这套时序成立的核心原因是：地址在某个流水级稳定后，数据无需等下一拍即可返回。改成 SRAM 同步读后，读数据天然晚一拍，因此需要让“读地址提前一拍发出”。

本次补充后的目标是：DTCM 的读、写地址都在 EXU 级给出，SRAM 在 EXU/MEM 边界采样请求，MEM 级获得 `rd_data`。这样 DTCM load 的可用级仍等效于当前组合读模型下的 MAU/MEM 级，load-use 继续只 stall 一拍，forwarding 策略也尽量保持当前结构。

## 目标时序建议

建议先按固定 1-cycle SRAM 读延迟收敛，不引入 ready/valid 可变等待：

| 路径 | 当前 | 建议目标 |
| --- | --- | --- |
| ITCM 取指读地址 | `pc_r` | `pc_next` 或等价的 fetch request PC |
| ITCM 取指返回数据 | 地址同周期组合返回 | 下一拍返回，需要配套返回 PC/valid |
| DTCM 数据读地址 | MAU 打拍后的 `r_mem_addr_mau` | EXU 级 `mem_addr_exu` 送 SRAM read address |
| DTCM load 数据使用 | MAU 级组合使用 | MEM/MAU 级使用同步读返回数据，保持当前 load-use 一拍模型 |
| DTCM store 写地址/数据 | MAU 打拍后写 | EXU 级给出写地址/写数据/写掩码，SRAM 在 EXU/MEM 边界采样 |

若目标 SRAM 为 1R1W 或 true dual port，DTCM 读写请求提前到 EXU 级比较自然。若目标是单端口 SRAM，则 load/store 同周期端口冲突需要额外仲裁；当前顺序流水每条指令最多一个 LSU 请求，通常不会同时对 DTCM 发出 load 和 store，但要核对 SRAM macro 的端口定义。

## IF/ITCM 影响

### 需要分离请求 PC 与返回 PC

当前 `ifu` 输出 `o_pc_if = pc_r`，`idu` 在同一拍把 `i_instr` 和 `i_pc_if` 打入 `r_instr_id/r_pc_id`。组合读 ITCM 下，`i_instr` 正好对应 `pc_r`。

若 ITCM 地址改为 `pc_next`：

- `pc_next` 是下一条请求地址，不再天然等于当前返回指令的 PC。
- `idu.i_pc_if` 不能直接接 SRAM read address，否则 `r_pc_id` 会领先 `r_instr_id` 一拍。
- 需要新增或重命名一个“返回侧 PC”寄存器，例如 `if_rsp_pc`/`if_pc_d1`，在发出 `itcm_rd_addr` 的同一拍记录该地址，下一拍与 `itcm_rd_data` 一起送入 IDU。

建议接口拆分为：

```text
ifu/soc_top:
  o_if_req_pc     -> ITCM read address
  o_if_rsp_pc     -> IDU PC tag, aligned with i_if_instr
  o_if_rsp_valid  -> optional, used for reset/redirect bubble control
```

短期也可以不显式引入 valid，但 reset 和 redirect 后至少需要插入/屏蔽一次无效返回，避免 IDU 解码旧地址返回的数据。

### reset 首拍行为

`ifu.sv` 里已有 TODO：如果 SRAM 读地址使用 `pc_next`，reset 后 `pc_r` 可能需要初始化为 `0 - 4`，让首个 `pc_next` 为 `0x0000_0000`。

更稳妥的做法是显式维护 fetch request PC：

- reset 后第一条 request PC 为 `ITCM_BASE`。
- request 发出时同步保存 `if_req_pc_d1`。
- 下一拍 `if_rsp_pc = if_req_pc_d1`，`i_if_instr` 对应该 PC。

这样不依赖 `pc_r = -4` 这类隐含技巧，也更利于后续加入 stall/redirect valid。

### redirect/flush 的额外无效返回

当前 EX 阶段产生 `redirect_req_exu` 后，`ctrl_hazard` flush IF/ID 和 ID/EX，IFU 同拍把 PC 改成 redirect target。组合读下，下一拍取到 target 指令。

同步 ITCM 下，redirect 发生时流水中可能已有一个“redirect 前发出的 fetch request”将在下一拍返回。该返回必须被丢弃，否则会把错误路径指令注入 IDU。

建议增加：

- `if_kill_rsp` 或 `if_rsp_valid`，当 redirect 生效时标记下一拍返回无效。
- `idu` 在 `i_flush` 或 `!if_rsp_valid` 时写入 `INSTR_NOP`，并避免更新错误 `pc_id`。
- `ctrl_hazard` 的 redirect flush 仍应保持优先级高于 load-use stall。

### FENCE.I 与 ITCM 数据兼容端口

当前 `FENCE.I` 作为 BRU 类操作，通过 redirect flush 取指路径。若去掉 ITCM 临时数据读端口，只保留取指读和数据写：

- 如果软件布局已经保证 `.data/signature` 在 DTCM，则 LSU 不再需要从 ITCM load。
- 本轮可以明确暂不支持自修改指令测试，不要求 `FENCE.I` 对 ITCM 写后取指做完整一致性保证。
- `FENCE.I` 可以先保留为普通 redirect/flush 类指令，语义上作为取指路径刷新点；真正的 I/D 一致性可等后续 cache/ICache invalidate 机制再恢复。
- `soc_bus_v0` 的 `i_itcm_rd_data` 和 `mem_itcm.o_data_rd_data` 可以作为去兼容端口的主要清理对象；但去掉前应同步调整 compliance/test linker，把 signature 放在 DTCM。

## LSU/DTCM 影响

### DTCM 读写请求提前到 EXU

当前路径：

```text
EXU/exu_lsu: mem_addr_exu, mem_req_info_bus
  -> MAU regs: r_mem_addr_mau, r_mem_req_info_bus
  -> soc_bus_v0/dtcm_addr
  -> mem_dtcm combinational read
  -> MAU load align/sign-extend
```

同步 SRAM 目标路径建议为：

```text
EXU/exu_lsu: mem_addr_exu, mem_wr_data_exu, mem_req_info_bus
  -> DTCM read/write address, write data, mask, we in EXU cycle
  -> SRAM captures request at EXU/MEM clock edge
  -> MEM/MAU cycle read data is available
  -> MAU uses registered addr offset/size/unsigned/rd tag to align and sign-extend
```

因此需要适配的信号包括：

| 当前信号 | 当前用途 | SRAM 化建议 |
| --- | --- | --- |
| `mem_addr_exu` / `o_mem_addr_exu` | EXU 地址生成结果 | 作为 DTCM read/write address 源 |
| `mem_wr_en_exu` | EXU store 写使能 | 作为 DTCM SRAM `we` 的早一拍源，但必须用 EX 有效位、异常和 misalign 屏蔽 |
| `mem_wr_data_exu` | EXU store 写数据 | 与 EXU 地址同拍送到 DTCM SRAM |
| `mem_req_info_bus` | `{wr_mask, load, size, unsigned}` | 写掩码同拍送 SRAM；load/size/unsigned 继续打一拍，与 MEM 级返回数据对齐 |
| `r_mem_addr_mau[1:0]` | load byte/halfword offset | 保持作为返回数据的 offset tag |
| `wb_rd_idx_exu/wb_rd_wen_exu` | load 目的寄存器 tag | 保持打一拍，使 MEM 级 load 数据与目的寄存器对齐 |

这里的“写地址提前”应理解为 store 请求在 EXU 组合生成、在 EXU/MEM 边界被 SRAM 采样。它不应绕过当前异常和 flush 语义：misalign store 已由 `exu_lsu` 屏蔽 `mem_wr_en_exu`，后续最好再补 `ex_valid`/`ex_kill` 门控，避免 bubble 或被杀指令产生 store side effect。

### SoC bus 读选择也要提前或打拍

如果 DTCM read address 用 EXU 地址，而 `soc_bus_v0.o_mem_rd_data` 仍用当前 `i_mem_addr` 组合选择返回源，会出现“返回数据是上一拍请求的数据，但选择信号是当前 EXU 地址”的错配。

至少需要为读返回路径保存一拍的 decode/tag：

- `mem_rd_sel_d1`：上一拍 read request 命中的 DTCM/UART/ITCM。
- `mem_rd_addr_d1`：用于调试、SVA、MMIO 返回选择。
- `mem_rd_is_load_d1`：只对真实 load 返回数据有效。

如果下一步只支持 DTCM 同步读、UART 仍组合读，也建议统一返回选择打一拍，避免 load to UART 与 load to DTCM 语义分裂。若 UART 保持 0-wait 组合 MMIO，则 LSU 需要区分 normal SRAM load 与 MMIO load，复杂度会升高。

### store 路径

store 不依赖读返回数据。按补充目标，store 地址、写数据、写掩码、写使能都应从 EXU 级送到 DTCM，让 SRAM 在 EXU/MEM 边界完成采样；MAU 仍可保留打一拍后的 store tag/调试信号，但不再作为 DTCM SRAM 写地址的唯一来源。

需要注意：

- 若 DTCM macro 是单端口，需要核对 read/write 端口是否可同周期访问。顺序流水通常每周期只有当前 EXU 的一个 LSU 请求，但可能和上一拍 store 写入行为在 macro 端口时序上相邻，需要按 macro 手册确定 read-during-write 语义。
- 若 byte mask 写由 SRAM macro 支持，则保留 `mem_wr_mask`。
- 若 SRAM macro 只支持 word write 或 byte enable 约束不同，`exu_lsu` 的 mask/data shift 逻辑需要重新核对。

### load 数据可用点保持在 MEM

目前 `mau.o_wb_data_mau` 在 MAU 阶段直接选择 `mau_load_data`，并且 `ctrl_hazard` 允许 EXU 从 MAU 前递。若 DTCM 在 EXU/MEM 边界采样地址、MEM 级给出 `rd_data`，则这一点可以保持：

- 对于 ALU/BRU/CSR 结果，MAU 前递仍然可行。
- 对于 load 结果，MEM/MAU 级已经拿到上一拍 EXU 请求对应的 `rd_data`，可以继续形成 `wb_data_mau`。
- 现有 load-use stall 一拍后，消费者进入 EXU 时，生产者 load 已进入 WBU 或处于可从 MEM/WB 路径前递的位置，策略可维持当前实现。

需要注意的是，前递路径的组合时序会包含 SRAM 输出、bus 返回 mux、load align/sign-extend、forward mux 和 EXU 运算输入。若目标频率较高，仍建议 STA 后决定是否给 load 返回数据再打一拍；但功能评估上不需要强制增加 load-use stall。

## Hazard/Forwarding 影响

### load-use stall 保持 1 拍

当前 load-use 检测：

```text
i_is_load_req_exu && IDU rs depends on EXU rd
  -> stall PC/IF_ID 1 cycle
  -> flush ID_EX 1 cycle
```

按“DTCM 地址 EXU 级给出、MEM 级获得 `rd_data`”的目标，一拍 bubble 后消费者到 EXU 时，load 生产者已经走到 MEM/WB 可前递路径，因此 load-use 策略可以保持当前实现：

- `ctrl_hazard` 继续检测 EXU load 与 IDU 源寄存器 RAW。
- stall PC/IF_ID 一拍，flush ID_EX 一拍。
- 下一拍消费者进入 EXU，使用现有 MAU/WBU forwarding 获得 load 结果。

这意味着 DTCM SRAM 化不应引入额外 MEM2 或 2 拍 load-use stall。真正需要新增的是“EXU 请求/MEM 返回”的 tag 对齐，以及 store/load 请求有效位门控。

### forwarding select 可基本保持，但建议补数据有效语义

在上述 DTCM 时序下，MAU 阶段的 load 数据仍应有效，因此 `ctrl_hazard` 的前递选择可以基本保持当前结构：MAU 命中优先，其次 WBU。

但为了降低后续 debug 风险，建议补充：

- `wb_is_load_mau`：MAU 阶段目的寄存器来自 load。
- `wb_data_valid_mau`：MAU 阶段前递数据是否真实可用；本轮 DTCM 固定 1-cycle SRAM 下，正常 load 到 MEM 时应为 1。
- `wb_is_load_wbu`：必要时用于 SVA/调试。

前递优先级应改为：

```text
if MAU has same rd and wb_data_valid_mau:
    forward MAU
else if WBU has same rd:
    forward WBU
else:
    use regfile
```

当 `wb_is_load_mau && !wb_data_valid_mau` 时，不能选择 MAU；该条件正常不应在固定 1-cycle DTCM 流水中出现，可作为断言或调试保护。

### redirect 与 load-use 的优先级

当前 `ctrl_hazard` 中 redirect 优先于 load-use：redirect 时不 stall，flush IF/ID 和 ID/EX。这个优先级建议保持。

同步取指后还要补充一类 fetch-response kill，但它不应阻塞 EX 阶段异常/CSR side effect 的提交。也就是说：

- redirect 负责清空年轻指令和杀掉错误 fetch response。
- load-use 只负责冻结取指/译码并向 ID/EX 注入 bubble。
- 二者同时出现时，redirect 优先，避免旧路径 load-use 把 PC 冻在错误路径。

## CSR 与异常控制影响

### 当前 CSR 提交点偏 EX，需要保持与 flush/stall 一致

`csr_regs` 当前使用：

```text
csr_commit_en = ~stall[STALL_ID_EX] & ~flush[FLUSH_ID_EX]
csr_wr_en = i_csr_wr_req & csr_commit_en
```

异常和 `mret` 硬件更新则直接由 EXU 的 `i_exc_req/i_trap_ret_req` 触发，优先于普通 CSR 写。

SRAM 化本身不要求 CSR 数据通路改变。按 DTCM 侧保持 1 拍 load-use 的方案，CSR 风险主要来自 ITCM 同步取指引入的 fetch bubble/kill，而不是 DTCM 多拍 stall。必须避免以下情况：

- 因同步取指插入 fetch bubble，错误地 flush 了正在 EX 阶段提交的 CSR/异常。
- 因 redirect kill fetch response，误用 `FLUSH_ID_EX` 屏蔽了当前 EX 指令 side effect。

当前 load-use stall 时 `STALL_ID_EX=0`、`FLUSH_ID_EX=1`，CSR 写被屏蔽。这在“load-use 只向 EX 注入 bubble”的语义下可以继续工作；但 ITCM 同步取指后会出现 fetch response valid/kill，建议逐步改成显式 `ex_valid`/`ex_kill` 作为 CSR commit 条件，而不是长期复用局部 flush bit 推导。

### 建议引入流水级 valid

同步 SRAM 后，IF 返回会有无效泡泡；DTCM 虽然按固定 1-cycle 返回设计，也建议带上数据 valid/tag 做调试和断言。继续只靠固定 NOP 和 flush/stall bit 会越来越脆。

建议下一轮至少引入内部 valid，不一定马上暴露到顶层：

| valid | 作用 |
| --- | --- |
| `if_rsp_valid` | 标识 ITCM 返回指令是否可进入 IDU |
| `id_valid` | 标识 `r_instr_id/r_pc_id` 是否为真实指令 |
| `ex_valid` | 标识 EXU 当前指令是否能产生 redirect/CSR/mem side effect |
| `mem_valid` | 标识 MAU 当前 request/tag 是否有效 |
| `wb_valid` | 标识 WBU 写回是否有效 |

CSR、异常、store、load writeback 均应以对应 stage valid 为门控。这样 reset 首拍、redirect 后旧 fetch response、load-use bubble 都能统一处理。

### CSR RAW 与序列化风险

`readme.md` 已指出 CSR 精确提交和 CSR RAW 是后续改进项。DTCM SRAM 化不改变这一点：普通 CSR 连续依赖问题仍存在，不会被 SRAM 化自动修复：

```asm
csrrw x0, mtvec, x1
csrr  x2, mtvec
```

当前 CSR 读写都在 EX 附近，具体能否读到新值依赖寄存器写入时序和组合读顺序。若下一步重构 hazard/valid，建议顺手明确 CSR 策略：

- 短期：对 CSR 指令序列化，当前 EX/MEM/WB 有未提交 CSR 写时，后续 CSR 在 ID 停顿。
- 中期：CSR 写意图推进到 WB/commit，再加 WB-to-EX CSR bypass。

不要把 CSR 提交点与 SRAM load 返回阶段混在一起；两者可以共用 valid/commit 框架，但 side effect 优先级需要明确：异常硬件更新 > `mret` 状态更新 > 普通 CSR 写。

## ITCM 临时兼容端口移除影响

当前 ITCM 数据侧临时读链路为：

```text
core LSU -> soc_bus_v0 sel_itcm -> mem_itcm.o_data_rd_data -> core load data
```

移除它会影响：

- `soc_bus_v0` 端口：删除 `i_itcm_rd_data`，读 mux 不再选择 ITCM load。
- `soc_top_v0` 连线：删除 `itcm_rd_data_lsu`。
- `mem_itcm` 端口：删除 `o_data_rd_data`，并考虑将 Port B 改名为 write-only data port。
- DV：`sva_soc_bus` 当前已经断言 `mau_req_load_mau && sel_itcm_bus` 不应发生，可继续保留或升级为 fatal。
- testbench signature dump：`tb_soctop_isatest.sv` 的 `read_signature_word()` 仍支持从 ITCM 读 signature，软件布局收敛到 DTCM 后应同步删除或仅作为历史兼容。
- linker/scripts：必须保证 `.data/.bss/.signature` 不再落入 ITCM，否则 compliance 或用户程序会失败。

本轮可以接受暂不支持自修改指令测试用例；如果仍保留 ITCM 数据侧写，也只作为后续 cache/FENCE.I 一致性机制的预留，不作为当前验证目标。

## 需要重点调整的信号清单

| 模块 | 信号/逻辑 | 调整原因 |
| --- | --- | --- |
| `ifu` | `pc_r`, `pc_next`, `o_pc_if` | 拆分 fetch request PC 和 instruction response PC |
| `core_rv32i_v0` | `o_if_pc`, `i_if_instr` | 顶层取指接口语义从组合读改为同步返回 |
| `idu` | `i_instr`, `i_pc_if`, `i_flush`, `r_pc_id` | 指令和 PC 必须按 SRAM 返回对齐；无效返回写 NOP |
| `ctrl_hazard` | load-use stall, forward select | 保持一拍 load-use；建议补 valid 断言防止无效 MAU 前递 |
| `exu` | `o_mem_addr_exu`, `o_mem_wr_en_exu`, `o_mem_wr_data_exu`, `o_is_load_req_exu` | DTCM 读写请求提前到 EXU 级；load hazard 保持当前入口 |
| `mau` | `r_mem_addr_mau`, `r_mem_req_info_bus`, `mau_load_data` | 作为 MEM 级返回数据的 offset/size/unsigned/tag |
| `soc_bus_v0` | read decode mux | 返回数据选择需要使用上一拍 request 的 decode |
| `mem_dtcm` | `i_addr/o_rd_data` | 组合读改为同步读，读地址来自 EXU 或 bus read-request |
| `mem_itcm` | `i_rd_addr/o_rd_data` | 组合读改为同步读，去掉临时数据读端口 |
| `csr_regs` | `csr_commit_en` | ITCM fetch valid/kill 引入后建议改用 EX valid/kill |

## 推荐分步迭代顺序

可以，而且建议分步做。DTCM SRAM 化和 ITCM SRAM 化影响面不同：DTCM 主要影响 LSU/bus/forwarding，ITCM 主要影响 fetch PC/valid/redirect。拆开验证能显著降低 debug 难度。

推荐顺序：

1. 先整理软件内存布局，保证普通数据和 signature 全部在 DTCM；保留并强化 `sva_soc_bus` 对 ITCM data load 的检查。
2. 移除 ITCM 第二读端口的依赖：`soc_bus_v0` 不再从 ITCM 返回 LSU load 数据，`mem_itcm.o_data_rd_data` 后续可删除；暂不支持自修改指令测试。
3. 单独做 DTCM SRAM 化：将 DTCM read/write address、write data、write mask、write enable 的给出时间提前到 EXU 级；MAU 保留 offset/size/unsigned/rd tag，对 MEM 级 `rd_data` 做 load align。
4. 验证 DTCM 阶段：重点跑 load/store、byte/halfword、misalign、load-use、load 后 branch/store/csr 源操作数；确认 load-use 仍为一拍。
5. DTCM 稳定后，再做 ITCM SRAM 化：为 IF 路径引入 request/response PC 和 valid/kill，处理 reset 首条取指和 redirect 后旧 fetch response。
6. 验证 ITCM 阶段：重点看 reset 首条指令、顺序取指、branch/jal/jalr、ecall/ebreak/mret、FENCE.I 作为 flush 指令但不验证自修改一致性。
7. 最后收敛 CSR/异常 commit 条件，优先引入 `ex_valid/ex_kill`，避免 flush/stall 语义继续膨胀。

## 建议新增/更新验证点

- IF PC/instr 对齐：每个进入 IDU 的有效指令，其 `pc_id` 等于前一拍发给 ITCM 的 request PC。
- redirect kill：branch/jump/trap/mret 后，redirect 前已发出的 fetch response 不得进入有效 ID/EX。
- load-use：`lw x1, 0(x2); add x3, x1, x4`、`lb/lh/lbu/lhu` 均应只 stall 一拍并得到正确前递。
- load 后 branch/store/csr 源操作数：覆盖 `lw` 后立即 `beq`、`sw`、`csrrw` 使用 load 结果的场景。
- misalign load/store：同步读地址提前后，misalign load 不应发出有效 SRAM read side effect，store 不应写。
- CSR side effect 一次性：fetch bubble/redirect kill 下 CSR 写、ecall/ebreak trap、mret 状态更新不能重复发生。
- ITCM data load 禁止：去端口后任何 LSU load 命中 ITCM 应断言或返回定义好的 bus error/0，但测试布局不应依赖该行为。

## 主要风险结论

- 最大功能风险仍在 ITCM：`pc_next` 作为 SRAM 地址后，返回指令与 PC 标签可能错位；必须拆分 request PC 和 response PC。
- DTCM 风险可控：只要读写请求在 EXU/MEM 边界被 SRAM 采样、MEM 级稳定返回 `rd_data`，load-use 可以保持一拍，当前 MAU/WBU 前递结构可以延续。
- 最大控制风险是继续用 flush/stall 位隐式表达 valid/kill，容易让 CSR、异常、store 在 fetch bubble 或 redirect kill 下重复或丢失；建议下一轮引入显式 stage valid。
- 去掉 ITCM 临时兼容读端口前，软件链接布局和 compliance signature dump 必须先完成 DTCM 化，否则测试会从架构变化变成软件布局失败。
