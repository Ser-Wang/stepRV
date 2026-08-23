#!/usr/bin/env bash
set -euo pipefail

# The experiment stays under doc/experiment; the shared DC flow stays in syn/.
script_dir=$(cd "$(dirname "$0")" && pwd)
experiment_dir=$(cd "$script_dir/.." && pwd)
proj_root=$(cd "$experiment_dir/../../.." && pwd)
syn_dir="$proj_root/syn"
run_stamp=$(date +%Y%m%d_%H%M%S)
run_dir="$syn_dir/output/alu_area_$run_stamp"
mkdir -p "$run_dir"

run_one() {
    local variant=$1
    local design_top=$2
    local filelist=$3

    echo "[$variant] Synthesizing $design_top"
    make -C "$syn_dir" syn \
        DESIGN_NAME=11_rv32im_bpu \
        DESIGN_TOP="$design_top" \
        SDC_NAME=../../doc/experiment/exu_alu_area_optimization/syn/exu_alu_area \
        SYN_FILELIST="$script_dir/filelist/$filelist" \
        SRAM_MACRO_DBLIST=/dev/null \
        OUT_DIR="$run_dir/$variant"
}

# All three runs use the same SMIC55 library selected by syn/Makefile and the
# same standalone combinational constraint archived beside this script.
run_one current       exu_alu              exu_alu_current.f
run_one no_isolation  exu_alu_no_isolation exu_alu_no_isolation.f
run_one unshared      exu_alu_unshared      exu_alu_unshared.f

current_rpt="$run_dir/current/rpt/exu_alu_area.rpt"
no_iso_rpt="$run_dir/no_isolation/rpt/exu_alu_no_isolation_area.rpt"
unshared_rpt="$run_dir/unshared/rpt/exu_alu_unshared_area.rpt"

area_of() {
    awk '/Total cell area:/ {print $4; found=1} END {if (!found) exit 1}' "$1"
}

current_area=$(area_of "$current_rpt")
no_iso_area=$(area_of "$no_iso_rpt")
unshared_area=$(area_of "$unshared_rpt")

awk -v current="$current_area" -v no_iso="$no_iso_area" -v unshared="$unshared_area" '
BEGIN {
    printf "variant\ttotal_cell_area_um2\n"
    printf "unshared\t%.6f\n", unshared
    printf "shared_no_isolation\t%.6f\n", no_iso
    printf "shared_with_isolation\t%.6f\n", current
    printf "\ncomparison\tdelta_um2\tdelta_percent\n"
    printf "sharing_saved_vs_unshared\t%.6f\t%.3f%%\n", \
           unshared-no_iso, 100.0*(unshared-no_iso)/unshared
    printf "isolation_overhead_vs_no_isolation\t%.6f\t%.3f%%\n", \
           current-no_iso, 100.0*(current-no_iso)/no_iso
}' | tee "$run_dir/summary.tsv"

printf '%s\n' "$run_dir" > "$syn_dir/output/alu_area_latest_path.txt"
echo "Reports complete: $run_dir"
