# RV32I Basic Design Architecture Spec

## 1. Scope

This document describes the current design architecture under `00_rv32i_basic/de`.
The design is named `StepRV_v0` in source headers and implements a basic RV32I
processor subsystem with local instruction/data memories.

The documented RTL directories are:

| Directory | Role |
| --- | --- |
| `00_rv32i_basic/de/core` | RV32I core pipeline, register file, execution units, CSR block, hazard control |
| `00_rv32i_basic/de/soc` | SoC top and memory address decoder |
| `00_rv32i_basic/de/periphs` | ITCM and DTCM memory models |
| `00_rv32i_basic/de/defines` | Global configuration macros and generated macro reports |

## 2. Top-Level Architecture

The top-level module is `soc_top_v0`. It instantiates:

| Instance | Module | Responsibility |
| --- | --- | --- |
| `u_core` | `core_rv32i_v0` | RV32I processor core |
| `u_soc_bus` | `soc_bus_v0` | Decode core data-memory accesses to ITCM write path or DTCM read/write path |
| `u_imem` | `mem_itcm` | Instruction TCM, read by IFU and writable through the data access bus |
| `u_dmem` | `mem_dtcm` | Data TCM, read/write by LSU through MAU and SoC bus |

High-level connection:

```text
                   +-------------------+
                   |   core_rv32i_v0   |
                   |                   |
     if_pc ------->| IF instruction PC |
 itcm_rd_data ---->| instruction input |
                   |                   |
 mema_* ---------->| data access port  |
                   +---------+---------+
                             |
                             v
                   +-------------------+
                   |    soc_bus_v0     |
                   +----+---------+----+
                        |         |
                        v         v
                +----------+  +----------+
                | mem_itcm |  | mem_dtcm |
                +----------+  +----------+
```

The instruction path is independent from the core data access path:

- Instruction fetch uses `o_if_pc` from the core to read `mem_itcm`.
- Data access uses `o_mema_*` from the core and is decoded by `soc_bus_v0`.
- Writes to the ITCM address range are supported from the data side, enabling a basic self-modifying-code/program-load path.
- Data-side reads from ITCM currently return zero because the SoC bus only exposes ITCM writes to the LSU path.

## 3. Global Configuration

Global macros live in `defines/config.v`.

Important configuration items:

| Macro | Current value | Meaning |
| --- | --- | --- |
| `XLEN` | `32` | Integer datapath width |
| `RFIDX_WIDTH` | `5` | Register index width |
| `ITCM_DEPTH` | `8192` | ITCM word depth, comment marks this as 32 KiB |
| `DTCM_DEPTH` | `4096` | DTCM intended word depth, comment marks this as 16 KiB |
| `INSTR_NOP` | `32'h00000013` | ADDI x0, x0, 0 pipeline bubble/NOP |
| `DECINFO_BUS_WIDTH` | CSR bus width, currently 25 | Unified decode-info bus width |

The decode-info bus is split by functional group:

| Group | Macro | Width | Main consumer |
| --- | --- | --- | --- |
| ALU | `DECINFO_GRP_ALU` | `DECINFO_BUS_ALU_WIDTH` = 16 | `exu_alu` |
| LSU | `DECINFO_GRP_LSU` | `DECINFO_BUS_LSU_WIDTH` = 9 | `exu_lsu` |
| BRU | `DECINFO_GRP_BRU` | `DECINFO_BUS_BRU_WIDTH` = 15 | `exu_bru` |
| CSR | `DECINFO_GRP_CSR` | `DECINFO_BUS_CSR_WIDTH` = 25 | `exu_csr` |

## 4. Core Pipeline

`core_rv32i_v0` is organized as a five-stage in-order pipeline:

```text
IFU -> IDU -> EXU -> MAU -> WBU
```

The register file and CSR file are side blocks connected to the pipeline:

- `regfile` provides two combinational read ports and one write-back port.
- `csr_regs` provides CSR read/write storage and timer counters.
- `ctrl_hazard` generates forwarding selects, stalls, and flushes.

### 4.1 IF Stage

