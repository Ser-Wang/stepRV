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
wire [`RFIDX_WIDTH-1:0] wrbk_rdidx_idu;
wire [31:0] dec_imm;
wire [`DECINFO_BUS_WIDTH-1:0] dec_info_bus_id;
wire wrbk_rdwen_idu;
wire need_rs1_idu;
wire need_rs2_idu;

// ex_hazard_ctrl
wire need_rs1_exu;
wire need_rs2_exu;
wire [`RFIDX_WIDTH-1:0] rs1idx_exu;
wire [`RFIDX_WIDTH-1:0] rs2idx_exu;
wire [1:0] fwding_rs1_sel;
wire [1:0] fwding_rs2_sel;
wire is_load_req_exu;

// flush & stall
wire [4:0] stall;
wire [3:0] flush;

// ex_2_mema
wire [31:0] mema_addr_exu;
wire mema_wren_exu;
wire [31:0] mema_wr_data_exu;
wire [3:0] mema_ld_info;

wire [31:0] wrbk_data_exu;
wire [`RFIDX_WIDTH-1:0] wrbk_rdidx_exu;
wire wrbk_rdwen_exu;

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
    .i_wrbk_wen         (rf_wrbk_wen      ),
    .i_wrbk_rdidx       (rf_wrbk_rdidx    ),   // write back
    .i_wrbk_data        (rf_wrbk_data     )
    );

assign rf_wrbk_wen = wrbk_rdwen_wbu;
assign rf_wrbk_rdidx = wrbk_rdidx_wbu;
assign rf_wrbk_data = wrbk_data_wbu;


ifu u_ifu(
    .clk        (clk    ),
    .rst_n      (rst_n  ),
    .i_stall    (stall[`STALL_PC]),
    .o_pc_if    (pc_if  )
    );

idu u_idu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_stall            (stall[`STALL_IF_ID]),
    .i_flush            (flush[`FLUSH_IF_ID]),
    .i_instr            (i_instr_if_data),
    .i_pc_if            (pc_if          ),
    .o_dec_rs1idx       (rf_read_rs1_idx),
    .o_dec_rs2idx       (rf_read_rs2_idx),
    .o_dec_rdidx        (wrbk_rdidx_idu ),
    .o_dec_imm          (dec_imm        ),
    .o_dec_info_bus_id  (dec_info_bus_id),
    .o_dec_rdwen_id     (wrbk_rdwen_idu ),
    .o_need_rs1_idu     (need_rs1_idu   ),  // decision basis: 该信号不能直接送入forwarding_ctrl模块，一方面fwd_ctrl工作在ex级，另一方面need_rs信号须与exu状态保持一致，如果stall要同时stall住，因此最好放在exu中
    .o_need_rs2_idu     (need_rs2_idu   ),
    // Pipeline_reg_out
    .o_instr_id         (instr_id       ),    // for what
    .o_pc_id            (pc_id          )
    );

exu u_exu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_stall            (stall[`STALL_ID_EX]),
    .i_flush            (flush[`FLUSH_ID_EX]),
    // dpath
    .i_rf_rs1_data      (rf_read_rs1_data   ),
    .i_rf_rs2_data      (rf_read_rs2_data   ),
    .i_dec_imm          (dec_imm            ),
    .i_pc_id            (pc_id              ),
    .i_dec_info_bus_id  (dec_info_bus_id    ),
    .o_wrbk_data_exu    (wrbk_data_exu      ),
    // forwarding
    .i_need_rs1_idu     (need_rs1_idu       ),
    .i_need_rs2_idu     (need_rs2_idu       ),
    .o_need_rs1_exu     (need_rs1_exu       ),
    .o_need_rs2_exu     (need_rs2_exu       ),
    .o_rs1idx_exu       (rs1idx_exu         ),
    .o_rs2idx_exu       (rs2idx_exu         ),
    .i_fwd_wrbk_data_mau(wrbk_data_mau      ),
    .i_fwd_wrbk_data_wbu(wrbk_data_wbu      ),
    .i_fwding_rs1_sel   (fwding_rs1_sel     ),
    .i_fwding_rs2_sel   (fwding_rs2_sel     ),
    // branch
    .o_pc_bru_next      (o_pc_bru_next      ),
    .o_jump_flag        (o_jump_flag        ),
    // mem access
    .o_mema_addr_exu    (mema_addr_exu      ),
    .o_mema_wren_exu    (mema_wren_exu      ),
    .o_mema_wr_data_exu (mema_wr_data_exu   ),
    .o_mema_ld_info     (mema_ld_info       ), // {lsu_req_load, lsu_req_info_size, lsu_req_info_usign}
    // pass by
    .i_wrbk_rdidx_id    (wrbk_rdidx_idu     ),
    .i_wrbk_rdwen_id    (wrbk_rdwen_idu     ),
    .o_wrbk_rdidx_ex    (wrbk_rdidx_exu     ),
    .o_wrbk_rdwen_ex    (wrbk_rdwen_exu     )
    );


ctrl_hazard u_ctrl_hazard(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    // for load-use hazard
    .i_need_rs1_idu     (need_rs1_idu       ),
    .i_need_rs2_idu     (need_rs2_idu       ),
    .i_rs1idx_idu       (rf_read_rs1_idx    ),
    .i_rs2idx_idu       (rf_read_rs2_idx    ),
    .i_is_load_req_exu  (is_load_req_exu    ),
    .i_wrbk_rdidx_exu   (wrbk_rdidx_exu     ),
    // for forwarding
    .i_need_rs1_exu     (need_rs1_exu       ),
    .i_need_rs2_exu     (need_rs2_exu       ),
    .i_rs1idx_exu       (rs1idx_exu         ),
    .i_rs2idx_exu       (rs2idx_exu         ),
    .i_wrbk_rdwen_mau   (wrbk_rdwen_mau     ),
    .i_wrbk_rdidx_mau   (wrbk_rdidx_mau     ),
    .i_wrbk_rdwen_wbu   (wrbk_rdwen_wbu     ),
    .i_wrbk_rdidx_wbu   (wrbk_rdidx_wbu     ),
    .o_fwding_rs1_sel   (fwding_rs1_sel     ),
    .o_fwding_rs2_sel   (fwding_rs2_sel     ),
    // flush & stall
    .o_stall            (stall              ),
    .o_flush            (flush              )
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
    .i_wrbk_data_exu    (wrbk_data_exu  ),
    .i_wrbk_rdidx_exu   (wrbk_rdidx_exu ),
    .i_wrbk_rdwen_exu   (wrbk_rdwen_exu ),
    .o_wrbk_data_mau    (wrbk_data_mau  ),
    .o_wrbk_rdidx_mau   (wrbk_rdidx_mau ),
    .o_wrbk_rdwen_mau   (wrbk_rdwen_mau )
    );

wbu u_wbu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    // pass by
    .i_wrbk_data_mau    (wrbk_data_mau  ),
    .i_wrbk_rdidx_mau   (wrbk_rdidx_mau ),
    .i_wrbk_rdwen_mau   (wrbk_rdwen_mau ),
    .o_wrbk_data_wbu    (wrbk_data_wbu  ),
    .o_wrbk_rdidx_wbu   (wrbk_rdidx_wbu ),
    .o_wrbk_rdwen_wbu   (wrbk_rdwen_wbu )
    );


endmodule
