`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/02/11
// Design Name: StepRV_v0
// Module Name: exu
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module exu(
    input  wire clk,
    input  wire rst_n,
    input  wire i_stall,
    input  wire i_flush,
    input  wire [31:0] i_rf_rs1_data,
    input  wire [31:0] i_rf_rs2_data,
    input  wire [31:0] i_dec_imm,
    input  wire [31:0] i_pc_id,
    input  wire [`DECINFO_BUS_WIDTH-1:0] i_dec_info_bus_id,
    output wire [31:0] o_wb_data_exu,
    // forwarding
    input wire i_need_rs1_idu,
    input wire i_need_rs2_idu,
    output wire o_need_rs1_exu,
    output wire o_need_rs2_exu,
    input wire [`RFIDX_WIDTH-1:0] i_rs1idx_idu,
    input wire [`RFIDX_WIDTH-1:0] i_rs2idx_idu,
    output wire [`RFIDX_WIDTH-1:0] o_rs1idx_exu,
    output wire [`RFIDX_WIDTH-1:0] o_rs2idx_exu,
    input wire [31:0] i_fwd_wb_data_mau,
    input wire [31:0] i_fwd_wb_data_wbu,
    input wire [1:0] i_fwding_rs1_sel,
    input wire [1:0] i_fwding_rs2_sel,
    // redirect
    output wire        o_redirect_req,
    output wire [31:0] o_redirect_pcnext,
    // to mem access unit
    output wire [31:0] o_mem_addr_exu,
    output wire [31:0] o_mem_wr_data_exu,
    output wire o_mem_wr_en_exu,
    output wire [7:0] o_mem_req_info_bus,  // {store_mask, lsu_req_load, lsu_req_info_size, lsu_req_info_usign}
    output wire o_is_load_req_exu,
    // input  wire [31:0] i_mem_rd_data,
    // pass by
    input  wire [`RFIDX_WIDTH-1:0] i_wb_rd_idx_idu,
    input  wire i_wb_rd_wen_idu,
    output wire [`RFIDX_WIDTH-1:0] o_wb_rd_idx_exu,
    output wire o_wb_rd_wen_exu,
    // csr interface to core
    output wire [11:0] o_csr_idx,
    output wire        o_csr_wr_req,
    output wire [31:0] o_csr_wr_data,
    input  wire [31:0] i_csr_rd_data,
    input  wire        i_csr_illegal_access_raw,
    input  wire [31:0] i_csr_mtvec,
    input  wire [31:0] i_csr_mepc,
    output wire        o_exc_req,
    output wire [31:0] o_exc_epc,
    output wire [31:0] o_exc_cause,
    output wire [31:0] o_exc_tval,
    output wire        o_trap_ret_req
    );

