// ===========================================================================
//// --------        CONFIGURATION        -------- ////

// Memory implementation selection:
// - No macro defined: use generic synthesizable RTL memory models.
// - USE_BRAM: instantiate Vivado Block Memory Generator IP wrappers.
// - USE_SRAM_MACRO: instantiate ASIC SRAM macro wrapper modules.
// If both are defined, USE_SRAM_MACRO has priority in mem_* wrappers.
//
// Vivado users can enable BRAM IP instantiation by uncommenting USE_BRAM here.
// `define USE_BRAM
`define USE_SRAM_MACRO


// ===========================================================================
// ===========================================================================


// ===========================================================================
// Memory Map Configuration
// `define ITCM_BASE 32'h0000_0000
// `define DTCM_BASE 32'h0000_1000
// 
// `define ITCM_SIZE 32'h0000_1000  // 4KB, matches link.ld .text before .data ALIGN(0x1000)
// `define DTCM_SIZE 32'h0000_F000  // Remaining address space for DTCM


`define ITCM_BASE 32'h0000_0000
`define DTCM_BASE 32'h1000_0000
`define UART_BASE 32'h3000_0000

`define ITCM_SIZE 32'h0000_8000  // 32KB, matching link.lds flash section length (32K)
// `define ITCM_SIZE 32'h0000_4000  // 16KB, matching link.lds flash section length (16K)
`define DTCM_SIZE 32'h0000_4000  // 16KB, matching link.lds ram section length (16K)
`define UART_SIZE 32'h0000_1000  // 4KB UART MMIO window

`define ITCM_DEPTH (`ITCM_SIZE / 4)  // Word depth derived from size (4 bytes per word)
`define DTCM_DEPTH (`DTCM_SIZE / 4)  // Word depth derived from size (4 bytes per word)



`define RFIDX_WIDTH 5

`define XLEN 32   // regfile width is 32


`define ZERO_WORD 32'b0
`define INSTR_NOP 32'h00000013

// Basic dynamic branch predictor: direct-mapped BTB plus a 2-bit BHT.
// Keep these overridable from the compile command line for A/B regression.
`ifndef BPU_ENABLE
`define BPU_ENABLE 1
`endif
`ifndef BPU_BTB_ENTRIES
`define BPU_BTB_ENTRIES 16
`endif
`ifndef BPU_BHT_ENTRIES
`define BPU_BHT_ENTRIES 16
`endif
`ifndef BPU_BHT_INIT
`define BPU_BHT_INIT 2'b01
`endif


// ===========================================================================
// Stall & Flush
`define STALL_PC        0
`define STALL_IF_ID     1
`define STALL_ID_EX     2
`define STALL_EX_MEM    3
`define STALL_MEM_WB    4

`define FLUSH_IF_ID     0
`define FLUSH_ID_EX     1
`define FLUSH_EX_MEM    2
`define FLUSH_MEM_WB    3


// ===========================================================================
// Decode relevant macro, E203v2 as a reference.

// ---- decinfo_bus
// ----------------        Common Seg        ---------------- //
`define DECINFO_GRP_WIDTH           3
`define DECINFO_GRP_ALU             `DECINFO_GRP_WIDTH'd0
`define DECINFO_GRP_LSU             `DECINFO_GRP_WIDTH'd1
`define DECINFO_GRP_BRU             `DECINFO_GRP_WIDTH'd2
`define DECINFO_GRP_CSR             `DECINFO_GRP_WIDTH'd3
`define DECINFO_GRP_MDU             `DECINFO_GRP_WIDTH'd4

    `define DECINFO_GRP_LSB         0
    `define DECINFO_GRP_MSB         (`DECINFO_GRP_LSB + `DECINFO_GRP_WIDTH -1)
