# RISCV_ARCH := rv32im
RISCV_ARCH := rv32i
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = coremark_lite


COREMARK_FLAGS := -Os -fno-common

# CFLAGS += -DSIMULATION
CFLAGS += -DCOREMARK_LITE
CFLAGS += -DTOTAL_DATA_SIZE=128
CFLAGS += $(COREMARK_FLAGS)
CFLAGS += -DFLAGS_STR=\""$(COREMARK_FLAGS)"\"
CFLAGS += -DITERATIONS=1 -DPERFORMANCE_RUN=1

C_SRCS := \
	core_main.c \
	core_list_join.c \
	core_util.c \
	core_portme.c \


COMMON_DIR = ../common
TOOLCHAIN_DIR = ../../..
include ../common/common.mk
