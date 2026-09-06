`timescale 1ns / 1ps
`include "config.v"

module backing_dmem (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_req_vld,
    output wire        o_req_rdy,
    input  wire [31:0] i_req_addr,
    input  wire        i_req_write,
    input  wire [ 3:0] i_req_wmask,
    input  wire [31:0] i_req_wdata,
    output wire        o_rsp_vld,
    input  wire        i_rsp_rdy,
    output wire [31:0] o_rsp_data
);

localparam integer DMEM_ADDR_WIDTH = $clog2(`DTCM_DEPTH);

reg [31:0] r_backing_dmem [0:`DTCM_DEPTH-1];
reg        r_rsp_vld;
reg [31:0] r_rsp_data;

wire req_fire = i_req_vld && o_req_rdy;

assign o_req_rdy = !r_rsp_vld || i_rsp_rdy;
assign o_rsp_vld = r_rsp_vld;
assign o_rsp_data = r_rsp_data;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rsp_vld <= 1'b0;
        r_rsp_data <= `ZERO_WORD;
    end else if (o_req_rdy) begin
        r_rsp_vld <= i_req_vld;
        if (req_fire)
            r_rsp_data <= i_req_write ? `ZERO_WORD
                                     : r_backing_dmem[i_req_addr[DMEM_ADDR_WIDTH+1:2]];
    end
end

always @(posedge clk) begin
    if (req_fire && i_req_write) begin
        if (i_req_wmask[0])
            r_backing_dmem[i_req_addr[DMEM_ADDR_WIDTH+1:2]][7:0] <= i_req_wdata[7:0];
        if (i_req_wmask[1])
            r_backing_dmem[i_req_addr[DMEM_ADDR_WIDTH+1:2]][15:8] <= i_req_wdata[15:8];
        if (i_req_wmask[2])
            r_backing_dmem[i_req_addr[DMEM_ADDR_WIDTH+1:2]][23:16] <= i_req_wdata[23:16];
        if (i_req_wmask[3])
            r_backing_dmem[i_req_addr[DMEM_ADDR_WIDTH+1:2]][31:24] <= i_req_wdata[31:24];
    end
end

endmodule