`define DECINFO_GRP         `DECINFO_GRP_MSB :`DECINFO_GRP_LSB

`define DECINFO_SUBDECINFO_LSB  (`DECINFO_GRP_MSB +1)

// ----------------        ALU group        ---------------- //
    `define DECINFO_ALU_ADD_LSB     `DECINFO_SUBDECINFO_LSB
    `define DECINFO_ALU_ADD_MSB     (`DECINFO_ALU_ADD_LSB+1-1)
`define DECINFO_ALU_ADD     `DECINFO_ALU_ADD_MSB :`DECINFO_ALU_ADD_LSB
    `define DECINFO_ALU_SUB_LSB     (`DECINFO_ALU_ADD_MSB+1)
    `define DECINFO_ALU_SUB_MSB     (`DECINFO_ALU_SUB_LSB+1-1)
`define DECINFO_ALU_SUB     `DECINFO_ALU_SUB_MSB :`DECINFO_ALU_SUB_LSB
    `define DECINFO_ALU_SLL_LSB     (`DECINFO_ALU_SUB_MSB+1)
    `define DECINFO_ALU_SLL_MSB     (`DECINFO_ALU_SLL_LSB+1-1)
`define DECINFO_ALU_SLL     `DECINFO_ALU_SLL_MSB :`DECINFO_ALU_SLL_LSB
    `define DECINFO_ALU_SLT_LSB     (`DECINFO_ALU_SLL_MSB+1)
    `define DECINFO_ALU_SLT_MSB     (`DECINFO_ALU_SLT_LSB+1-1)
`define DECINFO_ALU_SLT     `DECINFO_ALU_SLT_MSB :`DECINFO_ALU_SLT_LSB
    `define DECINFO_ALU_SLTU_LSB    (`DECINFO_ALU_SLT_MSB+1)
    `define DECINFO_ALU_SLTU_MSB    (`DECINFO_ALU_SLTU_LSB+1-1)
`define DECINFO_ALU_SLTU    `DECINFO_ALU_SLTU_MSB:`DECINFO_ALU_SLTU_LSB
    `define DECINFO_ALU_XOR_LSB     (`DECINFO_ALU_SLTU_MSB+1)
    `define DECINFO_ALU_XOR_MSB     (`DECINFO_ALU_XOR_LSB+1-1)
`define DECINFO_ALU_XOR     `DECINFO_ALU_XOR_MSB :`DECINFO_ALU_XOR_LSB
    `define DECINFO_ALU_SRL_LSB     (`DECINFO_ALU_XOR_MSB+1)
    `define DECINFO_ALU_SRL_MSB     (`DECINFO_ALU_SRL_LSB+1-1)
`define DECINFO_ALU_SRL     `DECINFO_ALU_SRL_MSB :`DECINFO_ALU_SRL_LSB
    `define DECINFO_ALU_SRA_LSB     (`DECINFO_ALU_SRL_MSB+1)
    `define DECINFO_ALU_SRA_MSB     (`DECINFO_ALU_SRA_LSB+1-1)
`define DECINFO_ALU_SRA     `DECINFO_ALU_SRA_MSB :`DECINFO_ALU_SRA_LSB
    `define DECINFO_ALU_OR_LSB      (`DECINFO_ALU_SRA_MSB+1)
    `define DECINFO_ALU_OR_MSB      (`DECINFO_ALU_OR_LSB+1-1)
`define DECINFO_ALU_OR      `DECINFO_ALU_OR_MSB  :`DECINFO_ALU_OR_LSB
    `define DECINFO_ALU_AND_LSB     (`DECINFO_ALU_OR_MSB+1)
    `define DECINFO_ALU_AND_MSB     (`DECINFO_ALU_AND_LSB+1-1)
`define DECINFO_ALU_AND     `DECINFO_ALU_AND_MSB :`DECINFO_ALU_AND_LSB // Above: R-type, I-type-arithm
    `define DECINFO_ALU_LUI_LSB     (`DECINFO_ALU_AND_MSB+1)
    `define DECINFO_ALU_LUI_MSB     (`DECINFO_ALU_LUI_LSB+1-1)
`define DECINFO_ALU_LUI     `DECINFO_ALU_LUI_MSB :`DECINFO_ALU_LUI_LSB // U-type
    `define DECINFO_ALU_OP1PC_LSB   (`DECINFO_ALU_LUI_MSB+1)
    `define DECINFO_ALU_OP1PC_MSB   (`DECINFO_ALU_OP1PC_LSB+1-1)
