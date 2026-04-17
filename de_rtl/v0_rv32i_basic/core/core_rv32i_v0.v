`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/22 17:00:00
// Design Name: 
// Module Name: core_rv32i_v0
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
// `include "./config.v"

module core_rv32i_v0(
    input wire clk,
    input wire rst_n,   //
    // if
    output wire [31:0] o_pc_if_addr,
    input  wire [31:0] i_instr_if_data,
    // mem access
    output wire [31:0] o_mema_addr,
    output wire o_mema_wren,
    output wire [31:0] o_mema_wr_data,
    input  wire [31:0] i_mema_rd_data
    );

////********    IO Insts    ********////
assign o_pc_if_addr = pc_if;



////********    Wires    ********////
// regfile
wire [`RFIDX_WIDTH-1:0] rf_read_rs1_idx;
wire [`RFIDX_WIDTH-1:0] rf_read_rs2_idx;
wire [31:0] rf_read_rs1_data;
wire [31:0] rf_read_rs2_data;
wire rf_wrbk_wen;
wire [`RFIDX_WIDTH-1:0] rf_wrbk_rdidx;
wire [31:0] rf_wrbk_data;

// if_2_id
wire [31:0] pc_if;  // this and above: reg_out

// id_2_ex
wire [31:0] instr_id;
wire [31:0] pc_id;      // this and above: reg_out
wire [`RFIDX_WIDTH-1:0] dec_rdidx_id;
wire [31:0] dec_imm;
wire [`DECINFO_BUS_ALU_WIDTH-1:0] dec_info_bus_id;
wire dec_rdwen_id;

// ex_2_mema
wire [31:0] mema_addr_exu;
wire mema_wren_exu;
wire [31:0] mema_wr_data_exu;
wire [3:0] mema_ld_info;

wire [31:0] wrbk_data_ex;
wire [`RFIDX_WIDTH-1:0] wrbk_rdidx_exu;
wire wrbk_wen_exu;

// mema_2_wb
wire [31:0] wrbk_data_mau;
wire [`RFIDX_WIDTH-1:0] wrbk_rdidx_mau;
wire wrbk_rdwen_mau;

// wb_out
wire [31:0] wrbk_data_wbu;
wire [`RFIDX_WIDTH-1:0] wrbk_rdidx_wbu;
wire wrbk_rdwen_wbu;


regfile u_regfile(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_read_rs1_idx     (rf_read_rs1_idx  ),
    .i_read_rs2_idx     (rf_read_rs2_idx  ),
    .o_read_rs1_data    (rf_read_rs1_data ),
    .o_read_rs2_data    (rf_read_rs2_data ),
    .i_wb_wen           (rf_wrbk_wen      ),
    .i_wb_dest_idx      (rf_wrbk_rdidx    ),   // write back
    .i_wb_dest_data     (rf_wrbk_data     )
    );

assign rf_wrbk_wen = wrbk_rdwen_wbu;
assign rf_wrbk_rdidx = wrbk_rdidx_wbu;
assign rf_wrbk_data = wrbk_data_wbu;


ifu u_ifu(
    .clk        (clk    ),
    .rst_n      (rst_n  ),
    .o_pc_if    (pc_if  )
    );

idu u_idu(
    .clk            (clk    ),
    .rst_n          (rst_n  ),
    .i_instr        (i_instr_if_data),
    .i_pc_if        (pc_if          ),
    .o_dec_rs1idx   (rf_read_rs1_idx),
    .o_dec_rs2idx   (rf_read_rs2_idx),
    .o_dec_rdidx    (dec_rdidx_id   ),
    .o_dec_imm      (dec_imm        ),
    .o_dec_info_bus_id (dec_info_bus_id   ),
    .o_dec_rdwen_id (dec_rdwen_id   ),
    // Pipeline_reg_out
    .o_instr_id     (instr_id       ),    // for what
    .o_pc_id        (pc_id          )
    );

exu u_exu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_rf_rs1_data      (rf_read_rs1_data   ),
    .i_rf_rs2_data      (rf_read_rs2_data   ),
    .i_dec_imm          (dec_imm            ),
    .i_pc_id            (pc_id              ),
    .i_dec_info_bus_id  (dec_info_bus_id    ),
    .o_wrbk_data_ex     (wrbk_data_ex       ),
    // branch
    .o_pc_bru_next      (o_pc_bru_next      ),
    .o_jump_flag        (o_jump_flag        ),
    // mem access
    .o_mema_addr_exu    (mema_addr_exu      ),
    .o_mema_wren_exu    (mema_wren_exu      ),
    .o_mema_wr_data_exu (mema_wr_data_exu   ),
    .o_mema_ld_info     (mema_ld_info       ), // {lsu_req_load, lsu_req_info_size, lsu_req_info_usign}
    // pass by
    .i_dec_rdidx_id     (dec_rdidx_id       ),
    .i_dec_rdwen_id     (dec_rdwen_id       ),
    .o_wrbk_rdidx_ex    (wrbk_rdidx_exu     ),
    .o_wrbk_wen_ex      (wrbk_wen_exu       )
    );

mau u_mau(
    .clk                (clk),
    .rst_n              (rst_n),
    .i_mema_addr_exu    (mema_addr_exu      ),
    .i_mema_wren_exu    (mema_wren_exu      ),
    .i_mema_wr_data_exu (mema_wr_data_exu   ),
    .i_mema_ld_info     (mema_ld_info       ),
    .o_mema_addr_mau    (o_mema_addr    ),
    .o_mema_wren_mau    (o_mema_wren    ),
    .o_mema_wr_data_mau (o_mema_wr_data ),
    .i_mema_rd_data_mau (i_mema_rd_data ),
    // pass by
    .i_wrbk_data_ex     (wrbk_data_ex   ),
    .i_wrbk_rdidx_ex    (wrbk_rdidx_exu ),
    .i_wrbk_rdwen_ex    (wrbk_wen_exu   ),
    .o_wrbk_data_mema   (wrbk_data_mau  ),
    .o_wrbk_rdidx_mema  (wrbk_rdidx_mau ),
    .o_wrbk_rdwen_mema  (wrbk_rdwen_mau )
    );

wbu u_wbu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    // pass by
    .i_wrbk_data_mema   (wrbk_data_mau  ),
    .i_wrbk_rdidx_mema  (wrbk_rdidx_mau ),
    .i_wrbk_rdwen_mema  (wrbk_rdwen_mau ),
    .o_wrbk_data_wb     (wrbk_data_wbu  ),
    .o_wrbk_rdidx_wb    (wrbk_rdidx_wbu ),
    .o_wrbk_rdwen_wb    (wrbk_rdwen_wbu )
    );


endmodule
