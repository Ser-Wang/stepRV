# Phase 0 S2 IFU / LSU 事务吞吐微架构

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 16:05
**Current Version**: v1.2

**Version Changelog**:
- **v1.2** (2026-09-06 16:47): 按最终 RTL 更新 IFU response-derived request、RAS-dependent response bubble，以及 MAU 既有 ingress/outstanding/completion 三位置的实际 fire/replace 关系。
- **v1.1** (2026-09-06 16:27): 按 review 补充 IFU steady-state 成立条件，明确 MA ingress 是现有 EX/MA elastic holding 而非新增流水级，区分 LSU transaction/completion latency与throughput，并将 RAS preview 改为与显式 bubble 并列的正确性方案。
- **v1.0** (2026-09-06 16:05): 分析 Phase 0 当前 IFU/LSU 串行事务结构，定义支持一拍响应、稳态每拍一笔事务的目标 slot、握手、时序、RAS 与 load dependency 处理。

---

## 1. 文档目的与术语

本文解释 Phase 0 当前 IFU 和 LSU memory transaction 的真实微架构，并定义 Phase 0 S2
需要实现的吞吐结构。对应实现工单为
[`dev_log/task_v12_02_phase0_s2_memory_throughput.md`](dev_log/task_v12_02_phase0_s2_memory_throughput.md)。

本文所说的“LSU 路径”不是单一 RTL module：

```text
ID/EX
  -> exu.sv / exu_lsu.sv      effective address、size、mask、write data、misalign
  -> EX/MA valid-ready
  -> mau.sv                    transaction owner、response、load formatting、MA/WB
  -> soc_bus.sv
  -> transitional backing memory / UART
```

时序图中的动作均以时钟上升沿采样：

- `req_fire = req_vld && req_rdy`；
- `rsp_fire = rsp_vld && rsp_rdy`；
- “一拍 response latency”表示 request 在边沿 N fire，response 在 N 到 N+1 周期有效并于边沿 N+1 fire；
- latency 是单笔事务从 request 到 response 的等待时间；
- throughput 是稳态相邻 transaction fire 的间隔。1-cycle latency 与 1/cycle throughput 是两个不同指标。

## 2. valid-ready 与单 outstanding 的正确理解

valid-ready 本身不引入固定气泡。单 outstanding 也不要求等待一个空闲周期后才能发下一笔：

```text
edge N:    response A fire，清除旧 outstanding
           request  B fire，建立新 outstanding
```

两件事同拍发生时，边沿前只有 A outstanding，边沿后只有 B outstanding，计数始终不超过 1。
因此一拍 backend 的理想时序可以是：

```text
cycle       C0                C1                C2                C3
request     A fire            B fire            C fire            D fire
response                      A fire            B fire            C fire
outstanding A                 B                 C                 D
```

Phase 0 当前性能问题不是握手协议，而是 IFU/MAU 用互斥 FSM 强制完整事务结束后才启动下一笔，
没有实现上述同拍 replacement。

S2 只优化 elastic control，不用增加容量换吞吐：IF/LSU 各自仍只有一个 unanswered request，
returned response/completion只使用既有的一项 holding capacity。不得增加 MSHR、request FIFO、第二个
request/response buffer、预取队列或新的 architectural pipeline stage。

## 3. Phase 0 Baseline IFU 微架构（S2 前）

### 3.1 结构

```text
                       +---------------------+
 issue_pc_r ---------->| BPU query           |---- txn_bp_pred_next_r
      |                +---------------------+
      v
 request slot: req_vld_r / issue_pc_r
      |
      | req_fire
      v
 outstanding slot: txn_pc_r / txn prediction / stale
      |
      | rsp_fire + RAS return selection
      v
 response buffer: instruction / PC / predicted-next-PC
      |
      | if_id_fire
      v
     IDU
```

各 slot 的职责：

| Slot | Valid/state | Payload | 释放条件 |
|---|---|---|---|
| Request | `req_vld_r` | `issue_pc_r` | `if_req_fire` |
| Outstanding | `outstanding_r` | request PC、BTB prediction、stale | `if_rsp_fire` |
| Response buffer | `rsp_buf_vld_r` | instruction、PC、最终 prediction | `if_id_fire` 或 redirect |

redirect 不能取消已经 fire 的 request，因此 outstanding 会标成 stale；其 response 被接收但不进入
response buffer。这个正确性行为必须保留。

### 3.2 当前无反压时序

当前 IFU 只有在 response buffer 被 IDU 消费后才重新拉高 request valid：

