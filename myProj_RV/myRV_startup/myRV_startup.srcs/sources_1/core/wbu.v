`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/17 19:33:45
// Design Name: 
// Module Name: wbu
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

module wbu(
    input wire clk,
    input wire rst_n,
    
    // pass by
    input wire [31:0] i_wrbk_data_mema,
    input wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_mema,
    input wire i_wrbk_rdwen_mema,

    output wire [31:0] o_wrbk_data_wb,
    output wire [`RFIDX_WIDTH-1:0] o_wrbk_rdidx_wb,
    output wire o_wrbk_rdwen_wb
    );

reg [31:0] r_wrbk_data_wb;
reg [`RFIDX_WIDTH-1:0] r_wrbk_rdidx_wb;
reg r_wrbk_rdwen_wb;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_data_wb <= 32'd0;
    end
    else begin
        r_wrbk_data_wb <= i_wrbk_data_mema;
    end
end
assign o_wrbk_data_wb = r_wrbk_data_wb;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdidx_wb <= {`RFIDX_WIDTH{1'b0}};
    end
    else begin
        r_wrbk_rdidx_wb <= i_wrbk_rdidx_mema;
    end
end
assign o_wrbk_rdidx_wb = r_wrbk_rdidx_wb;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdwen_wb <= 1'd0;
    end
    else begin
        r_wrbk_rdwen_wb <= i_wrbk_rdwen_mema;
    end
end
assign o_wrbk_rdwen_wb = r_wrbk_rdwen_wb;


endmodule
