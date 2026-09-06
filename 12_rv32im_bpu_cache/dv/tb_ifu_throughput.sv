`timescale 1ns / 1ps
`include "config.v"

module tb_ifu_throughput;

localparam integer STREAM_LEN = 16;

reg         clk;
reg         rst_n;
wire        if_req_vld;
wire        if_req_rdy;
wire [31:0] if_req_addr;
reg         if_rsp_vld;
wire        if_rsp_rdy;
reg  [31:0] if_rsp_data;
wire        if_id_vld;
wire [31:0] instr_pc;
wire [31:0] instr;
wire [31:0] pred_next_pc;

integer cycle_count;
integer req_count;
integer rsp_count;
integer id_count;
integer replace_count;
integer buf_replace_count;
integer last_req_cycle;
integer last_rsp_cycle;
integer last_id_cycle;
integer failures;

wire if_req_fire = if_req_vld & if_req_rdy;
wire if_rsp_fire = if_rsp_vld & if_rsp_rdy;
wire if_id_fire = if_id_vld;

assign if_req_rdy = !if_rsp_vld | if_rsp_rdy;

ifu u_ifu (
    .clk(clk), .rst_n(rst_n), .i_stall(1'b0), .i_if_id_rdy(1'b1),
    .o_if_id_vld(if_id_vld), .i_redirect_req(1'b0),
    .i_redirect_pcnext(32'b0), .i_bp_update_vld(1'b0),
    .i_bp_update_pc(32'b0), .i_bp_update_is_cond(1'b0),
    .i_bp_update_taken(1'b0), .i_bp_update_target(32'b0),
    .i_bp_invalidate(1'b0), .i_ras_resolve_fire(1'b0),
    .i_ras_resolve_pop(1'b0), .i_ras_resolve_push(1'b0),
    .i_ras_resolve_push_addr(32'b0), .o_if_req_vld(if_req_vld),
    .i_if_req_rdy(if_req_rdy), .o_if_req_addr(if_req_addr),
    .i_if_rsp_vld(if_rsp_vld), .o_if_rsp_rdy(if_rsp_rdy),
    .i_if_rsp_data(if_rsp_data), .o_instr_pc(instr_pc),
    .o_instr_if(instr), .o_pred_next_pc_if(pred_next_pc)
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

// One-entry, one-cycle backend with same-edge response-pop/request-push.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        if_rsp_vld <= 1'b0;
        if_rsp_data <= `INSTR_NOP;
    end else if (if_req_rdy) begin
        if_rsp_vld <= if_req_fire;
        if (if_req_fire)
            if_rsp_data <= `INSTR_NOP;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_count = 0;
        req_count = 0;
        rsp_count = 0;
        id_count = 0;
        replace_count = 0;
        buf_replace_count = 0;
        last_req_cycle = -1;
        last_rsp_cycle = -1;
        last_id_cycle = -1;
    end else begin
        cycle_count = cycle_count + 1;

        if (if_req_fire && req_count < STREAM_LEN) begin
            check(if_req_addr == (req_count * 4),
                  "IF request address sequence mismatch");
            if (req_count > 0)
                check(cycle_count - last_req_cycle == 1,
                      "steady-state IF request interval must be one cycle");
            last_req_cycle = cycle_count;
            req_count = req_count + 1;
        end

        if (if_rsp_fire && rsp_count < STREAM_LEN) begin
            if (rsp_count > 0)
                check(cycle_count - last_rsp_cycle == 1,
                      "steady-state IF response interval must be one cycle");
            last_rsp_cycle = cycle_count;
            rsp_count = rsp_count + 1;
        end

        if (if_id_fire && id_count < STREAM_LEN) begin
            check(instr_pc == (id_count * 4),
                  "IF/ID PC sequence mismatch");
            check(instr == `INSTR_NOP,
                  "IF/ID instruction data mismatch");
            if (id_count > 0)
                check(cycle_count - last_id_cycle == 1,
                      "steady-state IF/ID interval must be one cycle");
            last_id_cycle = cycle_count;
            id_count = id_count + 1;
        end

        if (if_rsp_fire && if_req_fire)
            replace_count = replace_count + 1;
        if (if_rsp_fire && if_id_fire)
            buf_replace_count = buf_replace_count + 1;
    end
end

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    failures = 0;
    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;

    repeat (64) begin
        @(posedge clk);
        if (id_count >= STREAM_LEN)
            break;
    end
    #1;

    check(req_count >= STREAM_LEN, "IF stream must issue sixteen requests");
    check(rsp_count >= STREAM_LEN, "IF stream must accept sixteen responses");
    check(id_count >= STREAM_LEN, "IF stream must deliver sixteen IF/ID payloads");
    check(replace_count >= STREAM_LEN-1,
          "IF stream must replace response with successor request every cycle");
    check(buf_replace_count >= STREAM_LEN-1,
          "IF response buffer must pop and push on the same edge");
    check(u_ifu.outstanding_r inside {1'b0, 1'b1},
          "IF unanswered depth must remain one-bit bounded");

    if (failures == 0)
        $display("PASS: Phase0 S2 IFU sixteen-entry one-cycle throughput test");
    else
        $display("FAIL: Phase0 S2 IFU throughput test, failures=%0d", failures);
    $finish;
end

endmodule
