# RV32I Basic RTL Static Analysis Report

Date: 2026-06-23

Current update: 2026-06-24

Scope: `00_rv32i_basic/de`

This report summarizes static review findings for RTL naming, signal semantics, module interfaces, temporary mechanisms, and simulation elaboration warnings. It is now kept as an active issue list plus a short record of fixed items.

Current version note:

- Fixed DV `soc_top_v0` UART port connections in `tb_soctop_isatest`.
- Removed unused `clk/rst_n` ports from `exu_alu`, `exu_bru`, `exu_lsu`, and `ctrl_hazard`.
- Renamed the raw CSR illegal-access signal to `csr_illegal_access_raw` and retained the EXU-side `csr_op_req` gate.
- Fixed UART RX sampling to assign each sampled bit directly.
- Cleaned minor RTL issues: MAU reset width, EXU dispatch group constants, EXU LSU write-back comment, and the IDU x0 source-need TODO.
- Migrated global memory/write-back naming from `mema/wrbk/rdwen/wren` to `mem_*`, `wb_*`, `rd_wen`, and `wr_en`.
- Deferred `pcnext` naming normalization by request.

## 1. Tool Check Summary

Command run from `work/my-RISCV-Projs/sim`:

```sh
make clean sim
```

Result:

- VCS compile/elaboration completed successfully.
- Normal `make sim` still times out without a meaningful program image when `inst.data` and `dmem.data` are absent.
- The earlier DV UART port-connection warning is no longer expected.
- A later `make sim_isa test=add` attempt did not complete because VCS could not obtain a license; this was an environment/license issue, not an RTL error.

Remaining expected warnings:

| Type | Location | Observation | Impact |
| --- | --- | --- | --- |
| `$readmem` file missing | `sim/sim.log` | `./inst.data` and `./dmem.data` are missing during plain `make sim`. | Normal `make sim` times out without a program image. Use `make sim_isa`, `make sim_compli`, `make sim_userprog`, or provide data files. |
| Kernel warning | VCS environment | WSL2 kernel is unsupported by this VCS version. | Environment warning only; compile/elaboration can still complete. |

## 2. High-Priority Findings

### 2.1 Decode lacks explicit illegal-instruction handling

Locations: `de/core/idu.sv`, `de/core/exu.sv`

`idu` dispatches supported instruction groups through `dec_oper_dispatch_*`, but there is no explicit `illegal_instr` decode path. `dec_info_need_rd` is still largely defined by exclusion rather than by positive instruction validity.

Risk:

- Unsupported or malformed opcodes can still assert `o_dec_rd_wen_id` if they are not excluded.
- A zero decode info bus can still look like ALU group encoding unless instruction validity is checked explicitly.

Suggested direction:

- Add `dec_instr_valid` as the OR of all supported instruction decodes.
- Gate `o_dec_rd_wen_id`, `o_need_rs1_idu`, and `o_need_rs2_idu` with `dec_instr_valid`.
- Add an illegal-instruction exception path with `mcause=2` and `mtval=instruction`.

### 2.2 `minstret` mechanism is present but permanently disabled

Locations: `de/core/core_rv32i_v0.sv`, `de/core/csr_regs.sv`

`csr_regs` implements `minstret/minstreth`, but `i_instr_ret_en` is still tied to `1'b0` at the core level.

Risk:

- `minstret/minstreth` always stay zero.
- CSR compliance or performance software that reads retired instruction counters will observe incorrect values.

Suggested direction:

- Generate an instruction-retired pulse at a real commit-equivalent point.
- Suppress it for bubbles, flushed instructions, stalls, and instructions that trap before retirement.

### 2.3 Temporary ITCM data-side read/write path needs architectural closure

Locations:

- `de/soc/soc_bus_v0.sv`
- `de/periphs/mem_itcm.sv`

The LSU can access ITCM through a data-side interface. This supports current test layouts and self-modifying-code-style flows, but the interface still carries temporary naming and lacks a documented conflict policy.

Risk:

- Instruction fetch and LSU access share one memory array without a clearly documented same-cycle conflict behavior.
- `fence.i` behavior is only loosely implied by the current direct ITCM access model.
- Current ITCM port-B naming still mixes read and write semantics.

Suggested direction:

- Rename ITCM port-B signals to neutral names such as `i_data_addr`, `i_data_wr_en`, `i_data_wr_mask`, `i_data_wr_data`, `o_data_rd_data`.
- Define same-cycle IF read versus data write behavior.
- Define how `fence.i` should synchronize instruction fetch with data-side writes.
- Tighten ITCM array indexing to use local `$clog2(ITCM_DEPTH)` width, matching the safer DTCM style.

## 3. Interface and Port Cleanliness

### 3.1 DV testbench UART ports (fixed)

`tb_soctop_isatest` now connects `o_uart_tx` to a local wire and ties `i_uart_rx` high.

