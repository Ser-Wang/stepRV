# StepRV_v0 SoC 串口（UART）外设移植设计与集成规范

本规范旨在结合参考项目 `tinyriscv` 的外设设计，详细规划和分析将 `ref/rtl_tinyriscv/perips/uart.v` 串口外设移植并集成到您自己的 `00_rv32i_basic/de` 设计中（下文简称为 `StepRV_v0` SoC）的完整方案。

由于您的软件库及测试程序（如 `tests/programs/uart_tx`）已经为基地址 `0x3000_0000` 编写了驱动代码，本设计规范将从软硬件协同的角度，确保硬件集成与软件定义的**绝对兼容**。

---

## 1. 概述与设计目标

### 1.1 设计背景
在当前的 `StepRV_v0` 架构中，SoC 顶层 `soc_top_v0` 仅包含 CPU 核心、指令紧耦合存储器（ITCM）以及数据紧耦合存储器（DTCM）。为了支持软件调试信息的实时打印（如使用 `xprintf` 系列函数），需要集成一个硬件串口外设。

### 1.2 移植目标
*   **硬件移植**：以 `tinyriscv` 现有的 `uart.v` 为硬件核心，完成针对 `StepRV_v0` 项目的信号匹配与复位风格统一。
*   **总线集成**：在 `soc_bus_v0.sv` 译码总线中开辟独立的物理映射地址空间，确保 CPU LSU 访存指令可直接读写 UART 的内部寄存器。
*   **软硬件协同**：完美适配 `tests/programs/common/include/uart.h` 中定义的寄存器地址映射及驱动控制逻辑。
*   **仿真监控验证**：扩展现有测试平台（`dv/tb_soctop_userprog.sv`），实现对串口 `TX` 物理引脚输出的自动监控与文本解调打印。

---

## 2. 参考项目 UART 外设深度分析（tinyriscv）

结合 `tinyriscv_analysis_skill.md` 和 `ref/rtl_tinyriscv/perips/uart.v`，其 UART 的核心工作机制和集成方式如下：

### 2.1 硬件架构与寄存器映射
参考项目中的 `uart.v` 是一个标准的 8-N-1 串行收发器（默认波特率 115200bps @ 50MHz 时钟）。内部共实现了 5 个 32 位宽度的寄存器：

| 寄存器名称 | 地址偏移 (Offset) | 读写属性 (R/W) | 核心比特位 (Bit Definitions) | 硬件功能描述 |
| :--- | :--- | :--- | :--- | :--- |
| **UART_CTRL** | `0x00` | R/W | `bit[0]`: TX 使能<br>`bit[1]`: RX 使能 | 全局使能串口发送与接收模块。 |
| **UART_STATUS** | `0x04` | R/W | `bit[0]`: TX 忙标志 (RO)<br>`bit[1]`: RX 溢出/就绪标志 (RW) | 软件查询忙闲状态。写 `bit[1]=0` 清除接收完成状态。 |
| **UART_BAUD** | `0x08` | R/W | `bit[15:0]`: 波特率分频计数最大值 | 控制串行传输时钟频率。默认值为 `32'h1B8` (440)。 |
| **UART_TXDATA** | `0x0C` | WO | `bit[7:0]`: 待发送的字节数据 | 软件写入此寄存器可自动启动一次并转串 TX 传输。 |
| **UART_RXDATA** | `0x10` | RO | `bit[7:0]`: 已接收的字节数据 | 存储最近一次从串行总线成功接收到的字节数据。 |

