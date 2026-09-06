# task_v12_01：Phase 0 可变延迟 Memory 事务基线实现工单

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 03:08
**Current Version**: v1.4
**Status**: Completed (2026-09-06 15:16) | Implementation Complete — Public Acceptance Pending User Run (2026-09-06 11:04) | Ready for Execution after Review (2026-09-06 03:37) | Ready for Execution (2026-09-06 03:08)

**Version Changelog**:
- **v1.4** (2026-09-06 15:16): 用户确认完整 ISA/Compliance 回归与 DC check 均已运行通过，工单更新为 Completed。
- **v1.3** (2026-09-06 14:09): 记录最终 Cache + backing memory 决策；Phase 0 的 IF/LSU 合同由 I/D Cache 直接继承，当前 ITCM/DTCM RTL 仅为过渡 backend，后续移除而非与 Cache 并存。
- **v1.2** (2026-09-06 11:04): 完成 Phase 0 RTL 与定向 DV；按用户要求不执行完整 ISA/Compliance 与 DC check，任务保持公共验收待用户运行状态。
- **v1.1** (2026-09-06 03:37): 按 review 收紧 Phase 0，移出精确地址、Unmapped error、32 KiB DTCM 和 SRAM macro 工作；明确 LSU transaction pending 由 MA/MEM 拥有，EX 仅生成请求 payload。
- **v1.0** (2026-09-06 03:08): 基于 Cache/Memory Subsystem 总体规格、Phase 0 Roadmap 和 v12 现有 RTL/DV 状态，定义首版实现与验收要求。

---

功能依据：

- [`../mainSpec_Cache_Mem-subsys_Feature.md`](../mainSpec_Cache_Mem-subsys_Feature.md)
- [`../phaseSpec_Cache_Mem-Subsys_Roadmap.md`](../phaseSpec_Cache_Mem-Subsys_Roadmap.md)
- [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)
- [`rule_ai_acceptance.md`](rule_ai_acceptance.md)

## 1. 任务目标

实现 Cache / Memory Subsystem Roadmap 的 **Phase 0 — Variable-Latency Memory Baseline**：把当前依赖固定一拍存储返回的 IF 与 LSU 通路改成 request/response valid-ready 事务接口，并保证请求等待、返回等待和流水线反压下不丢失、不重复、payload 稳定。

本任务只建立后续 Cache 可直接复用的事务和 stall 基线，不实现 I-Cache、D-Cache、BIU、AXI、APB、精确地址范围、访问错误、DTCM 扩容或 SRAM macro 映射。

已确定的后续演进边界：最终采用 Cache + backing memory，不保留 ITCM/DTCM。Phase 1
的 I-Cache 和 Phase 2 的 D-Cache 将直接成为本任务 IF/LSU req/rsp 接口的 responder；当前
`mem_itcm`/`mem_dtcm` 仅用于 Cache 加入前跑通系统，并分别在 Phase 1/Phase 2 被重构或
重命名为 Cache 下游 backing-memory adapter，
不得演化为与 Cache 并存的 software-visible TCM。

以下内容已明确搁置，只在本任务中保留接口预留或一句说明，具体分析与后续验收见 [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)：

- IMEM/DMEM/UART 精确地址范围及 alias 修正；
- Unmapped instruction/load/store access fault；
- 过渡 DTCM model 对应的 backing DMEM 从 16 KiB 扩展到 32 KiB；
- SRAM macro/BRAM banking、macro 等价性和相关边界测试。

## 2. 当前基线与本任务缺口

| 位置 | 当前行为 | 本任务需要解决 |
|---|---|---|
| `de/core/ifu.sv` | `o_fetch_req` 恒为 1，没有 request ready 或 response valid-ready；默认 ITCM 固定一拍返回 | 建立单 outstanding IF transaction，等待 request/response，并处理 redirect 后旧路径 response |
| `de/core/exu.sv` / `exu_lsu.sv` | load/store 信息从 EX 组合直出；所有非 MDU 指令默认立即完成 | EX 只在 EX/MA fire 时把稳定的 LSU payload 交给 MAU，不再直接驱动外部 memory side effect |
| `de/core/mau.sv` | MAU 默认一拍得到 load data，没有 request issued/pending/response 状态 | MAU/MEM 成为 LSU transaction owner，发一次请求并持有流水线直到 response |
| `de/soc/soc_bus.sv` | load/read select 固定打一拍；store write enable 由 EX level 信号直接透传 | 接入 req/rsp handshake，目标写副作用只绑定唯一 request fire |
| `filelist_sim_sram.f` / `filelist_syn_sram.f` | 仍显式引用 `../11_rv32im_bpu` | 切到 v12，证明实际编译本版本 RTL |
| 现有 DV | 没有 IF/LSU request-ready、response-delay、response-backpressure 和 exactly-once 覆盖 | 新增定向 TB、SVA 和 transaction scoreboard |

