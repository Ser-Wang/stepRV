# EXU ALU 面积实验使用说明

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: 2026-08-23 21:48
**Current Version**: v1.0

**Version Changelog**:
- **v1.0** (2026-08-23 21:48): 归档实验文件与最简复现步骤。

---

文件保持当前目录结构即可：`rtl/` 放两个对照 ALU，`syn/` 放脚本、约束和 filelist；原版 ALU 保持在 `11_rv32im_bpu/de/core/exu_alu.sv`。

```bash
cd /home/moxiao/work/my-RISCV-Projs/syn
bash ../doc/experiment/exu_alu_area_optimization/syn/run_synthesis.sh
```

汇总结果看 `syn/output/alu_area_latest_path.txt` 所指目录内的 `summary.tsv`；原始面积报告在该目录三个子目录的 `rpt/*_area.rpt`。
