# RV32IM BPU 核 Cache 支持分析与分阶段实现策略

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-17 02:00
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-08-17 02:00): 基于 OpenC906 Cache RTL 与 RV32IM BPU 核当前存储、流水和分支预测实现，给出面向校招项目的分阶段 Cache 架构、接口改造、验证和简历表述建议。

---

## 1. 结论先行

不建议把 OpenC906 的 Cache 子系统直接缩位移植，也不建议在当前固定 1 拍 TCM 接口前直接插入 Cache。适合本项目的路线是：

1. 先把取指和 LSU 存储接口改造成可等待、每笔请求只接收一次的握手接口，并提供可配置延迟的后备 SRAM；这是 Cache miss 能正确停顿和恢复的前提。
2. Phase 1 先完成一个 **4 KiB、直接映射、32 B line、阻塞式 I-Cache**，仅允许一个未完成 miss，整行 refill 后恢复取指，`fence.i` 全局失效。
3. Phase 2 增加一个 **4 KiB、直接映射、write-through + no-write-allocate 的阻塞式 D-Cache**。DTCM 地址可缓存；ITCM 数据侧和 UART 均旁路为 uncached。
4. Phase 3 将 I/D Cache 都升级为 **8 KiB、2-way、32 B line、每组 1-bit round-robin**，D-Cache 升级为 **write-back + write-allocate**，加入 dirty eviction；仍保持 blocking、单 outstanding。
5. Phase 3 同步加入基础性能计数；把 AXI burst bridge、critical-word-first 作为可选加分项。不做 MSHR、多未完成 miss、预取、Victim Buffer、复杂 Store Buffer、MMU 别名处理和硬件一致性。

最终推荐配置兼具 tag/data 阵列、组相联、替换、回写、写分配、refill/eviction 状态机、流水反压、MMIO 属性和验证等内容，复杂度足以形成有辨识度的校招项目，但不会进入 OpenC906 那种高并发 LSU 的验证规模。

另一个必须明确的结论是：**当前 ITCM/DTCM 本身就是 1 cycle 的片上 SRAM，Cache 不会天然加速它们。** 应通过可配置后备存储延迟或外部存储接口建立合理性能场景，再比较 no-cache 与 cache；否则 Cache 只会增加面积、miss 代价和控制复杂度，性能数据没有说服力。

## 2. 分析范围与证据来源

本文主要依据以下实现，而不是只复述已有结论：

- OpenC906：`C906_RTL_FACTORY/gen_rtl/cpu/rtl/cpu_cfig.h`、`ifu/rtl/aq_ifu_icache*.v`、`lsu/rtl/aq_lsu_{dc,rdl,lfb,stb,vb}.v`、`cp0/rtl/aq_cp0_{ext_csr,info_csr}.v`。
- OpenC906 已有分析：`work/openc906/my_docs/C906_Cache_Architecture.md` 与 `Riscv_Core_Cache_Design_Proposal.md`。
- 当前核：`11_rv32im_bpu/de/core/{ifu,core,exu,mau}.sv`、`de/soc/{soc_top,soc_bus}.sv`、`de/periphs/mem_{itcm,dtcm}.sv`、`de/defines/config.v` 及 v11 BPU 规格和开发日志。

本文是未来架构建议，不表示这些 Cache 功能已经存在于 `11_rv32im_bpu`。

## 3. OpenC906 的 Cache 支持情况

### 3.1 默认组织

OpenC906 当前默认宏配置为 32 KiB I-Cache 与 32 KiB D-Cache。其 CPUID 信息明确报告 I-Cache 为 2-way、D-Cache 为 4-way，两者 line size 均为 64 B。

| 特性 | OpenC906 I-Cache | OpenC906 D-Cache |
|---|---|---|
| 默认容量 | 32 KiB | 32 KiB |
| 相联度 | 2-way | 4-way |
| Cache line | 64 B | 64 B |
| 替换状态 | 每组 1-bit FIFO，两个 way 交替 | 每组 one-hot FIFO 指针，四个 way 循环 |
| 写策略 | 只读 | write-back；write-allocate 可由 `mhcr.wa` 控制 |
| miss 支持 | AXI refill，另有顺序预取 | LFB refill、dirty victim、Store Buffer、Victim Buffer |
| 维护/控制 | enable、invalidate、按地址/索引操作 | enable、clean/invalidate、按地址/索引操作 |
| 性能机制 | refill 旁路、预取 | 多 LFB、写合并/前递、预取、阵列仲裁 |

