# task_v12_05：Phase 3 Final L1 Cache 实现工单

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-07 01:30
**Current Version**: v1.3
**Status**: Implementation Complete — User Regression/Synthesis/CoreMark Pending (2026-09-07 02:14) | Scope Revised — Execution Continues (2026-09-07 02:03) | Ready for Execution (2026-09-07 01:59) | Ready for Review (2026-09-07 01:30)

**Version Changelog**:
- **v1.3** (2026-09-07 02:14): 完成8 KiB 2-way同步1RW I/D Cache、RR replacement及D$ WB/WA dirty eviction；两个Phase 3专用定向和全SoC compile通过，等待用户公共回归、综合与CoreMark。
- **v1.2** (2026-09-07 02:03): 按用户决定将performance counters和 `fence.i` I-Cache invalidate移出当前Phase 3执行与验收，登记为deferred；其余2-way同步1RW及D$ WB/WA范围继续执行。
- **v1.1** (2026-09-07 01:59): 用户批准执行；任务进入Phase 3 RTL、专用定向验证与文档更新阶段，公共回归、综合和CoreMark继续保留给用户手动完成。
- **v1.0** (2026-09-07 01:30): 定义8 KiB 2-way最终L1 I/D Cache、同步1RW 64-bit array wrapper、D$ write-back/write-allocate、dirty eviction、`fence.i` invalidate、性能计数及用户保留的全部公共回归/综合/CoreMark验收。

---

# Part I — 任务制定与 Review

本部分是执行前的稳定输入，只记录目标、设计约束、范围、实施顺序和验收标准。Review修订继续更新
本部分及文档版本；开始执行后，不把实施过程、测试结果或bugfix混入本部分。

## A1. 任务目标

在已完成Phase 1/2 blocking direct-mapped I/D Cache基础上，将L1升级为最终功能配置：

- I-Cache：8 KiB、2-way、128 sets、32 B line、read-only、blocking、single outstanding miss；
- D-Cache：8 KiB、2-way、128 sets、32 B line、write-back、write-allocate、dirty state、dirty victim
  writeback、blocking、single outstanding miss；
- 两者使用每set 1-bit round-robin replacement，并优先选择invalid way；
- Cache tag/data访问改为generic synchronous 1RW wrapper合同，Data Array每way逻辑组织为
  `512 × 64 bit`，一次访问64 bit；
- D-Cache继续正确支持byte/halfword/word load/store、CPU/backend backpressure和exactly-once副作用；
- 保持Phase 2的DMEM cacheable、IMEM LSU uncached、UART Device bypass和unmapped benign completion路由。

本任务不引入BIU、AXI/APB、多个outstanding miss、精确地址fault、backing memory扩容、工艺SRAM
macro或FPGA BRAM mapping；performance counters与 `fence.i` invalidate也按用户决定暂时搁置。

## A2. 依据与当前基线

- [`../mainSpec_Cache_Mem-subsys_Feature.md`](../mainSpec_Cache_Mem-subsys_Feature.md)
- [`../phaseSpec_Cache_Mem-Subsys_Roadmap.md`](../phaseSpec_Cache_Mem-Subsys_Roadmap.md)
- [`task_v12_03_phase1_basic_icache.md`](task_v12_03_phase1_basic_icache.md)
- [`task_v12_04_phase2_basic_dcache_mmio_bypass.md`](task_v12_04_phase2_basic_dcache_mmio_bypass.md)
- [`rule_ai_acceptance.md`](rule_ai_acceptance.md)
- [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)

当前可复用基线：

- I/D Cache CPU侧和backing memory侧均为valid-ready word transaction，response可反压；每个Cache最多
  一个unanswered miss/backend word transaction；
- `backing_imem`为32 KiB，`backing_dmem`本阶段继续为16 KiB；两者backend一次传输32 bit；
- Phase 2 LSU router已将DMEM送入D-Cache，IMEM data access与UART绕过D-Cache；
- MAU继续负责load byte/halfword sign/zero extension，D-Cache只返回包含目标byte的32-bit word；
- EX中的 `fence.i` 已在唯一 `ex_commit_fire` 上产生redirect和branch predictor invalidate，但当前仍不
  向I-Cache暴露invalidate事件；该功能按用户决定继续deferred；
