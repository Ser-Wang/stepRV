`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/22
// Design Name: StepRV_v0
// Module Name: core
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module core(
    input wire clk,
    input wire rst_n,
    // if
    output wire        o_fetch_req,
    output wire [31:0] o_fetch_pc,
    input  wire        i_fetch_req_rdy,
    input  wire        i_if_rsp_vld,
    output wire        o_if_rsp_rdy,
    input  wire [31:0] i_if_instr,
    // mem access
    output wire o_mem_req_vld,
    input  wire i_mem_req_rdy,
    output wire [31:0] o_mem_addr,
    output wire o_mem_req_load,
    output wire o_mem_wr_en,
    output wire [1:0] o_mem_size,
    output wire [3:0] o_mem_wr_mask,
    output wire [31:0] o_mem_wr_data,
    input  wire i_mem_rsp_vld,
    output wire o_mem_rsp_rdy,
    input  wire [31:0] i_mem_rd_data
    );

////********    Wires    ********////
//---- regfile
wire [`RFIDX_WIDTH-1:0] rf_read_rs1_idx;
wire [`RFIDX_WIDTH-1:0] rf_read_rs2_idx;
wire [31:0] rf_read_rs1_data;
wire [31:0] rf_read_rs2_data;
wire rf_wb_rd_wen;
wire [`RFIDX_WIDTH-1:0] rf_wb_rd_idx;
wire [31:0] rf_wb_data;

//-------- pipe data flow
// if_2_id
wire [31:0] instr_pc;  // this and above: reg_out
wire [31:0] instr_if;
wire [31:0] fetch_pc;
wire [31:0] pred_next_pc_if;
wire        if_id_vld;
wire        if_id_rdy;

// id_2_ex
wire [31:0] instr_id;
wire [31:0] pc_id;      // this and above: reg_out
wire [31:0] pred_next_pc_id;
wire        id_ex_vld;
wire        id_ex_rdy;
wire [`RFIDX_WIDTH-1:0] wb_rd_idx_idu;
wire [31:0] dec_imm;
wire [`DECINFO_BUS_WIDTH-1:0] dec_info_bus_id;
wire wb_rd_wen_idu;
wire need_rs1_idu;
wire need_rs2_idu;

// ex_2_mem
wire        ex_ma_vld;
wire        ex_ma_rdy;
wire [31:0] mem_addr_exu;
wire mem_wr_en_exu;
wire [31:0] mem_wr_data_exu;
wire [3:0] mem_wr_mask_exu;
wire [3:0] mem_req_info_bus;

wire [31:0] wb_data_exu;
wire [`RFIDX_WIDTH-1:0] wb_rd_idx_exu;
wire wb_rd_wen_exu;

// mem_2_wb
wire        ma_wb_vld;
wire        ma_wb_rdy;
wire [31:0] wb_data_mau;
wire [31:0] fwd_data_mau;
wire [`RFIDX_WIDTH-1:0] wb_rd_idx_mau;
wire wb_rd_wen_mau;

