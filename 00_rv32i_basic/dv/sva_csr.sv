`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/18
// Design Name: StepRV_v0
// Module Name: sva_csr
// Description:
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module sva_csr(
    input clk,
    input rst_n,
    input [11:0] i_csr_idx,
    input i_csr_wr_req,
    input exc_raw_illegal_csr_access,
    input req_disp_csr // From EXU, indicates this is a CSR/SYSTEM instruction
);

// Keep this as a small spec mirror instead of reusing csr_regs.is_supported_csr.
// That way the assertion can catch accidental RTL decode changes.
wire spec_csr_supported = (i_csr_idx == `CSR_MSTATUS)     ||
                          (i_csr_idx == `CSR_MISA)        ||
                          (i_csr_idx == `CSR_MTVEC)       ||
                          (i_csr_idx == `CSR_MEPC)        ||
                          (i_csr_idx == `CSR_MCAUSE)      ||
                          (i_csr_idx == `CSR_MTVAL)       ||
                          (i_csr_idx == `CSR_CYCLE)       ||
                          (i_csr_idx == `CSR_CYCLEH)      ||
                          (i_csr_idx == `CSR_MCYCLE)      ||
                          (i_csr_idx == `CSR_MCYCLEH)     ||
                          (i_csr_idx == `CSR_MINSTRET)    ||
                          (i_csr_idx == `CSR_MINSTRETH);

wire spec_system_non_csr = (i_csr_idx == 12'h000) ||
                           (i_csr_idx == 12'h001) ||
                           (i_csr_idx == 12'h302);

// Property to check if an illegal CSR access is correctly flagged
// We only care when a CSR instruction is executed (req_disp_csr is high)
property p_csr_illegal_flag;
    @(posedge clk) disable iff(!rst_n)
    (req_disp_csr && !spec_csr_supported && !spec_system_non_csr) |-> exc_raw_illegal_csr_access;
endproperty

assert property(p_csr_illegal_flag) else $error("[SVA Error] Unsupported CSR access did not raise illegal exception flag.");

// Check that writes to the read-only cycle/cycleh shadow CSRs are rejected.
property p_read_only_csr_write_illegal;
    @(posedge clk) disable iff(!rst_n)
    (req_disp_csr && i_csr_wr_req
     && ((i_csr_idx == `CSR_CYCLE) || (i_csr_idx == `CSR_CYCLEH)))
    |-> exc_raw_illegal_csr_access;
endproperty

assert property(p_read_only_csr_write_illegal)
    else $error("[SVA Error] Write to read-only cycle CSR did not raise illegal exception flag.");

endmodule
