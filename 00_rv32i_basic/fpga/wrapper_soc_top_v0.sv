`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/06/08
// Design Name: StepRV_v0
// Module Name: wrapper_soc_top_v0
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module wrapper_soc_top_v0(
    input wire clk,
    input wire rst_n,
    output wire o_uart_tx,
    input wire i_uart_rx
    );

// wire clk;
// assign clk = clk_board;

// clk_wiz_0 u_clking
//    (
//     // Clock out ports
//     .clk_out1(clk),     // output clk_out1
//     // Status and control signals
//     .resetn(rst_n), // input resetn
//     .locked(locked),       // output locked
//     // Clock in ports
//     .clk_in1(clk_board)      // input clk_in1
// );

soc_top_v0 u_soc_top_v0(
    .clk        (clk),
    .rst_n      (rst_n),
    .o_uart_tx  (o_uart_tx),
    .i_uart_rx  (i_uart_rx)
    );


// ila_0 your_instance_name (
// 	.clk(clk), // input wire clk
// 	.probe0(o_uart_tx), // input wire [0:0]  probe0  
// 	.probe1(u_soc_top_v0.u_core.u_exu.r_pc_exu) // input wire [7:0]  probe1
// );



endmodule
