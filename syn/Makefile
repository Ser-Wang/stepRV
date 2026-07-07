# Makefile for Design Compiler Synthesis Flow
SHELL := /bin/bash

# ------------------------------------------------------------------------------
# Configurable Variables
# ------------------------------------------------------------------------------
DESIGN_NAME   ?= 10_rv32im
DESIGN_TOP    ?= soc_top
SDC_NAME      ?= soc_top

# ------------------------------------------------------------------------------
# Directory and File Setup
# ------------------------------------------------------------------------------
PROJ_ROOT     := $(abspath $(CURDIR)/..)
RTL_PATH      := $(PROJ_ROOT)/$(DESIGN_NAME)/de
DEFINE_PATH   := $(RTL_PATH)/defines
FILELIST_PATH  := $(PROJ_ROOT)/$(DESIGN_NAME)/filelists

SYN_FILELIST  ?= $(FILELIST_PATH)/filelist_syn_sram.f

SRAM_MACRO_ROOT ?= /home/moxiao/pdk/smic55/sram/generated/macros
SRAM_MACRO_DBLIST ?= $(FILELIST_PATH)/filelist_sram_macro_db.f
SRAM_MACRO_DB_FILES ?= $(shell if [ -f "$(SRAM_MACRO_DBLIST)" ]; then sed -E '/^[[:space:]]*$$/d; /^[[:space:]]*\#/d; /^[[:space:]]*\/\//d; s/[[:space:]]+$$//' "$(SRAM_MACRO_DBLIST)"; fi)

STD_DB_PATH   ?= /home/moxiao/pdk/smic55/lib
STD_DB_LIST ?= scc55ulp_hdlp_rvt_ss_v1p08_125c_ccs.db
# STD_DB_LIST   ?= scc55ulp_hdlp_rvt_tt_v1p2_25c_ccs.db

# Date and Output Directory precise to the minute
DATE          := $(shell date +%Y%m%d_%H%M)
OUT_DIR       := $(CURDIR)/output/$(DATE)

# Export variables to sub-processes (like dc_shell)
export DESIGN_TOP
export SDC_NAME
export RTL_PATH
export DEFINE_PATH
export STD_DB_PATH
export STD_DB_LIST
export SYN_FILELIST
export SRAM_MACRO_ROOT
export SRAM_MACRO_DB_FILES
export OUT_DIR

# Tools
DC_SHELL      := dc_shell-t

# ------------------------------------------------------------------------------
# Targets
# ------------------------------------------------------------------------------
.PHONY: syn check clean help

# Default target runs synthesis
all: syn

# Run Synthesis
syn:
	mkdir -p $(OUT_DIR)
	@set -o pipefail; $(DC_SHELL) -f scr/dc.tcl | tee $(OUT_DIR)/syn.log; status=$$?; \
	sed -E -n '/(error|warning|fatal)/Ip' $(OUT_DIR)/syn.log > $(OUT_DIR)/check_error_warning.log; \
	if [ $$status -ne 0 ]; then \
		exit $$status; \
	fi; \
	if grep -Eiq '(fatal|error)' $(OUT_DIR)/check_error_warning.log; then \
		exit 1; \
	fi

# Run fast front-end checks only: analyze, elaborate, link, check_design,
# constraints load, check_timing. This skips compile and netlist export.
check:
	mkdir -p $(OUT_DIR)
	@set -o pipefail; $(DC_SHELL) -f scr/dc_check.tcl | tee $(OUT_DIR)/check.log; status=$$?; \
	sed -E -n '/(error|warning|fatal|loop|unresolved|multiple|latch)/Ip' $(OUT_DIR)/check.log > $(OUT_DIR)/check_error_warning.log; \
	if [ $$status -ne 0 ]; then \
		exit $$status; \
	fi; \
	if grep -Eiq '(fatal|error)' $(OUT_DIR)/check_error_warning.log; then \
		exit 1; \
	fi

# Clean up generated files and directories
clean:
	rm -rf WORK alib-52 WORK_GP_LIB
	rm -rf output
	rm -f syn.log check_error_warning.log
	rm -f command.log filenames.log default.svf

# Help Menu
help:
	@echo "Usage:"
	@echo "  make check                Run fast DC analyze/elaborate/link/check_design flow"
	@echo "  make syn                  Run synthesis with default top 'soc_top' in '10_rv32im'"
	@echo "  make syn DESIGN_NAME=... DESIGN_TOP=... SDC_NAME=...  Run synthesis for a different design/top/SDC"
	@echo "  make syn STD_DB_LIST='...'  Select standard-cell DB corner/library"
	@echo "  make syn SYN_FILELIST='...' SRAM_MACRO_DBLIST='...'  Configure synthesis filelist and SRAM macro DBs"
	@echo "  make clean                Remove all generated files and folders"
