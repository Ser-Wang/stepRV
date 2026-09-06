`timescale 1ns / 1ps
`include "config.v"

module tb_ras_frontend_disabled;

reg clk;
reg rst_n;
reg stall;
reg redirect_req;
reg bp_update_vld;
reg [31:0] bp_update_pc;
reg [31:0] bp_update_target;
reg [31:0] instr_if;
wire if_req_vld;
reg if_req_rdy;
reg if_rsp_vld;
reg [31:0] if_rsp_data;
wire if_id_vld;
wire [31:0] instr_pc;
wire [31:0] pred_next_pc;
integer failures;

ifu u_ifu (
    .clk                      (clk),
    .rst_n                    (rst_n),
    .i_stall                  (stall),
    .i_if_id_rdy              (1'b1),
    .o_if_id_vld              (if_id_vld),
    .i_redirect_req           (redirect_req),
    .i_redirect_pcnext        (32'b0),
    .i_bp_update_vld          (bp_update_vld),
    .i_bp_update_pc           (bp_update_pc),
    .i_bp_update_is_cond      (1'b0),
    .i_bp_update_taken        (1'b1),
    .i_bp_update_target       (bp_update_target),
    .i_bp_invalidate          (1'b0),
    .i_ras_resolve_fire       (1'b0),
    .i_ras_resolve_pop        (1'b0),
    .i_ras_resolve_push       (1'b0),
    .i_ras_resolve_push_addr  (32'b0),
    .o_if_req_vld             (if_req_vld),
    .i_if_req_rdy             (if_req_rdy),
    .o_if_req_addr            (),
    .i_if_rsp_vld             (if_rsp_vld),
    .o_if_rsp_rdy             (),
    .i_if_rsp_data            (if_rsp_data),
    .o_instr_pc               (instr_pc),
    .o_instr_if               (),
    .o_pred_next_pc_if        (pred_next_pc)
);

always #5 clk = ~clk;

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

task automatic fail_if;
    input condition;
    input [8*96-1:0] message;
    begin
        if (condition) begin
            failures = failures + 1;
            $display("FAIL: %0s", message);
        end
    end
endtask

task automatic present_instr;
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
    stall = 1'b1;
    redirect_req = 1'b0;
    bp_update_vld = 1'b0;
    bp_update_pc = 32'b0;
    bp_update_target = 32'b0;
    instr_if = 32'h0000_00ef; // jal x1
    if_req_rdy = 1'b0;
    failures = 0;

    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;
    present_instr(32'h0000_00ef);
    @(negedge clk) stall = 1'b0;
    @(posedge clk);
    #1 stall = 1'b1;
    fail_if(u_ifu.ras_top_vld !== 1'b0,
            "disabled frontend must not push accepted JAL x1");

    // Train before accepting the PC=4 request so the transaction captures 0x80.
    @(negedge clk);
    bp_update_vld = 1'b1;
    bp_update_pc = 32'h4;
    bp_update_target = 32'h80;
    @(posedge clk);
    #1 bp_update_vld = 1'b0;
    present_instr(32'h0000_8067); // jalr x0, 0(x1)
    fail_if(pred_next_pc !== ((`BPU_ENABLE != 0) ? 32'h80 : (instr_pc + 32'd4)),
            "disabled RAS return must use existing predictor result");
    fail_if(u_ifu.ras_pred_hit !== 1'b0,
            "disabled RAS must never report a prediction hit");

    if (failures == 0)
        $display("PASS: RAS-disabled IFU fallback directed test");
    else
        $display("FAIL: RAS-disabled frontend test, failures=%0d", failures);
    $finish;
end

endmodule
