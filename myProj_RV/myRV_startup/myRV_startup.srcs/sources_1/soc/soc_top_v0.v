`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/22 17:00:00
// Design Name: 
// Module Name: soc_top_v0
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


module soc_top_v0(
    input wire clk,
    input wire rst_n
    );

wire [31:0] if_pc_addr;
wire [31:0] if_instr_data;



core_rv32i_v0 u_core(
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    // if
    .o_if_pc_addr       (if_pc_addr     ),
    .i_if_instr_data    (if_instr_data  )
    );

p_imem_rom u_p_imem(
    .clk        (clk            ),
    .rst_n      (rst_n          ),
    .i_rd_addr  (if_pc_addr     ),
    .o_rd_data  (if_instr_data  )
    );



endmodule