现有地址高 nibble decode、16 KiB 过渡 DTCM model 和越界 alias 属于已接受的临时偏差，不得在本任务顺带修改。

## 3. Phase 0 目标拓扑与所有权

```text
IFU -- IF req/rsp valid-ready --------------------> RTL IMEM wrapper

EXU -- EX/MA payload --> MAU/MEM transaction FSM --> local bus --> RTL memory/UART
       addr/write/       REQ -> WAIT_RSP -> DONE
       size/mask/data
```

后续不是把 `mem_itcm`/`mem_dtcm` 内部逐步堆成 Cache，而是让 Cache 直接接管本任务定义的
上游接口，并把现有 RTL array 降级/替换为下游 backing-memory adapter：

```text
Phase 1: IFU ---- IF req/rsp ----> I-Cache ---- refill ----> backing memory
Phase 2: MAU ---- LSU req/rsp ---> D-Cache/routing --------> backing memory or MMIO
```

关键所有权如下：

- IFU 拥有 IF request pending、response pending 和 redirect stale-response 处理。
- EXU/LSU 只计算 effective address、load/store 类型、size、unsigned、write mask/data 和 misaligned exception。
- EXU 在正常 EX/MA fire 时把完整 LSU payload 交给 MAU；EX 内不得增加 LSU wait-response/issued FSM。
- MAU/MEM 拥有 LSU request valid、issued/pending、response capture、load formatting 和 completion。
- MAU 在 memory transaction 完成前通过 `o_ex_ma_rdy` 反压 EX/前端；后续 cache hit/miss/refill stall 均在 MA/MEM 侧吸收，不迁移 transaction owner。
- local bus/memory wrapper 只在 request fire 接收一次操作，并为 load 和 store 各返回一次 completion response。

IF 与 LSU 各允许最多一个 outstanding transaction。Phase 0 不要求二者收敛成全局单 outstanding；该仲裁属于后续 BIU。

## 4. 外部事务接口合同

最终信号名可按相邻 RTL 风格小幅调整，但以下 req/rsp 双向握手语义不得省略。

### 4.1 IF memory channel

| 方向 | 信号 | 语义 |
|---|---|---|
| Core -> SoC | `if_req_vld` | instruction request 有效 |
| SoC -> Core | `if_req_rdy` | 后端可接收 request |
| Core -> SoC | `if_req_addr[31:0]` | instruction byte address |
| SoC -> Core | `if_rsp_vld` | instruction response 有效 |
| Core -> SoC | `if_rsp_rdy` | IFU 可接收 response |
| SoC -> Core | `if_rsp_data[31:0]` | instruction word |

```text
if_req_fire = if_req_vld && if_req_rdy
if_rsp_fire = if_rsp_vld && if_rsp_rdy
```

### 4.2 LSU memory channel

| 方向 | 信号 | 语义 |
|---|---|---|
| Core -> SoC | `mem_req_vld` | load/store request 有效；由 MAU/MEM 驱动 |
| SoC -> Core | `mem_req_rdy` | 后端可接收 request |
| Core -> SoC | `mem_req_addr[31:0]` | byte address |
| Core -> SoC | `mem_req_write` | 1=store，0=load |
| Core -> SoC | `mem_req_size[1:0]` | byte/halfword/word，沿用现有编码 |
| Core -> SoC | `mem_req_wmask[3:0]` | byte write strobe |
| Core -> SoC | `mem_req_wdata[31:0]` | lane-aligned store data |
| SoC -> Core | `mem_rsp_vld` | completion response；load/store 都必须返回 |
| Core -> SoC | `mem_rsp_rdy` | MAU/MEM 可接收 response |
| SoC -> Core | `mem_rsp_rdata[31:0]` | load read data；store 时无架构意义 |

