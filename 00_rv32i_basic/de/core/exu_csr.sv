`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/18
// Design Name: StepRV_v0
// Module Name: exu_csr
// Description:
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module exu_csr(
    input  wire clk,
    input  wire rst_n,
    input  wire [31:0] i_csr_rs1,
    input  wire [`DECINFO_BUS_CSR_WIDTH-1:0] i_dec_info_bus_csr,
    output wire [31:0] o_csr_wrbk_res,
    // Interface to csr_regs
    output wire [11:0] o_csr_idx,
    output wire        o_csr_wr_en,
    output wire [31:0] o_csr_wr_data,
    input  wire [31:0] i_csr_rd_data,
    // Stall and Flush
    input  wire        i_stall,
    input  wire        i_flush
);

wire bru_req_csrrw  = i_dec_info_bus_csr[`DECINFO_CSR_CSRRW];
wire bru_req_csrrs  = i_dec_info_bus_csr[`DECINFO_CSR_CSRRS];
wire bru_req_csrrc  = i_dec_info_bus_csr[`DECINFO_CSR_CSRRC];
wire bru_req_rs1imm = i_dec_info_bus_csr[`DECINFO_CSR_RS1IMM];
wire [4:0] zimm = i_dec_info_bus_csr[`DECINFO_CSR_ZIMM];
wire rs1_is_x0 = i_dec_info_bus_csr[`DECINFO_CSR_RS1X0];
wire [11:0] csr_idx = i_dec_info_bus_csr[`DECINFO_CSR_CSRIDX];
    
assign o_csr_idx = csr_idx;
    
// Read data goes to write-back
assign o_csr_wrbk_res = i_csr_rd_data;
    
// Operand selection
wire [31:0] operand = bru_req_rs1imm ? {27'b0, zimm} : i_csr_rs1;
    
// Is it a pure read?
// csrrs/csrrc with rs1=x0 (or zimm=0) should not write
wire rs1_is_zero = bru_req_rs1imm ? (zimm == 5'b0) : rs1_is_x0;
wire bru_req_pure_read = (bru_req_csrrs | bru_req_csrrc) & rs1_is_zero;
    
// Write enable
wire req_disp_csr = (i_dec_info_bus_csr[`DECINFO_GRP] == `DECINFO_GRP_CSR);
wire csr_write_intent = req_disp_csr & (bru_req_csrrw | bru_req_csrrs | bru_req_csrrc) & (~bru_req_pure_read);
    
// Gate with stall and flush to prevent multiple writes and flushed writes
assign o_csr_wr_en = csr_write_intent & (~i_stall) & (~i_flush);
    
// Write data calculation
wire [31:0] wr_data_csrrw = operand;
wire [31:0] wr_data_csrrs = i_csr_rd_data | operand;
wire [31:0] wr_data_csrrc = i_csr_rd_data & (~operand);
    
assign o_csr_wr_data = ({32{bru_req_csrrw}} & wr_data_csrrw) |
                       ({32{bru_req_csrrs}} & wr_data_csrrs) |
                       ({32{bru_req_csrrc}} & wr_data_csrrc);


endmodule