OpenC906 的 I-Cache tag entry 包含两个 way 的 tag/valid 和一个 FIFO 位；refill 后翻转 FIFO 位。D-Cache 的 dirty array 低 4 bit 保存各 way dirty，高 4 bit 保存 one-hot FIFO；refill 完成时循环更新 FIFO。因此已有文档把它们归纳为 FIFO/round-robin，而非 LRU/PLRU，是符合 RTL 的。

### 3.2 refill、写回和并发能力

I-Cache 的 cacheable refill 使用 128-bit AXI beat，`arlen=3`，即 4 beat 填满 64 B line；非 cacheable 访问走单 beat。I-Cache 还以不同 AXI ID 区分普通 refill 与预取。

D-Cache 不只是一个 tag/data lookup 模块：

- `aq_lsu_dc.v` 负责命中、miss、别名判断和向 LFB/Store Buffer 分发。
- `aq_lsu_rdl.v` 读取替换 way、valid/dirty，并组织 victim line。
- `aq_lsu_lfb.v` 默认有 8 个 entry，可跟踪多个 refill；refill 末拍写 tag、dirty 和下一 FIFO 状态。
- `aq_lsu_stb.v` 默认有 4 个 entry，支持 store 暂存、合并和下发。
- `aq_lsu_vb.v` 暂存被替换或维护操作读出的 line。

这说明 OpenC906 的难点并不在“4 路比较器”，而在多个队列、阵列端口仲裁、依赖检查、总线 ID、异常、维护操作和 MMU 别名共同作用下的事务生命周期。它适合作为策略和模块职责参考，不适合作为本项目首版结构模板。

### 3.3 值得借鉴与应主动删减的部分

建议保留的思想：

- 独立 I/D Cache；
- cacheable/uncached 属性必须先于 Cache lookup 决定；
- 简单 round-robin 替代 LRU；
- D-Cache 最终采用 write-back + write-allocate；
- refill、dirty eviction 和前端 lookup 分成清晰状态；
- 所有 Cache 维护动作必须有完成语义，不能只发一拍脉冲；
- 性能计数和定向 Cache 测试应与实现一起设计。

本项目应删减：

- 4-way D-Cache、64 B line 的固定照搬；
- 8-entry LFB、4-entry Store Buffer、Victim Buffer；
- 多 AXI ID 和多个 outstanding miss；
- 预取、critical-word-first/early restart 的首版实现；
- MMU/VIPT alias、AMO、向量访存和硬件一致性；
- T-Head 私有 Cache 维护指令集合。

## 4. 当前 RV32IM BPU 核的状态与 Cache 接入约束

### 4.1 已具备的有利基础

- 五级顺序单发射流水已经采用 valid/ready 语义，EX 中的多周期 MDU 也已有 request issued 和一次性 `fire` 思路，可复用于 Cache 请求。
- 取指端已经完成固定 1 拍同步 ITCM 对齐；BPU 使用 16-entry BTB/BHT，预测 next-PC 随指令流水传递，EX/MA fire 时训练和恢复。
- ITCM 为 32 KiB 双端口结构：取指侧只读，LSU 侧可读写；DTCM 为 16 KiB；两者都支持 32-bit、1 cycle 同步读和 byte write mask。
- 地址空间天然可以提供简单属性：ITCM `0x0...`、DTCM `0x1...`、UART `0x3...`，且没有 MMU，因此 Cache 可采用 PIPT，不存在虚实地址 synonym 问题。
- `fence.i` 已在 EX 形成重定向，并使 BPU 失效，可扩展为等待 I-Cache invalidate 完成后再提交。

### 4.2 当前接口不能直接承载 Cache miss

当前 core 顶层的 IF 端只有 `fetch_req/fetch_pc/instr`，没有 request ready、response valid 或错误返回；`ifu.sv` 还把 `o_fetch_req` 常置 1。LSU 端也只有 load/store 请求信号与读数据，没有 request ready/response valid。

这些接口隐含“请求本拍发出、数据固定下一拍返回”的契约。Cache hit 可以勉强模拟这一契约，但 miss 的 refill 延迟可变，无法告诉 IFU/MAU 哪一拍数据有效，也无法可靠阻塞请求发起者。