`define DECINFO_ALU_OP1PC   `DECINFO_ALU_OP1PC_MSB :`DECINFO_ALU_OP1PC_LSB
    `define DECINFO_ALU_OP2IMM_LSB    (`DECINFO_ALU_OP1PC_MSB+1)
    `define DECINFO_ALU_OP2IMM_MSB    (`DECINFO_ALU_OP2IMM_LSB+1-1)
`define DECINFO_ALU_OP2IMM    `DECINFO_ALU_OP2IMM_MSB :`DECINFO_ALU_OP2IMM_LSB

`define DECINFO_BUS_ALU_WIDTH   (`DECINFO_ALU_OP2IMM_MSB+1)  // = 16

//     `define DECINFO_ALU_NOP_LSB    (`DECINFO_ALU_OP1PC_MSB+1)
//     `define DECINFO_ALU_NOP_MSB    (`DECINFO_ALU_NOP_LSB+1-1)
// `define DECINFO_ALU_NOP    `DECINFO_ALU_NOP_MSB :`DECINFO_ALU_NOP_LSB 
//     `define DECINFO_ALU_ECAL_LSB  (`DECINFO_ALU_NOP_MSB+1)
//     `define DECINFO_ALU_ECAL_MSB  (`DECINFO_ALU_ECAL_LSB+1-1)
// `define DECINFO_ALU_ECAL   `DECINFO_ALU_ECAL_MSB:`DECINFO_ALU_ECAL_LSB 
//     `define DECINFO_ALU_EBRK_LSB  (`DECINFO_ALU_ECAL_MSB+1)
//     `define DECINFO_ALU_EBRK_MSB  (`DECINFO_ALU_EBRK_LSB+1-1)
// `define DECINFO_ALU_EBRK   `DECINFO_ALU_EBRK_MSB:`DECINFO_ALU_EBRK_LSB 
//     `define DECINFO_ALU_WFI_LSB  (`DECINFO_ALU_EBRK_MSB+1)
//     `define DECINFO_ALU_WFI_MSB  (`DECINFO_ALU_WFI_LSB+1-1)
// `define DECINFO_ALU_WFI   `DECINFO_ALU_WFI_MSB:`DECINFO_ALU_WFI_LSB 


// ----------------        LSU group        ---------------- //
    `define DECINFO_LSU_LOAD_LSB    `DECINFO_SUBDECINFO_LSB
    `define DECINFO_LSU_LOAD_MSB    (`DECINFO_LSU_LOAD_LSB+1-1)
`define DECINFO_LSU_LOAD    `DECINFO_LSU_LOAD_MSB :`DECINFO_LSU_LOAD_LSB
    `define DECINFO_LSU_STORE_LSB   (`DECINFO_LSU_LOAD_MSB+1)
    `define DECINFO_LSU_STORE_MSB   (`DECINFO_LSU_STORE_LSB+1-1)
`define DECINFO_LSU_STORE   `DECINFO_LSU_STORE_MSB :`DECINFO_LSU_STORE_LSB
    `define DECINFO_LSU_SIZE_LSB    (`DECINFO_LSU_STORE_MSB+1)
    `define DECINFO_LSU_SIZE_MSB    (`DECINFO_LSU_SIZE_LSB+2-1)
`define DECINFO_LSU_SIZE    `DECINFO_LSU_SIZE_MSB :`DECINFO_LSU_SIZE_LSB
    `define DECINFO_LSU_USIGN_LSB   (`DECINFO_LSU_SIZE_MSB+1)
    `define DECINFO_LSU_USIGN_MSB   (`DECINFO_LSU_USIGN_LSB+1-1)
`define DECINFO_LSU_USIGN    `DECINFO_LSU_USIGN_MSB :`DECINFO_LSU_USIGN_LSB
    `define DECINFO_LSU_OP2IMM_LSB  (`DECINFO_LSU_USIGN_MSB+1)
    `define DECINFO_LSU_OP2IMM_MSB  (`DECINFO_LSU_OP2IMM_LSB+1-1)
