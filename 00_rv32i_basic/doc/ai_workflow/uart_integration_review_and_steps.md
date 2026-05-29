# UART 集成规格审阅与修订执行步骤

## 文档信息

- 时间戳：2026-05-29 19:33:16 CST +0800
- 作者：Codex（GPT-5 coding model）
- 父任务：StepRV_v0 SoC UART TX 外设集成审阅与实施准备
- 文档类型：规格审阅与修订执行建议
- 文档状态：已完成初版审阅；具体实施边界以后续决议文档为准
- 上游引用：`uart_integration_spec.md`
- 下游引用：`uart_integration_review_resolution.md` 对本文部分建议进行了取舍和收敛；
           `uart_tx_integration_coding_work_order.md` 将作为下一步 coding 输入
- 执行状态：审阅完成，等待按决议文档进入 RTL/testbench coding

本文用于审阅 `uart_integration_spec.md` 中的执行计划，指出当前计划里可能存在的漏洞、不清晰之处，并给出一版更贴合当前仓库状态的实施步骤。

审阅范围：

- `00_rv32i_basic/doc/ai_workflow/uart_integration_spec.md`
- `00_rv32i_basic/de/defines/config.v`
- `00_rv32i_basic/de/soc/soc_bus_v0.sv`
- `00_rv32i_basic/de/soc/soc_top_v0.sv`
- `00_rv32i_basic/dv/tb_soctop_userprog.sv`
- `00_rv32i_basic/dv/uart_tx_map.sv`
- `tests/programs/common/include/uart.h`
- `tests/programs/common/lib/uart.c`
- `tests/programs/uart_tx/main.c`
- `ref/rtl_tinyriscv/perips/uart.v`

## 1. 总体结论

原规格的大方向是可执行的：把 `tinyriscv` 的 `uart.v` 移入 `de/periphs`，在 `soc_bus_v0` 增加 `0x3000_0000` 地址段，在 `soc_top_v0` 实例化 UART，并在 `tb_soctop_userprog` 中通过 TX 引脚解码输出字符。

但是原计划还不够“施工级”。主要缺口集中在：编译源文件清单、现有 testbench 状态、仿真 monitor 的时序写法、UART TX 默认空闲电平、软件退出/判定方式、字节写访问兼容性、以及与现有其他 testbench 的接口变化兼容。

## 2. 发现的问题与建议

### 2.1 `soc_top_v0` 增加端口会影响多个 testbench

原计划只提到修改 `tb_soctop_userprog.sv`，但仓库中还有 `tb_soctop_isatest.sv` 等测试平台直接例化了 `soc_top_v0`。如果 `soc_top_v0` 顶层新增必连端口：

```verilog
output wire o_uart_tx,
input  wire i_uart_rx
```

则所有例化点都需要同步更新，否则仿真编译会报端口连接错误。

建议：

- `tb_soctop_userprog.sv` 接出 `uart_tx`、驱动 `uart_rx = 1'b1`，并加入 monitor。
- `tb_soctop_isatest.sv` 等暂不关心 UART 的 testbench 也要补连接，可用 `wire unused_uart_tx; wire uart_rx = 1'b1;`。
- 如果希望减少影响，也可以把 UART 端口放在 `soc_top_v0` 端口列表末尾，并在所有 testbench 中用具名端口连接，避免位置连接风险。

### 2.2 原计划没有覆盖仿真/综合源文件列表

当前 `00_rv32i_basic` 目录内没有明显的 filelist、Makefile 或 Vivado 工程脚本。新增 `de/periphs/uart.v` 后，仿真或综合工程必须显式把该文件加入编译列表，否则顶层实例化 `uart` 后会出现 module not found。

建议在执行步骤中加入：

- 查明当前使用的仿真命令或 Vivado 工程源文件管理方式。
- 将 `de/periphs/uart.v` 加入工程源文件。
- 若之后建立脚本化 flow，建议补一个固定 filelist，避免依赖 GUI 状态。

### 2.3 `uart.v` 复位说明基本正确，但 TX 复位空闲电平值得调整

参考 `tinyriscv` 的 `uart.v` 在 TX always block 复位时：

```verilog
tx_reg <= 1'b0;
```

但 UART 物理线空闲态应为高电平。该实现会在复位期间让 TX 为低，复位释放后才回到 idle 高电平。如果 monitor 在复位前后直接监听 `negedge uart_tx`，可能误判或带来波形上的假起始位。

建议移植时将复位态改成：

```verilog
tx_reg <= 1'b1;
```

并让 testbench monitor 在 `@(posedge rst_n)` 之后延迟至少一个时钟再开始监听。

