`timescale 1ns / 1ps
`include "config.v"

// Phase-0 transitional instruction-memory backend. Phase 1 inserts I-Cache on
// the CPU-side req/rsp contract and renames/reworks this storage as backing IMEM.
module mem_itcm(
    input  wire        clk,
    input  wire        rst_n,
    // Port 0: IF request/response
    input  wire        i_p0_req_vld,
    output wire        o_p0_req_rdy,
    input  wire [31:0] i_p0_req_addr,
    output wire        o_p0_rsp_vld,
    input  wire        i_p0_rsp_rdy,
    output wire [31:0] o_p0_rsp_data,
    // Port 1: local LSU backend, synchronous 1RW
    input  wire        i_p1_en,
    input  wire        i_p1_we,
    input  wire [31:0] i_p1_addr,
    input  wire [ 3:0] i_p1_wmask,
    input  wire [31:0] i_p1_wdata,
    output wire [31:0] o_p1_rdata
);

localparam ITCM_ADDR_WIDTH = $clog2(`ITCM_DEPTH);
localparam [31:0] ITCM_BASE_ADDR = `ITCM_BASE;

reg [31:0] r_itcm [0:`ITCM_DEPTH-1];
reg        r_p0_rsp_vld;
reg [31:0] r_p0_rdata;
reg [31:0] r_p1_rdata;

wire p0_req_fire = i_p0_req_vld & o_p0_req_rdy;
wire p0_addr_mapped = (i_p0_req_addr[31:28] == ITCM_BASE_ADDR[31:28]);

assign o_p0_req_rdy = !r_p0_rsp_vld | i_p0_rsp_rdy;
assign o_p0_rsp_vld = r_p0_rsp_vld;
assign o_p0_rsp_data = r_p0_rdata;
assign o_p1_rdata = r_p1_rdata;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_p0_rsp_vld <= 1'b0;
    end else if (o_p0_req_rdy) begin
        r_p0_rsp_vld <= i_p0_req_vld;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_p0_rdata <= `INSTR_NOP;
    end else if (p0_req_fire) begin
        r_p0_rdata <= p0_addr_mapped
                    ? r_itcm[i_p0_req_addr[ITCM_ADDR_WIDTH+1:2]]
                    : `INSTR_NOP;
    end
end

// Port 1: Data Write
always @(posedge clk) begin
    if (i_p1_en && i_p1_we) begin
        if (i_p1_wmask[0])
            r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]][7:0]   <= i_p1_wdata[7:0];
        if (i_p1_wmask[1])
            r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]][15:8]  <= i_p1_wdata[15:8];
        if (i_p1_wmask[2])
            r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]][23:16] <= i_p1_wdata[23:16];
        if (i_p1_wmask[3])
            r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]][31:24] <= i_p1_wdata[31:24];
    end
end
// Port 1: Data Read
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_p1_rdata <= `ZERO_WORD;
    end else if (i_p1_en && !i_p1_we) begin
        r_p1_rdata <= r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]];
    end
end

endmodule
