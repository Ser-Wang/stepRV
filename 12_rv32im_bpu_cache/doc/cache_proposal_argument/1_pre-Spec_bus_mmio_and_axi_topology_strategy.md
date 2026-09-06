# RV32IM BPU Cache 核总线、MMIO 与 AXI 拓扑策略

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-23 23:58
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-08-23 23:58): 整理 Cache 外层总线、稀疏地址路由、MMIO uncached 路径、BIU 职责及一主多从 AXI 拓扑；分析 LSU 直连 APB 和 I-Cache 独立 AXI Master 的可行性与项目取舍。

---

## 1. 文档定位与结论

本文补充 `0_pre-Spec_cache_support_strategy.md` 之后讨论的总线与外设问题，不重复 Cache 容量、相联度、写策略和分 Phase 实现细节。

适合当前项目的总原则是：

1. UART 等 memory-mapped 外设仍由普通 RISC-V `load/store` 指令访问，但对应地址必须被标记为 **Device/uncached**。
2. Cache 阵列本身不使用 AXI/APB；只有 miss refill、dirty writeback 和 uncached/MMIO 请求需要进入后端互连。
3. Phase 0～3 先使用简单 valid-ready 后端即可；需要展示 SoC 总线能力时，再增加单 outstanding 的 AXI Master bridge。
4. 最终推荐让 I-Cache refill、D-Cache refill/writeback 和 uncached/MMIO 成为 BIU 内部请求源，经仲裁后共享 **一个对外 AXI Master**。
5. SoC 侧采用 **一主多从 AXI Interconnect**：地址译码后分别进入 IMEM/DMEM、AXI-to-APB bridge 或 error slave。地址空洞不实例化存储器。
6. LSU 直连 APB 在功能上可行；但更好的模块边界是 LSU 输出统一的 memory request，由独立的属性译码、uncached router 和 APB adapter/BIU 完成协议转换。
7. I-Cache 可以拥有独立 AXI Master，但当前单发射、blocking Cache 项目收益有限，增加的多主互连和验证工作不划算；先采用共享 BIU 更适合求职项目的复杂度目标。

推荐的目标拓扑如下：

```text
                               CPU core
          +--------------------------------------------------+
          |                                                  |
 IFU ---> | I-Cache -- miss/refill -------------------+      |
          |                                           |      |
 LSU ---> | memory attribute decoder                  |      |
          |       |                                   |      |
          |       +-- cacheable --> D-Cache ----------+      |
          |       |                  | refill/writeback      |
          |       +-- device ------> uncached/MMIO ----+      |
          |       `-- unmapped ----> access fault             |
          +--------------------------------------------------+
                                                       |
                          internal request arbitration |
                                                       v
                                                   +-------+
                                                   |  BIU  |
                                                   +---+---+
                                                       |
                                             one AXI Master port
                                                       |
                                                       v
                                      +---------------------------+
                                      | 1-to-N AXI Interconnect    |
                                      +-----+-----------+---------+
                                            |           |
                           +----------------+           +----------------+
                           v                                             v
                   AXI memory slave                              AXI-to-APB bridge
                   / address adapter                                      |
                     |             |                            APB decoder/fabric
                     v             v                              |       |       |
                  IMEM SRAM     DMEM SRAM                         UART   Timer    GPIO

 Unmapped AXI address ------------------------------------------------> error slave
                                                                    (DECERR)
```

## 2. 外设访问是不是 `load/store`

是。RISC-V 的 memory-mapped I/O 把外设寄存器分配到物理地址空间，软件使用普通 load/store 指令访问。例如：

```assembly
li   t0, 0x30000000      # UART base
li   t1, 'A'
sw   t1, 0x0c(t0)        # UART TXDATA
lw   t2, 0x04(t0)        # UART STATUS
```

指令语义虽然与访问内存相同，微架构属性却不同：

| 属性 | 普通可缓存内存 | UART 等 MMIO |
|---|---|---|
| 是否查找/分配 D-Cache | 是 | 否 |
| 是否允许整行 refill | 是 | 否 |
| 是否允许合并、预取 | 视设计而定 | 首版禁止 |
| 访问宽度 | byte/half/word 等 | 由寄存器定义约束 |
| 访问副作用 | 普通数据读写 | 一次读写可能改变设备状态 |
| 完成条件 | Cache hit 或后端响应 | 外设明确返回完成/错误 |

因此不能先访问 D-Cache、等 miss 后才发现这是外设。应在 Cache lookup 前进行地址属性判断：

```text
LSU request
    |
    v
