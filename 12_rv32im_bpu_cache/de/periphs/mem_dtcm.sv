`timescale 1ns / 1ps
`include "config.v"

// Phase-0 transitional data-memory backend. Phase 2 inserts D-Cache on the
// CPU-side req/rsp contract and renames/reworks this storage as backing DMEM.
module mem_dtcm(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_en,
    input  wire        i_wr_en,
    input  wire [ 3:0] i_wr_mask,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_wr_data,
    output wire [31:0] o_rd_data
);

localparam DTCM_ADDR_WIDTH = $clog2(`DTCM_DEPTH);

reg [31:0] r_dtcm [0:`DTCM_DEPTH-1];
reg [31:0] r_rd_data;

always @(posedge clk) begin
    if (i_en && i_wr_en) begin
        if (i_wr_mask[0]) 
            r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]][7:0] <= i_wr_data[7:0];
        if (i_wr_mask[1]) 
            r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]][15:8] <= i_wr_data[15:8];
        if (i_wr_mask[2]) 
            r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]][23:16] <= i_wr_data[23:16];
        if (i_wr_mask[3]) 
            r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]][31:24] <= i_wr_data[31:24];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rd_data <= `ZERO_WORD;
    end else if (i_en && !i_wr_en) begin
        r_rd_data <= r_dtcm[i_addr[DTCM_ADDR_WIDTH+1:2]];
    end
end

assign o_rd_data = r_rd_data;

endmodule
