# Memory 实现配置

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-09-06 11:04
**Current Version**: v1.1

**Version Changelog**:
- **v1.1** (2026-09-06 14:09): 明确当前 ITCM/DTCM 是 Cache 加入前的过渡 backend；最终采用 I/D Cache + backing memory 并移除 TCM 模块与语义。
- **v1.0** (2026-09-06 11:04): 记录 Phase 0 RTL memory wrapper、容量、事务接口与已搁置的 macro/扩容范围。

---

当前版本的 `mem_itcm`、`mem_dtcm` 均使用可综合 RTL array。`USE_BRAM` 与
`USE_SRAM_MACRO` 不参与 Phase 0 构建；已有 macro wrapper 文件保留在仓库中，但不进入
`filelist_sim_sram.f` 或 `filelist_syn_sram.f`。

这些模块不是最终 TCM 架构。确定的演进关系为：

```text
IFU -> mem_itcm                 (Phase 0 transitional)
IFU -> I-Cache -> backing IMEM  (Phase 1+ target)

MAU -> soc_bus -> mem_dtcm                 (Phase 0 transitional)
MAU -> D-Cache/routing -> backing DMEM/MMIO (Phase 2+ target)
```

I/D Cache 直接继承 Phase 0 已定义的 CPU-side req/rsp 合同。当前 RTL arrays 后续只作为
下游 backing-memory model 复用或被 adapter 替换；最终删除 `mem_itcm`/`mem_dtcm` 名称，
不提供 software-visible TCM bypass path。

## 当前容量与映射

| 存储 | Base | 逻辑容量 | RTL depth | Phase 0 decode |
|---|---:|---:|---:|---|
| 过渡 ITCM model / 最终 backing IMEM | `0x0000_0000` | 32 KiB | 8192 x 32 | 地址高 nibble 为 `0x0` |
| 过渡 DTCM model / 最终 backing DMEM | `0x1000_0000` | 16 KiB | 4096 x 32 | 地址高 nibble 为 `0x1` |
| UART | `0x3000_0000` | 既有寄存器窗口 | 不适用 | 地址高 nibble 为 `0x3` |

高 nibble decode 与过渡 DTCM model 越界 alias 是已接受的临时行为。精确范围、access fault、
backing DMEM 32 KiB 扩展及 SRAM/BRAM 替换见
[`dev_log/pending_v12_cache_mem_subsys_deferred_scope.md`](dev_log/pending_v12_cache_mem_subsys_deferred_scope.md)。

## IF transaction

ITCM port 0 使用 request/response valid-ready：

```text
request  = if_req_vld && if_req_rdy
response = if_rsp_vld && if_rsp_rdy
```

- wrapper 内只有一个 response slot；slot 空闲或当拍被消费时可接受新 request；
- request fire 后同步读取 RTL array，并从下一拍起保持 response valid/data，直到 response fire；
- IFU 同时最多保留一个 outstanding request；redirect 后已发出的旧 response 会被接收并丢弃；
- 未映射 IF request 以 NOP benign completion 返回，本阶段不产生 access fault。

ITCM port 1 保留给 LSU/self-modifying-code 路径，使用同步 RTL 1RW enable/write-mask 接口。

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
- `.data` 文件一行一个 32-bit hex word，testbench 直接 preload `r_itcm`/`r_dtcm`；
- 当前 filelist 不包含 PDK SRAM model、SRAM wrapper 或 Vivado BRAM IP。
