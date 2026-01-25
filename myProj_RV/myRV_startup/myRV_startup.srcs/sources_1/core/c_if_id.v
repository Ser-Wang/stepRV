`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/24 18:43:15
// Design Name: 
// Module Name: c_if_id
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


module c_if_id(
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_instr,
    input wire [31:0] i_pc,
    output wire [31:0] o_instr_d0,
    output wire [31:0] o_pc_d0
    );


reg [31:0] r_instr_d0;
reg [31:0] r_pc_d0;

assign o_instr_d0 = r_instr_d0;
assign o_pc_d0 = r_pc_d0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_instr_d0 <= 32'b0;
    end
    else begin
        r_instr_d0 <= i_instr;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_pc_d0 <= 32'b0;
    end
    else begin
        r_pc_d0 <= i_pc;
    end
end


endmodule
