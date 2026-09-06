# OpenC906 Cache、BIU 与 SoC 存储拓扑参考机制汇总

**整理日期**：2026-09-05  
**来源文档**：

- `0_pre-Spec_cache_support_strategy.md`
- `1_pre-Spec_bus_mmio_and_axi_topology_strategy.md`

---

## 1. 文档范围

本文汇总两份 pre-Spec 文档中与 OpenC906 参考设计有关的机制，重点说明：

1. OpenC906 的 I/D Cache 组织、替换、refill、写回和维护机制；
2. Cache、BIU、AXI、APB 与物理存储之间的层次关系；
3. OpenC906 demo SoC 的真实存储拓扑和地址译码；
4. 哪些思想适合当前 RV32IM BPU Cache 项目借鉴，哪些复杂机制应主动删减。

需要区分两类内容：第 2～4 节是源文档明确给出的 OpenC906 实现事实；第 5～7 节是结合总线策略文档提炼出的参考抽象和本项目取舍，不表示 OpenC906 RTL 必然采用文中每一项简化规则。

## 2. OpenC906 L1 Cache 基本组织

OpenC906 采用分离的一级指令 Cache 和数据 Cache。默认宏配置及 CPUID 报告的主要参数如下。

| 特性 | I-Cache | D-Cache |
|---|---|---|
| 默认容量 | 32 KiB | 32 KiB |
| 相联度 | 2-way | 4-way |
| Cache line | 64 B | 64 B |
| 替换状态 | 每组 1-bit FIFO，两个 way 交替 | 每组 one-hot FIFO 指针，四个 way 循环 |
| 写策略 | 只读 | write-back；write-allocate 可由 `mhcr.wa` 控制 |
| miss 路径 | AXI refill，并支持顺序预取 | LFB refill、dirty victim、Store Buffer、Victim Buffer |
| 维护操作 | enable、invalidate、按地址/索引操作 | enable、clean/invalidate、按地址/索引操作 |
| 性能机制 | refill 旁路、预取 | 多 LFB、写合并/前递、预取、阵列仲裁 |

### 2.1 替换状态不是 LRU/PLRU

- I-Cache 的每个 tag entry 保存两个 way 的 tag/valid 和一个 FIFO 位；refill 后翻转该位。
- D-Cache dirty array 的低 4 bit 保存四个 way 的 dirty 状态，高 4 bit 保存 one-hot FIFO 指针；refill 完成时循环更新指针。

因此，两者更准确的归纳是 FIFO/round-robin，而不是 LRU 或 PLRU。其价值在于以很小的状态开销获得确定、易实现的替换行为。

### 2.2 refill 与非缓存访问

I-Cache 的 cacheable refill 使用 128-bit AXI beat，`arlen=3`，即用 4 beat 填满一条 64 B cache line。非 cacheable 访问使用单 beat。普通 refill 与预取可使用不同 AXI ID 区分。

这里体现了两个可复用原则：

- cache line refill 使用 burst，设备或其他 uncached 访问保持单次事务；
- 请求类型和返回归属必须在总线事务期间可识别，可由锁存的 source 或 AXI ID 表示。

## 3. D-Cache 的事务化与并发机制

OpenC906 D-Cache 不是单一的 tag/data lookup 模块，而是由多个职责清晰的模块和队列共同完成访存事务生命周期。

| RTL 模块 | 主要职责 |
|---|---|
| `aq_lsu_dc.v` | 命中、miss、别名判断，以及向 LFB/Store Buffer 分发 |
| `aq_lsu_rdl.v` | 读取替换 way、valid/dirty，并组织 victim line |
| `aq_lsu_lfb.v` | 默认 8 个 entry，跟踪多个 refill；末拍写入 tag、dirty 和下一 FIFO 状态 |
| `aq_lsu_stb.v` | 默认 4 个 entry，负责 store 暂存、合并和下发 |
| `aq_lsu_vb.v` | 暂存被替换或由维护操作读出的 cache line |

这些模块共同处理：

- 多个未完成 refill；
- dirty victim 的读出和回写；
- store 暂存、合并与前递；
- tag/data/dirty 阵列端口仲裁；
- 访存依赖、异常和返回归属；
- Cache 维护操作；
- MMU/VIPT alias 与总线 ID 带来的复杂交互。

因此，OpenC906 Cache 的主要复杂度不是相联查找本身，而是并发事务、队列和各类副作用之间的正确协作。它适合作为模块职责和事务拆分的参考，不适合作为当前项目首版的直接缩位模板。

