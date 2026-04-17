# RV32I 基础五级流水线：数据冒险、停顿与冲刷机制实现指南

你好！作为你的IC设计辅助导师，我非常高兴能带你一起完善你的RISC-V核心。

通过阅读你的代码（`core_rv32i_v0.v`, `ifu.v`, `idu.v`, `exu.v`等），我发现你已经搭建好了一个非常扎实的五级流水线数据通路基础。目前的流水线寄存器是无条件打拍的（例如 `idu.v` 中的 `r_instr_id` 和 `exu.v` 中的 `rf_rs1_r_ex`）。

要解决**数据冒险（Data Hazards）**和**控制冒险（Control Hazards）**，我们需要引入**前递（Forwarding）**、**流水线停顿（Stalling/Interlocking）**和**流水线冲刷（Flushing）**三种机制。

你不希望我直接修改代码，所以这份指南将“手把手”教你如何修改各个模块。

---

## 整体架构新增：冒险控制单元 (Hazard Control Unit)

你需要新增一个模块，专门负责监听流水线各级的状态，并发出前递、停顿和冲刷信号。我们通常将它分为两部分（你也可以写在一起，叫做 `hazard_ctrl.v`）。

### 1. 前递单元 (Forwarding Unit)
**作用**：检测到后面的指令（EX, MEM, WB）正在计算我们需要的数据，且还没写回寄存器堆时，直接把数据“抄近道”送给当前 EX 阶段的 ALU。

**接口设计：**
```verilog
module forwarding_unit(
    // 监听 EX 阶段的操作数索引
    input wire [4:0] ex_rs1_idx,
    input wire [4:0] ex_rs2_idx,
    // 监听 MEM 阶段的写回信息
    input wire mem_reg_wen,
    input wire [4:0] mem_rd_idx,
    // 监听 WB 阶段的写回信息
    input wire wb_reg_wen,
    input wire [4:0] wb_rd_idx,

    // 输出给 EX 阶段的多路选择器信号
    output reg [1:0] forward_a, // 00: 来自寄存器, 01: 来自WB, 10: 来自MEM
    output reg [1:0] forward_b  // 00: 来自寄存器, 01: 来自WB, 10: 来自MEM
);
    // 判断逻辑示例：
    // 如果 MEM 阶段会写回，且 rd == rs1，且 rd != 0，则优先来自 MEM (10)
    // 否则如果 WB 阶段会写回，且 rd == rs1，且 rd != 0，则来自 WB (01)
    // 否则原样输出 (00)
    // (需要你自己用 assign/always 写出来)
endmodule
```

### 2. 冒险检测单元 (Hazard Detection Unit)
**作用**：处理 **Load-Use 冒险**。当上一条指令是 `Load`，且下一条指令马上要用它的结果时，前递是来不及的（Load结果在MEM阶段末尾出，而下一条指令的EX阶段马上要用）。此时必须**停顿（Stall）**一拍。

**接口设计：**
```verilog
module hazard_detect_unit(
    // 监听 ID 阶段的源操作数
    input wire [4:0] id_rs1_idx,
    input wire [4:0] id_rs2_idx,
    // 监听 EX 阶段（也就是上一条指令）是否是 Load
    input wire ex_is_load,    // 从 exu.v 中提取：r_dec_info_bus_ex[`DECINFO_LSU_LOAD]
    input wire [4:0] ex_rd_idx,

    // 输出控制信号
    output wire stall_if,     // 冻结 PC
    output wire stall_id_ex   // 清空 ID/EX 寄存器 (插入气泡)
);
    // 判断逻辑：
    // 如果 ex_is_load 且 (ex_rd_idx == id_rs1_idx || ex_rd_idx == id_rs2_idx)
    // 则说明发生了 Load-Use 冒险，拉高上述 stall 信号