- 当前I/D Cache均使用异步RTL array读语义，I$为4 KiB direct-mapped，D$为4 KiB WT/NWA；
- Phase 2公共验收已通过，用户报告 `coremark_10` 基线为103 ms。

## A3. 目标结构与所有权

```text
IFU req/rsp --> final I-Cache --> 32-bit word refill --> backing_imem

MAU req/rsp --> LSU router
                  |-- DMEM Cacheable --> final D-Cache
                  |                         |-- refill read ----+
                  |                         `-- dirty writeback -+--> backing_dmem
                  |-- IMEM Uncached -----------------------------> backing_imem p1
                  |-- UART Device -------------------------------> UART native port
                  `-- Unmapped ----------------------------------> benign completion
```

所有权约束：

- IFU/MAU继续拥有core-side request生命周期、redirect stale drain和load格式化；Cache不得复制这些状态；
- I/D Cache分别拥有lookup、way选择、replacement、refill、atomic install和response holding；
- D-Cache额外拥有dirty、victim snapshot、writeback、store merge与write-allocate；
- backing memory只执行32-bit word transaction，不感知Cache line、way、dirty或replacement；
- LSU router不观察或修改D-Cache内部line，只负责属性分流和response ownership；
- LSU对IMEM的读写仍走uncached backing IMEM；本任务不新增I/D Cache coherence机制；
- 本阶段不实现performance counters，也不新增CSR、MMIO寄存器或软件ABI。

## A4. Cache几何与地址分解

每个Cache总容量：

```text
2 ways × 128 sets × 32 B = 8192 B = 8 KiB
```

地址字段：

```text
31                     12 11             5 4       3 2 1       0
+------------------------+----------------+---------+-+---------+
|       tag[31:12]       | set[11:5]      | chunk   |w|  byte   |
+------------------------+----------------+---------+-+---------+
          20 bits             7 bits        2 bits  1    2 bits
```

- line offset：`addr[4:0]`；word offset：`addr[4:2]`；
- 64-bit chunk index：`addr[4:3]`；chunk内word select：`addr[2]`；
- little-endian mapping：`addr[2]==0`选择chunk `[31:0]`，`addr[2]==1`选择 `[63:32]`；
- 每way Data Array为512 entries：entry address `{set[6:0], chunk[1:0]}`；
- 每way Tag Array为128 entries × 20 bit；valid、D$ dirty和round-robin metadata按set/way保存；
- reset清valid、dirty和replacement，不要求清tag/data array内容；
- refill/writeback line base均按32 B对齐；backend仍依次传输8个32-bit word。

## A5. Synchronous 1RW Cache Array合同

### A5.1 Shared generic wrappers

新增共享generic RTL wrapper，至少形成以下逻辑接口：

- `cache_data_array_1rw`：512 × 64 bit、单端口、synchronous read、synchronous byte-mask write；
- `cache_tag_array_1rw`：128 × 20 bit、单端口、synchronous read/write；
- I/D Cache各自每way实例化一份Data Array和一份Tag Array；way0/way1可在同拍读取同一个set/chunk；
- `enable`在上升沿采样；read data在该沿后对应本次read地址并保持到下一次有效read；
- 单实例每拍只能read或write一种操作，不依赖同地址read-during-write返回旧值或新值；
- controller不得从wrapper内部array做组合旁路，也不得依赖层次化存储布局完成正常功能；
- byte write mask宽8 bit，bit 0对应64-bit data最低byte；tag write不需要mask；
- wrapper先用可综合RTL model实现。SMIC55 macro、Vivado BRAM及三模式等价性仍属于Phase 6。

### A5.2 Lookup与response

