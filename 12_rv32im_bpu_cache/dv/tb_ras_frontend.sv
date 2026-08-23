`timescale 1ns / 1ps

module tb_ras_frontend;

reg         clk;
reg         rst_n;
reg         stall;
reg         if_id_rdy;
wire        if_id_vld;
reg         redirect_req;
reg  [31:0] redirect_pc;
reg         bp_update_vld;
reg  [31:0] bp_update_pc;
reg         bp_update_is_cond;
reg         bp_update_taken;
reg  [31:0] bp_update_target;
reg         bp_invalidate;
reg  [31:0] instr_if;
reg         ras_resolve_fire;
reg         ras_resolve_pop;
reg         ras_resolve_push;
reg  [31:0] ras_resolve_push_addr;
wire        fetch_req;
wire [31:0] fetch_pc;
wire [31:0] instr_pc;
wire [31:0] pred_next_pc;
integer     failures;

localparam [31:0] JAL_X0       = 32'h0000_006f;
localparam [31:0] JAL_X1       = 32'h0000_00ef;
localparam [31:0] JAL_X5       = 32'h0000_02ef;
localparam [31:0] RET_X1       = 32'h0000_8067;
localparam [31:0] RET_X5       = 32'h0002_8067;
localparam [31:0] JALR_X1_X2   = 32'h0001_00e7;
localparam [31:0] JALR_X1_X1   = 32'h0000_80e7;
localparam [31:0] JALR_X5_X1   = 32'h0000_82e7;
localparam [31:0] JALR_BAD_F3  = 32'h0000_9067;

ifu u_ifu (
    .clk                      (clk),
    .rst_n                    (rst_n),
    .i_stall                  (stall),
    .i_if_id_rdy              (if_id_rdy),
    .o_if_id_vld              (if_id_vld),
    .i_redirect_req           (redirect_req),
    .i_redirect_pcnext        (redirect_pc),
    .i_bp_update_vld          (bp_update_vld),
    .i_bp_update_pc           (bp_update_pc),
    .i_bp_update_is_cond      (bp_update_is_cond),
    .i_bp_update_taken        (bp_update_taken),
    .i_bp_update_target       (bp_update_target),
    .i_bp_invalidate          (bp_invalidate),
    .i_instr_if               (instr_if),
    .i_ras_resolve_fire       (ras_resolve_fire),
    .i_ras_resolve_pop        (ras_resolve_pop),
    .i_ras_resolve_push       (ras_resolve_push),
    .i_ras_resolve_push_addr  (ras_resolve_push_addr),
    .o_fetch_req              (fetch_req),
    .o_fetch_pc               (fetch_pc),
    .o_instr_pc               (instr_pc),
    .o_pred_next_pc_if        (pred_next_pc)
);

always #5 clk = ~clk;

task automatic check;
    input condition;
    input [8*112-1:0] message;
    begin
        if (!condition) begin
            failures = failures + 1;
            $display("FAIL: %0s", message);
        end
    end
endtask

task automatic redirect_to;
    input [31:0] target;
    begin
        @(negedge clk);
        redirect_req = 1'b1;
        redirect_pc = target;
        @(posedge clk);
        #1;
        redirect_req = 1'b0;
        stall = 1'b1;
    end
endtask

task automatic accept_instr;
    input [31:0] instr;
    begin
        @(negedge clk);
        instr_if = instr;
        stall = 1'b0;
        if_id_rdy = 1'b1;
        @(posedge clk);
        #1;
        stall = 1'b1;
    end
endtask

task automatic check_empty_with_ret;
    input [31:0] ret_instr;
    input [8*112-1:0] message;
    begin
        instr_if = ret_instr;
        #1;
        check(!u_ifu.ras_top_vld, message);
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    stall = 1'b1;
    if_id_rdy = 1'b1;
    redirect_req = 1'b0;
    redirect_pc = 32'b0;
    bp_update_vld = 1'b0;
    bp_update_pc = 32'b0;
    bp_update_is_cond = 1'b0;
    bp_update_taken = 1'b0;
    bp_update_target = 32'b0;
    bp_invalidate = 1'b0;
    instr_if = 32'h0000_0013;
    ras_resolve_fire = 1'b0;
    ras_resolve_pop = 1'b0;
    ras_resolve_push = 1'b0;
    ras_resolve_push_addr = 32'b0;
    failures = 0;

    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;
    @(posedge clk);
    #1;
    check(if_id_vld && instr_pc == 32'h0, "IFU must present reset PC payload");

    // Held call must not update; one accept must push exactly once.
    instr_if = JAL_X1;
    repeat (3) begin
        @(posedge clk);
        #1;
        check(!u_ifu.ras_top_vld, "stalled JAL x1 must not update prediction stack");
    end
    accept_instr(JAL_X1);
    check(u_ifu.ras_top_vld && u_ifu.ras_top_addr == 32'h4,
          "accepted JAL x1 must push aligned PC+4");

    // Train a conflicting BTB target at the held return PC. RAS must win.
    instr_if = RET_X1;
    @(negedge clk);
    bp_update_vld = 1'b1;
    bp_update_pc = instr_pc;
    bp_update_is_cond = 1'b0;
    bp_update_taken = 1'b1;
    bp_update_target = 32'h88;
    @(posedge clk);
    #1 bp_update_vld = 1'b0;
    check(pred_next_pc == 32'h4,
          "non-empty return must select RAS target over conflicting BTB target");
    accept_instr(RET_X1);
    check_empty_with_ret(RET_X1, "single accepted return must pop exactly once");
    check(pred_next_pc == 32'h88,
          "empty return must fall back to the existing BTB prediction");

    // x5 is a link register; JAL x0 and illegal-funct3 JALR are not hints.
    redirect_to(32'h100);
    accept_instr(JAL_X5);
    check(u_ifu.ras_top_addr == 32'h104, "JAL x5 must push PC+4");
    accept_instr(RET_X5);
    check(!u_ifu.ras_top_vld, "return through x5 must pop");
    accept_instr(JAL_X0);
    check(!u_ifu.ras_top_vld, "JAL x0 must not push");
    accept_instr(JALR_BAD_F3);
    check(!u_ifu.ras_top_vld, "JALR funct3!=000 must not produce a RAS action");

    // JALR hint matrix: rd link/rs1 non-link pushes; same link only pushes;
    // different x1/x5 performs pop+push and preserves the deeper entry.
    redirect_to(32'h200);
    accept_instr(JALR_X1_X2);
    check(u_ifu.ras_top_addr == 32'h204,
          "JALR with link rd and non-link rs1 must push");
    accept_instr(JALR_X1_X1);
    check(u_ifu.ras_top_addr == 32'h208,
          "same-link JALR must push without pop");
    accept_instr(JALR_X5_X1);
    check(u_ifu.ras_top_addr == 32'h20c,
          "different-link JALR must install new top via pop+push");
    accept_instr(RET_X5);
    check(u_ifu.ras_top_vld && u_ifu.ras_top_addr == 32'h204,
          "different-link pop+push must preserve deeper prediction entry");

    // Recovery consumes post-resolve state, including a same-cycle resolve push.
    @(negedge clk);
    ras_resolve_fire = 1'b1;
    ras_resolve_pop = 1'b0;
    ras_resolve_push = 1'b1;
    ras_resolve_push_addr = 32'h4444_0004;
    redirect_req = 1'b1;
    redirect_pc = 32'h300;
    @(posedge clk);
    #1;
    ras_resolve_fire = 1'b0;
    ras_resolve_push = 1'b0;
    redirect_req = 1'b0;
    instr_if = RET_X1;
    #1;
    check(u_ifu.ras_top_vld && u_ifu.ras_top_addr == 32'h4444_0004,
          "same-cycle resolve+redirect must recover post-resolve top");
    check(pred_next_pc == 32'h4444_0004,
          "recovered resolved top must immediately predict a return");

    if (failures == 0)
        $display("PASS: RAS IFU hint, handshake, recovery and arbitration directed test");
    else
        $display("FAIL: RAS frontend directed test, failures=%0d", failures);
    $finish;
end

endmodule
