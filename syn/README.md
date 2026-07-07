# Design Compiler Flow for my-RISCV-Projs

This directory contains a Makefile-driven Synopsys Design Compiler flow adapted
for `10_rv32im`.

## Directory Layout

```text
syn/
├── Makefile
├── sdc/
│   └── soc_top.sdc
└── scr/
    ├── dc.tcl
    ├── dc_check.tcl
    ├── 1_dc_setup.tcl
    ├── 2_dc_const.tcl
    ├── 3_dc_compile.tcl
    ├── 4_dc_report.tcl
    └── 5_dc_temp_report.tcl
```

The default configuration is:

```text
DESIGN_NAME    = 10_rv32im
DESIGN_TOP     = soc_top
SDC_NAME       = soc_top
RTL_PATH       = ../10_rv32im/de
SYN_FILELIST   = ../10_rv32im/filelists/filelist_syn_sram.f
STD_DB_PATH    = /home/moxiao/pdk/smic55/lib
STD_DB_LIST    = scc55ulp_hdlp_rvt_tt_v1p2_25c_ccs.db
```

The setup script uses Design Compiler's VCS-style filelist parser:

```tcl
analyze -vcs "+define+SYNTHESIS +incdir+... -f $SYN_FILELIST" -format sverilog
```

Filelist source entries stay relative to `RTL_PATH`, for example
`soc/soc_top.sv`. The setup script also adds
`../10_rv32im/de/defines` to the include path so source files can
resolve `include "config.v"`.

The default SRAM synthesis filelist nests the base RTL and SRAM wrapper lists:

```text
-f ../10_rv32im/filelists/filelist_rtl.f
-f ../10_rv32im/filelists/filelist_sram_wrapper.f
```

For designs without SRAM macros, point `SYN_FILELIST` at the RTL-only filelist.
For designs with different SRAM macros, update the design-local synthesis
filelist and `SRAM_MACRO_DBLIST`, or override those variables on the make command
line. `SRAM_MACRO_DBLIST` uses one `.db` path per line and supports blank lines
plus full-line `#` or `//` comments.

The VCS-style parser used by this DC version does not ignore `#` comment lines
inside HDL filelists. Keep synthesis HDL filelists to source paths and `-f`
entries.

The standard-cell synthesis target library is configured in `Makefile` through
`STD_DB_PATH` and `STD_DB_LIST`, matching the origin flow's `STD_DB_PATH` /
`STD_DB_LIST` style. Override `STD_DB_LIST` to switch to another independent
`.db` corner.

The RTL macro selection itself is owned by the design source. For this project,
`USE_SRAM_MACRO` is defined in `../10_rv32im/de/defines/config.v`, and
the synthesis scripts do not pass it through command-line defines.

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
rpt/soc_top_chk_design.rpt
rpt/soc_top_check_timing.rpt
rpt/soc_top_constraints_check.rpt
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
