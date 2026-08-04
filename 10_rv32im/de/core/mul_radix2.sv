`timescale 1ns / 1ps
`include "config.v"

module mul_radix2(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_req_vld,
    output wire        o_req_rdy,
    input  wire [1:0]  i_req_op,
    input  wire [31:0] i_req_operand_a,
    input  wire [31:0] i_req_operand_b,
    output wire        o_rsp_vld,
    input  wire        i_rsp_rdy,
    output wire [31:0] o_rsp_result,
    input  wire        i_kill
    );

localparam ST_IDLE     = 3'd0;
localparam ST_PREPARE  = 3'd1;
localparam ST_ITERATE  = 3'd2;
localparam ST_FINAL    = 3'd3;
localparam ST_RESPONSE = 3'd4;

reg [2:0] state_q;
reg [31:0] raw_operand_a_q;
reg [31:0] raw_operand_b_q;
reg [1:0] op_q;
reg [31:0] multiplicand_q;
reg [31:0] multiplier_q;
reg [32:0] acc_q;
reg [5:0] iter_count_q;
reg result_neg_q;
reg [31:0] rsp_result_q;

wire req_fire = i_req_vld & o_req_rdy;
wire rsp_fire = o_rsp_vld & i_rsp_rdy;

wire op_a_signed = (op_q == `MDU_OP_MULH) | (op_q == `MDU_OP_MULHSU);
wire op_b_signed = (op_q == `MDU_OP_MULH);
wire neg_a = op_a_signed & raw_operand_a_q[31];
wire neg_b = op_b_signed & raw_operand_b_q[31];
wire [31:0] magnitude_a = neg_a ? (~raw_operand_a_q + 32'd1) : raw_operand_a_q;
wire [31:0] magnitude_b = neg_b ? (~raw_operand_b_q + 32'd1) : raw_operand_b_q;

wire [32:0] acc_add = acc_q + (multiplier_q[0] ? {1'b0, multiplicand_q} : 33'd0);
wire [64:0] iter_shifted = {acc_add, multiplier_q} >> 1;
wire [63:0] magnitude_product = {acc_q[31:0], multiplier_q};
wire [63:0] full_product = result_neg_q ? (~magnitude_product + 64'd1) : magnitude_product;
wire sel_low_result = (op_q == `MDU_OP_MUL);

assign o_req_rdy = (state_q == ST_IDLE);
assign o_rsp_vld = (state_q == ST_RESPONSE);
assign o_rsp_result = rsp_result_q;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= ST_IDLE;
        raw_operand_a_q <= 32'd0;
        raw_operand_b_q <= 32'd0;
        op_q <= `MDU_OP_MUL;
        multiplicand_q <= 32'd0;
        multiplier_q <= 32'd0;
        acc_q <= 33'd0;
        iter_count_q <= 6'd0;
        result_neg_q <= 1'b0;
        rsp_result_q <= 32'd0;
    end
    else if (i_kill) begin
        state_q <= ST_IDLE;
        raw_operand_a_q <= 32'd0;
        raw_operand_b_q <= 32'd0;
        op_q <= `MDU_OP_MUL;
        multiplicand_q <= 32'd0;
        multiplier_q <= 32'd0;
        acc_q <= 33'd0;
        iter_count_q <= 6'd0;
        result_neg_q <= 1'b0;
        rsp_result_q <= 32'd0;
    end
    else begin
        case (state_q)
            ST_IDLE: begin
                if (req_fire) begin
                    raw_operand_a_q <= i_req_operand_a;
                    raw_operand_b_q <= i_req_operand_b;
                    op_q <= i_req_op;
                    state_q <= ST_PREPARE;
                end
            end

            ST_PREPARE: begin
                multiplicand_q <= magnitude_a;
                multiplier_q <= magnitude_b;
                acc_q <= 33'd0;
                iter_count_q <= 6'd0;
                result_neg_q <= neg_a ^ neg_b;
                state_q <= ST_ITERATE;
            end

            ST_ITERATE: begin
                acc_q <= iter_shifted[64:32];
                multiplier_q <= iter_shifted[31:0];
                if (iter_count_q == 6'd31) begin
                    iter_count_q <= 6'd0;
                    state_q <= ST_FINAL;
                end
                else begin
                    iter_count_q <= iter_count_q + 6'd1;
                end
            end

            ST_FINAL: begin
                rsp_result_q <= sel_low_result ? full_product[31:0] : full_product[63:32];
                state_q <= ST_RESPONSE;
            end

            ST_RESPONSE: begin
                if (rsp_fire) begin
                    state_q <= ST_IDLE;
                end
            end

            default: begin
                state_q <= ST_IDLE;
            end
        endcase
    end
end

endmodule