`define DECINFO_LSU_OP2IMM  `DECINFO_LSU_OP2IMM_MSB :`DECINFO_LSU_OP2IMM_LSB

`define DECINFO_BUS_LSU_WIDTH   (`DECINFO_LSU_OP2IMM_MSB+1)  // = 9


// ----------------        BRU group        ---------------- //
    `define DECINFO_BRU_JAL_LSB     `DECINFO_SUBDECINFO_LSB
    `define DECINFO_BRU_JAL_MSB     (`DECINFO_BRU_JAL_LSB+1-1)
`define DECINFO_BRU_JAL     `DECINFO_BRU_JAL_MSB :`DECINFO_BRU_JAL_LSB 
    `define DECINFO_BRU_JALR_LSB    (`DECINFO_BRU_JAL_MSB+1)
    `define DECINFO_BRU_JALR_MSB    (`DECINFO_BRU_JALR_LSB+1-1)
`define DECINFO_BRU_JALR    `DECINFO_BRU_JALR_MSB :`DECINFO_BRU_JALR_LSB 
    `define DECINFO_BRU_JUMP_LSB    (`DECINFO_BRU_JALR_MSB+1)
    `define DECINFO_BRU_JUMP_MSB    (`DECINFO_BRU_JUMP_LSB+1-1)
`define DECINFO_BRU_JUMP    `DECINFO_BRU_JUMP_MSB :`DECINFO_BRU_JUMP_LSB 
    `define DECINFO_BRU_BEQ_LSB     (`DECINFO_BRU_JUMP_MSB+1)
    `define DECINFO_BRU_BEQ_MSB     (`DECINFO_BRU_BEQ_LSB+1-1)
`define DECINFO_BRU_BEQ     `DECINFO_BRU_BEQ_MSB  :`DECINFO_BRU_BEQ_LSB  
    `define DECINFO_BRU_BNE_LSB     (`DECINFO_BRU_BEQ_MSB+1)
    `define DECINFO_BRU_BNE_MSB     (`DECINFO_BRU_BNE_LSB+1-1)
`define DECINFO_BRU_BNE     `DECINFO_BRU_BNE_MSB  :`DECINFO_BRU_BNE_LSB  
    `define DECINFO_BRU_BLT_LSB     (`DECINFO_BRU_BNE_MSB+1)
    `define DECINFO_BRU_BLT_MSB     (`DECINFO_BRU_BLT_LSB+1-1)
`define DECINFO_BRU_BLT     `DECINFO_BRU_BLT_MSB  :`DECINFO_BRU_BLT_LSB  
    `define DECINFO_BRU_BGE_LSB     (`DECINFO_BRU_BLT_MSB+1)
    `define DECINFO_BRU_BGE_MSB     (`DECINFO_BRU_BGE_LSB+1-1)
`define DECINFO_BRU_BGE     `DECINFO_BRU_BGE_MSB  :`DECINFO_BRU_BGE_LSB  
    `define DECINFO_BRU_BLTU_LSB    (`DECINFO_BRU_BGE_MSB+1)
    `define DECINFO_BRU_BLTU_MSB    (`DECINFO_BRU_BLTU_LSB+1-1)
`define DECINFO_BRU_BLTU    `DECINFO_BRU_BLTU_MSB :`DECINFO_BRU_BLTU_LSB 
    `define DECINFO_BRU_BGEU_LSB    (`DECINFO_BRU_BLTU_MSB+1)
    `define DECINFO_BRU_BGEU_MSB    (`DECINFO_BRU_BGEU_LSB+1-1)
`define DECINFO_BRU_BGEU    `DECINFO_BRU_BGEU_MSB :`DECINFO_BRU_BGEU_LSB 
    `define DECINFO_BRU_BXX_LSB     (`DECINFO_BRU_BGEU_MSB+1)
    `define DECINFO_BRU_BXX_MSB     (`DECINFO_BRU_BXX_LSB+1-1)