## 4. OpenC906 demo SoC 的存储与地址拓扑

### 4.1 分离 L1 不等于分离物理 SRAM

OpenC906 核内采用 split I/D Cache，但 IFU miss、LSU miss 和 D-Cache writeback 最终都经 BIU/AXI 访问统一的系统物理地址空间。`smart_run` 默认结构应理解为：

```text
split L1 Cache + unified backing memory
```

而不是：

```text
独立指令 SRAM + 独立数据 SRAM
```

### 4.2 demo SoC 的硬件地址译码

`smart_run/logical/axi/axi_interconnect128.v` 对 40-bit AXI 地址的主要分配如下。

| 物理地址范围 | AXI 目标 | 含义 |
|---|---|---|
| `0x0000_0000`～`0x00FF_FFFF` | `axi_slave128` | 16 MiB 统一 SRAM，指令和普通数据均可访问 |
| `0x0100_0000`～`0x0FFF_FFFF` | error slave | 未实现存储区域 |
| `0x1000_0000`～`0x1FFF_FFFF` | APB bridge | 外设窗口，由桥内继续进行子地址译码 |
| `0x2000_0000`～`0xFF_FFFF_FFFF` | error slave | 其余高地址空间 |

统一 SRAM 由 `axi_slave128.v` 中两个 `524288 x 128-bit` 存储体构成。每个存储体为 8 MiB，`mem_addr[23]` 选择低/高 bank，`mem_addr[22:4]` 作为 128-bit word 索引。两个实例共同构成一个连续的 16 MiB SRAM 窗口，并非分别对应 IMEM 和 DMEM。

demo SoC 将 CPU reset base `pad_cpu_rvba` 接为 0，因此处理器从 `0x0000_0000` 开始取指。

### 4.3 软件分区不等于物理分离

`smart_run/tests/lib/linker.lcf` 在统一 SRAM 的前 1 MiB 内进行软件布局：

| 链接区 | 地址范围 | 内容 |
|---|---|---|
| `MEM1` | `0x0000_0000`～`0x0003_FFFF`，256 KiB | `.text`、`.rodata` |
| `MEM2` | `0x0004_0000`～`0x000F_FFFF`，768 KiB | `.data`、`.bss` |

testbench 将 `inst.pat` 装载到偏移 0，将 `data.pat` 装载到偏移 `0x40000`。这与链接布局一致，但二者仍位于同一个物理 SRAM 中。

分析 C906 时必须分开理解三个层次：

1. I-Cache/D-Cache：核内访问路径和缓存副本的分离；
2. `.text/.data`：链接脚本定义的软件布局；
3. SRAM/APB/error slave：SoC 物理地址空间与硬件译码。

三者的边界不必相同。软件区分代码和数据，不要求物理上存在两个 SRAM；物理上使用两个 SRAM，也不要求它们在 CPU 地址空间连续。

## 5. 从 C906 机制抽象出的 Cache—BIU—总线分层

结合两份源文档，可将可借鉴的层次关系整理如下：

```text
IFU -> I-Cache hit ------------------------------> IFU response
             `-- miss/refill --+
                                |
LSU -> memory attribute decoder |
       |                        |
       +-- cacheable -> D-Cache +-- refill/writeback --+
       +-- device ---> uncached/MMIO ------------------+-> BIU -> AXI
       `-- unmapped -> access fault                    |
                                                        `-> response routing
```

### 5.1 Cache 阵列与总线协议解耦

Cache hit 只访问本地 tag/data/dirty 阵列，不需要进入 AXI 或 APB。只有以下事务进入后端：

- I-Cache refill；
- D-Cache refill；
- D-Cache dirty writeback；
- uncached load/store；
- MMIO。

这使 Cache 控制器可以使用较简单的内部 valid-ready 请求接口，由 BIU 统一完成 AXI/AHB 协议转换。

### 5.2 BIU 的职责

作为 C906 复杂总线机制的简化抽象，BIU 应负责：

- 仲裁 I refill、D refill、D writeback 和 uncached/MMIO 请求；
- 将内部事务转换为 AXI 的 AR/R/AW/W/B 通道操作；
- 产生 burst、ID、size 及访问属性；
- 保存请求来源并把 response/error 返回正确模块；
- 处理 back-pressure、顺序、错误和必要缓冲。

“内部有多个请求源”不等于“对 SoC 有多个 AXI Master”。多个源可以先经 BIU 仲裁，再复用为一套完整 AXI Master 接口。

### 5.3 属性译码与 Slave 译码是两次不同决策

同一地址通常经历两次译码：

1. 核内 memory attribute/PMA 译码决定该请求是否可缓存、是否为 Device、是否映射以及访问权限；
2. SoC Interconnect 译码决定 AXI 请求应发送给 SRAM、AXI-to-APB bridge 还是 error slave。

两处应共享同一份 memory map 规格，但职责不能混合。尤其不能先查 D-Cache，发生 miss 后才判断地址属于 MMIO。

## 6. MMIO 与 AXI/APB 参考机制

UART 等 memory-mapped 外设仍由普通 load/store 指令访问，但必须在 Cache lookup 前判定为 Device/uncached，并全程绕过 D-Cache：

```text
load/store
  -> LSU 计算有效地址并检查对齐
  -> 属性译码判定 Device/uncached
  -> 绕过 D-Cache
  -> BIU 形成单 beat AXI 事务
  -> AXI Interconnect 选择 AXI-to-APB bridge
  -> APB decoder 选择具体外设
  -> PREADY/PSLVERR/PRDATA 沿原路径返回 LSU