Module: `ifu`

Responsibilities:

- Holds the current PC in `pc_r`.
- Generates sequential PC by `pc + 4`.
- Redirects PC to `i_pc_next_bru` when `i_jump_flag` is asserted by the branch unit.
- Freezes PC when `i_stall` is asserted.

Reset behavior:

- `pc_r` resets to `0`, so reset vector is currently `0x0000_0000`.

### 4.2 ID Stage

Module: `idu`

Responsibilities:

- Captures IF-stage instruction and PC into ID-stage pipeline registers.
- Decodes RV32I opcode/funct fields.
- Generates I/S/B/U/J immediates.
- Emits source/destination register indexes.
- Emits `need_rs1`, `need_rs2`, and `rdwen` metadata for dependency control.
- Encodes operation control into the unified `dec_info_bus`.

Decode coverage in the current RTL includes:

- ALU: LUI, AUIPC, ADD/SUB, shifts, SLT/SLTU, XOR/OR/AND and immediate variants.
- Load/store: LB/LH/LW/LBU/LHU and SB/SH/SW.
- Branch/jump: BEQ/BNE/BLT/BGE/BLTU/BGEU, JAL, JALR.
- Misc memory: FENCE, FENCE.I.
- CSR: CSRRW/CSRRS/CSRRC and immediate forms.
- ECALL/EBREAK are recognized for decode exclusion, but no full trap flow is implemented in the pipeline.

Flush behavior:

- On `i_flush`, ID injects `INSTR_NOP`.

### 4.3 EX Stage

Module: `exu`

Responsibilities:

- Holds ID-to-EX pipeline registers for operands, immediate, PC, decode-info bus, register indexes, and write-back metadata.
- Applies forwarding muxes for RS1/RS2.
- Dispatches the decoded operation to one of four execution sub-units:
  - `exu_alu`
  - `exu_lsu`
  - `exu_bru`
  - `exu_csr`
- Selects ALU/BRU/CSR result for write-back.
- Generates branch redirect signals.
- Generates LSU memory request metadata for MAU.
- Gates illegal CSR exception indication with actual CSR dispatch.

The EXU uses the group field in `dec_info_bus` to isolate unrelated sub-unit inputs.

### 4.4 MA Stage

Module: `mau`

Responsibilities:

- Captures EXU memory address, write enable, write data, and memory-info bus.
- Drives the external core memory access port:
  - `o_mema_addr_mau`
  - `o_mema_wren_mau`
  - `o_mema_wr_mask`
  - `o_mema_wr_data_mau`
- Selects write-back data:
  - load result when the instruction is a load
  - pass-through EXU result for non-load instructions
- Performs load byte/halfword extraction and sign/zero extension.

Load-size encoding follows `func3[1:0]`:

| Size | Encoding | Behavior |
| --- | --- | --- |
| Byte | `2'b00` | Select byte by address offset; sign/zero extend |
| Halfword | `2'b01` | Select lower/upper halfword; sign/zero extend |
| Word | `2'b10` | Use full 32-bit memory data |

### 4.5 WB Stage

Module: `wbu`

Responsibilities:

- Captures MA-stage write-back data, destination register index, and write enable.
- Drives the register file write-back port.

## 5. Execution Sub-Units

### 5.1 ALU

Module: `exu_alu`

Supported operations:

- ADD/SUB and ADDI.
- SLT/SLTU and immediate variants, sharing the adder/subtractor.
- XOR/OR/AND and immediate variants.
- SLL/SRL/SRA and immediate variants.
- LUI.
- AUIPC through `OP1PC` plus immediate add.

The shifter implements right shifts by bit-reversing into a left shifter, then reversing back for SRL/SRA.

### 5.2 LSU

Module: `exu_lsu`

Responsibilities:

- Computes effective address as `rs1 + imm`.
- Generates store byte mask and store write data based on access size and address offset.
- Generates memory write enable for stores.
- Packs memory request info for MAU as:

```text
{mema_wr_mask[3:0], lsu_req_load, lsu_req_info_size[1:0], lsu_req_info_usign}
```

