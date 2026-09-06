# Repository Guidelines

## Project Structure & Module Organization

This repository develops an RV32 SoC through numbered design stages. The current implementation is in `10_rv32im/`; earlier directories preserve prior milestones. Within a design, `de/` contains SystemVerilog RTL (`core/`, `soc/`, `periphs/`, and `defines/`), `dv/` contains testbenches and SVA, `filelists/` defines tool inputs, and `fpga/` holds FPGA collateral. Shared test images live under `tests/`. Simulation and synthesis flows are in `sim/` and `syn/`; utilities are in `tools/scripts/`. Treat `ref/` as reference material.

## Build, Test, and Development Commands

Run commands from the relevant flow directory:

- `cd sim && make sim_isa test=add` compiles with VCS and runs one `riscv-tests` ISA case.
- `cd sim && make sim_compli test=I-ADD-01` runs one compliance case.
- `cd sim && make sim_isa_all type=isa group=rv32ui` runs an ISA group.
- `cd sim && make sim_userprog name=simple` runs `tests/programs/simple/simple.data`.
- `cd sim && make verdi` opens the latest FSDB waveform; `make clean` removes generated simulation artifacts.
- `cd syn && make check` performs fast Design Compiler elaboration and timing checks; `make syn` runs full synthesis.

VCS, Verdi, Design Compiler, the RISC-V toolchain, and configured SMIC55 libraries may be required.

## Coding Style & Naming Conventions

Use SystemVerilog for new RTL and four-space indentation. Use lowercase `snake_case` for modules, files, signals, and parameters; `i_`/`o_` prefixes for ports; `_n` for active-low signals; and `u_<module>` for instances. Align port connections, declare widths explicitly, and keep one primary module per file. Put shared macros in `de/defines/config.v`. No formatter is configured, so match adjacent code.

## Testing Guidelines

Add directed testbench logic in the design's `dv/` directory and reusable assertions as `sva_<area>.sv`. Add program images under `tests/programs/<name>/` and ISA data in the matching `rv32ui`, `rv32um`, or compliance group. A change is ready when its focused test reports `[PASS]`; architectural changes should also run the affected batch group and `syn/make check` when available. Review `sim.log` and `sva.log` for failures.

## Commit & Pull Request Guidelines

Only user can use commit, pull commands, LLM/Agents are forbidden from using these git commands that changes files.

## Development Workflow

- Use the task/work-order document as the source of truth for scoped development. After its requirements and acceptance criteria are ready for implementation, set `Status` to an English state such as `Ready for Execution` and append the local timestamp in parentheses: `Ready for Execution (YYYY-MM-DD HH:MM)`. Status names are descriptive and are not restricted to a fixed enumeration.
- Preserve the complete task status history on the same `Status` line. Whenever the state changes, prepend the newest state and timestamp before the older states, separated by ` | `. For example: `**Status**: Completed (YYYY-MM-DD HH:MM) | Ready for Execution (YYYY-MM-DD HH:MM)`. Never delete or overwrite an earlier state; if there are multiple earlier states, retain them in reverse chronological order.
- After completing a task/work order, update the corresponding version development log at `doc/dev_log/log_dev_<version>.md`. Add a concise entry linking the task and recording the implemented content, verification results, and any accepted known failures or unperformed checks. Keep development-log entries in reverse chronological order, with the newest completed task first.
- Keep repeated development-log DV results brief. When a task uses the same standard regression and acceptance criteria as nearby entries, summarize the group results and accepted known failure instead of repeating commands or detailed completion criteria.

## Documentation Convention

This repository will be used as a reference design for RISC-V analysis. Every newly created or materially updated Markdown analysis document must begin with the following unified title and header block:

```markdown
# Document Title

**Author**: Wang Jianghao, Codex, GPT-5.6-Solar
**Created**: YYYY-MM-DD HH:MM
**Current Version**: vX.Y

**Version Changelog**:
- **vX.Y** (YYYY-MM-DD HH:MM): Brief description of the current change.

---
```

Task/work-order documents must additionally insert the following field after `Current Version` and before `Version Changelog`:

```markdown
**Status**: Completed (YYYY-MM-DD HH:MM)
```

Requirements:

- Place the document title on the first line. Do not put author, version, status, or other metadata before the title.
- Use local time in `YYYY-MM-DD HH:MM` format. Preserve the original `Created` timestamp across later revisions.
- Development logs named `log_dev_<version>.md` are an exception to document version metadata: retain the title, `Author`, `Created`, and terminating `---`, but omit `Current Version` and `Version Changelog`. Their reverse-chronological development entries are the iteration history.
- Version-local AI acceptance rules named `doc/dev_log/rule_ai_acceptance.md` are also an exception: use only the document title and rule body, without the unified metadata header.
- Use `Status` only for task/work-order documents; other Markdown analysis documents must omit it. In a task document, place `Status` after `Current Version` and before `Version Changelog`. Follow the status-history and timestamp rules in `Development Workflow`.
- For documents that use version metadata, start at `v1.0`. Increment the version appropriately for every material revision and update `Current Version` to match.
- For documents that use `Version Changelog`, keep all historical entries in reverse chronological/version order, with the newest version first.
- Keep each version changelog item to one or two concise sentences describing what changed.
- End the header block with a standalone `---` separator before the document body.
- Retain `Author` as `Wang Jianghao, Codex, GPT-5.6-Solar` unless the user explicitly specifies otherwise.
