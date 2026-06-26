`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/22
// Design Name: StepRV_v0
// Module Name: core_rv32i_v0
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module core_rv32i_v0(
    input wire clk,
    input wire rst_n,
    // if
    output wire        o_fetch_req,
    output wire [31:0] o_fetch_pc,
    input  wire [31:0] i_if_instr,
    // mem access
    output wire [31:0] o_mem_addr,
    output wire o_mem_req_load,
    output wire o_mem_wr_en,
    output wire [3:0] o_mem_wr_mask,
    output wire [31:0] o_mem_wr_data,
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
wire        if_valid;
wire [31:0] fetch_pc;

// id_2_ex
wire [31:0] instr_id;
wire [31:0] pc_id;      // this and above: reg_out
wire [`RFIDX_WIDTH-1:0] wb_rd_idx_idu;
wire [31:0] dec_imm;
wire [`DECINFO_BUS_WIDTH-1:0] dec_info_bus_id;
wire wb_rd_wen_idu;
wire need_rs1_idu;
wire need_rs2_idu;

// ex_2_mem
wire [31:0] mem_addr_exu;
wire mem_wr_en_exu;
wire [31:0] mem_wr_data_exu;
wire       mem_req_load_exu;
wire [3:0] mem_wr_mask_exu;
wire [3:0] mem_req_info_bus;

wire [31:0] wb_data_exu;
wire [`RFIDX_WIDTH-1:0] wb_rd_idx_exu;
wire wb_rd_wen_exu;

// mem_2_wb
wire [31:0] wb_data_mau;
wire [`RFIDX_WIDTH-1:0] wb_rd_idx_mau;
wire wb_rd_wen_mau;

// wb_out
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
assign mem_req_load_exu = mem_req_info_bus[3];

assign o_mem_addr    = mem_addr_exu;
assign o_mem_req_load = mem_req_load_exu;
assign o_mem_wr_en   = mem_wr_en_exu;
assign o_mem_wr_mask = mem_wr_mask_exu;
assign o_mem_wr_data = mem_wr_data_exu;


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

assign rf_wb_rd_wen = wb_rd_wen_wbu;
assign rf_wb_rd_idx = wb_rd_idx_wbu;
assign rf_wb_data = wb_data_wbu;


ifu u_ifu(
    .clk            (clk    ),
    .rst_n          (rst_n  ),
    .i_stall        (stall[`STALL_PC]),
    .i_redirect_req (redirect_req_exu),
    .i_redirect_pcnext  (redirect_pcnext_exu ),
    .o_fetch_req    (o_fetch_req),
    .o_fetch_pc     (fetch_pc),
    .o_if_valid     (if_valid),
    .o_instr_pc     (instr_pc)
    );

wire [31:0] instr_to_idu = if_valid ? i_if_instr : `INSTR_NOP;
idu u_idu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_stall            (stall[`STALL_IF_ID]),
    .i_flush            (flush[`FLUSH_IF_ID]),
    .i_instr            (instr_to_idu   ),
    .i_pc_if            (instr_pc       ),
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
    .i_fwd_wb_data_mau  (wb_data_mau        ),
    .i_fwd_wb_data_wbu  (wb_data_wbu        ),
    .i_fwding_rs1_sel   (fwding_rs1_sel     ),
    .i_fwding_rs2_sel   (fwding_rs2_sel     ),
    // redirect / exception
    .o_redirect_req     (redirect_req_exu   ),
    .o_redirect_pcnext  (redirect_pcnext_exu),
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
    // for load-use hazard
    .i_need_rs1_idu     (need_rs1_idu       ),
    .i_need_rs2_idu     (need_rs2_idu       ),
    .i_rs1idx_idu       (rf_read_rs1_idx    ),
    .i_rs2idx_idu       (rf_read_rs2_idx    ),
    .i_is_load_req_exu  (is_load_req_exu    ),
    .i_wb_rd_idx_exu    (wb_rd_idx_exu      ),
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
    .i_mem_addr_exu     (mem_addr_exu       ),
    .i_mem_req_info_bus (mem_req_info_bus   ),
    .i_mem_rd_data_mau  (i_mem_rd_data      ),
    // pass by
    .i_wb_data_exu      (wb_data_exu    ),
    .i_wb_rd_idx_exu    (wb_rd_idx_exu  ),
    .i_wb_rd_wen_exu    (wb_rd_wen_exu  ),
    .o_wb_data_mau      (wb_data_mau    ),
    .o_wb_rd_idx_mau    (wb_rd_idx_mau  ),
    .o_wb_rd_wen_mau    (wb_rd_wen_mau  )
    );

wbu u_wbu(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
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
    .i_exc_req      (exc_req_exu    ),
    .i_exc_epc      (exc_epc_exu    ),
    .i_exc_cause    (exc_cause_exu  ),
    .i_exc_tval     (exc_tval_exu   ),
    .i_trap_ret_req (trap_ret_req_exu ),
    .i_instr_ret_en (1'b0           ) // Tied to 0 for now
    );

endmodule
