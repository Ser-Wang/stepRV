`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/01/22
// Design Name: StepRV_v0
// Module Name: ifu
// Description: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------
`include "config.v"

module ifu(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_stall,
    input  wire        i_if_id_rdy,
    output wire        o_if_id_vld,
    input  wire        i_redirect_req,
    input  wire [31:0] i_redirect_pcnext,
    input  wire        i_bp_update_vld,
    input  wire [31:0] i_bp_update_pc,
    input  wire        i_bp_update_is_cond,
    input  wire        i_bp_update_taken,
    input  wire [31:0] i_bp_update_target,
    input  wire        i_bp_invalidate,
    input  wire [31:0] i_instr_if,
    input  wire        i_ras_resolve_fire,
    input  wire        i_ras_resolve_pop,
    input  wire        i_ras_resolve_push,
    input  wire [31:0] i_ras_resolve_push_addr,
    output wire        o_fetch_req,
    output wire [31:0] o_fetch_pc, // Sent to ITCM
    output wire [31:0] o_instr_pc, // Sent to ID
    output wire [31:0] o_pred_next_pc_if
);

localparam RESET_PC = 32'h0000_0000;

reg [31:0] pc_r;
reg        if_valid_r;

wire [31:0] pc_add4;
wire [31:0] if_req_pc;
wire        if_accept;

assign pc_add4 = pc_r + 32'd4;

assign if_accept = o_if_id_vld && i_if_id_rdy && !i_stall && !i_redirect_req;

assign if_req_pc = i_redirect_req ? i_redirect_pcnext : // actrually if_req_pc is pc_next for pc_r
                   if_accept      ? o_pred_next_pc_if :
                                    pc_r;

assign o_fetch_req = 1'b1;
assign o_fetch_pc  = if_req_pc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc_r <= RESET_PC;
    end else begin
        pc_r <= if_req_pc;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_valid_r <= 1'b0;
    end else begin
        if_valid_r <= 1'b1;
    end
end

assign o_if_id_vld = if_valid_r && !i_redirect_req;
assign o_instr_pc = pc_r;

wire bp_btb_hit;
wire bp_pred_taken;
wire [31:0] bp_pred_next_pc;

wire if_is_jal = (i_instr_if[6:0] == 7'b1101111);
wire if_is_jalr = (i_instr_if[6:0] == 7'b1100111) & (i_instr_if[14:12] == 3'b000);
wire if_rd_is_link = (i_instr_if[11:7] == 5'd1) | (i_instr_if[11:7] == 5'd5);
wire if_rs1_is_link = (i_instr_if[19:15] == 5'd1) | (i_instr_if[19:15] == 5'd5);
wire ras_pred_push = (if_is_jal & if_rd_is_link) | (if_is_jalr & if_rd_is_link);
wire ras_pred_pop = if_is_jalr & if_rs1_is_link & (!if_rd_is_link | (i_instr_if[11:7] != i_instr_if[19:15]));
wire ras_pred_update_fire = if_accept & (ras_pred_pop | ras_pred_push);
wire ras_top_vld;
wire [31:0] ras_top_addr;
wire ras_pred_hit = (`BPU_ENABLE != 0) & (`BPU_RAS_ENABLE != 0)
                  & o_if_id_vld & ras_pred_pop & ras_top_vld;

assign o_pred_next_pc_if = ras_pred_hit ? ras_top_addr : bp_pred_next_pc;

branch_predictor u_branch_predictor (
    .clk              (clk),
    .rst_n            (rst_n),
    .i_query_pc       (pc_r),
    .o_pred_next_pc   (bp_pred_next_pc),
    .o_btb_hit        (bp_btb_hit),
    .o_pred_taken     (bp_pred_taken),
    .i_update_vld     (i_bp_update_vld),
    .i_update_pc      (i_bp_update_pc),
    .i_update_is_cond (i_bp_update_is_cond),
    .i_update_taken   (i_bp_update_taken),
    .i_update_target  (i_bp_update_target),
    .i_invalidate     (i_bp_invalidate)
);

ras_dual_full_stack u_ras_dual_full_stack (
    .clk                      (clk),
    .rst_n                    (rst_n),
    .o_top_vld                (ras_top_vld),
    .o_top_addr               (ras_top_addr),
    .i_pred_update_fire       (ras_pred_update_fire),
    .i_pred_pop               (ras_pred_pop),
    .i_pred_push              (ras_pred_push),
    .i_pred_push_addr         (pc_add4),
    .i_resolve_fire           (i_ras_resolve_fire),
    .i_resolve_pop            (i_ras_resolve_pop),
    .i_resolve_push           (i_ras_resolve_push),
    .i_resolve_push_addr      (i_ras_resolve_push_addr),
    .i_recover                (i_redirect_req)
);

endmodule
