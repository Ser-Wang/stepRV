#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
exp_dir=$(cd "$script_dir/.." && pwd)
proj_root=$(cd "$exp_dir/../../.." && pwd)
rtl_dir="$proj_root/11_rv32im_bpu/de"

sources=(
    "$rtl_dir/core/exu_alu.sv"
    "$exp_dir/rtl/exu_alu_unshared.sv"
    "$exp_dir/rtl/exu_alu_no_isolation.sv"
    "$script_dir/tb_exu_alu_equiv.sv"
)

if command -v iverilog >/dev/null 2>&1; then
    iverilog -g2012 -I "$rtl_dir/defines" \
        -o "$script_dir/exu_alu_equiv.vvp" "${sources[@]}"
    vvp "$script_dir/exu_alu_equiv.vvp"
else
    vcs -full64 -sverilog +incdir+"$rtl_dir/defines" \
        -Mdir="$script_dir/csrc" -o "$script_dir/simv" "${sources[@]}"
    "$script_dir/simv"
fi