PMA / memory-region decoder
    |-- cacheable --> D-Cache
    |-- device -----> uncached/MMIO path
    `-- unmapped ---> load/store access fault
```

本项目没有 MMU，首版无需完整实现 RISC-V PMA 寄存器组，可以用固定地址范围比较实现 `memory_region_decoder`，但应把输出语义命名清楚，例如：

```text
region_cacheable
region_device
region_executable
region_readable
region_writable
region_mapped
```

## 3. 外设请求经 AXI-to-APB 时如何走

以 UART 地址 `0x3000_0000` 为例，推荐路径为：

```text
load/store
   -> LSU 计算有效地址并检查对齐
   -> memory attribute decoder 判定 Device/uncached
   -> 绕过 D-Cache
   -> BIU 形成单次 AXI 读或写
   -> AXI Interconnect 根据完整地址选择 AXI-to-APB slave
   -> bridge 把 AXI 事务转换为 APB SETUP/ACCESS 时序
   -> APB decoder 选择 UART
   -> UART 的 PREADY/PSLVERR/PRDATA 经原路径返回 LSU
```

该事务不会查找 D-Cache tag，不会分配 Cache line，也不会设置 dirty。AXI 侧通常发单 beat，不应把 MMIO 访问扩展成 Cache line burst。

如果系统已经存在 AHB 子系统，可以采用 `AXI -> AHB -> APB`；若没有复用需求，直接 `AXI -> APB` 少一层状态机、等待和验证边界，更适合本项目。

## 4. 共享 AXI 时到底有几个 Master

“有几个请求源”和“有几个 AXI Master 接口”不是一回事。

```text
I$ refill ---------+
D$ refill ---------+
D$ writeback ------+--> BIU arbiter --> one complete AXI interface
uncached load/store+
```

左侧是多个核内请求源。只要它们先由 BIU 仲裁并复用为一组 AR/R/AW/W/B 通道，对 SoC Interconnect 而言就只有 **一个 AXI Master**。

只有在 I-Cache 和 D-Cache/LSU 各自向 SoC 暴露完整 AXI 接口时，才是两个 Master：

```text
I-Cache AXI Master --+
                     +--> multi-master AXI Interconnect --> slaves
D/LSU AXI Master ----+
```

AXI 的读通道和写通道相互独立，也不表示它们是两个 Master；它们是一套 AXI Master 接口的组成部分。

对当前方案，SoC Interconnect 是一主多从：

| 地址范围示例 | Slave | 处理 |
|---|---|---|
| `0x0000_0000`～`0x0000_7FFF` | IMEM adapter/SRAM | 可缓存指令后备存储 |
| `0x1000_0000`～`0x1000_7FFF` | DMEM adapter/SRAM | 可缓存数据后备存储 |
| `0x3000_0000`～`0x3000_0FFF` | AXI-to-APB | UART 等 Device 区 |
| 其他地址 | error slave | 返回 `DECERR`，核转为 access fault |

IMEM 与 DMEM 之间的空洞在 Interconnect 的地址译码中表现为“不命中任何正常 Slave”，不需要用大存储器覆盖。SRAM adapter 只有在对应窗口命中后才做 `local_addr = system_addr - BASE`。

## 5. BIU、地址属性译码和 Interconnect 的边界

### 5.1 BIU 是什么

BIU 即 Bus Interface Unit。一个较完整的 BIU 通常负责：

- 仲裁 I-Cache refill、D-Cache refill/writeback、uncached/MMIO 等内部请求；
- 把简单内部 valid-ready 事务转换为 AXI/AHB 通道事务；
- 产生 burst、ID、size、protection/cache attribute；
- 接收 response 并按来源返回；
- 处理 back-pressure、错误、outstanding、顺序和必要的缓冲；
- 可选地在内部把特定地址转到 APB，而不送出外部 AXI。

如果一个模块仅根据地址选择 D-Cache 或旁路，它还不能算完整 BIU。建议按职责命名：

