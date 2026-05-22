`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/02
// Design Name: StepRV_v0
// Module Name: mem_dtcm
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module mem_dtcm(
    input  wire clk,
    input  wire rst_n,
    input  wire i_wr_en,
    input  wire [3:0] i_wr_mask,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_wr_data,
    output wire [31:0] o_rd_data
    );

reg [31:0] r_dtcm [0:`DTCM_DEPTH-1];    // 4096 by default
reg [31:0] r_rd_data;

// write data
always @(posedge clk) begin
    if (i_wr_en) begin
        // r_dtcm[i_addr[31:2]] <= i_wr_data;
        if (i_wr_mask[0]) begin
            r_dtcm[i_addr[31:2]][7:0]   <= i_wr_data[7:0];
        end
        if (i_wr_mask[1]) begin
            r_dtcm[i_addr[31:2]][15:8]  <= i_wr_data[15:8];
        end
        if (i_wr_mask[2]) begin
            r_dtcm[i_addr[31:2]][23:16] <= i_wr_data[23:16];
        end
        if (i_wr_mask[3]) begin
            r_dtcm[i_addr[31:2]][31:24] <= i_wr_data[31:24];
        end
    end
end

// read data
always @(*) begin
    if (!rst_n) begin
        r_rd_data = `ZERO_WORD;
    end
    else begin
        r_rd_data = r_dtcm[i_addr[31:2]];
    end
end

assign o_rd_data = r_rd_data;

endmodule
