`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/24
// Design Name: StepRV_v0
// Module Name: idu
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module idu(
    input wire clk,
    input wire rst_n,
    input wire i_stall,
    input wire i_flush,
    input wire i_if_id_vld,
    output wire o_if_id_rdy,
    output wire o_id_ex_vld,
    input wire i_id_ex_rdy,
    input wire [31:0] i_instr,
    input wire [31:0] i_pc_if,
    output wire [`RFIDX_WIDTH-1:0] o_dec_rs1idx,
    output wire [`RFIDX_WIDTH-1:0] o_dec_rs2idx,
    output wire [`RFIDX_WIDTH-1:0] o_dec_rd_idx,
    output wire [31:0] o_dec_imm,
    output wire [`DECINFO_BUS_WIDTH-1:0] o_dec_info_bus_id,
    output wire o_dec_rd_wen_id,
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
reg        r_id_vld;

assign o_instr_id = r_instr_id;
assign o_pc_id = r_pc_id;
assign o_if_id_rdy = (!r_id_vld | i_id_ex_rdy) & !i_stall;
assign o_id_ex_vld = r_id_vld;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_id_vld <= 1'b0;
    end
    else if (i_flush) begin
        r_id_vld <= 1'b0;
    end
    else if (o_if_id_rdy) begin
        r_id_vld <= i_if_id_vld;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_instr_id <= 32'b0;
    end
    else if (i_if_id_vld & o_if_id_rdy & !i_flush) begin
        r_instr_id <= i_instr;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_pc_id <= 32'b0;
    end
    else if (i_if_id_vld & o_if_id_rdy & !i_flush) begin
        r_pc_id <= i_pc_if;
    end
end

////////****   ↑ Pipeline Regs ↑   ****////////


// =============================================================
// ----------------        Decode        ---------------- //
wire [31:0] rv32_instr = r_instr_id;
// wire [15:0] rv16_instr = r_instr_id[15:0]; // reserved

wire [6:0] dec_opcode  = rv32_instr[6:0];
wire [4:0] dec_rd_idx  = rv32_instr[11:7];
wire [2:0] dec_funct3  = rv32_instr[14:12];
wire [4:0] dec_rs1_idx = rv32_instr[19:15];
wire [4:0] dec_rs2_idx = rv32_instr[24:20];
wire [6:0] dec_funct7  = rv32_instr[31:25];

// opcode[1:0]=2'b11 is fixed for RV32I, no need to consider other cases
wire dec_opcode_6_5_00  = (dec_opcode[6:5] == 2'b00);
wire dec_opcode_6_5_01  = (dec_opcode[6:5] == 2'b01);
wire dec_opcode_6_5_10  = (dec_opcode[6:5] == 2'b10);
wire dec_opcode_6_5_11  = (dec_opcode[6:5] == 2'b11);
wire dec_opcode_4_2_000 = (dec_opcode[4:2] == 3'b000);
wire dec_opcode_4_2_001 = (dec_opcode[4:2] == 3'b001);
wire dec_opcode_4_2_010 = (dec_opcode[4:2] == 3'b010);
wire dec_opcode_4_2_011 = (dec_opcode[4:2] == 3'b011);
wire dec_opcode_4_2_100 = (dec_opcode[4:2] == 3'b100);
wire dec_opcode_4_2_101 = (dec_opcode[4:2] == 3'b101);
wire dec_opcode_4_2_110 = (dec_opcode[4:2] == 3'b110);
wire dec_opcode_4_2_111 = (dec_opcode[4:2] == 3'b111);
wire dec_opcode_1_0_00  = (dec_opcode[1:0] == 2'b00);  // reserved for rv16("C"?)
wire dec_opcode_1_0_01  = (dec_opcode[1:0] == 2'b01);  // reserved for rv16("C"?)
wire dec_opcode_1_0_10  = (dec_opcode[1:0] == 2'b10);  // reserved for rv16("C"?)
wire dec_opcode_1_0_11  = (dec_opcode[1:0] == 2'b11);  // rv32i, all

// func3
wire dec_funct3_000 = (dec_funct3 == 3'b000);
wire dec_funct3_001 = (dec_funct3 == 3'b001);
wire dec_funct3_010 = (dec_funct3 == 3'b010);
wire dec_funct3_011 = (dec_funct3 == 3'b011);
wire dec_funct3_100 = (dec_funct3 == 3'b100);
wire dec_funct3_101 = (dec_funct3 == 3'b101);
wire dec_funct3_110 = (dec_funct3 == 3'b110);
wire dec_funct3_111 = (dec_funct3 == 3'b111);

// func7
wire dec_funct7_0000000 = (dec_funct7 == 7'b0000000);
wire dec_funct7_0000001 = (dec_funct7 == 7'b0000001);
wire dec_funct7_0100000 = (dec_funct7 == 7'b0100000);

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

assign o_dec_rs1idx = dec_rs1_idx;
assign o_dec_rs2idx = dec_rs2_idx;
assign o_dec_rd_idx = dec_rd_idx;

wire dec_rs1_x0 = (dec_rs1_idx == 5'b00000);
wire dec_rs2_x0 = (dec_rs2_idx == 5'b00000);
wire dec_rs2_x1 = (dec_rs2_idx == 5'b00001); // for what
wire dec_rd_x0  = (dec_rd_idx == 5'b00000);
wire dec_rd_x2  = (dec_rd_idx == 5'b00010);  // for what


////************    Instr types decode    ************////
wire instr_type_arithm  = dec_opcode_6_5_01 & dec_opcode_4_2_100 & dec_opcode_1_0_11; // R-type, arithmetic operations.
wire instr_type_arithm_imm = dec_opcode_6_5_00 & dec_opcode_4_2_100 & dec_opcode_1_0_11; // I-type, arithmetic operations.
wire instr_type_load    = dec_opcode_6_5_00 & dec_opcode_4_2_000 & dec_opcode_1_0_11; // I-type, loads.
wire instr_type_store   = dec_opcode_6_5_01 & dec_opcode_4_2_000 & dec_opcode_1_0_11; // S-type, stores.
wire instr_type_branch  = dec_opcode_6_5_11 & dec_opcode_4_2_000 & dec_opcode_1_0_11; // S-type, stores.
wire instr_type_miscmem = dec_opcode_6_5_00 & dec_opcode_4_2_011 & dec_opcode_1_0_11; // I-type, "fence", "fence.i".
wire instr_type_system  = dec_opcode_6_5_11 & dec_opcode_4_2_100 & dec_opcode_1_0_11; // I-type, csrs, "ecall", "ebreak".

wire instr_type_muldiv = instr_type_arithm & dec_funct7_0000001;
wire instr_type_csr     = instr_type_system & (~dec_funct3_000);    // part of "system" type, func3_000 is for "ecall", "ebreak".
wire instr_ecall_ebreak_mret = instr_type_system & dec_funct3_000;


////************    Specific Instruction decode    ************////
wire instr_lui   = dec_opcode_6_5_01 & dec_opcode_4_2_101 & dec_opcode_1_0_11; // U-type, "lui".
wire instr_auipc = dec_opcode_6_5_00 & dec_opcode_4_2_101 & dec_opcode_1_0_11; // U-type, "auipc".
wire instr_jal   = dec_opcode_6_5_11 & dec_opcode_4_2_011 & dec_opcode_1_0_11; // J-type, "jal".
wire instr_jalr  = dec_opcode_6_5_11 & dec_opcode_4_2_001 & dec_opcode_1_0_11; // J-type, "jalr".

// Branch Instructions
wire instr_beq  = instr_type_branch & dec_funct3_000;
wire instr_bne  = instr_type_branch & dec_funct3_001;
wire instr_blt  = instr_type_branch & dec_funct3_100;
wire instr_bge  = instr_type_branch & dec_funct3_101;
wire instr_bltu = instr_type_branch & dec_funct3_110;
wire instr_bgeu = instr_type_branch & dec_funct3_111;

// Load/Store Instructions
wire instr_lb   = instr_type_load   & dec_funct3_000;
wire instr_lh   = instr_type_load   & dec_funct3_001;
wire instr_lw   = instr_type_load   & dec_funct3_010;
wire instr_lbu  = instr_type_load   & dec_funct3_100;
wire instr_lhu  = instr_type_load   & dec_funct3_101;
wire instr_sb   = instr_type_store  & dec_funct3_000;
wire instr_sh   = instr_type_store  & dec_funct3_001;
wire instr_sw   = instr_type_store  & dec_funct3_010;

wire [1:0] dec_info_lsu_size = dec_funct3[1:0];
wire dec_info_lsu_unsigned = dec_funct3[2];


// Arithmetic Instructions
wire instr_addi  = instr_type_arithm_imm & dec_funct3_000;
wire instr_slti  = instr_type_arithm_imm & dec_funct3_010;
wire instr_sltiu = instr_type_arithm_imm & dec_funct3_011;
wire instr_xori  = instr_type_arithm_imm & dec_funct3_100;
wire instr_ori   = instr_type_arithm_imm & dec_funct3_110;
wire instr_andi  = instr_type_arithm_imm & dec_funct3_111;
wire instr_slli  = instr_type_arithm_imm & dec_funct3_001 & (rv32_instr[31:26] == 6'b000000);
wire instr_srli  = instr_type_arithm_imm & dec_funct3_101 & (rv32_instr[31:26] == 6'b000000);
wire instr_srai  = instr_type_arithm_imm & dec_funct3_101 & (rv32_instr[31:26] == 6'b010000);

wire instr_add  = instr_type_arithm & dec_funct3_000 & dec_funct7_0000000;
wire instr_sub  = instr_type_arithm & dec_funct3_000 & dec_funct7_0100000;
wire instr_sll  = instr_type_arithm & dec_funct3_001 & dec_funct7_0000000;
wire instr_slt  = instr_type_arithm & dec_funct3_010 & dec_funct7_0000000;
wire instr_sltu = instr_type_arithm & dec_funct3_011 & dec_funct7_0000000;
wire instr_xor  = instr_type_arithm & dec_funct3_100 & dec_funct7_0000000;
wire instr_srl  = instr_type_arithm & dec_funct3_101 & dec_funct7_0000000;
wire instr_sra  = instr_type_arithm & dec_funct3_101 & dec_funct7_0100000;
wire instr_or   = instr_type_arithm & dec_funct3_110 & dec_funct7_0000000;
wire instr_and  = instr_type_arithm & dec_funct3_111 & dec_funct7_0000000;

// Memory Order Instructions
wire instr_fence    = instr_type_miscmem & dec_funct3_000;
wire instr_fence_i  = instr_type_miscmem & dec_funct3_001;
wire instr_fence_fencei  = instr_type_miscmem;

// System Instructions
wire instr_ecall  = instr_type_system & dec_funct3_000 & (rv32_instr[31:20] == 12'b0000_0000_0000);
wire instr_ebreak = instr_type_system & dec_funct3_000 & (rv32_instr[31:20] == 12'b0000_0000_0001);
wire instr_mret   = instr_type_system & dec_funct3_000 & (rv32_instr[31:20] == 12'h302);
wire instr_csrrw    = instr_type_system & dec_funct3_001;
wire instr_csrrs    = instr_type_system & dec_funct3_010;
wire instr_csrrc    = instr_type_system & dec_funct3_011;
wire instr_csrrwi   = instr_type_system & dec_funct3_101;
wire instr_csrrsi   = instr_type_system & dec_funct3_110;
wire instr_csrrci   = instr_type_system & dec_funct3_111;


// =========================================================================
// ----------------        Immediate Generate        ---------------- //

wire [31:0] dec_imm_i = {{20{rv32_instr[31]}}, rv32_instr[31:20]};
wire [31:0] dec_imm_s = {{20{rv32_instr[31]}}, rv32_instr[31:25], rv32_instr[11:7]};
wire [31:0] dec_imm_b = {{19{rv32_instr[31]}}, rv32_instr[31], rv32_instr[7], rv32_instr[30:25], rv32_instr[11:8], 1'b0};
wire [31:0] dec_imm_u = {rv32_instr[31:12], 12'b0};
wire [31:0] dec_imm_j = {{11{rv32_instr[31]}}, rv32_instr[31], rv32_instr[19:12], rv32_instr[20], rv32_instr[30:21], 1'b0};

wire dec_imm_sel_i = instr_type_arithm_imm | instr_type_load | instr_jalr;
wire dec_imm_sel_s = instr_type_store;
// wire [31:0] rv32_jalr_imm = dec_imm_i;    // For WHAT??
wire dec_imm_sel_b = instr_type_branch;
wire dec_imm_sel_u = instr_lui | instr_auipc;
wire dec_imm_sel_j = instr_jal;

wire [31:0] dec_imm = 
                    ({32{dec_imm_sel_i}} & dec_imm_i)
                  | ({32{dec_imm_sel_s}} & dec_imm_s)
                  | ({32{dec_imm_sel_b}} & dec_imm_b)
                  | ({32{dec_imm_sel_u}} & dec_imm_u)
                  | ({32{dec_imm_sel_j}} & dec_imm_j);

assign o_dec_imm = dec_imm;

// wire [11:0] dec_csr_idx = rv32_instr[31:20];


// =======================================================================
// ----------------        EXU Datapath Ctrl Sigs        ---------------- //
// wire dec_info_need_rd = instr_type_arithm | instr_type_arithm_imm | instr_type_load | instr_type_csr | instr_lui | instr_auipc | instr_jal | instr_jalr;
wire dec_info_need_rd = (~dec_rd_x0) & (~instr_type_branch) & (~instr_type_store) & (~instr_fence_fencei) & (~instr_ecall_ebreak_mret);
// x0 still reads as 0 from regfile; excluding it here only skips false hazard/forwarding dependencies.
wire dec_info_need_rs1 = (~dec_rs1_x0) & (
                                              (~instr_lui)
                                            & (~instr_auipc) 
                                            & (~instr_jal) 
                                            & (~instr_fence_fencei) 
                                            & (~instr_ecall_ebreak_mret)
                                            & (~instr_csrrwi)
                                            & (~instr_csrrsi)
                                            & (~instr_csrrci)
                                            );
wire dec_info_need_rs2 = (~dec_rs2_x0) & (
                                              (instr_type_branch)
                                            | (instr_type_store)
                                            | (instr_type_arithm)
                                            );

wire dec_info_op1pc = instr_auipc;
wire dec_info_op2imm = dec_imm_sel_i | dec_imm_sel_s | dec_imm_sel_b | dec_imm_sel_u | dec_imm_sel_j;

// ----------------        Decode Ctrl Sigs        ---------------- //
assign o_dec_rd_wen_id = dec_info_need_rd;
assign o_need_rs1_idu = dec_info_need_rs1;
assign o_need_rs2_idu = dec_info_need_rs2;


// =======================================================================
// ----------------        Decode Info Bus        ---------------- //
// The following buses achieves a many-to-one mapping from instructions to exu circuits.
// wire [`E203_DECINFO_BJP_WIDTH-1:0] bjp_info_bus;
wire [`DECINFO_BUS_ALU_WIDTH-1:0] dec_info_bus_alu;
wire [`DECINFO_BUS_LSU_WIDTH-1:0] dec_info_bus_lsu;
wire [`DECINFO_BUS_BRU_WIDTH-1:0] dec_info_bus_bru;
wire [`DECINFO_BUS_CSR_WIDTH-1:0] dec_info_bus_csr;
wire [`DECINFO_BUS_MDU_WIDTH-1:0] dec_info_bus_mdu;

wire dec_oper_dispatch_alu = (instr_type_arithm & (~dec_funct7_0000001)) | instr_type_arithm_imm | instr_lui | instr_auipc;
wire dec_oper_dispatch_lsu = instr_type_load | instr_type_store;
wire dec_oper_dispatch_bru = instr_type_branch | instr_jal | instr_jalr | instr_fence_fencei;
wire dec_oper_dispatch_csr = instr_type_csr | instr_ecall | instr_ebreak | instr_mret;
wire dec_oper_dispatch_mdu = instr_type_muldiv;


// ALU group
assign dec_info_bus_alu[`DECINFO_GRP        ] = `DECINFO_GRP_ALU;
assign dec_info_bus_alu[`DECINFO_ALU_ADD    ] = instr_add | instr_addi | instr_auipc;
assign dec_info_bus_alu[`DECINFO_ALU_SUB    ] = instr_sub;
assign dec_info_bus_alu[`DECINFO_ALU_SLL    ] = instr_sll | instr_slli;
assign dec_info_bus_alu[`DECINFO_ALU_SLT    ] = instr_slt | instr_slti;
assign dec_info_bus_alu[`DECINFO_ALU_SLTU   ] = instr_sltu | instr_sltiu;
assign dec_info_bus_alu[`DECINFO_ALU_XOR    ] = instr_xor | instr_xori;
assign dec_info_bus_alu[`DECINFO_ALU_SRL    ] = instr_srl | instr_srli;
assign dec_info_bus_alu[`DECINFO_ALU_SRA    ] = instr_sra | instr_srai;
assign dec_info_bus_alu[`DECINFO_ALU_OR     ] = instr_or | instr_ori;
assign dec_info_bus_alu[`DECINFO_ALU_AND    ] = instr_and | instr_andi;
assign dec_info_bus_alu[`DECINFO_ALU_LUI    ] = instr_lui;
assign dec_info_bus_alu[`DECINFO_ALU_OP2IMM ] = dec_info_op2imm;
assign dec_info_bus_alu[`DECINFO_ALU_OP1PC  ] = dec_info_op1pc;


