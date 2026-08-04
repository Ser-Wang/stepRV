# RISCV_ARCH := rv32im
RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = coremark

# Previous fixed quick-run configuration (kept for reference):
# CFLAGS += -DCOREMARK_QUICK_RUN
# CFLAGS += -DTOTAL_DATA_SIZE=128	# for fast sim
# CFLAGS += -DITERATIONS=1 -DPERFORMANCE_RUN=1

# These values can be overridden on the make command line.
TOTAL_DATA_SIZE ?= 2000	# Total benchmark data size; official performance/validation runs require 2000 bytes.
ITERATIONS ?= 1300			# Benchmark loops: 500 for my_rv32i@50MHz, 750 for my_rv32im_phase1@50MHz, 1300 for my_rv32im_phase2@50MHz
RUN_TYPE ?= PERFORMANCE
# RUN_TYPE ?= PERFORMANCE	# Seed set: PERFORMANCE produces the score; VALIDATION separately checks official validation CRCs; PROFILE is for PGO.
QUICK_RUN ?= 0			# 1 skips the official >=10s validity check; set to 0 for a reportable performance run.
# Debug only: print completed iterations at this interval; 0 disables progress output.
PROGRESS_INTERVAL ?= 0

# Remove whitespace retained before inline comments or at line endings.
TOTAL_DATA_SIZE_VALUE := $(strip $(TOTAL_DATA_SIZE))
ITERATIONS_VALUE      := $(strip $(ITERATIONS))
RUN_TYPE_VALUE        := $(strip $(RUN_TYPE))
QUICK_RUN_VALUE       := $(strip $(QUICK_RUN))
PROGRESS_INTERVAL_VALUE := $(strip $(PROGRESS_INTERVAL))

COREMARK_FLAGS := -O2 -fno-common -funroll-loops -finline-functions --param max-inline-insns-auto=20 -falign-functions=4 -falign-jumps=4 -falign-loops=4

# CFLAGS += -DSIMULATION
# Use the selected dataset size and iteration count.
CFLAGS += -DTOTAL_DATA_SIZE=$(TOTAL_DATA_SIZE_VALUE)
CFLAGS += $(COREMARK_FLAGS)
CFLAGS += -DFLAGS_STR=\""$(COREMARK_FLAGS)"\"
CFLAGS += -DITERATIONS=$(ITERATIONS_VALUE)

# Select the official performance, validation, or profile seed set.
ifeq ($(RUN_TYPE_VALUE),PERFORMANCE)
CFLAGS += -DPERFORMANCE_RUN=1
else ifeq ($(RUN_TYPE_VALUE),VALIDATION)
CFLAGS += -DVALIDATION_RUN=1
else ifeq ($(RUN_TYPE_VALUE),PROFILE)
CFLAGS += -DPROFILE_RUN=1
else
ifeq ($(filter clean clean_all,$(MAKECMDGOALS)),)
$(error RUN_TYPE must be PERFORMANCE, VALIDATION, or PROFILE)
endif
endif

# Quick runs skip CoreMark's minimum 10-second validity check.
ifeq ($(QUICK_RUN_VALUE),1)
CFLAGS += -DCOREMARK_QUICK_RUN
endif
# Progress printing occurs inside the timed benchmark and invalidates scores.
ifneq ($(PROGRESS_INTERVAL_VALUE),0)
CFLAGS += -DCOREMARK_PROGRESS_INTERVAL=$(PROGRESS_INTERVAL_VALUE)
endif

C_SRCS := \
	core_main.c \
	core_list_join.c \
	core_matrix.c \
	core_state.c \
	core_util.c \
	core_portme.c \


COMMON_DIR = ../common
TOOLCHAIN_DIR = ../../..
include ../common/common.mk
