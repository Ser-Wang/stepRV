# Makefile for Design Compiler Synthesis Flow
SHELL := /bin/bash

# ------------------------------------------------------------------------------
# Configurable Variables
# ------------------------------------------------------------------------------
MODULE_NAME   ?= 00_rv32i_basic
DESIGN_TOP    ?= soc_top_v0
SDC_NAME      ?= soc_top_v0

# ------------------------------------------------------------------------------
# Directory and File Setup
# ------------------------------------------------------------------------------
PROJ_ROOT     := $(abspath $(CURDIR)/..)
RTL_PATH      := $(PROJ_ROOT)/$(MODULE_NAME)/de
DEFINE_PATH   := $(RTL_PATH)/defines
LIB_PATH      ?= /home/moxiao/pdk/smic55/lib

# Date and Output Directory precise to the minute
DATE          := $(shell date +%Y%m%d_%H%M)
OUT_DIR       := $(CURDIR)/output/$(DATE)

# Export variables to sub-processes (like dc_shell)
export DESIGN_TOP
export SDC_NAME
export RTL_PATH
export DEFINE_PATH
export LIB_PATH
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
	@echo "Starting DC Synthesis for $(MODULE_NAME) (Top: $(DESIGN_TOP), SDC: $(SDC_NAME)) -> $(OUT_DIR)"
	mkdir -p $(OUT_DIR)
	@set -o pipefail; $(DC_SHELL) -f scr/dc.tcl | tee $(OUT_DIR)/syn.log; status=$$?; \
	echo "Generating timing logs..."; \
	sed -E -n '/(error|warning|fatal)/Ip' $(OUT_DIR)/syn.log > $(OUT_DIR)/check_error_warning.log; \
	mkdir -p .trash; \
	mv command.log filenames.log default.svf .trash/ 2>/dev/null || true; \
	if [ $$status -ne 0 ]; then \
		echo "Synthesis failed. See: $(OUT_DIR)/syn.log"; \
		exit $$status; \
	fi; \
	if grep -Eiq '(fatal|error)' $(OUT_DIR)/check_error_warning.log; then \
		echo "Synthesis reported errors. See: $(OUT_DIR)/check_error_warning.log"; \
		exit 1; \
	fi
	@echo "Synthesis flow completed. Results available at: $(OUT_DIR)"

# Run fast front-end checks only: analyze, elaborate, link, check_design,
# constraints load, check_timing. This skips compile and netlist export.
check:
	@echo "Starting DC quick check for $(MODULE_NAME) (Top: $(DESIGN_TOP), SDC: $(SDC_NAME)) -> $(OUT_DIR)"
	mkdir -p $(OUT_DIR)
	@set -o pipefail; $(DC_SHELL) -f scr/dc_check.tcl | tee $(OUT_DIR)/check.log; status=$$?; \
	sed -E -n '/(error|warning|fatal|loop|unresolved|multiple|latch)/Ip' $(OUT_DIR)/check.log > $(OUT_DIR)/check_error_warning.log; \
	mkdir -p .trash; \
	mv command.log filenames.log default.svf .trash/ 2>/dev/null || true; \
	if [ $$status -ne 0 ]; then \
		echo "DC quick check failed. See: $(OUT_DIR)/check.log"; \
		exit $$status; \
	fi; \
	if grep -Eiq '(fatal|error)' $(OUT_DIR)/check_error_warning.log; then \
		echo "DC quick check reported errors. See: $(OUT_DIR)/check_error_warning.log"; \
		exit 1; \
	fi
	@echo "DC quick check completed. Results available at: $(OUT_DIR)"

# Clean up generated files and directories
clean:
	@echo "Cleaning up generated synthesis files..."
	rm -rf WORK alib-52 WORK_GP_LIB
	rm -rf output .trash
	rm -f syn.log check_error_warning.log
	rm -f command.log filenames.log default.svf

# Help Menu
help:
	@echo "Usage:"
	@echo "  make check                Run fast DC analyze/elaborate/link/check_design flow"
	@echo "  make syn                  Run synthesis with default top 'soc_top_v0' in '00_rv32i_basic'"
	@echo "  make syn MODULE_NAME=... DESIGN_TOP=... SDC_NAME=...  Run synthesis for a different module/top/SDC"
	@echo "  make clean                Remove all generated files and folders"
