# task_v12_03：Phase 1 Basic I-Cache 实现工单

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 23:22
**Current Version**: v1.2
**Status**: Completed (2026-09-07 00:50) | Implementation Complete — Public Acceptance Pending User Run (2026-09-07 00:42) | Ready for Execution (2026-09-07 00:38) | Ready for Review (2026-09-06 23:22)

**Version Changelog**:
- **v1.2** (2026-09-07 00:50): 记录用户完成公共ISA、Compliance与synthesis验收，并补记 `coremark_10` 运行成绩81 ms；任务关闭为Completed。
- **v1.1** (2026-09-07 00:42): 完成Phase 1 I-Cache、backing IMEM重构、定向验证及两个SoC smoke；公共回归和synthesis check等待用户运行。
- **v1.0** (2026-09-06 23:22): 定义4 KiB direct-mapped blocking I-Cache的最小实现、极速迭代边界、核心定向验证和用户保留的公共验收；采用任务制定/Review与分轮执行记录分区格式。

---

# Part I — 任务制定与 Review

本部分是执行前的稳定输入，只记录目标、设计约束、范围、实施顺序和验收标准。Review修订继续更新
本部分及文档版本；开始执行后，不把实施过程、测试结果或bugfix混入本部分。

## A1. 任务目标

在 Phase 0/Phase 0 S2 的 IF request/response valid-ready合同上加入最小blocking I-Cache：

- 4 KiB容量、direct-mapped、32 B cache line、read-only；
- 128 lines，每line 8个32-bit word；
- 同一时刻最多处理一个blocking miss，miss时整行refill；
- hit由I-Cache本地返回，只有miss refill访问backing IMEM；
- CPU侧直接继承现有IFU req/rsp接口及response/request同拍replacement语义；
- 将过渡 `mem_itcm` 重构/重命名为I-Cache下游backing-IMEM model/adapter，取指不再存在ITCM bypass；
- 保持redirect stale-response drain正确，错误路径instruction不得进入IF/ID；
- 以最少的核心验证尽快完成一轮可运行实现，其余边界分析后登记为deferred，后续集中补全验证。

本任务不加入D-Cache、BIU、AXI、组相联、预取或non-blocking能力。

## A2. 依据与当前基线

