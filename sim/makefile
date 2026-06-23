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

# ---- Global Config ----
SHELL       := /bin/bash
.SHELLFLAGS := -o pipefail -c

CORE_VERSION ?= ../00_rv32i_basic
DE_DIR       := $(CORE_VERSION)/de
DV_DIR       := $(CORE_VERSION)/dv
DEFINES_DIR  ?= $(DE_DIR)/defines
TB_FILE      ?= $(DV_DIR)/tb_soctop_isatest.sv
# DEFINES_DIR  :=
# No define files: change the line above to `DEFINES_DIR :=`, or run `make <target> DEFINES_DIR=`.

DUMP         ?= 0
VCS_DEFINES  := +define+VCS $(if $(filter 1,$(DUMP)),+define+DUMP_FSDB)
VCS_INCDIR   := $(if $(strip $(DEFINES_DIR)),+incdir+$(DEFINES_DIR))

TESTS_DIR    ?= ../tests/rv_tests_isa_new
COMP_DIR     := ../tests/rv_compliance
USERPROG_DIR := ../tests/programs

# ---- ISA test search folders ----
ISA_GROUPS   := rv32ui rv32um
COMP_GROUPS  := rv32i rv32im rv32Zicsr rv32Zifencei

# Common VCS compile options
VCS_FLAGS := \
	-timescale=1ns/100ps \
	-full64 +v2k -sverilog -Mupdate \
	$(VCS_INCDIR) \
	-debug_acc+all -debug_region+cell+encrypt

# ------------------------------------------------------------------------------
# Normal Compile / Sim / Verdi / Clean Flow
# ------------------------------------------------------------------------------
filelist:
	@find $(DE_DIR) -path "$(DEFINES_DIR)" -prune -o \( -name "*.v" -o -name "*.sv" \) -print > filelist.f
	@echo "$(TB_FILE)" >> filelist.f
	@echo "$(DV_DIR)/sva_exu_lsu.sv"       >> filelist.f
	@echo "$(DV_DIR)/sva_soc_bus.sv"       >> filelist.f
	@echo "$(DV_DIR)/sva_csr.sv"           >> filelist.f

# Compile for normal simulation
com:
	vcs -f filelist.f \
		$(VCS_FLAGS) $(VCS_DEFINES) \
		|tee vcs.log

sim: filelist com
	./simv |tee sim.log

sim_run_all: sim verdi

verdi:
	verdi -f filelist.f -ssf tb_top.fsdb -play ./scripts/verdi.tcl &

clean:
	rm -rf csrc novas* *.log simv* *fsdb* ucli.key verdiLog \
		inst.data dmem.data out.ref signature.output

# ------------------------------------------------------------------------------
# ISA / Compliance Test Flow
# ------------------------------------------------------------------------------

# Compile for ISA test mode
com_isa: VCS_DEFINES += +define+RVTEST_ISA
com_isa: filelist com

# Compile for Compliance test mode
com_compli: VCS_DEFINES += +define+RVTEST_COMPLIANCE
com_compli: filelist com

# Compile for user program mode
com_userprog: TB_FILE := $(DV_DIR)/tb_soctop_userprog.sv
com_userprog: filelist com

# Usage: make sim_isa test=add
#   Searches for rv32ui-p-add.data / rv32um-p-add.data etc.
sim_isa: com_isa
ifndef test
	$(error "Usage: make sim_isa test=<inst_name>  e.g. make sim_isa test=add")
