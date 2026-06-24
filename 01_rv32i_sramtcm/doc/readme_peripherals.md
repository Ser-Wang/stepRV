# 外设说明

本文档记录 `00_rv32i_basic` 当前接入的 MMIO 外设。

## UART

UART 已在 `soc_top_v0` 中接入，基地址和窗口大小由 `de/defines/config.v` 定义：

```text
UART_BASE = 0x3000_0000
UART_SIZE = 0x0000_1000
```

当前 UART 保证 32-bit MMIO 访问。寄存器偏移如下：

| 偏移 | 寄存器 | 说明 |
| --- | --- | --- |
| `0x00` | `CTRL` | bit0 使能 TX，bit1 使能 RX |
| `0x04` | `STATUS` | bit0 表示 TX busy，bit1 表示 RX over |
| `0x08` | `BAUD` | 波特率分频配置，复位默认 115200 对应分频 |
| `0x0C` | `TXDATA` | 写入低 8 bit 触发发送 |
| `0x10` | `RXDATA` | 读取接收数据低 8 bit |

写 `TXDATA` 时，如果 TX 已使能且当前不 busy，则低 8 bit 会进入发送逻辑，并置位 `STATUS[0]`。接收侧使能后，接收完成时数据写入 `RXDATA[7:0]`，并置位 `STATUS[1]`。
