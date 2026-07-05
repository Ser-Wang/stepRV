`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/22
// Design Name: StepRV_v0
// Module Name: ifu
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module ifu(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_stall,
    input  wire        i_redirect_req,
    input  wire [31:0] i_redirect_pcnext,
    output wire        o_fetch_req,
    output wire [31:0] o_fetch_pc, // Sent to ITCM
    output wire        o_if_valid,
    output wire [31:0] o_instr_pc  // Sent to ID
);

localparam RESET_PC = 32'h0000_0000;

reg [31:0] pc_r;
reg        if_valid_r;

wire [31:0] pc_add4;
wire [31:0] if_req_pc;
wire        if_accept;

assign pc_add4 = pc_r + 32'd4;

assign if_accept = o_if_valid && !i_stall && !i_redirect_req;

assign if_req_pc = i_redirect_req ? i_redirect_pcnext : // actrually if_req_pc is pc_next for pc_r
                   if_accept      ? pc_add4 :
                                    pc_r;

assign o_fetch_req = 1'b1;
assign o_fetch_pc  = if_req_pc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_r <= RESET_PC;
    end else begin
        pc_r <= if_req_pc;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_valid_r <= 1'b0;
    end else begin
        if_valid_r <= 1'b1;
    end
end

assign o_if_valid = if_valid_r && !i_redirect_req;
assign o_instr_pc = pc_r;

endmodule
