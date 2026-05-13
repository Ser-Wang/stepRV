`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/04/17
// Design Name: StepRV_v0
// Module Name: ctrl_hazard
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module ctrl_hazard(
    input  wire clk,
    input  wire rst_n,
    // branch
    input  wire i_jump_flag,
    // for load-use hazard
    input  wire i_need_rs1_idu,
    input  wire i_need_rs2_idu,
    input  wire [`RFIDX_WIDTH-1:0] i_rs1idx_idu,
    input  wire [`RFIDX_WIDTH-1:0] i_rs2idx_idu,
    input  wire i_is_load_req_exu,
    input  wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_exu,
    // for forwarding
    input  wire i_need_rs1_exu,
    input  wire i_need_rs2_exu,
    input  wire [`RFIDX_WIDTH-1:0] i_rs1idx_exu,
    input  wire [`RFIDX_WIDTH-1:0] i_rs2idx_exu,
    input  wire i_wrbk_rdwen_mau,
    input  wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_mau,
    input  wire i_wrbk_rdwen_wbu,
    input  wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_wbu,
    output wire [1:0] o_fwding_rs1_sel,
    output wire [1:0] o_fwding_rs2_sel,
    // flush & stall
    output wire [4:0] o_stall,
    output wire [3:0] o_flush
    );

// ================================================================
// ----------------        Data Forwarding Ctrl        ---------------- //
// RAW with I-1 Instruction, which is at MAU now.
wire hzd_rs1_raw_mem = i_need_rs1_exu & i_wrbk_rdwen_mau & (i_rs1idx_exu == i_wrbk_rdidx_mau); // need_rd/rs sigs have already excluded the x0 situation. 
wire hzd_rs2_raw_mem = i_need_rs2_exu & i_wrbk_rdwen_mau & (i_rs2idx_exu == i_wrbk_rdidx_mau);

// RAW with I-2 Instruction, which is at WB now.
wire hzd_rs1_raw_wbu = i_need_rs1_exu & i_wrbk_rdwen_wbu & (i_rs1idx_exu == i_wrbk_rdidx_wbu); 
wire hzd_rs2_raw_wbu = i_need_rs2_exu & i_wrbk_rdwen_wbu & (i_rs2idx_exu == i_wrbk_rdidx_wbu);

assign o_fwding_rs1_sel = hzd_rs1_raw_mem ? 2'b10 : 
                          hzd_rs1_raw_wbu ? 2'b11 : 2'b00;
assign o_fwding_rs2_sel = hzd_rs2_raw_mem ? 2'b10 : 
                          hzd_rs2_raw_wbu ? 2'b11 : 2'b00;

// ----------------        Load-Use Hazard        ---------------- //
wire hzd_rs1_lduse = i_is_load_req_exu & i_need_rs1_idu & (i_wrbk_rdidx_exu == i_rs1idx_idu);
wire hzd_rs2_lduse = i_is_load_req_exu & i_need_rs2_idu & (i_wrbk_rdidx_exu == i_rs2idx_idu);
wire hzd_lduse_id = hzd_rs1_lduse | hzd_rs2_lduse;

wire stall_req_lduse_id = hzd_lduse_id;

// ================================================================
// ----------------        Stall & Flush        ---------------- //

// assign o_stall[`STALL_PC]     = stall_req_lduse_id;
// assign o_stall[`STALL_IF_ID]  = stall_req_lduse_id;
// assign o_stall[`STALL_ID_EX]  = 1'b0; // no stalling between id and ex.
// assign o_stall[`STALL_EX_MEM] = 1'b0;
// assign o_stall[`STALL_MEM_WB] = 1'b0;

// assign o_flush[`FLUSH_IF_ID]  = 1'b0;
// assign o_flush[`FLUSH_ID_EX]  = stall_req_lduse_id;
// assign o_flush[`FLUSH_EX_MEM] = 1'b0;
// assign o_flush[`FLUSH_MEM_WB] = 1'b0;

reg [4:0] stall;
reg [3:0] flush;
always @(*) begin
    if (i_jump_flag) begin
        stall = 5'b00000;
    end
    else if (stall_req_lduse_id) begin
        stall = 5'b00011;   // MEM_WB | EX_MEM | ID_EX | IF_ID | PC
    end
    else begin
        stall = 5'b00000;
    end
end

always @(*) begin
    if (i_jump_flag) begin
        flush = 4'b0011;    // MEM_WB | EX_MEM | ID_EX | IF_ID
    end
    else if (stall_req_lduse_id) begin
        flush = 4'b0010;
    end
    else begin
        flush = 4'b0000;
    end
end

assign o_stall = stall;
assign o_flush = flush;


endmodule
