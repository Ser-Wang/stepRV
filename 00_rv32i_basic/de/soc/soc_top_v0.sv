`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/22
// Design Name: StepRV_v0
// Module Name: soc_top_v0
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module soc_top_v0(
    input wire clk,
    input wire rst_n
    );

wire [31:0] if_pc;

wire [31:0] itcm_rd_data;

wire [31:0] mema_addr;
wire mema_wren;
wire [3:0] mema_wr_mask;
wire [31:0] mema_wr_data;
wire [31:0] mema_rd_data;

core_rv32i_v0 u_core(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    // if
    .o_if_pc            (if_pc          ),
    .i_if_instr         (itcm_rd_data   ),
    // mem access
    .o_mema_addr        (mema_addr      ),
    .o_mema_wren        (mema_wren      ),
    .o_mema_wr_mask     (mema_wr_mask   ),
    .o_mema_wr_data     (mema_wr_data   ),
    .i_mema_rd_data     (mema_rd_data   )
    );


wire [31:0] itcm_wr_addr;
wire        itcm_wr_en;
wire [ 3:0] itcm_wr_mask;
wire [31:0] itcm_wr_data;

wire [31:0] dtcm_addr;
wire        dtcm_wr_en;
wire [ 3:0] dtcm_wr_mask;
wire [31:0] dtcm_wr_data;
wire [31:0] dtcm_rd_data;

// Memory Bus & Arbitration
soc_bus_v0 u_soc_bus (
    // Core interface
    .i_mema_addr    (mema_addr    ),
    .i_mema_wren    (mema_wren    ),
    .i_mema_wr_mask (mema_wr_mask ),
    .i_mema_wr_data (mema_wr_data ),
    .o_mema_rd_data (mema_rd_data ),

    // ITCM interface
    .o_itcm_wr_addr (itcm_wr_addr ),
    .o_itcm_wr_en   (itcm_wr_en   ),
    .o_itcm_wr_mask (itcm_wr_mask ),
    .o_itcm_wr_data (itcm_wr_data ),

    // DTCM interface
    .o_dtcm_addr    (dtcm_addr    ),
    .o_dtcm_wr_en   (dtcm_wr_en   ),
    .o_dtcm_wr_mask (dtcm_wr_mask ),
    .o_dtcm_wr_data (dtcm_wr_data ),
    .i_dtcm_rd_data (dtcm_rd_data )
);

mem_itcm u_imem(
    .clk                (clk            ),
    .rst_n              (rst_n          ),
    .i_rd_addr          (if_pc     ),
    .o_rd_data          (itcm_rd_data  ),
    // Data Write (Self-modifying support)
    .i_wr_en            (itcm_wr_en     ),
    .i_wr_mask          (itcm_wr_mask   ),
    .i_wr_addr          (itcm_wr_addr   ),
    .i_wr_data          (itcm_wr_data   )
    );

mem_dtcm u_dmem(
    .clk        (clk            ),
    .rst_n      (rst_n          ),
    .i_addr     (dtcm_addr      ),
    .i_wr_en    (dtcm_wr_en     ),
    .i_wr_mask  (dtcm_wr_mask   ),
    .i_wr_data  (dtcm_wr_data   ),
    .o_rd_data  (dtcm_rd_data   )
    );


endmodule