此外，当前 store enable 由有效 EX payload 组合产生。若以后因 D-Cache miss 让该 payload 停留多个周期，而没有 `req_fire` 或 `req_issued`，同一 store 会被重复接收。当前 MAU 又默认每拍可向 WB 推进，没有等待 memory response 的状态。因此，**Phase 0 是功能正确性要求，不是可选重构。**

### 4.3 Cache 与当前 BPU 的交互

I-Cache 的响应必须携带或对应正确的请求 PC。只有 `if_rsp_valid && if_rsp_ready` 时，IFU 才能把该指令交给 IDU，并依据该 PC 的 `pred_next_pc` 发起下一次请求。不能在 I-Cache miss 期间继续按 BPU 预测推进 `pc_r`。

EX redirect 可能在一个年轻的 I-Cache miss 尚未完成时发生。首版可采用以下简单正确策略：

- 后备总线事务一旦发出必须收完，不强行取消；
- redirect 到来时记录新的 fetch PC，并用一个 epoch/kill 位标记旧 miss 的返回不得进入 IDU；
- 旧 refill 可选择写入 I-Cache，但其 CPU response 必须丢弃；refill 结束后优先服务 redirect PC。

这比加入可取消总线简单，也避免错路径指令在 redirect 后重新变为 valid。

### 4.4 Cache 与当前存储图的属性边界

推荐第一版固定如下：

| 访问来源与区域 | 属性 | 原因 |
|---|---|---|
| IFU 访问 ITCM 区 | I-Cacheable | 正常代码取指 |
| LSU 访问 DTCM 区 | D-Cacheable | 正常数据区 |
| LSU 访问 ITCM 区 | Uncached | 保留测试兼容和自修改代码，避免 I/D 不一致 |
| LSU 访问 UART 区 | Strongly ordered / uncached | MMIO 读写不能被合并、缓存或延迟隐藏 |
| 未映射地址 | Access error | 后续补充 load/store/instruction access fault |

因为 LSU 对 ITCM 的写保持 uncached，软件修改代码后，写已经到达后备 ITCM；`fence.i` 只需等待所有先前数据写完成、全局失效 I-Cache 和 BPU，再从 `PC+4` 取指。这样无需在 Phase 3 为 `fence.i` 扫描并 clean 全部 D-Cache dirty line。

## 5. 推荐的目标微架构

### 5.1 最终推荐参数

| 参数 | I-Cache | D-Cache |
|---|---:|---:|
| 容量 | 8 KiB | 8 KiB |
| 相联度 | 2-way | 2-way |
| Line 大小 | 32 B | 32 B |
| Set 数 | 128 | 128 |
| Offset | `addr[4:0]` | `addr[4:0]` |
| Index | `addr[11:5]` | `addr[11:5]` |
| Tag | `addr[31:12]` | `addr[31:12]` |
| 替换 | 每组 1-bit round-robin | 每组 1-bit round-robin |
| 写策略 | 只读 | write-back + write-allocate |
| outstanding miss | 1 | 1 |
| hit latency | 目标 1 cycle | 目标 1 cycle |

选择 32 B line 而不是照搬 C906 的 64 B，原因是当前后备数据宽度为 32 bit：32 B refill 为 8 beat，已经足以体现 burst、计数器和空间局部性；64 B 要 16 beat，会显著放大首版 miss 状态和仿真时间。Phase 1/2 的 4 KiB 直接映射版本同样有 128 set，升级为 2-way 8 KiB 时可以保持 offset/index 不变，只增加第二个 way 和替换状态，便于 A/B 验证。

### 5.2 模块边界

```text
IFU/BPU <-> icache <-> imem backend adapter <-> ITCM / future AXI

EX/MAU <-> dcache + uncached router <-> dmem backend adapter
                                      |-> DTCM / future AXI
                                      `-> ITCM data port / UART
