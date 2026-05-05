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
    input wire [31:0] i_wrbk_data_mau,
    input wire [`RFIDX_WIDTH-1:0] i_wrbk_rdidx_mau,
    input wire i_wrbk_rdwen_mau,

    output wire [31:0] o_wrbk_data_wbu,
    output wire [`RFIDX_WIDTH-1:0] o_wrbk_rdidx_wbu,
    output wire o_wrbk_rdwen_wbu
    );

reg [31:0] r_wrbk_data_wbu;
reg [`RFIDX_WIDTH-1:0] r_wrbk_rdidx_wbu;
reg r_wrbk_rdwen_wbu;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_data_wbu <= 32'd0;
    end
    else begin
        r_wrbk_data_wbu <= i_wrbk_data_mau;
    end
end
assign o_wrbk_data_wbu = r_wrbk_data_wbu;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdidx_wbu <= {`RFIDX_WIDTH{1'b0}};
    end
    else begin
        r_wrbk_rdidx_wbu <= i_wrbk_rdidx_mau;
    end
end
assign o_wrbk_rdidx_wbu = r_wrbk_rdidx_wbu;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wrbk_rdwen_wbu <= 1'd0;
    end
    else begin
        r_wrbk_rdwen_wbu <= i_wrbk_rdwen_mau;
    end
end
assign o_wrbk_rdwen_wbu = r_wrbk_rdwen_wbu;


endmodule