```text
mem_req_fire = mem_req_vld && mem_req_rdy
mem_rsp_fire = mem_rsp_vld && mem_rsp_rdy
```

本 Phase 不实现 backend error/access fault。若为后续接口稳定性预留 `if_rsp_err/mem_rsp_err`，本任务中必须明确绑为 0 且不得生成新异常；也允许留到后续 deferred task 再加入。

### 4.3 通用握手规则

- producer 拉高 `*_vld` 后，在 fire 前必须保持 valid 和全部 payload 稳定；不得等待 ready 才产生 valid。
- responder 拉高 `*_rsp_vld` 后，在 response fire 前必须保持 valid 和 response data 稳定。
- 每个 request fire 必须且只能得到一个匹配 response；不得无请求 response、重复 response 或乱序。
- request fire 后撤销 request valid，等待 response 期间不得重发同一 transaction。
- store 目标写使能/UART 写副作用只能由 `mem_req_fire && mem_req_write && target_selected` 产生一次。
- reset 清空 pending request/response 状态，不产生幽灵 response 或 store side effect。
- 环境保证已接收请求最终返回 response；core 必须支持 request-ready、response-valid 和 response-ready 分别反压任意有限周期。

## 5. 必须实现的行为

### 5.1 IFU transaction

- IFU 只能在 `if_req_fire` 时认定取指 request 被接收，并保存与该请求一致的 PC/BPU metadata。
- request 已 fire、response 未返回时不得再次请求；response 返回后必须与原 PC、prediction metadata 对齐。
- 若 IDU not-ready，已返回 instruction、PC 和 prediction metadata 必须稳定保存，不得丢失或重复送出。
- redirect 优先于顺序/预测 next-PC；尚未提交给 IDU 的旧路径 response/payload 必须失效。
- 已 fire 的旧路径 request 不假设可取消。IFU 必须接收并丢弃其 response，再从 redirect PC 请求；旧 response 不得进入 IDU 或更新 speculative RAS。
- request valid 等待 ready 时遇到 redirect，仍须遵守 valid/payload 稳定合同；可在该 request fire 后标记 stale 并 drain response。
- RAS 预测 push/pop 仍只绑定真正送入 IF/ID 的有效 instruction fire；BPU/RAS 功能和配置保持不变。

### 5.2 EX/MA payload

- EXU/LSU 继续完成 effective address、store lane/mask、load size/unsigned 和 misaligned 检查。
- misaligned load/store 不得作为 memory transaction 交给 MAU，沿用现有 cause=4/6 exception 路径。
- 对齐 load/store 与其他正常 EX 结果一样，在唯一 `ex_ma_fire = o_ex_ma_vld && i_ex_ma_rdy` 时移交一次。
- EX/MA payload 必须补齐 MAU 发请求所需的 `is_load/is_store/addr/size/unsigned/wmask/wdata`；payload 在 valid && !ready 时保持稳定。
- EXU 不再直接向 `core/soc_top` 输出生效的 memory request/write enable。不得在 `exu.sv` 中维护 LSU issued、wait-response 或 retry 状态。

### 5.3 MAU/MEM transaction FSM

MAU 至少具备语义等价的 `IDLE/REQ/WAIT_RSP/DONE` 行为；允许合并状态或做无气泡优化，但所有握手与持有规则必须等价。

- `IDLE`：在 EX/MA fire 捕获完整 LSU payload；非 memory 指令继续按现有 MA/WB 路径处理。
- `REQ`：持续拉高 `mem_req_vld` 并保持 payload，直到唯一 `mem_req_fire`。
- `WAIT_RSP`：停止 request，等待匹配的 `mem_rsp_vld`；不得提前产生 MA/WB completion。
- `DONE`：保存 response/load result，并通过 MA/WB valid-ready 完成一次；WB not-ready 时全部结果与 rd metadata 保持稳定。
- 也可在 `mem_rsp_fire` 与 MA/WB ready 同拍直接完成，但必须证明 response、writeback 和 slot 重用不存在丢失或重复。
- MAU busy 时 `o_ex_ma_rdy` 必须阻止 EX 覆盖当前 transaction。只有 slot 空闲或当前 MA/WB payload 真正被接受时才能接收下一条 EX payload。
- load byte/halfword/word sign/zero extension 位于 MA/MEM，并使用已捕获的匹配 response data；不得使用自由运行、默认固定一拍的 read-data 信号。
- store 同样等待 response 后才完成流水线指令；写副作用发生在后端 request fire，response 只表示 completion，不得二次写。
- 等待 load response 时，MAU forwarding valid/data 不得把旧 ALU pass-through data 伪装成 load result。依赖指令只能在 load data 真正可用时得到正确 forwarding，或继续被反压。
- 非 memory 指令的 MA/WB 行为、BPU/CSR side effect 和现有流水线 valid-ready 语义不得回退。

