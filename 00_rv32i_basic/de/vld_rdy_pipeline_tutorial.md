# Risc-V 5级流水线停顿与冲刷改造指南 (Valid/Ready握手版)

本指南旨在手把手指导您重构 `./de_rtl/v0_rv32i_basic` 中的代码，引入**Valid/Ready握手机制**和**分布式冲刷（Flush）机制**。这样不仅解决了当前的停顿/冲刷问题，还可以为您将来平滑切换到“乱序执行(OOO)”和“高级分支预测”打下坚实的基础。

---

## 1. 原理速览

流水级间的交互原则请牢记两句话：
*   **Valid (vld, 下发)**：上一级大喊，“我的数据算好啦，它是有效的，你可以拿走！”
*   **Ready (rdy, 接收)**：下一级大喊，“我这会不忙，如果数据做好了你就直接塞给我！”

当且仅当两者在同一个时钟上升沿**同时为 1** 时，数据正式被传递（这个动作叫 Handshake，握手完成）。

**冲刷（Flush）的作用机制：**
当我们在某个周期发现之前预取的指令是错的（比如分支预测失败），我们就发出全局或者局部 `flush` 脉冲。所有被波及的流水线打拍寄存器，遇到 `flush` 为 1，就毫不犹豫地**把它们内部承载的 `valid` 信号拉低为 0**（也就是变成一个不产生任何副作用的气泡/Bubble）。

---

## 2. 第一步：编写一个通用的流水线级间寄存器模块

流水线不应该直接把 `idu.v` 的输出连到 `exu.v` 内部组合逻辑去锁存。标准的做法是所有模块内部都只做组合逻辑和局部状态，**级与级之间完全通过专用寄存器模块隔开**。

请在您的核心目录（如 `./de_rtl/v0_rv32i_basic/core/`）新建一个 `pipe_reg_slice.v` 文件，模板如下，以后所有的级间打拍都例化这个模块：

```verilog
`timescale 1ns / 1ps