```

建议新增或演进为：

| 模块 | 责任 |
|---|---|
| `icache.sv` | IF request/response、tag/data lookup、refill、invalidate、redirect kill |
| `dcache.sv` | load/store request/response、写策略、dirty eviction、DTCM cacheability |
| `cache_data_array.sv` | 可替换的寄存器阵列/BRAM/SRAM wrapper，不承载协议 FSM |
| `mem_backend_adapter.sv` | 32-bit line beat 请求，提供可配置 latency/back-pressure；以后可换 AXI bridge |
| `soc_bus.sv` | 地址属性和 uncached/MMIO 路由，不负责 Cache replacement |
| `mau.sv` | 保存单条 LSU 请求 payload，等待 memory response 后才向 WB valid |

不建议把 I/D Cache 写成一个高度泛化的大模块。可以共享参数计算、阵列 wrapper 和简单 beat counter，但 I-Cache 的 redirect/invalidate 与 D-Cache 的 byte store/dirty eviction 责任不同，分开更易验证和面试讲解。

### 5.3 建议的最小事务接口

CPU 到 Cache 使用 decoupled single-beat 请求/响应：

```text
req_valid, req_ready, req_addr
req_write, req_wdata, req_wstrb       // D 侧
rsp_valid, rsp_ready, rsp_rdata, rsp_err
```

后备存储首版可使用相同风格的 32-bit beat 接口，由 Cache FSM 连续请求 line 中 8 个 word；每个 beat 都必须以 `valid && ready` 计数。不要用“固定等待 N 拍后自行加计数器”代替真实握手。

AXI 不是 Phase 1 正确性的必要条件。若后续加入 AXI，建议做独立 bridge：I-Cache 只需 AR/R，D-Cache 需要 AR/R/AW/W/B；仍限制同一时刻一个事务和固定 ID，保留 burst 与 back-pressure，避免把 AXI 五通道状态塞入 Cache lookup FSM。

## 6. 分阶段实现路线

### Phase 0：可变延迟存储协议基线

目标是 Cache 关闭时功能和性能基线仍可运行。

- 为 IF 与 LSU 增加 request/response valid-ready；请求 payload 在 `req_valid && !req_ready` 时保持稳定。
- IFU 仅在真实 instruction response fire 后生成下一预测请求；redirect 能 kill 旧响应。
- MAU 对 load/store 保存 addr/size/sign/wdata/wstrb，并在 response fire 后推进 WB。
- store 只在 request fire 时产生一次副作用；为 EX/MA LSU 请求增加 `req_issued`，语义参考当前 MDU。
- 后备 SRAM adapter 提供 `MEM_WAIT_CYCLES` 或随机 back-pressure 模式；先证明 0、1、若干等待周期均正确。
- Cache disable 模式必须走同一握手接口，作为后续差分基线。

完成标志：ISA/Compliance、BPU on/off、CoreMark 在随机等待下架构结果一致；SVA 能证明请求等待时 payload 稳定、一次指令至多一次 store fire、无 response 不提交 load。

### Phase 1：最小 I-Cache，可最快形成成果

配置：4 KiB、direct-mapped、32 B line、blocking、whole-line refill、一个 miss。

状态可保持为：

```text
IDLE/LOOKUP -> HIT_RESP
            -> MISS_REQ -> REFILL(8 beats) -> INSTALL -> REPLAY/RESP
INVALIDATE -> 逐 set 清 valid 或 valid epoch 翻转
```

首版使用寄存器阵列方便观察；通过功能验证后再接同步 BRAM/SRAM wrapper。reset 不清 data/tag，只清 valid。`fence.i` 全局 invalidate；redirect 对 in-flight CPU response 做 kill。暂不做预取、early restart 和 AXI。

简历上这一阶段已可描述“实现阻塞式直接映射 I-Cache、整行 refill、流水停顿恢复与 `fence.i` 失效”，但还不应写组相联或 D-Cache。

### Phase 2：简单且完整的 D-Cache

配置：4 KiB、direct-mapped、32 B line、write-through、no-write-allocate。

- load hit 从 Cache 返回；load miss refill 整行并 replay。
- store hit 同时更新 Cache word/byte lanes 并写后备存储；只有后备 write response 后才完成。
- store miss 不 refill，直接写后备存储。
- DTCM 为 cacheable；ITCM 数据访问和 UART 始终 uncached。
- 所有访问仍 blocking，无 Store Buffer，因此强内存顺序自然成立。

这一策略没有 dirty eviction，是在加入 D-Cache 时控制风险的关键。它可以先把 byte mask、load sign/size、MMIO bypass、store 单次接收和 I/D 并发仲裁验证清楚。

### Phase 3：推荐的简历最终版

升级为 8 KiB、2-way I/D Cache；每组增加 1-bit replacement pointer。优先使用 invalid way，两个 way 都 valid 时才使用 round-robin victim；只有发生真实 replacement/install 时才翻转指针。

D-Cache 改为 write-back + write-allocate：

```text
LOOKUP
  hit load  -> RESP
  hit store -> merge bytes, set dirty, RESP
  miss      -> choose invalid/RR victim
                 clean/invalid -> REFILL
                 dirty         -> WRITEBACK(8 beats) -> REFILL
              REFILL(8 beats) -> INSTALL
                 load  -> RESP
                 store -> merge bytes, set dirty, RESP
