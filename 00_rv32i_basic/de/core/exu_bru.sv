`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/02/27
// Design Name: StepRV_v0
// Module Name: exu_bru
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module exu_bru(
    input wire [31:0] i_bru_rs1,
    input wire [31:0] i_bru_rs2,
    input wire [31:0] i_bru_imm,
    input wire [31:0] i_bru_pc,
    input wire [`DECINFO_BUS_BRU_WIDTH-1:0] i_dec_info_bus_bru,
    output wire [31:0] o_bru_wb_data, // jal, jalr write pc+4 to rd.
    output wire [31:0] o_redirect_pcnext_bru,
    output wire o_redirect_req_bru,
    output wire o_exc_req_instr_addr_misaligned_bru,
    output wire [31:0] o_exc_tval_instr_addr_misaligned_bru
    );

// ----------------        dec_info debus        ---------------- //
// ---- dec_info debus
wire bru_req_jal     = i_dec_info_bus_bru[`DECINFO_BRU_JAL   ];
wire bru_req_jalr    = i_dec_info_bus_bru[`DECINFO_BRU_JALR  ];
wire bru_req_beq     = i_dec_info_bus_bru[`DECINFO_BRU_BEQ   ];
wire bru_req_bne     = i_dec_info_bus_bru[`DECINFO_BRU_BNE   ];
wire bru_req_blt     = i_dec_info_bus_bru[`DECINFO_BRU_BLT   ];
wire bru_req_bge     = i_dec_info_bus_bru[`DECINFO_BRU_BGE   ];
wire bru_req_bltu    = i_dec_info_bus_bru[`DECINFO_BRU_BLTU  ];
wire bru_req_bgeu    = i_dec_info_bus_bru[`DECINFO_BRU_BGEU  ];
wire bru_req_fence   = i_dec_info_bus_bru[`DECINFO_BRU_FENCE ];
wire bru_req_fence_i = i_dec_info_bus_bru[`DECINFO_BRU_FENCEI];

wire bru_req_info_jump = i_dec_info_bus_bru[`DECINFO_BRU_JUMP];
wire bru_req_info_bxx = i_dec_info_bus_bru[`DECINFO_BRU_BXX];
wire bru_req_info_comp = bru_req_info_bxx;

wire bru_req_addr_cal = bru_req_info_jump | bru_req_info_bxx;

// adder, serve as a subber to compare
wire [31:0] adder_opr1, adder_opr2;
wire [31+1:0] adder_in1, adder_in2;
wire op_usign = bru_req_bltu | bru_req_bgeu;
wire [31+1:0] adder_result;
// assign adder_opr1 = bru_req_info_comp ? i_bru_rs1 : i_bru_pc;
// assign adder_opr2 = bru_req_info_comp ? i_bru_rs2 : `XLEN'd4;
assign adder_opr1 = i_bru_rs1;
assign adder_opr2 = i_bru_rs2;
assign adder_in1 = {(~op_usign & adder_opr1[31]), adder_opr1};
assign adder_in2 = {(~op_usign & adder_opr2[31]), adder_opr2};
assign adder_result = adder_in1 + (~adder_in2) + 1'b1; // 1'b1 is cin_0, making it a subber

// ---- compare results
wire comp_res_eq  = (i_bru_rs1 == i_bru_rs2) ? 1'b1 : 1'b0;
wire comp_res_ne  = ~comp_res_eq;
wire comp_res_lt  =  adder_result[32];
wire comp_res_ltu =  adder_result[32];
wire comp_res_ge  = ~adder_result[32];
wire comp_res_geu = ~adder_result[32];

wire comp_res = (bru_req_beq  & comp_res_eq )   // those comp_results may have multiple "1"s simultaneously, so operand isolation is needed
              | (bru_req_bne  & comp_res_ne )   // comp_req == 1 means need jump, otherwise don't jump.
              | (bru_req_blt  & comp_res_lt )
              | (bru_req_bge  & comp_res_ge )
              | (bru_req_bltu & comp_res_ltu)
              | (bru_req_bgeu & comp_res_geu) ;

// ---- generate pc_addr

wire [31:0] adder_jump_opr1 = i_dec_info_bus_bru[`DECINFO_BRU_JALR] ? i_bru_rs1 : i_bru_pc; // only when jalr is rs1+imm, others are all pc+imm.
wire [31:0] adder_jump_opr2 = i_bru_imm;    // Operands are already gated during dispatch from EXU to EXU_BRU

wire [31:0] adder_jumpaddr_raw = adder_jump_opr1 + adder_jump_opr2; // bxx
wire [31:0] adder_jumpaddr = bru_req_jalr ? {adder_jumpaddr_raw[31:1], 1'b0} : adder_jumpaddr_raw;
// RISC-V JALR clears target bit[0]. JAL/branch targets are PC + imm, whose imm[0] is naturally 1'b0; JALR targets come from rs1 + imm, so bit[0] is forced to 1'b0 and may be used by software as a flag.
// bit[1:0] is still checked below for RV32I 4-byte alignment.
wire [31:0] pc_add4 = i_bru_pc + `XLEN'd4;


// ---- 
wire jump_taken = (bru_req_info_jump | bru_req_fence_i) ? 1'b1 : comp_res;
assign o_exc_req_instr_addr_misaligned_bru = jump_taken & (adder_jumpaddr[1:0] != 2'b00) & (~bru_req_fence_i);
assign o_exc_tval_instr_addr_misaligned_bru = adder_jumpaddr;

assign o_redirect_req_bru = jump_taken & (~o_exc_req_instr_addr_misaligned_bru);
assign o_bru_wb_data = pc_add4;   // only jal, jalr write rd
assign o_redirect_pcnext_bru = (bru_req_fence_i) ? pc_add4 :        // Note: when req_fence_i = 1'b1, redirect_req is also 1'b1.
                               (o_redirect_req_bru) ? adder_jumpaddr : pc_add4;



endmodule