// ================================================================
// ----------------        Pipeline Regs        ---------------- //
//---- pass by, to wb
reg [`RFIDX_WIDTH-1:0] r_wb_rd_idx_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_rd_idx_exu <= 'd0;
    end
    else if(!i_stall) begin
        r_wb_rd_idx_exu <= i_wb_rd_idx_idu;
    end
end
assign o_wb_rd_idx_exu = r_wb_rd_idx_exu;

reg r_wb_rd_wen_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_wb_rd_wen_exu <= 1'b0;
    end
    else if(i_flush) begin
        r_wb_rd_wen_exu <= 1'b0;
    end
    else if(!i_stall) begin
        r_wb_rd_wen_exu <= i_wb_rd_wen_idu;
    end
end
assign o_wb_rd_wen_exu = r_wb_rd_wen_exu & (~o_exc_req) & (~o_trap_ret_req);


// Comb in, reg 
reg [31:0] rf_rs1_r_ex, rf_rs2_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rf_rs1_r_ex <= 32'd0;
        rf_rs2_r_ex <= 32'd0;
    end
    else if(!i_stall) begin
        rf_rs1_r_ex <= i_rf_rs1_data;
        rf_rs2_r_ex <= i_rf_rs2_data;
    end
end

reg [31:0] dec_imm_r_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dec_imm_r_ex <= 32'd0;
    end
    else if(!i_stall) begin
        dec_imm_r_ex <= i_dec_imm;
    end
end

reg [31:0] r_pc_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_pc_exu <= 32'b0;
    end
    else if(!i_stall) begin
        r_pc_exu <= i_pc_id;
    end
end

reg [`DECINFO_BUS_WIDTH-1:0] r_dec_info_bus_ex;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_dec_info_bus_ex <= {`DECINFO_BUS_WIDTH{1'b0}};
    end
    else if(i_flush) begin
        r_dec_info_bus_ex <= 'd0;
    end
    else if(!i_stall) begin
        r_dec_info_bus_ex <= i_dec_info_bus_id;
    end
end

//---- for forwarding and stall
reg r_need_rs1_exu, r_need_rs2_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_need_rs1_exu <= 1'b0;
        r_need_rs2_exu <= 1'b0;
    end
    else if(i_flush) begin
        r_need_rs1_exu <= 1'b0;
        r_need_rs2_exu <= 1'b0;
    end
    else if(!i_stall) begin
        r_need_rs1_exu <= i_need_rs1_idu;
        r_need_rs2_exu <= i_need_rs2_idu;
    end
end
assign o_need_rs1_exu = r_need_rs1_exu;
assign o_need_rs2_exu = r_need_rs2_exu;


reg [`RFIDX_WIDTH-1:0] r_rs1idx_exu;
reg [`RFIDX_WIDTH-1:0] r_rs2idx_exu;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rs1idx_exu <= 'd0;
        r_rs2idx_exu <= 'd0;
    end
    else if(!i_stall) begin
        r_rs1idx_exu <= i_rs1idx_idu;
        r_rs2idx_exu <= i_rs2idx_idu;
    end
end
assign o_rs1idx_exu = r_rs1idx_exu;
assign o_rs2idx_exu = r_rs2idx_exu;


// ================================================================
// ----------------        Data Forwarding        ---------------- //
wire [`XLEN-1:0] rs1_fwded, rs2_fwded;
assign rs1_fwded = (~i_fwding_rs1_sel[1]) ? rf_rs1_r_ex : 
                   ( i_fwding_rs1_sel[0]) ? i_fwd_wb_data_wbu : i_fwd_wb_data_mau;
assign rs2_fwded = (~i_fwding_rs2_sel[1]) ? rf_rs2_r_ex : 
                   ( i_fwding_rs2_sel[0]) ? i_fwd_wb_data_wbu : i_fwd_wb_data_mau;



