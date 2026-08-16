`timescale 1ns / 1ps

module sva_bpu_exu (
    input wire        clk,
    input wire        rst_n,
    input wire        i_flush,
    input wire        i_id_ex_vld,
    input wire        o_id_ex_rdy,
    input wire [31:0] i_pred_next_pc_id,
    input wire [31:0] r_pred_next_pc_ex,
    input wire        ex_commit_fire,
    input wire        o_bp_update_vld,
    input wire        o_bp_invalidate,
    input wire        prediction_recovery_req,
    input wire        o_redirect_req,
    input wire        o_exc_req,
    input wire        o_trap_ret_req,
    input wire        bru_fence_i,
    input wire        bru_is_control,
    input wire [31:0] actual_next_pc
);

wire id_ex_fire = i_id_ex_vld && o_id_ex_rdy && !i_flush;

property p_pred_capture_on_fire;
    @(posedge clk) disable iff (!rst_n)
        id_ex_fire |=> (r_pred_next_pc_ex == $past(i_pred_next_pc_id));
endproperty
assert_pred_capture_on_fire: assert property (p_pred_capture_on_fire)
    else $error("[BPU SVA] EX prediction payload did not capture on valid/ready fire");

property p_pred_hold_without_fire;
    @(posedge clk) disable iff (!rst_n)
        !id_ex_fire |=> $stable(r_pred_next_pc_ex);
endproperty
assert_pred_hold_without_fire: assert property (p_pred_hold_without_fire)
    else $error("[BPU SVA] EX prediction payload changed without valid/ready fire");

property p_events_require_commit;
    @(posedge clk) disable iff (!rst_n)
        (o_bp_update_vld || o_bp_invalidate || prediction_recovery_req)
        |-> ex_commit_fire;
endproperty
assert_events_require_commit: assert property (p_events_require_commit)
    else $error("[BPU SVA] predictor event occurred without EX/MA fire");

property p_no_commit_no_redirect;
    @(posedge clk) disable iff (!rst_n)
        !ex_commit_fire |-> !(o_bp_update_vld || o_bp_invalidate || o_redirect_req);
endproperty
assert_no_commit_no_redirect: assert property (p_no_commit_no_redirect)
    else $error("[BPU SVA] update, invalidate, or redirect occurred while EX was not committed");

property p_correct_prediction_no_recovery;
    @(posedge clk) disable iff (!rst_n)
        (ex_commit_fire && !o_exc_req && !o_trap_ret_req && !bru_fence_i
         && (r_pred_next_pc_ex == actual_next_pc))
        |-> (!prediction_recovery_req && !o_redirect_req);
endproperty
assert_correct_prediction_no_recovery: assert property (p_correct_prediction_no_recovery)
    else $error("[BPU SVA] correct next-PC prediction incorrectly requested recovery");

cover_bp_update: cover property (
    @(posedge clk) disable iff (!rst_n) o_bp_update_vld
);
cover_bp_invalidate: cover property (
    @(posedge clk) disable iff (!rst_n) o_bp_invalidate
);
cover_prediction_recovery: cover property (
    @(posedge clk) disable iff (!rst_n) prediction_recovery_req
);
cover_correct_prediction: cover property (
    @(posedge clk) disable iff (!rst_n)
        ex_commit_fire && !o_exc_req && !o_trap_ret_req && !bru_fence_i
        && (r_pred_next_pc_ex == actual_next_pc)
);
cover_control_correct_prediction: cover property (
    @(posedge clk) disable iff (!rst_n)
        ex_commit_fire && bru_is_control
        && !o_exc_req && !o_trap_ret_req && !bru_fence_i
        && (r_pred_next_pc_ex == actual_next_pc)
);

endmodule

bind exu sva_bpu_exu u_sva_bpu_exu (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .i_flush                 (i_flush),
    .i_id_ex_vld             (i_id_ex_vld),
    .o_id_ex_rdy             (o_id_ex_rdy),
    .i_pred_next_pc_id       (i_pred_next_pc_id),
    .r_pred_next_pc_ex       (r_pred_next_pc_ex),
    .ex_commit_fire          (ex_commit_fire),
    .o_bp_update_vld         (o_bp_update_vld),
    .o_bp_invalidate         (o_bp_invalidate),
    .prediction_recovery_req (prediction_recovery_req),
    .o_redirect_req          (o_redirect_req),
    .o_exc_req               (o_exc_req),
    .o_trap_ret_req          (o_trap_ret_req),
    .bru_fence_i             (bru_fence_i),
    .bru_is_control          (bru_is_control),
    .actual_next_pc          (actual_next_pc)
);