### 2.4 原 monitor 的 `#(20 * ... * 1.5)` 写法不够稳妥

原计划中 monitor 使用：

```verilog
#(20 * (baud_cycle_cnt + 1) * 1.5);
```

在不同仿真器里，integer 与 real 混合 delay 可能有兼容性差异。更稳妥的写法是用整数 delay：

```verilog
localparam integer CLK_PERIOD_NS = 20;
bit_period_ns = CLK_PERIOD_NS * (baud_cycle_cnt + 1);
#(bit_period_ns + bit_period_ns / 2);
```

同时建议不要跨层读取不存在或被改名后的信号。若移植后内部寄存器仍命名为 `uart_baud`，可继续读取 `u_soc_top_v0.u_uart.uart_baud[15:0]`；如果改名，需要同步修改 monitor。

### 2.5 `uart_tx` 软件不会主动结束仿真，现有 x26/x27 检查可能卡住

`tests/programs/uart_tx/main.c` 当前逻辑为：

```c
uart_init();
xprintf("hello world\n");
while (1);
```

而 `tb_soctop_userprog.sv` 默认启用 `CHECK_X26_X27`，会等待 `x26 == 1` 后判定通过。`uart_tx` 程序不一定会设置 x26/x27，因此仿真很可能只能等 watchdog timeout。

建议二选一：

- 为 UART 专用 testbench 增加 monitor 字符串匹配逻辑，收到 `"hello world\n"` 后 `$finish` 并报告 PASS。
- 或修改 `uart_tx/main.c`，在打印完成后写入 x26/x27 作为用户程序通过标志。

为了不污染软件程序语义，推荐优先采用 testbench monitor 字符串匹配。

### 2.6 原计划未明确 `uart_init()` 不写 `UART_BAUD`

`tests/programs/common/lib/uart.c` 的 `uart_init()` 只写：

```c
UART0_REG(UART0_CTRL) = 0x3;
```

它不设置 `UART0_BAUD`。因此 RTL 默认 `BAUD_115200 = 32'h1B8` 就是软件能否正常输出的关键。移植时不要误删或改变默认值。

如果要做仿真加速，有两个更清晰的选项：

- 在软件里用 `#ifdef SIMULATION` 写 `UART_BAUD = 3`，但需要重新编译程序。
- 在 testbench 中复位释放后、软件访问 UART 前 force `u_soc_top_v0.u_uart.uart_baud = 16'd3`，但这会依赖内部层级名。

考虑可维护性，建议后续给 `uart_init()` 增加可选 `SIMULATION` 分支，而不是长期依赖 force 内部寄存器。

### 2.7 字节写兼容性需要确认，不建议完全忽略写掩码

原计划说 UART 不引入写掩码，直接按 32 位整字处理。当前 `uart.c` 用的是 `volatile uint32_t *`，会生成 32 位 load/store，短期可行。

但函数签名 `uart_putc(uint8_t c)` 可能让读者误以为软件会字节写 TXDATA。若后续有人改成 `volatile uint8_t *`，当前 UART 总线接口没有写掩码语义，会在地址偏移和数据 lane 上产生兼容性问题。

建议在文档和代码注释里明确第一版约束：

- UART MMIO 仅保证 32-bit word 访问。
- 软件驱动必须通过 `UART0_REG(addr)` 的 `uint32_t` 指针访问。
- 暂不支持 `sb/sh` 到 UART 寄存器；如果要支持，需要在 bus 或 UART 内部按 `i_mema_wr_mask` 和地址低位重排写数据。

### 2.8 地址偏移使用 `addr_i[7:0]` 可行，但需要说明镜像范围

`uart.v` 只解码 `addr_i[7:0]`，而 bus 计划给 UART 分配 4KB 空间。这意味着 `0x3000_0000`、`0x3000_0100`、`0x3000_0200` 等地址会在 UART 内部镜像到相同寄存器偏移。

短期不是功能 bug，但需要在文档中说明：

- bus 负责限制 `0x3000_0000` 到 `0x3000_0fff`。
- UART 内部只使用低 8 位，因此 4KB 空间内每 256B 镜像一次。
- 软件只使用 `0x00/0x04/0x08/0x0c/0x10` 标准偏移。

若希望更严谨，可把 UART 内部 offset 改成 `addr_i[11:0]` 并只响应 `12'h000` 等寄存器地址。

### 2.9 RX 路径第一版可以接入但未验证

原计划同时描述 TX 和 RX，但当前用户程序只验证 TX。`uart_getc()` 会清 `STATUS[1]` 并轮询 RX ready，真实 RX 还需要 testbench 产生 8N1 串行输入。

建议把执行验收分两层：

