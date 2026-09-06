# Memory 实现配置

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 11:04
**Current Version**: v1.4

**Version Changelog**:
- **v1.4** (2026-09-07 02:12): 记录Phase 3 8 KiB 2-way同步1RW I/D Cache、round-robin replacement及D$ write-back/write-allocate dirty eviction；performance counters与 `fence.i` invalidate继续deferred。
- **v1.3** (2026-09-07 01:08): 记录Phase 2 4 KiB WT/NWA D-Cache、cacheable/uncached/Device路由、事务化backing DMEM与新preload层次。
- **v1.2** (2026-09-07 00:42): 记录 Phase 1 4 KiB blocking I-Cache、32 KiB backing IMEM、refill合同与新preload层次；移除取指侧过渡 `mem_itcm`。
- **v1.1** (2026-09-06 14:09): 明确当前 ITCM/DTCM 是 Cache 加入前的过渡 backend；最终采用 I/D Cache + backing memory 并移除 TCM 模块与语义。
- **v1.0** (2026-09-06 11:04): 记录 Phase 0 RTL memory wrapper、容量、事务接口与已搁置的 macro/扩容范围。

---

当前版本的 `icache`、`dcache`、`backing_imem`、`backing_dmem` 均使用可综合RTL array。
Cache tag/data通过generic synchronous 1RW wrapper访问。`USE_BRAM`与 `USE_SRAM_MACRO` 不参与Phase 3
构建；已有macro wrapper文件保留在仓库中，但不进入
`filelist_sim_sram.f` 或 `filelist_syn_sram.f`。

这些模块不是最终 TCM 架构。确定的演进关系为：

```text
IFU -> 8 KiB 2-way I-Cache -> backing IMEM

MAU -> LSU router -> 8 KiB 2-way WB/WA D-Cache -> backing DMEM
                  -> backing IMEM data port          (uncached IMEM)
                  -> UART                            (Device bypass)
```

I/D Cache直接继承Phase 0定义的IF/LSU req/rsp合同。取指侧和data侧过渡TCM模块均已移除。

## 当前容量与映射

| 存储 | Base | 逻辑容量 | RTL depth | Phase 0 decode |
|---|---:|---:|---:|---|
| backing IMEM | `0x0000_0000` | 32 KiB | 8192 x 32 | 地址高 nibble 为 `0x0` |
| I-Cache | CPU请求地址 | 8 KiB | 2 ways × 128 sets × 32 B | tag `[31:12]`、set `[11:5]`、word `[4:2]` |
| backing DMEM | `0x1000_0000` | 16 KiB | 4096 x 32 | 地址高 nibble 为 `0x1` |
| D-Cache | DMEM请求地址 | 8 KiB | 2 ways × 128 sets × 32 B | tag `[31:12]`、set `[11:5]`、word `[4:2]` |
| UART | `0x3000_0000` | 既有寄存器窗口 | 不适用 | 地址高 nibble 为 `0x3` |

高nibble decode与16 KiB backing DMEM越界alias是已接受的临时行为。精确范围、access fault、
backing DMEM 32 KiB 扩展及 SRAM/BRAM 替换见
[`dev_log/pending_v12_cache_mem_subsys_deferred_scope.md`](dev_log/pending_v12_cache_mem_subsys_deferred_scope.md)。

## I-Cache / IF transaction

IFU与I-Cache、I-Cache与backing IMEM均使用request/response valid-ready：

```text
request  = if_req_vld && if_req_rdy
response = if_rsp_vld && if_rsp_rdy
```

- I-Cache为8 KiB、2-way、128-set、32 B line只读blocking cache；
- invalid way优先；两way均valid时按每set 1-bit round-robin选择victim，hit不更新replacement bit；
- cold/conflict miss从32 B对齐地址开始发出8次32-bit word transaction，收集后写入4个64-bit chunk，
  完整安装data/tag后才原子置valid；
- 每way Data Array逻辑组织为 `512 × 64 bit`，Tag Array为 `128 × 20 bit`，均使用synchronous 1RW
  generic wrapper；CPU request fire发起lookup，下一拍使用同步输出判定hit；
- miss期间不接受第二个CPU request；hit response在消费前保持稳定；
- warm hit response被消费时可同拍接受下一个CPU request；
- backing IMEM只有一个response slot，请求fire后同步读array，并保持response直到fire；
- IFU 同时最多保留一个 outstanding request；redirect 后已发出的旧 response 会被接收并丢弃；
- reset清除全部cache valid和控制状态，但不清cache data/tag或backing IMEM内容；
- 未映射refill request以NOP benign completion返回，本阶段不产生access fault。
- `fence.i` I-Cache invalidate按当前Phase 3范围决定继续deferred，现有 `fence.i`只执行流水线redirect和
  branch predictor invalidate。

backing IMEM port 1保留给LSU executable-region路径，使用同步RTL 1RW enable/write-mask接口；
该data port不经过I-Cache。

## D-Cache / LSU transaction

MAU/MEM 是 LSU transaction owner，状态语义为：

```text
EMPTY -> REQ -> WAIT_RSP -> DONE -> EMPTY
```

- `REQ` 在 backend ready 前保持地址、读写类型、size、mask 与 write data；
- `WAIT_RSP` 不重复发 request，也不提前完成 MA/WB；
- `DONE` 保存 load 格式化结果与 rd metadata，在 WB backpressure 下保持稳定；
- store 写副作用只发生在 `mem_req_vld && mem_req_rdy && mem_req_write` 的唯一 fire；
- byte/halfword 的 sign/zero extension 在 MAU 使用已捕获 response data 完成；
- 当前 unmapped LSU request 返回零数据/无写副作用的 benign completion。

LSU router使用当前粗粒度属性分流：

- `0x1xxx_xxxx` DMEM为cacheable，进入8 KiB、2-way blocking D-Cache；
- D-Cache使用与I$相同的invalid-first/per-set 1-bit round-robin及同步1RW 64-bit Data Array组织；
- load miss和store miss均执行8-word whole-line refill；store miss在refill line中做byte-mask merge后
  write-allocate并置dirty；
- store hit只更新命中64-bit chunk的目标byte并置dirty，不执行write-through；
- valid+dirty victim先通过4次同步64-bit read保存整条line，再按地址升序完成8次32-bit full-word
  writeback response，之后才能开始新line refill；clean/invalid victim不writeback；
- `0x0xxx_xxxx` executable IMEM data access走backing IMEM uncached data port；
- `0x3xxx_xxxx` UART为Device并绕过D-Cache；其他地址临时benign completion。

backing DMEM array不由reset清零；reset清D-Cache valid及transaction/output状态。byte mask bit 0
对应 `[7:0]`，bit 3对应 `[31:24]`。

Phase 3 performance counters按用户决定暂不实现；当前没有Cache counter CSR、MMIO或debug output。

## 构建与初始化

- 仿真入口：`filelists/filelist_sim_sram.f`，其路径显式指向 v12 RTL；
- 综合入口：`filelists/filelist_syn_sram.f` -> `filelist_rtl.f`；
- `.data` 文件一行一个32-bit hex word，testbench直接preload
  `u_backing_imem.r_backing_imem` / `u_backing_dmem.r_backing_dmem`；
- 当前 filelist 不包含 PDK SRAM model、SRAM wrapper 或 Vivado BRAM IP。
