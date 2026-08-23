`timescale 1ns / 1ps
`include "config.v"

// Area experiment variant: identical sharing structure to exu_alu, but without
// the operand-isolation AND masks on the adder, XOR unit, and shared shifter.
module exu_alu_no_isolation(
    input  wire [31:0] i_alu_rs1,
    input  wire [31:0] i_alu_rs2,
    input  wire [31:0] i_alu_imm,
    input  wire [31:0] i_alu_pc,
    input  wire [`DECINFO_BUS_ALU_WIDTH-1:0] i_dec_info_bus_alu,
    output wire [31:0] o_alu_wb_data
    );

wire [31:0] alu_req_op1 = i_dec_info_bus_alu[`DECINFO_ALU_OP1PC] ? i_alu_pc  : i_alu_rs1;
wire [31:0] alu_req_op2 = i_dec_info_bus_alu[`DECINFO_ALU_OP2IMM] ? i_alu_imm : i_alu_rs2;

wire dec_req_sub    = i_dec_info_bus_alu[`DECINFO_ALU_SUB];
wire dec_req_addsub = i_dec_info_bus_alu[`DECINFO_ALU_ADD] | i_dec_info_bus_alu[`DECINFO_ALU_SUB];
wire dec_req_xor    = i_dec_info_bus_alu[`DECINFO_ALU_XOR];
wire dec_req_or     = i_dec_info_bus_alu[`DECINFO_ALU_OR];
wire dec_req_and    = i_dec_info_bus_alu[`DECINFO_ALU_AND];
wire dec_req_sll    = i_dec_info_bus_alu[`DECINFO_ALU_SLL];
wire dec_req_srl    = i_dec_info_bus_alu[`DECINFO_ALU_SRL];
wire dec_req_sra    = i_dec_info_bus_alu[`DECINFO_ALU_SRA];
wire dec_req_slt    = i_dec_info_bus_alu[`DECINFO_ALU_SLT];
wire dec_req_sltu   = i_dec_info_bus_alu[`DECINFO_ALU_SLTU];
wire dec_req_slttu  = dec_req_slt | dec_req_sltu;
wire dec_req_lui    = i_dec_info_bus_alu[`DECINFO_ALU_LUI];
wire flag_op_unsigned = dec_req_sltu;

wire [32:0] adder_extend_op1 = {((~flag_op_unsigned) & alu_req_op1[31]), alu_req_op1};
wire [32:0] adder_extend_op2 = {((~flag_op_unsigned) & alu_req_op2[31]), alu_req_op2};
wire        flag_adder_sub   = dec_req_sub | dec_req_slttu;
wire [32:0] adder_in2        = adder_extend_op2 ^ {33{flag_adder_sub}};
wire [32:0] adder_result     = adder_extend_op1 + adder_in2 + flag_adder_sub;
wire [31:0] alu_result_addsub = adder_result[31:0];
wire [31:0] alu_result_slttu  = (dec_req_slttu & adder_result[32]) ? 32'd1 : 32'd0;

wire [31:0] alu_result_xor = alu_req_op1 ^ alu_req_op2;
wire [31:0] alu_result_or  = alu_req_op1 | alu_req_op2;
wire [31:0] alu_result_and = alu_req_op1 & alu_req_op2;

wire [31:0] reversed_op1 = {
    alu_req_op1[00], alu_req_op1[01], alu_req_op1[02], alu_req_op1[03],
    alu_req_op1[04], alu_req_op1[05], alu_req_op1[06], alu_req_op1[07],
    alu_req_op1[08], alu_req_op1[09], alu_req_op1[10], alu_req_op1[11],
    alu_req_op1[12], alu_req_op1[13], alu_req_op1[14], alu_req_op1[15],
    alu_req_op1[16], alu_req_op1[17], alu_req_op1[18], alu_req_op1[19],
    alu_req_op1[20], alu_req_op1[21], alu_req_op1[22], alu_req_op1[23],
    alu_req_op1[24], alu_req_op1[25], alu_req_op1[26], alu_req_op1[27],
    alu_req_op1[28], alu_req_op1[29], alu_req_op1[30], alu_req_op1[31]
};
wire [31:0] shifter_in1   = dec_req_sll ? alu_req_op1 : reversed_op1;
wire [4:0]  shifter_in2   = alu_req_op2[4:0];
wire [31:0] shifter_result = shifter_in1 << shifter_in2;
wire [31:0] mask_sign_extention = 32'hffff_ffff >> shifter_in2;
wire [31:0] alu_result_sll = shifter_result;
wire [31:0] alu_result_srl = {
    shifter_result[00], shifter_result[01], shifter_result[02], shifter_result[03],
    shifter_result[04], shifter_result[05], shifter_result[06], shifter_result[07],
    shifter_result[08], shifter_result[09], shifter_result[10], shifter_result[11],
    shifter_result[12], shifter_result[13], shifter_result[14], shifter_result[15],
    shifter_result[16], shifter_result[17], shifter_result[18], shifter_result[19],
    shifter_result[20], shifter_result[21], shifter_result[22], shifter_result[23],
    shifter_result[24], shifter_result[25], shifter_result[26], shifter_result[27],
    shifter_result[28], shifter_result[29], shifter_result[30], shifter_result[31]
};
wire [31:0] alu_result_sra = (alu_result_srl & mask_sign_extention)
                           | ({32{alu_req_op1[31]}} & ~mask_sign_extention);
wire [31:0] alu_result_lui = alu_req_op2;

assign o_alu_wb_data = ({32{dec_req_addsub}} & alu_result_addsub)
                     | ({32{dec_req_xor   }} & alu_result_xor   )
                     | ({32{dec_req_or    }} & alu_result_or    )
                     | ({32{dec_req_and   }} & alu_result_and   )
                     | ({32{dec_req_sll   }} & alu_result_sll   )
                     | ({32{dec_req_srl   }} & alu_result_srl   )
                     | ({32{dec_req_sra   }} & alu_result_sra   )
                     | ({32{dec_req_slttu }} & alu_result_slttu )
                     | ({32{dec_req_lui   }} & alu_result_lui   );

endmodule
