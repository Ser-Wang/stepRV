`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/02/27
// Design Name: StepRV_v0
// Module Name: exu_lsu
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module exu_lsu(
    input wire [31:0] i_lsu_rs1,
    input wire [31:0] i_lsu_rs2,
    input wire [31:0] i_lsu_imm,
    input wire [`DECINFO_BUS_LSU_WIDTH-1:0] i_dec_info_bus_lsu,
    output wire [31:0] o_mem_addr_exu,
    output wire [31:0] o_mem_wr_data_exu,
    output wire o_mem_wr_en_exu,
    output wire [7:0] o_mem_req_info_bus, // {lsu_req_load, lsu_req_info_size, lsu_req_info_usign}
    output wire o_exc_req_load_addr_misaligned_lsu,
    output wire o_exc_req_store_addr_misaligned_lsu,
    output wire [31:0] o_exc_tval_addr_misaligned_lsu
    );

wire addr_misaligned;


// ----------------        dec_info debus        ---------------- //
// ---- dec_info debus
wire lsu_req_load       = i_dec_info_bus_lsu[`DECINFO_LSU_LOAD];
wire lsu_req_store      = i_dec_info_bus_lsu[`DECINFO_LSU_STORE];
wire lsu_req_info_usign = i_dec_info_bus_lsu[`DECINFO_LSU_USIGN];
wire [1:0] lsu_req_info_size  = i_dec_info_bus_lsu[`DECINFO_LSU_SIZE];  // 00:b 01:h 10:w


// ----------------        addr_gen, load, store        ---------------- //
// ---- Address Generation
wire [31:0] lsu_req_ag_op1 = i_lsu_rs1;
wire [31:0] lsu_req_ag_op2 = i_lsu_imm;
// wire [31:0] lsu_req_ag_op2 = (i_dec_info_bus_lsu[`DECINFO_LSU_OP2IMM]) ? i_lsu_imm : i_lsu_rs2;
wire [31:0] mem_addr = lsu_req_ag_op1 + lsu_req_ag_op2;
assign o_mem_addr_exu = mem_addr;

// ---- store data mask
// support addr not aligned by 4 bytes.
// For Byte instructions (00), support any 2-bit offset.
// For Halfword (01) and Word (10), maintain existing alignment support.
wire [1:0] addr_offset = mem_addr[1:0];

wire [3:0] mem_wr_mask;
assign mem_wr_mask = (lsu_req_info_size == 2'b10) ? 4'b1111 :
                      (lsu_req_info_size == 2'b01) ? (addr_offset[1] ? 4'b1100 : 4'b0011) :
                      (lsu_req_info_size == 2'b00) ? (4'b0001 << addr_offset) : 4'b0000;    // mask will be 4'b0001 when it isn't load/store instr


// ---- store data
wire [31:0] lsu_data_tostore;

wire [31:0] data_sb = (addr_offset == 2'b00) ? {24'b0, i_lsu_rs2[7:0]} :
                      (addr_offset == 2'b01) ? {16'b0, i_lsu_rs2[7:0], 8'b0} :
                      (addr_offset == 2'b10) ? {8'b0,  i_lsu_rs2[7:0], 16'b0} :
                                                 {i_lsu_rs2[7:0], 24'b0};

wire [31:0] data_sh = (addr_offset[1]) ? {i_lsu_rs2[15:0], 16'b0} : {16'b0, i_lsu_rs2[15:0]};

wire [31:0] data_sw = i_lsu_rs2;

assign o_mem_wr_data_exu = (lsu_req_info_size == 2'b10) ? data_sw :
                            (lsu_req_info_size == 2'b01) ? data_sh :
                                                           data_sb;

// assign lsu_data_tostore[7:0] = i_lsu_rs2[7:0];
// assign lsu_data_tostore[15:8] = (lsu_req_info_size != 2'b00) ? i_lsu_rs2[15:8] : 8'b0;
// assign lsu_data_tostore[31:16] = (lsu_req_info_size == 2'b10) ? i_lsu_rs2[31:16] : 16'b0;


// ---- ctrl logic
assign o_mem_wr_en_exu = lsu_req_store && !addr_misaligned; // Prevent writing if address is misaligned
assign o_mem_req_info_bus = {mem_wr_mask, lsu_req_load && !addr_misaligned, lsu_req_info_size, lsu_req_info_usign};


//// ----------------------------------------------------------------------------------------------------------
// ---- Misalignment Check
assign addr_misaligned = (lsu_req_load || lsu_req_store) && (
                       (lsu_req_info_size == 2'b10 && mem_addr[1:0] != 2'b00) || // Word must be 4-byte aligned
                       (lsu_req_info_size == 2'b01 && mem_addr[0]   != 1'b0 )    // Halfword must be 2-byte aligned
                       );

assign o_exc_req_load_addr_misaligned_lsu = addr_misaligned & lsu_req_load;
// Store address misaligned is RV32I store-only today. When A extension is added, this path may expand to store/AMO address misaligned.
assign o_exc_req_store_addr_misaligned_lsu = addr_misaligned & lsu_req_store;
assign o_exc_tval_addr_misaligned_lsu = mem_addr;


endmodule