endmodule
```

### 详细分析：在五级流水线中可能存在的 RAW 数据冒险
RAW（Read-After-Write）也就是“写后读”数据相关。在基础的单发射五级流水（IF-ID-EX-MEM-WB）中，当你打算在 EX 阶段读取操作数进行计算时，如果前面刚发射的指令还没把结果写回通用寄存器（Regfile 只有在 WB 阶段才写回），就会发生 RAW 冒险。

具体有以下几种典型场景以及对应模块到模块的解决路径：

#### 1. EX/MEM 级冒险 (ALU 紧跟 ALU)
*   **场景描述**：相邻的两条 ALU 算术逻辑指令。例如：
    ```assembly
    add x1, x2, x3   // 第1条指令，处于 MEM 阶段（结果已在EX算出）
    sub x4, x1, x5   // 第2条指令，紧跟其后，处于 EX 阶段（正需要 x1）
    ```
*   **如何解决**：通过前递 (Forwarding)。
*   **模块路径**：从 `mau.v` (或进入 `mau` 之前的寄存器) 将即将写入内存或往后传的经过 ALU 算完的 `wrbk_data` 提取出来，直接前递回 `exu.v` 的 ALU 输入多路选择器。

#### 2. MEM/WB 级冒险 (相隔一条指令的依赖)
*   **场景描述**：相隔一条指令的数据依赖。例如：
    ```assembly
    add x1, x2, x3   // 第1条指令，处于 WB 阶段（正准备写回到寄存器）
    and x8, x9, x10  // 第2条指令，处于 MEM 阶段（无相关，打酱油）
    sub x4, x1, x5   // 第3条指令，处于 EX 阶段（正需要 x1）
    ```
*   **如何解决**：通过前递 (Forwarding)。注意，这种情况下虽然 `add` 正在写 Regfile，但在时序上，`sub` 是在此时周期初去读 Regfile 的，很可能读到的是旧值（取决于你 Regfile 是否支持“内部旁路/Write-First”）。为保险起见，由前递单元统一拦截。
*   **模块路径**：从 `wbu.v` 模块将最终写回的数据 `wrbk_data_wbu` 提取出来，前递回 `exu.v` 的 ALU 输入多路选择器。*注意优先级：如果 MEM 阶段和 WB 阶段都有同一目标寄存器的数据，要优先取 MEM 阶段（更新的）数据。*

#### 3. Load-Use 冒险 (Load 紧跟使用)
*   **场景描述**：上一条是 Load 指令，下一条是要用 Load 出来的数据。
    ```assembly
    lw  x1, 0(x2)    // 第1条，在 EX 阶段计算内存地址，但数据要下周期 MEM 阶段才出来的
    add x3, x1, x4   // 第2条，紧跟其后，处于 ID/EX 边界（正需要 x1 进 EX 计算）
    ```
*   **如何解决**：前递救不了这个场景，因为相当于“向时间倒流”要数据。必须利用 Hazard Detection Unit 触发**流水线停顿**。将后面的指令在 ID 阶段卡住（Stall）一个周期，同时往 EX 阶段注入一个无效的指令气泡。停顿一拍后，这就演变成了上述的第 1 种“EX/MEM 级冒险”，可以通过前递解决。
*   **模块路径**：依赖检测信号从 `exu.v` (传出上一条指令是 load 及其 `rd_idx`) 传到 `hazard_ctrl.v`，然后 `hazard_ctrl.v` 发送停顿信号给 `ifu.v` 和 `idu.v`，发送冲刷/气泡信号给 `exu.v` 的控制输入端。

#### 4. 分支冒险隐含的数据相关 (Branch Hazard Data Dependency)
*   **场景描述**：遇到 `beq x1, x2, label` 这种条件分支时。在你的代码架构中，分支判定是在 `exu_bru.v`（EX阶段）完成的。这意味着判断跳转条件时，同样需要最新的 `x1` 和 `x2`。
*   **如何解决**：如果前面的指令正在修改 `x1` 或 `x2`，这也属于 RAW 数据冒险。
*   **模块路径**：幸运的是，因为你的分支判定在 EX 阶段，所以它其实**复用**了上述第 1 和第 2 种算术指令在 `exu.v` 中的前递逻辑路径。即直接把前递后的 `forwarded_rs1` 和 `forwarded_rs2` 从 `exu.v` 传给里头的 `exu_bru.v`。无需额外新建数据通路。

---

## 如何改造你现有的代码

为了让上述单位生效，你需要在现有的文件里做以下修改。

### 第一步：在 `core_rv32i_v0.v` 中连线
1. 例化 `forwarding_unit` 和 `hazard_detect_unit`。
2. 从各个模块中引出需要的线（比如 `ex_rs1_idx` 需要由 `idu` 传给 `exu`，因为你目前的 `exu.v` 里好像没有存 rs1_idx，只有 rs1_data）。
3. 增加 `flush` 信号。分支预测失败（或者无预测直接跳转时），需要冲刷流水线。这通常由 `exu_bru.v` 返回的 `o_jump_flag` 驱动，我们将它定义为 `flush_if_id`信号。

### 第二步：改造 `exu.v` 增加前递多路选择器
在 `exu.v` 中，你原本直接把 `rf_rs1_r_ex` 送给 ALU。现在需要给EX模块增加两个新的输入：`i_forward_mema_data` 和 `i_forward_wbu_data`，以及控制信号 `i_forward_a` 和 `i_forward_b`。

```verilog
// 改造前：
wire [`XWIDTH-1:0] alu_rs1 = {`XWIDTH{req_disp_alu}} & rf_rs1_r_ex;
// 改造后：
wire [31:0] forwarded_rs1 = (i_forward_a == 2'b10) ? i_forward_mema_data :
                            (i_forward_a == 2'b01) ? i_forward_wbu_data :
                                                     rf_rs1_r_ex;
wire [`XWIDTH-1:0] alu_rs1 = {`XWIDTH{req_disp_alu}} & forwarded_rs1;
```

### 第三步：改造 `ifu.v` 支持停顿 (Stall)
你要加一个 `i_stall` 输入信号。如果遇到 Load-Use 冒险，PC 不能增加。

```verilog
// 改造前：
pc_r <= pc_next;
// 改造后：
if (!i_stall) begin
    pc_r <= pc_next; // 也可以由 BRU 返回的分支地址做跳转选择 (i_jump_flag / i_jump_addr)
end
// 如果 i_stall == 1，pc_r 保持不变，代表重复取指
```

### 第四步：改造 `idu.v` 支持停顿 (Stall) 和冲刷 (Flush)
你的 `idu.v` 里面有 `r_instr_id` 和 `r_pc_id` 获取流水线内容。
1. 增加 `i_stall`：如果 `i_stall == 1`，寄存器内容需保持不变（冻结）。
2. 增加 `i_flush`：如果 `o_jump_flag` 为高（在 EX 阶段产生了分支跳转），我们要把刚刚在 IF 发起的取指和刚刚进入 ID 阶段的错指令废弃掉。这叫做**插入气泡 (Bubble)**。通常通过将指令替换为 `NOP` (如 RV32I 的 `addi x0, x0, 0` 即 `32'h0000_0013`) 或直接向下一级输出无效控制信号来实现。

```verilog
// 改造示例：
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_instr_id <= 32'h00000013; // 复位时塞入 NOP
    end else if (i_flush) begin
        r_instr_id <= 32'h00000013; // 分支跳错时，冲刷流水线，插入 NOP
    end else if (!i_stall) begin
        r_instr_id <= i_instr;      // 正常传递
    end
    // stall == 1 时不写，保持原值
end
```

### 第五步：改造 `exu.v` 寄存器组支持气泡 (Bubble)
当 Load-Use 发生时，IF 和 ID 阶段停顿，但 EX 阶段不能停，它需要执行一个假动作（气泡）。
你要给 `exu.v` 增加一个 `i_flush` 信号（当 `stall_id_ex` 有效时传进来）。
如果 `i_flush` 为 1，则在这一个周期内，将 `r_dec_info_bus_ex` 全部清零，或者将 `r_wrbk_wen_ex` 清零。这样 EX 阶段什么都不做，也不会写内存，也不会写寄存器。

---

## 你的下一步大作业 🚀

1.  在 `core` 目录下创建一个 `hazard_ctrl.v`。
2.  给 `idu.v` 的输出端口补充 `o_rs1_idx_id` 和 `o_rs2_idx_id` （以便往下传给 `exu.v`，从而给前递判断比对 `rd_idx`）。
3.  在 `exu.v` 中打拍锁存 `rs1_idx` 和 `rs2_idx`。
4.  根据我在前面给出的伪代码接口，尝试把线在 `core_rv32i_v0.v` 里都连起来。

遇到某个信号不知道怎么取，或者组合逻辑写起来有困惑，可以随时把代码对应的部分发给我，我们进一步讨论！祝你 debug 顺利！