```

仍然不加入 Store Buffer：所有 store 在 Cache 操作完成前阻塞 LSU。这样已经具备完整 write-back Cache 的核心难点，又把 memory ordering、store-load forwarding 和多个 miss 合并排除在项目边界外。

Phase 3 同时增加只读性能计数：I/D access、hit、miss、dirty writeback、uncached access、miss stall cycles。可先通过 debug 层次读取，之后映射到自定义 CSR；性能报告同时给出 no-cache、Phase 1/2、Phase 3，在相同后备延迟下的 CoreMark cycle、miss rate、AMAT 与综合面积/频率。

### Phase 4：只选一到两个加分项

优先级建议：

1. **AXI4 burst bridge**：固定单 ID、单 outstanding，验证 R/W back-pressure 和错误响应。
2. **Critical-word-first + early restart**：refill 未完成时先返回请求 word，但同一 line 仍只允许一个 miss。
3. **1-entry write buffer**：仅用于 write-through/uncached store，与后续 load 做地址冲突检查。

不建议同时展开三个方向。对校招项目，完整验证的 blocking 2-way write-back Cache，通常比功能很多但边界不清的 non-blocking Cache 更有说服力。

## 7. 验证与验收策略

### 7.1 单元测试

- reset 后所有访问 cold miss；data/tag 未复位也不能误命中。
- 同 line 不同 word/byte/half/word，检查读选取和 byte merge。
- 同 index 不同 tag 的冲突替换；2-way 阶段验证 invalid-way-first 和 RR 序列。
- dirty victim 逐 beat 写回地址和数据正确，写回后 refill 正确。
- store miss 在 Phase 2 不分配，在 Phase 3 必须分配并置 dirty。
- refill 与 writeback 每个 beat 在 back-pressure 下只计数一次，地址不跳拍。
- UART/ITCM 数据访问不进入 D-Cache，不产生 tag/dirty 状态。
- `fence.i` 后旧 I-Cache line 和旧 BTB 均不可命中。
- redirect 与 I-Cache miss/refill 同时发生时，旧 response 被 kill。
- memory error 不安装 valid line，不产生寄存器或存储副作用。

### 7.2 SVA 重点

- `req_valid && !req_ready |=> $stable(req_payload)`；
- refill/install 只发生在完整 line 成功接收后；
- Cache hit 必须满足 valid 与 tag 同时匹配；
- dirty 只由 cacheable store hit/allocate store 设置；
- dirty valid victim 覆盖前必须完成全 line writeback；
- MMIO request 不得命中/分配 D-Cache；
- killed IF response 不得形成 IF/ID fire；
- 一条 LSU payload 至多一次 CPU request fire、至多一次 response/异常提交；
- `fence.i` 完成前取指不能越过维护序列。

### 7.3 系统回归与性能报告

- 保留现有 RV32I/RV32M/Zicsr/Zifencei ISA 与 Compliance 全回归，BPU enable/disable 都跑。
- 增加自检 Cache 程序：冲突地址、容量扫描、dirty eviction、自修改代码、MMIO 串行读写。
- 使用 reference memory model 在每个 committed load/store 上做地址、mask、data 对比；write-back 阶段不能只对比后备 SRAM 的即时内容。
- 后备延迟至少覆盖 0、1、固定 5 cycle 和随机 back-pressure；命中率测试固定随机种子。
- 综合分别报告 Cache off、direct-map、2-way WB 三组的面积、Fmax 和 SRAM 规模，避免只展示性能收益。

## 8. 关键风险与控制办法

| 风险 | 后果 | 控制办法 |
|---|---|---|
| 在固定 1 拍接口上硬插 Cache | miss 数据时序错误 | 先完成 Phase 0 握手改造 |
| EX store valid 多拍保持 | 重复写内存或 Cache | 以 request fire 接收一次，并记录 issued |
| I-Cache miss 时 PC/BPU 继续前进 | PC、指令、预测元数据错位 | 仅 response fire 推进 IF payload |
| redirect 与 refill 相撞 | 错路径指令复活 | epoch/kill 返回，事务收完但不交付 |
| UART 被 D-Cache 缓存 | 外设副作用丢失/重排 | 地址属性先判定，MMIO 全程 uncached |
| write-back 后 `fence.i` 只清 I-Cache | 自修改代码仍看到旧主存 | 当前阶段规定 ITCM 数据侧 uncached |
| 同时改相联度、写策略、AXI | 定位困难、验证爆炸 | 按 Phase 单变量升级并保留 A/B 配置 |
| 用 1-cycle TCM 宣称性能收益 | 数据缺乏可信基线 | 引入可配置后备延迟，报告 AMAT/面积/Fmax |
| 为追求“高级”加入 MSHR/预取 | 事务与验证规模失控 | 最终版保持 blocking、single outstanding |

## 9. 建议的工作拆分与交付物

每个 Phase 单独建立 spec/task、RTL、DV、SVA、回归记录和一页性能/综合结果，不要把 Cache 开发写成一个超大任务。

| Phase | 主要 RTL 交付 | 主要证明材料 |
|---|---|---|
| 0 | IF/LSU 握手、MAU wait、backend adapter | 随机等待回归、单次副作用 SVA |
| 1 | direct-map I-Cache | refill 波形、冲突/失效测试、BPU 协同 |
| 2 | WT/NWA D-Cache、uncached router | byte mask/MMIO/自修改代码测试 |
| 3 | 2-way、RR、WB/WA、dirty eviction | miss/writeback 覆盖率、CoreMark、综合对比 |
| 4 可选 | AXI bridge 或 early restart | back-pressure/error 定向与性能增益 |

版本目录建议沿用项目当前的阶段化方式，例如以新版本目录承载 Phase 0/1，而不是在已经完成 BPU 验收的 v11 中同时大改取指和存储协议。具体版本号应在实施 work order 中确定。

## 10. 简历与面试表述

### 10.1 Phase 3 完成后可使用的简历描述

> 为自研 RV32IM 五级顺序流水核设计独立 L1 I/D Cache：8 KiB、2 路组相联、32 B Cache line、round-robin 替换；D-Cache 支持 write-back/write-allocate 与 dirty eviction。实现 blocking refill/writeback 状态机、可变延迟存储握手、MMIO uncached 路由及 `fence.i`/分支重定向协同，并通过随机 back-pressure、ISA/Compliance、CoreMark 和综合 PPA 对比验证。

只有相应功能和数据确实完成后才保留这句话中的参数、AXI/PPA 或性能表述。

### 10.2 面试时应能回答的设计问题

- 为什么当前 TCM 前加 Cache 不一定更快，性能基线如何构造？
- 为什么先做 write-through/no-write-allocate，再升级 write-back/write-allocate？
- blocking Cache 如何冻结流水，同时避免 store 重复接收？
- redirect 到来而 I-Cache miss 未完成时如何保证错路径 response 不提交？
- 为什么 UART 必须 uncached，ITCM 数据侧为什么也暂定 uncached？
- dirty victim 的写回地址如何由 old tag、set index 和 line offset 重建？
- 2-way round-robin 相比 LRU 的面积、时序和验证取舍是什么？
- `fence.i`、D-Cache 写策略和自修改代码之间是什么关系？
- Cache 参数变化如何影响 set/index/tag、SRAM 容量、miss penalty 和 Fmax？

## 11. 最终边界

本项目的理想终点不是复刻 OpenC906，而是完成一套边界清楚、数据可信、可综合验证的嵌入式 L1 Cache：

```text
PIPT split L1 + 2-way RR + blocking single miss
+ D$ write-back/write-allocate + dirty eviction
+ uncached MMIO + fence.i/redirect correctness
+ configurable-latency backend + counters + PPA/performance report
```

在此边界内，项目既有足够的架构与 RTL 复杂度，也能把每个状态、握手和正确性条件讲清楚。OpenC906 的多 LFB、Store/Victim Buffer、预取和多 AXI ID 应作为后续学习对照，而不是本次求职项目完成度的必要条件。
