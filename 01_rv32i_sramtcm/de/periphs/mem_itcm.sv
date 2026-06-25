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
    // Port 0: 1R, IFU
    input  wire [31:0] i_p0_addr,
    output wire [31:0] o_p0_rdata,
    // Port 1: 1RW, LSU/load or preload/write
    input  wire        i_p1_en,
    input  wire        i_p1_we,
    input  wire [31:0] i_p1_addr,
    input  wire [ 3:0] i_p1_wmask,
    input  wire [31:0] i_p1_wdata,
    output wire [31:0] o_p1_rdata
    );

reg [31:0] r_itcm [0:`ITCM_DEPTH-1];    // 8192 by default
reg [31:0] r_p0_rdata;
reg [31:0] r_p1_rdata;

assign o_p0_rdata = r_p0_rdata;
assign o_p1_rdata = r_p1_rdata;

// Port 0: Instruction Fetch
always @(*) begin
    if (!rst_n) begin
        r_p0_rdata = `ZERO_WORD;
    end
    else begin
        r_p0_rdata = r_itcm[i_p0_addr[31:2]];
    end
end

// Port 1: Data Write
always @(posedge clk) begin
    if (i_p1_en && i_p1_we) begin
        if (i_p1_wmask[0]) begin
            r_itcm[i_p1_addr[31:2]][7:0]   <= i_p1_wdata[7:0];
        end
        if (i_p1_wmask[1]) begin
            r_itcm[i_p1_addr[31:2]][15:8]  <= i_p1_wdata[15:8];
        end
        if (i_p1_wmask[2]) begin
            r_itcm[i_p1_addr[31:2]][23:16] <= i_p1_wdata[23:16];
        end
        if (i_p1_wmask[3]) begin
            r_itcm[i_p1_addr[31:2]][31:24] <= i_p1_wdata[31:24];
        end
    end
end
// Port 1: Data Read (synchronous, aligns with rd_sel_itcm_d1 in soc_bus)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        r_p1_rdata <= `ZERO_WORD;
    else if (i_p1_en)
        r_p1_rdata <= r_itcm[i_p1_addr[31:2]];
end

// initial begin
//     // $readmemh("d:/myProj_WJH/11_myRV/tests/programs/simple/simple.data", r_itcm);
//     // $readmemh("g:/myProjs/11_myRV/tests/programs/uart_tx/uart_tx.data", r_itcm);
//     // $readmemh("g:/myProjs/11_myRV/tests/programs/coremark/coremark.data", r_itcm);
//     $readmemh("g:/myProjs/11_myRV/tests/programs/coremark_lite/coremark_lite.data", r_itcm);
// end


endmodule