`define DECINFO_BRU_BXX     `DECINFO_BRU_BXX_MSB :`DECINFO_BRU_BXX_LSB
    `define DECINFO_BRU_FENCE_LSB   (`DECINFO_BRU_BXX_MSB+1)
    `define DECINFO_BRU_FENCE_MSB   (`DECINFO_BRU_FENCE_LSB+1-1)
`define DECINFO_BRU_FENCE   `DECINFO_BRU_FENCE_MSB :`DECINFO_BRU_FENCE_LSB
    `define DECINFO_BRU_FENCEI_LSB  (`DECINFO_BRU_FENCE_MSB+1)
    `define DECINFO_BRU_FENCEI_MSB  (`DECINFO_BRU_FENCEI_LSB+1-1)
`define DECINFO_BRU_FENCEI  `DECINFO_BRU_FENCEI_MSB :`DECINFO_BRU_FENCEI_LSB

`define DECINFO_BUS_BRU_WIDTH   (`DECINFO_BRU_FENCEI_MSB+1)  // = 15

//       `define DECINFO_BRU_BPRDT_LSB (`DECINFO_BRU_JUMP_MSB+1)
//       `define DECINFO_BRU_BPRDT_MSB (`DECINFO_BRU_BPRDT_LSB+1-1)
//   `define DECINFO_BRU_BPRDT  `DECINFO_BRU_BPRDT_MSB:`DECINFO_BRU_BPRDT_LSB
//       `define DECINFO_BRU_MRET_LSB  (`DECINFO_BRU_BXX_MSB+1)
//       `define DECINFO_BRU_MRET_MSB  (`DECINFO_BRU_MRET_LSB+1-1)
//   `define DECINFO_BRU_MRET    `DECINFO_BRU_MRET_MSB :`DECINFO_BRU_MRET_LSB
//       `define DECINFO_BRU_DRET_LSB  (`DECINFO_BRU_MRET_MSB+1)
//       `define DECINFO_BRU_DRET_MSB  (`DECINFO_BRU_DRET_LSB+1-1)
//   `define DECINFO_BRU_DRET    `DECINFO_BRU_DRET_MSB :`DECINFO_BRU_DRET_LSB


// ----------------        CSR group        ---------------- //
    `define DECINFO_CSR_CSRRW_LSB   `DECINFO_SUBDECINFO_LSB
    `define DECINFO_CSR_CSRRW_MSB   (`DECINFO_CSR_CSRRW_LSB+1-1)
`define DECINFO_CSR_CSRRW   `DECINFO_CSR_CSRRW_MSB :`DECINFO_CSR_CSRRW_LSB
    `define DECINFO_CSR_CSRRS_LSB   (`DECINFO_CSR_CSRRW_MSB+1)
    `define DECINFO_CSR_CSRRS_MSB   (`DECINFO_CSR_CSRRS_LSB+1-1)
`define DECINFO_CSR_CSRRS   `DECINFO_CSR_CSRRS_MSB :`DECINFO_CSR_CSRRS_LSB
    `define DECINFO_CSR_CSRRC_LSB   (`DECINFO_CSR_CSRRS_MSB+1)
    `define DECINFO_CSR_CSRRC_MSB   (`DECINFO_CSR_CSRRC_LSB+1-1)
`define DECINFO_CSR_CSRRC   `DECINFO_CSR_CSRRC_MSB :`DECINFO_CSR_CSRRC_LSB
    `define DECINFO_CSR_RS1IMM_LSB  (`DECINFO_CSR_CSRRC_MSB+1)
    `define DECINFO_CSR_RS1IMM_MSB  (`DECINFO_CSR_RS1IMM_LSB+1-1)
`define DECINFO_CSR_RS1IMM  `DECINFO_CSR_RS1IMM_MSB :`DECINFO_CSR_RS1IMM_LSB
    `define DECINFO_CSR_ZIMM_LSB    (`DECINFO_CSR_RS1IMM_MSB+1)
    `define DECINFO_CSR_ZIMM_MSB    (`DECINFO_CSR_ZIMM_LSB+5-1)
`define DECINFO_CSR_ZIMM    `DECINFO_CSR_ZIMM_MSB :`DECINFO_CSR_ZIMM_LSB
    `define DECINFO_CSR_RS1X0_LSB   (`DECINFO_CSR_ZIMM_MSB+1)
    `define DECINFO_CSR_RS1X0_MSB   (`DECINFO_CSR_RS1X0_LSB+1-1)
`define DECINFO_CSR_RS1X0   `DECINFO_CSR_RS1X0_MSB :`DECINFO_CSR_RS1X0_LSB
    `define DECINFO_CSR_CSRIDX_LSB  (`DECINFO_CSR_RS1X0_MSB+1)
    `define DECINFO_CSR_CSRIDX_MSB  (`DECINFO_CSR_CSRIDX_LSB+12-1)
`define DECINFO_CSR_CSRIDX  `DECINFO_CSR_CSRIDX_MSB :`DECINFO_CSR_CSRIDX_LSB
    `define DECINFO_CSR_ECALL_LSB   (`DECINFO_CSR_CSRIDX_MSB+1)
    `define DECINFO_CSR_ECALL_MSB   (`DECINFO_CSR_ECALL_LSB+1-1)
`define DECINFO_CSR_ECALL   `DECINFO_CSR_ECALL_MSB :`DECINFO_CSR_ECALL_LSB
    `define DECINFO_CSR_EBREAK_LSB  (`DECINFO_CSR_ECALL_MSB+1)
    `define DECINFO_CSR_EBREAK_MSB  (`DECINFO_CSR_EBREAK_LSB+1-1)
`define DECINFO_CSR_EBREAK  `DECINFO_CSR_EBREAK_MSB :`DECINFO_CSR_EBREAK_LSB
    `define DECINFO_CSR_MRET_LSB    (`DECINFO_CSR_EBREAK_MSB+1)
    `define DECINFO_CSR_MRET_MSB    (`DECINFO_CSR_MRET_LSB+1-1)
`define DECINFO_CSR_MRET    `DECINFO_CSR_MRET_MSB :`DECINFO_CSR_MRET_LSB

`define DECINFO_BUS_CSR_WIDTH   (`DECINFO_CSR_MRET_MSB+1)  // = 28


// ----------------        MDU group        ---------------- //
    `define DECINFO_MDU_OP_LSB      `DECINFO_SUBDECINFO_LSB
    `define DECINFO_MDU_OP_MSB      (`DECINFO_MDU_OP_LSB+3-1)
`define DECINFO_MDU_OP      `DECINFO_MDU_OP_MSB :`DECINFO_MDU_OP_LSB

`define DECINFO_BUS_MDU_WIDTH   (`DECINFO_MDU_OP_MSB+1)  // = 6

// These 2-bit multiply operation codes match RV32M funct3[1:0].
`define MDU_OP_MUL       2'b00
`define MDU_OP_MULH      2'b01
`define MDU_OP_MULHSU    2'b10
`define MDU_OP_MULHU     2'b11
// These 2-bit divide operation codes match RV32M funct3[1:0].
`define MDU_DIV_OP_DIV   2'b00
`define MDU_DIV_OP_DIVU  2'b01
`define MDU_DIV_OP_REM   2'b10
`define MDU_DIV_OP_REMU  2'b11


`define DECINFO_BUS_WIDTH       `DECINFO_BUS_CSR_WIDTH  // max(ALU=16, LSU=9, BRU=15, CSR=28)

// ----------------        CSR Addresses        ---------------- //
`define CSR_MSTATUS   12'h300
`define CSR_MISA      12'h301
`define CSR_MTVEC     12'h305
`define CSR_MSCRATCH  12'h340
`define CSR_MEPC      12'h341
`define CSR_MCAUSE    12'h342
`define CSR_MTVAL     12'h343
`define CSR_MCYCLE    12'hB00
`define CSR_MCYCLEH   12'hB80
`define CSR_MINSTRET  12'hB02
`define CSR_MINSTRETH 12'hB82

`define CSR_CYCLE     12'hC00
`define CSR_CYCLEH    12'hC80
