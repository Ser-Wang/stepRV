`timescale 1ns / 1ps
`include "config.v"

module tb_ifu_variable_latency;
reg clk, rst_n, stall, if_id_rdy, redirect_req;
reg [31:0] redirect_pc;
reg req_rdy, rsp_vld;
reg [31:0] rsp_data;
wire if_id_vld, req_vld, rsp_rdy;
wire [31:0] req_addr, instr_pc, instr, pred_pc;
integer failures, req_count, rsp_count, id_count, n;

ifu u_ifu (
    .clk(clk), .rst_n(rst_n), .i_stall(stall), .i_if_id_rdy(if_id_rdy),
    .o_if_id_vld(if_id_vld), .i_redirect_req(redirect_req),
    .i_redirect_pcnext(redirect_pc), .i_bp_update_vld(1'b0),
    .i_bp_update_pc(32'b0), .i_bp_update_is_cond(1'b0),
    .i_bp_update_taken(1'b0), .i_bp_update_target(32'b0),
    .i_bp_invalidate(1'b0), .i_ras_resolve_fire(1'b0),
    .i_ras_resolve_pop(1'b0), .i_ras_resolve_push(1'b0),
    .i_ras_resolve_push_addr(32'b0), .o_if_req_vld(req_vld),
    .i_if_req_rdy(req_rdy), .o_if_req_addr(req_addr),
    .i_if_rsp_vld(rsp_vld), .o_if_rsp_rdy(rsp_rdy),
    .i_if_rsp_data(rsp_data), .o_instr_pc(instr_pc),
    .o_instr_if(instr), .o_pred_next_pc_if(pred_pc)
);

always #5 clk = ~clk;
always @(posedge clk) if (rst_n) begin
    if (req_vld && req_rdy) req_count = req_count + 1;
    if (rsp_vld && rsp_rdy) rsp_count = rsp_count + 1;
    if (if_id_vld && if_id_rdy && !stall) id_count = id_count + 1;
end

task automatic check;
    input condition;
    input [8*112-1:0] message;
    begin if (!condition) begin failures=failures+1; $display("FAIL: %0s", message); end end
endtask

task automatic accept_req;
    input [31:0] expected_addr;
    begin
        wait(req_vld === 1'b1);
        check(req_addr == expected_addr, "request address must match transaction sequence");
        @(negedge clk); req_rdy=1;
        @(posedge clk); #1 req_rdy=0;
        check(!req_vld && rsp_rdy, "request fire must create one outstanding IF transaction");
    end
endtask

task automatic send_rsp;
    input [31:0] data;
    begin
        @(negedge clk); rsp_data=data; rsp_vld=1;
        @(posedge clk); #1 rsp_vld=0;
    end
endtask

task automatic consume_if;
    begin
        @(negedge clk); if_id_rdy=1;
        @(posedge clk); #1 if_id_rdy=0;
    end
endtask

initial begin
    clk=0; rst_n=0; stall=0; if_id_rdy=0; redirect_req=0; redirect_pc=0;
    req_rdy=0; rsp_vld=0; rsp_data=0; failures=0;
    req_count=0; rsp_count=0; id_count=0;
    repeat (2) @(posedge clk); #1 rst_n=1;

    wait(req_vld === 1'b1);
    for (n=0; n<3; n=n+1) begin
        @(posedge clk); #1;
        check(req_vld && req_addr == 0, "IF request must hold for at least three stalled cycles");
    end
    accept_req(32'h0);
    for (n=0; n<7; n=n+1) begin
        @(posedge clk); #1;
        check(!if_id_vld && !req_vld, "delayed IF response must not create early payload or reissue");
    end
    send_rsp(32'h0000_0013);
    check(if_id_vld && instr_pc==0 && instr==32'h0000_0013 && pred_pc==4,
          "response must publish instruction with captured PC/prediction metadata");
    for (n=0; n<3; n=n+1) begin
        @(posedge clk); #1;
        check(if_id_vld && instr_pc==0 && instr==32'h0000_0013,
              "IF/ID backpressure must hold returned payload stable");
    end
    consume_if();

    accept_req(32'h4);
    repeat (2) @(posedge clk);
    @(negedge clk); redirect_pc=32'h100; redirect_req=1;
    @(posedge clk); #1 redirect_req=0;
    send_rsp(32'hdead_beef);
    check(!if_id_vld, "stale response after redirect must not reach IF/ID");
    accept_req(32'h100);
    repeat (2) @(posedge clk);
    send_rsp(32'h0010_0093);
    check(if_id_vld && instr_pc==32'h100 && instr==32'h0010_0093,
          "redirect target response must be the next published payload");
    consume_if();

    check(req_count==3 && rsp_count==3 && id_count==2,
          "IF scoreboard requires one response per request and excludes stale commit");
    if (failures==0)
        $display("PASS: Phase0 IFU variable-latency, backpressure and stale-response directed test");
    else
        $display("FAIL: Phase0 IFU directed test, failures=%0d", failures);
    $finish;
end
endmodule
