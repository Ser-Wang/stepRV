# biRISCV 项目分析报告

## 1. 取指时 reset 地址如何配置？

在取指时，reset（复位）地址是通过模块的输入端口和参数进行配置的。

在 `src/top/riscv_tcm_top.v` 中，定义了一个名为 `BOOT_VECTOR` 的参数，默认值为 `32'h00000000`：

```verilog
parameter BOOT_VECTOR = 32'h00000000;
```

随后，这个参数被赋值给 `boot_vector_w` 信号，并作为核心（`riscv_core`）的 `.reset_vector_i` 端口输入：

```verilog
wire  [ 31:0]  boot_vector_w = BOOT_VECTOR;
// ...
    ,.reset_vector_i(boot_vector_w)
```

**结论**：你可以通过在例化顶层模块（如 `riscv_tcm_top` 或 `riscv_top`）时重写 `BOOT_VECTOR` 这个 parameter，或者在顶层直接修改该值，来配置 CPU 启动和复位时的第一条指令获取地址。

## 2. 它的 dmem 是 SRAM 那种同步时序吗？

**是的，它的内存（包括 TCM 数据内存）是标准的同步 SRAM 时序。**

在 `src/tcm/tcm_mem_ram.v` 模块中实现了真实的 RAM 推断。这块双端口 RAM（Dual Port RAM）的读和写都是严格依赖于时钟上升沿的同步操作：

```verilog
// Synchronous write and read for port 0
always @ (posedge clk0_i)
begin
    if (wr0_i[0]) ram[addr0_i][7:0]   <= data0_i[7:0];
    if (wr0_i[1]) ram[addr0_i][15:8]  <= data0_i[15:8];
    // ... 其他字节写使能 ...
    
    ram_read0_q <= ram[addr0_i]; // 读取操作也被时钟寄存
end

assign data0_o = ram_read0_q;
```

**结论**：由上述代码可以看到，这是一种典型的 **同步写、同步读（Read First 模式，且存在一拍读延迟）** 的 SRAM 行为建模。这种写法会被综合工具标准地映射为 FPGA 的 Block RAM (BRAM) 或 ASIC 库中的同步 SRAM 宏单元。