- [`../mainSpec_Cache_Mem-subsys_Feature.md`](../mainSpec_Cache_Mem-subsys_Feature.md)
- [`../phaseSpec_Cache_Mem-Subsys_Roadmap.md`](../phaseSpec_Cache_Mem-Subsys_Roadmap.md)
- [`task_v12_01_phase0_variable_latency_memory_baseline.md`](task_v12_01_phase0_variable_latency_memory_baseline.md)
- [`task_v12_02_phase0_s2_memory_throughput.md`](task_v12_02_phase0_s2_memory_throughput.md)
- [`rule_ai_acceptance.md`](rule_ai_acceptance.md)
- [`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)

当前可直接复用的基线：

- IFU已提供 `if_req_vld/rdy/addr` 与 `if_rsp_vld/rdy/data`；
- 每通道最多一个unanswered request，允许response A与request B同拍replacement；
- IFU已拥有redirect后的stale-response drain和response payload holding；
- `mem_itcm` 当前是32 KiB双端口RTL array：P0服务IF transaction，P1服务LSU对可执行区域的本地访问；
- 仿真TB通过 `u_imem.r_itcm` 等层次路径preload，重命名时必须同步调整，不能保留旧模块名作为旁路。

## A3. 目标结构与所有权

```text
IFU IF req/rsp
      |
      v
4 KiB blocking I-Cache
  |-- hit --------------------------> IF response
  `-- miss: 8 x 32-bit word refill
                  |
                  v
           backing_imem RTL model
                  ^
                  |
        LSU executable-region access
```

所有权约束：

- I-Cache拥有CPU IF request、lookup、miss、refill、install和CPU response；
- backing IMEM只保存后备存储内容并响应word transaction，不包含Cache tag/valid/FSM；
- LSU访问可执行区域仍直达backing IMEM的data port，不经过I-Cache；这不是取指ITCM bypass；
- IFU继续拥有PC/BPU metadata、redirect优先级和stale response丢弃；I-Cache不复制预测状态；
- 本阶段继续使用可综合RTL arrays，不接SRAM macro或BRAM wrapper。

## A4. Cache几何与地址分解

4 KiB / 32 B = 128 lines，32-bit地址按以下字段解释：

```text
31                     12 11             5 4       2 1  0
+------------------------+----------------+---------+----+
|       tag[31:12]       | index[11:5]    | word    | 00 |
+------------------------+----------------+---------+----+
          20 bits              7 bits       3 bits
```

- valid：128 × 1 bit；
- tag：128 × 20 bit；
- data：128 lines × 8 words × 32 bit；
- reset只清valid和控制状态，不清tag/data array；
- refill base为 `{request_addr[31:5], 5'b0}`；8个beat地址依次为base + 0/4/.../28；
- 只有整行8个word全部成功接收后才能写入tag并置valid；请求word在install后replay或等价地正确返回。

## A5. 必须实现的核心行为

### A5.1 CPU-side lookup与response

- request只在 `if_req_vld && if_req_rdy` 时被接收，地址等待ready期间保持稳定的责任沿用Phase 0合同；
- hit必须同时满足 `valid[index] && tag[index] == request_tag`；
- hit response在被IFU接受前保持 `vld/data` 稳定；
- response A被接受时允许同拍接收request B，warm hit顺序流不得重新引入只用于FSM切换的固定空拍；
- miss期间对CPU侧施加blocking backpressure，不接受第二个CPU request。

### A5.2 Miss与whole-line refill

- 一次miss只对应一个line refill，上游request address在整个miss期间稳定保存；
- backend继续使用32-bit word req/rsp valid-ready，每个refill beat只在request fire时计数；
- response beat只在response fire时写入其唯一word slot并推进计数，不得跳beat、重复写或串line；
- refill未完成时line保持invalid，不能被CPU hit；
- 最后一个beat接收后原子安装tag/valid，再向原CPU request返回正确word；
- direct-mapped conflict直接覆盖同index旧line；I-Cache只读，无dirty/writeback。

### A5.3 Redirect、reset与backing IMEM

- redirect期间若已有取指request/miss，允许refill继续并安装，但其旧CPU response必须由既有IFU stale
  机制drain，不能进入IF/ID；I-Cache不能因旧response未被架构采用而重复响应或死锁；
- reset中止未完成lookup/miss/response并清全部valid，复位后首次访问必须cold miss；
- 删除 `mem_itcm` 模块名和 `u_imem.r_itcm` 依赖，重命名后的backing IMEM继续支持仿真preload和LSU
  data port；
- filelist、SoC连接、TB preload/signature辅助路径与memory配置文档同步到新名称。

## A6. 极速迭代范围与deferred策略

### A6.1 本轮明确不实现

- `fence.i` 引发的I-Cache全局invalidate（Roadmap已标记Pending）；
- 多miss、MSHR、hit-under-miss、prefetch、critical-word-first或early restart；
- 2-way、replacement policy、8 KiB最终容量；
- refill AXI burst、BIU、backend arbitration或error slave；
- Cache SRAM macro/BRAM映射、同步1RW物理时序收口；
- I-Cache性能计数器和完整CoreMark性能分析；
- 精确IMEM地址范围、unmapped instruction access fault。

### A6.2 已知边界但不作为本轮验证门槛

- 当前backend合同没有response error sideband，因此“refill error不得安装valid line”在本轮无法形成端到端激励；保持install只发生在完整refill完成的结构边界，error接口与error injection后续补充；
- redirect/reset落在每个refill beat、install、response replacement拍的穷举组合；
- CPU response backpressure与backend req/rsp backpressure的随机交叉矩阵；
- 同index多tag反复thrash、所有8个word offset、跨line长流和长时间scoreboard；
- LSU修改backing IMEM后、没有 `fence.i` 时的I-Cache stale副本属于当前已知软件可见限制；
- X态、非法地址、非word-aligned IF request和参数非法值的防御性行为。

执行中发现新的边界条件时：先分析是否影响本轮正常核心路径；不影响则在
[`pending_v12_cache_mem_subsys_deferred_scope.md`](pending_v12_cache_mem_subsys_deferred_scope.md)
追加“现象/风险、当前接受行为、后续触发条件、建议验证”，本轮不扩展成corner matrix。若影响最小核心
定向或公共回归，则必须修复，不能以deferred掩盖功能错误。

## A7. 预期文件范围

| 文件 | 预期修改 |
|---|---|
| `de/core/icache.sv` | 新增4 KiB direct-mapped blocking I-Cache、lookup/refill/install/response控制 |
| `de/periphs/backing_imem.sv` | 由 `mem_itcm.sv` 重构/重命名；保留refill transaction与LSU data port |
| `de/soc/soc_top.sv` | 在IFU与backing IMEM之间接入I-Cache并更新命名 |
| `filelists/filelist_rtl.f`、`filelist_sim_sram.f` | 纳入I-Cache和新backing IMEM，删除 `mem_itcm` |
| `dv/` 中最小TB源文件 | 只放源代码，不在该目录运行仿真或生成build |
| `../sim/makefile`或sim专用filelist | 提供从统一 `sim/` 启动核心定向测试的目标 |
| `dv/tb_soctop_*.sv` | 更新preload/层次路径，不保留 `u_imem.r_itcm` 依赖 |
| `doc/readme_mem_config.md` | 更新Phase 1结构、backing IMEM名称和preload说明 |
| `doc/dev_log/pending_v12_cache_mem_subsys_deferred_scope.md` | 仅追加执行中已分析并明确搁置的边界 |
| `doc/dev_log/log_dev_v12.md` | Phase 1完成后追加简短实现与验收摘要 |

若实现需要增加小型array wrapper或专用类型文件，可以纳入；不得顺带重构D-Cache/LSU路径。

## A8. 推荐实施顺序

1. 固定I-Cache CPU/backend端口、address split、状态与refill计数合同。
2. 新增I-Cache RTL，先跑通cold miss → 8-beat refill → install → response。
3. 加入hit与response/request同拍replacement，确认warm hit顺序流无固定FSM空拍。
4. 完成direct-map conflict replacement、response backpressure holding和reset valid清除。
5. 将 `mem_itcm` 重构为 `backing_imem`，更新SoC、filelist和仿真preload路径。
6. 只在统一 `work/my-RISCV-Projs/sim` 运行A9规定的最小核心测试。
7. 分析执行中遇到的corner；核心错误当轮修复，其余登记pending后停止扩验。
8. 更新uArch/memory配置、task执行记录和devlog，通知用户运行保留的公共验收与synthesis check。

## A9. 验证与验收

### A9.1 AI执行的最小核心验证

所有仿真命令必须从 `work/my-RISCV-Projs/sim` 运行。禁止在设计的 `dv/` 目录运行make、仿真或生成
build结果；`dv/` 仅保存TB/SVA源文件。

只要求以下最小集合：

1. **一个I-Cache核心定向流**：在同一TB中覆盖reset后cold miss、8个连续refill word及地址/data对应、
   同line warm hit无backend访问、至少一次response backpressure稳定、同index不同tag conflict replacement，
   并观察至少一次warm hit response A/request B同拍replacement。

   ```text
   make sim_phase1_icache DESIGN_NAME=../12_rv32im_bpu_cache
   ```

2. **两个SoC smoke单例**：一个普通顺序/访存基础用例和一个redirect用例，建议使用：

   ```text
   make sim_isa test=add DESIGN_NAME=../12_rv32im_bpu_cache
   make sim_isa test=jal DESIGN_NAME=../12_rv32im_bpu_cache
   ```

   两者必须PASS、无新增SVA/Assertion error，用来证明真实preload、cold refill、hit取指及基本redirect
   路径可运行。

除非上述最小用例失败并需要缩小根因，否则AI不主动扩跑其他ISA、Compliance、随机回归、CoreMark或
synthesis。

### A9.2 用户手动公共验收

最终验收标准继续完整遵循 [`rule_ai_acceptance.md`](rule_ai_acceptance.md)，但执行责任按用户要求调整：
ISA、Compliance和synthesis check均由用户手动运行并反馈，AI不得代跑。

用户在 `work/my-RISCV-Projs/sim` 手动运行并显式指定v12：

```text
make sim_isa_all type=isa group=rv32ui DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=isa group=rv32um DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32i DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32im DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zicsr DESIGN_NAME=../12_rv32im_bpu_cache
make sim_isa_all type=compli group=rv32Zifencei DESIGN_NAME=../12_rv32im_bpu_cache
```

标准保持为：

- ISA：`rv32ui` 41/42 PASS，仅允许既有 `ma_data` FAIL；`rv32um` 8/8 PASS；
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
- 不得出现新的simulation、SVA或assertion failure。

用户另在 `work/my-RISCV-Projs/syn` 手动运行：

```text
make check DESIGN_NAME=12_rv32im_bpu_cache
```

synthesis check必须PASS。AI完成RTL和A9.1最小验证后，状态更新为
`Implementation Complete — Public Acceptance Pending User Run`；只有用户反馈上述公共回归与synthesis
结果满足标准后，才能标记 `Completed`。

## A10. Review记录

当前为v1.0初稿，等待Review。每轮Review在本小节追加独立条目，并同步更新header版本/状态；Review只
修改Part I，不提前填写执行结果。

---

# Part II — 执行、验证与后续修复记录

本部分从任务状态进入执行后开始填写。每轮实现、返修或bugfix使用独立的“Execution Round”，不得与
Part I的任务定义混排，也不得把多轮结果堆在同一级连续编号中。

## E0. 记录规则

每轮至少记录：

- 开始原因与本轮目标；
- 实际修改文件和关键设计决策；
- 只在 `work/my-RISCV-Projs/sim` 执行的命令与结果；
- 首个错误时序和根因（若本轮是bugfix）；
- 新增deferred边界及其pending文档链接；
- 本轮结束状态和下一执行责任人。

建议格式：

```text
## Execution Round N — <目标>（YYYY-MM-DD HH:MM）
### E<N>.1 实现
### E<N>.2 最小验证
### E<N>.3 Deferred / 已知边界
### E<N>.4 结果与状态
```

## Execution Round 1 — 初始实现（2026-09-07 00:38）

### E1.1 实现

- 新增 `de/core/icache.sv`：4 KiB、128-line、32 B line的direct-mapped read-only blocking
  I-Cache；实现CPU hit/response holding与response/request同拍replacement、single-miss whole-line
  refill、完整8 beat后的原子install、conflict invalidate/replace和reset valid清除。
- 将 `de/periphs/mem_itcm.sv` 重构并重命名为 `backing_imem.sv`；保留32 KiB RTL array、word
  req/rsp端口与LSU executable-region data port，不保留取指bypass。
- `soc_top.sv`、sim/syn filelist、SoC TB preload路径和memory配置文档均切换到I-Cache +
  `u_backing_imem.r_backing_imem`。
- 新增 `dv/tb_icache_basic.sv` 与统一 `sim/makefile` 的 `sim_phase1_icache` 目标；所有build产物均在
  `work/my-RISCV-Projs/sim` 产生。

### E1.2 最小验证

均于 `work/my-RISCV-Projs/sim` 执行：

- `make sim_phase1_icache DESIGN_NAME=../12_rv32im_bpu_cache`：PASS；覆盖cold miss、8个有序refill
  地址/data、warm hit无backend访问、response连续3拍反压稳定、同index不同tag conflict replacement
  及warm hit response/request同拍replacement。
- `make sim_isa test=add DESIGN_NAME=../12_rv32im_bpu_cache`：PASS，`24_250_000 ps`，无新增
  SVA/Assertion error。
- `make sim_isa test=jal DESIGN_NAME=../12_rv32im_bpu_cache`：PASS，`2_410_000 ps`，无新增
  SVA/Assertion error。

### E1.3 Deferred / 已知边界

本轮未发现影响核心路径的新边界；A6既定的error sideband、`fence.i` invalidate、随机corner matrix、
SRAM/BRAM映射与精确地址/access fault继续保持deferred，本轮未扩验。

### E1.4 结果与状态

Phase 1 RTL及A9.1最小验证完成。状态为
`Implementation Complete — Public Acceptance Pending User Run`；完整ISA/Compliance与synthesis check
由用户按A9.2手动运行，满足标准后再进入`Completed`。

### E1.5 用户公共验收（2026-09-07 00:50）

用户反馈A9.2手动验收全部完成：

- ISA：`rv32ui` 41/42 PASS（仅允许的既有 `ma_data` FAIL），`rv32um` 8/8 PASS；
- Compliance：`rv32i` 48/48、`rv32im` 8/8、`rv32Zicsr` 6/6、`rv32Zifencei` 1/1 PASS；
- synthesis check：PASS；
- `coremark_10`：运行成绩 `81 ms`（用户报告）。

任务状态更新为`Completed`。
