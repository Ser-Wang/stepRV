`timescale 1ns / 1ps
`include "config.v"

module tb_branch_predictor;

localparam integer BTB_ENTRIES = `BPU_BTB_ENTRIES;
localparam integer BHT_ENTRIES = `BPU_BHT_ENTRIES;

reg         clk;
reg         rst_n;
reg  [31:0] query_pc;
wire [31:0] pred_next_pc;
wire        btb_hit;
wire        pred_taken;
reg         update_vld;
reg  [31:0] update_pc;
reg         update_is_cond;
reg         update_taken;
reg  [31:0] update_target;
reg         invalidate;
integer     failures;
integer     idx;

branch_predictor dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .i_query_pc       (query_pc),
    .o_pred_next_pc   (pred_next_pc),
    .o_btb_hit        (btb_hit),
    .o_pred_taken     (pred_taken),
    .i_update_vld     (update_vld),
    .i_update_pc      (update_pc),
    .i_update_is_cond (update_is_cond),
    .i_update_taken   (update_taken),
    .i_update_target  (update_target),
    .i_invalidate     (invalidate)
);

always #5 clk = ~clk;

task automatic check;
    input condition;
    input [8*96-1:0] message;
    begin
        if (!condition) begin
            failures = failures + 1;
            $display("FAIL: %0s", message);
        end
    end
endtask

task automatic drive_update;
    input [31:0] pc;
    input        is_cond;
    input        taken;
    input [31:0] target;
    begin
        @(negedge clk);
        update_vld = 1'b1;
        update_pc = pc;
        update_is_cond = is_cond;
        update_taken = taken;
        update_target = target;
        @(posedge clk);
        #1;
        update_vld = 1'b0;
    end
endtask

