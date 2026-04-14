# 解决RAW数据冒险：流水线停顿（Stall）实现指南

## 1. 你的思路是否正确？
**你的思路是非常正确且标准的！**
在真正实现复杂的数据旁路（Data Forwarding / Bypassing）之前，首先通过流水线停顿（Pipeline Stall / Bubble）来解决RAW（Read-After-Write）数据冒险，是CPU设计学习中非常规范的第一步。这能帮你打下坚实的Hazard Detection基础，确保处理器逻辑的绝对正确，之后再加入Forwarding来优化性能（减少停顿带来的CPI损失）会水到渠成。

## 2. 流水线停顿的实现原理
产生RAW冒险的根本原因：ID阶段（译码阶段）正在解码的指令，其需要的源寄存器（`rs1`或`rs2`），恰好是后续EX、MEM、WB阶段中某条正在执行的指令的目的寄存器（`rd`），且那条指令还没把结果写回Register File。

要通过停顿解决这个问题，我们需要一个**冒险检测单元 (Hazard Detection Unit, HDU)**，它的工作机制如下：
1. **检测 (Detect)**：检查当前ID阶段指令的 `rs1` 和 `rs2`，是否与 EX、MEM、WB 阶段指令的 `rd` 冲突，并且对应阶段的写使能 (`wen`) 为有效（还要注意避开 `x0` 寄存器）。
2. **停顿 (Stall) & 冲刷 (Bubble)**：
   - **IF阶段**：冻结PC的值，不让它加4（停止取下一条指令）。
   - **ID阶段**：冻结IF/ID流水线寄存器，让当前遇到冒险的指令停留在ID阶段继续等待。
   - **EX阶段**：向ID/EX流水线寄存器插入一个“气泡”（Bubble / NOP）。最简单的办法是把流入EX阶段的写使能信号（`wen_ex`）等控制信号清零，这样EX阶段在下一拍就不会对系统状态产生任何影响。

---

## 3. 在你的代码中要如何实现（分步修改指南）

在你现有的工程中，我梳理了各个模块的连线，你需要按照以下步骤进行修改：

