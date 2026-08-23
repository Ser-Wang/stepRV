`timescale 1ns / 1ps
`include "config.v"

module div_radix2(
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

reg [2:0]  state_q;
reg [31:0] raw_operand_a_q;
reg [31:0] raw_operand_b_q;
reg [1:0]  op_q;
reg [31:0] dividend_q;
reg [31:0] divisor_q;
reg [32:0] partial_rem_q;
reg [31:0] quotient_q;
reg [4:0]  bit_idx_q;
reg quotient_neg_q;
reg remainder_neg_q;
reg special_q;
reg [31:0] rsp_result_q;

wire req_fire = i_req_vld & o_req_rdy;
wire rsp_fire = o_rsp_vld & i_rsp_rdy;

wire op_signed = (op_q == `MDU_DIV_OP_DIV) | (op_q == `MDU_DIV_OP_REM);
wire op_rem = (op_q == `MDU_DIV_OP_REM) | (op_q == `MDU_DIV_OP_REMU);
wire a_neg = op_signed & raw_operand_a_q[31];
wire b_neg = op_signed & raw_operand_b_q[31];
wire [31:0] a_mag = a_neg ? (~raw_operand_a_q + 32'd1) : raw_operand_a_q;
wire [31:0] b_mag = b_neg ? (~raw_operand_b_q + 32'd1) : raw_operand_b_q;
wire div_by_zero = (raw_operand_b_q == 32'd0);
wire signed_overflow = op_signed & (raw_operand_a_q == 32'h8000_0000) & (raw_operand_b_q == 32'hffff_ffff);

wire [32:0] trial_rem = {partial_rem_q[31:0], dividend_q[bit_idx_q]};
wire [32:0] divisor_ext = {1'b0, divisor_q};
wire trial_ge_divisor = (trial_rem >= divisor_ext);
wire [32:0] rem_after_iter = trial_ge_divisor ? (trial_rem - divisor_ext) : trial_rem;
wire quotient_bit = trial_ge_divisor;

wire [31:0] quotient_signed = quotient_neg_q ? (~quotient_q + 32'd1) : quotient_q;
wire [31:0] remainder_mag = partial_rem_q[31:0];
wire [31:0] remainder_signed = remainder_neg_q ? (~remainder_mag + 32'd1) : remainder_mag;
wire [31:0] normal_result = op_rem ? remainder_signed : quotient_signed;

assign o_req_rdy = (state_q == ST_IDLE);
assign o_rsp_vld = (state_q == ST_RESPONSE);
assign o_rsp_result = rsp_result_q;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= ST_IDLE;
        raw_operand_a_q <= 32'd0;
        raw_operand_b_q <= 32'd0;
        op_q <= `MDU_DIV_OP_DIV;
        dividend_q <= 32'd0;
        divisor_q <= 32'd0;
        partial_rem_q <= 33'd0;
        quotient_q <= 32'd0;
        bit_idx_q <= 5'd0;
        quotient_neg_q <= 1'b0;
        remainder_neg_q <= 1'b0;
        special_q <= 1'b0;
        rsp_result_q <= 32'd0;
    end
    else if (i_kill) begin
        state_q <= ST_IDLE;
        raw_operand_a_q <= 32'd0;
        raw_operand_b_q <= 32'd0;
        op_q <= `MDU_DIV_OP_DIV;
        dividend_q <= 32'd0;
        divisor_q <= 32'd0;
        partial_rem_q <= 33'd0;
        quotient_q <= 32'd0;
        bit_idx_q <= 5'd0;
        quotient_neg_q <= 1'b0;
        remainder_neg_q <= 1'b0;
        special_q <= 1'b0;
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
                dividend_q <= a_mag;
                divisor_q <= b_mag;
                partial_rem_q <= 33'd0;
                quotient_q <= 32'd0;
                bit_idx_q <= 5'd31;
                quotient_neg_q <= a_neg ^ b_neg;
                remainder_neg_q <= a_neg;
                special_q <= div_by_zero | signed_overflow;
                if (div_by_zero) begin
                    rsp_result_q <= op_rem ? raw_operand_a_q : 32'hffff_ffff;
                    state_q <= ST_RESPONSE;
                end
                else if (signed_overflow) begin
                    rsp_result_q <= op_rem ? 32'd0 : 32'h8000_0000;
                    state_q <= ST_RESPONSE;
                end
                else begin
                    state_q <= ST_ITERATE;
                end
            end

            ST_ITERATE: begin
                partial_rem_q <= rem_after_iter;
                quotient_q[bit_idx_q] <= quotient_bit;
                if (bit_idx_q == 5'd0) begin
                    state_q <= ST_FINAL;
                end
                else begin
                    bit_idx_q <= bit_idx_q - 5'd1;
                end
            end

            ST_FINAL: begin
                if (!special_q) begin
                    rsp_result_q <= normal_result;
                end
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