| 模块名建议 | 责任 |
|---|---|
| `memory_region_decoder` / `pma_checker` | 判定 cacheable、device、unmapped、权限 |
| `lsu_memory_router` / `cache_bypass_router` | 在 D-Cache 与 uncached 路径之间选择 |
| `biu` / `axi_biu` | 内部仲裁、response 路由和 AXI 协议转换 |
| `axi_interconnect` / `soc_interconnect` | 根据 AXI 地址选择系统 Slave |
| `axi_to_apb_bridge` | 协议转换，不决定是否使用 Cache |
| `apb_decoder` | 在 UART/Timer/GPIO 等 APB Slave 间译码 |

### 5.2 两次地址决策不要混为一层

同一个地址可能在两个位置被译码，但目的不同：

1. 核内属性译码决定“是否允许进入 Cache”和访问权限；
2. SoC Interconnect 译码决定“这个 AXI 事务交给哪个 Slave”。

两者应使用同一份 memory map 规格，避免范围不一致；但不建议把核内 D-Cache bypass 控制与 SoC Slave mux 强行做成一个大组合模块。

## 6. LSU 能否直接作为 APB Master

### 6.1 功能上可行

可以。地址属性译码命中外设段后，可以让请求直接进入一个 APB Master adapter：

```text
                        +--> D-Cache/backend AXI --> memory
LSU -> address router --|
                        `--> APB Master adapter ----> UART/Timer/GPIO
```

但不能把 LSU 的一拍 load/store 信号直接接到 APB 引脚。APB 有明确的两阶段事务：

```text
IDLE -> SETUP(PSEL=1, PENABLE=0)
     -> ACCESS(PSEL=1, PENABLE=1)
     -> 等待 PREADY；采样 PRDATA/PSLVERR 后完成
```

adapter 必须锁存地址、写数据、byte strobe/访问大小与读写属性，并在等待期间保持 APB payload 稳定。返回 `PSLVERR` 时还要转换为 load/store access fault。

还要明确 APB 版本和外设访问宽度：APB4 可用 `PSTRB` 表示 byte lane，较早 APB 接口没有该信号；后者若需要 byte/halfword MMIO，必须由寄存器接口定义低位选取或在 adapter 中处理，不能默认所有外设都支持任意宽度。当前 UART 已规定首版只支持 32-bit MMIO，因此最简单且最清晰的策略是只允许对齐的 `LW/SW`，其他宽度产生访问错误或明确标为不支持。

因此更准确的说法应是“LSU 具有独立 uncached 请求口，该请求口连接 APB Master adapter”，而不是“LSU 内嵌 APB 状态机”。

### 6.2 直接 APB 路径的优点

- CPU MMIO 不占用外部 AXI 端口，理论上不会和 Cache refill/writeback 竞争该端口；
- 对只有一个核和少量片上低速外设的小 MCU，结构直观、逻辑规模较小；
- 可以把 APB 外设和外部存储置于不同 clock/power domain；
- 若 APB 仅连接核内 timer/interrupt controller，可形成边界清晰的 core-local peripheral port。

### 6.3 不合适之处和隐藏成本

1. **核与 SoC 耦合更紧。** LSU 需要感知 APB 或至少多暴露一个专用端口，核移植到 AHB/AXI/Wishbone SoC 时接口更难复用。
2. **出现两条完成路径。** D-Cache/AXI response 与 APB response 必须在 LSU 汇合；异常、flush、请求只接收一次和返回归属都要验证。
3. **顺序问题转移到核内。** 在 MMIO 发出前，必须按项目定义等待旧的 cacheable store/writeback；MMIO 完成前也不能让年轻内存操作越过。以后增加 store buffer 或 outstanding 后，这一问题明显复杂。
4. **地址安全与错误处理分散。** memory map、权限、timeout、错误注入和调试 trace 需要覆盖两套端口。
5. **其他 Master 的可达性较差。** 若以后 DMA、debug master 也要配置 UART/Timer，把外设只挂在 CPU 私有 APB 上会迫使系统增加旁路或第二个 APB Master 仲裁。
6. **未必产生可见并行收益。** 当前核是单发射、blocking LSU；CPU 等待 MMIO 时通常也不能继续执行下一条依赖访存。即使 D-Cache 后台仍能访问 AXI，首版也没有足够 outstanding/队列去利用这种并行。
7. **APB 本身是低吞吐协议。** 它适合寄存器访问，不适合 Cache line refill；必须严格保证只有 Device 请求进入该端口。

“共享 AXI 会影响 D-Cache 访问”是事实，但要看影响是否值得优化：UART 配置和字符发送的 MMIO 频率通常远低于 Cache refill；一笔单 beat MMIO 在 BIU/AXI 上造成的阻塞很短。对于当前项目，先证明正确的 arbitration、ordering 和 error handling，比为了低频冲突增加第二套系统路径更有价值。

### 6.4 三种 SoC 组织方式的比较

| 组织 | 适用情况 | 优点 | 代价 |
|---|---|---|---|
| 单 AXI Master，外部 AXI-to-APB | 通用 SoC、未来可能有 DMA/多 Master | memory map 集中、外设可被其他 Master 访问、核接口干净 | MMIO 与 Cache 流量共享端口 |
| BIU 内部 APB 分支 | PLIC/CLINT 等 core-local 外设 | 外设请求不出核外 AXI，仍由 BIU统一顺序/返回 | 核多一个 APB 端口，地址图和集成更定制化 |
| LSU uncached 口直连 APB adapter | 极小 MCU、固定外设、追求最少 fabric | 实现直观，可隔离外部 AXI | 顺序和错误路径分裂，可复用性与扩展性较弱 |

### 6.5 对本项目的选择

建议按以下顺序演进：

1. Phase 0～3：保留统一 LSU memory request，属性译码后走 D-Cache 或一个简单 uncached/MMIO adapter；UART 不进入 D-Cache。
2. 加 AXI 时：由 BIU 汇合 I/D/uncached 请求，只暴露一个 AXI Master；UART 位于外部 AXI-to-APB 后面。
3. 若希望额外展示 APB 设计：实现独立 `axi_to_apb_bridge`、APB decoder 和 UART/Timer Slave，比把 APB FSM 塞入 LSU 更有简历展示价值。
4. 只有在明确设计 core-local PLIC/CLINT 或需要独立低功耗外设域时，再为 BIU增加内部 APB 分支。

## 7. I-Cache 是否也经过 BIU

推荐是。I-Cache hit 只访问本地 data/tag array；miss 时生成 line refill 请求，进入 BIU，与 LSU/D-Cache 请求仲裁：

```text
I-Cache hit  -> IFU（不进入 BIU）
I-Cache miss -> refill request --+
                                  |
