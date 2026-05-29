# UART 集成审阅意见处理决议

## 文档信息

- 时间戳：2026-05-29 19:33:16 CST +0800
- 作者：Codex（GPT-5 coding model）
- 父任务：StepRV_v0 SoC UART TX 外设集成审阅与实施准备
- 文档类型：审阅意见处理决议与当前阶段实施边界
- 文档状态：已确认当前阶段决议，可作为下一步 coding 约束
- 上游引用：`uart_integration_spec.md`、`uart_integration_review_and_steps.md`
- 下游引用：`uart_tx_integration_coding_work_order.md` 将按本文边界指导下一步实现
- 执行状态：决议完成；下一步进入 UART TX 初步集成 coding

本文记录对 `uart_integration_review_and_steps.md` 的审阅反馈处理结果。条目编号沿用原文档第 2 节的问题编号，作为后续实施时的约束依据。

## 2.1 `soc_top_v0` 端口影响其他 testbench

审阅意见：

- `tb_soctop_isatest.sv` 完全不关心 UART，倾向于不处理、不修改例化。

处理决议：

- 当前 UART 集成只面向 `tb_soctop_userprog.sv` 和 `uart_tx` 用户程序验证。
- 若 `soc_top_v0` 顶层端口新增 `o_uart_tx/i_uart_rx`，理论上所有具名例化该模块的 testbench 都需要补端口连接，否则编译该 testbench 时会出现未连接端口警告或错误，具体取决于仿真器和编译选项。
- 本阶段不主动修改 `tb_soctop_isatest.sv`，除非后续实际编译该 testbench 时出现阻塞性错误。

实施约束：

- UART 初步实现与验证只改 `tb_soctop_userprog.sv`。
- 在 `tb_soctop_userprog.sv` 中明确增加 `uart_tx_monitor`，用于观察并打印 UART TX 串行输出。
- `tb_soctop_isatest.sv` 暂不作为本任务验收对象。
- 若后续需要跑 ISA testbench，再单独评估是否补 idle UART 连接。

## 2.2 filelist 或工程源文件管理

审阅意见：

- 暂不需要处理 filelist 生成问题，其他平台仿真时已有其他处理脚本。

处理决议：

- 本阶段不新增 filelist，不修改工程脚本，不引入新的仿真源文件管理方案。
- 实施时只新增/修改 RTL 和 testbench 文件，由现有外部脚本或平台机制负责收集 `de/periphs/uart.v`。

实施约束：

- 若后续仿真报 `module uart not found`，优先检查外部脚本是否包含 `de/periphs/uart.v`。
- 当前任务文档只把它列为环境检查点，不作为必须实施步骤。

## 2.5 `uart_tx` 软件不会主动结束仿真

审阅意见：

- `tb_soctop_userprog.sv` 已有超时停止机制，可以依赖该机制，但需要评估定时时长。

处理决议：

- 初步跑通阶段可以不新增 UART 字符串匹配 PASS 逻辑，也不修改 `uart_tx/main.c` 写 x26/x27。
- 当前 testbench watchdog 为：

```verilog
initial begin
    #1000000;
    $display("Simulation Time Out.");
    $finish;
end
```

- 时钟周期为 20ns，默认 UART baud 分频 `32'h1B8 = 440`。参考 UART TX 状态机每 bit 大约需要 `uart_baud + 1 = 441` 个周期，即约 `8820ns`。
- 发送 1 字节 8N1 约 10 bit，约 `88.2us`。
- `"hello world\n"` 共 12 字节，纯串行输出约 `1.0584ms`。
- 当前 watchdog `#1000000` 是 `1ms`，略短于完整打印 12 字节所需时间，还未计入 CPU 执行 `uart_init/xprintf/uart_putc` 的开销。

结论：

- 如果保持默认 baud 且依赖 timeout，当前 `1ms` 超时大概率偏短。
- 建议把 `tb_soctop_userprog.sv` 的 watchdog 调整到至少 `2ms`，更稳妥可设为 `5ms`：

```verilog
#5000000;
```

实施约束：