- CPU request仅在valid-ready fire时被接受，同时向两个way发起同set tag read和目标64-bit chunk read；
- 下一拍使用同步read output与已锁存的request metadata做hit compare，禁止用当拍CPU地址组合读array；
- 两way最多一个hit；若出现双hit，定向/SVA应报错，功能选择固定way0以避免X扩散；
- hit response在上游接受前保持valid/data稳定，期间不得改写承载该response的array输出；
- response A被接受时允许同拍接受request B并发起B的同步lookup，维持Phase 0 S2 elastic replacement合同；
- miss处理、store-hit data write或install占用array端口时Cache保持blocking，不接受额外CPU request。

## A6. Replacement与metadata规则

每set一个 `rr` bit，其含义固定为“两way都valid时下一次选择的victim way”：

1. way0 invalid时选择way0；
2. 否则way1 invalid时选择way1；
3. 两way均valid时选择 `rr[set]`；
4. line成功install后设置 `rr[set] = ~victim_way`；
5. hit不更新round-robin bit；
6. reset将所有 `rr` 清零，因此空set的确定性安装顺序为way0、way1，之后首先替换way0。

Victim way、victim tag、valid/dirty和原始CPU request metadata必须在miss分类时锁存；后续同步array
读取或backend反压不能让这些信息随CPU输入变化。

## A7. I-Cache必须实现的行为

### A7.1 Hit、miss与install

- I$ hit从命中way的64-bit chunk选择正确32-bit instruction word并返回；
- miss按A6选择way，保持目标way invalid，顺序请求line base + 0/4/.../28；
- backend request只在fire时推进request序号，response只在fire时收集对应word；
- 两个相邻32-bit refill word组成一个64-bit chunk，使用目标way的1RW Data Array完成4次chunk write；
- tag/data全部写完后才原子置valid并更新round-robin，不能暴露半条line；
- refill期间不修改另一个way；同set第二条line装入后，两条line均应可命中；
- 原始miss response返回正确word，response backpressure不得重复refill或install。

### A7.2 `fence.i` 当前边界

`fence.i` I-Cache invalidate按用户决定暂时搁置。本任务保持既有行为：`fence.i`继续执行流水线redirect与
branch predictor invalidate，但不清I-Cache valid。LSU修改backing IMEM后，既有I-Cache副本可能stale；
该限制必须记录为Deferred/Not Run，不得写成PASS。

## A8. D-Cache必须实现的行为

### A8.1 Load hit与store hit

- load hit从命中way/64-bit chunk选择正确32-bit word返回，不产生backing DMEM transaction；
- store hit在命中chunk内按原始4-bit `wmask`和`addr[2]`映射为8-bit byte mask，执行一次local
  Data Array write并置该way dirty；
- store hit不再执行Phase 2 write-through backend write；local data write完成后返回一次zero completion；
- byte/halfword/word store未覆盖的byte必须保持，随后load hit必须观察到merge后的值；
- CPU response反压不得重复store array write或dirty更新。

### A8.2 Clean/invalid victim refill

- load miss和store miss都按A6选择victim，store miss必须write-allocate；
- invalid或valid-clean victim不得产生writeback transaction；目标way保持invalid后进入8-word refill；
- refill response完整收集到line buffer后，store miss先把原始wmask/wdata合并到目标word；
- 通过4次64-bit chunk write和一次tag install完成line安装，最后原子设置valid；
- load miss安装为clean，返回refill中的目标word；store miss安装为dirty，返回zero completion；
- store miss不得向backing DMEM立即写原store，数据只在后续dirty eviction时写回。

### A8.3 Dirty victim snapshot与writeback

- valid+dirty victim必须在任何refill覆盖前先完整保存victim tag和4个64-bit chunk；
- controller用选中way的同步1RW端口依次读取4个chunk到256-bit victim buffer；
- victim writeback地址使用 `{victim_tag, request_set, 5'b0}`，按地址升序发出8个32-bit全字写；
- 每个writeback word必须保持addr/write/wmask=`4'b1111`/wdata稳定直到backend request fire；
- 每个backend write只允许一次request fire，并等待对应response后再推进，不能因request/response反压
  重复副作用、跳word或乱序；