// LSU group, Load and Store Instrs
assign dec_info_bus_lsu[`DECINFO_GRP        ] = `DECINFO_GRP_LSU;
assign dec_info_bus_lsu[`DECINFO_LSU_LOAD   ] = instr_type_load;
assign dec_info_bus_lsu[`DECINFO_LSU_STORE  ] = instr_type_store;
assign dec_info_bus_lsu[`DECINFO_LSU_SIZE   ] = dec_info_lsu_size;
assign dec_info_bus_lsu[`DECINFO_LSU_USIGN  ] = dec_info_lsu_unsigned;
assign dec_info_bus_lsu[`DECINFO_LSU_OP2IMM ] = dec_info_op2imm;


// BRU, Branch Unit, handle Branch and System Instrs
assign dec_info_bus_bru[`DECINFO_GRP       ] = `DECINFO_GRP_BRU;
assign dec_info_bus_bru[`DECINFO_BRU_JAL   ] = instr_jal;
assign dec_info_bus_bru[`DECINFO_BRU_JALR  ] = instr_jalr;
assign dec_info_bus_bru[`DECINFO_BRU_JUMP  ] = instr_jal | instr_jalr;
assign dec_info_bus_bru[`DECINFO_BRU_BEQ   ] = instr_beq;
assign dec_info_bus_bru[`DECINFO_BRU_BNE   ] = instr_bne;
assign dec_info_bus_bru[`DECINFO_BRU_BLT   ] = instr_blt; 
assign dec_info_bus_bru[`DECINFO_BRU_BGE   ] = instr_bge;
assign dec_info_bus_bru[`DECINFO_BRU_BLTU  ] = instr_bltu;
assign dec_info_bus_bru[`DECINFO_BRU_BGEU  ] = instr_bgeu;
assign dec_info_bus_bru[`DECINFO_BRU_BXX   ] = instr_type_branch;
assign dec_info_bus_bru[`DECINFO_BRU_FENCE ] = instr_fence;
assign dec_info_bus_bru[`DECINFO_BRU_FENCEI] = instr_fence_i;
//   assign dec_info_bus_bru[`DECINFO_BRU_BPRDT]  = i_prdt_taken;

