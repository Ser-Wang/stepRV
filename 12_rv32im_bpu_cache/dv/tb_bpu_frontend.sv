`timescale 1ns / 1ps
`include "config.v"

module tb_bpu_frontend;

reg         clk;
reg         rst_n;
integer     failures;

reg         if_stall;
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
wire        if_req_vld;
wire [31:0] if_req_addr;
reg         if_req_rdy;
reg         if_rsp_vld;
reg  [31:0] if_rsp_data;
reg         ras_resolve_fire;
reg         ras_resolve_pop;
reg         ras_resolve_push;
reg  [31:0] ras_resolve_push_addr;
wire        fetch_req = if_req_vld;
wire [31:0] fetch_pc = if_req_addr;
wire [31:0] instr_pc;
wire [31:0] pred_next_pc_if;

reg         id_stall;
reg         id_flush;
reg         id_if_vld;
wire        id_if_rdy;
wire        id_ex_vld;
reg         id_ex_rdy;
reg  [31:0] id_instr_in;
reg  [31:0] id_pc_in;
reg  [31:0] id_pred_in;
wire [31:0] id_instr_out;
wire [31:0] id_pc_out;
wire [31:0] id_pred_out;

wire [`RFIDX_WIDTH-1:0] unused_rs1idx;
wire [`RFIDX_WIDTH-1:0] unused_rs2idx;
wire [`RFIDX_WIDTH-1:0] unused_rd_idx;
wire [31:0] unused_imm;
wire [`DECINFO_BUS_WIDTH-1:0] unused_dec_info;
wire unused_rd_wen;
wire unused_need_rs1;
wire unused_need_rs2;

ifu u_ifu (
    .clk                 (clk),
    .rst_n               (rst_n),
    .i_stall             (if_stall),
    .i_if_id_rdy         (if_id_rdy),
    .o_if_id_vld         (if_id_vld),
    .i_redirect_req      (redirect_req),
    .i_redirect_pcnext   (redirect_pc),
    .i_bp_update_vld     (bp_update_vld),
    .i_bp_update_pc      (bp_update_pc),
    .i_bp_update_is_cond (bp_update_is_cond),
    .i_bp_update_taken   (bp_update_taken),
    .i_bp_update_target  (bp_update_target),
    .i_bp_invalidate     (bp_invalidate),
    .i_ras_resolve_fire  (ras_resolve_fire),
    .i_ras_resolve_pop   (ras_resolve_pop),
    .i_ras_resolve_push  (ras_resolve_push),
    .i_ras_resolve_push_addr (ras_resolve_push_addr),
    .o_if_req_vld        (if_req_vld),
    .i_if_req_rdy        (if_req_rdy),
    .o_if_req_addr       (if_req_addr),
    .i_if_rsp_vld        (if_rsp_vld),
    .o_if_rsp_rdy        (),
    .i_if_rsp_data       (if_rsp_data),
    .o_instr_pc          (instr_pc),
    .o_instr_if          (),
    .o_pred_next_pc_if   (pred_next_pc_if)
);

idu u_idu (
    .clk               (clk),
    .rst_n             (rst_n),
    .i_stall           (id_stall),
    .i_flush           (id_flush),
    .i_if_id_vld       (id_if_vld),
    .o_if_id_rdy       (id_if_rdy),
    .o_id_ex_vld       (id_ex_vld),
    .i_id_ex_rdy       (id_ex_rdy),
    .i_instr           (id_instr_in),
    .i_pc_if           (id_pc_in),
    .i_pred_next_pc_if (id_pred_in),
    .o_dec_rs1idx      (unused_rs1idx),
    .o_dec_rs2idx      (unused_rs2idx),
    .o_dec_rd_idx      (unused_rd_idx),
    .o_dec_imm         (unused_imm),
    .o_dec_info_bus_id (unused_dec_info),
    .o_dec_rd_wen_id   (unused_rd_wen),
    .o_need_rs1_idu    (unused_need_rs1),
    .o_need_rs2_idu    (unused_need_rs2),
    .o_instr_id        (id_instr_out),
    .o_pc_id           (id_pc_out),
    .o_pred_next_pc_id (id_pred_out)
);

always #5 clk = ~clk;

// One-cycle response model.  The instruction value is sampled with request fire.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_rsp_vld <= 1'b0;
        if_rsp_data <= 32'h0000_0013;
    end else begin
        if_rsp_vld <= if_req_vld & if_req_rdy;
        if (if_req_vld & if_req_rdy)
            if_rsp_data <= instr_if;
    end
end

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

