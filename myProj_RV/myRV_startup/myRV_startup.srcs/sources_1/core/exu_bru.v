`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/27 01:13:41
// Design Name: 
// Module Name: exu_bru
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "../defines/config.v"

module exu_bru(
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_bru_rs1,
    input wire [31:0] i_bru_rs2,
    input wire [31:0] i_bru_imm,
    input wire [31:0] i_pc,
    input wire [`DECINFO_BUS_BRU_WIDTH-1:0] i_dec_info_bus_bru,
    output wire [31:0] o_pc_jump,
    output wire o_jump_flag,
    output wire [31:0] o_bru_req_result // jal, jalr has to wrbk pc+4 to rd.
    );

// ----------------        dec_info debus        ---------------- //
// ---- dec_info debus
wire bru_req_jump    = i_dec_info_bus_bru[`DECINFO_BRU_JUMP  ];
wire bru_req_beq     = i_dec_info_bus_bru[`DECINFO_BRU_BEQ   ];
wire bru_req_bne     = i_dec_info_bus_bru[`DECINFO_BRU_BNE   ];
wire bru_req_blt     = i_dec_info_bus_bru[`DECINFO_BRU_BLT   ];
wire bru_req_bge     = i_dec_info_bus_bru[`DECINFO_BRU_BGE   ];
wire bru_req_bltu    = i_dec_info_bus_bru[`DECINFO_BRU_BLTU  ];
wire bru_req_bgeu    = i_dec_info_bus_bru[`DECINFO_BRU_BGEU  ];
wire bru_req_fence   = i_dec_info_bus_bru[`DECINFO_BRU_FENCE ];
wire bru_req_fence_i = i_dec_info_bus_bru[`DECINFO_BRU_FENCEI];

wire bru_req_info_bxx = i_dec_info_bus_bru[`DECINFO_BRU_BXX];

// adder, serve as a subber
wire [31+1:0] adder_in1, adder_in2;
wire op_usign = bru_req_bltu | bru_req_bgeu;
wire [31+1:0] adder_result;
assign adder_in1 = {(~op_usign & i_bru_rs1[31]), i_bru_rs1};
assign adder_in2 = {(~op_usign & i_bru_rs2[31]), i_bru_rs2};
assign adder_result = adder_in1 + (~adder_in2) + 1'b1; // 1'b1 is cin_0, making it a subber

wire comp_lessthan = adder_result[32];
wire comp_equal = (i_bru_rs1 == i_bru_rs2) ? 1'b1 : 1'b0;
wire comp_ne = ~comp_equal;

wire [31:0] pc_add4 = i_pc + 3'd4;





endmodule
