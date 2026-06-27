`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/14
// Design Name: StepRV_v0
// Module Name: soc_bus
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module soc_bus (
    input  wire        clk,
    input  wire        rst_n,
    // Core LSU interface
    input  wire [31:0] i_mem_addr,
    input  wire        i_mem_req_load,
    input  wire        i_mem_wr_en,
    input  wire [ 3:0] i_mem_wr_mask,
    input  wire [31:0] i_mem_wr_data,
    output wire [31:0] o_mem_rd_data,

    // ITCM interface
    output wire        o_itcm_p1_en,
    output wire        o_itcm_p1_we,
    output wire [31:0] o_itcm_p1_addr,
    output wire [ 3:0] o_itcm_p1_wmask,
    output wire [31:0] o_itcm_p1_wdata,
    input  wire [31:0] i_itcm_p1_rdata,

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

reg rd_sel_itcm_d1;
reg rd_sel_dtcm_d1;
reg rd_sel_uart_d1;
reg [31:0] r_uart_rd_data_d1;  // Latch UART combinational read data to align with rd_sel_uart_d1

// Route to ITCM
assign o_itcm_p1_en    = sel_itcm & (i_mem_req_load | i_mem_wr_en);
assign o_itcm_p1_we    = i_mem_wr_en & sel_itcm;
assign o_itcm_p1_addr  = i_mem_addr;
assign o_itcm_p1_wmask = i_mem_wr_mask;
assign o_itcm_p1_wdata = i_mem_wr_data;

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
        rd_sel_itcm_d1 <= 1'b0;
        rd_sel_dtcm_d1 <= 1'b0;
        rd_sel_uart_d1 <= 1'b0;
        r_uart_rd_data_d1 <= 32'b0;
    end
    else begin
        rd_sel_itcm_d1 <= i_mem_req_load & sel_itcm;
        rd_sel_dtcm_d1 <= i_mem_req_load & sel_dtcm;
        rd_sel_uart_d1 <= i_mem_req_load & sel_uart;
        // Sample UART combinational output while address & sel_uart are still valid (this cycle).
        // Next cycle, rd_sel_uart_d1 will select this latched value.
        if (i_mem_req_load & sel_uart)
            r_uart_rd_data_d1 <= i_uart_rd_data;
    end
end

// Read Data Mux (Parallel, No Priority)
assign o_mem_rd_data = ({32{rd_sel_itcm_d1}} & i_itcm_p1_rdata)
                     | ({32{rd_sel_dtcm_d1}} & i_dtcm_rd_data)
                     | ({32{rd_sel_uart_d1}} & r_uart_rd_data_d1);




endmodule
