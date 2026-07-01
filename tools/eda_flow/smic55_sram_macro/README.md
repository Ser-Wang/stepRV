# SMIC55 SRAM Macro 使用说明

## 目录约定

工程 RTL 目录只保留设计代码和 wrapper，不存放 SRAM compiler 生成物：

```text
01_rv32i_sramtcm/de/periphs/sram_dtcm_1rw_wrapper.sv
01_rv32i_sramtcm/de/periphs/sram_itcm_1r1rw_wrapper.sv
```

SRAM macro 的生成物统一放在 PDK 区域：

```text
/home/moxiao/pdk/smic55/sram/generated/macros/
```

SRAM compiler 原始压缩包和解压后的工具也放在小写 `sram` 目录下：

```text
/home/moxiao/pdk/smic55/sram/S55NLLGSPH_CDK_V1.1.a.tar.gz
/home/moxiao/pdk/smic55/sram/S55NLLGDPH_CDK_V1.3.a.tar.gz
/home/moxiao/pdk/smic55/sram/compiler/
```

## 已生成的 Macro

SRAM macro 本身采用通用命名，不带 ITCM/DTCM 这类项目用途语义：

```text
/home/moxiao/pdk/smic55/sram/generated/macros/
  smic55_4096x32_1rw/
    rtl/
    lib/
    doc/
    report/
  smic55_8192x32_2p/
    rtl/
    lib/
    doc/
    report/
```

| Macro | Compiler | 容量 | 端口 | Mux | Bit write |
| --- | --- | --- | --- | --- | --- |
| `smic55_4096x32_1rw` | S55NLLGSPH | 4096 x 32 | 1RW | 16 | On |
| `smic55_8192x32_2p` | S55NLLGDPH | 8192 x 32 | dual-port | 16 | On |

当前生成的视图包括：

```text
smic55_4096x32_1rw/rtl/smic55_4096x32_1rw.v
smic55_4096x32_1rw/lib/smic55_4096x32_1rw_*.lib
smic55_4096x32_1rw/doc/smic55_4096x32_1rw.pdf

smic55_8192x32_2p/rtl/smic55_8192x32_2p.v
smic55_8192x32_2p/lib/smic55_8192x32_2p_*.lib
smic55_8192x32_2p/doc/smic55_8192x32_2p.pdf
```

## Wrapper 映射关系

工程侧 wrapper 保留用途语义，便于阅读 SoC 代码：

```text
sram_dtcm_1rw_wrapper
sram_itcm_1r1rw_wrapper
```

映射关系如下：

```text
mem_dtcm.sv
  -> sram_dtcm_1rw_wrapper
     -> smic55_4096x32_1rw

mem_itcm.sv
  -> sram_itcm_1r1rw_wrapper
     -> smic55_8192x32_2p
```

SMIC macro 控制信号为低有效：

```text
CEN  = 0 表示使能
WEN  = 0 表示写，1 表示读
BWEN = 0 表示对应 bit 可写
```

wrapper 会把工程内的 4-bit byte mask 展开成 SRAM macro 需要的 32-bit bit-write mask。

## 重新生成 SRAM Macro

主脚本放在 PDK 目录：

```bash
/home/moxiao/pdk/smic55/sram/scripts/gen_smic55_sram_macros.sh
```

项目工具目录中也保留了一份副本：

```bash
tools/eda_flow/smic55_sram_macro/scripts/gen_smic55_sram_macros.sh
```

执行：

```bash
/home/moxiao/pdk/smic55/sram/scripts/gen_smic55_sram_macros.sh
```

这个 Java compiler 即使命令行生成也需要 X display。WSL2 + VcXsrv 下可先设置：

```bash
export DISPLAY=$(awk '/nameserver/{print $2; exit}' /etc/resolv.conf):0.0
export LIBGL_ALWAYS_INDIRECT=1
```

## 仿真使用

共享仿真 flow 位于：

```text
/home/moxiao/work/my-RISCV-Projs/sim
```

普通 RTL memory：