// ================================================================
// ----------------        Datapath Dispatch        ---------------- //
wire req_disp_alu = (r_dec_info_bus_ex[`DECINFO_GRP] == `DECINFO_GRP_ALU);
wire req_disp_lsu = (r_dec_info_bus_ex[`DECINFO_GRP] == `DECINFO_GRP_LSU);
wire req_disp_bru = (r_dec_info_bus_ex[`DECINFO_GRP] == `DECINFO_GRP_BRU);
wire req_disp_csr = (r_dec_info_bus_ex[`DECINFO_GRP] == `DECINFO_GRP_CSR);

assign o_is_load_req_exu = req_disp_lsu & r_dec_info_bus_ex[`DECINFO_LSU_LOAD];

// ---- dec_info_bus dispatch
wire [`DECINFO_BUS_ALU_WIDTH-1:0] dec_info_bus_alu = {`DECINFO_BUS_ALU_WIDTH{req_disp_alu}} & r_dec_info_bus_ex[`DECINFO_BUS_ALU_WIDTH-1:0];
wire [`DECINFO_BUS_LSU_WIDTH-1:0] dec_info_bus_lsu = {`DECINFO_BUS_LSU_WIDTH{req_disp_lsu}} & r_dec_info_bus_ex[`DECINFO_BUS_LSU_WIDTH-1:0];
wire [`DECINFO_BUS_BRU_WIDTH-1:0] dec_info_bus_bru = {`DECINFO_BUS_BRU_WIDTH{req_disp_bru}} & r_dec_info_bus_ex[`DECINFO_BUS_BRU_WIDTH-1:0];
wire [`DECINFO_BUS_CSR_WIDTH-1:0] dec_info_bus_csr = {`DECINFO_BUS_CSR_WIDTH{req_disp_csr}} & r_dec_info_bus_ex[`DECINFO_BUS_CSR_WIDTH-1:0];
// assign dec_info_bus_alu = r_dec_info_bus_ex;


// ---- rs1, rs2, imm logic-gating
wire [`XLEN-1:0] alu_rs1 = {`XLEN{req_disp_alu}} & rs1_fwded;
wire [`XLEN-1:0] alu_rs2 = {`XLEN{req_disp_alu}} & rs2_fwded;
wire [`XLEN-1:0] alu_imm = dec_imm_r_ex;
// wire [`XLEN-1:0] alu_imm = {`XLEN{req_disp_alu}} & dec_imm_r_ex;
// ALU immediate does not need isolation as it is only an input to the adder. In non-ALU requests, the mux selects RS2 (which is already isolated). This saves logic gates.
// ALU PC also does not need isolation; in non-ALU requests, the mux selects RS1 (already isolated).

wire [`XLEN-1:0] lsu_rs1 = {`XLEN{req_disp_lsu}} & rs1_fwded;
wire [`XLEN-1:0] lsu_rs2 = {`XLEN{req_disp_lsu}} & rs2_fwded;
wire [`XLEN-1:0] lsu_imm = {`XLEN{req_disp_lsu}} & dec_imm_r_ex;

wire [`XLEN-1:0] bru_rs1 = {`XLEN{req_disp_bru}} & rs1_fwded;
wire [`XLEN-1:0] bru_rs2 = {`XLEN{req_disp_bru}} & rs2_fwded;
wire [`XLEN-1:0] bru_imm = {`XLEN{req_disp_bru}} & dec_imm_r_ex;
wire [`XLEN-1:0] bru_pc = {`XLEN{req_disp_bru}} & r_pc_exu;

wire [`XLEN-1:0] csr_rs1 = {`XLEN{req_disp_csr}} & rs1_fwded;

// ---- write-back results
wire [31:0] alu_wb_data;
wire [31:0] bru_wb_data;
wire [31:0] csr_wb_data;
// wire [31:0] lsu_req_result;
// Load write-back data is selected later in MAU; LSU only contributes memory request signals here.
assign o_wb_data_exu = ({`XLEN{req_disp_alu}} & alu_wb_data)
                       | ({`XLEN{req_disp_bru}} & bru_wb_data)
                       | ({`XLEN{req_disp_csr}} & csr_wb_data);


wire redirect_req_bru;
wire [31:0] redirect_pcnext_bru;
// ----------------        Exception        ---------------- //
wire csr_op_req;
wire exc_req_ecall;
wire exc_req_ebreak;
wire trap_ret_req_mret;

wire exc_req_illegal_csr_access;
wire exc_req_instr_addr_misaligned_bru;
wire [31:0] exc_tval_instr_addr_misaligned_bru;
wire exc_req_load_addr_misaligned_lsu;
wire exc_req_store_addr_misaligned_lsu;
wire [31:0] exc_tval_addr_misaligned_lsu;

assign exc_req_illegal_csr_access = i_csr_illegal_access_raw & csr_op_req;
// i_csr_illegal_access_raw is combinational by CSR index/request; only trust it for real CSR accesses.
assign o_trap_ret_req = trap_ret_req_mret;
assign o_exc_req = exc_req_ebreak | exc_req_ecall
                 | exc_req_illegal_csr_access
                 | exc_req_instr_addr_misaligned_bru
                 | exc_req_load_addr_misaligned_lsu
                 | exc_req_store_addr_misaligned_lsu;
assign o_exc_epc = r_pc_exu;
assign o_exc_cause = ({32{exc_req_ebreak}} & 32'd3)
                   | ({32{exc_req_ecall}} & 32'd11)
                   | ({32{exc_req_instr_addr_misaligned_bru}} & 32'd0)
                   | ({32{exc_req_load_addr_misaligned_lsu}} & 32'd4)
                   | ({32{exc_req_store_addr_misaligned_lsu}} & 32'd6)
                   | ({32{exc_req_illegal_csr_access}} & 32'd2);
assign o_exc_tval = ({32{exc_req_instr_addr_misaligned_bru}} & exc_tval_instr_addr_misaligned_bru)
                  | ({32{exc_req_load_addr_misaligned_lsu | exc_req_store_addr_misaligned_lsu}} & exc_tval_addr_misaligned_lsu);

// All EX-stage redirect sources are arbitrated here. This keeps the core top
// level source-agnostic and leaves one expandable redirect port for future cache,
// debug, interrupt, or prediction-recovery flows.
assign o_redirect_req = o_exc_req | o_trap_ret_req | redirect_req_bru;
assign o_redirect_pcnext = o_exc_req       ? i_csr_mtvec         :
                           o_trap_ret_req  ? i_csr_mepc          :
                                             redirect_pcnext_bru;


// ----------------        Instantiations        ---------------- //

// // ---- op1 and op2
// wire [31:0] alu_req_op1, alu_req_op2;
// assign alu_req_op1 = (dec_info_bus_alu[`DECINFO_ALU_OP1PC]) ? r_pc_exu : rf_rs1_r_ex;
// assign alu_req_op2 = (dec_info_bus_alu[`DECINFO_ALU_OP2IMM]) ? dec_imm_r_ex : rf_rs2_r_ex;
exu_alu u_exu_alu(
    .i_alu_rs1          (alu_rs1            ),
    .i_alu_rs2          (alu_rs2            ),
    .i_alu_imm          (alu_imm            ),
    .i_alu_pc           (r_pc_exu           ),
    .i_dec_info_bus_alu (dec_info_bus_alu   ),
    .o_alu_wb_data     (alu_wb_data      )
    );


exu_lsu u_exu_lsu(
    .i_lsu_rs1          (lsu_rs1            ),
    .i_lsu_rs2          (lsu_rs2            ),
    .i_lsu_imm          (lsu_imm            ),
    .i_dec_info_bus_lsu (dec_info_bus_lsu   ),
    .o_mem_addr_exu    (o_mem_addr_exu    ),
    .o_mem_wr_data_exu (o_mem_wr_data_exu ),
    .o_mem_wr_en_exu    (o_mem_wr_en_exu    ),
    .o_mem_req_info_bus    (o_mem_req_info_bus    ),
    .o_exc_req_load_addr_misaligned_lsu  (exc_req_load_addr_misaligned_lsu ),
    .o_exc_req_store_addr_misaligned_lsu (exc_req_store_addr_misaligned_lsu),
    .o_exc_tval_addr_misaligned_lsu      (exc_tval_addr_misaligned_lsu     )
    // .i_mem_rd_data     (i_mem_rd_data     ),
    // .o_lsu_req_result   (lsu_req_result     )
    );

exu_bru u_exu_bru(
    .i_bru_rs1          (bru_rs1            ),
    .i_bru_rs2          (bru_rs2            ),
    .i_bru_imm          (bru_imm            ),
    .i_bru_pc           (bru_pc             ),
    .i_dec_info_bus_bru (dec_info_bus_bru   ),
    .o_bru_wb_data    (bru_wb_data      ),
    .o_redirect_pcnext_bru (redirect_pcnext_bru),
    .o_redirect_req_bru (redirect_req_bru   ),
    .o_exc_req_instr_addr_misaligned_bru  (exc_req_instr_addr_misaligned_bru),
    .o_exc_tval_instr_addr_misaligned_bru (exc_tval_instr_addr_misaligned_bru)
    );

exu_csr u_exu_csr(
    .clk                (clk    ),
    .rst_n              (rst_n  ),
    .i_csr_rs1          (csr_rs1            ),
    .i_dec_info_bus_csr (dec_info_bus_csr   ),
    .o_csr_wb_data     (csr_wb_data      ),
    .o_csr_op_req       (csr_op_req         ),
    .o_exc_req_ecall    (exc_req_ecall      ),
    .o_exc_req_ebreak   (exc_req_ebreak     ),
    .o_trap_ret_req_mret(trap_ret_req_mret  ),
    .o_csr_idx          (o_csr_idx          ),
    .o_csr_wr_req       (o_csr_wr_req       ),
    .o_csr_wr_data      (o_csr_wr_data      ),
    .i_csr_rd_data      (i_csr_rd_data      )
    );

endmodule
