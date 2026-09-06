`timescale 1ns / 1ps
`include "config.v"

// Word-transaction backing store for I-Cache refill plus the existing LSU
// executable-region data port. Cache tags and refill control live in icache.
module backing_imem (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_p0_req_vld,
    output wire        o_p0_req_rdy,
    input  wire [31:0] i_p0_req_addr,
    output wire        o_p0_rsp_vld,
    input  wire        i_p0_rsp_rdy,
    output wire [31:0] o_p0_rsp_data,
    input  wire        i_p1_en,
    input  wire        i_p1_we,
    input  wire [31:0] i_p1_addr,
    input  wire [ 3:0] i_p1_wmask,
    input  wire [31:0] i_p1_wdata,
    output wire [31:0] o_p1_rdata
);

localparam integer IMEM_ADDR_WIDTH = $clog2(`ITCM_DEPTH);
localparam [31:0] IMEM_BASE_ADDR = `ITCM_BASE;

reg [31:0] r_backing_imem [0:`ITCM_DEPTH-1];
reg        r_p0_rsp_vld;
reg [31:0] r_p0_rdata;
reg [31:0] r_p1_rdata;

wire p0_req_fire = i_p0_req_vld && o_p0_req_rdy;
wire p0_addr_mapped = (i_p0_req_addr[31:28] == IMEM_BASE_ADDR[31:28]);

assign o_p0_req_rdy = !r_p0_rsp_vld || i_p0_rsp_rdy;
assign o_p0_rsp_vld = r_p0_rsp_vld;
assign o_p0_rsp_data = r_p0_rdata;
assign o_p1_rdata = r_p1_rdata;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        r_p0_rsp_vld <= 1'b0;
    else if (o_p0_req_rdy)
        r_p0_rsp_vld <= i_p0_req_vld;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        r_p0_rdata <= `INSTR_NOP;
    else if (p0_req_fire)
        r_p0_rdata <= p0_addr_mapped
                    ? r_backing_imem[i_p0_req_addr[IMEM_ADDR_WIDTH+1:2]]
                    : `INSTR_NOP;
end

always @(posedge clk) begin
    if (i_p1_en && i_p1_we) begin
        if (i_p1_wmask[0])
            r_backing_imem[i_p1_addr[IMEM_ADDR_WIDTH+1:2]][7:0] <= i_p1_wdata[7:0];
        if (i_p1_wmask[1])
            r_backing_imem[i_p1_addr[IMEM_ADDR_WIDTH+1:2]][15:8] <= i_p1_wdata[15:8];
        if (i_p1_wmask[2])
            r_backing_imem[i_p1_addr[IMEM_ADDR_WIDTH+1:2]][23:16] <= i_p1_wdata[23:16];
        if (i_p1_wmask[3])
            r_backing_imem[i_p1_addr[IMEM_ADDR_WIDTH+1:2]][31:24] <= i_p1_wdata[31:24];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        r_p1_rdata <= `ZERO_WORD;
    else if (i_p1_en && !i_p1_we)
        r_p1_rdata <= r_backing_imem[i_p1_addr[IMEM_ADDR_WIDTH+1:2]];
end

endmodule