Alignment policy:

- Byte accesses may use any byte offset.
- Halfword accesses require `addr[0] == 0`.
- Word accesses require `addr[1:0] == 0`.
- Misaligned load/store suppresses load/write request and asserts `o_lsu_misaligned_exc`.

Current integration note:

- `o_lsu_misaligned_exc` is generated in `exu_lsu`, but it is not connected upward in `exu` or converted into a trap flow.

### 5.3 BRU

Module: `exu_bru`

Responsibilities:

- Evaluates conditional branches.
- Computes JAL/JALR/branch target address.
- Produces `pc + 4` write-back value for JAL/JALR.
- Asserts `o_jump_flag` for taken branches, JAL, JALR, and FENCE.I.

Branch resolution occurs in EX. A taken branch redirects the IFU and causes flushes generated by `ctrl_hazard`.

### 5.4 CSR Execution

Module: `exu_csr`

Responsibilities:

- Decodes CSR operation control from the CSR decode-info bus.
- Reads old CSR value for write-back.
- Computes CSR write data for CSRRW/CSRRS/CSRRC and immediate variants.
- Suppresses writes for pure-read CSRRS/CSRRC with zero source operand.
- Gates CSR write enable with `~stall` and `~flush`.

## 6. Register File and CSR File

### 6.1 Integer Register File

Module: `regfile`

Properties:

- 32 architectural registers, with x0 hardwired to zero.
- Two read ports, one write port.
- Registers x1-x31 are implemented as flip-flop arrays.
- Same-cycle write-through is supported: if WB writes the same register that ID reads, read data returns write-back data.

### 6.2 CSR Registers

Module: `csr_regs`

Implemented CSRs:

| CSR | Address |
| --- | --- |
| `mstatus` | `0x300` |
| `mtvec` | `0x305` |
| `mepc` | `0x341` |
| `mcause` | `0x342` |
| `mcycle` | `0xB00` |
| `mcycleh` | `0xB80` |
| `minstret` | `0xB02` |
| `minstreth` | `0xB82` |

Behavior:

- `mcycle` increments every cycle.
- `minstret` increments when `i_instr_ret_en` is asserted.
- In `core_rv32i_v0`, `i_instr_ret_en` is currently tied to `1'b0`, so `minstret` does not count retired instructions yet.
- Unsupported CSR indexes assert `o_exc_raw_illegal_csr_access`; EXU gates this raw indication with a real CSR op request before folding it into `o_exc_req` with `mcause=2`.

## 7. Hazard, Forwarding, Stall, and Flush

Module: `ctrl_hazard`

### 7.1 Forwarding

Forwarding is resolved for EX-stage operands:

| Select | Meaning |
| --- | --- |
| `2'b00` | Use registered RF data in EXU |
| `2'b10` | Forward from MAU result |
| `2'b11` | Forward from WBU result |

MAU forwarding has priority over WBU forwarding.

The hazard check uses `need_rs1/need_rs2` and write-back enables/indexes, so x0 and unused operands are intended to be excluded by decode metadata.

### 7.2 Load-Use Hazard

The controller detects when the instruction in ID needs a source register that is the destination of a load currently in EX.

On load-use hazard:

- Stall PC and IF/ID.
- Flush ID/EX to insert a bubble.

Implementation detail:

- `ctrl_hazard` has input `i_is_load_req_exu`, but `core_rv32i_v0` currently declares `is_load_req_exu` without connecting it to an EXU output. The intended architecture is clear, but the load-use hazard path needs that signal to be driven for complete functionality.

### 7.3 Branch Flush

On `i_jump_flag`:

- No stall is requested.
- IF/ID and ID/EX are flushed.

This matches EX-stage branch resolution: the younger instructions behind the resolved control transfer are invalidated.

## 8. Memory and Address Map

### 8.1 SoC Bus

Module: `soc_bus_v0`

Address decode parameters in `soc_top_v0`:

