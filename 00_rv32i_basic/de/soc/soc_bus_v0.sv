`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/14
// Design Name: StepRV_v0
// Module Name: soc_bus_v0
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module soc_bus_v0 (
    // Core LSU interface
    input  wire [31:0] i_mema_addr,
    input  wire        i_mema_wren,
    input  wire [ 3:0] i_mema_wr_mask,
    input  wire [31:0] i_mema_wr_data,
    output wire [31:0] o_mema_rd_data,

    // ITCM Data interface
    output wire [31:0] o_itcm_wr_addr,
    output wire        o_itcm_wr_en,
    output wire [ 3:0] o_itcm_wr_mask,
    output wire [31:0] o_itcm_wr_data,
    input  wire [31:0] i_itcm_rd_data, // (Temporary)

    // DTCM interface (Read/Write)
    output wire [31:0] o_dtcm_addr,
    output wire        o_dtcm_wr_en,
    output wire [ 3:0] o_dtcm_wr_mask,
    output wire [31:0] o_dtcm_wr_data,
    input  wire [31:0] i_dtcm_rd_data,

    // UART interface (32-bit MMIO access only in this first integration)
    output wire [31:0] o_uart_addr,
    output wire        o_uart_wr_en,
    output wire [31:0] o_uart_wr_data,
    input  wire [31:0] i_uart_rd_data
);

// Address Decoding
wire sel_itcm = (i_mema_addr >= `ITCM_BASE) && (i_mema_addr < (`ITCM_BASE + `ITCM_SIZE));
wire sel_dtcm = (i_mema_addr >= `DTCM_BASE) && (i_mema_addr < (`DTCM_BASE + `DTCM_SIZE));
wire sel_uart = (i_mema_addr >= `UART_BASE) && (i_mema_addr < (`UART_BASE + `UART_SIZE));

// Route to ITCM
assign o_itcm_wr_addr = i_mema_addr;
assign o_itcm_wr_en   = i_mema_wren & sel_itcm;
assign o_itcm_wr_mask = i_mema_wr_mask;
assign o_itcm_wr_data = i_mema_wr_data;

// Route to DTCM
assign o_dtcm_addr    = i_mema_addr;
assign o_dtcm_wr_en   = i_mema_wren & sel_dtcm;
assign o_dtcm_wr_mask = i_mema_wr_mask;
assign o_dtcm_wr_data = i_mema_wr_data;

// Route to UART
assign o_uart_addr    = i_mema_addr;
assign o_uart_wr_en   = i_mema_wren & sel_uart;
assign o_uart_wr_data = i_mema_wr_data;

// Read Data Mux
assign o_mema_rd_data = sel_dtcm ? i_dtcm_rd_data :
                        sel_itcm ? i_itcm_rd_data : // (Temporary)
                        sel_uart ? i_uart_rd_data :
                        32'b0;




endmodule
