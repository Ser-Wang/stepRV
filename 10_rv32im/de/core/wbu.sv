`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/02/17
// Design Name: StepRV_v0
// Module Name: wbu
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module wbu(
    input wire clk,
    input wire rst_n,
    input wire i_ma_wb_vld,
    output wire o_ma_wb_rdy,
    output wire o_wb_vld,
    input wire i_wb_rdy,
    
    // pass by
    input wire [31:0] i_wb_data_mau,
    input wire [`RFIDX_WIDTH-1:0] i_wb_rd_idx_mau,
    input wire i_wb_rd_wen_mau,

    output wire [31:0] o_wb_data_wbu,
    output wire [`RFIDX_WIDTH-1:0] o_wb_rd_idx_wbu,
    output wire o_wb_rd_wen_wbu
    );

reg [31:0] r_wb_data_wbu;
reg [`RFIDX_WIDTH-1:0] r_wb_rd_idx_wbu;
reg r_wb_rd_wen_wbu;
reg r_wb_vld;

assign o_ma_wb_rdy = !r_wb_vld | i_wb_rdy;
assign o_wb_vld = r_wb_vld;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_vld <= 1'b0;
    end
    else if (o_ma_wb_rdy) begin
        r_wb_vld <= i_ma_wb_vld;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_data_wbu <= 32'd0;
    end
    else if (i_ma_wb_vld & o_ma_wb_rdy) begin
        r_wb_data_wbu <= i_wb_data_mau;
    end
end
assign o_wb_data_wbu = r_wb_data_wbu;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_rd_idx_wbu <= {`RFIDX_WIDTH{1'b0}};
    end
    else if (i_ma_wb_vld & o_ma_wb_rdy) begin
        r_wb_rd_idx_wbu <= i_wb_rd_idx_mau;
    end
end
assign o_wb_rd_idx_wbu = r_wb_rd_idx_wbu;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_rd_wen_wbu <= 1'd0;
    end
    else if (i_ma_wb_vld & o_ma_wb_rdy) begin
        r_wb_rd_wen_wbu <= i_wb_rd_wen_mau;
    end
end
assign o_wb_rd_wen_wbu = r_wb_vld & r_wb_rd_wen_wbu;


endmodule