```text
cycle       C0              C1              C2              C3
IF/ID       A fire                                          B fire
request                     B fire
response                                    B fire
state       create request  outstanding     buffer B        create request C
```

所以即使 memory 永远 ready 且固定一拍响应，IF/ID 最大吞吐仍约为每 3 拍一条。额外机制等待来自：

1. `if_id_fire` 后下一拍才看到 registered `req_vld_r`；
2. request fire 后完全停止发请求；
3. response 先写 register buffer，下一拍才能被 IDU fire；
4. 直到该 buffer fire 后才生成下一 request。

### 3.3 当前 prediction/RAS 时序

- request fire 时保存该 PC 的 BTB/BHT prediction；
- response fire 时根据返回 instruction 判断是否为 return，并以 RAS top 覆盖 BTB target；
- IF/ID fire 时才根据 buffered instruction 对 speculative RAS push/pop；
- stale response 不更新 RAS。

预测选择和 RAS 状态更新分属两个时刻是正确的，但当前两阶段之间没有流水重叠。

## 4. Phase 0 S2 已实现 IFU 微架构

### 4.1 总体结构

目标仍保持一个 unanswered request，但允许一个 returned payload buffer 与该 outstanding 并存：

```text
                   +-------------------------+
                   | successor PC generator  |
                   | BTB/BHT + response RAS  |
                   +------------+------------+
                                |
                                v
backend <---- req ---- [ one outstanding metadata ]
backend ---- rsp ----> [ one-entry elastic response buffer ] ----> IDU
                               push/replace              pop
```

这里有两个独立容量：

- 最多 1 个 request 已 fire 但尚未 response；
- 最多 1 个 response 已返回但尚未 IF/ID fire。

response buffer 必须是 elastic slot：

```text
buf_pop      = if_id_vld && if_id_rdy && !stall
buf_can_push = !buf_vld || buf_pop
rsp_rdy      = outstanding && buf_can_push
```

因此 buffer 在同一边沿可以 pop A 并 push B，不产生空拍。

### 4.2 同拍 response/request replacement

当一拍 backend 返回 A 时，IFU在该周期已经能看到 response instruction、保存的 request PC 和
prediction metadata，可产生 successor B：

```text
rsp_fire(A) + req_fire(B)
```

理想稳态：

```text
cycle       C0              C1                    C2                    C3
request     A               B                     C                     D
response                    A                     B                     C
IF/ID                                             A                     B
buffer                       push A                pop A / push B        pop B / push C
outstanding A               replace A->B          replace B->C          replace C->D
```

在 `if_req_rdy=1`、固定一拍 response、`if_id_rdy=1`、无 redirect/exception且无 RAS-dependent
bubble时，启动延迟之后 request fire、response fire和IF/ID fire均可每拍发生一次。任何一个前提
不成立时都允许产生真实 stall，因此“每拍一条”不是无条件断言。

### 4.3 next-PC 与 RAS 顺序

普通顺序流和 BTB/BHT prediction 的 successor 已由 outstanding metadata 给出。return target 需要
response instruction 和 RAS top。若同拍发生：

```text
buffered older instruction A: IF/ID fire 并更新 RAS
new response B:              return decode 并查询 RAS
```

B 不能使用错误的旧 RAS top。可以选择 combinational preview/等价旁路：

```text
ras_effective_top = RAS state after same-cycle older buf_pop action
B return target   = ras_effective_top
```

也可以识别这种 RAS-dependent pair，暂停新 return response/successor一拍，等待 A 的 RAS action真正
写入后再继续。两种方案在 S2 中地位相同，优先选择改动小、时序风险低的实现。无论选择哪种方案，
都要求：

1. resolved RAS update/recovery 与 redirect 优先级沿用现有定义；
2. 只有真正 `if_id_fire` 的 buffered instruction 才修改 speculative RAS；
3. stale response 不 push/pop；
4. 新 response 的 return prediction读取正确的 post-A state，或被显式阻塞到该 state 可见；
5. prediction metadata 与对应 response 一起进入 buffer。

最终实现选择显式 bubble，没有修改 `ras_dual_full_stack` 或增加 preview组合路径。显式 bubble只作用于
真实 RAS-dependent pair，
不得让普通顺序/BTB-neutral hit stream退化，也不得以重新全串行为替代。

### 4.4 redirect/backpressure

- request valid 等待 ready 时发生 redirect：旧 request payload必须保持到 fire，随后标 stale；
- outstanding 等 response 时发生 redirect：drain旧 response后请求 redirect PC；
- response buffer 被 IDU 阻塞时发生 redirect：buffer立即失效；
- backend response 因 buffer full 被反压时必须保持 valid/data；
- 同拍 redirect、response、request replacement 时 redirect 优先，禁止发错误 successor。

