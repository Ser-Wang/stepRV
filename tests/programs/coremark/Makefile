# RISCV_ARCH := rv32im
RISCV_ARCH := rv32i
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = coremark


COREMARK_FLAGS := -O2 -fno-common -funroll-loops -finline-functions --param max-inline-insns-auto=20 -falign-functions=4 -falign-jumps=4 -falign-loops=4

# CFLAGS += -DSIMULATION
CFLAGS += -DCOREMARK_QUICK_RUN
CFLAGS += -DTOTAL_DATA_SIZE=128	# for fast sim
CFLAGS += $(COREMARK_FLAGS)
CFLAGS += -DFLAGS_STR=\""$(COREMARK_FLAGS)"\"
CFLAGS += -DITERATIONS=1 -DPERFORMANCE_RUN=1

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