assign dec_info_bus_csr[`DECINFO_GRP        ] = `DECINFO_GRP_CSR;
assign dec_info_bus_csr[`DECINFO_CSR_CSRRW  ] = instr_csrrw | instr_csrrwi;
assign dec_info_bus_csr[`DECINFO_CSR_CSRRS  ] = instr_csrrs | instr_csrrsi;
assign dec_info_bus_csr[`DECINFO_CSR_CSRRC  ] = instr_csrrc | instr_csrrci;
assign dec_info_bus_csr[`DECINFO_CSR_RS1IMM ] = instr_csrrwi | instr_csrrsi | instr_csrrci;
assign dec_info_bus_csr[`DECINFO_CSR_ZIMM   ] = dec_rs1_idx;
assign dec_info_bus_csr[`DECINFO_CSR_RS1X0  ] = dec_rs1_x0;
assign dec_info_bus_csr[`DECINFO_CSR_CSRIDX ] = rv32_instr[31:20];
assign dec_info_bus_csr[`DECINFO_CSR_ECALL  ] = instr_ecall;
assign dec_info_bus_csr[`DECINFO_CSR_EBREAK ] = instr_ebreak;
assign dec_info_bus_csr[`DECINFO_CSR_MRET   ] = instr_mret;


assign dec_info_bus_mdu[`DECINFO_GRP        ] = `DECINFO_GRP_MDU;
assign dec_info_bus_mdu[`DECINFO_MDU_OP     ] = dec_funct3;




// assign o_dec_info_bus_id = dec_info_bus_alu;
assign o_dec_info_bus_id = 
                        ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_alu}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_ALU_WIDTH{1'b0}}, dec_info_bus_alu})
                      | ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_lsu}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_LSU_WIDTH{1'b0}}, dec_info_bus_lsu})
                      | ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_bru}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_BRU_WIDTH{1'b0}}, dec_info_bus_bru})
                      | ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_csr}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_CSR_WIDTH{1'b0}}, dec_info_bus_csr})
                      | ({`DECINFO_BUS_WIDTH{dec_oper_dispatch_mdu}} & {{`DECINFO_BUS_WIDTH-`DECINFO_BUS_MDU_WIDTH{1'b0}}, dec_info_bus_mdu});







endmodule
