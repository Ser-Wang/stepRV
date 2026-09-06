# OpenC906 BIU、I/D Cache 请求与 APB 路径实现参考

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-23 23:58
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-08-23 23:58): 基于 OpenC906 BIU、IFU/ICache、LSU 和 smart_run RTL，整理 I/D 请求合并、读写仲裁、AXI ID 返回分流、核内 APB 与外部 AXI-to-APB 两类路径。

---

## 1. 文档目的与证据范围

本文只记录 OpenC906 中与当前总线架构讨论直接相关的实现方式，作为设计参考，不表示要原样移植到当前 RV32IM 项目。

主要 RTL 证据：

- `C906_RTL_FACTORY/gen_rtl/ifu/rtl/aq_ifu_icache.v`
- `C906_RTL_FACTORY/gen_rtl/lsu/rtl/aq_lsu_lfb.v`
- `C906_RTL_FACTORY/gen_rtl/biu/rtl/aq_biu_top.v`
- `C906_RTL_FACTORY/gen_rtl/biu/rtl/aq_biu_req_arbiter.v`
- `C906_RTL_FACTORY/gen_rtl/biu/rtl/aq_biu_read_channel.v`
- `C906_RTL_FACTORY/gen_rtl/biu/rtl/aq_biu_write_channel.v`
- `C906_RTL_FACTORY/gen_rtl/biu/rtl/aq_biu_apbif.v`
- `C906_RTL_FACTORY/gen_rtl/cpu/rtl/aq_sysio_top.v`
- `smart_run/logical/common/tr_axi_interconnect.v`
- `smart_run/logical/axi/axi_interconnect128.v`

核心结论：**OpenC906 的 IFU/I-Cache 与 LSU 有独立的内部 BIU 请求接口，但在 `aq_biu_top` 内被仲裁、转换，最终共用一套对外 `biu_pad_*` AXI Master 接口。** 因此“内部有 I/D 两类请求”不等于 SoC 看到两个 AXI Master。

## 2. OpenC906 的整体请求路径

```text
                                 OpenC906 core

 IFU / I-Cache
   | hit -> instruction pipeline
   |
   `-- ifu_biu_ar* --------------------------------+
                                                      |
 LSU / D-Cache subsystem                              |
   |                                                  |
   +-- LFB read/refill: lsu_biu_ar* ------------------+---> aq_biu_req_arbiter
   +-- STB writes:     lsu_biu_stb_aw/w* -------------+          |
   `-- VB writeback:   lsu_biu_vb_aw/w* --------------+          |
                                                                 v
                                                        +-----------------+
                                                        | APB-window hit? |
                                                        +---+---------+---+
                                                            |         |
                                                   yes      |         | no
                                                            v         v
                                                    aq_biu_apbif   read/write channel
                                                        |              |
                                                   PLIC/CLINT           v
                                                               biu_pad_* AXI Master
                                                                      |
                                                                      v
                                                             external SoC fabric
```

这里有两种不同的 APB 组织，不能混淆：

1. C906 BIU 内部的 `aq_biu_apbif` 把配置窗口请求转到核接口上的 PLIC/CLINT APB 信号；
2. smart_run demo SoC 还可以在核外 AXI Interconnect 中把外设地址送入外部 APB bridge。

二者都是合法系统组织，只是外设归属和桥的位置不同。

## 3. I-Cache 如何发起 BIU 请求

`aq_ifu_icache.v` 直接产生：

```text
ifu_biu_arvalid
ifu_biu_araddr
ifu_biu_arid
ifu_biu_arlen
ifu_biu_arsize/arburst/arcache/arprot
```

关键赋值表明普通 I-Cache 请求和预取请求共用这一组读请求端口：

```text
ifu_biu_arvalid = icache_req || pf_biu_req
ifu_biu_arid    = !icache_req
```

因此 IFU 内部先在普通 refill 与 prefetch 之间选择，再把请求送给 BIU。默认 cacheable I-Cache refill 的 `arlen=3`，结合 128-bit beat，四个 beat 填满 64 B line；uncached 取指为单 beat。

I-Cache hit 完全在 I-Cache 内部完成，不使用 AXI。只有 refill、uncached fetch 或 prefetch 等后端请求才进入 BIU。

## 4. LSU 如何发起 BIU 请求

OpenC906 的 LSU 不是一个单一 D-Cache 模块直接连 AXI，而是多个内部结构产生请求：

```text
LFB (Line Fill Buffer) -> lsu_biu_ar*       # load、D$ refill 等读事务
STB (Store Buffer)     -> lsu_biu_stb_aw/w* # 普通 store/uncached 等写事务
VB  (Victim Buffer)    -> lsu_biu_vb_aw/w*  # dirty victim/writeback 等写事务
```

这些仍是 BIU 的内部 requester，不是三个对外 AXI Master。BIU 负责选择请求、保存写数据来源，并把 response 返回 LSU。

