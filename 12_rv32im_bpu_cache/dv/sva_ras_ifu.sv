`timescale 1ns / 1ps
`include "config.v"

module sva_ras_ifu (
    input wire        clk,
    input wire        rst_n,
    input wire        if_accept,
    input wire        ras_pred_update_fire,
    input wire        ras_pred_pop,
    input wire        ras_pred_push,
    input wire        ras_pred_hit,
    input wire        ras_top_vld,
    input wire [31:0] ras_top_addr,
    input wire [31:0] o_pred_next_pc_if
);

property p_pred_update_is_accepted_action;
    @(posedge clk) disable iff (!rst_n)
        ras_pred_update_fire |-> (if_accept && (ras_pred_pop || ras_pred_push));
endproperty
assert_pred_update_is_accepted_action:
assert property (p_pred_update_is_accepted_action)
    else $error("[BPU SVA][RAS] prediction update was not an accepted RAS action");

property p_accepted_action_updates;
    @(posedge clk) disable iff (!rst_n)
        (if_accept && (ras_pred_pop || ras_pred_push)) |-> ras_pred_update_fire;
endproperty
assert_accepted_action_updates:
assert property (p_accepted_action_updates)
    else $error("[BPU SVA][RAS] accepted RAS action did not produce update fire");

property p_ras_hit_is_valid_return;
    @(posedge clk) disable iff (!rst_n)
        ras_pred_hit |-> (ras_top_vld && ras_pred_pop);
endproperty
assert_ras_hit_is_valid_return:
assert property (p_ras_hit_is_valid_return)
    else $error("[BPU SVA][RAS] prediction hit lacked a valid return/top");

property p_ras_wins_prediction_mux;
    @(posedge clk) disable iff (!rst_n)
        ras_pred_hit |-> (o_pred_next_pc_if == ras_top_addr);
endproperty
assert_ras_wins_prediction_mux:
assert property (p_ras_wins_prediction_mux)
    else $error("[BPU SVA][RAS] target did not win prediction arbitration");

property p_disabled_never_hits;
    @(posedge clk) disable iff (!rst_n)
        ((`BPU_ENABLE == 0) || (`BPU_RAS_ENABLE == 0)) |-> !ras_pred_hit;
endproperty
assert_disabled_never_hits:
assert property (p_disabled_never_hits)
    else $error("[BPU SVA][RAS] disabled RAS produced a prediction hit");

cover_ras_push: cover property (
    @(posedge clk) disable iff (!rst_n)
        ras_pred_update_fire && ras_pred_push && !ras_pred_pop
);
cover_ras_pop: cover property (
    @(posedge clk) disable iff (!rst_n)
        ras_pred_update_fire && ras_pred_pop && !ras_pred_push
);
cover_ras_pop_push: cover property (
    @(posedge clk) disable iff (!rst_n)
        ras_pred_update_fire && ras_pred_pop && ras_pred_push
);
cover_ras_hit: cover property (
    @(posedge clk) disable iff (!rst_n) ras_pred_hit
);

endmodule

bind ifu sva_ras_ifu u_sva_ras_ifu (
    .clk                  (clk),
    .rst_n                (rst_n),
    .if_accept            (if_accept),
    .ras_pred_update_fire (ras_pred_update_fire),
    .ras_pred_pop         (ras_pred_pop),
    .ras_pred_push        (ras_pred_push),
    .ras_pred_hit         (ras_pred_hit),
    .ras_top_vld          (ras_top_vld),
    .ras_top_addr         (ras_top_addr),
    .o_pred_next_pc_if    (o_pred_next_pc_if)
);
