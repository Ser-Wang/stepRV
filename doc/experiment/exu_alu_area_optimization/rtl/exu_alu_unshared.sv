`timescale 1ns / 1ps
`include "config.v"

// Area experiment baseline: describe every arithmetic/shift operation directly.
// The RTL intentionally does not manually share add/sub/compare or shift logic.
module exu_alu_unshared(
    input  wire [31:0] i_alu_rs1,
    input  wire [31:0] i_alu_rs2,
    input  wire [31:0] i_alu_imm,
    input  wire [31:0] i_alu_pc,
    input  wire [`DECINFO_BUS_ALU_WIDTH-1:0] i_dec_info_bus_alu,
    output wire [31:0] o_alu_wb_data
    );

wire [31:0] alu_req_op1 = i_dec_info_bus_alu[`DECINFO_ALU_OP1PC] ? i_alu_pc  : i_alu_rs1;
wire [31:0] alu_req_op2 = i_dec_info_bus_alu[`DECINFO_ALU_OP2IMM] ? i_alu_imm : i_alu_rs2;

wire dec_req_add  = i_dec_info_bus_alu[`DECINFO_ALU_ADD];
wire dec_req_sub  = i_dec_info_bus_alu[`DECINFO_ALU_SUB];
wire dec_req_sll  = i_dec_info_bus_alu[`DECINFO_ALU_SLL];
wire dec_req_slt  = i_dec_info_bus_alu[`DECINFO_ALU_SLT];
wire dec_req_sltu = i_dec_info_bus_alu[`DECINFO_ALU_SLTU];
wire dec_req_xor  = i_dec_info_bus_alu[`DECINFO_ALU_XOR];
wire dec_req_srl  = i_dec_info_bus_alu[`DECINFO_ALU_SRL];
wire dec_req_sra  = i_dec_info_bus_alu[`DECINFO_ALU_SRA];
wire dec_req_or   = i_dec_info_bus_alu[`DECINFO_ALU_OR];
wire dec_req_and  = i_dec_info_bus_alu[`DECINFO_ALU_AND];
wire dec_req_lui  = i_dec_info_bus_alu[`DECINFO_ALU_LUI];

// Deliberately straightforward, independent operators.
wire [31:0] alu_result_add  = alu_req_op1 + alu_req_op2;
wire [31:0] alu_result_sub  = alu_req_op1 - alu_req_op2;
wire [31:0] alu_result_sll  = alu_req_op1 << alu_req_op2[4:0];
wire [31:0] alu_result_slt  = ($signed(alu_req_op1) < $signed(alu_req_op2)) ? 32'd1 : 32'd0;
wire [31:0] alu_result_sltu = (alu_req_op1 < alu_req_op2) ? 32'd1 : 32'd0;
wire [31:0] alu_result_xor  = alu_req_op1 ^ alu_req_op2;
wire [31:0] alu_result_srl  = alu_req_op1 >> alu_req_op2[4:0];
wire [31:0] alu_result_sra  = $signed(alu_req_op1) >>> alu_req_op2[4:0];
wire [31:0] alu_result_or   = alu_req_op1 | alu_req_op2;
wire [31:0] alu_result_and  = alu_req_op1 & alu_req_op2;
wire [31:0] alu_result_lui  = alu_req_op2;

assign o_alu_wb_data = ({32{dec_req_add }} & alu_result_add )
                     | ({32{dec_req_sub }} & alu_result_sub )
                     | ({32{dec_req_sll }} & alu_result_sll )
                     | ({32{dec_req_slt }} & alu_result_slt )
                     | ({32{dec_req_sltu}} & alu_result_sltu)
                     | ({32{dec_req_xor }} & alu_result_xor )
                     | ({32{dec_req_srl }} & alu_result_srl )
                     | ({32{dec_req_sra }} & alu_result_sra )
                     | ({32{dec_req_or  }} & alu_result_or  )
                     | ({32{dec_req_and }} & alu_result_and )
                     | ({32{dec_req_lui }} & alu_result_lui );

endmodule
