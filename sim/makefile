# ------------------------------------------------------------------------------
# Makefile for RISC-V Core VCS Simulation
# ------------------------------------------------------------------------------
# Usage:
#   make sim_isa  test=add              - Run a single ISA test (riscv-tests)
#   make sim_compli test=I-ADD-01       - Run a single Compliance test
#   make sim_userprog name=simple       - Run tests/programs/<name>/<name>.data with tb_soctop_userprog
#   make sim_isa_all type=isa    group=rv32ui   - Batch run all ISA tests in a group
#   make sim_isa_all type=compli group=rv32i    - Batch run all Compliance tests in a group
#   make sim_run_all                    - Run normal filelist, compile, sim, and Verdi flow
#   make verdi                          - Open Verdi with latest waveform
#   make clean                          - Clean all generated files
# ------------------------------------------------------------------------------

DUMP         ?= 0
SIMV_ARGS    ?=
EXTRA_VCS_DEFINES ?=
# ---- Global Config ----
SHELL       := /bin/bash
.SHELLFLAGS := -o pipefail -c
.NOTPARALLEL:

DESIGN_NAME ?= ../12_rv32im_bpu_cache
DE_DIR       := $(DESIGN_NAME)/de
DV_DIR       := $(DESIGN_NAME)/dv
DEFINES_DIR  := $(DE_DIR)/defines
FILELIST_DIR := $(DESIGN_NAME)/filelists
TB_FILE      := $(DV_DIR)/tb_soctop_isatest.sv
SIM_FILELIST := $(FILELIST_DIR)/filelist_sim_sram.f
ICACHE_FINAL_TB_FILE := $(DV_DIR)/tb_icache_final.sv
DCACHE_FINAL_TB_FILE := $(DV_DIR)/tb_dcache_final.sv

FILELIST_OUT ?= filelist.f
SVA_FILES := \
	$(DV_DIR)/sva_exu_lsu.sv \
	$(DV_DIR)/sva_soc_bus.sv \
	$(wildcard $(DV_DIR)/sva_mem_transaction.sv) \
	$(DV_DIR)/sva_csr.sv

# Version-local optional checkers. wildcard keeps the shared flow usable for
# design versions that do not implement the corresponding feature.
# SVA_FILES += $(wildcard $(DV_DIR)/sva_bpu_idu.sv)
# SVA_FILES += $(wildcard $(DV_DIR)/sva_bpu_exu.sv)

# ---- Test Dirs ----
RVTESTS_DIR  ?= ../tests/rv_tests_isa_new
RVCOMPI_DIR  ?= ../tests/rv_compliance_new
USERPROG_DIR := ../tests/programs

# ---- ISA test search folders ----
ISA_GROUPS   := rv32ui rv32um
COMP_GROUPS  := rv32i rv32im rv32Zicsr rv32Zifencei


SVA_LOG      ?= sva.log
USERPROG_DEFINES := $(if $(filter coremark_10,$(strip $(name))),+define+PROG_COREMARK_10)
VCS_DEFINES  := +define+VCS $(if $(filter 1,$(DUMP)),+define+DUMP_FSDB) \
	$(USERPROG_DEFINES) $(EXTRA_VCS_DEFINES)
VCS_INCDIR   := $(if $(strip $(DEFINES_DIR)),+incdir+$(DEFINES_DIR))
# Common VCS compile options
VCS_FLAGS := \
	-timescale=1ns/100ps \
	-full64 +v2k -sverilog -Mupdate \
	$(VCS_INCDIR) \
	-debug_acc+all -debug_region+cell+encrypt \
	+notimingcheck

# ------------------------------------------------------------------------------
# Normal Compile / Sim / Verdi / Clean Flow
# ------------------------------------------------------------------------------
filelist:
	@find $(DE_DIR) \( -name "*.v" -o -name "*.sv" \) -print > $(FILELIST_OUT)

filelist_cfig:
	@printf "%s\n" "-f $(SIM_FILELIST)" "$(TB_FILE)" $(SVA_FILES) > $(FILELIST_OUT)