- 第一阶段只要求 TX 打印 `"hello world\n"`。
- 第二阶段再写 RX loopback 或 testbench UART sender 验证 `uart_getc()`。

### 2.10 SVA 可能需要同步更新

`dv/sva_soc_bus.sv` 当前 bind 到 `soc_bus_v0`，观察 `sel_itcm`、`mema_addr_bus` 等内部信号。新增 `sel_uart` 后，已有断言可能仍能编译，但地址 decode 相关断言若假设 only ITCM/DTCM，需要补 UART 例外。

建议执行时至少跑一次带 SVA 的非 IVERILOG 仿真，若断言失败，再把 UART 地址段加入允许范围。

## 3. 修订后的清晰操作步骤

### Step 0：确认目标和验收标准

第一阶段只集成 UART TX，验收标准如下：

- 软件 `tests/programs/uart_tx` 可访问 `0x3000_0000` UART MMIO。
- `uart_init()` 写 `UART_CTRL = 0x3` 后，`xprintf("hello world\n")` 可触发 TXDATA 写入。
- testbench monitor 从 `o_uart_tx` 解码并打印 `hello world`。
- 仿真能够自动 PASS/finish，不能只依赖 watchdog timeout。

RX 验证作为第二阶段，不阻塞第一阶段合入。

### Step 1：移植 UART RTL

新增文件：

```text
00_rv32i_basic/de/periphs/uart.v
```

从 `ref/rtl_tinyriscv/perips/uart.v` 拷贝后做最小修改：

- 端口 `rst` 改为 `rst_n`。
- 所有 `if (rst == 1'b0)` 改为 `if (rst_n == 1'b0)`。
- TX 复位空闲态建议改为 `tx_reg <= 1'b1`。
- 保留 `BAUD_115200 = 32'h1B8`，因为当前 `uart_init()` 不写 baud。
- 保留寄存器偏移 `0x00/0x04/0x08/0x0c/0x10`。
- 明确第一版只保证 32-bit MMIO 访问。

### Step 2：增加地址宏

修改：

```text
00_rv32i_basic/de/defines/config.v
```

在 memory map 区域加入：

```verilog
`define UART_BASE 32'h3000_0000
`define UART_SIZE 32'h0000_1000
```

注意不要改变现有 `ITCM_BASE/DTCM_BASE` 和 size，避免影响现有软件链接脚本与测试。

### Step 3：扩展 `soc_bus_v0`

修改：

```text
00_rv32i_basic/de/soc/soc_bus_v0.sv
```

新增 UART 端口：

```verilog
output wire [31:0] o_uart_addr,
output wire        o_uart_wr_en,
output wire [31:0] o_uart_wr_data,
input  wire [31:0] i_uart_rd_data
```

新增 decode：

```verilog
wire sel_uart = (i_mema_addr >= `UART_BASE) &&
                (i_mema_addr < (`UART_BASE + `UART_SIZE));
```

新增 route：

```verilog
assign o_uart_addr    = i_mema_addr;
assign o_uart_wr_en   = i_mema_wren & sel_uart;
assign o_uart_wr_data = i_mema_wr_data;
```

扩展 read mux：

```verilog
assign o_mema_rd_data = sel_dtcm ? i_dtcm_rd_data :
                        sel_itcm ? i_itcm_rd_data :
                        sel_uart ? i_uart_rd_data :
                        32'b0;
```

建议同时补一条注释：UART 第一版不消费 `i_mema_wr_mask`，软件需使用 32-bit MMIO。

### Step 4：扩展 `soc_top_v0`

修改：

```text
00_rv32i_basic/de/soc/soc_top_v0.sv
```

顶层端口新增：

```verilog
output wire o_uart_tx,
input  wire i_uart_rx
```

新增总线到 UART 的内部连线：

```verilog
wire [31:0] uart_addr;
wire        uart_wr_en;
wire [31:0] uart_wr_data;
wire [31:0] uart_rd_data;
```

在 `u_soc_bus` 例化中连接 UART 端口，并实例化：

```verilog
uart u_uart (
    .clk       (clk),
    .rst_n     (rst_n),
    .we_i      (uart_wr_en),
    .addr_i    (uart_addr),
    .data_i    (uart_wr_data),
    .data_o    (uart_rd_data),
    .tx_pin    (o_uart_tx),
    .rx_pin    (i_uart_rx)
);
```

### Step 5：同步所有 testbench 的 `soc_top_v0` 例化

至少修改：

```text
00_rv32i_basic/dv/tb_soctop_userprog.sv
00_rv32i_basic/dv/tb_soctop_isatest.sv
```

在 `tb_soctop_userprog.sv` 中：

```verilog
wire uart_tx;
reg  uart_rx;