- 8个write response全部接受后才视为dirty eviction完成，随后清目标way valid/dirty并开始新line refill；
- refill不得早于writeback完成；另一个way及其他set不受影响；

### A8.4 Store miss merge与可见性

- write-allocate store miss必须先取得整条refill line，再对line buffer执行一次byte-mask merge；
- 若目标word是最后一个refill word，merge仍必须使用返回的新数据而不是旧buffer值；
- store completion仅在merge后line完整install并标dirty后产生；
- eviction前backing memory允许仍是旧值，D$ load必须看到cache中更新值；
- dirty eviction后读取backing memory应看到所有已合并byte，且再次访问被逐出地址应由refill取得新值。

## A9. Backend、reset与系统集成

- I$ refill及D$ refill/writeback继续复用现有32-bit valid-ready backend合同，不在本Phase改成64 bit；
- 同一D-Cache miss内部backend阶段严格串行：dirty snapshot → dirty writeback → refill → install；
- backing memory response当前没有error sideband，因此不得虚构PASS的error验证；valid只在完整install后设置；
- reset中止Cache控制状态并清valid/dirty；已被backend接受的writeback word副作用不回滚，也不得
  在reset后重发；backing memory内容不由reset清除；
- `soc_top`接入新Cache与wrapper，不改变top-level芯片IO；
- Phase 2 `soc_bus`地址分类保持：high nibble `0x1` DMEM cacheable、`0x0` IMEM uncached、`0x3`
  UART Device、其他unmapped benign completion；
- IMEM LSU和UART访问不得分配D$、修改D$ dirty或增加D$ access/hit/miss；
- filelist必须加入shared cache array wrappers，仿真和综合使用同一generic wrapper源。

## A10. 暂时搁置的观测功能

按用户2026-09-07 02:03决定，本任务不实现或验收任何performance counter，包括I/D access/hit/miss、
dirty writeback、uncached access和miss stall cycles。不得保留未接线或未经验证的counter RTL，也不得为
counter新增CSR/MMIO ABI。后续恢复时应单独定义计数宽度、唯一事件、overflow和软件可见性。

## A11. 极速迭代范围与deferred策略

### A11.1 本轮明确不实现

- non-blocking Cache、MSHR、hit-under-miss、多个outstanding backend transaction；
- store buffer、write combining、prefetch、critical-word-first或early restart；
- pseudo-LRU/random/LRU replacement；本阶段只实现定义明确的1-bit round-robin；
- BIU、I/D arbitration、64-bit AXI、burst、AXI/APB interconnect或UART APB化；
- backing DMEM 16 KiB到32 KiB扩容；
- SMIC55 SRAM macro、macro model/db切换、FPGA BRAM mapping或形式等价；
- 精确IMEM/DMEM/UART范围、跨界检查、unmapped/backend error与instruction/load/store access fault；
- D-Cache flush/clean/invalidate指令、DMA coherence或I/D hardware coherence；
- `fence.i` I-Cache invalidate及in-flight fill抑制；
- 全部performance counters及其CSR/MMIO暴露、overflow、冻结/快照或privilege控制；
- 固定hit latency/IPC/CoreMark性能硬门槛和Cache流水化优化。

### A11.2 已知边界但不作为本轮验证门槛

- reset落在dirty snapshot、8个writeback word、refill、4个install chunk每个边界的穷举组合；
- CPU/backend交叉随机反压、所有set/chunk/word/byte offset和长时间thrash scoreboard；
- wrapper同地址read/write collision；controller设计应避免依赖其返回语义，本轮不穷举物理macro行为；
- LSU写backing IMEM与I$ refill同拍的memory read-during-write物理语义；
- backend error导致部分dirty writeback或refill失败；在error sideband加入前无法闭环；
- dirty Cache内容不会在仿真自然结束时自动flush，TB检查backing memory前必须显式制造eviction。

