# Memory 实现配置

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 11:04
**Current Version**: v1.2

**Version Changelog**:
- **v1.2** (2026-09-07 00:42): 记录 Phase 1 4 KiB blocking I-Cache、32 KiB backing IMEM、refill合同与新preload层次；移除取指侧过渡 `mem_itcm`。
- **v1.1** (2026-09-06 14:09): 明确当前 ITCM/DTCM 是 Cache 加入前的过渡 backend；最终采用 I/D Cache + backing memory 并移除 TCM 模块与语义。
- **v1.0** (2026-09-06 11:04): 记录 Phase 0 RTL memory wrapper、容量、事务接口与已搁置的 macro/扩容范围。

---

当前版本的 `icache`、`backing_imem`、`mem_dtcm` 均使用可综合 RTL array。`USE_BRAM` 与
`USE_SRAM_MACRO` 不参与 Phase 1 构建；已有 macro wrapper 文件保留在仓库中，但不进入
`filelist_sim_sram.f` 或 `filelist_syn_sram.f`。

这些模块不是最终 TCM 架构。确定的演进关系为：

```text
IFU -> I-Cache -> backing IMEM  (Phase 1 current)

MAU -> soc_bus -> mem_dtcm                 (Phase 0 transitional)
MAU -> D-Cache/routing -> backing DMEM/MMIO (Phase 2+ target)
```

I-Cache 已直接继承 Phase 0 定义的 IF req/rsp 合同，取指不再具有 `mem_itcm` bypass。
`mem_dtcm` 仍等待 Phase 2 由 D-Cache 与 backing DMEM 接管。

## 当前容量与映射

| 存储 | Base | 逻辑容量 | RTL depth | Phase 0 decode |
|---|---:|---:|---:|---|
| backing IMEM | `0x0000_0000` | 32 KiB | 8192 x 32 | 地址高 nibble 为 `0x0` |
| I-Cache | CPU请求地址 | 4 KiB | 128 lines x 8 words | tag `[31:12]`、index `[11:5]`、word `[4:2]` |
| 过渡 DTCM model / 最终 backing DMEM | `0x1000_0000` | 16 KiB | 4096 x 32 | 地址高 nibble 为 `0x1` |
| UART | `0x3000_0000` | 既有寄存器窗口 | 不适用 | 地址高 nibble 为 `0x3` |

高 nibble decode 与过渡 DTCM model 越界 alias 是已接受的临时行为。精确范围、access fault、
backing DMEM 32 KiB 扩展及 SRAM/BRAM 替换见
[`dev_log/pending_v12_cache_mem_subsys_deferred_scope.md`](dev_log/pending_v12_cache_mem_subsys_deferred_scope.md)。

## I-Cache / IF transaction

IFU与I-Cache、I-Cache与backing IMEM均使用request/response valid-ready：

```text
request  = if_req_vld && if_req_rdy
response = if_rsp_vld && if_rsp_rdy
```

- I-Cache为4 KiB、32 B line、128-line direct-mapped只读blocking cache；
- cold/conflict miss从32 B对齐地址开始发出8次32-bit word transaction，完整接收后原子安装valid/tag；
- miss期间不接受第二个CPU request；hit response在消费前保持稳定；
- warm hit response被消费时可同拍接受下一个CPU request；
- backing IMEM只有一个response slot，请求fire后同步读array，并保持response直到fire；
- IFU 同时最多保留一个 outstanding request；redirect 后已发出的旧 response 会被接收并丢弃；
- reset清除全部cache valid和控制状态，但不清cache data/tag或backing IMEM内容；
- 未映射refill request以NOP benign completion返回，本阶段不产生access fault。

backing IMEM port 1保留给LSU executable-region路径，使用同步RTL 1RW enable/write-mask接口；
该data port不经过I-Cache。

## LSU transaction

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

当前过渡 DTCM array 不由 reset 清零；reset 只清 transaction/output 状态。byte mask bit 0 对应
`[7:0]`，bit 3 对应 `[31:24]`。

## 构建与初始化

- 仿真入口：`filelists/filelist_sim_sram.f`，其路径显式指向 v12 RTL；
- 综合入口：`filelists/filelist_syn_sram.f` -> `filelist_rtl.f`；
- `.data` 文件一行一个32-bit hex word，testbench直接preload
  `u_backing_imem.r_backing_imem` / `u_dmem.r_dtcm`；
- 当前 filelist 不包含 PDK SRAM model、SRAM wrapper 或 Vivado BRAM IP。
