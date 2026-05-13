# Hummingbird E203 RISC-V Core Analysis Skill

This document provides a structural overview and analysis of the E203 core to streamline future deep-dives.

## 1. Core Architecture
- **Type:** RV32IMAC (Configurable).
- **Pipeline:** 2-stage (IF, EX/Commit).
- **Bus:** ICB (Internal Chip Bus), a proprietary high-performance protocol.
- **TCM:** Dedicated Instruction TCM (ITCM) and Data TCM (DTCM).

## 2. Directory Structure (`ref/rtl_e203/`)
- `core/`: Primary CPU logic (IFU, EXU, LSU, BIU).
- `subsys/`: Subsystem top-level, including memory controllers, PLIC, and CLINT.
- `soc/`: SoC-level wrapper.
- `fab/`: Interconnect and bus bridging logic.
- `debug/`: JTAG/Debug module.
- `perips/`: Integrated peripherals (UART, SPI, GPIO, etc.).

## 3. Module Hierarchy & Key Files

### Top-Level Hierarchy
1. **`e203_soc_top`** (`soc/e203_soc_top.v`)
2. **`e203_subsys_top`** (`subsys/e203_subsys_top.v`)
3. **`e203_core`** (`core/e203_core.v`)

### Core Sub-units (`core/`)
- **IFU (`e203_ifu.v`)**: Instruction Fetch Unit.
  - `e203_ifu_ifetch.v`: Fetch control logic.
  - `e203_ifu_ift2icb.v`: Fetch to ICB interface conversion.
- **EXU (`e203_exu.v`)**: Execution Unit.
  - `e203_exu_decode.v`: Instruction decoding.
  - `e203_exu_disp.v`: Dispatching instructions to functional units.
  - `e203_exu_alu.v`: Single-cycle execution (ALU, BJP, CSR).
  - `e203_exu_oitf.v`: Hazard management for long-latency instructions.
  - `e203_exu_commit.v`: Trap handling and instruction retirement.
  - `e203_exu_regfile.v`: Register file (32 GPRs).
- **LSU (`e203_lsu.v`)**: Load Store Unit.
  - `e203_lsu_ctrl.v`: Address decoding and memory arbitration.
- **BIU (`e203_biu.v`)**: Bus Interface Unit for external memory access.

### Memory Controllers
- **`e203_itcm_ctrl.v`**: Manages ITCM. Supports simultaneous fetch and LSU access (write support for self-modifying code).
- **`e203_dtcm_ctrl.v`**: Manages DTCM.

## 4. Key Implementation Details
- **`fence.i` Implementation:**
  - Stalls dispatch until `oitf` is empty (all stores completed).
  - Triggers a pipeline flush in `e203_exu_branchslv.v`.
  - IFU restarts fetching from the next PC, ensuring visibility of modified instructions in ITCM.
- **Hazard Handling:** Uses the **OITF** (Outstanding Instruction Track FIFO) to track long-latency instructions (LSU, MUL, DIV) and manage RAW/WAW hazards.
- **NICE Interface:** Dedicated ports in `e203_core` for co-processor expansion.

## 5. Analysis Guidelines
- When analyzing instruction execution: Start at `e203_exu_decode` -> `e203_exu_disp` -> `e203_exu_alu`.
- When analyzing memory access: Check `e203_lsu_ctrl` for address decoding logic.
- When analyzing pipeline flushes: Check `e203_exu_commit` and `e203_exu_branchslv`.
