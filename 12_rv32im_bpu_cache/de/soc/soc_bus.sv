`timescale 1ns / 1ps
`include "config.v"

module soc_bus (
    input  wire        clk,
    input  wire        rst_n,
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

    output wire        o_dcache_req_vld,
    input  wire        i_dcache_req_rdy,
    output wire [31:0] o_dcache_req_addr,
    output wire        o_dcache_req_load,
    output wire        o_dcache_req_write,
    output wire [ 3:0] o_dcache_req_wmask,
    output wire [31:0] o_dcache_req_wdata,
    input  wire        i_dcache_rsp_vld,
    output wire        o_dcache_rsp_rdy,
    input  wire [31:0] i_dcache_rsp_data,

    output wire        o_imem_p1_en,
    output wire        o_imem_p1_we,
    output wire [31:0] o_imem_p1_addr,
    output wire [ 3:0] o_imem_p1_wmask,
    output wire [31:0] o_imem_p1_wdata,
    input  wire [31:0] i_imem_p1_rdata,

    output wire [31:0] o_uart_addr,
    output wire        o_uart_wr_en,
    output wire [31:0] o_uart_wr_data,
    input  wire [31:0] i_uart_rd_data
);

localparam [31:0] IMEM_BASE_ADDR = `ITCM_BASE;
localparam [31:0] DMEM_BASE_ADDR = `DTCM_BASE;
localparam [31:0] UART_BASE_ADDR = `UART_BASE;
localparam [1:0] TARGET_DCACHE = 2'd0;
localparam [1:0] TARGET_IMEM   = 2'd1;

// Phase-2 coarse attributes. Exact range/error handling remains deferred.
wire sel_imem = (i_mem_addr[31:28] == IMEM_BASE_ADDR[31:28]);
wire sel_dmem = (i_mem_addr[31:28] == DMEM_BASE_ADDR[31:28]);
wire sel_uart = (i_mem_addr[31:28] == UART_BASE_ADDR[31:28]);
wire sel_unmapped = !(sel_imem || sel_dmem || sel_uart);

reg        r_active;
reg [ 1:0] r_active_target;
reg        r_rsp_vld;
reg [31:0] r_rsp_data;

wire rsp_pop = r_rsp_vld && i_mem_rsp_rdy;
wire rsp_slot_available = !r_rsp_vld || i_mem_rsp_rdy;
wire request_window = !r_active && rsp_slot_available;

assign o_dcache_req_vld = i_mem_req_vld && request_window && sel_dmem;
assign o_dcache_req_addr = i_mem_addr;
assign o_dcache_req_load = i_mem_req_load;
assign o_dcache_req_write = i_mem_wr_en;
assign o_dcache_req_wmask = i_mem_wr_mask;
assign o_dcache_req_wdata = i_mem_wr_data;

assign o_mem_req_rdy = request_window
                     && (!sel_dmem || i_dcache_req_rdy);
wire mem_req_fire = i_mem_req_vld && o_mem_req_rdy;

assign o_imem_p1_en = mem_req_fire && sel_imem;
assign o_imem_p1_we = o_imem_p1_en && i_mem_wr_en;
assign o_imem_p1_addr = i_mem_addr;
assign o_imem_p1_wmask = i_mem_wr_mask;
assign o_imem_p1_wdata = i_mem_wr_data;

assign o_uart_addr = i_mem_addr;
assign o_uart_wr_en = mem_req_fire && sel_uart && i_mem_wr_en;
assign o_uart_wr_data = i_mem_wr_data;

assign o_dcache_rsp_rdy = r_active && (r_active_target == TARGET_DCACHE)
                          && rsp_slot_available;
wire dcache_rsp_fire = i_dcache_rsp_vld && o_dcache_rsp_rdy;
wire imem_rsp_complete = r_active && (r_active_target == TARGET_IMEM)
                        && rsp_slot_available;
wire delayed_rsp_push = dcache_rsp_fire || imem_rsp_complete;
wire immediate_rsp_push = mem_req_fire && (sel_uart || sel_unmapped);
wire rsp_push = delayed_rsp_push || immediate_rsp_push;

assign o_mem_rsp_vld = r_rsp_vld;
assign o_mem_rd_data = r_rsp_data;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_active <= 1'b0;
        r_active_target <= TARGET_DCACHE;
        r_rsp_vld <= 1'b0;
        r_rsp_data <= `ZERO_WORD;
    end else begin
        case ({rsp_push, rsp_pop})
            2'b10: r_rsp_vld <= 1'b1;
            2'b01: r_rsp_vld <= 1'b0;
            2'b11: r_rsp_vld <= 1'b1;
            default: r_rsp_vld <= r_rsp_vld;
        endcase

        if (dcache_rsp_fire)
            r_rsp_data <= i_dcache_rsp_data;
        else if (imem_rsp_complete)
            r_rsp_data <= i_imem_p1_rdata;
        else if (immediate_rsp_push)
            r_rsp_data <= (sel_uart && i_mem_req_load)
                        ? i_uart_rd_data : `ZERO_WORD;

        if (delayed_rsp_push)
            r_active <= 1'b0;

        if (mem_req_fire && sel_dmem) begin
            r_active <= 1'b1;
            r_active_target <= TARGET_DCACHE;
        end else if (mem_req_fire && sel_imem) begin
            r_active <= 1'b1;
            r_active_target <= TARGET_IMEM;
        end
    end
end

wire unused_mem_size = ^i_mem_size;

endmodule