// wb_out
wire        wb_vld;
wire        wb_rdy;
wire [31:0] wb_data_wbu;
wire [`RFIDX_WIDTH-1:0] wb_rd_idx_wbu;
wire wb_rd_wen_wbu;

//-------- ctrl
// ex_hazard_ctrl
wire need_rs1_exu;
wire need_rs2_exu;
wire [`RFIDX_WIDTH-1:0] rs1idx_exu;
wire [`RFIDX_WIDTH-1:0] rs2idx_exu;
wire [1:0] fwding_rs1_sel;
wire [1:0] fwding_rs2_sel;
wire is_load_req_exu;

// redirect / exception
wire        redirect_req_exu;
wire [31:0] redirect_pcnext_exu;
wire        trap_ret_req_exu;
wire        exc_req_exu;
wire [31:0] exc_epc_exu;
wire [31:0] exc_cause_exu;
wire [31:0] exc_tval_exu;

// branch predictor training / invalidation
wire        bp_update_vld;
wire [31:0] bp_update_pc;
wire        bp_update_is_cond;
wire        bp_update_taken;
wire [31:0] bp_update_target;
wire        bp_invalidate;
wire        ras_resolve_fire;
wire        ras_resolve_pop;
wire        ras_resolve_push;
wire [31:0] ras_resolve_push_addr;

// csr
wire [11:0] csr_idx;
wire        csr_wr_req;
wire [31:0] csr_wr_data;
wire [31:0] csr_rd_data;
wire        csr_illegal_access_raw;
wire [31:0] csr_mtvec;
wire [31:0] csr_mepc;

// flush & stall
wire [4:0] stall;
wire [3:0] flush;


////********    IO Insts    ********////
assign o_fetch_pc = fetch_pc;
assign wb_rdy = 1'b1;


regfile u_regfile(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_read_rs1_idx     (rf_read_rs1_idx  ),
    .i_read_rs2_idx     (rf_read_rs2_idx  ),
    .o_read_rs1_data    (rf_read_rs1_data ),
    .o_read_rs2_data    (rf_read_rs2_data ),
    .i_wb_rd_wen        (rf_wb_rd_wen     ),
    .i_wb_rd_idx        (rf_wb_rd_idx     ),
    .i_wb_data          (rf_wb_data       )
    );

// wb_rd_wen_wbu is already qualified by the WB-stage valid bit in WBU.
assign rf_wb_rd_wen = wb_rd_wen_wbu;
assign rf_wb_rd_idx = wb_rd_idx_wbu;
assign rf_wb_data = wb_data_wbu;


ifu u_ifu(
    .clk            (clk    ),
    .rst_n          (rst_n  ),
    .i_stall        (stall[`STALL_PC]),
    .i_if_id_rdy    (if_id_rdy),
    .i_redirect_req (redirect_req_exu),
    .i_redirect_pcnext  (redirect_pcnext_exu ),
    .i_bp_update_vld    (bp_update_vld),
    .i_bp_update_pc     (bp_update_pc),
    .i_bp_update_is_cond(bp_update_is_cond),
    .i_bp_update_taken  (bp_update_taken),
    .i_bp_update_target (bp_update_target),
    .i_bp_invalidate    (bp_invalidate),
    .i_ras_resolve_fire (ras_resolve_fire),
    .i_ras_resolve_pop  (ras_resolve_pop),
    .i_ras_resolve_push (ras_resolve_push),
    .i_ras_resolve_push_addr (ras_resolve_push_addr),
    .o_if_req_vld   (o_fetch_req),
    .i_if_req_rdy   (i_fetch_req_rdy),
    .o_if_req_addr  (fetch_pc),
    .i_if_rsp_vld   (i_if_rsp_vld),
    .o_if_rsp_rdy   (o_if_rsp_rdy),
    .i_if_rsp_data  (i_if_instr),
    .o_if_id_vld    (if_id_vld),
    .o_instr_pc     (instr_pc),
    .o_instr_if     (instr_if),
    .o_pred_next_pc_if (pred_next_pc_if)
    );

idu u_idu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_stall            (stall[`STALL_IF_ID]),
    .i_flush            (flush[`FLUSH_IF_ID]),
    .i_if_id_vld        (if_id_vld      ),
    .o_if_id_rdy        (if_id_rdy      ),
    .o_id_ex_vld        (id_ex_vld      ),
    .i_id_ex_rdy        (id_ex_rdy      ),
    .i_instr            (instr_if       ),
    .i_pc_if            (instr_pc       ),
    .i_pred_next_pc_if  (pred_next_pc_if),
    .o_dec_rs1idx       (rf_read_rs1_idx),
    .o_dec_rs2idx       (rf_read_rs2_idx),
    .o_dec_rd_idx       (wb_rd_idx_idu  ),
    .o_dec_imm          (dec_imm        ),
    .o_dec_info_bus_id  (dec_info_bus_id),
    .o_dec_rd_wen_id    (wb_rd_wen_idu  ),
    .o_need_rs1_idu     (need_rs1_idu   ),  // Decision basis: This signal cannot be directly sent to forwarding_ctrl. fwd_ctrl operates in EX stage, and the need_rs signal must stay consistent with the EXU state; if stalled, it must be stalled together. Thus, it is best kept inside EXU.
    .o_need_rs2_idu     (need_rs2_idu   ),
    // Pipeline_reg_out
    .o_instr_id         (instr_id       ),    // for pipeline debug
    .o_pc_id            (pc_id          ),
    .o_pred_next_pc_id  (pred_next_pc_id)
    );

