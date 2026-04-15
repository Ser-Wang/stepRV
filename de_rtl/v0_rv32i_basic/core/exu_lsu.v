`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/27 01:13:41
// Design Name: 
// Module Name: exu_lsu
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

module exu_lsu(
    input wire clk,
    input wire rst_n,
    input wire [31:0] i_lsu_rs1,
    input wire [31:0] i_lsu_rs2,
    input wire [31:0] i_lsu_imm,
    input wire [`DECINFO_BUS_LSU_WIDTH-1:0] i_dec_info_bus_lsu,
    output wire [31:0] o_mema_addr_exu,
    output wire [31:0] o_mema_wr_data_exu,
    output wire o_mema_wren_exu,
    output wire [3:0] o_mema_ld_info  // {lsu_req_load, lsu_req_info_size, lsu_req_info_usign}
    // input wire [31:0] i_mema_rd_data,
    // output wire [31:0] o_lsu_req_result
    );

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
wire [31:0] mema_addr = lsu_req_ag_op1 + lsu_req_ag_op2;
assign o_mema_addr_exu = mema_addr;

// ---- store data
wire [31:0] lsu_data_tostore;
assign lsu_data_tostore[7:0] = i_lsu_rs2[7:0];
assign lsu_data_tostore[15:8] = (lsu_req_info_size != 2'b00) ? i_lsu_rs2[15:8] : 8'b0;
assign lsu_data_tostore[31:16] = (lsu_req_info_size == 2'b10) ? i_lsu_rs2[31:16] : 16'b0;
assign o_mema_wr_data_exu = lsu_data_tostore;

// ---- ctrl logic
assign o_mema_wren_exu = lsu_req_store;
assign o_mema_ld_info = {lsu_req_load, lsu_req_info_size, lsu_req_info_usign};


endmodule
