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
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_bru_rs1,
    input wire [31:0] i_bru_rs2,
    input wire [31:0] i_bru_imm,
    input wire [31:0] i_bru_pc,
    input wire [`DECINFO_BUS_BRU_WIDTH-1:0] i_dec_info_bus_bru,
    output wire [31:0] o_bru_wrbk_data, // jal, jalr has to wrbk pc+4 to rd.
    output wire [31:0] o_pc_next_bru,
    output wire o_jump_flag
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
// assign adder_opr2 = bru_req_info_comp ? i_bru_rs2 : `XWIDTH'd4;
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

wire [31:0] adder_jumpaddr = adder_jump_opr1 + adder_jump_opr2; // bxx

wire [31:0] pc_add4 = i_bru_pc + `XWIDTH'd4;


// ---- 
assign o_jump_flag = (bru_req_info_jump | bru_req_fence_i) ? 1'b1 : comp_res;
assign o_bru_wrbk_data = pc_add4;   // only jal, jalr need to wrbk rd
assign o_pc_next_bru = (bru_req_fence_i) ? pc_add4 :        // Note: when req_fence_i = 1'b1, jump_flag is also 1'b1.
                       (o_jump_flag)     ? adder_jumpaddr : pc_add4;



endmodule
