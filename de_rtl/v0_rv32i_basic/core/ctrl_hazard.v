`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/17 15:57:20
// Design Name: 
// Module Name: ctrl_hazard
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

module ctrl_hazard(
    input  wire clk,
    input  wire rst_n,
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
    output wire [1:0] o_fwding_rs2_sel
    );

// ================================================================
// ----------------        Data Forwarding Ctrl        ---------------- //


// RAW with I-1 Instruction, which is at MAU now.
wire rs1_hzd_raw_mem = i_need_rs1_exu & i_wrbk_rdwen_mau & (i_rs1idx_exu == i_wrbk_rdidx_mau); // need_rd/rs sigs have already excluded the x0 situation. 
wire rs2_hzd_raw_mem = i_need_rs2_exu & i_wrbk_rdwen_mau & (i_rs2idx_exu == i_wrbk_rdidx_mau);

// RAW with I-2 Instruction, which is at WB now.
wire rs1_hzd_raw_wbu = i_need_rs1_exu & i_wrbk_rdwen_wbu & (i_rs1idx_exu == i_wrbk_rdidx_wbu); 
wire rs2_hzd_raw_wbu = i_need_rs2_exu & i_wrbk_rdwen_wbu & (i_rs2idx_exu == i_wrbk_rdidx_wbu);

assign o_fwding_rs1_sel = rs1_hzd_raw_wbu ? 2'b11 : 
                          rs1_hzd_raw_mem ? 2'b10 : 2'b00;
assign o_fwding_rs2_sel = rs2_hzd_raw_wbu ? 2'b11 : 
                          rs2_hzd_raw_mem ? 2'b10 : 2'b00;


endmodule
