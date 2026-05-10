`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/24 18:43:15
// Design Name: 
// Module Name: idu
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
`include "config.v"

module idu(
    input wire clk,
    input wire rst_n,
    input wire i_stall,
    input wire i_flush,
    input wire [31:0] i_instr,
    input wire [31:0] i_pc_if,
    output wire [`RFIDX_WIDTH-1:0] o_dec_rs1idx,
    output wire [`RFIDX_WIDTH-1:0] o_dec_rs2idx,
    output wire [`RFIDX_WIDTH-1:0] o_dec_rdidx,
    output wire [31:0] o_dec_imm,
    output wire [`DECINFO_BUS_WIDTH-1:0] o_dec_info_bus_id,
    output wire o_dec_rdwen_id,
    output wire o_need_rs1_idu,
    output wire o_need_rs2_idu,
    // Pipeline Reg Output
    output wire [31:0] o_instr_id,
    output wire [31:0] o_pc_id
    );

// ===========================================================================
////********    Pipeline Regs    ********////
reg [31:0] r_instr_id;
reg [31:0] r_pc_id;

assign o_instr_id = r_instr_id;
assign o_pc_id = r_pc_id;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_instr_id <= 32'b0;
    end
    else if (i_flush) begin
        r_instr_id <= `INSTR_NOP;
    end
    else if(!i_stall) begin
        r_instr_id <= i_instr;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_pc_id <= 32'b0;
    end
    else if(!i_stall) begin
        r_pc_id <= i_pc_if;
    end
end

////////****   ↑ Pipeline Regs ↑   ****////////


// =============================================================
// ----------------        Decode        ---------------- //
wire [31:0] rv32_instr = r_instr_id;
wire [15:0] rv16_instr = r_instr_id[15:0]; // reserved

wire [6:0] instr_opcode   = rv32_instr[6:0];
wire [4:0] instr32_rd     = rv32_instr[11:7];
wire [2:0] instr32_func3  = rv32_instr[14:12];
wire [4:0] instr32_rs1    = rv32_instr[19:15];
wire [4:0] instr32_rs2    = rv32_instr[24:20];
wire [6:0] instr32_func7  = rv32_instr[31:25];

// opcode   opcode[1:0]=2'b11 在rv32i阶段是确定的，无需考虑
wire dec_opcode_6_5_00 = (instr_opcode[6:5] == 2'b00);
wire dec_opcode_6_5_01 = (instr_opcode[6:5] == 2'b01);
wire dec_opcode_6_5_10 = (instr_opcode[6:5] == 2'b10);
wire dec_opcode_6_5_11 = (instr_opcode[6:5] == 2'b11);
wire dec_opcode_4_2_000 = (instr_opcode[4:2] == 3'b000);
wire dec_opcode_4_2_001 = (instr_opcode[4:2] == 3'b001);
wire dec_opcode_4_2_010 = (instr_opcode[4:2] == 3'b010);
wire dec_opcode_4_2_011 = (instr_opcode[4:2] == 3'b011);
wire dec_opcode_4_2_100 = (instr_opcode[4:2] == 3'b100);
wire dec_opcode_4_2_101 = (instr_opcode[4:2] == 3'b101);
wire dec_opcode_4_2_110 = (instr_opcode[4:2] == 3'b110);
wire dec_opcode_4_2_111 = (instr_opcode[4:2] == 3'b111);
wire dec_opcode_1_0_00 = (instr_opcode[1:0] == 2'b00);  // reserved for rv16("C"?)
wire dec_opcode_1_0_01 = (instr_opcode[1:0] == 2'b01);  // reserved for rv16("C"?)
wire dec_opcode_1_0_10 = (instr_opcode[1:0] == 2'b10);  // reserved for rv16("C"?)
wire dec_opcode_1_0_11 = (instr_opcode[1:0] == 2'b11);  // rv32i, all

// func3
wire dec_rv32_func3_000 = (instr32_func3 == 3'b000);
wire dec_rv32_func3_001 = (instr32_func3 == 3'b001);
wire dec_rv32_func3_010 = (instr32_func3 == 3'b010);
wire dec_rv32_func3_011 = (instr32_func3 == 3'b011);
wire dec_rv32_func3_100 = (instr32_func3 == 3'b100);
wire dec_rv32_func3_101 = (instr32_func3 == 3'b101);
wire dec_rv32_func3_110 = (instr32_func3 == 3'b110);
wire dec_rv32_func3_111 = (instr32_func3 == 3'b111);

// func7
wire dec_rv32_func7_0000000 = (instr32_func7 == 7'b0000000);
wire dec_rv32_func7_0100000 = (instr32_func7 == 7'b0100000);

// To be considered
//   wire rv32_rs1_x0 = (rv32_rs1 == 5'b00000);
//   wire rv32_rs2_x0 = (rv32_rs2 == 5'b00000);
//   wire rv32_rs2_x1 = (rv32_rs2 == 5'b00001);
//   wire rv32_rd_x0  = (rv32_rd  == 5'b00000);
//   wire rv32_rd_x2  = (rv32_rd  == 5'b00010);

//   wire rv16_rs1_x0 = (rv16_rs1 == 5'b00000);
//   wire rv16_rs2_x0 = (rv16_rs2 == 5'b00000);
//   wire rv16_rd_x0  = (rv16_rd  == 5'b00000);
//   wire rv16_rd_x2  = (rv16_rd  == 5'b00010);

//   wire rv32_rs1_x31 = (rv32_rs1 == 5'b11111);
//   wire rv32_rs2_x31 = (rv32_rs2 == 5'b11111);
//   wire rv32_rd_x31  = (rv32_rd  == 5'b11111);

assign o_dec_rs1idx = instr32_rs1;
assign o_dec_rs2idx = instr32_rs2;
assign o_dec_rdidx = instr32_rd;

wire dec_rv32_rs1_x0 = (instr32_rs1 == 5'b00000);
wire dec_rv32_rs2_x0 = (instr32_rs2 == 5'b00000);
wire dec_rv32_rs2_x1 = (instr32_rs2 == 5'b00001); // for what
wire dec_rv32_rd_x0  = (instr32_rd == 5'b00000);
wire dec_rv32_rd_x2  = (instr32_rd == 5'b00010);  // for what


////************    Instr types decode    ************////
wire dec_rv32i_arithm_type  = dec_opcode_6_5_01 & dec_opcode_4_2_100 & dec_opcode_1_0_11; // R-type, arithmetic operations.
wire dec_rv32i_arithm_imm_type = dec_opcode_6_5_00 & dec_opcode_4_2_100 & dec_opcode_1_0_11; // I-type, arithmetic operations.
wire dec_rv32i_load_type    = dec_opcode_6_5_00 & dec_opcode_4_2_000 & dec_opcode_1_0_11; // I-type, loads.
wire dec_rv32i_store_type   = dec_opcode_6_5_01 & dec_opcode_4_2_000 & dec_opcode_1_0_11; // S-type, stores.
wire dec_rv32i_branch_type  = dec_opcode_6_5_11 & dec_opcode_4_2_000 & dec_opcode_1_0_11; // S-type, stores.
wire dec_rv32i_miscmem_type = dec_opcode_6_5_00 & dec_opcode_4_2_011 & dec_opcode_1_0_11; // I-type, "fence", "fence.i".
wire dec_rv32i_system_type  = dec_opcode_6_5_11 & dec_opcode_4_2_100 & dec_opcode_1_0_11; // I-type, csrs, "ecall", "ebreak".

wire dec_rv32i_csr_type     = dec_rv32i_system_type & (~dec_rv32_func3_000);    // part of "system" type, func3_000 is for "ecall", "ebreak".
wire dec_rv32i_ecall_ebreak = dec_rv32i_system_type & dec_rv32_func3_000;


////************    Specific Instruction decode    ************////
wire dec_rv32i_lui   = dec_opcode_6_5_01 & dec_opcode_4_2_101 & dec_opcode_1_0_11; // U-type, "lui".
wire dec_rv32i_auipc = dec_opcode_6_5_00 & dec_opcode_4_2_101 & dec_opcode_1_0_11; // U-type, "auipc".
wire dec_rv32i_jal   = dec_opcode_6_5_11 & dec_opcode_4_2_011 & dec_opcode_1_0_11; // J-type, "jal".
wire dec_rv32i_jalr  = dec_opcode_6_5_11 & dec_opcode_4_2_001 & dec_opcode_1_0_11; // J-type, "jalr".

// Branch Instructions
wire dec_rv32i_beq  = dec_rv32i_branch_type & dec_rv32_func3_000;
wire dec_rv32i_bne  = dec_rv32i_branch_type & dec_rv32_func3_001;
wire dec_rv32i_blt  = dec_rv32i_branch_type & dec_rv32_func3_100;
wire dec_rv32i_bge  = dec_rv32i_branch_type & dec_rv32_func3_101;
wire dec_rv32i_bltu = dec_rv32i_branch_type & dec_rv32_func3_110;
wire dec_rv32i_bgeu = dec_rv32i_branch_type & dec_rv32_func3_111;

// Load/Store Instructions
wire dec_rv32i_lb   = dec_rv32i_load_type   & dec_rv32_func3_000;
wire dec_rv32i_lh   = dec_rv32i_load_type   & dec_rv32_func3_001;
wire dec_rv32i_lw   = dec_rv32i_load_type   & dec_rv32_func3_010;
wire dec_rv32i_lbu  = dec_rv32i_load_type   & dec_rv32_func3_100;
wire dec_rv32i_lhu  = dec_rv32i_load_type   & dec_rv32_func3_101;

wire dec_rv32i_sb   = dec_rv32i_store_type  & dec_rv32_func3_000;
wire dec_rv32i_sh   = dec_rv32i_store_type  & dec_rv32_func3_001;
wire dec_rv32i_sw   = dec_rv32i_store_type  & dec_rv32_func3_010;

wire [1:0] dec_info_lsu_size = instr32_func3[1:0];
wire dec_info_lsu_unsigned = instr32_func3[2];


// Arithmetic Instructions
wire dec_rv32i_addi  = dec_rv32i_arithm_imm_type & dec_rv32_func3_000;
wire dec_rv32i_slti  = dec_rv32i_arithm_imm_type & dec_rv32_func3_010;
wire dec_rv32i_sltiu = dec_rv32i_arithm_imm_type & dec_rv32_func3_011;
wire dec_rv32i_xori  = dec_rv32i_arithm_imm_type & dec_rv32_func3_100;
wire dec_rv32i_ori   = dec_rv32i_arithm_imm_type & dec_rv32_func3_110;
wire dec_rv32i_andi  = dec_rv32i_arithm_imm_type & dec_rv32_func3_111;
wire dec_rv32i_slli  = dec_rv32i_arithm_imm_type & dec_rv32_func3_001 & (rv32_instr[31:26] == 6'b000000);
wire dec_rv32i_srli  = dec_rv32i_arithm_imm_type & dec_rv32_func3_101 & (rv32_instr[31:26] == 6'b000000);
wire dec_rv32i_srai  = dec_rv32i_arithm_imm_type & dec_rv32_func3_101 & (rv32_instr[31:26] == 6'b010000);

wire dec_rv32i_add  = dec_rv32i_arithm_type & dec_rv32_func3_000 & dec_rv32_func7_0000000;
wire dec_rv32i_sub  = dec_rv32i_arithm_type & dec_rv32_func3_000 & dec_rv32_func7_0100000;
wire dec_rv32i_sll  = dec_rv32i_arithm_type & dec_rv32_func3_001 & dec_rv32_func7_0000000;
wire dec_rv32i_slt  = dec_rv32i_arithm_type & dec_rv32_func3_010 & dec_rv32_func7_0000000;
wire dec_rv32i_sltu = dec_rv32i_arithm_type & dec_rv32_func3_011 & dec_rv32_func7_0000000;
wire dec_rv32i_xor  = dec_rv32i_arithm_type & dec_rv32_func3_100 & dec_rv32_func7_0000000;
wire dec_rv32i_srl  = dec_rv32i_arithm_type & dec_rv32_func3_101 & dec_rv32_func7_0000000;
wire dec_rv32i_sra  = dec_rv32i_arithm_type & dec_rv32_func3_101 & dec_rv32_func7_0100000;
wire dec_rv32i_or   = dec_rv32i_arithm_type & dec_rv32_func3_110 & dec_rv32_func7_0000000;
wire dec_rv32i_and  = dec_rv32i_arithm_type & dec_rv32_func3_111 & dec_rv32_func7_0000000;

// Memory Order Instructions
wire dec_rv32i_fence    = dec_rv32i_miscmem_type & dec_rv32_func3_000;
wire dec_rv32i_fence_i  = dec_rv32i_miscmem_type & dec_rv32_func3_001;
wire dec_rv32i_fence_fencei  = dec_rv32i_miscmem_type;

// System Instructions
wire dec_rv32i_ecall  = dec_rv32i_system_type & dec_rv32_func3_000 & (rv32_instr[31:20] == 12'b0000_0000_0000);
wire dec_rv32i_ebreak = dec_rv32i_system_type & dec_rv32_func3_000 & (rv32_instr[31:20] == 12'b0000_0000_0001);
wire rv32_csrrw    = dec_rv32i_system_type & dec_rv32_func3_001;
wire rv32_csrrs    = dec_rv32i_system_type & dec_rv32_func3_010;
wire rv32_csrrc    = dec_rv32i_system_type & dec_rv32_func3_011;
wire rv32_csrrwi   = dec_rv32i_system_type & dec_rv32_func3_101;
wire rv32_csrrsi   = dec_rv32i_system_type & dec_rv32_func3_110;
wire rv32_csrrci   = dec_rv32i_system_type & dec_rv32_func3_111;


// =========================================================================
// ----------------        Immediate Generate        ---------------- //

wire [31:0] rv32_imm_i = {{20{rv32_instr[31]}}, rv32_instr[31:20]};
wire [31:0] rv32_imm_s = {{20{rv32_instr[31]}}, rv32_instr[31:25], rv32_instr[11:7]};
wire [31:0] rv32_imm_b = {{19{rv32_instr[31]}}, rv32_instr[31], rv32_instr[7], rv32_instr[30:25], rv32_instr[11:8], 1'b0};
wire [31:0] rv32_imm_u = {rv32_instr[31:12], 12'b0};
wire [31:0] rv32_imm_j = {{11{rv32_instr[31]}}, rv32_instr[31], rv32_instr[19:12], rv32_instr[20], rv32_instr[30:21], 1'b0};

wire rv32_imm_sel_i = dec_rv32i_arithm_imm_type | dec_rv32i_load_type | dec_rv32i_jalr;
wire rv32_imm_sel_s = dec_rv32i_store_type;
// wire [31:0] rv32_jalr_imm = rv32_imm_i;    // For WHAT??
wire rv32_imm_sel_b = dec_rv32i_branch_type;
wire rv32_imm_sel_u = dec_rv32i_lui | dec_rv32i_auipc;
wire rv32_imm_sel_j = dec_rv32i_jal;

wire [31:0] rv32_imm = 
                    ({32{rv32_imm_sel_i}} & rv32_imm_i)
                  | ({32{rv32_imm_sel_s}} & rv32_imm_s)
                  | ({32{rv32_imm_sel_b}} & rv32_imm_b)
                  | ({32{rv32_imm_sel_u}} & rv32_imm_u)
                  | ({32{rv32_imm_sel_j}} & rv32_imm_j);

assign o_dec_imm = rv32_imm;


// =======================================================================
// ----------------        EXU Datapath Ctrl Sigs        ---------------- //
// wire dec_info_need_rd = dec_rv32i_arithm_type | dec_rv32i_arithm_imm_type | dec_rv32i_load_type | dec_rv32i_csr_type | dec_rv32i_lui | dec_rv32i_auipc | dec_rv32i_jal | dec_rv32i_jalr;
wire dec_info_need_rd = (~dec_rv32_rd_x0) & (~dec_rv32i_branch_type) & (~dec_rv32i_store_type) & (~dec_rv32i_fence_fencei) & (~dec_rv32i_ecall_ebreak);
wire dec_info_need_rs1 = (~dec_rv32_rs1_x0) & (   // TODO: Needs further consideration: 需要排除rs==x0的情况吗？
                                              (~dec_rv32i_lui)
                                            & (~dec_rv32i_auipc) 
                                            & (~dec_rv32i_jal) 
                                            & (~dec_rv32i_fence_fencei) 
                                            & (~dec_rv32i_ecall_ebreak)
                                            & (~rv32_csrrwi)
                                            & (~rv32_csrrsi)
                                            & (~rv32_csrrci)
                                            );
wire dec_info_need_rs2 = (~dec_rv32_rs2_x0) & (
                                              (dec_rv32i_branch_type)
                                            | (dec_rv32i_store_type)
                                            | (dec_rv32i_arithm_type)
                                            );

wire dec_info_op1pc = dec_rv32i_auipc;
wire dec_info_op2imm = rv32_imm_sel_i | rv32_imm_sel_s | rv32_imm_sel_b | rv32_imm_sel_u | rv32_imm_sel_j;

// ----------------        Decode Ctrl Sigs        ---------------- //
assign o_dec_rdwen_id = dec_info_need_rd;
assign o_need_rs1_idu = dec_info_need_rs1;
assign o_need_rs2_idu = dec_info_need_rs2;


// =======================================================================
// ----------------        Decode Info Bus        ---------------- //
// The following buses achieves a many-to-one mapping from instructions to exu circuits.
// wire [`E203_DECINFO_BJP_WIDTH-1:0] bjp_info_bus;
wire [`DECINFO_BUS_ALU_WIDTH-1:0] dec_info_bus_alu;
wire [`DECINFO_BUS_LSU_WIDTH-1:0] dec_info_bus_lsu;
wire [`DECINFO_BUS_BRU_WIDTH-1:0] dec_info_bus_bru;
// wire [`DECINFO_BUS_CSR_WIDTH-1:0] dec_info_bus_csr;