### 步聚一：在 [idu.v](file:///g:/myProjs/11_myRV/myProj_RV/1_rtl_current/core/idu.v) 中补全寄存器读取使能信号
在你的 [idu.v](file:///g:/myProjs/11_myRV/myProj_RV/1_rtl_current/core/idu.v) (Line 247-248)，`dec_info_need_rs1` 和 `dec_info_need_rs2` 仅声明了但没有赋值。HDU需要知道当前指令到底需不需要读源寄存器。你需要补全它们，并作为 output 引出：
```verilog
// 在idu.v 的端口列表中新增：
output wire o_dec_rs1_en,
output wire o_dec_rs2_en,

// 在内部逻辑中补全（简单示例，你需要根据具体指令群补充完整）：
// 例如：R型指令、I型指令、S型（Store）、B型（Branch）都需要读rs1。
assign dec_info_need_rs1 = dec_rv32i_arithm_type | dec_rv32i_arithm_imm_type | 
                           dec_rv32i_load_type | dec_rv32i_store_type | 
                           dec_rv32i_branch_type | dec_rv32i_jalr;

// R型、S型、B型需要读rs2。
assign dec_info_need_rs2 = dec_rv32i_arithm_type | dec_rv32i_store_type | 
                           dec_rv32i_branch_type;

assign o_dec_rs1_en = dec_info_need_rs1;
assign o_dec_rs2_en = dec_info_need_rs2;
```
*另外，给 [idu.v](file:///g:/myProjs/11_myRV/myProj_RV/1_rtl_current/core/idu.v) 增加 `i_stall` 输入端口，并修改其流水线寄存器（`r_instr_id` 和 `r_pc_id`）：*
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_instr_id <= 32'b0;
        r_pc_id <= 32'b0;
    end else if (!i_stall) begin // 如果没有stall，正常更新
        r_instr_id <= i_instr;
        r_pc_id <= i_pc_if;
    end
    // 如果有stall，保持原来的值不变
end
```

### 步骤二：在 [ifu.v](file:///g:/myProjs/11_myRV/myProj_RV/1_rtl_current/core/ifu.v) 中增加 Stall 端口并冻结PC
```verilog
// ifu.v 新增输入：
input wire i_stall,

// 修改PC更新逻辑：
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_r <= 32'd0;
    end
    else if (!i_stall) begin // 只有不在停顿状态才更新PC
        pc_r <= pc_next;
    end
end
```

### 步骤三：在 [exu.v](file:///g:/myProjs/11_myRV/myProj_RV/1_rtl_current/core/exu.v) 中增加 Bubble 端口产生气泡
流水线停顿意味着送入EX阶段的指令应该作废（变为NOP）。
```verilog
// exu.v 新增输入：
input wire i_ bubble, // 对应顶层的stall信号

// 修改 pipeline regs，比如 r_wrbk_wen_ex 和 r_dec_info_bus_ex
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_wen_ex <= 1'b0;
        r_dec_info_bus_ex <= 'b0;
    end else if (i_bubble) begin // 如果插入气泡，清零控制信号
        r_wrbk_wen_ex <= 1'b0;
        r_dec_info_bus_ex <= 'b0; // 相当于变成了一套不会写内存和寄存器的NOP指令
    end else begin
        r_wrbk_wen_ex <= i_dec_rdwen_id;
        r_dec_info_bus_ex <= i_dec_info_bus_id;
    end
end
```
*(注意对 [exu.v](file:///g:/myProjs/11_myRV/myProj_RV/1_rtl_current/core/exu.v) 里面其他的流水线寄存器 `r_wrbk_rdidx` 等做类似的复位逻辑也是好习惯，但最关键的是写使能 `wen` 和 控制总线清零)*

### 步骤四：在顶层模块 [core_rv32i_v0.v](file:///g:/myProjs/11_myRV/myProj_RV/1_rtl_current/core/core_rv32i_v0.v) 中例化 HDU (Hazard Detection Unit)
在顶层收集各阶段的寄存器地址和读写使能，进行判断：

```verilog
// 首先，接出idu新增的 o_dec_rs1_en 和 o_dec_rs2_en 信号
wire rs1_en;
wire rs2_en;

// --- Hazard Detection Unit (HDU) ---
// 检测是否与 EX 阶段有 RAW 冲突
wire stall_req_ex = (rs1_en && (rf_read_rs1_idx == wrbk_rdidx_ex) && wrbk_wen_ex && (rf_read_rs1_idx != 0)) ||
                    (rs2_en && (rf_read_rs2_idx == wrbk_rdidx_ex) && wrbk_wen_ex && (rf_read_rs2_idx != 0));

// 检测是否与 MEMA 阶段有 RAW 冲突
wire stall_req_mema = (rs1_en && (rf_read_rs1_idx == wrbk_rdidx_mema) && wrbk_rdwen_mema && (rf_read_rs1_idx != 0)) ||
                      (rs2_en && (rf_read_rs2_idx == wrbk_rdidx_mema) && wrbk_rdwen_mema && (rf_read_rs2_idx != 0));

// 检测是否与 WB 阶段有 RAW 冲突 (如果你的寄存器堆不支持内部前推，也需要停顿)
wire stall_req_wb = (rs1_en && (rf_read_rs1_idx == wrbk_rdidx_wb) && wrbk_rdwen_wb && (rf_read_rs1_idx != 0)) ||
                    (rs2_en && (rf_read_rs2_idx == wrbk_rdidx_wb) && wrbk_rdwen_wb && (rf_read_rs2_idx != 0));

// 综合stall信号
wire pipe_stall = stall_req_ex || stall_req_mema || stall_req_wb;

// 将 pipe_stall 接入到 ifu (作为 i_stall), idu (作为 i_stall), 以及 exu (作为 i_bubble) 的端口。
```

---

你可以先仔细阅读以上方案。如果思路清晰了，你可以尝试自己修改代码；**如果你希望我直接基于这个方案帮你修改工程代码，请告诉我“帮我修改”，我会自动执行代码替换！**