### 3.2 Unused `clk/rst_n` ports on combinational modules (fixed)

Unused clock/reset ports were removed from `exu_alu`, `exu_bru`, `exu_lsu`, and `ctrl_hazard`, along with their instance connections.

### 3.3 `mema` naming overload (fixed)

The core, EXU, MAU, SoC bus, and active DV references now use `mem_*` naming. Memory write enable uses `wr_en`, and the old `mema` spelling is no longer present in active RTL/DV paths.

## 4. Naming and Semantic Ambiguity

### 4.1 `wrbk`, `rdwen`, `wen`, and `wren` mix (fixed)

Register write-back naming now uses `wb_data`, `wb_rd_idx`, and `wb_rd_wen`. Memory write naming now uses `mem_wr_en`, `mem_wr_mask`, and `mem_wr_data`.

### 4.2 `pcnext` should be normalized

Examples:

- `i_redirect_pcnext`
- `o_redirect_pcnext`
- `redirect_pcnext_bru`

Suggested convention:

- Use `redirect_pc_next` or `redirect_target_pc`.
- `target_pc` is often clearer for branch, jump, and trap redirects.

### 4.3 Raw CSR illegal-access signal (fixed)

The former `o_exc_raw_illegal_csr_access` signal was renamed to `csr_illegal_access_raw`. Producer and consumer comments now make clear that the signal is raw by CSR index/request and must be gated by a real CSR operation in EXU.

### 4.4 Dead or unclear decode helper names

Examples:

- `idu.sv`: `csridx` is declared but unused.
- `idu.sv`: `dec_rv32_rs2_x1` and `dec_rv32_rd_x2` are currently unused and commented "for what".

Suggested direction:

- Remove unused helpers until needed.
- If reserved for compressed ISA, stack-pointer hints, or call/return prediction, comment that intent explicitly.

## 5. Functional Mechanisms Still Waiting for Closure

### 5.1 IFU PC timing assumes combinational ITCM

Location: `de/core/ifu.sv`

The current IFU outputs `pc_r` directly and increments it every unstalled cycle. Existing TODO comments already identify that reset/next-PC behavior must change when moving to a normal synchronous SRAM.

Risk:

- With a synchronous instruction memory, PC address and instruction return timing will be off by one cycle unless IF/ID alignment is redesigned.

Suggested direction:

- Decide whether `o_pc_if` is "current instruction PC" or "next fetch address".
- If using synchronous SRAM, add an IF valid/data register or a fetch request/response convention.

### 5.2 `fence` and `fence.i` mechanism needs documentation

Locations:

- `de/core/idu.sv`
- `de/core/exu_bru.sv`

`fence` and `fence.i` are decoded into the BRU group. In this simple single-core/no-cache design, plain `fence` can reasonably be a no-op. `fence.i` currently uses a redirect-style refresh path, but the architectural contract should be documented because ITCM data writes are supported.

Suggested direction:

- Document `fence` as no-op for strongly ordered local memory.
- Document current `fence.i` behavior and revisit it if instruction memory becomes cached, buffered, or synchronous.

### 5.3 UART RX bit accumulation (fixed)

RX now assigns the sampled bit directly instead of OR-accumulating into `rx_data`.

## 6. Minor Static Issues

| Location | Observation | Recommendation |
| --- | --- | --- |
| `de/periphs/mem_itcm.sv` | ITCM indexes with `addr[31:2]`, unlike DTCM which masks to depth width. | Use local `$clog2(ITCM_DEPTH)` indexing to avoid out-of-range simulation behavior. |

Fixed minor items removed from the active table:

- `mau.sv`: the memory request info register reset width now matches the 8-bit register.
- `exu.sv`: dispatch group comparisons now use `DECINFO_GRP_*` constants.
- `exu.sv`: EXU write-back mux now documents that load data is selected later in MAU.
- `idu.sv`: the x0 source-need TODO was replaced with a comment explaining that x0 still reads as zero from regfile, while excluding it only skips false hazard/forwarding dependencies.

## 7. Recommended Fix Order

1. Add illegal-instruction detection and trap path.
2. Connect `minstret` to a real retirement pulse.
3. Replace the temporary ITCM data-side interface names, document IF/data conflict behavior, and tighten ITCM indexing.
4. Normalize `pcnext` naming when ready.
5. Add a stricter lint target, for example VCS with `+lint=TFIPC-L`, and keep warnings reviewed.

## 8. Overall Assessment

The current `de` hierarchy is structurally connected well enough for VCS elaboration. The main remaining risks are semantic drift points:

- decode accepts too much by exclusion instead of validating supported instructions;
- `minstret` has storage but no real retirement pulse;
- ITCM data access exists, but its contract is still temporary;
- `pcnext` remains a naming cleanup item, intentionally deferred for now.

Cleaning these next would make the design easier to extend toward synchronous memories, exception completeness, cleaner CSR semantics, and broader compliance coverage.