wire dec_oper_dispatch_alu = dec_rv32i_arithm_type | dec_rv32i_arithm_imm_type | dec_rv32i_lui | dec_rv32i_auipc;
wire dec_oper_dispatch_lsu = dec_rv32i_load_type | dec_rv32i_store_type;
wire dec_oper_dispatch_bru = dec_rv32i_branch_type | dec_rv32i_jal | dec_rv32i_jalr | dec_rv32i_fence_fencei;
wire dec_oper_dispatch_csr; // TODO


// ALU group
assign dec_info_bus_alu[`DECINFO_GRP        ] = `DECINFO_GRP_ALU;
assign dec_info_bus_alu[`DECINFO_ALU_ADD    ] = dec_rv32i_add | dec_rv32i_addi | dec_rv32i_auipc;
assign dec_info_bus_alu[`DECINFO_ALU_SUB    ] = dec_rv32i_sub;
assign dec_info_bus_alu[`DECINFO_ALU_SLL    ] = dec_rv32i_sll | dec_rv32i_slli;
assign dec_info_bus_alu[`DECINFO_ALU_SLT    ] = dec_rv32i_slt | dec_rv32i_slti;
assign dec_info_bus_alu[`DECINFO_ALU_SLTU   ] = dec_rv32i_sltu | dec_rv32i_sltiu;
assign dec_info_bus_alu[`DECINFO_ALU_XOR    ] = dec_rv32i_xor | dec_rv32i_xori;
assign dec_info_bus_alu[`DECINFO_ALU_SRL    ] = dec_rv32i_srl | dec_rv32i_srli;
assign dec_info_bus_alu[`DECINFO_ALU_SRA    ] = dec_rv32i_sra | dec_rv32i_srai;
assign dec_info_bus_alu[`DECINFO_ALU_OR     ] = dec_rv32i_or | dec_rv32i_ori;
assign dec_info_bus_alu[`DECINFO_ALU_AND    ] = dec_rv32i_and | dec_rv32i_andi;
assign dec_info_bus_alu[`DECINFO_ALU_LUI    ] = dec_rv32i_lui;
assign dec_info_bus_alu[`DECINFO_ALU_OP2IMM ] = dec_info_op2imm;
assign dec_info_bus_alu[`DECINFO_ALU_OP1PC  ] = dec_info_op1pc;


// LSU group, Load and Store Instrs
assign dec_info_bus_lsu[`DECINFO_GRP        ] = `DECINFO_GRP_LSU;
assign dec_info_bus_lsu[`DECINFO_LSU_LOAD   ] = dec_rv32i_load_type;
assign dec_info_bus_lsu[`DECINFO_LSU_STORE  ] = dec_rv32i_store_type;
assign dec_info_bus_lsu[`DECINFO_LSU_SIZE   ] = dec_info_lsu_size;
assign dec_info_bus_lsu[`DECINFO_LSU_USIGN  ] = dec_info_lsu_unsigned;
assign dec_info_bus_lsu[`DECINFO_LSU_OP2IMM ] = dec_info_op2imm;