// 流水线级间握手寄存器模块
module pipe_reg_slice #(
    parameter DATA_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,

    // Flush - 用于分支预测失败等情况下的冲刷
    input  wire i_flush,

    // 上一级 (Master) 来的信号
    input  wire i_vld,
    output wire o_rdy,
    input  wire [DATA_WIDTH-1:0] i_data,

    // 去往下一级 (Slave) 的信号
    output wire o_vld,
    input  wire i_rdy,
    output wire [DATA_WIDTH-1:0] o_data
);

    // 内部寄存器堆
    reg [DATA_WIDTH-1:0] data_r;
    reg                  vld_r;

    // 当本身为空（vld_r == 0），或者下一级准备好接收去腾出空间了（i_rdy == 1）时，
    // 当前级才对外显示“Ready”，允许上一级写入
    assign o_rdy = (~vld_r) | i_rdy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vld_r  <= 1'b0;
            data_r <= {DATA_WIDTH{1'b0}};
        end 
        else if (i_flush) begin
            // 收到全局冲刷请求时，直接拉低有效位，就地气泡化，数据值无需真清空
            vld_r  <= 1'b0;
        end 
        else if (i_vld && o_rdy) begin
            // 握手成功：如果上一级有效且本级能收，就把数据打入本级寄存器
            vld_r  <= 1'b1;
            data_r <= i_data;
        end
        else if (i_rdy) begin
            // 当这拍没有新数据进来，但老数据被下一级成功取走时，把自己腾空
            vld_r  <= 1'b0;
        end
    end

    // 输出赋值
    assign o_vld  = vld_r;
    assign o_data = data_r;

endmodule
```

---

## 3. 第二步：改造各模块的输入输出接口

此时您的每个计算模块（如 `ifu.v`, `idu.v`, `exu.v`）就变成了纯粹的吞吐单元。

拿出 `idu.v` 举例，将其接口修改成带握手的（请在您代码里对应修改）：

```verilog
module idu(
    // 时钟和复位不需要说
    input wire clk,
    input wire rst_n,
    
    //-----------------
    // [接收] 来自 IF 的数据
    //-----------------
    input  wire        i_if_vld,    // IF段告诉IDU数据好了
    output wire        o_if_rdy,    // IDU告诉IF段自己有空
    input  wire [31:0] i_instr,
    input  wire [31:0] i_pc_if,
    
    //-----------------
    // [发送] 发往 downstream EX 的数据
    //-----------------
    output wire        o_id_vld,    // IDU告诉EX自己算完了
    input  wire        i_id_rdy,    // EX告诉IDU自己有空接单

    // 以下是原来的数据线，打包成往外发出的数据
    output wire [`RFIDX_WIDTH-1:0] o_dec_rs1idx,
    // ... 其他老接口保留
);

// 核心控制逻辑示例：
// 1. 本模块内部能够进行有效动作的前提是：输入有效 (i_if_vld)
// 2. 本模块能发出新数据的前提是：自身内部不卡顿
// 3. 握手绑定映射
assign o_if_rdy = i_id_rdy; // 这是一个非常简单的透明传递，表示如果下一级（EXU）不堵，我（IDU）就不堵。如果中间有很复杂的运算，就不能直接连。
assign o_id_vld = i_if_vld; // 取决于 IDU 本身这周期是否能跑完翻译任务，纯组合逻辑可以直连
```

> **注意：** 像 IFU 比较特殊，它的上方就是 PC。只要前端没人堵它 (`o_if_rdy` == 1 从 `ifu_idu_reg` 传来)，它就每个周期去 ROM 抓数据并抛出 `o_vld=1`。如果碰到 Cache Miss，它只要拉低 `o_vld`，后续流水线就会自动出现气泡等待。

---

## 4. 第三步：在核心顶层 `core_rv32i_v0.v` 中“接下水管”

现在需要把那些散装的 `ifu.v`, `idu.v`, `exu.v` 等等用新建的 `pipe_reg_slice` 隔开。在顶层的结构看起来长得很均匀：

```verilog
//============ [第一段管线] IF -> IF_ID_REG ============
ifu u_ifu(
    // ...
    .o_vld  (if_vld_out),
    .i_rdy  (if_rdy_in),
    .o_pc_if(pc_if_out)
    // 注意：假设取指等数据都被打包装入 if_data_out [63:0]
);

wire id_vld_in;
wire id_rdy_out;
wire [63:0] id_data_in;

pipe_reg_slice #( .DATA_WIDTH(64) ) u_if_id_reg (
    .clk    (clk),
    .rst_n  (rst_n),
    .i_flush(br_flush), // 这里接来自 EXU 分支预测失败的 flush
    
    .i_vld  (if_vld_out),
    .o_rdy  (if_rdy_in), 
    .i_data (if_data_out),  // PC和指令等拼在一起：{pc_if_out, instr_if_out}

    .o_vld  (id_vld_in),
    .i_rdy  (id_rdy_out),
    .o_data (id_data_in)    // 输出到下面的 IDU
);

//============ [第二段管线] ID_REG -> IDU ============
idu u_idu(
    // ...
    .i_if_vld (id_vld_in),
    .o_if_rdy (id_rdy_out),
    .i_pc_if  (id_data_in[63:32]), // 解包
    .i_instr  (id_data_in[31:0]),  // 解包
    // ...
    .o_id_vld (id_vld_out),
    .i_id_rdy (id_rdy_in)
    // 数据线拼装成 id_data_out 去下一个阶段
);

// ... 同理例化 u_id_ex_reg, u_exu, u_ex_ma_reg...
```

---

## 5. 第四步：实战演练 - 分支跳转/异常引起的 Flush （冲刷）

比方说在 **EXU (执行阶段)**，执行引擎在运算后终于知道了该不该跳（或者原本预判不跳，结果现在发现必须要跳）。

此时您可以在 `exu.v` 增加两个输出引脚：
```verilog
output wire        o_branch_mispredict, // 当真实跳转方向与原预取不符时拉高 1 个周期
output wire [31:0] o_branch_target      // 正确的新 PC
```

然后在 `core_rv32i_v0.v` 里把脉冲接起来：
1. **把 `br_mispredict` 连到 `IF_ID` 和 `ID_EX` 两个管线寄存器的 `i_flush` 上。**
   -> 一旦拉高，这两个寄存器内部的 `vld_r` 瞬间归零，它们携带的错误指令全部变成气泡。
2. **把 `branch_target` 接到前端 IFU 的特殊跳转控制接口上。** 
   -> IFU 获取新跳转地址，抛弃原来的顺序 PC，从新地址开始吐出数据。

## 学习总结

改造的核心思路是把原本“通过时钟上升沿强行推着数据走”变成“**只有 Valid 亮了才代表有活干，只有 Ready 亮了才代表敢交差**”。

您可以试着从 `ifu.v` 和 `idu.v` 这最基本的两级入手手打一下，只要第一截水管（`u_if_id_reg`）跑通了且没有丢失时钟节拍，后面的 3 级改造不过是简单的复制粘贴了！一旦这项改造完成，遇到任何由于内存慢、除法器慢引起的停顿，只需把对应模块的 `Valid` 暂缓给出或者把 `Ready` 拉低即可，不用再满代码加判断！
