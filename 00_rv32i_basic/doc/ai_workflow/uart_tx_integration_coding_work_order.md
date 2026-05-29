# UART TX 集成 Coding 工单

## 文档信息

- 时间戳：2026-05-29 19:33:16 CST +0800
- 作者：Codex（GPT-5 coding model）
- 父任务：StepRV_v0 SoC UART TX 外设集成
- 文档类型：coding 工单与实施约束
- 文档状态：已执行，待外部仿真验证
- 上游引用：`uart_integration_spec.md`、`uart_integration_review_and_steps.md`、`uart_integration_review_resolution.md`
- 下游引用：后续 RTL/testbench 修改记录与仿真结果
- 执行状态：coding 已完成；当前环境缺少 HDL 仿真/编译工具，需在外部仿真平台验证

## 1. 任务目标

在 `00_rv32i_basic` 中完成 UART TX 初步集成，使 `tests/programs/uart_tx` 通过 MMIO 写 `0x3000_0000` UART 寄存器后，能从 `soc_top_v0.o_uart_tx` 输出串行字符，并由 `tb_soctop_userprog.sv` 中的 `uart_tx_monitor` 观察打印。

本阶段只追求 TX 初步跑通，不做 UART RX 验证。

## 2. 必改文件

- `00_rv32i_basic/de/defines/config.v`
- `00_rv32i_basic/de/soc/soc_bus_v0.sv`
- `00_rv32i_basic/de/soc/soc_top_v0.sv`
- `00_rv32i_basic/dv/tb_soctop_userprog.sv`

## 3. 新增文件

- `00_rv32i_basic/de/periphs/uart.v`

来源：

- 从 `ref/rtl_tinyriscv/perips/uart.v` 移植。

## 4. 明确不做

- 不修改 `tests/programs/common/lib/uart.c`。
- 不修改 `tests/programs/uart_tx/main.c`。
- 不新增或修改 filelist、Vivado 工程脚本、仿真脚本。
- 不主动修改 `tb_soctop_isatest.sv`。
- 不做 baud 仿真加速。
- 不做 RX sender task。
- 不验证 `uart_getc()`、`UART_STATUS[1]`、`UART_RXDATA`。
- 不强化 UART 内部地址解码，保留 `addr_i[7:0]` 偏移解码。
- 不主动修改 SVA，除非实际编译或运行报错。

## 5. 实施步骤

### Step 1：移植 UART RTL

新增 `de/periphs/uart.v`：

- 从 `ref/rtl_tinyriscv/perips/uart.v` 拷贝。
- 端口 `rst` 改为 `rst_n`。
- 所有复位判断改为 `if (rst_n == 1'b0)`。
- TX 复位空闲态建议改为 `tx_reg <= 1'b1`。
- 保留 `BAUD_115200 = 32'h1B8`。
- 保留寄存器偏移 `0x00/0x04/0x08/0x0c/0x10`。

### Step 2：增加 UART 地址宏

在 `de/defines/config.v` 的 memory map 区域加入：

```verilog
`define UART_BASE 32'h3000_0000
`define UART_SIZE 32'h0000_1000
```

不要改变现有 `ITCM_BASE/DTCM_BASE` 和 size。

### Step 3：扩展 `soc_bus_v0`

在 `de/soc/soc_bus_v0.sv` 中：

- 新增 UART 总线端口：`o_uart_addr`、`o_uart_wr_en`、`o_uart_wr_data`、`i_uart_rd_data`。
- 增加 `sel_uart`，范围为 `` `UART_BASE`` 到 `` `UART_BASE + `UART_SIZE``。
- 写通路：`o_uart_wr_en = i_mema_wren & sel_uart`。
- 读通路 mux 增加 `sel_uart ? i_uart_rd_data`。
- 注释说明第一版 UART MMIO 只保证 32-bit word 访问。

### Step 4：扩展 `soc_top_v0`

在 `de/soc/soc_top_v0.sv` 中：

- 顶层新增 `output wire o_uart_tx`、`input wire i_uart_rx`。
- 增加 bus 到 UART 的内部连线。
- 在 `u_soc_bus` 中连接 UART 端口。
- 实例化 `uart u_uart`，连接 `clk/rst_n/we_i/addr_i/data_i/data_o/tx_pin/rx_pin`。

### Step 5：修改 `tb_soctop_userprog.sv`

在 `dv/tb_soctop_userprog.sv` 中：

- 声明 `wire uart_tx; reg uart_rx;`。
- 例化 `soc_top_v0` 时连接 `.o_uart_tx(uart_tx)` 和 `.i_uart_rx(uart_rx)`。
- `initial` 中设置 `uart_rx = 1'b1`。
- 增加 `uart_tx_monitor`，用于观察并打印 UART TX 输出。
- 将 watchdog 从 `#1000000` 调整为 `#5000000`。

`uart_tx_monitor` 要求：

- 等待 `rst_n` 释放后再监听 `uart_tx`。
- 使用 `u_soc_top_v0.u_uart.uart_baud[15:0]` 获取当前 baud 分频。
- 使用整数 delay 计算 bit 周期，避免 real delay。
- 解码 8N1，低位先采样。
- 用 `$write("%c", rx_char);` 打印字符。
- 本阶段不要求自动 PASS，不做字符串匹配 `$finish`。

## 6. 验收标准

- RTL 编译时不出现 UART 相关语法错误。
- `tb_soctop_userprog.sv` 可例化带 UART 端口的 `soc_top_v0`。
- `uart_tx_monitor` 在仿真控制台可观察到 `hello world` 输出。
- watchdog 不早于完整 UART TX 输出前结束，建议使用 `5ms`。

## 7. 风险与检查项

- 如果仿真报 `module uart not found`，检查外部脚本是否纳入 `de/periphs/uart.v`，本工单不处理脚本。
- 如果启用 SVA 后访问 `0x3000_0000` 触发断言，检查 `sva_soc_bus.sv` 是否隐含 only ITCM/DTCM 假设。
- 如果后续需要运行 `tb_soctop_isatest.sv`，再单独评估是否补接 UART 端口。
- 如果仿真耗时不可接受，再另开任务考虑 `UART_BAUD` 仿真加速。
