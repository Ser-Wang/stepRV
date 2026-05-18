`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/18
// Design Name: StepRV_v0
// Module Name: csr_sva
// Description:
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module csr_sva(
    input clk,
    input rst_n,
    input [11:0] i_csr_idx,
    input i_csr_wr_en,
    input o_csr_ill_exc,
    input req_disp_csr // From EXU, indicates this is a CSR instruction
);

wire is_supported = (i_csr_idx == `CSR_MSTATUS)     ||
                    (i_csr_idx == `CSR_MTVEC)       ||
                    (i_csr_idx == `CSR_MEPC)        ||
                    (i_csr_idx == `CSR_MCAUSE)      ||
                    (i_csr_idx == `CSR_MCYCLE)      ||
                    (i_csr_idx == `CSR_MCYCLEH)     ||
                    (i_csr_idx == `CSR_MINSTRET)    ||
                    (i_csr_idx == `CSR_MINSTRETH);

// Property to check if an illegal CSR access is correctly flagged
// We only care when a CSR instruction is executed (req_disp_csr is high)
property p_csr_illegal_flag;
    @(posedge clk) disable iff(!rst_n)
    (req_disp_csr && !is_supported) |-> o_csr_ill_exc;
endproperty

assert property(p_csr_illegal_flag) else $error("SVA ERROR: Unsupported CSR access did not raise illegal exception flag.");

endmodule
