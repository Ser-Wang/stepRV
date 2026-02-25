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

wire [31:0] pc_addr_if;
wire [31:0] instr_if_data;



core_rv32i_v0 u_core(
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    // if
    .o_pc_if_addr       (pc_addr_if     ),
    .i_instr_if_data    (instr_if_data  )
    );

p_imem_rom u_p_imem(
    .clk        (clk            ),
    .rst_n      (rst_n          ),
    .i_rd_addr  (pc_addr_if     ),
    .o_rd_data  (instr_if_data  )
    );



endmodule