与当前计划的 blocking Cache 相比，C906 有 LFB、STB、VB、多 ID 和更强的 outstanding 能力；应借鉴模块职责，而不应直接复制其队列深度和事务并发。

## 5. BIU 读请求仲裁

`aq_biu_req_arbiter.v` 在读地址通道上直接以 LSU valid 作为选择条件：

```text
lsu_sel     = lsu_biu_arvalid
arb_arvalid = lsu_sel ? lsu_biu_arvalid : ifu_biu_arvalid
arb_araddr  = lsu_sel ? lsu_biu_araddr  : ifu_biu_araddr
```

因此当 IFU 与 LSU 同时提出读请求时，LSU 优先；没有 LSU 请求时才选择 IFU。

```text
                +------------------+
IFU AR -------->|                  |
                | read AR arbiter  |----> selected AR
LSU AR -------->|  LSU priority    |
                +------------------+
```

IFU 的 ready 还显式要求 `!lsu_sel`，所以 IFU 只在真正被选中时看到握手。当前项目若采用类似固定优先级，需要检查连续 LSU 流量是否可能让取指饥饿；对简化版可以使用事务级 round-robin 或“LSU 优先但限制连续 grant 次数”。

## 6. 读 response 如何返回 IFU 或 LSU

C906 用读 response ID 的编码区分来源。`aq_biu_req_arbiter.v` 中：

```text
r_ifu_sel      = (rid[3:1] == 3'b000)
biu_ifu_rvalid = rvalid && r_ifu_sel
biu_lsu_rvalid = (rvalid && !r_ifu_sel) || apbif_rvalid
```

也就是说：

```text
external AXI R ----> inspect RID ----+--> IFU response
                                     `--> LSU response

