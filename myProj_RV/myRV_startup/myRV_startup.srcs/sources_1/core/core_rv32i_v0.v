`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/22 17:00:00
// Design Name: 
// Module Name: core_rv32i_v0
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
// `include "./config.v"

module core_rv32i_v0(
    input wire clk,
    input wire rst_n,   //
    // if
    output wire [31:0] o_if_pc_addr,
    input  wire [31:0] i_if_instr_data
    );

////********    Wires    ********////
// regfile
wire [4:0] rf_read_rs1_idx;
wire [4:0] rf_read_rs2_idx;
wire [31:0] rf_read_rs1_data;
wire [31:0] rf_read_rs2_data;
wire rf_wb_wen;
wire [4:0] rf_wb_dest_idx;
wire [31:0] rf_wb_dest_data;

// if_id
wire [31:0] if_id_instr_d0;
wire [31:0] if_id_pc_d0;

c_regfile u_c_regfile(
    .clk                (clk),
    .rst_n              (rst_n),
    .i_read_rs1_idx     (rf_read_rs1_idx),
    .i_read_rs2_idx     (rf_read_rs2_idx),
    .o_read_rs1_data    (rf_read_rs1_data),
    .o_read_rs2_data    (rf_read_rs2_data),
    .i_wb_wen           (rf_wb_wen),
    .i_wb_dest_idx      (rf_wb_dest_idx),   // write back
    .i_wb_dest_data     (rf_wb_dest_data)
    );

c_ifu u_c_ifu(
    .clk        (clk),
    .rst_n      (rst_n),
    .o_pc       (o_if_pc_addr)
    );

c_if_id u_c_if_id(
    .clk        (clk    ),
    .rst_n      (rst_n  ),
    .i_instr    (i_if_instr_data),
    .i_pc       (o_if_pc_addr   ),
    .o_instr_d0 (if_id_instr_d0 ),
    .o_pc_d0    (if_id_pc_d0    )
    );




endmodule