| Region | Base | Size | Access through data bus |
| --- | --- | --- | --- |
| ITCM | `0x0000_0000` | `0x0000_1000` | Write only from LSU path |
| DTCM | `0x0000_1000` | `0x0000_F000` | Read/write |

Read mux:

- DTCM-selected data accesses return `i_dtcm_rd_data`.
- Other data-side reads return `32'b0`.

### 8.2 ITCM

Module: `mem_itcm`

Properties:

- Word-addressed memory array.
- Combinational instruction read from `i_rd_addr[31:2]`.
- Byte-mask write port for data-side writes.
- Contains an internal data-read signal, but `soc_bus_v0` currently does not expose ITCM data reads to the core data bus.

### 8.3 DTCM

Module: `mem_dtcm`

Properties:

- Word-addressed memory array.
- Combinational read from `i_addr[31:2]`.
- Byte-mask write on clock edge.

Current RTL note:

- The array declaration uses `` `ITCM_DEPTH`` even though `config.v` defines `` `DTCM_DEPTH``. Based on naming and comments, this appears intended to use `DTCM_DEPTH`.

## 9. Pipeline Dataflow Summary

```text
IFU
  pc_if
  |
  v
IDU
  instr_id, pc_id, rs indexes, rd index, immediate, dec_info_bus
  |
  v
EXU
  forwarded operands
  ALU/LSU/BRU/CSR dispatch
  branch redirect
  memory request metadata
  write-back candidate
  |
  v
MAU
  external memory access
  load formatting
  write-back selection
  |
  v
WBU
  register file write-back
```

## 10. Current Architectural Limitations and Follow-Up Items

The following items are visible from the current RTL and should be treated as design status notes:

1. `is_load_req_exu` is declared in `core_rv32i_v0` but is not driven by `exu`, so load-use stall detection is architecturally intended but not fully wired.
2. `exu_lsu` generates `o_lsu_misaligned_exc`, but the exception signal is not integrated into the core-level trap/CSR flow.
3. CSR illegal access is detected and gated in EXU, but there is no complete exception entry pipeline yet.
4. `minstret` is present but not active because `i_instr_ret_en` is tied to zero.
5. Data-side ITCM reads return zero through `soc_bus_v0`; only ITCM writes are routed.
6. `mem_dtcm` appears to instantiate memory depth with `` `ITCM_DEPTH`` rather than `` `DTCM_DEPTH``.
7. ECALL/EBREAK and broader machine-mode trap behavior are recognized in decode-related logic but not implemented as a full architectural flow.

## 11. Module Inventory

| File | Module | Summary |
| --- | --- | --- |
| `core/core_rv32i_v0.sv` | `core_rv32i_v0` | Core integration top |
| `core/ifu.sv` | `ifu` | PC generation and branch redirect |
| `core/idu.sv` | `idu` | Instruction decode and ID pipeline register |
| `core/exu.sv` | `exu` | EX pipeline register, forwarding muxes, execution dispatch |
| `core/exu_alu.sv` | `exu_alu` | Integer ALU |
| `core/exu_lsu.sv` | `exu_lsu` | Load/store address, mask, store-data generation |
| `core/exu_bru.sv` | `exu_bru` | Branch/jump compare and target generation |
| `core/exu_csr.sv` | `exu_csr` | CSR instruction execution |
| `core/mau.sv` | `mau` | Memory access stage and load result formatting |
| `core/wbu.sv` | `wbu` | Write-back stage register |
| `core/regfile.sv` | `regfile` | RV32 integer register file |
| `core/csr_regs.sv` | `csr_regs` | CSR storage and counters |
| `core/ctrl_hazard.sv` | `ctrl_hazard` | Forwarding, load-use stall, branch flush |
| `soc/soc_top_v0.sv` | `soc_top_v0` | SoC integration top |
| `soc/soc_bus_v0.sv` | `soc_bus_v0` | Data address decode and memory routing |
| `periphs/mem_itcm.sv` | `mem_itcm` | Instruction TCM |
| `periphs/mem_dtcm.sv` | `mem_dtcm` | Data TCM |
| `defines/config.v` | N/A | Shared configuration macros |