// BRU, Branch Unit, handle Branch and System Instrs
assign dec_info_bus_bru[`DECINFO_GRP       ] = `DECINFO_GRP_BRU;
assign dec_info_bus_bru[`DECINFO_BRU_JAL   ] = dec_rv32i_jal;
assign dec_info_bus_bru[`DECINFO_BRU_JALR  ] = dec_rv32i_jalr;
assign dec_info_bus_bru[`DECINFO_BRU_JUMP  ] = dec_rv32i_jal | dec_rv32i_jalr;
assign dec_info_bus_bru[`DECINFO_BRU_BEQ   ] = dec_rv32i_beq;
assign dec_info_bus_bru[`DECINFO_BRU_BNE   ] = dec_rv32i_bne;
assign dec_info_bus_bru[`DECINFO_BRU_BLT   ] = dec_rv32i_blt; 
assign dec_info_bus_bru[`DECINFO_BRU_BGE   ] = dec_rv32i_bge;
assign dec_info_bus_bru[`DECINFO_BRU_BLTU  ] = dec_rv32i_bltu;
assign dec_info_bus_bru[`DECINFO_BRU_BGEU  ] = dec_rv32i_bgeu;
assign dec_info_bus_bru[`DECINFO_BRU_BXX   ] = dec_rv32i_branch_type;
assign dec_info_bus_bru[`DECINFO_BRU_FENCE ] = dec_rv32i_fence;
assign dec_info_bus_bru[`DECINFO_BRU_FENCEI] = dec_rv32i_fence_i;
//   assign dec_info_bus_bru[`DECINFO_BRU_BPRDT]  = i_prdt_taken;


// assign o_dec_info_bus_id = dec_info_bus_alu;
assign o_dec_info_bus_id = 
                        ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_alu}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_ALU_WIDTH{1'b0}}, dec_info_bus_alu})
                      | ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_lsu}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_LSU_WIDTH{1'b0}}, dec_info_bus_lsu})
                      | ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_bru}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_BRU_WIDTH{1'b0}}, dec_info_bus_bru});
                    //   | ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_csr}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_BRU_WIDTH{1'b0}}, dec_info_bus_csr});







endmodule
