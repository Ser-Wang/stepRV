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
    input  wire        i_p0_en,
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

localparam ITCM_ADDR_WIDTH = $clog2(`ITCM_DEPTH);

`ifdef USE_SRAM_MACRO

sram_itcm_1r1rw_wrapper u_itcm_sram_wrapper (
    .clk        (clk),
    .rst_n      (rst_n),
    .i_p0_en    (i_p0_en),
    .i_p0_addr  (i_p0_addr),
    .o_p0_rdata (o_p0_rdata),
    .i_p1_en    (i_p1_en),
    .i_p1_we    (i_p1_we),
    .i_p1_addr  (i_p1_addr),
    .i_p1_wmask (i_p1_wmask),
    .i_p1_wdata (i_p1_wdata),
    .o_p1_rdata (o_p1_rdata)
);

`elsif USE_BRAM

wire [31:0] bram_p0_rdata;
wire [31:0] bram_p1_rdata;

assign o_p0_rdata = rst_n ? bram_p0_rdata : `INSTR_NOP;
assign o_p1_rdata = rst_n ? bram_p1_rdata : `ZERO_WORD;

imem_bram_singleport u_itcm_bram (
    .clka  (clk),
    .ena   (i_p0_en),
    .wea   (4'b0000),
    .addra (i_p0_addr[ITCM_ADDR_WIDTH+1:2]),
    .dina  (`ZERO_WORD),
    .douta (bram_p0_rdata),
    .clkb  (clk),
    .enb   (i_p1_en),
    .web   (i_p1_we ? i_p1_wmask : 4'b0000),
    .addrb (i_p1_addr[ITCM_ADDR_WIDTH+1:2]),
    .dinb  (i_p1_wdata),
    .doutb (bram_p1_rdata)
);

`else

reg [31:0] r_itcm [0:`ITCM_DEPTH-1];    // 8192 by default
reg [31:0] r_p0_rdata;
reg [31:0] r_p1_rdata;

assign o_p0_rdata = r_p0_rdata;
assign o_p1_rdata = r_p1_rdata;

// Port 0: Instruction Fetch
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_p0_rdata <= `INSTR_NOP;
    end
    else if (i_p0_en) begin
        r_p0_rdata <= r_itcm[i_p0_addr[ITCM_ADDR_WIDTH+1:2]];
    end
end

// Port 1: Data Write
always @(posedge clk) begin
    if (i_p1_en && i_p1_we) begin
        if (i_p1_wmask[0]) begin
            r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]][7:0]   <= i_p1_wdata[7:0];
        end
        if (i_p1_wmask[1]) begin
            r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]][15:8]  <= i_p1_wdata[15:8];
        end
        if (i_p1_wmask[2]) begin
            r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]][23:16] <= i_p1_wdata[23:16];
        end
        if (i_p1_wmask[3]) begin
            r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]][31:24] <= i_p1_wdata[31:24];
        end
    end
end
// Port 1: Data Read (synchronous, aligns with rd_sel_itcm_d1 in soc_bus)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        r_p1_rdata <= `ZERO_WORD;
    else if (i_p1_en)
        r_p1_rdata <= r_itcm[i_p1_addr[ITCM_ADDR_WIDTH+1:2]];
end

// initial begin
//     // $readmemh("d:/myProj_WJH/11_myRV/tests/programs/simple/simple.data", r_itcm);
//     // $readmemh("g:/myProjs/11_myRV/tests/programs/uart_tx/uart_tx.data", r_itcm);
//     // $readmemh("g:/myProjs/11_myRV/tests/programs/coremark/coremark.data", r_itcm);
//     // $readmemh("g:/myProjs/11_myRV/tests/programs/coremark_lite/coremark_lite.data", r_itcm);
// end

`endif

endmodule