### 5.4 地址属性的 Phase 0 最小实现

- 保留并显式标识 `Cacheable`、`Device/uncached`、`Unmapped` 三类属性，为 Phase 1/2 分流预留稳定语义。
- 本 Phase 允许沿用当前高 nibble decode。IF 对 `0x0...` window 标记为 cacheable；LSU 对 `0x1...` window 标记为 cacheable，对 `0x0...` 和 `0x3...` window 标记为 device/uncached，其余标记为 unmapped。
- 精确上下界、跨界检查和 Unmapped error 暂不实现。为防止 transaction 死锁，当前 unmapped request 应返回一次 benign completion：IF 返回 NOP、load 返回 0、store 无目标写；不得静默吞掉 request 而永不 response。
- 不得扩大既有 UART 功能或修改寄存器定义；当前程序使用的访问行为保持不变。
- 后续 exact decode/error 工作不得要求重新迁移 IF/MAU transaction owner；具体见 deferred 文档。

### 5.5 RTL memory baseline

- 本任务所有新增或重构后的 memory storage/wrapper 先使用 synthesizable RTL 行为实现，不例化新的 SRAM macro 或 BRAM IP。
- 可保留稳定 wrapper 边界和未来 macro replacement 注释，但 wrapper 内本阶段应选择 RTL array/model。
- 过渡 `mem_dtcm` 保持当前 16 KiB 配置；不得修改成 32 KiB、不得增加双 bank、不得新增对应 banking/preload 测试。
- 不要求验证 RTL 与现有 SRAM macro/BRAM 的等价性；macro replacement 已转入 deferred scope。

## 6. 预期文件范围

| 文件 | 要求 |
|---|---|
| `de/core/ifu.sv` | 单 outstanding IF req/rsp、response/payload 保存、redirect stale-response drain |
| `de/core/exu_lsu.sv` | 生成完整 LSU payload并保留 misaligned 检查 |
| `de/core/exu.sv` | 仅经 EX/MA valid-ready 传递 LSU payload；移除对外生效 memory strobes，不加入 wait-response FSM |
| `de/core/mau.sv` | 成为 LSU transaction owner；实现 request/pending/response/DONE、load formatting、forwarding 与 MA/WB hold |
| `de/core/core.sv` | 连接 IF req/rsp；将 EX LSU payload送 MAU；由 MAU 暴露 LSU req/rsp |
| `de/soc/soc_bus.sv` | 接收 MAU req/rsp，产生单次 target access 和 completion；保留当前粗粒度 decode |
| `de/soc/soc_top.sv` | 连接 IF/LSU transaction channel 和本地 RTL memory wrapper |
| `de/periphs/mem_itcm.sv`、`mem_dtcm.sv` | 以 RTL wrapper/model 响应 request enable；维持当前容量，不做 macro/banking 扩展 |
| `de/defines/config.v` | Phase 0 默认选择 RTL memory；DTCM size 保持 16 KiB |
| `filelists/*.f` | 纳入新增 RTL并清除 v11 设计路径引用，保证实际编译 v12 |
| `dv/*` | 新增 Phase 0 variable-latency TB/SVA/scoreboard；适配 IFU/BPU/RAS 现有定向测试 |
| `doc/readme_mem_config.md` | 记录 Phase 0 RTL wrapper、容量和 req/rsp latency 合同；链接 deferred 文档 |
| `doc/dev_log/log_dev_v12.md` | 完成时创建/更新，链接本工单并记录实现与验收结果 |

若实现需要精确地址 fault、DTCM 扩容、SRAM macro、Cache、BIU、AXI/APB 或多个 outstanding transaction，应停止并按 deferred 文档另开工单。

