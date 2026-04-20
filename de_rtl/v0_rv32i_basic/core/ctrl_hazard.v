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
    input  wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_exu,
    input  wire i_wrbk_rdwen_exu,
    input  wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_mau,
    input  wire i_wrbk_rdwen_mau,
    input  wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_wbu,
    input  wire i_wrbk_rdwen_wbu,
    output wire [1:0] o_fwd_datasel_1,
    output wire [1:0] o_fwd_datasel_2
    );

// ================================================================
// ----------------        Data Forwarding Ctrl        ---------------- //




endmodule