internal APB response -------------------> LSU response
```

IFU 的内部 ARID 只有 1 bit，进入仲裁器时扩展为 `{3'b000, ifu_biu_arid}`；LSU 使用其他 ID 编码。这样多个内部来源可以共享一个外部 AXI read data channel，而返回仍能找到请求者。

当前项目若坚持 single outstanding，可以先不依赖复杂 ID：在 BIU 接受请求时锁存 `source = I/D/MMIO`，事务完成后按 source 返回。加入多个 outstanding 后，才需要系统化规划 ID 位域、每源队列深度和乱序返回规则。

## 7. BIU 写请求仲裁

写请求只来自 LSU 侧，但有 STB 和 VB 两个内部来源。`aq_biu_req_arbiter.v` 使用：

```text
vb_sel      = lsu_biu_vb_awvalid
arb_awvalid = vb_sel ? lsu_biu_vb_awvalid : lsu_biu_stb_awvalid
arb_awaddr  = vb_sel ? lsu_biu_vb_awaddr  : lsu_biu_stb_awaddr
```

即两者同时有效时 VB 优先。由于 AXI 的 AW 和 W 是独立通道，C906 还使用选择 FIFO 记录已接受的写地址来自 VB 还是 STB，以及它最终应走 APB 还是外部 AXI，随后让对应来源驱动 W channel。

```text
VB AW/W  ----+
             +--> AW arbitration --> source/APB selection FIFO --> W routing
STB AW/W ----+
```

这部分正体现了“BIU 不只是地址 mux”：它还必须维护地址通道与数据通道的事务关联。当前项目若限制 single outstanding，可以在一个 FSM 中锁存写来源，避免首版实现选择 FIFO。

## 8. C906 BIU 内部 APB 路径

### 8.1 APB 窗口命中

`aq_sysio_top.v` 把输入 `pad_cpu_apb_base[39:27]` 锁存为 13-bit base，再生成：

```text
sysio_biu_apb_base = {apb_base[12:0], 27'b0}
```

`aq_biu_req_arbiter.v` 对读写地址比较 `[39:27]`：

```text
apb_ar_hit = arb_araddr[39:27] == sysio_biu_apb_base[39:27]
apb_aw_hit = arb_awaddr[39:27] == sysio_biu_apb_base[39:27]
```

因此这是一个 128 MiB 的可配置核内 APB 窗口。smart_run 中 `pad_cpu_apb_base` 被配置为 `0x4000_0000_00`。

### 8.2 命中后的分流

```text
selected BIU request
       |
       +-- APB window hit --> apbif_ar/aw/w --> aq_biu_apbif
       |
       `-- not hit --------> ar/aw/w --------> external AXI channels
```

APB hit 时，外部 AXI 对应的 `arvalid/awvalid/wvalid` 被抑制；ready 和 response 改由 `aq_biu_apbif` 返回。也就是说请求只走一个目标，不会同时送给 APB 和 AXI。

### 8.3 `aq_biu_apbif` 的转换

`aq_biu_apbif.v` 包含 `IDLE -> WDATA -> REQ -> PEND` 状态机：

- read 可从 IDLE 进入 REQ；
- write 先等写数据，再进入 REQ；
- REQ 对应 APB SETUP；
- PEND 拉高 `PENABLE` 并等待所选 Slave 完成；
- 32-bit APB 数据从 128-bit BIU 数据中依据地址低位选择。

其内部只译码 PLIC 和 CLINT：

```text
aq_biu_apbif
   |-- psel_plic
   `-- psel_clint
```

因此不能把这条路径简单描述为“C906 所有 UART 都从 LSU 直连 APB”。它是 BIU 统一仲裁之后的一个核内 APB 分支，主要服务 PLIC/CLINT；普通 SoC 外设仍可位于核外 AXI fabric 后面的 APB bridge。

## 9. C906 对外仍是一套 AXI Master

`aq_biu_top.v` 内部例化：

```text
aq_biu_req_arbiter
aq_biu_read_channel
aq_biu_write_channel
aq_biu_apbif
```

经过仲裁且未命中内部 APB 的请求分别进入 read/write channel，最终从唯一一组 `biu_pad_*` 端口送出：

```text
biu_pad_ar* / biu_pad_r*
biu_pad_aw* / biu_pad_w* / biu_pad_b*
```

所以对外部 SoC Interconnect 而言，C906 是一个 AXI Master；其 I-Cache 与 LSU并不是两个独立的外部 Master。AXI 的 ID 让这一个 Master 可以标记不同来源和多个事务，并不改变 Master 端口数量。

## 10. smart_run 核外互连和外设路径

OpenC906 demo SoC 还存在核外地址译码。与 `0_pre-Spec_cache_support_strategy.md` 已记录的地址图一致：

```text
C906 biu_pad_* AXI Master
          |
          v
external AXI Interconnect
   |-- 0x0000_0000 ... -> unified AXI SRAM
   |-- 0x1000_0000 ... -> external APB bridge/peripherals
   `-- other holes ----> error response
```

这说明一个 SoC 可以同时具有：

- BIU 内部、面向 core-local PLIC/CLINT 的 APB bridge；
- BIU 外部、面向一般 SoC 外设的 AXI-to-APB bridge。

具体采用哪条路径由地址图和外设归属决定。C906 的实现重点不是“APB 必须放在哪里”，而是把请求来源仲裁、地址窗口分流、协议转换和 response 返回组织在明确层次中。

## 11. 从 C906 可借鉴的设计点

### 11.1 适合当前项目直接借鉴

- I-Cache 与 LSU使用独立内部 request/response 接口；
- 在 BIU 内合并为一个外部 AXI Master；
- 以事务 ID 或锁存 source 将 response 返回正确单元；
- 地址先判断内部 APB窗口，命中后不再驱动外部 AXI；
- 写地址与写数据来源必须保持关联；
- BIU 拆为 request arbiter、read channel、write channel、APB adapter，职责清晰；
- Cache hit 不进入 BIU，只有后端事务才占用总线。

### 11.2 当前项目应简化

- 不复制 C906 的多个 LFB、STB、VB entry；
- 不在首版支持大量 outstanding 和复杂 ID 空间；
- 不实现写选择 FIFO，single-outstanding FSM 锁存来源即可；
- 不照搬 128-bit 数据宽度和 64 B line；
- 不必照搬固定 LSU 读优先级，可以选更易证明无饥饿的事务级 round-robin；
- 不必同时实现内部 APB 和外部 AXI-to-APB，先选一种符合项目目标的路径。

## 12. 对当前项目的映射建议

可以把 C906 的结构缩减为：

```text
                   +------------------------------+
I$ refill -------->|                              |
D$ refill -------->| simple request arbiter       |--> one AXI Master
D$ writeback ----->| source latch, one outstanding|
uncached/MMIO ---->|                              |
                   +------------------------------+
                                  |
                                  `--> optional internal APB adapter
```

建议首版只保留以下状态信息：

```text
active
source = I_REFILL / D_REFILL / D_WRITEBACK / UNCACHED
read_or_write
address
burst_length
beat_count
error_seen
```

如果 UART 采用核外 AXI-to-APB，BIU不需要理解 UART，只需把 uncached 单 beat AXI 事务发出；SoC Interconnect 决定它进入 APB bridge。如果以后增加 core-local APB，再仿照 C906 在 BIU request arbiter 后按窗口分流。

## 13. 最终认识

OpenC906 证明了以下结构是成熟且合理的：

```text
multiple internal requesters
 -> BIU arbitration and protocol handling
 -> optional internal APB branch
 -> one external AXI Master
 -> SoC address interconnect
```

它并没有因为 I-Cache 也需要 refill 就为 I-Cache 单独暴露第二个 AXI Master。C906 通过内部仲裁和 ID 分流换取了统一的对外接口；其复杂度来自并发队列和 outstanding，而不是简单的端口数量。当前项目采用相同的层次划分、但限制 blocking 和 single outstanding，可以获得足够的工程复杂度，同时让验证规模保持可控。