新增独立 DV 若产生构建目录，必须提供安全 `clean`：目标必须解析到本版本 `dv` 下、不是符号链接、顶层内容属于白名单且不含 RTL/TB/Markdown/Makefile 源文件，之后才可删除明确生成物。

## 7. 推荐实施顺序

1. 修正 sim/syn filelist 的 v11 遗留路径，确认编译输入只来自 v12。
2. 固化 IF/LSU req/rsp 接口、fire 定义、单 outstanding 和 payload-hold SVA。
3. 以 RTL wrapper 建立可反压的 IF/LSU backend response；保留当前容量与粗粒度地址行为。
4. 重构 IFU request/response FSM，覆盖 request stall、response stall 和 redirect stale response。
5. 扩充 EX/MA LSU payload，确保 EX 只生产/移交信息且 valid && !ready 时稳定。
6. 在 MAU/MEM 实现 transaction FSM、load formatting、store completion 和正确 forwarding。
7. 在 `core.sv`/`soc_top.sv` 完成连线，适配现有 BPU/RAS TB/SVA。
8. 跑定向 DV、Cache-disable user program、公共回归和 DC 前端检查，最后更新工单状态与 v12 development log。

## 8. 定向验证清单

### 8.1 IF transaction

- request ready 连续拉低至少 3 拍：valid/address 稳定，只产生一个 request fire。
- response 分别延迟 1、2、7 拍：PC/instruction/prediction metadata 对齐，只提交一次。
- response valid 时 IF/ID not-ready：payload 稳定，恢复 ready 后只提交一次。
- redirect 分别发生在 request 等 ready、已 fire 等 response、response 已到但 IF/ID 阻塞和空闲状态；旧路径 instruction 均不得进入 ID。
- 连续正常取指不丢 PC、不重复 PC；BPU/RAS frontend 定向用例继续 PASS。

### 8.2 MAU/LSU transaction

- EX/MA valid 被 MAU 反压时，完整 LSU payload 保持稳定，EX 不重复移交。
- load/store request ready 反压和 response 延迟 1、2、7 拍；每条指令 request fire=1、response fire=1、MA/WB completion=1。
- response valid 时强制 MA/WB not-ready：response/result/rd metadata 保持，恢复后只完成一次。
- 对 store 在 request-ready 前、request fire 后等待 response、DONE 被 WB 反压三个阶段计数目标 write pulse；全过程只能为 1。
- 连续 load、连续 store 和 load-store-store-load 无丢失/重复；byte/halfword/word load sign/zero extension 正确。
- load-use 依赖在多拍 response 下获得正确 forwarding；response 前不得使用旧 MAU data。
- misaligned load/store 不产生 MAU memory request，现有 cause=4/6 测试继续 PASS。
- 当前 unmapped load 得到一次零数据 completion，unmapped store 得到一次无副作用 completion，均不得死锁；这只是临时兼容行为，不代表最终 error 语义。

### 8.3 RTL baseline 与兼容性

- 定向测试和公共回归的编译日志证明使用 RTL `mem_itcm/mem_dtcm` 路径，没有例化 SRAM macro/BRAM。
- 现有 `dv/Makefile.bpu` predictor、RAS、frontend 和 SVA compile 目标在接口适配后全部 PASS。
- 至少一个现有 user program 在 Cache-disable/default Phase 0 路径完成，UART 输出/结束条件与基线一致。
- 不执行 32 KiB backing DMEM、双 bank、精确边界、Unmapped access fault 或 macro 等价性测试；交付记录应明确标记为 deferred，而不是 PASS。

## 9. 必须加入的断言与记分板

至少覆盖以下语义；最终信号名可调整：

```text
if_req_vld  && !if_req_rdy |=> if_req_vld  && $stable(if_req_addr)
if_rsp_vld  && !if_rsp_rdy |=> if_rsp_vld  && $stable(if_rsp_data)
mem_req_vld && !mem_req_rdy |=> mem_req_vld && $stable({addr, write, size, wmask, wdata})
mem_rsp_vld && !mem_rsp_rdy |=> mem_rsp_vld && $stable(mem_rsp_rdata)

outstanding_if  inside {0,1}
outstanding_lsu inside {0,1}
if_rsp_fire     |-> outstanding_if
mem_rsp_fire    |-> outstanding_lsu

target_store_write |-> mem_req_fire && mem_req_write && target_selected
mau_wait_response && !mem_rsp_fire |-> !ma_wb_completion
ex_lsu_payload_valid && !ex_ma_rdy |=> $stable(ex_lsu_payload)
stale_if_response  |-> !if_id_fire
```