### 2.2 串行收发状态机逻辑
*   **发送部分 (TX)**：使用经典的 `S_IDLE`、`S_START`、`S_SEND_BYTE`、`S_STOP` 4状态有限状态机。写入 `UART_TXDATA` 且 TX 使能时，硬件自动拉低 `tx_pin` 发送起始位，然后由低位（LSB）到高位（MSB）推入 8 位数据，最后拉高 `tx_pin` 输出停止位，并置 `tx_data_ready = 1` 恢复 `tx_busy` 状态。
*   **接收部分 (RX)**：通过双级 D 触发器检测 `rx_pin` 下降沿以捕捉起始位。开始接收后，计算半个波特率周期（`uart_baud[15:1]`）作为第一个采样点（处于起始位正中央），后续以完整波特率周期在每个数据位和停止位的正中央进行稳定采样，最大化抗干扰能力，接收完成后触发 `rx_over = 1`。

### 2.3 硬件挂载与总线（RIB）集成方式
*   **地址译码**：在 `tinyriscv_soc_top.v` 中，UART 挂载在内部 RIB 总线（`rib.v`）的 **`slave_3`** 端口上。
*   **基地址定位**：RIB 总线利用数据地址的高 4 位（`Addr[31:28]`）进行粗译码。
    ```verilog
    parameter [3:0] slave_3 = 4'b0011; // 对应 32'h3000_0000 至 32'h3FFF_FFFF 空间
    ```
    当主设备访问地址落入此空间时，`rib` 会自动拉高面向 UART 模块的 `s3_we_o` 信号。
*   **寄存器粗寻址**：由于 `uart.v` 仅监听 `addr_i[7:0]` 偏移寻址，因此任意高位为 `0x3` 且低 8 位符合偏移的请求都会被 UART 拦截响应，实现物理挂载。
*   **仲裁与挂起**：当有主设备（如 `uart_debug` 串口下载）请求独占总线时，RIB 总线仲裁器会生成 `hold_flag_o` 信号挂起（Stall）CPU 流水线。

---

## 3. 用户项目（StepRV_v0）架构与对比分析