# Compile for normal simulation
com:
	vcs -f $(FILELIST_OUT) \
		$(VCS_FLAGS) $(VCS_DEFINES) \
		|tee vcs.log

sim: com
	./simv $(SIMV_ARGS) |tee sim.log
	@$(MAKE) --no-print-directory sva_log

sim_run_all: sim verdi

# Phase 3 final L1 focused tests. Build products stay in the shared sim folder.
sim_phase3_icache:
	vcs $(DE_DIR)/core/cache_data_array_1rw.sv \
		$(DE_DIR)/core/cache_tag_array_1rw.sv \
		$(DE_DIR)/core/icache.sv $(ICACHE_FINAL_TB_FILE) \
		$(VCS_FLAGS) $(VCS_DEFINES) -top tb_icache_final \
		|tee vcs.log
	./simv |tee sim.log

sim_phase3_dcache:
	vcs $(DE_DIR)/soc/soc_bus.sv \
		$(DE_DIR)/core/cache_data_array_1rw.sv \
		$(DE_DIR)/core/cache_tag_array_1rw.sv \
		$(DE_DIR)/core/dcache.sv \
		$(DE_DIR)/periphs/backing_dmem.sv $(DCACHE_FINAL_TB_FILE) \
		$(VCS_FLAGS) $(VCS_DEFINES) -top tb_dcache_final \
		|tee vcs.log
	./simv |tee sim.log

verdi:
	verdi -f $(FILELIST_OUT) -ssf tb_top.fsdb -play ./scripts/verdi.tcl &

clean:
	rm -rf csrc novas* *.log simv* *fsdb* ucli.key verdiLog \
		inst.data dmem.data out.ref signature.output

# ------------------------------------------------------------------------------
# ISA / Compliance Test Flow
# ------------------------------------------------------------------------------

# Compile for ISA test mode
com_isa: VCS_DEFINES += +define+RVTEST_ISA
com_isa: filelist_cfig com

# Compile for Compliance test mode
com_compli: VCS_DEFINES += +define+RVTEST_COMPLIANCE
com_compli: filelist_cfig com

# Compile for user program mode
com_userprog: TB_FILE := $(DV_DIR)/tb_soctop_userprog.sv
com_userprog: filelist_cfig com

# Usage: make sim_isa test=add
#   Searches for rv32ui-p-add.data / rv32um-p-add.data etc.
sim_isa: com_isa
ifndef test
	$(error "Usage: make sim_isa test=<inst_name>  e.g. make sim_isa test=add")
endif
	@echo "=== ISA Test: $(test) ==="
	@found=0; \
	for grp in $(ISA_GROUPS); do \
		data_file="$(RVTESTS_DIR)/$$grp/$${grp}-p-$(test).data"; \
		if [ -f "$$data_file" ]; then \
			dmem_file="$${data_file%.data}.dmem.data"; \
			if [ ! -f "$$dmem_file" ]; then \
				echo "Error: Cannot find DMEM data for test '$(test)': $$dmem_file"; \
				exit 1; \
			fi; \
			rm -f ./inst.data ./dmem.data ./out.ref; \
			cp "$$data_file" ./inst.data; \
			cp "$$dmem_file" ./dmem.data; \
			found=1; \
			break; \
		fi; \
	done; \
	if [ "$$found" = "0" ]; then \
		echo "Error: Cannot find .data for test '$(test)' in $(ISA_GROUPS)"; \
		exit 1; \
	fi
	./simv |tee sim.log
	@$(MAKE) --no-print-directory sva_log
	@if grep -q '\[PASS\]' sim.log; then \
		echo ">>> Result: [PASS]"; \
	else \
		echo ">>> Result: [FAIL] - Check sim.log for details"; \
	fi

# Single Test: Compliance (riscv-compliance)
# Usage: make sim_compli test=I-ADD-01
#   Searches for I-ADD-01.data in rv32i, rv32im, etc.
sim_compli: com_compli
ifndef test
	$(error "Usage: make sim_compli test=<test_name>  e.g. make sim_compli test=I-ADD-01")