soc_top_v0 u_soc_top_v0(
    .clk       (clk),
    .rst_n     (rst_n),
    .o_uart_tx (uart_tx),
    .i_uart_rx (uart_rx)
);

initial begin
    uart_rx = 1'b1;
end
```

在其他暂不使用 UART 的 testbench 中，也要给 `i_uart_rx` 接 idle high，`o_uart_tx` 接 unused wire。

### Step 6：加入 UART TX monitor 和自动 PASS 条件

在 `tb_soctop_userprog.sv` 增加 UART monitor。建议使用整数 delay，避免 real delay：

```verilog
localparam integer CLK_PERIOD_NS = 20;

initial begin : tb_uart_tx_monitor
    integer baud_cycle_cnt;
    integer bit_period_ns;
    integer i;
    reg [7:0] rx_char;
    string uart_text;

    uart_text = "";
    @(posedge rst_n);
    repeat (2) @(posedge clk);

    forever begin
        @(negedge uart_tx);
        baud_cycle_cnt = u_soc_top_v0.u_uart.uart_baud[15:0];
        bit_period_ns = CLK_PERIOD_NS * (baud_cycle_cnt + 1);

        #(bit_period_ns + bit_period_ns / 2);
        rx_char = 8'h00;

        for (i = 0; i < 8; i = i + 1) begin
            rx_char[i] = uart_tx;
            #(bit_period_ns);
        end

        $write("%c", rx_char);
        uart_text = {uart_text, rx_char};

        if (uart_text.len() >= 12 &&
            uart_text.substr(uart_text.len() - 12, uart_text.len() - 1) == "hello world\n") begin
            report_result(1, "UART_TX");
            $finish;
        end
    end
end
```

如果目标仿真器不完整支持 SystemVerilog `string.substr()`，则改用固定长度 shift buffer：

```verilog
reg [8*12-1:0] uart_last12;
uart_last12 = {uart_last12[8*11-1:0], rx_char};
if (uart_last12 == "hello world\n") begin
    report_result(1, "UART_TX");
    $finish;
end
```

同时对 UART 测试建议关闭或绕开默认 `CHECK_X26_X27`，否则它可能等待不到 x26/x27。

### Step 7：加入 `uart.v` 到工程/仿真源文件

根据实际 flow 做其中一种：

- Vivado GUI：把 `00_rv32i_basic/de/periphs/uart.v` 加入 Design Sources。
- 脚本化仿真：把 `de/periphs/uart.v` 加入 filelist 或编译命令。
- 如果还没有统一 filelist，建议补一个最小 filelist，把 `defines` include path、core、periphs、soc、dv 文件固定下来。

这是原计划遗漏但实际必需的一步。

### Step 8：编译并修复端口/SVA 编译问题

编译时重点看：

- `uart` module 是否找得到。
- 所有 `soc_top_v0` 例化是否已经补齐 UART 端口。
- `sva_soc_bus` 是否因新增 decode 或信号路径变化报错。
- `config.v` include path 是否仍然有效。

### Step 9：运行 UART TX 用户程序

准备 `tests/programs/uart_tx` 的 instruction data 后，用 `tb_soctop_userprog.sv` 加载运行。

期望现象：

- PC monitor 进入 `uart_init`、`xprintf`、`uart_putc`。
- UART monitor 打印：

```text
hello world
```

- testbench 自动报告 `UART_TX [PASS]` 并 `$finish`。

### Step 10：第二阶段再验证 RX

TX 通过后，再新增 RX 验证：

- 在 testbench 中写一个 UART sender task，向 `uart_rx` 发送 8N1 字符。
- 软件侧调用 `uart_getc()` 读取字符。
- 检查 `UART_STATUS[1]` 置位、`UART_RXDATA[7:0]` 等于发送字符。
- 检查写 `UART_STATUS &= ~0x2` 后 RX ready 被清除。

## 4. 推荐审阅决策点

在真正改 RTL 前，建议先确认以下 4 个决策：

1. 第一阶段是否只要求 TX 打印通过，RX 放到第二阶段。
2. 是否接受 `soc_top_v0` 新增 UART 物理端口，并同步更新所有 testbench。
3. 是否接受 UART 第一版只支持 32-bit MMIO，不支持 byte/halfword 写寄存器。
4. 仿真加速采用软件 `SIMULATION` 分支写 baud，还是暂时保持默认 `32'h1B8` 跑完整 115200 分频。

我的建议是：第一阶段保持 RTL 简单，先不做 byte lane 支持；默认 baud 不动，先跑通真实 115200 行为。如果仿真速度不可接受，再加 `SIMULATION` 分支写小 baud。
