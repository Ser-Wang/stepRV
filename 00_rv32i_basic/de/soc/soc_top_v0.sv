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
    input wire rst_n,
    output wire o_uart_tx,
    input wire i_uart_rx
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
wire [31:0] itcm_rd_data_lsu; // (Temporary)

wire [31:0] dtcm_addr;
wire        dtcm_wr_en;
wire [ 3:0] dtcm_wr_mask;
wire [31:0] dtcm_wr_data;
wire [31:0] dtcm_rd_data;

wire [31:0] uart_addr;
wire        uart_wr_en;
wire [31:0] uart_wr_data;
wire [31:0] uart_rd_data;

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
    .i_itcm_rd_data (itcm_rd_data_lsu), // (Temporary)

    // DTCM interface
    .o_dtcm_addr    (dtcm_addr    ),
    .o_dtcm_wr_en   (dtcm_wr_en   ),
    .o_dtcm_wr_mask (dtcm_wr_mask ),
    .o_dtcm_wr_data (dtcm_wr_data ),
    .i_dtcm_rd_data (dtcm_rd_data ),

    // UART interface
    .o_uart_addr    (uart_addr    ),
    .o_uart_wr_en   (uart_wr_en   ),
    .o_uart_wr_data (uart_wr_data ),
    .i_uart_rd_data (uart_rd_data )
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
    .i_wr_data          (itcm_wr_data   ),
    .o_data_rd_data     (itcm_rd_data_lsu) // (Temporary)
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

uart u_uart(
    .clk        (clk         ),
    .rst_n      (rst_n       ),
    .we_i       (uart_wr_en  ),
    .addr_i     (uart_addr   ),
    .data_i     (uart_wr_data),
    .data_o     (uart_rd_data),
    .tx_pin     (o_uart_tx   ),
    .rx_pin     (i_uart_rx   )
    );


// ila_0 your_instance_name (
// 	.clk(clk), // input wire clk
// 	.probe0(o_uart_tx), // input wire [0:0]  probe0  
// 	.probe1(u_core.u_exu.r_pc_exu) // input wire [7:0]  probe1
// );


endmodule
