`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/27 01:13:41
// Design Name: 
// Module Name: exu_lsu
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

module exu_lsu(
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_lsu_rs1,
    input wire [31:0] i_lsu_rs2,
    input wire [31:0] i_lsu_imm,
    input wire [`DECINFO_BUS_LSU_WIDTH-1:0] i_dec_info_bus_lsu,
    output wire [31:0] o_mema_ld_addr,
    input wire [31:0] i_mema_ld_data,
    output wire [31:0] o_mema_st_addr,
    output wire [31:0] o_mema_st_data,
    output wire [31:0] o_lsu_req_result

    );
endmodule