endif
	@echo "=== Compliance Test: $(test) ==="
	@found=0; \
	for grp in $(COMP_GROUPS); do \
		data_file="$(RVCOMPI_DIR)/$$grp/$(test).data"; \
		if [ -f "$$data_file" ]; then \
			rm -f ./inst.data ./dmem.data ./out.ref; \
			cp "$$data_file" ./inst.data; \
			dmem_file="$${data_file%.data}.dmem.data"; \
			if [ -f "$$dmem_file" ]; then \
				cp "$$dmem_file" ./dmem.data; \
			else \
				printf "00000000\n" > ./dmem.data; \
			fi; \
			ref_file="$(RVCOMPI_DIR)/$$grp/$(test).ref"; \
			if [ -f "$$ref_file" ]; then \
				cp "$$ref_file" ./out.ref; \
			else \
				echo "Error: Cannot find .ref for test '$(test)': $$ref_file"; \
				exit 1; \
			fi; \
			found=1; \
			break; \
		fi; \
	done; \
	if [ "$$found" = "0" ]; then \
		echo "Error: Cannot find .data for test '$(test)' in $(COMP_GROUPS)"; \
		exit 1; \
	fi
	./simv |tee sim.log
	@$(MAKE) --no-print-directory sva_log
	@if grep -q '\[PASS\]' sim.log; then \
		echo ">>> Result: [PASS]"; \
	elif grep -q '\[FAIL\]' sim.log; then \
		echo ">>> Result: [FAIL] - Check sim.log for details"; \
	else \
		echo ">>> Result: [UNKNOWN] - No ref file or no pass/fail detected"; \
	fi

# Single User Program
# Usage: make sim_userprog name=simple
#   Copies ../tests/programs/simple/simple.data to ./inst.data, then runs
#   tb_soctop_userprog.sv. Alias: make sim_user name=simple
sim_userprog:
ifndef name
	$(error "Usage: make sim_userprog name=<program_name>  e.g. make sim_userprog name=simple")
endif
	@data_file="$(USERPROG_DIR)/$(name)/$(name).data"; \
	if [ ! -f "$$data_file" ]; then \
		echo "Error: Cannot find user program data: $$data_file"; \
		exit 1; \
	fi; \
	rm -f ./inst.data ./dmem.data ./out.ref; \
	cp "$$data_file" ./inst.data; \
	echo "=== User Program: $(name) ==="
	@$(MAKE) --no-print-directory com_userprog
	./simv $(SIMV_ARGS) |tee sim.log
	@$(MAKE) --no-print-directory sva_log
	@if grep -q '\[PASS\]' sim.log; then \
		echo ">>> Result: [PASS]"; \
	elif grep -q '\[FAIL\]' sim.log; then \
		echo ">>> Result: [FAIL] - Check sim.log for details"; \
	else \
		echo ">>> Result: [DONE] - Check sim.log for UART/user-program output"; \
	fi

sim_user: sim_userprog

# Batch Test: sim_isa_all
# Usage:
#   make sim_isa_all type=isa    group=rv32ui
#   make sim_isa_all type=compli group=rv32i
sim_isa_all:
ifndef type
	$(error "Usage: make sim_isa_all type=<isa|compli> group=<group_name>")
endif
ifndef group
	$(error "Usage: make sim_isa_all type=<isa|compli> group=<group_name>")
endif
ifeq ($(type),isa)
	@$(MAKE) --no-print-directory _batch_isa group=$(group)
else ifeq ($(type),compli)
	@$(MAKE) --no-print-directory _batch_compli group=$(group)
else
	$(error "Unknown type '$(type)'. Use 'isa' or 'compli'.")
endif

