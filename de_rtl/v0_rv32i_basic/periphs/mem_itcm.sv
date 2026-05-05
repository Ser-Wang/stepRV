`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/22 17:23:50
// Design Name: 
// Module Name: mem_itcm
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

module mem_itcm(
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_rd_addr,
    output wire [31:0] o_rd_data
    );

reg [31:0] r_itcm [0:`ITCM_DEPTH-1];    // 4096 by default
reg [31:0] r_rd_data;

assign o_rd_data = r_rd_data;

always @(*) begin
    if (!rst_n) begin
        r_rd_data = `ZERO_WORD;
    end
    else begin
        r_rd_data = r_itcm[i_rd_addr[31:2]];
    end
end


endmodule
