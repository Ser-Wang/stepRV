`timescale 1ns / 1ps
`include "config.v"

module sram_dtcm_1rw_wrapper (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_wr_en,
    input  wire [ 3:0] i_wr_mask,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_wr_data,
    output wire [31:0] o_rd_data
);

localparam DTCM_ADDR_WIDTH = $clog2(`DTCM_DEPTH);

wire [31:0] macro_q;
wire [31:0] macro_bwen = {
    {8{~i_wr_mask[3]}},
    {8{~i_wr_mask[2]}},
    {8{~i_wr_mask[1]}},
    {8{~i_wr_mask[0]}}
};

assign o_rd_data = rst_n ? macro_q : `ZERO_WORD;

smic55_4096x32_1rw u_smic55_4096x32_1rw (
    .Q    (macro_q),
    .CLK  (clk),
    .CEN  (1'b0),
    .WEN  (~i_wr_en),
    .BWEN (macro_bwen),
    .A    (i_addr[DTCM_ADDR_WIDTH+1:2]),
    .D    (i_wr_data)
);

endmodule