- 当前阶段不做自动 PASS 字符串匹配。
- 必须在 `tb_soctop_userprog.sv` 中增加 `uart_tx_monitor`，用于人工观察是否打印 `hello world`。
- watchdog 建议改为 `5ms`，避免完整 UART TX 尚未输出完就提前结束。

## 2.6 仿真加速与 `UART_BAUD`

审阅意见：

- 简便起见，先不做仿真加速，保持软件原样。
- 另起文档记录这个可能改进点，初步跑通后再考虑。

处理决议：

- 当前阶段不改 `tests/programs/common/lib/uart.c`。
- 不添加 `SIMULATION` 宏分支。
- 不在 testbench 中 force `u_uart.uart_baud`。
- 保持 RTL 默认 `BAUD_115200 = 32'h1B8`。

后续改进点记录：

- 可在初步跑通后考虑添加软件侧仿真加速：

```c
#ifdef SIMULATION
    UART0_REG(UART0_BAUD) = 3;
#endif
```

- 或者添加专用仿真 testbench 参数/plusarg 控制 baud，但这会引入额外实现复杂度。

实施约束：

- 当前任务验收以真实默认 baud 行为为准。
- 若仿真耗时不可接受，再开启单独优化任务。

## 2.8 UART 地址镜像

审阅意见：

- 先记录，不做更严谨改进。

处理决议：

- 保留 `uart.v` 内部 `addr_i[7:0]` 偏移解码。
- 接受 4KB UART 地址段内部每 256B 镜像一次的现象。
- 软件只使用标准偏移：

```text
0x00 CTRL
0x04 STATUS
0x08 BAUD
0x0c TXDATA
0x10 RXDATA
```

实施约束：

- 不把 UART 内部 offset 改成 `addr_i[11:0]`。
- 不添加非法偏移访问检查。

## 2.9 RX 验证范围

审阅意见：

- 当前任务只考虑 `uart_tx`，不考虑 `uart_rx` 的任何内容，除非存在依赖。

处理决议：

- 本阶段不写 RX sender task。
- 不验证 `uart_getc()`。
- 不验证 `UART_STATUS[1]`、`UART_RXDATA`。
- `i_uart_rx` 只需在 testbench 中保持 idle high，避免 RX 逻辑误触发。

实施约束：

- RTL 可保留 tinyriscv UART 的 RX 逻辑，因为 TX 模块接口中包含 `rx_pin`，移植时删除 RX 反而会扩大改动。
- 验收只关注 TXDATA 写入后 `o_uart_tx` 是否输出正确串行字符。

## 2.10 SVA 影响

审阅意见：

- 记录，作为检查项。

处理决议：

- 当前阶段不主动修改 `dv/sva_soc_bus.sv`。
- 若仿真启用了 SVA 且因为 UART 地址段导致断言失败，再根据失败信息补充 UART 例外。

检查项：

- 编译 `tb_soctop_userprog.sv` 时确认 bind 没有因 `soc_bus_v0` 端口或内部信号变化报错。
- 运行时若访问 `0x3000_0000` 触发 bus 相关 assertion，需要检查 SVA 是否假设只有 ITCM/DTCM。

## 当前阶段最终实施边界

本阶段只做 UART TX 初步跑通：

- 移植 `uart.v`。
- 增加 `UART_BASE/UART_SIZE`。
- 扩展 `soc_bus_v0` 的 UART decode 和读写通路。
- 在 `soc_top_v0` 实例化 UART。
- 只修改 `tb_soctop_userprog.sv` 接 UART TX/RX，其中 RX idle high。
- 在 `tb_soctop_userprog.sv` 中增加 `uart_tx_monitor`，用于观察 UART TX 输出。
- 建议把 watchdog 从 `1ms` 调整到 `5ms`。

本阶段明确不做：

- 不处理 filelist/工程脚本。
- 不做仿真 baud 加速。
- 不新增 RX 验证。
- 不主动修改 `tb_soctop_isatest.sv`。
- 不强化 UART 地址偏移解码。
- 不主动修改 SVA，除非实际报错。
