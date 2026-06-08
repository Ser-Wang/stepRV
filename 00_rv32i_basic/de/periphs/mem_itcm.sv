`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/22
// Design Name: StepRV_v0
// Module Name: mem_itcm
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module mem_itcm(
    input wire clk,
    input wire rst_n,
    // Port A: Instruction Fetch (Read Only)
    input wire [31:0] i_rd_addr,
    output wire [31:0] o_rd_data,
    // Port B: Data Access (Read/Write)
    input wire i_wr_en,
    input wire [3:0] i_wr_mask,
    input wire [31:0] i_wr_addr,
    input wire [31:0] i_wr_data,
    output wire [31:0] o_data_rd_data // (Temporary)
    );

reg [31:0] r_itcm [0:`ITCM_DEPTH-1];    // 8192 by default
reg [31:0] r_rd_data;
reg [31:0] r_data_rd_data;

assign o_rd_data = r_rd_data;
assign o_data_rd_data = r_data_rd_data;

// Port A: Instruction Fetch
always @(*) begin
    if (!rst_n) begin
        r_rd_data = `ZERO_WORD;
    end
    else begin
        r_rd_data = r_itcm[i_rd_addr[31:2]];
    end
end

// Port B: Data Write
always @(posedge clk) begin
    if (i_wr_en) begin
        if (i_wr_mask[0]) begin
            r_itcm[i_wr_addr[31:2]][7:0]   <= i_wr_data[7:0];
        end
        if (i_wr_mask[1]) begin
            r_itcm[i_wr_addr[31:2]][15:8]  <= i_wr_data[15:8];
        end
        if (i_wr_mask[2]) begin
            r_itcm[i_wr_addr[31:2]][23:16] <= i_wr_data[23:16];
        end
        if (i_wr_mask[3]) begin
            r_itcm[i_wr_addr[31:2]][31:24] <= i_wr_data[31:24];
        end
    end
end

// Port B: Data Read
always @(*) begin
    if (!rst_n) begin
        r_data_rd_data = `ZERO_WORD;
    end
    else begin
        r_data_rd_data = r_itcm[i_wr_addr[31:2]];
    end
end

initial begin
    // $readmemh("d:/myProj_WJH/11_myRV/tests/programs/simple/simple.data", r_itcm);
    // $readmemh("g:/myProjs/11_myRV/tests/programs/uart_tx/uart_tx.data", r_itcm);
    $readmemh("g:/myProjs/11_myRV/tests/programs/coremark/coremark.data", r_itcm);
end


endmodule
