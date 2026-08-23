`timescale 1ns / 1ps
`include "config.v"

// Read-only performance monitor for RAS on/off A/B runs.  The return event is
// derived from resolved EX decode rather than o_ras_resolve_fire so the same
// denominator is available when BPU_RAS_ENABLE=0.
module monitor_ras_stats (
    input wire        clk,
    input wire        rst_n,
    input wire        ex_commit_fire,
    input wire        o_exc_req,
    input wire        o_trap_ret_req,
    input wire        ras_resolve_pop_raw,
    input wire        prediction_recovery_req,
    input wire [31:0] r_pred_next_pc_ex,
    input wire [31:0] actual_next_pc
);

integer return_resolve_count;
integer return_recovery_count;
integer return_correct_prediction_count;

wire return_resolve_event = ex_commit_fire
                          && !o_exc_req
                          && !o_trap_ret_req
                          && ras_resolve_pop_raw;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        return_resolve_count <= 0;
        return_recovery_count <= 0;
        return_correct_prediction_count <= 0;
    end
    else if (return_resolve_event) begin
        return_resolve_count <= return_resolve_count + 1;
        if (prediction_recovery_req)
            return_recovery_count <= return_recovery_count + 1;
        if (r_pred_next_pc_ex == actual_next_pc)
            return_correct_prediction_count <= return_correct_prediction_count + 1;
    end
end

final begin
    $display("[RAS STATS] BPU_ENABLE=%0d BPU_RAS_ENABLE=%0d return_resolve=%0d return_recovery=%0d return_correct_prediction=%0d",
             `BPU_ENABLE, `BPU_RAS_ENABLE, return_resolve_count,
             return_recovery_count, return_correct_prediction_count);
end

endmodule

bind exu monitor_ras_stats u_monitor_ras_stats (
    .clk                             (clk),
    .rst_n                           (rst_n),
    .ex_commit_fire                  (ex_commit_fire),
    .o_exc_req                       (o_exc_req),
    .o_trap_ret_req                  (o_trap_ret_req),
    .ras_resolve_pop_raw             (ras_resolve_pop_raw),
    .prediction_recovery_req         (prediction_recovery_req),
    .r_pred_next_pc_ex               (r_pred_next_pc_ex),
    .actual_next_pc                  (actual_next_pc)
);