### 3.1 用户项目当前架构
根据 `rv32i_basic_design_arch_spec.md`：
*   **流水线深度**：5 级在-order 流水线（IF -> ID -> EX -> MA -> WB）。
*   **数据访存端口**：在 EX/MA 阶段，通过 core 发出的 `o_mema_addr`、`o_mema_wren`、`o_mema_wr_mask` 和 `o_mema_wr_data` 接口直接访问 SoC 总线。
*   **总线译码器**：采用无仲裁的极简纯组合逻辑译码器 `soc_bus_v0.sv`。仅通过以下逻辑粗划分 ITCM 和 DTCM 空间：
    ```verilog
    wire sel_itcm = (i_mema_addr >= `ITCM_BASE) && (i_mema_addr < (`ITCM_BASE + `ITCM_SIZE));
    wire sel_dtcm = (i_mema_addr >= `DTCM_BASE) && (i_mema_addr < (`DTCM_BASE + `DTCM_SIZE));
    ```

### 3.2 架构 gap 与设计调整
1.  **时钟与复位**：
    *   `tinyriscv` 的复位信号命名为 `rst`，但实质为低电平复位。
    *   `StepRV_v0` 统一使用 `rst_n`（Active Low）。为了保持代码风格一致，移植时将 `uart` 的复位引脚更名为 `rst_n` 并统一使用 `~rst_n` 作为同步/异步复位条件。
2.  **数据写掩码（Write Mask）的处理**：
    *   `StepRV_v0` 的 LSU 输出带有 `mema_wr_mask` 字节掩码。
    *   而 `uart.v` 作为一个 32 位字对齐外设，读写均按 32 位整字进行。因此，在总线设计中我们**不将写掩码引入串口内部逻辑**，直接将总线译码得到的 `uart_wr_en` 接入串口模块即可。
3.  **地址空间的对齐**：
    *   软件定义基地址：`0x3000_0000`。
    *   配置调整：必须在 `config.v` 中加入 `UART_BASE = 32'h3000_0000`，使硬件译码段与软件定义完全契合。

---

## 4. 移植与集成详细设计方案

以下是具体的硬件集成实施细节：

### 4.1 目录结构规划
将移植后的外设文件和配置文件按如下目录存放：
*   📂 串口模块源文件：`00_rv32i_basic/de/periphs/uart.v`
*   📂 总线与顶层修改：`00_rv32i_basic/de/soc/soc_bus_v0.sv`，`00_rv32i_basic/de/soc/soc_top_v0.sv`
*   📂 全局配置修改：`00_rv32i_basic/de/defines/config.v`

---

### 4.2 具体模块修改规范

#### A. 配置定义扩展 (`00_rv32i_basic/de/defines/config.v`)
新增 UART 的基地址与空间大小宏定义（推荐大小分配为 4KB 以匹配通用对齐）：
```verilog
// ===========================================================================
// Memory Map & Peripherals Configuration
`define ITCM_BASE 32'h0000_0000
`define DTCM_BASE 32'h1000_0000
`define UART_BASE 32'h3000_0000  // 新增：UART 外设基物理地址

`define ITCM_SIZE 32'h0000_4000  // 16KB
`define DTCM_SIZE 32'h0000_4000  // 16KB
`define UART_SIZE 32'h0000_1000  // 新增：4KB 映射地址空间
```

#### B. 移植后 UART 核心引脚适配 (`00_rv32i_basic/de/periphs/uart.v`)
在移入文件时，对接口定义做极简化统一风格重命名：
```verilog
module uart(
    input wire clk,
    input wire rst_n,          // 风格统一：更名为 rst_n

    input wire we_i,
    input wire[31:0] addr_i,
    input wire[31:0] data_i,
    output reg[31:0] data_o,

    output wire tx_pin,
    input wire rx_pin
);
// 模块内部所有 checking： if (rst == 1'b0) 改为 if (rst_n == 1'b0) 或 if (~rst_n)
```

#### C. 总线接口与译码器升级 (`00_rv32i_basic/de/soc/soc_bus_v0.sv`)
升级总线译码器，暴露出对外设 UART 的互联通道：
```verilog
module soc_bus_v0 (
    // ... 原有接口保持不变 ...

    // 新增：UART 外设总线接口 (Read/Write)
    output wire [31:0] o_uart_addr,
    output wire        o_uart_wr_en,
    output wire [31:0] o_uart_wr_data,
    input  wire [31:0] i_uart_rd_data
);

// 地址解析：加入对 0x3000_0000 区域的拦截判断
wire sel_itcm = (i_mema_addr >= `ITCM_BASE) && (i_mema_addr < (`ITCM_BASE + `ITCM_SIZE));
wire sel_dtcm = (i_mema_addr >= `DTCM_BASE) && (i_mema_addr < (`DTCM_BASE + `DTCM_SIZE));
wire sel_uart = (i_mema_addr >= `UART_BASE) && (i_mema_addr < (`UART_BASE + `UART_SIZE)); // 新增

// 路由控制：输出信号分发
assign o_uart_addr    = i_mema_addr;
assign o_uart_wr_en   = i_mema_wren & sel_uart;  // 仅在写使能且地址匹配时拉高
assign o_uart_wr_data = i_mema_wr_data;

// ... ITCM 和 DTCM 的路由保持不变 ...

// 读数据总线多路复用扩展
assign o_mema_rd_data = sel_dtcm ? i_dtcm_rd_data :
                        sel_itcm ? i_itcm_rd_data :
                        sel_uart ? i_uart_rd_data : // 新增：将 UART 读数据汇入核心数据通路
                        32'b0;

endmodule
```

#### D. SoC 顶层实例化与物理连接 (`00_rv32i_basic/de/soc/soc_top_v0.sv`)
修改顶层模块，将 UART 的 TX 和 RX 导出为 SoC 物理引脚，供后续仿真平台抓取：
```verilog
module soc_top_v0(
    input wire clk,
    input wire rst_n,

    // 新增：顶层 SoC UART IO 引脚
    output wire o_uart_tx,
    input  wire i_uart_rx
    );