scoreboard 必须分别统计 IF/LSU request fire、response fire、store target write 和 MA/WB completion，证明 valid 保持多拍不会被误计成多次 transaction。

## 10. 公共回归与交付判定

按 [`rule_ai_acceptance.md`](rule_ai_acceptance.md) 执行公共回归，并按其“当前设计版本”要求显式使用 v12：

```text
cd work/my-RISCV-Projs/sim
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32i DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../12_rv32im_bpu_cache
```

验收标准：

- ISA：`rv32ui` 41/42 PASS，仅允许既有 `ma_data` FAIL；`rv32um` 8/8 PASS。
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS。
- 不得出现新的 simulation、SVA、assertion 或 scoreboard failure。
- 在 `work/my-RISCV-Projs/syn` 执行 `make check DESIGN_NAME=12_rv32im_bpu_cache` 并 PASS；不要求完整综合。

交付记录必须包含：

- 修改/新增文件及最终 IF、EX/MA LSU payload、MAU memory req/rsp 接口表。
- MAU FSM/状态语义，以及 request、response、store side effect、MA/WB completion 的唯一 fire 定义。
- compile/filelist 路径证据，证明使用 v12 RTL memory 和 core，不存在 v11 RTL 偷换或 SRAM macro 例化。
- request-ready、response-delay、response-backpressure、redirect stale-response、store exactly-once 和 load forwarding 的定向结果。
- Cache-disable user program、BPU/RAS DV、公共回归和 DC check 结果。
- deferred 项明确列表；不得把精确地址、access fault、32 KiB backing DMEM 或 macro 等价性记为已验收。

完成后按仓库规则更新本工单 `Status`，保留完整历史，并在 `log_dev_v12.md` 倒序添加开发记录。

## 11. 实施与验证记录（2026-09-06 11:04）

已完成：

- IFU 单 outstanding req/rsp、request hold、response buffer、IF/ID backpressure 和 redirect stale-response drain；
- EX 仅经 EX/MA fire 移交 LSU payload；CSR/BPU/redirect 等 EX side effect 均由唯一 transfer fire 限定；
- MAU 实现 `EMPTY/REQ/WAIT_RSP/DONE`，负责 LSU request pending、response capture、load formatting、forwarding 与 MA/WB hold；
- local bus 将 target write 限定在唯一 store request fire，load/store/unmapped 均返回一次 completion；
- ITCM/DTCM 改为 RTL storage，DTCM 维持 16 KiB；sim/syn filelist 均指向 v12，未纳入 SRAM macro/BRAM；
- 新增 IFU/MAU transaction SVA、scoreboard、Phase 0 独立定向 Makefile，并迁移既有 BPU/RAS frontend TB。

已执行结果：

- `make -f Makefile.phase0 all`：PASS；IFU、MAU、local bus 三组定向均通过，覆盖 IF request ready 3 拍反压、response 7 拍延迟、IF/ID 反压、redirect stale response、MAU request/response 延迟、WB 反压、mapped store exactly-once、unmapped benign completion 与 load sign/zero extension；
- `make -f Makefile.bpu all`：PASS；BPU/RAS unit、frontend、disabled configuration 及相关 SVA compile 全部通过；
- smoke：`add`、`lw` PASS，且日志确认加载 ITCM/DTCM RTL memory，无新增 SVA failure；
- `make com_isa DESIGN_NAME=../12_rv32im_bpu_cache`：PASS，compile log 仅使用 v12 core/memory RTL。

用户于 2026-09-06 15:16 确认已手动执行完整公共验收并通过：

- ISA：`rv32ui` 41/42 PASS（仅允许的既有 `ma_data` FAIL），`rv32um` 8/8 PASS；
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
- DC check：PASS。

因此本工单满足 [`rule_ai_acceptance.md`](rule_ai_acceptance.md) 并更新为 `Completed`。精确地址/access fault、
32 KiB backing DMEM 和 macro replacement 仍为 deferred，详见
[`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)。
