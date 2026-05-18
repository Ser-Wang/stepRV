`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/18
// Design Name: StepRV_v0
// Module Name: csr_regs
// Description:
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module csr_regs(
    input  wire clk,
    input  wire rst_n,
    // Interface with EXU
    input  wire [11:0] i_csr_idx,
    input  wire        i_csr_wr_en,
    input  wire [31:0] i_csr_wr_data,
    output reg  [31:0] o_csr_rd_data,
    output wire        o_csr_ill_exc,
    // Hardware update interfaces
    input  wire        i_instr_ret_en
);

// Registers
reg [31:0] r_mstatus;
reg [31:0] r_mtvec;
reg [31:0] r_mepc;
reg [31:0] r_mcause;
reg [63:0] r_mcycle;
reg [63:0] r_minstret;

// Exception for unsupported CSR access
wire is_supported_csr = (i_csr_idx == `CSR_MSTATUS)     ||
                        (i_csr_idx == `CSR_MTVEC)       ||
                        (i_csr_idx == `CSR_MEPC)        ||
                        (i_csr_idx == `CSR_MCAUSE)      ||
                        (i_csr_idx == `CSR_MCYCLE)      ||
                        (i_csr_idx == `CSR_MCYCLEH)     ||
                        (i_csr_idx == `CSR_MINSTRET)    ||
                        (i_csr_idx == `CSR_MINSTRETH);

// Provide the signal for illegal CSR access
assign o_csr_ill_exc = ~is_supported_csr;

// mcycle increment
wire [63:0] mcycle_nxt = r_mcycle + 1'b1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mcycle <= 64'b0;
    end else begin
        r_mcycle <= mcycle_nxt;
        if (i_csr_wr_en) begin
            if (i_csr_idx == `CSR_MCYCLE)  r_mcycle[31:0]  <= i_csr_wr_data;
            if (i_csr_idx == `CSR_MCYCLEH) r_mcycle[63:32] <= i_csr_wr_data;
        end
    end
end

// minstret increment
wire [63:0] minstret_nxt = r_minstret + {63'b0, i_instr_ret_en};
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_minstret <= 64'b0;
    end else begin
        r_minstret <= minstret_nxt;
        if (i_csr_wr_en) begin
            if (i_csr_idx == `CSR_MINSTRET)  r_minstret[31:0]  <= i_csr_wr_data;
            if (i_csr_idx == `CSR_MINSTRETH) r_minstret[63:32] <= i_csr_wr_data;
        end
    end
end

// Other registers
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mstatus <= 32'b0;
        r_mtvec <= 32'b0;
        r_mepc <= 32'b0;
        r_mcause <= 32'b0;
    end else if (i_csr_wr_en) begin
        case (i_csr_idx)
            `CSR_MSTATUS: r_mstatus <= i_csr_wr_data;
            `CSR_MTVEC:   r_mtvec   <= i_csr_wr_data;
            `CSR_MEPC:    r_mepc    <= i_csr_wr_data;
            `CSR_MCAUSE:  r_mcause  <= i_csr_wr_data;
        endcase
    end
end

// Read logic
always @(*) begin
    case (i_csr_idx)
        `CSR_MSTATUS:   o_csr_rd_data = r_mstatus;
        `CSR_MTVEC:     o_csr_rd_data = r_mtvec;
        `CSR_MEPC:      o_csr_rd_data = r_mepc;
        `CSR_MCAUSE:    o_csr_rd_data = r_mcause;
        `CSR_MCYCLE:    o_csr_rd_data = r_mcycle[31:0];
        `CSR_MCYCLEH:   o_csr_rd_data = r_mcycle[63:32];
        `CSR_MINSTRET:  o_csr_rd_data = r_minstret[31:0];
        `CSR_MINSTRETH: o_csr_rd_data = r_minstret[63:32];
        default:        o_csr_rd_data = 32'b0;
    endcase
end


endmodule
