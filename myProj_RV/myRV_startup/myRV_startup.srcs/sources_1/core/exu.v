`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/11 18:57:41
// Design Name: 
// Module Name: exu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "../defines/config.v"

module exu(
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_rf_rs1_data,
    input wire [31:0] i_rf_rs2_data,
    input wire [31:0] i_dec_imm,
    input wire [`DECINFO_BUS_ALU_WIDTH-1:0] i_dec_info_bus_id,
    output wire [31:0] o_wbck_data_ex,
    input wire [31:0] i_pc_id,
    // pass by
    input wire [`RFIDX_WIDTH-1:0] i_dec_rdidx_id,
    input wire i_dec_rdwen_id,
    output wire [`RFIDX_WIDTH-1:0] o_wbck_rdidx_ex,
    output wire o_wbck_wen_ex
    );

// ================================================================
// ----------------        Pipeline Regs        ---------------- //
// to wb
reg [`RFIDX_WIDTH-1:0] r_wbck_rdidx_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wbck_rdidx_ex <= 'd0;
    end
    else begin
        r_wbck_rdidx_ex <= i_dec_rdidx_id;
    end
end
assign o_wbck_rdidx_ex = r_wbck_rdidx_ex;

reg r_wbck_wen_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wbck_wen_ex <= 1'b0;
    end
    else begin
        r_wbck_wen_ex <= i_dec_rdwen_id;
    end
end
assign o_wbck_wen_ex = r_wbck_wen_ex;


// Comb in, reg 
reg [31:0] rf_rs1_r_ex, rf_rs2_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rf_rs1_r_ex <= 32'd0;
        rf_rs2_r_ex <= 32'd0;
    end
    else begin
        rf_rs1_r_ex <= i_rf_rs1_data;
        rf_rs2_r_ex <= i_rf_rs2_data;
    end
end

reg [31:0] dec_imm_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dec_imm_r_ex <= 32'd0;
    end
    else begin
        dec_imm_r_ex <= i_dec_imm;
    end
end

reg [31:0] pc_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_r_ex <= 32'b0;
    end
    else begin
        pc_r_ex <= i_pc_id;
    end
end

reg [`DECINFO_BUS_ALU_WIDTH-1:0] r_dec_info_bus_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_dec_info_bus_ex <= {`DECINFO_BUS_ALU_WIDTH{1'b0}};
    end
    else begin
        r_dec_info_bus_ex <= i_dec_info_bus_id;
    end
end



// ================================================================
// ----------------        Pipeline Regs        ---------------- //

wire [31:0] alu_req_op1, alu_req_op2;

wire [`DECINFO_BUS_ALU_WIDTH-1:0] dec_info_bus_alu;

wire [31:0] alu_req_result;

// ---- op1 and op2
assign alu_req_op1 = (dec_info_bus_alu[`DECINFO_ALU_OP1PC]) ? pc_r_ex : rf_rs1_r_ex;
assign alu_req_op2 = (dec_info_bus_alu[`DECINFO_ALU_OP2IMM]) ? dec_imm_r_ex : rf_rs2_r_ex;

// ---- dec_info_bus dispatch
assign dec_info_bus_alu = r_dec_info_bus_ex;


// ---- results wrbk
assign o_wbck_data_ex = alu_req_result;


// ----------------        Instantiations        ---------------- //
exu_alu u_exu_alu(
    .clk                (clk        ),
    .rst_n              (rst_n      ),
    .i_alu_req_op1      (alu_req_op1),
    .i_alu_req_op2      (alu_req_op2),
    .i_dec_info_bus_alu (dec_info_bus_alu),
    .o_alu_req_result   (alu_req_result)
    );




    

endmodule