exu u_exu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_stall            (stall[`STALL_ID_EX]),
    .i_flush            (flush[`FLUSH_ID_EX]),
    .i_id_ex_vld        (id_ex_vld      ),
    .o_id_ex_rdy        (id_ex_rdy      ),
    .o_ex_ma_vld        (ex_ma_vld      ),
    .i_ex_ma_rdy        (ex_ma_rdy      ),
    // dpath
    .i_rf_rs1_data      (rf_read_rs1_data   ),
    .i_rf_rs2_data      (rf_read_rs2_data   ),
    .i_dec_imm          (dec_imm            ),
    .i_pc_id            (pc_id              ),
    .i_pred_next_pc_id  (pred_next_pc_id    ),
    .i_dec_info_bus_id  (dec_info_bus_id    ),
    .o_wb_data_exu      (wb_data_exu        ),
    // forwarding
    .i_need_rs1_idu     (need_rs1_idu       ),
    .i_need_rs2_idu     (need_rs2_idu       ),
    .o_need_rs1_exu     (need_rs1_exu       ),
    .o_need_rs2_exu     (need_rs2_exu       ),
    .i_rs1idx_idu       (rf_read_rs1_idx    ),
    .i_rs2idx_idu       (rf_read_rs2_idx    ),
    .o_rs1idx_exu       (rs1idx_exu         ),
    .o_rs2idx_exu       (rs2idx_exu         ),
    .i_fwd_wb_data_mau  (fwd_data_mau       ),
    .i_fwd_wb_data_wbu  (wb_data_wbu        ),
    .i_fwding_rs1_sel   (fwding_rs1_sel     ),
    .i_fwding_rs2_sel   (fwding_rs2_sel     ),
    // redirect / exception
    .o_redirect_req     (redirect_req_exu   ),
    .o_redirect_pcnext  (redirect_pcnext_exu),
    .o_bp_update_vld    (bp_update_vld      ),
    .o_bp_update_pc     (bp_update_pc       ),
    .o_bp_update_is_cond(bp_update_is_cond  ),
    .o_bp_update_taken  (bp_update_taken    ),
    .o_bp_update_target (bp_update_target   ),
    .o_bp_invalidate    (bp_invalidate      ),
    .o_ras_resolve_fire (ras_resolve_fire   ),
    .o_ras_resolve_pop  (ras_resolve_pop    ),
    .o_ras_resolve_push (ras_resolve_push   ),
    .o_ras_resolve_push_addr (ras_resolve_push_addr),
    // mem access
    .o_mem_addr_exu     (mem_addr_exu       ),
    .o_mem_wr_en_exu    (mem_wr_en_exu      ),
    .o_mem_wr_data_exu  (mem_wr_data_exu    ),
    .o_mem_wr_mask_exu  (mem_wr_mask_exu    ),
    .o_mem_req_info_bus (mem_req_info_bus   ), // {lsu_req_load, lsu_req_info_size, lsu_req_info_usign}
    .o_is_load_req_exu  (is_load_req_exu    ),
    // csr
    .o_csr_idx          (csr_idx            ),
    .o_csr_wr_req       (csr_wr_req         ),
    .o_csr_wr_data      (csr_wr_data        ),
    .i_csr_rd_data      (csr_rd_data        ),
    .i_csr_illegal_access_raw (csr_illegal_access_raw),
    .i_csr_mtvec        (csr_mtvec          ),
    .i_csr_mepc         (csr_mepc           ),
    .o_exc_req          (exc_req_exu        ),
    .o_exc_epc          (exc_epc_exu        ),
    .o_exc_cause        (exc_cause_exu      ),
    .o_exc_tval         (exc_tval_exu       ),
    .o_trap_ret_req     (trap_ret_req_exu   ),
    // pass by
    .i_wb_rd_idx_idu    (wb_rd_idx_idu      ),
    .i_wb_rd_wen_idu    (wb_rd_wen_idu      ),
    .o_wb_rd_idx_exu    (wb_rd_idx_exu      ),
    .o_wb_rd_wen_exu    (wb_rd_wen_exu      )
    );

ctrl_hazard u_ctrl_hazard(
    // redirect
    .i_redirect_req     (redirect_req_exu   ),
    .i_id_ex_vld        (id_ex_vld          ),
    // for load-use hazard
    .i_need_rs1_idu     (need_rs1_idu       ),
    .i_need_rs2_idu     (need_rs2_idu       ),
    .i_rs1idx_idu       (rf_read_rs1_idx    ),
    .i_rs2idx_idu       (rf_read_rs2_idx    ),
    .i_is_load_req_exu  (is_load_req_exu    ),
    .i_wb_rd_idx_exu    (wb_rd_idx_exu      ),
    .i_ex_ma_rdy        (ex_ma_rdy           ),
    // for forwarding
    .i_need_rs1_exu     (need_rs1_exu       ),
    .i_need_rs2_exu     (need_rs2_exu       ),
    .i_rs1idx_exu       (rs1idx_exu         ),
    .i_rs2idx_exu       (rs2idx_exu         ),
    .i_wb_rd_wen_mau    (wb_rd_wen_mau      ),
    .i_wb_rd_idx_mau    (wb_rd_idx_mau      ),
    .i_wb_rd_wen_wbu    (wb_rd_wen_wbu      ),
    .i_wb_rd_idx_wbu    (wb_rd_idx_wbu      ),
    .o_fwding_rs1_sel   (fwding_rs1_sel     ),
    .o_fwding_rs2_sel   (fwding_rs2_sel     ),
    // flush & stall
    .o_stall            (stall  ),
    .o_flush            (flush  )
    );