```bash
make sim_isa test=add SRAM_IMPL=rtl
make sim_userprog name=simple SRAM_IMPL=rtl
```

SRAM macro model：

```bash
make sim_isa test=add SRAM_IMPL=macro
make sim_userprog name=simple SRAM_IMPL=macro
```

`SRAM_IMPL=macro` 会：

```text
1. 加入 +define+USE_SRAM_MACRO
2. 编译 PDK 目录下的 generated SRAM macro Verilog model
3. 为 VCS 加入 +notimingcheck
```

加 `+notimingcheck` 的原因是 SMIC dual-port SRAM model 在两个端口使用同源时钟时会刷大量 specify timing violation。功能仿真阶段这些 timing check 没有实际帮助，反而会污染日志。

testbench 中 `$readmemh` 的目标也随 `USE_SRAM_MACRO` 切换：

```text
RTL memory 模式：
  u_soc_top.u_imem.r_itcm
  u_soc_top.u_dmem.r_dtcm

SRAM macro 模式：
  u_soc_top.u_imem.u_itcm_sram_wrapper.u_smic55_8192x32_2p.mem_array
  u_soc_top.u_dmem.u_dtcm_sram_wrapper.u_smic55_4096x32_1rw.mem_array
```

SRAM macro 模式下 preload 前加了 `#1`，避免和 generated model 自己的 time-zero 初始化竞争。

## 综合使用

共享综合 flow 位于：

```text
/home/moxiao/work/my-RISCV-Projs/syn
```

普通 RTL memory：

```bash
make syn SRAM_IMPL=rtl
make check SRAM_IMPL=rtl
```

SRAM macro：

```bash
make syn SRAM_IMPL=macro
make check SRAM_IMPL=macro
```

综合模式下，DC 只 analyze 工程 wrapper，不 analyze generated SRAM behavioral Verilog。SRAM instance 通过 `.db` library cell 进行 link。

`SRAM_IMPL=macro` 需要 `syn/Makefile` 中 `SRAM_MACRO_DB_FILES` 指定的 `.db` 文件存在；否则 Makefile 会提前报错。

## `.lib` 与 `.db`

SRAM compiler 已生成 Liberty `.lib`。多数 Synopsys 综合 flow 更推荐先转成 `.db`，再放入 `target_library` 和 `link_library`。这样和当前 standard-cell `.db` 的使用方式一致，DC link 也更稳定。

批量转换脚本位于：

```bash
/home/moxiao/pdk/smic55/sram/generated/macros/convert_lib_to_db.sh
/home/moxiao/pdk/smic55/sram/generated/macros/convert_lib_to_db.tcl
```

执行：

```bash
/home/moxiao/pdk/smic55/sram/generated/macros/convert_lib_to_db.sh
```

单个 corner 的转换示例：

```tcl
read_lib /home/moxiao/pdk/smic55/sram/generated/macros/smic55_4096x32_1rw/lib/smic55_4096x32_1rw_ss_1.08_125.lib
write_lib smic55_4096x32_1rw_ss_1.08_125 -format db \
  -output /home/moxiao/pdk/smic55/sram/generated/macros/smic55_4096x32_1rw/lib/smic55_4096x32_1rw_ss_1.08_125.db
```

当前环境暂时没有可用 `lc_shell`。尝试用 `dc_shell-t` 转换时，工具提示 `read_lib` 依赖 Library Compiler 未安装或未启用。因此 `.db` 还没有在本机生成。等 Library Compiler 环境可用后，直接运行上面的转换脚本即可。

## 物理视图状态

当前 compiler 成功生成了：

```text
Verilog model
Liberty timing/power model
PDF datasheet
```

尝试直接生成 LEF/GDS/CDL 时，在 LEF 阶段遇到 compiler 内部异常：

```text
javax.crypto.BadPaddingException: Given final block not properly padded
```

因此，目前这套视图足够支持 RTL 仿真和 DC 逻辑综合接入准备；后续如果要做 APR/signoff，还需要解决或另行获取 LEF/GDS/CDL。
