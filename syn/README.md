# Design Compiler Flow for my-RISCV-Projs

This directory contains a Makefile-driven Synopsys Design Compiler flow adapted
for `00_rv32i_basic`.

## Directory Layout

```text
syn/
├── Makefile
├── filelist/
│   └── soc_top_v0.f
├── sdc/
│   └── soc_top_v0.sdc
└── scr/
    ├── dc.tcl
    ├── dc_check.tcl
    ├── 1_dc_setup.tcl
    ├── 2_dc_const.tcl
    ├── 3_dc_compile.tcl
    └── 4_dc_report.tcl
```

The default configuration is:

```text
MODULE_NAME = 00_rv32i_basic
DESIGN_TOP  = soc_top_v0
SDC_NAME    = soc_top_v0
RTL_PATH    = ../00_rv32i_basic/de
```

Filelist entries are relative to `RTL_PATH`. The setup script also adds
`../00_rv32i_basic/de/defines` to the DC search path so source files can resolve
`include "config.v"`.

## Fast Check

Run front-end structural checks without compile or netlist export:

```bash
make check
```

This runs:

```text
analyze -> elaborate -> link -> check_design -> source SDC -> check_timing
```

Outputs are archived under:

```text
output/YYYYMMDD_HHMM/
```

Useful files include:

```text
check.log
check_error_warning.log
rpt/soc_top_v0_chk_design.rpt
rpt/soc_top_v0_check_timing.rpt
rpt/soc_top_v0_constraints_check.rpt
```

## Full Synthesis

Run the full compile/report/export flow:

```bash
make syn
```

This additionally runs `compile` and writes the synthesized netlist, DDC, SDF,
SDC, and reports under `output/YYYYMMDD_HHMM/`.

## Clean

```bash
make clean
```

This removes generated DC work libraries, logs, trash, and `output/`.

## Notes

If DC exits immediately with:

```text
Fatal: Design Compiler is not enabled. (DCSH-1)
```

the flow did not reach RTL analysis. Check Synopsys license/environment setup or
run on a machine/session where Design Compiler is enabled.
