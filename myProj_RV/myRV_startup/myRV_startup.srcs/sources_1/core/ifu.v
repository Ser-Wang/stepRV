`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/22 17:00:00
// Design Name: 
// Module Name: ifu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "../defines/config.v"

module ifu(
    input wire clk,
    input wire rst_n,
    output wire [31:0] o_pc
    );


reg [31:0] pc_r;
assign o_pc = pc_r;


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_r <= 32'd0;
    end
    else begin
        pc_r <= pc_r + 3'd4;
    end
end


endmodule