```

关键约束如下：

- MMIO 不查 tag、不分配 cache line、不设置 dirty，也不允许预取或写合并；
- MMIO 的 AXI 访问使用单 beat，不能扩展为 cache line burst；
- APB adapter 必须锁存地址、数据、strobe、size 和读写属性，并在 `PREADY` 到来前保持 payload 稳定；
- AXI `SLVERR/DECERR` 和 APB `PSLVERR` 应转换为对应的 instruction/load/store access fault；
- error refill 不能设置 valid，错误 store 不能报告成功。

外设可放在统一 AXI 地址空间中的 APB bridge 后面。这样 Cache 流量和 MMIO 虽共享一个对外 AXI Master，但 memory map、顺序和错误路径集中，且其他系统 Master 未来也可访问外设。

## 7. 对当前项目的借鉴与删减边界

### 7.1 建议保留的设计思想

- 采用独立 I/D Cache；
- 在 Cache lookup 前完成 cacheable/device/unmapped 属性判断；
- 使用简单、确定的 round-robin/FIFO 替换，而非实现成本更高的 LRU；
- D-Cache 最终采用 write-back + write-allocate；
- 将前端 lookup、refill 和 dirty eviction 划分为清晰的事务状态；
- 所有 invalidate/clean 等维护操作都具有明确的完成语义；
- 将性能计数器和定向 Cache 测试与 RTL 同步设计；
- 通过 BIU集中处理内部请求仲裁、总线转换、返回归属和错误传播；
- 使用精确地址范围和 error slave 表达稀疏地址空间，避免低位截断造成地址镜像。

### 7.2 首版应主动删减的 C906 复杂机制

- 不固定照搬 4-way D-Cache 和 64 B line；
- 不实现 8-entry LFB、4-entry Store Buffer 和 Victim Buffer；
- 不支持多个 outstanding miss 和复杂 AXI ID 并发；
- 首版不实现预取、critical-word-first 或 early restart；
- 不引入 MMU/VIPT alias、AMO、向量访存和硬件一致性；
- 不复刻 T-Head 私有 Cache 维护指令集合。

### 7.3 推荐的渐进式落点

当前五级单发射、blocking Cache 设计可先保留 C906 的职责分层，同时压缩事务并发度：

```text
split I/D Cache
+ cacheable/device/unmapped 属性译码
+ MMIO 绕过 D-Cache
+ I refill / D refill / D writeback / uncached 的事务级仲裁
+ single outstanding
+ one AXI Master
+ 1-to-N AXI Interconnect
+ AXI memory slave + AXI-to-APB + error slave
```

首版 BIU 应在一笔 burst 的完整生命周期内保持仲裁所有权，并按锁存的 source 返回响应。只有性能计数证明共享端口成为主要瓶颈、下游存储可以真实并行且 Cache 已支持多个 outstanding 后，才有充分理由拆分 I/D AXI Master。

## 8. 核心结论

OpenC906 最值得参考的不是其参数规模，而是其分层和事务化思路：split I/D Cache 负责局部副本，属性译码区分 cacheable 与 Device，BIU组织 refill/writeback/uncached 请求，AXI Interconnect 完成物理 Slave 路由，APB bridge 承接低速外设。

对当前项目，应复用上述职责边界和正确性原则，但将多队列、多 outstanding、多 ID、预取及 MMU 别名等高并发机制降为后续扩展。这样既保留 C906 设计中有价值的架构思想，也能把首版 RTL 和验证规模控制在可解释、可闭环的范围内。