执行中发现新边界时：影响A13.1核心定向则当轮修复；不影响最小核心路径则在
[`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)
追加“现象/风险、当前接受行为、后续触发条件、建议验证”，本轮不扩展成随机corner matrix。

## A12. 预期文件范围

| 文件 | 预期修改 |
|---|---|
| `de/core/cache_data_array_1rw.sv` | 新增共享512 × 64-bit synchronous 1RW generic data wrapper |
| `de/core/cache_tag_array_1rw.sv` | 新增共享128 × 20-bit synchronous 1RW generic tag wrapper |
| `de/core/icache.sv` | 升级8 KiB 2-way I$、同步lookup、RR和refill/install |
| `de/core/dcache.sv` | 升级8 KiB 2-way WB/WA D$、dirty snapshot/writeback和store merge |
| `filelists/filelist_rtl.f`、`filelist_sim_sram.f` | 纳入shared generic Cache array wrappers |
| `dv/tb_icache_final.sv` | Phase 3 I$ 2-way/RR/synchronous array定向 |
| `dv/tb_dcache_final.sv` | Phase 3 D$ WB/WA/dirty eviction/router定向 |
| `dv/tb_icache_basic.sv`、`tb_dcache_basic.sv` | 旧策略定向按需要重命名/替换，不能保留已知必FAIL的make目标 |
| `../sim/makefile` | 新增统一目录运行的 `sim_phase3_icache`、`sim_phase3_dcache`目标 |
| `doc/readme_mem_config.md` | 更新最终L1几何、策略、array组织与preload说明 |
| `doc/dev_log/pending_v12_cache_mem_subsys_deferred_scope.md` | 仅追加执行中分析后明确搁置的新边界 |
| `doc/dev_log/log_dev_v12.md` | Phase 3完成并经用户验收后追加简短摘要 |

允许按实现需要新增小型line buffer/helper或Cache SVA文件；不得顺带重构MAU、IFU、BPU、backing
memory或pipeline，除非A13.1暴露现有接口合同级错误。用户当前对roadmap及 `.gitignore` 的未提交修改
不属于本任务，不得覆盖。

## A13. 验证与验收

### A13.1 AI执行的Phase 3最小定向验证

AI只允许运行本小节两个专用定向测试及非功能性的文本/编译检查。所有命令必须从
`work/my-RISCV-Projs/sim`运行；禁止在设计 `dv/` 目录生成build结果。

1. I-Cache final directed：

```text
make sim_phase3_icache DESIGN_NAME=../12_rv32im_bpu_cache
```

同一TB至少覆盖：

- cold miss的8个32-bit refill、4个64-bit chunk install及正确word返回；
- 同set A/B依次装入way0/way1并均能命中；C按RR替换way0且B保留；
- invalid way优先、hit不改变RR、不同set互不污染；
- synchronous lookup至少跨一个时钟边界，不允许CPU地址组合读array；
- response backpressure稳定及response A/request B同拍replacement；

2. D-Cache final directed：

```text
make sim_phase3_dcache DESIGN_NAME=../12_rv32im_bpu_cache
```

同一TB至少覆盖：

- cold load miss、warm load hit、两way共存、invalid-first及第三tag RR clean replacement；
- byte/halfword/word store hit只改目标byte、置dirty且无backend write-through；
- store miss执行write-allocate，backing memory eviction前保持旧值，cache load看到新值；
- dirty victim 4个64-bit chunk snapshot、8个有序exactly-once word writeback、随后8-word refill；
- writeback address使用victim tag而非新request tag，逐出后backing memory包含完整merge结果；
- clean victim不writeback，另一个way不受污染；
- backend request和CPU response反压、response/request同拍replacement；
- IMEM/UART重复访问均绕过D$，unmapped保持benign completion；

两个定向测试必须报告 `[PASS]`，且无新增SVA/Assertion error。若失败，AI可用缩小版定向或波形进行
根因定位；AI不得自行转跑任何ISA、Compliance、synthesis或CoreMark命令。

### A13.2 用户手动ISA与Compliance验收

以下全部由用户在 `work/my-RISCV-Projs/sim` 手动运行并反馈，AI不得代跑：

```text
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32i DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../12_rv32im_bpu_cache
```

标准：

- ISA：`rv32ui` 41/42 PASS，仅允许既有 `ma_data` FAIL；`rv32um` 8/8 PASS；
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
- 不得出现新的simulation、SVA或assertion failure。

如需先跑 `ld_st`、`jal` 或单个 `I-FENCE.I-01` 缩小公共回归问题，也仍由用户执行，AI只根据用户
提供的首错日志/波形进行返修。

### A13.3 用户手动synthesis验收

由用户在 `work/my-RISCV-Projs/syn` 手动运行，AI不得代跑：

```text
make check DESIGN_NAME=12_rv32im_bpu_cache
```

要求elaboration/synthesis check PASS；不得把generic wrapper错误推迟到Phase 6。Phase 6仅负责macro/
BRAM mapping，不负责修复本阶段RTL不可综合问题。

### A13.4 用户手动CoreMark验收与记录

由用户在 `work/my-RISCV-Projs/sim` 手动运行，AI不得代跑：

```text
make sim_userprog name=coremark_10 DESIGN_NAME=../12_rv32im_bpu_cache
```

要求程序正常完成、无新的simulation/SVA/assertion failure，并记录运行成绩（ms）。与Phase 2用户报告
的103 ms对比仅作性能观察，本任务不设置未经验证的硬阈值；若出现明显退化，再决定是否另开性能观测/
优化工单。

### A13.5 状态关闭规则

- RTL与A13.1完成后，状态只能更新为
  `Implementation Complete — User Regression/Synthesis/CoreMark Pending`；
- ISA、Compliance、synthesis及CoreMark任一项未收到用户结果时，不得标记`Completed`，也不得在
  dev log中写成PASS；
- 只有用户反馈A13.2、A13.3、A13.4全部完成且满足标准后，才更新task为`Completed`并在
  `log_dev_v12.md`新增Phase 3条目，记录用户报告的CoreMark成绩。

## A14. 推荐实施顺序

1. 固定shared 1RW wrapper端口、read latency、byte mask和不依赖read-during-write的合同，先做小型
   wrapper directed sanity。
2. 将I$升级为2-way同步lookup，完成invalid-first/RR、8-word refill到4个64-bit chunk的atomic install。
3. 将D$升级为2-way同步lookup，先完成load miss/hit、clean replacement和write-allocate line install。
4. 完成store hit/store miss byte merge、dirty metadata、victim 4-chunk snapshot和8-word writeback。
5. 加入response holding/replacement，保持Phase 2 router行为。
6. 更新SoC、filelists、定向TB、make target和memory配置文档，只运行A13.1。
7. 分析corner；核心错误当轮修复，其余登记pending后停止扩验。
8. 更新task执行记录并通知用户手动完成A13.2～A13.4；收到完整结果后再更新dev log并关闭任务。

## A15. Review记录

v1.0初稿经用户确认，2026-09-07 01:59进入执行。后续需求变更仍在本小节追加独立条目并同步更新
header版本/状态；执行结果统一记录在Part II。

---

# Part II — 执行、验证与后续修复记录

本部分从任务状态进入执行后开始填写。每轮实现、返修或bugfix使用独立的“Execution Round”，不得与
Part I任务定义混排，也不得把多轮结果堆在同一级连续编号中。

## E0. 记录规则

每轮至少记录：

- 开始原因与本轮目标；
- 实际修改文件和关键设计决策；
- 只在 `work/my-RISCV-Projs/sim` 执行的Phase 3专用定向命令与结果；
- 首个错误时序和根因（若本轮是bugfix）；
- 新增deferred边界及其pending文档链接；
- 本轮结束状态和下一执行责任人；
- ISA、Compliance、synthesis、CoreMark必须明确标记为用户手动结果或Pending，禁止AI代跑。

## Execution Round 1 — Phase 3初始实现（2026-09-07 01:59）

### E1.1 范围调整

- 2026-09-07 02:03用户要求暂时搁置performance counters和 `fence.i` I-Cache invalidate；已在开始
  实现后立即移除相关拟议端口/RTL，不保留未验证counter或invalidate逻辑。
- task Part I升级为v1.2；两项边界同步登记到
  [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)。

### E1.2 实现

- 新增 `cache_data_array_1rw.sv`：每实例512 × 64 bit、同步读、8-bit byte-mask同步写；新增
  `cache_tag_array_1rw.sv`：每实例128 × 20 bit同步1RW Tag Array。controller不读取wrapper内部array，
  不依赖read-during-write语义。
- `icache.sv`升级为8 KiB、2-way、128-set blocking I-Cache：CPU request fire同时发起两way同步
  tag/chunk lookup；invalid way优先、两way valid时使用per-set 1-bit RR；8个32-bit refill response收集为
  256-bit line，经4次64-bit chunk write和tag write后原子置valid；保留response holding及同拍replacement。
- `dcache.sv`升级为8 KiB、2-way write-back/write-allocate blocking D-Cache：load/store同步lookup，
  store hit用8-bit chunk byte mask本地更新并置dirty，不再write-through；store miss整线refill后merge并
  dirty install。
- D$ dirty miss顺序固定为4次同步64-bit victim read → 8次32-bit full-word writeback（逐word等待
  response）→ 8次32-bit refill → 4次64-bit install；victim tag在miss分类时锁存，writeback完成前不覆盖
  victim，clean/invalid victim直接refill。
- 更新sim/syn filelist、`config.v`说明和统一 `sim/makefile`；新增 `tb_icache_final.sv`、
  `tb_dcache_final.sv`，移除旧Phase 1/2策略专用make目标，避免保留已知策略不兼容的执行入口。
- `soc_top`、`soc_bus`、core和backing memory接口无需修改，继续复用Phase 2路由与32-bit backend合同。

### E1.3 AI最小定向验证

均从 `work/my-RISCV-Projs/sim` 执行，未运行任何ISA/Compliance程序、synthesis或CoreMark：

- `make sim_phase3_icache DESIGN_NAME=../12_rv32im_bpu_cache`：PASS，`1_540_000 ps`；覆盖同步lookup、
  两way共存、invalid-first、RR replacement、hit不更新RR、8-word refill/4-chunk install、response
  backpressure及response/request replacement。
- `make sim_phase3_dcache DESIGN_NAME=../12_rv32im_bpu_cache`：PASS，`2_600_000 ps`；覆盖clean
  replacement、store miss WA、store hit无WT、byte/halfword/word merge、dirty 4-chunk snapshot、8个有序
  exactly-once writeback后再8-word refill、backend request反压、CPU response replacement及IMEM/UART/
  unmapped路由。
- 全SoC VCS elaboration/compile：首次手工compile命令因漏列TB中 `bind` 使用的既有SVA模块而失败，
  不是RTL错误；补入 `sva_soc_bus.sv`、`sva_exu_lsu.sv`、`sva_csr.sv`、
  `sva_mem_transaction.sv` 后compile PASS。仅编译，未启动ISA仿真。
- `git diff --check HEAD`：PASS。

### E1.4 Deferred / 已知边界

- 按用户决定，performance counters和 `fence.i` I-Cache invalidate均为Deferred/Not Run；不得从
  本轮 `rv32Zifencei` 后续公共PASS推导I-Cache coherence已实现。
- BIU/AXI、backend error、精确地址/access fault、32 KiB backing DMEM、SRAM macro/BRAM mapping及随机
  corner matrix继续保持既有deferred范围。
- 本轮未新增其他影响核心定向的功能边界。

### E1.5 结果与下一责任人

Phase 3 RTL、专用定向验证、全SoC compile和文档更新完成。任务状态为
`Implementation Complete — User Regression/Synthesis/CoreMark Pending`。

以下均未由AI运行，等待用户按A13.2～A13.4手动完成并反馈：

- ISA：rv32ui、rv32um；
- Compliance：rv32i、rv32im、rv32Zicsr、rv32Zifencei；
- synthesis：`make check DESIGN_NAME=12_rv32im_bpu_cache`；
- `coremark_10`功能结果和运行成绩。

收到全部验收结果前，不更新 `log_dev_v12.md` Phase 3完成项，也不将task标记为`Completed`。
