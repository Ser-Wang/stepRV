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
    output wire        o_exc_raw_illegal_csr_access,
    output wire [31:0] o_mtvec,
    output wire [31:0] o_mepc,
    // Hardware update interfaces
    input  wire        i_exc_req,
    input  wire [31:0] i_exc_epc,
    input  wire [31:0] i_exc_cause,
    input  wire [31:0] i_exc_tval,
    input  wire        i_trap_ret_req,
    input  wire        i_instr_ret_en
);

// Registers
reg [31:0] r_mstatus;
reg [31:0] r_mtvec;
reg [31:0] r_mepc;
reg [31:0] r_mcause;
reg [31:0] r_mtval;
reg [63:0] r_mcycle;
reg [63:0] r_minstret;

// Machine-level privileged CSRs
wire csr_sel_mstatus   = (i_csr_idx == `CSR_MSTATUS)   ? 1'b1 : 1'b0;
wire csr_sel_misa      = (i_csr_idx == `CSR_MISA)      ? 1'b1 : 1'b0;
wire csr_sel_mtvec     = (i_csr_idx == `CSR_MTVEC)     ? 1'b1 : 1'b0;
wire csr_sel_mepc      = (i_csr_idx == `CSR_MEPC)      ? 1'b1 : 1'b0;
wire csr_sel_mcause    = (i_csr_idx == `CSR_MCAUSE)    ? 1'b1 : 1'b0;
wire csr_sel_mtval     = (i_csr_idx == `CSR_MTVAL)     ? 1'b1 : 1'b0;
wire csr_sel_mcycle    = (i_csr_idx == `CSR_MCYCLE)    ? 1'b1 : 1'b0;
wire csr_sel_mcycleh   = (i_csr_idx == `CSR_MCYCLEH)   ? 1'b1 : 1'b0;
wire csr_sel_minstret  = (i_csr_idx == `CSR_MINSTRET)  ? 1'b1 : 1'b0;
wire csr_sel_minstreth = (i_csr_idx == `CSR_MINSTRETH) ? 1'b1 : 1'b0;

// Unprivileged read-only counter CSRs
// cycle/cycleh are shadow views of the physical mcycle counter. They do not
// have independent storage: reads return r_mcycle, while writes are illegal.
// mcycle/mcycleh are the machine-mode writable views of the same counter.
wire csr_sel_cycle     = (i_csr_idx == `CSR_CYCLE)     ? 1'b1 : 1'b0;
wire csr_sel_cycleh    = (i_csr_idx == `CSR_CYCLEH)    ? 1'b1 : 1'b0;


wire is_supported_machine_csr = csr_sel_mstatus  | csr_sel_misa     |
                                csr_sel_mtvec    |
                                csr_sel_mepc     | csr_sel_mcause   |
                                csr_sel_mtval    |
                                csr_sel_mcycle   | csr_sel_mcycleh  |
                                csr_sel_minstret | csr_sel_minstreth;

wire is_supported_unpriv_csr = csr_sel_cycle | csr_sel_cycleh;

wire is_supported_csr = is_supported_machine_csr | is_supported_unpriv_csr;

// Raw illegal CSR access indication. EXU gates it with a real CSR op request.
assign o_exc_raw_illegal_csr_access = (~is_supported_csr)
                                    | (i_csr_wr_en & (csr_sel_cycle | csr_sel_cycleh));
assign o_mtvec = r_mtvec;
assign o_mepc = r_mepc;

// mcycle increment
wire [63:0] mcycle_nxt = r_mcycle + 1'b1;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_mcycle <= 64'b0;
    end else begin
        r_mcycle <= mcycle_nxt;
        if (i_csr_wr_en) begin
            if (csr_sel_mcycle)  r_mcycle[31:0]  <= i_csr_wr_data;
            if (csr_sel_mcycleh) r_mcycle[63:32] <= i_csr_wr_data;
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
            if (csr_sel_minstret)  r_minstret[31:0]  <= i_csr_wr_data;
            if (csr_sel_minstreth) r_minstret[63:32] <= i_csr_wr_data;
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
        r_mtval <= 32'b0;
    end else if (i_exc_req) begin
        r_mepc <= i_exc_epc;
        r_mcause <= i_exc_cause;
        r_mtval <= i_exc_tval;
        r_mstatus[7] <= r_mstatus[3]; // MPIE <= MIE
        r_mstatus[3] <= 1'b0;         // MIE  <= 0
        r_mstatus[12:11] <= 2'b11;    // MPP  <= M-mode
    end else if (i_trap_ret_req) begin
        r_mstatus[3] <= r_mstatus[7]; // MIE  <= MPIE
        r_mstatus[7] <= 1'b1;         // MPIE <= 1
        r_mstatus[12:11] <= 2'b00;    // MPP  <= U-mode per spec
    end else if (i_csr_wr_en) begin
        if (csr_sel_mstatus) r_mstatus <= i_csr_wr_data;
        if (csr_sel_mtvec)   r_mtvec   <= i_csr_wr_data;
        if (csr_sel_mepc)    r_mepc    <= i_csr_wr_data;
        if (csr_sel_mcause)  r_mcause  <= i_csr_wr_data;
        if (csr_sel_mtval)   r_mtval   <= i_csr_wr_data;
    end
end

// Read logic
// always @(*) begin
//     case (i_csr_idx)
//         `CSR_MSTATUS:   o_csr_rd_data = r_mstatus;
//         `CSR_MTVEC:     o_csr_rd_data = r_mtvec;
//         `CSR_MEPC:      o_csr_rd_data = r_mepc;
//         `CSR_MCAUSE:    o_csr_rd_data = r_mcause;
//         `CSR_MCYCLE:    o_csr_rd_data = r_mcycle[31:0];
//         `CSR_MCYCLEH:   o_csr_rd_data = r_mcycle[63:32];
//         `CSR_MINSTRET:  o_csr_rd_data = r_minstret[31:0];
//         `CSR_MINSTRETH: o_csr_rd_data = r_minstret[63:32];
//         default:        o_csr_rd_data = 32'b0;
//     endcase
// end

always @(*) begin
    // Machine-level privileged CSRs
    o_csr_rd_data = ({32{csr_sel_mstatus}}   & r_mstatus)
                  | ({32{csr_sel_misa}}      & 32'h4000_0100)
                  | ({32{csr_sel_mtvec}}     & r_mtvec)
                  | ({32{csr_sel_mepc}}      & r_mepc)
                  | ({32{csr_sel_mcause}}    & r_mcause)
                  | ({32{csr_sel_mtval}}     & r_mtval)
                  | ({32{csr_sel_mcycle}}    & r_mcycle[31:0])
                  | ({32{csr_sel_mcycleh}}   & r_mcycle[63:32])
                  | ({32{csr_sel_minstret}}  & r_minstret[31:0])
                  | ({32{csr_sel_minstreth}} & r_minstret[63:32])
    // Unprivileged shadow views of mcycle
                  | ({32{csr_sel_cycle}}     & r_mcycle[31:0])
                  | ({32{csr_sel_cycleh}}    & r_mcycle[63:32]);
end

endmodule
