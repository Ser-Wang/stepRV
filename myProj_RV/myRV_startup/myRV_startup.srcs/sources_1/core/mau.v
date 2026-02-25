`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/17 19:33:45
// Design Name: 
// Module Name: mau
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

module mau(
    input wire clk,
    input wire rst_n,

    // pass by
    input wire [31:0] i_wbck_data_ex,
    input wire [`RFIDX_WIDTH-1:0] i_wbck_rdidx_ex,
    input wire i_wbck_rdwen_ex,

    output wire [31:0] o_wbck_data_mema,
    output wire [`RFIDX_WIDTH-1:0] o_wbck_rdidx_mema,
    output wire o_wbck_rdwen_mema
    );

reg [31:0] r_wbck_data_mema;
reg [`RFIDX_WIDTH-1:0] r_wbck_rdidx_mema;
reg r_wbck_rdwen_mema;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wbck_data_mema <= 32'd0;
    end
    else begin
        r_wbck_data_mema <= i_wbck_data_ex;
    end
end
assign o_wbck_data_mema = r_wbck_data_mema;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wbck_rdidx_mema <= {`RFIDX_WIDTH{1'b0}};
    end
    else begin
        r_wbck_rdidx_mema <= i_wbck_rdidx_ex;
    end
end
assign o_wbck_rdidx_mema = r_wbck_rdidx_mema;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wbck_rdwen_mema <= 1'd0;
    end
    else begin
        r_wbck_rdwen_mema <= i_wbck_rdwen_ex;
    end
end
assign o_wbck_rdwen_mema = r_wbck_rdwen_mema;







endmodule
