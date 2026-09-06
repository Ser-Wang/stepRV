`timescale 1ns / 1ps
`include "config.v"

module soc_bus (
    input  wire        clk,
    input  wire        rst_n,
    // MAU request/response
    input  wire        i_mem_req_vld,
    output wire        o_mem_req_rdy,
    input  wire [31:0] i_mem_addr,
    input  wire        i_mem_req_load,
    input  wire        i_mem_wr_en,
    input  wire [ 1:0] i_mem_size,
    input  wire [ 3:0] i_mem_wr_mask,
    input  wire [31:0] i_mem_wr_data,
    output wire        o_mem_rsp_vld,
    input  wire        i_mem_rsp_rdy,
    output wire [31:0] o_mem_rd_data,

    // ITCM port 1
    output wire        o_itcm_p1_en,
    output wire        o_itcm_p1_we,
    output wire [31:0] o_itcm_p1_addr,
    output wire [ 3:0] o_itcm_p1_wmask,
    output wire [31:0] o_itcm_p1_wdata,
    input  wire [31:0] i_itcm_p1_rdata,

    // DTCM
    output wire        o_dtcm_en,
    output wire [31:0] o_dtcm_addr,
    output wire        o_dtcm_wr_en,
    output wire [ 3:0] o_dtcm_wr_mask,
    output wire [31:0] o_dtcm_wr_data,
    input  wire [31:0] i_dtcm_rd_data,

    // UART native interface
    output wire [31:0] o_uart_addr,
    output wire        o_uart_wr_en,
    output wire [31:0] o_uart_wr_data,
    input  wire [31:0] i_uart_rd_data
);

localparam [31:0] ITCM_BASE_ADDR = `ITCM_BASE;
localparam [31:0] DTCM_BASE_ADDR = `DTCM_BASE;
localparam [31:0] UART_BASE_ADDR = `UART_BASE;

// Phase-0 coarse attributes. Exact range/error handling is deferred.
wire sel_itcm = (i_mem_addr[31:28] == ITCM_BASE_ADDR[31:28]);
wire sel_dtcm = (i_mem_addr[31:28] == DTCM_BASE_ADDR[31:28]);
wire sel_uart = (i_mem_addr[31:28] == UART_BASE_ADDR[31:28]);
wire attr_cacheable = sel_dtcm;
wire attr_device = sel_itcm | sel_uart;
wire attr_unmapped = !(attr_cacheable | attr_device);

reg        r_rsp_vld;
reg        r_rsp_load;
reg        r_rsp_sel_itcm;
reg        r_rsp_sel_dtcm;
reg        r_rsp_sel_uart;
reg [31:0] r_uart_rd_data;

wire mem_req_fire = i_mem_req_vld & o_mem_req_rdy;
wire target_write_fire = mem_req_fire & i_mem_wr_en & !attr_unmapped;

assign o_mem_req_rdy = !r_rsp_vld | i_mem_rsp_rdy;
assign o_mem_rsp_vld = r_rsp_vld;

assign o_itcm_p1_en = mem_req_fire & sel_itcm;
assign o_itcm_p1_we = target_write_fire & sel_itcm;
assign o_itcm_p1_addr = i_mem_addr;
assign o_itcm_p1_wmask = i_mem_wr_mask;
assign o_itcm_p1_wdata = i_mem_wr_data;

assign o_dtcm_en = mem_req_fire & sel_dtcm;
assign o_dtcm_addr = i_mem_addr;
assign o_dtcm_wr_en = target_write_fire & sel_dtcm;
assign o_dtcm_wr_mask = i_mem_wr_mask;
assign o_dtcm_wr_data = i_mem_wr_data;

assign o_uart_addr = i_mem_addr;
assign o_uart_wr_en = target_write_fire & sel_uart;
assign o_uart_wr_data = i_mem_wr_data;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rsp_vld <= 1'b0;
        r_rsp_load <= 1'b0;
        r_rsp_sel_itcm <= 1'b0;
        r_rsp_sel_dtcm <= 1'b0;
        r_rsp_sel_uart <= 1'b0;
        r_uart_rd_data <= `ZERO_WORD;
    end else if (o_mem_req_rdy) begin
        r_rsp_vld <= i_mem_req_vld;
        if (mem_req_fire) begin
            r_rsp_load <= i_mem_req_load;
            r_rsp_sel_itcm <= sel_itcm;
            r_rsp_sel_dtcm <= sel_dtcm;
            r_rsp_sel_uart <= sel_uart;
            r_uart_rd_data <= i_uart_rd_data;
        end
    end
end

assign o_mem_rd_data = !r_rsp_load ? `ZERO_WORD
                         : r_rsp_sel_itcm ? i_itcm_p1_rdata
                         : r_rsp_sel_dtcm ? i_dtcm_rd_data
                         : r_rsp_sel_uart ? r_uart_rd_data
                                          : `ZERO_WORD;

// Keep size visible at this boundary for the later exact range/device checks.
wire unused_mem_size = ^i_mem_size;

endmodule
