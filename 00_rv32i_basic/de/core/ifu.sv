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
    input wire clk,
    input wire rst_n,
    input wire i_stall,
    input wire i_jump_flag,
    input wire [31:0] i_pc_next_bru,
    output wire [31:0] o_pc_if
    );


reg [31:0] pc_r;
wire [31:0] pc_add4;
wire [31:0] pc_next;

assign pc_add4 = pc_r + 3'd4;
assign pc_next = i_jump_flag ? i_pc_next_bru : pc_add4;


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_r <= 32'd0;
    end
    else if(!i_stall) begin
        pc_r <= pc_next;
    end
end

assign o_pc_if = pc_r;


endmodule
