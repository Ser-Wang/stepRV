`timescale 1ns / 1ps
`include "config.v"

module sram_itcm_1r1rw_wrapper (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_p0_en,
    input  wire [31:0] i_p0_addr,
    output wire [31:0] o_p0_rdata,
    input  wire        i_p1_en,
    input  wire        i_p1_we,
    input  wire [31:0] i_p1_addr,
    input  wire [ 3:0] i_p1_wmask,
    input  wire [31:0] i_p1_wdata,
    output wire [31:0] o_p1_rdata
);

localparam ITCM_ADDR_WIDTH = $clog2(`ITCM_DEPTH);

wire [31:0] macro_qa;
wire [31:0] macro_qb;
wire [31:0] macro_bwenb = {
    {8{~i_p1_wmask[3]}},
    {8{~i_p1_wmask[2]}},
    {8{~i_p1_wmask[1]}},
    {8{~i_p1_wmask[0]}}
};

assign o_p0_rdata = rst_n ? macro_qa : `INSTR_NOP;
assign o_p1_rdata = rst_n ? macro_qb : `ZERO_WORD;

smic55_8192x32_2p u_smic55_8192x32_2p (
    .QA    (macro_qa),
    .QB    (macro_qb),
    .CLKA  (clk),
    .CLKB  (clk),
    .CENA  (~i_p0_en),
    .CENB  (~i_p1_en),
    .WENA  (1'b1),
    .WENB  (~i_p1_we),
    .BWENA ({32{1'b1}}),
    .BWENB (macro_bwenb),
    .AA    (i_p0_addr[ITCM_ADDR_WIDTH+1:2]),
    .AB    (i_p1_addr[ITCM_ADDR_WIDTH+1:2]),
    .DA    (`ZERO_WORD),
    .DB    (i_p1_wdata)
);

endmodule