// ... 原有内部连线 ...

// 新增：UART 与总线之间的连接线
wire [31:0] uart_addr;
wire        uart_wr_en;
wire [31:0] uart_wr_data;
wire [31:0] uart_rd_data;

// 在 u_soc_bus 实例化中挂接这些信号
soc_bus_v0 u_soc_bus (
    // ... 挂载原有的 Core/ITCM/DTCM 信号 ...
    
    // 挂载新外设接口
    .o_uart_addr    (uart_addr    ),
    .o_uart_wr_en   (uart_wr_en   ),
    .o_uart_wr_data (uart_wr_data ),
    .i_uart_rd_data (uart_rd_data )
);

// 实例化移植过来的串口核心 IP
uart u_uart (
    .clk       (clk         ),
    .rst_n     (rst_n       ),
    .we_i      (uart_wr_en  ),
    .addr_i    (uart_addr   ),
    .data_i    (uart_wr_data),
    .data_o    (uart_rd_data),
    .tx_pin    (o_uart_tx   ),
    .rx_pin    (i_uart_rx   )
);

endmodule
```

---

## 5. 软件编程接口与驱动调用规范

在硬件设计通过以上方案落地后，软件层面的调用关系将获得“无缝对接”。

### 5.1 基础 C 语言驱动层工作机制
当 C 程序在 `StepRV_v0` 处理器上执行 `printf` 操作时，底层的寄存器级流转细节如下：

#### 1. 软件轮询发送数据
```c
void uart_putc(uint8_t c)
{
    // 1. 轮询读取物理地址 0x30000004。
    //    当 bit[0] (tx_busy) 为 1 时，代表上个字符还未串行发送完毕，CPU 在此原地自旋等待。
    while (UART0_REG(UART0_STATUS) & 0x01);
    
    // 2. 自旋结束后，将要发送的单字节字符写入物理发送寄存器 0x3000000C。
    //    硬件检测到写指令，自动拉高 tx_busy 并通过并转串移位输出到物理引脚 o_uart_tx。
    UART0_REG(UART0_TXDATA) = c;
}
```

#### 2. 软件轮询接收数据
```c
uint8_t uart_getc()
{
    // 1. 向物理地址 0x30000004 写入 0x00，手动复位 rx_over 接收标志。
    UART0_REG(UART0_STATUS) &= ~0x02;
    
    // 2. 自旋查询 rx_over，当它为 1 时说明 RXDATA 已锁存新数据。
    while (!(UART0_REG(UART0_STATUS) & 0x02));
    
    // 3. 读取物理寄存器 0x30000010 上的 8bit 接收缓存，并剥离高 24 位脏数据返回。
    return (UART0_REG(UART0_RXDATA) & 0xff);
}
```

---

## 6. 仿真与验证（Verification）方案

由于串行发送在硬件仿真中是非常“耗时”的操作（例如以默认分频 115200 波特率发送一个字节需要上千个系统时钟周期），我们需要在验证平台中同时提供**黑盒引脚解调监控**与**快速仿真技巧**。

### 6.1 验证平台引脚修改 (`dv/tb_soctop_userprog.sv`)
将 `tb_soctop_userprog` 中例化的被测系统接口引脚补充完整：
```verilog
// 信号申明
wire uart_tx;
reg  uart_rx;

// 实例化被测顶层
soc_top_v0 u_soc_top_v0(
    .clk       (clk),
    .rst_n     (rst_n),
    .o_uart_tx (uart_tx), // 连出发送物理通路
    .i_uart_rx (uart_rx)
);

initial begin
    uart_rx = 1'b1; // 闲置状态保持高电平
