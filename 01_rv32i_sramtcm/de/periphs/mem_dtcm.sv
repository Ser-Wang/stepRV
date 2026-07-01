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

localparam DTCM_ADDR_WIDTH = $clog2(`DTCM_DEPTH);

`ifdef USE_SRAM_MACRO

sram_dtcm_1rw_wrapper u_dtcm_sram_wrapper (
    .clk       (clk),
    .rst_n     (rst_n),
    .i_wr_en   (i_wr_en),
    .i_wr_mask (i_wr_mask),
    .i_addr    (i_addr),
    .i_wr_data (i_wr_data),
    .o_rd_data (o_rd_data)
);

`elsif USE_BRAM

wire [31:0] bram_rdata;

assign o_rd_data = rst_n ? bram_rdata : `ZERO_WORD;

dmem_bram_truedualport u_dtcm_bram (
    .clka  (clk),
    .ena   (1'b1),
    .wea   (i_wr_en ? i_wr_mask : 4'b0000),
    .addra (i_addr[DTCM_ADDR_WIDTH+1:2]),
    .dina  (i_wr_data),
    .douta (bram_rdata)
);

`else

// write data
always @(posedge clk) begin
    if (i_wr_en) begin
        // r_dtcm[i_addr[31:2]] <= i_wr_data;
        if (i_wr_mask[0]) begin
            r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]][7:0]   <= i_wr_data[7:0];
        end
        if (i_wr_mask[1]) begin
            r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]][15:8]  <= i_wr_data[15:8];
        end
        if (i_wr_mask[2]) begin
            r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]][23:16] <= i_wr_data[23:16];
        end
        if (i_wr_mask[3]) begin
            r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]][31:24] <= i_wr_data[31:24];
        end
    end
end

// synchronous read data
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rd_data <= `ZERO_WORD;
    end
    else begin
        r_rd_data <= r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]];
    end
end

assign o_rd_data = r_rd_data;

`endif

endmodule