# --- Internal: Batch ISA ---
_batch_isa: com_isa
	@echo "=== Batch ISA: group=$(group) ==="
	@pass=0; fail=0; total=0; \
	for data_file in $(RVTESTS_DIR)/$(group)/$(group)-p-*.data; do \
		[ -f "$$data_file" ] || continue; \
		[[ "$$data_file" != *.dmem.data ]] || continue; \
		test_name=$$(basename "$$data_file" .data | sed 's/$(group)-p-//'); \
		dmem_file="$${data_file%.data}.dmem.data"; \
		total=$$((total + 1)); \
		if [ ! -f "$$dmem_file" ]; then \
			printf "  %-30s [# FAIL #] missing dmem\n" "$$test_name"; \
			fail=$$((fail + 1)); \
			continue; \
		fi; \
		rm -f ./inst.data ./dmem.data ./out.ref; \
		cp "$$data_file" ./inst.data; \
		cp "$$dmem_file" ./dmem.data; \
		./simv > sim.log 2>&1; \
		if grep -q '\[PASS\]' sim.log && ! grep -q '\[BPU SVA\]' sim.log; then \
			printf "  %-30s [  PASS  ]\n" "$$test_name"; \
			pass=$$((pass + 1)); \
		else \
			printf "  %-30s [# FAIL #]\n" "$$test_name"; \
			fail=$$((fail + 1)); \
			cp sim.log "sim_$${test_name}.fail.log"; \
		fi; \
	done; \
	echo "-------------------------------------------"; \
	echo "  Summary: $$pass/$$total Passed"; \
	echo "-------------------------------------------"; \
	if [ "$$fail" != "0" ]; then \
		echo "  $$fail test(s) failed. Check sim_*.fail.log"; \
	fi

# --- Internal: Batch Compliance ---
_batch_compli: com_compli
	@echo "=== Batch Compliance: group=$(group) ==="
	@pass=0; fail=0; total=0; \
	for data_file in $(RVCOMPI_DIR)/$(group)/*.data; do \
		[ -f "$$data_file" ] || continue; \
		[[ "$$data_file" != *.dmem.data ]] || continue; \
		test_name=$$(basename "$$data_file" .data); \
		total=$$((total + 1)); \
		rm -f ./inst.data ./dmem.data ./out.ref; \
		cp "$$data_file" ./inst.data; \
		dmem_file="$${data_file%.data}.dmem.data"; \
		if [ -f "$$dmem_file" ]; then \
			cp "$$dmem_file" ./dmem.data; \
		else \
			printf "00000000\n" > ./dmem.data; \
		fi; \
		ref_file="$(RVCOMPI_DIR)/$(group)/$${test_name}.ref"; \
		if [ -f "$$ref_file" ]; then \
			cp "$$ref_file" ./out.ref; \
		else \
			printf "  %-30s [# FAIL #] missing ref\n" "$$test_name"; \
			fail=$$((fail + 1)); \
			continue; \
		fi; \
		./simv > sim.log 2>&1; \
		if grep -q '\[PASS\]' sim.log && ! grep -q '\[BPU SVA\]' sim.log; then \
			printf "  %-30s [  PASS  ]\n" "$$test_name"; \
			pass=$$((pass + 1)); \
		else \
			printf "  %-30s [# FAIL #]\n" "$$test_name"; \
			fail=$$((fail + 1)); \
			cp sim.log "sim_$${test_name}.fail.log"; \
		fi; \
	done; \
	echo "-------------------------------------------"; \
	echo "  Summary: $$pass/$$total Passed"; \
	echo "-------------------------------------------"; \
	if [ "$$fail" != "0" ]; then \
		echo "  $$fail test(s) failed. Check sim_*.fail.log"; \
	fi

.PHONY: sva_log
sva_log:
	@{ \
		echo "SVA log summary"; \
		echo "Generated from sim.log"; \
		echo "----------------------------------------"; \
		if [ -f sim.log ]; then \
			grep -n -E '\[SVA Error\]|SVA Error|assert|Assertion|cover_|u_sva' sim.log 2>/dev/null || true; \
		else \
			echo "No sim.log found."; \
		fi; \
	} > $(SVA_LOG)
	@if grep -q -E '\[SVA Error\]|SVA Error|assert|Assertion|cover_|u_sva' $(SVA_LOG); then \
		echo "SVA summary written to $(SVA_LOG)"; \
	fi

.PHONY: all filelist filelist_cfig \
        com com_isa com_compli com_userprog sim sim_run_all \
        sim_isa sim_compli sim_userprog sim_user sim_isa_all _batch_isa \
        _batch_compli verdi clean sva_log sim_phase3_icache sim_phase3_dcache
