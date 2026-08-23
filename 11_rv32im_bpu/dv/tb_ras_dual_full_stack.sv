`timescale 1ns / 1ps

module tb_ras_dual_full_stack;

reg         clk;
reg         rst_n;
reg         pred_update_fire;
reg         pred_pop;
reg         pred_push;
reg  [31:0] pred_push_addr;
reg         resolve_fire;
reg         resolve_pop;
reg         resolve_push;
reg  [31:0] resolve_push_addr;
reg         recover;
wire        top_vld;
wire [31:0] top_addr;
integer     failures;

ras_dual_full_stack #(
    .ENTRIES (4)
) u_dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .o_top_vld           (top_vld),
    .o_top_addr          (top_addr),
    .i_pred_update_fire  (pred_update_fire),
    .i_pred_pop          (pred_pop),
    .i_pred_push         (pred_push),
    .i_pred_push_addr    (pred_push_addr),
    .i_resolve_fire      (resolve_fire),
    .i_resolve_pop       (resolve_pop),
    .i_resolve_push      (resolve_push),
    .i_resolve_push_addr (resolve_push_addr),
    .i_recover           (recover)
);

always #5 clk = ~clk;

task automatic check_top;
    input        expected_vld;
    input [31:0] expected_addr;
    input [8*96-1:0] message;
    begin
        if ((top_vld !== expected_vld)
                || (expected_vld && (top_addr !== expected_addr))) begin
            failures = failures + 1;
            $display("FAIL: %0s (vld=%b addr=%08x, expected vld=%b addr=%08x)",
                     message, top_vld, top_addr, expected_vld, expected_addr);
        end
    end
endtask

task automatic drive_cycle;
    input        do_pred;
    input        do_pred_pop;
    input        do_pred_push;
    input [31:0] do_pred_addr;
    input        do_resolve;
    input        do_resolve_pop;
    input        do_resolve_push;
    input [31:0] do_resolve_addr;
    input        do_recover;
    begin
        @(negedge clk);
        pred_update_fire = do_pred;
        pred_pop = do_pred_pop;
        pred_push = do_pred_push;
        pred_push_addr = do_pred_addr;
        resolve_fire = do_resolve;
        resolve_pop = do_resolve_pop;
        resolve_push = do_resolve_push;
        resolve_push_addr = do_resolve_addr;
        recover = do_recover;
        @(posedge clk);
        #1;
        pred_update_fire = 1'b0;
        pred_pop = 1'b0;
        pred_push = 1'b0;
        resolve_fire = 1'b0;
        resolve_pop = 1'b0;
        resolve_push = 1'b0;
        recover = 1'b0;
    end
endtask

task automatic reset_dut;
    begin
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        #1 rst_n = 1'b1;
        @(posedge clk);
        #1;
        check_top(1'b0, 32'b0, "reset must empty both stacks");
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    pred_update_fire = 1'b0;
    pred_pop = 1'b0;
    pred_push = 1'b0;
    pred_push_addr = 32'b0;
    resolve_fire = 1'b0;
    resolve_pop = 1'b0;
    resolve_push = 1'b0;
    resolve_push_addr = 32'b0;
    recover = 1'b0;
    failures = 0;

    reset_dut();

    // Empty pop is a no-op. Action bits without their fire are also a no-op.
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b0, 32'b0, "empty prediction pop must not underflow");
    drive_cycle(1'b0, 1'b0, 1'b1, 32'hdead_0004,
                1'b0, 1'b0, 1'b1, 32'hbeef_0004, 1'b0);
    check_top(1'b0, 32'b0, "action bits without fire must not update state");

    // Prediction push/pop ordering.
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h0000_0104,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h0000_0104, "first prediction push must become top");
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h0000_0204,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h0000_0204, "second prediction push must become top");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h0000_0104, "prediction pop must reveal prior entry");

    // Prediction and resolved stacks advance independently.
    drive_cycle(1'b0, 1'b0, 1'b0, 32'b0,
                1'b1, 1'b0, 1'b1, 32'h0000_a004, 1'b0);
    check_top(1'b1, 32'h0000_0104,
              "resolved update without recovery must not replace prediction top");
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h0000_bad4,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b1);
    check_top(1'b1, 32'h0000_a004,
              "recovery must beat simultaneous younger prediction update");

    // Full-state recovery: build three resolved entries, contaminate prediction,
    // recover, then pop through every restored entry and restored count.
    drive_cycle(1'b0, 1'b0, 1'b0, 32'b0,
                1'b1, 1'b0, 1'b1, 32'h0000_b004, 1'b0);
    drive_cycle(1'b0, 1'b0, 1'b0, 32'b0,
                1'b1, 1'b0, 1'b1, 32'h0000_c004, 1'b0);
    drive_cycle(1'b1, 1'b0, 1'b1, 32'hffff_1004,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    drive_cycle(1'b1, 1'b0, 1'b1, 32'hffff_2004,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    drive_cycle(1'b0, 1'b0, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b1);
    check_top(1'b1, 32'h0000_c004, "recovery must restore resolved top");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h0000_b004, "recovery must restore resolved entry 1");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h0000_a004, "recovery must restore resolved entry 2");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b0, 32'b0, "recovery must restore resolved count exactly");

    // Overflow retains the four youngest entries and discards the deepest.
    reset_dut();
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h104,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h204,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h304,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h404,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h504,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h504, "overflow push must install newest top");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h404, "overflow pop order 1");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h304, "overflow pop order 2");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h204, "overflow must retain fourth-youngest entry");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b0, 32'b0, "overflow must discard oldest/deepest entry");

    // pop+push replaces top when non-empty and acts as push when empty.
    drive_cycle(1'b1, 1'b1, 1'b1, 32'h604,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h604, "empty pop+push must act as push");
    drive_cycle(1'b1, 1'b0, 1'b1, 32'h704,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    drive_cycle(1'b1, 1'b1, 1'b1, 32'h804,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h804, "non-empty pop+push must replace top");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b1, 32'h604, "pop+push must preserve deeper entries");

    // Same-cycle resolve+recover must restore post-resolve state.
    reset_dut();
    drive_cycle(1'b0, 1'b0, 1'b0, 32'b0,
                1'b1, 1'b0, 1'b1, 32'h1004, 1'b1);
    check_top(1'b1, 32'h1004, "resolve push + recover must include current push");
    drive_cycle(1'b0, 1'b0, 1'b0, 32'b0,
                1'b1, 1'b0, 1'b1, 32'h2004, 1'b1);
    check_top(1'b1, 32'h2004, "second resolve push + recover");
    drive_cycle(1'b0, 1'b0, 1'b0, 32'b0,
                1'b1, 1'b1, 1'b0, 32'b0, 1'b1);
    check_top(1'b1, 32'h1004, "resolve pop + recover must include current pop");
    drive_cycle(1'b0, 1'b0, 1'b0, 32'b0,
                1'b1, 1'b1, 1'b1, 32'h3004, 1'b1);
    check_top(1'b1, 32'h3004,
              "resolve pop+push + recover must include current replacement");
    drive_cycle(1'b1, 1'b1, 1'b0, 32'b0,
                1'b0, 1'b0, 1'b0, 32'b0, 1'b0);
    check_top(1'b0, 32'b0, "resolve pop+push must preserve resolved depth of one");

    if (failures == 0)
        $display("PASS: ras_dual_full_stack directed test");
    else
        $display("FAIL: ras_dual_full_stack directed test, failures=%0d", failures);
    $finish;
end

endmodule