D-Cache miss -> refill request ---+--> BIU --> AXI
dirty victim -> writeback request-+
MMIO         -> uncached request -+
```

首版 BIU 可以很小：

- 一次只接受一个内部事务；
- 固定 AXI ID 或按 I/D 使用两个固定 ID；
- burst 只用于 Cache line，MMIO 为单 beat；
- 持有 grant 直到整个 burst response 完成，避免事务中途换源；
- 初始优先级可让 LSU 高于 IFU，但应加入 bounded wait 或 round-robin，避免连续 D 请求让取指永久饥饿；
- AXI response 必须按已保存的 source 或 ID 返回正确请求者。

单一 Master 不等于所有事务只能完全串行。AXI 读写通道本身独立，且可用 ID 支持多个 outstanding；但本项目为了控制验证规模，应主动限制为 single outstanding，待基本架构稳定后再决定是否增加并发。

## 8. I-Cache 能否另起一个 AXI Master

可以，典型的 Harvard SoC 也常把 instruction master 和 data master 分开。两种方案的取舍如下：

| 维度 | 共享一个 BIU/AXI Master | I/D 两个 AXI Master |
|---|---|---|
| Interconnect | 一主多从，简单 | 至少二主多从，需要每个 Slave 入口仲裁 |
| I/D 并发 | 由 BIU及 outstanding 能力限制 | 可同时发起，但若命中同一 SRAM/DDR 仍会在下游竞争 |
| 地址/ID管理 | BIU集中管理 | 两个 Master 的 ID 域独立，Interconnect 需附加来源信息 |
| ordering/error | 集中、易观察 | response 与错误路径更多，跨 Master 顺序更难统一 |
| 面积与时序 | 较小 | 多一套 AXI 通道、仲裁和 buffering |
| 可扩展性 | 足够支持当前单核 | 更适合高吞吐、独立 I/D outstanding |
| 当前项目展示价值 | BIU 仲裁 + AXI bridge 已有足够内容 | 增量主要落在互连与 DV，Cache 核心收益有限 |

两个 Master 并不能保证两倍带宽。如果 IMEM/DMEM 最终是独立 SRAM Slave，可真实并行；如果 I/D 都访问同一单端口 SRAM 或同一 DDR controller，请求仍会在 Slave 前仲裁。是否拆分应从目标带宽、存储端口数和 outstanding 能力推导，而不是仅因 I/D Cache 分离就拆端口。

对当前五级单发射、blocking I/D Cache，推荐共享一个 AXI Master。以下条件出现后，再评估拆分 I/D Master：

- I$ miss 与 D$ miss/writeback 重叠频繁，BIU成为性能计数中的主要 stall 来源；
- I/D 后备存储确实能并行服务，而不是在下一层重新串行；
- Cache 或流水已经支持多个 outstanding，能利用两个端口；
- 愿意承担 multi-master Interconnect、公平仲裁、response routing 和随机 back-pressure DV。

## 9. 推荐的仲裁、顺序与错误规则

### 9.1 最小仲裁规则

对 single-outstanding 版本，建议事务级仲裁而非 beat 级仲裁：

```text
IDLE
  -> choose one of {D writeback, D refill/uncached, I refill}
  -> latch source, address, length and type
  -> keep ownership through all address/data/response beats
  -> return completion/error to latched source
  -> IDLE
