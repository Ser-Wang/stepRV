`timescale 1ns / 1ps

module sva_bpu_idu (
    input wire        clk,
    input wire        rst_n,
    input wire        i_flush,
    input wire        i_if_id_vld,
    input wire        o_if_id_rdy,
    input wire [31:0] i_pred_next_pc_if,
    input wire [31:0] o_pred_next_pc_id
);

wire if_id_fire = i_if_id_vld && o_if_id_rdy && !i_flush;

property p_pred_capture_on_fire;
    @(posedge clk) disable iff (!rst_n)
        if_id_fire |=> (o_pred_next_pc_id == $past(i_pred_next_pc_if));
endproperty
assert_pred_capture_on_fire: assert property (p_pred_capture_on_fire)
    else $error("[BPU SVA] ID prediction payload did not capture on valid/ready fire");

property p_pred_hold_without_fire;
    @(posedge clk) disable iff (!rst_n)
        !if_id_fire |=> $stable(o_pred_next_pc_id);
endproperty
assert_pred_hold_without_fire: assert property (p_pred_hold_without_fire)
    else $error("[BPU SVA] ID prediction payload changed without valid/ready fire");

cover_pred_capture: cover property (
    @(posedge clk) disable iff (!rst_n) if_id_fire
);
cover_pred_backpressure: cover property (
    @(posedge clk) disable iff (!rst_n) i_if_id_vld && !o_if_id_rdy
);
cover_pred_invalid_ready: cover property (
    @(posedge clk) disable iff (!rst_n) !i_if_id_vld && o_if_id_rdy
);

endmodule

bind idu sva_bpu_idu u_sva_bpu_idu (
    .clk               (clk),
    .rst_n             (rst_n),
    .i_flush           (i_flush),
    .i_if_id_vld       (i_if_id_vld),
    .o_if_id_rdy       (o_if_id_rdy),
    .i_pred_next_pc_if (i_pred_next_pc_if),
    .o_pred_next_pc_id (o_pred_next_pc_id)
);