endif
	@echo "=== ISA Test: $(test) ==="
	@found=0; \
	for grp in $(ISA_GROUPS); do \
		data_file="$(TESTS_DIR)/$$grp/$${grp}-p-$(test).data"; \
		if [ -f "$$data_file" ]; then \
			dmem_file="$${data_file%.data}.dmem.data"; \
			if [ ! -f "$$dmem_file" ]; then \
				echo "Error: Cannot find DMEM data for test '$(test)': $$dmem_file"; \
				exit 1; \
			fi; \
			cp "$$data_file" ./inst.data; \
			cp "$$dmem_file" ./dmem.data; \
			echo "  Data: $$data_file"; \
			echo "  DMem: $$dmem_file"; \
			found=1; \
			break; \
		fi; \
	done; \
	if [ "$$found" = "0" ]; then \
		echo "Error: Cannot find .data for test '$(test)' in $(ISA_GROUPS)"; \
		exit 1; \
	fi
	./simv |tee sim.log
	@echo ""
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
		data_file="$(COMP_DIR)/$$grp/$(test).data"; \
		if [ -f "$$data_file" ]; then \
			cp "$$data_file" ./inst.data; \
			echo "  Data: $$data_file"; \
			ref_file="$(COMP_DIR)/$$grp/$(test).ref"; \
			if [ -f "$$ref_file" ]; then \
				cp "$$ref_file" ./out.ref; \
				echo "  Ref:  $$ref_file"; \
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
	@echo ""
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
	cp "$$data_file" ./inst.data; \
	echo "=== User Program: $(name) ==="; \
	echo "  Data: $$data_file"; \
	echo "  TB:   $(DV_DIR)/tb_soctop_userprog.sv"; \
	echo "  RTL:  $(CORE_VERSION)"
	@$(MAKE) --no-print-directory com_userprog
	./simv |tee sim.log
	@echo ""
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
	@echo "-------------------------------------------"
	@echo "  Batch ISA Test: group=$(group)"
	@echo "-------------------------------------------"
	@pass=0; fail=0; total=0; \
	for data_file in $(TESTS_DIR)/$(group)/$(group)-p-*.data; do \
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
		cp "$$data_file" ./inst.data; \
		cp "$$dmem_file" ./dmem.data; \
		./simv > sim.log 2>&1; \
		if grep -q '\[PASS\]' sim.log; then \
			printf "  %-30s [  PASS  ]\n" "$$test_name"; \
			pass=$$((pass + 1)); \
		else \
			printf "  %-30s [# FAIL #]\n" "$$test_name"; \
			fail=$$((fail + 1)); \
			cp sim.log "sim_$${test_name}.fail.log"; \
		fi; \
	done; \
	echo ""; \
	echo "-------------------------------------------"; \
	echo "  Summary: $$pass/$$total Passed"; \
	echo "-------------------------------------------"; \
	if [ "$$fail" = "0" ]; then \
		echo "  Congratulations, All PASS!"; \
	else \
		echo "  $$fail test(s) failed. Check sim_*.fail.log"; \
	fi

# --- Internal: Batch Compliance ---
_batch_compli: com_compli
	@echo "-------------------------------------------"
	@echo "  Batch Compliance Test: group=$(group)"
	@echo "-------------------------------------------"
	@pass=0; fail=0; total=0; \
	for data_file in $(COMP_DIR)/$(group)/*.data; do \
		[ -f "$$data_file" ] || continue; \
		test_name=$$(basename "$$data_file" .data); \
		total=$$((total + 1)); \
		cp "$$data_file" ./inst.data; \
		ref_file="$(COMP_DIR)/$(group)/$${test_name}.ref"; \
		if [ -f "$$ref_file" ]; then \
			cp "$$ref_file" ./out.ref; \
		else \
			printf "  %-30s [# FAIL #] missing ref\n" "$$test_name"; \
			fail=$$((fail + 1)); \
			continue; \
		fi; \
		./simv > sim.log 2>&1; \
		if grep -q '\[PASS\]' sim.log; then \
			printf "  %-30s [  PASS  ]\n" "$$test_name"; \
			pass=$$((pass + 1)); \
		else \
			printf "  %-30s [# FAIL #]\n" "$$test_name"; \
			fail=$$((fail + 1)); \
			cp sim.log "sim_$${test_name}.fail.log"; \
		fi; \
	done; \
	echo ""; \
	echo "-------------------------------------------"; \
	echo "  Summary: $$pass/$$total Passed"; \
	echo "-------------------------------------------"; \
	if [ "$$fail" = "0" ]; then \
		echo "  Congratulations, All PASS!"; \
	else \
		echo "  $$fail test(s) failed. Check sim_*.fail.log"; \
	fi

.PHONY: all filelist com com_isa com_compli com_userprog sim sim_run_all \
        sim_isa sim_compli sim_userprog sim_user sim_isa_all _batch_isa \
        _batch_compli verdi clean