## 5. Phase 0 Baseline LSU/MAU 微架构（S2 前）

### 5.1 EXU LSU 的职责

`exu_lsu.sv` 是组合 address-generation/decode 单元：

- `effective_address = rs1 + imm`；
- 生成 byte/half/word size；
- 生成 store byte mask 和 lane-aligned write data；
- 生成 load unsigned 属性；
- 检查 load/store address misaligned。

它不保存 transaction，也不应直接产生外部 store side effect。完整 payload 在唯一
`ex_ma_fire` 时交给 MAU。

### 5.2 当前 MAU 单 slot FSM

```text
EXU
  | ex_ma_fire
  v
+-------+    req_fire    +----------+    rsp_fire    +------+
| EMPTY | -------------> | MA_REQ   | -------------> | WAIT |
+-------+                +----------+                +------+
     ^                                                    |
     |                       ma_wb_fire                    v
     +------------------------------------------------- DONE
```

实际上 `r_state` 同时承担 ingress payload、outstanding transaction 和 completion 三种角色。
一个角色未结束时，另一个角色不能进入，因而无法 overlap。

### 5.3 当前一拍 backend 时序

```text
cycle       C0              C1              C2              C3
EX/MA       A fire                                          next may fire
request                     A fire
response                                    A fire
MA/WB                                                       A fire
state       EMPTY->REQ      REQ->WAIT       WAIT->DONE      DONE->...
```

连续 memory request 的 fire 间隔至少约 3 拍。DTCM array/soc_bus 本身仍是一拍 response，
额外间隔来自 MAU FSM。

## 6. Phase 0 S2 已实现 LSU/MAU 微架构

### 6.1 复用既有流水边界形成三个逻辑位置

图中的 `MA ingress` 是现有 EX/MA valid-ready transfer storage/holding capability在 MAU 入口处的逻辑
名称，不代表在 EX/MA 与 MAU 之间再插一个 register。目标保持五级流水边界，只让既有逻辑位置并行推进：

```text
EXU/EX-MA
    |
    v
[ MA ingress slot ] ---- memory request ----> [ outstanding metadata ]
    |                                               |
    | non-memory                                    | memory response
    +---------------------> [ MA/WB completion slot ] ----> WBU
```

| Slot | 内容 | 作用 |
|---|---|---|
| Existing EX/MA holding | EX payload、LSU payload | 持有尚不能向 transaction/completion 推进的最年轻指令 |
| Outstanding | addr、load/store、size、unsigned、rd metadata | 匹配唯一 backend response |
| Completion | formatted result、rd、write enable | 在 WBU backpressure 下稳定保持 |

逻辑位置应支持同拍释放旧 payload并接受新 payload。不得新增 pipeline stage/FIFO，也不得再用互斥
`REQ/WAIT/DONE` 阻止既有相邻阶段并行。

### 6.2 一拍 backend 的连续独立 memory stream

```text
cycle       C0              C1                         C2                         C3
ingress     capture A       issue A / capture B        issue B / capture C        issue C
request                     A fire                     B fire                     C fire
response                                                A fire                     B fire
completion                                              push A                    pop A/push B
outstanding                 A                           replace A->B               replace B->C
```

在 `mem_req_rdy=1`、固定一拍 response、EX持续提供互不依赖的 memory operation且
`ma_wb_rdy=1` 时，稳态 backend request/response可每拍一笔，同时 outstanding仍不超过1。

图中的 completion 表示 response结果被推入 MA/WB holding，不要求 `rsp_fire` 与 `ma_wb_fire` 同拍。
load formatting和MA/WB register可以让 architectural completion相对response晚一个或若干固定cycle；
只要 pipeline填满后相邻 completion仍能每拍发生一次，throughput就是1/cycle。需要区分：

```text
transaction latency: req_fire(A) -> rsp_fire(A)
completion latency:  rsp_fire(A) -> ma_wb_fire(A)
transaction throughput: adjacent req/rsp fire interval
completion throughput:  adjacent ma_wb fire interval
```

### 6.3 in-order 与 load dependency

MA ingress 可以在旧 transaction 等 response 时暂存至多一条年轻指令，但不得越过旧指令提交。
若年轻指令依赖 outstanding load 的 rd：

- hazard logic 必须识别 pending load rd 与 EX source register；
- 在 load data 尚不可转发时禁止捕获错误 operand；
- 可以在 response 当拍提供经过格式化的 forwarding bypass，或等 response 进入 completion slot 后再放行；
- 依赖链允许产生 data-hazard bubble，不计为独立 hit stream 吞吐失败；
- 不相关的连续 load/store 不得被不必要地全局串行化。

