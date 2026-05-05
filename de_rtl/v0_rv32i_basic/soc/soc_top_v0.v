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

wire [31:0] mema_addr;
wire mema_wren;
wire [3:0] mema_wr_mask;
wire [31:0] mema_rd_data;
wire [31:0] mema_wr_data;


core_rv32i_v0 u_core(
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    // if
    .o_pc_if_addr       (pc_addr_if     ),
    .i_instr_if_data    (instr_if_data  ),
    // mem access
    .o_mema_addr        (mema_addr      ),
    .o_mema_wren        (mema_wren      ),
    .o_mema_wr_mask     (mema_wr_mask   ),
    .i_mema_rd_data     (mema_rd_data   ),
    .o_mema_wr_data     (mema_wr_data   )
    );


mem_itcm u_imem(
    .clk        (clk            ),
    .rst_n      (rst_n          ),
    .i_rd_addr  (pc_addr_if     ),
    .o_rd_data  (instr_if_data  )
    );

mem_dtcm u_dmem(
    .clk        (clk            ),
    .rst_n      (rst_n          ),
    .i_wr_en    (mema_wren      ),
    .i_wr_mask  (mema_wr_mask   ),
    .i_addr     (mema_addr      ),
    // .i_addr     ({1'b1, mema_addr[30:2]}),
    .i_wr_data  (mema_wr_data   ),
    .o_rd_data  (mema_rd_data   )
    );


endmodule