task automatic check_query;
    input [31:0] pc;
    input        expected_hit;
    input        expected_taken;
    input [31:0] expected_next_pc;
    input [8*96-1:0] message;
    begin
        query_pc = pc;
        #1;
        check((btb_hit === expected_hit)
              && (pred_taken === expected_taken)
              && (pred_next_pc === expected_next_pc), message);
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    query_pc = 32'h0000_0100;
    update_vld = 1'b0;
    update_pc = 32'b0;
    update_is_cond = 1'b0;
    update_taken = 1'b0;
    update_target = 32'b0;
    invalidate = 1'b0;
    failures = 0;

    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;
    #1;

    check(BTB_ENTRIES == 16, "v11 default BTB depth must be 16");
    check(BHT_ENTRIES == 16, "v11 default BHT depth must be 16");
    for (idx = 0; idx < BTB_ENTRIES; idx = idx + 1)
        check(dut.btb_valid[idx] === 1'b0, "reset must invalidate every BTB entry");
    for (idx = 0; idx < BHT_ENTRIES; idx = idx + 1)
        check(dut.bht_counter[idx] === `BPU_BHT_INIT, "reset must initialize every BHT entry");

    if (`BPU_ENABLE == 0) begin
        check_query(32'h0000_0100, 1'b0, 1'b0, 32'h0000_0104,
                    "disabled predictor must be sequential before update");
        drive_update(32'h0000_0100, 1'b0, 1'b1, 32'h0000_0200);
        check_query(32'h0000_0100, 1'b0, 1'b0, 32'h0000_0104,
                    "disabled predictor must ignore update and remain sequential");
        check(dut.btb_valid[0] === 1'b0, "disabled predictor must not train BTB");
        check(dut.bht_counter[0] === `BPU_BHT_INIT, "disabled predictor must not train BHT");
    end
    else begin
        check_query(32'h0000_0100, 1'b0, 1'b0, 32'h0000_0104,
                    "cold BTB must predict sequential PC");

        // A not-taken conditional branch still installs its target in the BTB.
        drive_update(32'h0000_0100, 1'b1, 1'b0, 32'h0000_0080);
        check_query(32'h0000_0100, 1'b1, 1'b0, 32'h0000_0104,
                    "not-taken conditional update must install BTB but predict sequentially");
        check(dut.bht_counter[0] === 2'b00, "01 not-taken transition must produce 00");

        drive_update(32'h0000_0100, 1'b1, 1'b0, 32'h0000_0080);
        check(dut.bht_counter[0] === 2'b00, "not-taken counter must saturate at 00");
        drive_update(32'h0000_0100, 1'b1, 1'b1, 32'h0000_0080);
        check(dut.bht_counter[0] === 2'b01, "00 taken transition must produce 01");
        drive_update(32'h0000_0100, 1'b1, 1'b1, 32'h0000_0080);
        check(dut.bht_counter[0] === 2'b10, "01 taken transition must produce 10");
        check_query(32'h0000_0100, 1'b1, 1'b1, 32'h0000_0080,
                    "conditional counter MSB one must select trained target");
        drive_update(32'h0000_0100, 1'b1, 1'b1, 32'h0000_0080);
        drive_update(32'h0000_0100, 1'b1, 1'b1, 32'h0000_0080);
        check(dut.bht_counter[0] === 2'b11, "taken counter must saturate at 11");

        // Same index, different tag replaces the old direct-mapped entry.
        drive_update(32'h0000_0140, 1'b0, 1'b1, 32'h0000_0200);
        check_query(32'h0000_0100, 1'b0, 1'b0, 32'h0000_0104,
                    "same-index different-tag replacement must make old PC miss");
        check_query(32'h0000_0140, 1'b1, 1'b1, 32'h0000_0200,
                    "unconditional BTB entry must always predict taken");
        check(dut.bht_counter[0] === 2'b11, "unconditional update must not alter BHT");

        // Query/update collision observes the old entry until the active edge.
        query_pc = 32'h0000_0140;
        @(negedge clk);
        update_vld = 1'b1;
        update_pc = 32'h0000_0140;
        update_is_cond = 1'b0;
        update_taken = 1'b1;
        update_target = 32'h0000_0240;
        #1;
        check(pred_next_pc === 32'h0000_0200,
              "same-cycle query/update must observe old target before write edge");
        @(posedge clk);
        #1;
        update_vld = 1'b0;
        check(pred_next_pc === 32'h0000_0240,
              "updated target must become visible after write edge");

        // Exercise a non-zero, non-alias index independently from entry zero.
        drive_update(32'h0000_0114, 1'b0, 1'b1, 32'h0000_0300);
        check_query(32'h0000_0114, 1'b1, 1'b1, 32'h0000_0300,
                    "non-zero BTB index must train and query independently");
        check_query(32'h0000_0140, 1'b1, 1'b1, 32'h0000_0240,
                    "training another index must preserve existing entry");

        // invalidate has priority over a simultaneous update and resets all state.
        query_pc = 32'h0000_0140;
        @(negedge clk);
        invalidate = 1'b1;
        update_vld = 1'b1;
        update_pc = 32'h0000_0140;
        update_is_cond = 1'b0;
        update_taken = 1'b1;
        update_target = 32'h0000_0400;
        @(posedge clk);
        #1;
        invalidate = 1'b0;
        update_vld = 1'b0;
        check_query(32'h0000_0140, 1'b0, 1'b0, 32'h0000_0144,
                    "invalidate must clear BTB and win over simultaneous update");
        for (idx = 0; idx < BTB_ENTRIES; idx = idx + 1)
            check(dut.btb_valid[idx] === 1'b0, "invalidate must clear every BTB valid bit");
        for (idx = 0; idx < BHT_ENTRIES; idx = idx + 1)
            check(dut.bht_counter[idx] === `BPU_BHT_INIT,
                  "invalidate must restore every BHT entry");
    end

    if (failures == 0)
        $display("PASS: branch_predictor directed test (BPU_ENABLE=%0d)", `BPU_ENABLE);
    else
        $display("FAIL: branch_predictor directed test, failures=%0d (BPU_ENABLE=%0d)",
                 failures, `BPU_ENABLE);
    $finish;
end

endmodule