```

D writeback 必须与其后的 D refill 组成不可被同一 miss 状态机打乱的序列。可在每笔事务之间允许 I refill 插入，但不能在一条 AXI burst 的 beat 中途切换请求源。

### 9.2 MMIO 顺序

首版 blocking LSU 可采用保守规则：

- 发 MMIO 前等待更老的 D-Cache miss/writeback/uncached store 完成；
- 一次只允许一笔 MMIO；
- load 在读响应回来后才能写回寄存器；
- store 在 AXI `B` 或 APB `PREADY` 完成后才视为完成；
- MMIO 等待期间，LSU 不接受更年轻访存；
- `fence`/`fence.i` 等待相关写操作完成后再结束。

这会牺牲少量吞吐，但特别适合当前顺序 blocking 核，且便于解释和验证。

### 9.3 空洞与错误

- 核内 `memory_region_decoder` 对明显 unmapped 地址可以直接产生 access fault；
- 若请求已经进入 AXI，而 Interconnect 没有正常 Slave 命中，则路由到 error slave 返回 `DECERR`；
- AXI `SLVERR/DECERR` 或 APB `PSLVERR` 统一转换为 instruction/load/store access fault；
- 错误 refill 不得设置 Cache valid，错误 store 不得被报告为成功；
- 地址范围必须精确比较，不能只比较 `[31:28]` 后让空洞地址镜像到 SRAM。

## 10. 分阶段落地建议

| 阶段 | 总线与外设工作 | 暂不加入 |
|---|---|---|
| Phase 0 | IF/LSU valid-ready；精确地址范围；unmapped error；UART uncached | AXI/APB 完整协议 |
| Phase 1 | I$ refill 作为独立内部请求源 | 多 outstanding |
| Phase 2 | D$ 与 MMIO bypass；保守顺序；I/D 后端仲裁 | Store Buffer、MMIO 并发 |
| Phase 3 | dirty writeback/refill 事务级仲裁；性能计数 | 多 Master |
| Phase 4 | 单 Master AXI burst bridge + AXI-to-APB + UART APB Slave | AXI crossbar、复杂 QoS |
| 可选加分 | Timer/GPIO、timeout/error slave、形式化握手断言 | I/D 双 Master，除非性能数据证明需要 |

这一组织既能展示 Cache，也能展示 PMA/地址译码、BIU 仲裁、AXI bridge、APB bridge 和错误处理，同时保持“blocking、single outstanding、一主多从”的清晰边界。

## 11. 最终建议

本项目现阶段采用以下结构最平衡：

```text
split I/D Cache
 + cacheable/device/unmapped 属性译码
 + MMIO 全程绕过 D-Cache
 + I refill / D refill / D writeback / uncached 的 BIU事务级仲裁
 + one AXI Master
 + 1-to-N AXI Interconnect
 + AXI memory slaves and AXI-to-APB
 + exact sparse address decode and error slave
```

LSU 直连 APB与 I-Cache 独立 AXI Master 都是合法设计，不应表述成“不能做”。但它们解决的是端口隔离和并发扩展问题，而当前项目首先要解决的是可变延迟握手、Cache miss、MMIO 正确旁路、顺序和错误传播。先完成共享 BIU方案，之后用性能计数证明共享端口确实成为瓶颈，再拆端口，是更有工程依据的演进路线。