task automatic return_instr;
    input [31:0] instr;
    begin
        wait(if_req_vld === 1'b1);
        @(negedge clk);
        instr_if = instr;
        if_req_rdy = 1'b1;
        @(posedge clk);
        #1 if_req_rdy = 1'b0;
        @(posedge clk);
        #1;
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    failures = 0;
    if_stall = 1'b0;
    if_id_rdy = 1'b0;
    if_req_rdy = 1'b0;
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
    id_stall = 1'b0;
    id_flush = 1'b0;
    id_if_vld = 1'b0;
    id_ex_rdy = 1'b1;
    id_instr_in = 32'b0;
    id_pc_in = 32'b0;
    id_pred_in = 32'b0;

    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;
    return_instr(32'h0000_0013);
    check(if_id_vld, "IFU must present payload only after a memory response");
    check(instr_pc == 32'h0 && pred_next_pc_if == 32'h4,
          "IFU prediction must align with returned instruction PC, not request PC");

    @(negedge clk);
    if_id_rdy = 1'b1;
    @(posedge clk);
    #1;
    if_id_rdy = 1'b0;
    check(fetch_req && fetch_pc == 32'h4,
          "accepted cold payload must issue the sequential request");

    // Train before accepting the held request so its transaction captures the target.
    @(negedge clk);
    bp_update_vld = 1'b1;
    bp_update_pc = 32'h4;
    bp_update_is_cond = 1'b0;
    bp_update_taken = 1'b1;
    bp_update_target = 32'h40;
    @(posedge clk);
    #1;
    bp_update_vld = 1'b0;
    check(fetch_req && fetch_pc == 32'h4,
          "request backpressure must hold valid and address");
    return_instr(32'h0000_0013);
    check(instr_pc == 32'h4 && pred_next_pc_if == 32'h40,
          "transaction must retain the prediction sampled for its request PC");

    @(negedge clk);
    if_id_rdy = 1'b1;
    @(posedge clk);
    #1 if_id_rdy = 1'b0;
    check(fetch_req && fetch_pc == 32'h40,
          "accepted prediction must become the next request PC");

    // Redirect makes an unaccepted old request stale; it is drained before target issue.
    @(negedge clk);
    redirect_req = 1'b1;
    redirect_pc = 32'h100;
    #1;
    check(fetch_pc == 32'h40 && !if_id_vld,
          "redirect must suppress the old IF payload while a request is pending");
    @(posedge clk);
    #1;
    redirect_req = 1'b0;
    return_instr(32'h0000_0013); // stale PC 0x40 response is discarded
    return_instr(32'h0000_0013); // redirected PC 0x100 response is published
    check(instr_pc == 32'h100 && pred_next_pc_if == 32'h104,
          "redirect target must become the next published transaction");

    // ID payload captures only on valid/ready fire.
    @(negedge clk);
    id_if_vld = 1'b1;
    id_instr_in = 32'h0010_0093;
    id_pc_in = 32'h200;
    id_pred_in = 32'h280;
    @(posedge clk);
    #1;
    check(id_ex_vld && id_instr_out == 32'h0010_0093
          && id_pc_out == 32'h200 && id_pred_out == 32'h280,
          "ID instruction, PC and prediction payload must capture together");

    // An invalid bubble may clear valid but must not overwrite payload.
    @(negedge clk);
    id_if_vld = 1'b0;
    id_instr_in = 32'hdead_beef;
    id_pc_in = 32'hdead_0000;
    id_pred_in = 32'hdead_0004;
    @(posedge clk);
    #1;
    check(!id_ex_vld && id_instr_out == 32'h0010_0093
          && id_pc_out == 32'h200 && id_pred_out == 32'h280,
          "invalid ready cycle must clear valid without overwriting ID payload");

    // Downstream backpressure holds both valid and all payload fields.
    @(negedge clk);
    id_if_vld = 1'b1;
    id_ex_rdy = 1'b1;
    id_instr_in = 32'h0020_0113;
    id_pc_in = 32'h204;
    id_pred_in = 32'h208;
    @(posedge clk);
    #1;
    @(negedge clk);
    id_ex_rdy = 1'b0;
    id_instr_in = 32'hffff_ffff;
    id_pc_in = 32'hffff_0000;
    id_pred_in = 32'hffff_0004;
    @(posedge clk);
    #1;
    check(id_ex_vld && id_instr_out == 32'h0020_0113
          && id_pc_out == 32'h204 && id_pred_out == 32'h208,
          "ID backpressure must hold valid, instruction, PC and prediction payload");

    // Flush kills valid and preserves don't-care payload consistently.
    @(negedge clk);
    id_flush = 1'b1;
    @(posedge clk);
    #1;
    id_flush = 1'b0;
    check(!id_ex_vld && id_instr_out == 32'h0020_0113
          && id_pc_out == 32'h204 && id_pred_out == 32'h208,
          "ID flush must kill valid without independently modifying prediction payload");

    if (failures == 0)
        $display("PASS: BPU IF/ID alignment and handshake directed test");
    else
        $display("FAIL: BPU frontend directed test, failures=%0d", failures);
    $finish;
end

endmodule
