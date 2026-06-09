
# [Win] gnu-mcu-eclipse riscv-none-embed toolchain (Windows only)
# RISCV_PATH := $(TOOLCHAIN_DIR)/tools/gnu-mcu-eclipse-riscv-none-gcc-8.2.0-2.2-20190521-0004-win64/
# [Win] riscv-none-embed-* (Windows toolchain prefix)
# RISCV_GCC     := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-gcc)
# RISCV_AS      := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-as)
# RISCV_GXX     := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-g++)
# RISCV_OBJDUMP := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-objdump)
# RISCV_GDB     := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-gdb)
# RISCV_AR      := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-ar)
# RISCV_OBJCOPY := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-objcopy)
# RISCV_READELF := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-readelf)


# [Linux] SiFive riscv64-unknown-elf toolchain
RISCV_PATH := $(TOOLCHAIN_DIR)/tools/riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14/
# [Linux] riscv64-unknown-elf-* (Linux toolchain prefix)
RISCV_GCC     := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-gcc)
RISCV_AS      := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-as)
RISCV_GXX     := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-g++)
RISCV_OBJDUMP := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-objdump)
RISCV_GDB     := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-gdb)
RISCV_AR      := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-ar)
RISCV_OBJCOPY := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-objcopy)
RISCV_READELF := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-readelf)

PYTHON ?= python3
TOOLS_SCRIPT_DIR := $(abspath $(TOOLCHAIN_DIR)/tools/scripts)
BIN_TO_MEM_SCRIPT := $(TOOLS_SCRIPT_DIR)/BinToMem_CLI.py
RENAME_REGS_SCRIPT := $(TOOLS_SCRIPT_DIR)/rename_regs.py

.PHONY: all data rename
all: $(TARGET)

data: $(TARGET)
	$(PYTHON) $(BIN_TO_MEM_SCRIPT) $(TARGET).bin $(TARGET).data

rename: $(TARGET)
	$(PYTHON) $(RENAME_REGS_SCRIPT) $(TARGET).dump $(TARGET).dump.rename

ASM_SRCS += $(COMMON_DIR)/start.S
ASM_SRCS += $(COMMON_DIR)/trap_entry.S
C_SRCS += $(COMMON_DIR)/init.c
C_SRCS += $(COMMON_DIR)/trap_handler.c
C_SRCS += $(COMMON_DIR)/lib/utils.c
C_SRCS += $(COMMON_DIR)/lib/xprintf.c
C_SRCS += $(COMMON_DIR)/lib/uart.c
# C_SRCS += $(COMMON_DIR)/lib/flash_n25q.c
# C_SRCS += $(COMMON_DIR)/lib/spi.c

LINKER_SCRIPT := $(COMMON_DIR)/link.lds

INCLUDES += -I$(COMMON_DIR)/include -I$(COMMON_DIR)

LDFLAGS += -T $(LINKER_SCRIPT) -nostartfiles -Wl,--gc-sections -Wl,--check-sections

ASM_OBJS := $(ASM_SRCS:.S=.o)
C_OBJS := $(C_SRCS:.c=.o)

LINK_OBJS += $(ASM_OBJS) $(C_OBJS)
LINK_DEPS += $(LINKER_SCRIPT)

CLEAN_OBJS += $(TARGET) $(LINK_OBJS)
CLEAN_OUTPUTS += $(TARGET).bin $(TARGET).dump
CLEAN_OUTPUTS += $(TARGET).data $(TARGET).dump.rename

CFLAGS += -march=$(RISCV_ARCH)
CFLAGS += -mabi=$(RISCV_ABI)
CFLAGS += -mcmodel=$(RISCV_MCMODEL) -ffunction-sections -fdata-sections -fno-builtin-printf -fno-builtin-malloc

$(TARGET): $(LINK_OBJS) $(LINK_DEPS) Makefile
	$(RISCV_GCC) $(CFLAGS) $(INCLUDES) $(LINK_OBJS) -o $@ $(LDFLAGS)
	$(RISCV_OBJCOPY) -O binary $@ $@.bin
	$(RISCV_OBJDUMP) --disassemble-all $@ > $@.dump

$(ASM_OBJS): %.o: %.S
	$(RISCV_GCC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

$(C_OBJS): %.o: %.c
	$(RISCV_GCC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

.PHONY: clean clean_all
clean:
	rm -f $(CLEAN_OBJS)

clean_all: clean
	rm -f $(CLEAN_OUTPUTS)
