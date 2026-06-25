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
    input  wire        clk,
    input  wire        rst_n,
    // Core LSU interface
    input  wire [31:0] i_mem_addr,
    input  wire        i_mem_req_load,
    input  wire        i_mem_wr_en,
    input  wire [ 3:0] i_mem_wr_mask,
    input  wire [31:0] i_mem_wr_data,
    output wire [31:0] o_mem_rd_data,

    // ITCM Data interface
    output wire [31:0] o_itcm_wr_addr,
    output wire        o_itcm_wr_en,
    output wire [ 3:0] o_itcm_wr_mask,
    output wire [31:0] o_itcm_wr_data,

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
wire sel_itcm = (i_mem_addr >= `ITCM_BASE) && (i_mem_addr < (`ITCM_BASE + `ITCM_SIZE));
wire sel_dtcm = (i_mem_addr >= `DTCM_BASE) && (i_mem_addr < (`DTCM_BASE + `DTCM_SIZE));
wire sel_uart = (i_mem_addr >= `UART_BASE) && (i_mem_addr < (`UART_BASE + `UART_SIZE));

reg rd_sel_dtcm_d1;
reg rd_sel_uart_d1;

// Route to ITCM
assign o_itcm_wr_addr = i_mem_addr;
assign o_itcm_wr_en   = i_mem_wr_en & sel_itcm;
assign o_itcm_wr_mask = i_mem_wr_mask;
assign o_itcm_wr_data = i_mem_wr_data;

// Route to DTCM
assign o_dtcm_addr    = i_mem_addr;
assign o_dtcm_wr_en   = i_mem_wr_en & sel_dtcm;
assign o_dtcm_wr_mask = i_mem_wr_mask;
assign o_dtcm_wr_data = i_mem_wr_data;

// Route to UART
assign o_uart_addr    = i_mem_addr;
assign o_uart_wr_en   = i_mem_wr_en & sel_uart;
assign o_uart_wr_data = i_mem_wr_data;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_sel_dtcm_d1 <= 1'b0;
        rd_sel_uart_d1 <= 1'b0;
    end
    else begin
        rd_sel_dtcm_d1 <= i_mem_req_load & sel_dtcm;
        rd_sel_uart_d1 <= i_mem_req_load & sel_uart;
    end
end

// Read Data Mux
assign o_mem_rd_data = rd_sel_dtcm_d1 ? i_dtcm_rd_data :
                        rd_sel_uart_d1 ? i_uart_rd_data :
                        32'b0;




endmodule