mau u_mau(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_ex_ma_vld        (ex_ma_vld      ),
    .o_ex_ma_rdy        (ex_ma_rdy      ),
    .o_ma_wb_vld        (ma_wb_vld      ),
    .i_ma_wb_rdy        (ma_wb_rdy      ),
    .i_mem_addr_exu     (mem_addr_exu       ),
    .i_mem_wr_data_exu  (mem_wr_data_exu    ),
    .i_mem_wr_en_exu    (mem_wr_en_exu      ),
    .i_mem_wr_mask_exu  (mem_wr_mask_exu    ),
    .i_mem_req_info_bus (mem_req_info_bus   ),
    .o_mem_req_vld      (o_mem_req_vld      ),
    .i_mem_req_rdy      (i_mem_req_rdy      ),
    .o_mem_addr         (o_mem_addr         ),
    .o_mem_req_load     (o_mem_req_load     ),
    .o_mem_wr_en        (o_mem_wr_en        ),
    .o_mem_size         (o_mem_size         ),
    .o_mem_wr_mask      (o_mem_wr_mask      ),
    .o_mem_wr_data      (o_mem_wr_data      ),
    .i_mem_rsp_vld      (i_mem_rsp_vld      ),
    .o_mem_rsp_rdy      (o_mem_rsp_rdy      ),
    .i_mem_rsp_data     (i_mem_rd_data      ),
    // pass by
    .i_wb_data_exu      (wb_data_exu    ),
    .i_wb_rd_idx_exu    (wb_rd_idx_exu  ),
    .i_wb_rd_wen_exu    (wb_rd_wen_exu  ),
    .o_wb_data_mau      (wb_data_mau    ),
    .o_fwd_data_mau     (fwd_data_mau   ),
    .o_wb_rd_idx_mau    (wb_rd_idx_mau  ),
    .o_wb_rd_wen_mau    (wb_rd_wen_mau  )
    );

wbu u_wbu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_ma_wb_vld        (ma_wb_vld      ),
    .o_ma_wb_rdy        (ma_wb_rdy      ),
    .o_wb_vld           (wb_vld         ),
    .i_wb_rdy           (wb_rdy         ),
    // pass by
    .i_wb_data_mau      (wb_data_mau    ),
    .i_wb_rd_idx_mau    (wb_rd_idx_mau  ),
    .i_wb_rd_wen_mau    (wb_rd_wen_mau  ),
    .o_wb_data_wbu      (wb_data_wbu    ),
    .o_wb_rd_idx_wbu    (wb_rd_idx_wbu  ),
    .o_wb_rd_wen_wbu    (wb_rd_wen_wbu  )
    );

csr_regs u_csr_regs(
    .clk            (clk            ),
    .rst_n          (rst_n          ),
    .i_stall        (stall          ),
    .i_flush        (flush          ),
    .i_csr_idx      (csr_idx        ),
    .i_csr_wr_req   (csr_wr_req     ),
    .i_csr_wr_data  (csr_wr_data    ),
    .o_csr_rd_data  (csr_rd_data    ),
    .o_csr_illegal_access_raw (csr_illegal_access_raw),
    .o_mtvec        (csr_mtvec      ),
    .o_mepc         (csr_mepc       ),
    .i_exc_req      (exc_req_exu & ex_ma_vld & ex_ma_rdy),
    .i_exc_epc      (exc_epc_exu    ),
    .i_exc_cause    (exc_cause_exu  ),
    .i_exc_tval     (exc_tval_exu   ),
    .i_trap_ret_req (trap_ret_req_exu & ex_ma_vld & ex_ma_rdy),
    .i_instr_ret_en (1'b0           ) // Tied to 0 for now
    );

endmodule
