`timescale 1ns / 1ps
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
    input  wire        i_ras_resolve_fire,
    input  wire        i_ras_resolve_pop,
    input  wire        i_ras_resolve_push,
    input  wire [31:0] i_ras_resolve_push_addr,
    output wire        o_if_req_vld,
    input  wire        i_if_req_rdy,
    output wire [31:0] o_if_req_addr,
    input  wire        i_if_rsp_vld,
    output wire        o_if_rsp_rdy,
    input  wire [31:0] i_if_rsp_data,
    output wire [31:0] o_instr_pc,
    output wire [31:0] o_instr_if,
    output wire [31:0] o_pred_next_pc_if
);

localparam [31:0] RESET_PC = 32'h0000_0000;

reg [31:0] issue_pc_r;
reg        req_vld_r;
reg        req_stale_r;

reg        outstanding_r;
reg        outstanding_stale_r;
reg [31:0] txn_pc_r;
reg [31:0] txn_bp_pred_next_r;

reg        redirect_pending_r;
reg [31:0] redirect_pc_r;

reg        rsp_buf_vld_r;
reg [31:0] rsp_buf_instr_r;
reg [31:0] rsp_buf_pc_r;
reg [31:0] rsp_buf_pred_next_r;

wire if_req_fire = o_if_req_vld & i_if_req_rdy;
wire if_rsp_fire = i_if_rsp_vld & o_if_rsp_rdy;
wire if_id_fire = o_if_id_vld & i_if_id_rdy & !i_stall;
wire rsp_buf_can_push;
wire rsp_ras_conflict;
wire rsp_successor_vld;
wire [31:0] rsp_pred_next_pc;
// Kept as named internal protocol points for the legacy BPU/RAS bind checkers.
wire if_accept = if_id_fire;

// A normal response supplies the successor request directly.  If the backend
// cannot accept it on this cycle, the sequential logic below parks it in the
// existing request holding register.  This is still one unanswered request:
// response A and request B may replace each other on the same edge.
assign o_if_req_vld = req_vld_r | rsp_successor_vld;
assign o_if_req_addr = req_vld_r ? issue_pc_r : rsp_pred_next_pc;

assign o_if_id_vld = rsp_buf_vld_r & !i_redirect_req;
assign o_instr_pc = rsp_buf_pc_r;
assign o_instr_if = rsp_buf_instr_r;
assign o_pred_next_pc_if = rsp_buf_pred_next_r;

wire bp_btb_hit;
wire bp_pred_taken;
wire [31:0] bp_pred_next_pc;

branch_predictor u_branch_predictor (
    .clk              (clk),
    .rst_n            (rst_n),
    .i_query_pc       (o_if_req_addr),
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

wire rsp_is_jal = (i_if_rsp_data[6:0] == 7'b1101111);
wire rsp_is_jalr = (i_if_rsp_data[6:0] == 7'b1100111)
                 & (i_if_rsp_data[14:12] == 3'b000);
wire rsp_rd_is_link = (i_if_rsp_data[11:7] == 5'd1)
                    | (i_if_rsp_data[11:7] == 5'd5);
wire rsp_rs1_is_link = (i_if_rsp_data[19:15] == 5'd1)
                     | (i_if_rsp_data[19:15] == 5'd5);
wire rsp_ras_pred_pop = rsp_is_jalr & rsp_rs1_is_link
                      & (!rsp_rd_is_link
                         | (i_if_rsp_data[11:7] != i_if_rsp_data[19:15]));

wire buf_is_jal = (rsp_buf_instr_r[6:0] == 7'b1101111);
wire buf_is_jalr = (rsp_buf_instr_r[6:0] == 7'b1100111)
                 & (rsp_buf_instr_r[14:12] == 3'b000);
wire buf_rd_is_link = (rsp_buf_instr_r[11:7] == 5'd1)
                    | (rsp_buf_instr_r[11:7] == 5'd5);
wire buf_rs1_is_link = (rsp_buf_instr_r[19:15] == 5'd1)
                     | (rsp_buf_instr_r[19:15] == 5'd5);
wire ras_pred_push = (buf_is_jal & buf_rd_is_link)
                   | (buf_is_jalr & buf_rd_is_link);
wire ras_pred_pop = buf_is_jalr & buf_rs1_is_link
                  & (!buf_rd_is_link
                     | (rsp_buf_instr_r[11:7] != rsp_buf_instr_r[19:15]));
wire ras_pred_update_fire = if_id_fire & (ras_pred_pop | ras_pred_push);
wire ras_top_vld;
wire [31:0] ras_top_addr;
wire rsp_ras_pred_hit = (`BPU_ENABLE != 0) & (`BPU_RAS_ENABLE != 0)
                      & rsp_ras_pred_pop & ras_top_vld;
wire ras_pred_hit = (`BPU_ENABLE != 0) & (`BPU_RAS_ENABLE != 0)
                  & rsp_buf_vld_r & ras_pred_pop & ras_top_vld;

assign rsp_buf_can_push = !rsp_buf_vld_r | if_id_fire;
// Without a RAS preview path, hold a younger return response for one cycle
// when the older IF/ID transfer changes the stack on this same edge.  Ordinary
// sequential/BTB traffic remains fully pipelined.
assign rsp_ras_conflict = ras_pred_update_fire & rsp_ras_pred_pop;
assign o_if_rsp_rdy = outstanding_r
                    & (i_redirect_req | outstanding_stale_r
                       | (rsp_buf_can_push & !rsp_ras_conflict));
assign rsp_pred_next_pc = rsp_ras_pred_hit
                        ? ras_top_addr : txn_bp_pred_next_r;
assign rsp_successor_vld = if_rsp_fire
                         & !outstanding_stale_r
                         & !i_redirect_req;

ras_dual_full_stack u_ras_dual_full_stack (
    .clk                      (clk),
    .rst_n                    (rst_n),
    .o_top_vld                (ras_top_vld),
    .o_top_addr               (ras_top_addr),
    .i_pred_update_fire       (ras_pred_update_fire),
    .i_pred_pop               (ras_pred_pop),
    .i_pred_push              (ras_pred_push),
    .i_pred_push_addr         (rsp_buf_pc_r + 32'd4),
    .i_resolve_fire           (i_ras_resolve_fire),
    .i_resolve_pop            (i_ras_resolve_pop),
    .i_resolve_push           (i_ras_resolve_push),
    .i_resolve_push_addr      (i_ras_resolve_push_addr),
    .i_recover                (i_redirect_req)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        issue_pc_r <= RESET_PC;
        req_vld_r <= 1'b0;
        req_stale_r <= 1'b0;
        outstanding_r <= 1'b0;
        outstanding_stale_r <= 1'b0;
        txn_pc_r <= RESET_PC;
        txn_bp_pred_next_r <= RESET_PC + 32'd4;
        redirect_pending_r <= 1'b0;
        redirect_pc_r <= RESET_PC;
        rsp_buf_vld_r <= 1'b0;
        rsp_buf_instr_r <= `INSTR_NOP;
        rsp_buf_pc_r <= RESET_PC;
        rsp_buf_pred_next_r <= RESET_PC + 32'd4;
    end else if (i_redirect_req) begin
        rsp_buf_vld_r <= 1'b0;
        redirect_pc_r <= i_redirect_pcnext;

        if (req_vld_r) begin
            if (if_req_fire) begin
                req_vld_r <= 1'b0;
                req_stale_r <= 1'b0;
                outstanding_r <= 1'b1;
                outstanding_stale_r <= 1'b1;
                txn_pc_r <= issue_pc_r;
                txn_bp_pred_next_r <= bp_pred_next_pc;
            end else begin
                req_stale_r <= 1'b1;
            end
            redirect_pending_r <= 1'b1;
        end else if (outstanding_r) begin
            if (if_rsp_fire) begin
                outstanding_r <= 1'b0;
                outstanding_stale_r <= 1'b0;
                issue_pc_r <= i_redirect_pcnext;
                req_vld_r <= 1'b1;
                req_stale_r <= 1'b0;
                redirect_pending_r <= 1'b0;
            end else begin
                outstanding_stale_r <= 1'b1;
                redirect_pending_r <= 1'b1;
            end
        end else begin
            issue_pc_r <= i_redirect_pcnext;
            req_vld_r <= 1'b1;
            req_stale_r <= 1'b0;
            redirect_pending_r <= 1'b0;
        end
    end else begin
        // The returned-payload slot is elastic: an old payload may leave on
        // the same edge that the next response replaces it.
        if (if_id_fire)
            rsp_buf_vld_r <= 1'b0;

        if (if_rsp_fire) begin
            outstanding_r <= 1'b0;
            outstanding_stale_r <= 1'b0;
            if (outstanding_stale_r) begin
                if (redirect_pending_r) begin
                    issue_pc_r <= redirect_pc_r;
                    req_vld_r <= 1'b1;
                    req_stale_r <= 1'b0;
                    redirect_pending_r <= 1'b0;
                end
            end else begin
                rsp_buf_vld_r <= 1'b1;
                rsp_buf_instr_r <= i_if_rsp_data;
                rsp_buf_pc_r <= txn_pc_r;
                rsp_buf_pred_next_r <= rsp_pred_next_pc;
                // If the direct successor request was backpressured, retain
                // it in the existing request slot for a later handshake.
                if (!if_req_fire) begin
                    issue_pc_r <= rsp_pred_next_pc;
                    req_vld_r <= 1'b1;
                    req_stale_r <= 1'b0;
                end
            end
        end

        // This block is intentionally after response handling so a same-edge
        // response/request replacement leaves the new request outstanding.
        if (if_req_fire) begin
            req_vld_r <= 1'b0;
            req_stale_r <= 1'b0;
            outstanding_r <= 1'b1;
            outstanding_stale_r <= req_vld_r ? req_stale_r : 1'b0;
            txn_pc_r <= o_if_req_addr;
            txn_bp_pred_next_r <= bp_pred_next_pc;
        end

        if (!req_vld_r && !outstanding_r && !rsp_buf_vld_r
            && !if_req_fire && !if_rsp_fire && !if_id_fire) begin
            if (redirect_pending_r) begin
                issue_pc_r <= redirect_pc_r;
                redirect_pending_r <= 1'b0;
            end
            req_vld_r <= 1'b1;
            req_stale_r <= 1'b0;
        end
    end
end

endmodule