store 的架构副作用仍严格绑定：

```text
target_write = mem_req_fire && mem_req_write && target_selected
```

response 仅表示 store completion，不能再次写。

### 6.4 mixed stream 与 completion collision

memory response 和年轻 non-memory instruction 可能同拍竞争 MA/WB completion slot。MA ingress slot
必须保留年轻指令，先让旧 response 进入 completion；下拍在 completion pop 时再推进年轻指令。
这保证：

- in-order completion；
- 不丢 ALU/branch/CSR result；
- CSR、redirect、BPU update 仍只绑定唯一 EX/MA transfer；
- 连续 non-memory 指令保持一拍吞吐；
- 连续独立 memory 指令保持一拍 request/response 吞吐。

### 6.5 variable latency/backpressure

- request ready 拉低：ingress request valid/payload稳定；
- request fire 后 response 延迟：outstanding metadata稳定，不重复 request；
- completion slot full：`mem_rsp_rdy` 拉低，backend保持 response；
- outstanding 未释放且本拍没有 response fire：禁止第二个 memory request fire；
- response fire 与下一 request fire可以同拍；
- MA/WB fire 与新 completion push可以同拍；
- reset/flush 不产生 ghost response、重复 store 或错误 writeback。

## 7. Backend 的当前能力

当前 `mem_itcm` 和 `soc_bus` 都使用一项 response slot，并具有：

```text
req_rdy = !rsp_vld || rsp_rdy
```

所以它们已经允许旧 response 被接受时同拍接收新 request。当前吞吐瓶颈主要在 IFU 和 MAU
producer/owner，而不是 RTL array 必须空闲额外一拍。S2最小短流测试需要实际覆盖这种 replacement并
检查基本数据顺序；长流、随机反压和 metadata corner矩阵暂时搁置。

## 8. 性能与观测口径

CoreMark 的 UART 输出可能发生在 benchmark `stop_time()` 之后，因此仿真总时长与 benchmark-body
cycles不是同一指标。本轮快速迭代只要求用和当前约172 ms相同的配置/口径重跑简化测试，记录正确性
与耗时改善；如果现成 testbench已有 start/stop cycle则一并记录，不要求新增完整性能计数器。

严格的 pre-Phase0/Phase0/S2三版本 benchmark-body、IPC、各类 stall counter、长流和corner DV已移至
[`dev_log/pending_v12_cache_mem_subsys_deferred_scope.md`](dev_log/pending_v12_cache_mem_subsys_deferred_scope.md)。

## 9. 最终 RTL 控制摘要

### 9.1 IFU

IFU保留原 request holding、单 outstanding metadata和单 response buffer。普通response在被接受的
同一个cycle直接提供 successor request：

```text
rsp_buf_can_push = !rsp_buf_vld || if_id_fire
rsp_rdy          = outstanding && (discard_rsp ||
                   (rsp_buf_can_push && !ras_conflict))
req_vld          = held_req_vld || accepted_normal_rsp
req_addr         = held_req_vld ? held_req_pc : response_pred_next_pc
```

- successor request ready时，response A与request B同拍fire；
- successor request被反压时，将其PC写入原 request holding，下一拍继续保持；
- response buffer支持`if_id_fire(A) + rsp_fire(B)`同拍pop/push；
- redirect/stale response不产生successor request；
- older IF/ID instruction同拍修改RAS且new response为return时，`rsp_rdy`暂停一拍，等待正确RAS top。

### 9.2 LSU/MAU

MAU保留原 EX/MA capture位置并将其改为elastic ingress；没有把request组合前移到EX，也没有新增入口
FIFO。三个位置独立valid：

```text
existing MA ingress       r_ingress_vld
one unanswered request    outstanding_r
existing MA/WB holding    r_completion_vld
```

主要推进关系为：

```text
ingress memory pop    = mem_req_fire
ingress nonmem pop    = no outstanding && completion_can_push
EX/MA replacement     = ex_ma_fire && ingress_pop
outstanding replace   = mem_rsp_fire && mem_req_fire
completion replace    = ma_wb_fire && completion_push
```

当ingress为空但仍有outstanding load时，MAU保守拉低`o_ex_ma_rdy`，避免依赖指令在load forwarding可见
之前离开EX。连续独立memory stream不会触发该空槽情形：A从ingress发request时可同拍capture B，之后
每拍执行`response A + request B` replacement。