end
```

### 6.2 仿真自动化 UART 监控解调器（UART Monitor）
在验证平台（`dv`）中，可以使用 Verilog/SystemVerilog 编写一个虚拟的 UART 接收接收器。该监视器无需合成，可纯靠时延语法实时捕捉 `uart_tx` 电平，并直接在终端控制台以 `ASCII 文本` 形式输出打印，极大地方便调试：

```verilog
// 自动捕捉 UART 串行输出并解调为 ASCII 在仿真器窗口打印
initial begin : tb_uart_rx_monitor
    integer baud_cycle_cnt;
    reg [7:0] rx_char;
    integer i;
    
    // 等待复位释放
    @(posedge rst_n);
    $display("[UART Monitor] Monitoring UART TX Output...");
    
    forever begin
        // 1. 等待起始位：当物理 tx 发生 1 到 0 的下降沿转变
        @(negedge uart_tx);
        
        // 2. 获取硬件当前的波特率分频值 (从寄存器直接跨层层读取，规避写死波特率)
        //    每个 Bit 维持的时钟周期数 = 20ns (50MHz) * (uart_baud + 1)
        baud_cycle_cnt = u_soc_top_v0.u_uart.uart_baud[15:0];
        
        // 3. 延时到起始位的中点 (1.5个波特率周期处开始采集首个数据位)
        #(20 * (baud_cycle_cnt + 1) * 1.5);
        
        rx_char = 8'b0;
        // 4. 连续循环采样 8 个数据位的中点
        for (i = 0; i < 8; i = i + 1) begin
            rx_char[i] = uart_tx;
            #(20 * (baud_cycle_cnt + 1));
        end
        
        // 5. 采样结束，利用 $write 将解调出的 ASCII 实时打印到终端控制台
        $write("%c", rx_char);
        $fflush();
    end
end
```

### 6.3 仿真加速优化建议
为了在 RTL 级仿真中不必等待长时间的移位输出：
> [!TIP]
> **仿真加速策略**：
> 在软件初始化驱动 `uart_init()` 中，或者在 testbench 用 force/release 手段，将 `UART_BAUD` 寄存器的分频计数值强制设为极小值（例如写入 `2` 或 `3`）。
> 这样，原本需要数百个系统周期发送的 1 bit 将被压缩为只需 3 个时钟周期。上面的 `tb_uart_rx_monitor` 可以由于动态读取了底层的 `uart_baud` 值，从而自适应加速，完美实现秒级得到打印结果。

---

## 7. 总结与后续实施步骤

### 7.1 软硬件对应检查表

| 属性 | 软件定义 (`uart.h`) | 硬件设计规划 | 匹配验证状态 |
| :--- | :--- | :--- | :--- |
| **UART 基物理地址** | `0x30000000` | `` `UART_BASE`` 宏定义为 `32'h3000_0000` | 🟢 完美一致 |
| **控制寄存器寻址** | `0x30000000 + 0x0` | `uart.v` 中对偏移 `addr_i[7:0] == 8'h0` 进行写响应 | 🟢 完美一致 |
| **忙状态判断位** | 读 `STATUS` 并与 `0x01` 校验是否为忙 | 发送开始时 `uart_status[0] <= 1'b1`；发送结束自动变为 `0` | 🟢 完美一致 |
| **发送启动触发器** | 写入数据至 `0x3000000C` | `addr_i[7:0] == 8'hC` 时且 tx_en 开启，锁存数据开启发送 | 🟢 完美一致 |

### 7.2 后续实施计划
1.  **文件移入**：将 `ref/rtl_tinyriscv/perips/uart.v` 拷贝入 `00_rv32i_basic/de/periphs/`，重命名为风格一致的接口，修缮复位为 `rst_n`。
2.  **增加宏定义**：修改 `00_rv32i_basic/de/defines/config.v`，写入基地址和大小宏。
3.  **适配总线与顶层**：修改 `soc_bus_v0.sv` 和 `soc_top_v0.sv` 实现线路对接。
4.  **跑通仿真**：引入 `tb_soctop_userprog.sv`，在 testbench 级绑定解调 monitor，加载 `tests/programs/uart_tx` 固件直接进行仿真联调验证。
