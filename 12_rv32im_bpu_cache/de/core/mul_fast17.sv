`timescale 1ns / 1ps
`include "config.v"

module mul_fast17(
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
localparam ST_ALBL     = 3'd1;
localparam ST_ALBH     = 3'd2;
localparam ST_AHBL     = 3'd3;
localparam ST_AHBH     = 3'd4;
localparam ST_RESPONSE = 3'd5;

reg [2:0] state_q;
reg [31:0] operand_a_q;
reg [31:0] operand_b_q;
reg [1:0] op_q;
reg [15:0] result_low16_q;
reg signed [33:0] acc_q;
reg [31:0] rsp_result_q;

wire req_fire = i_req_vld & o_req_rdy;
wire rsp_fire = o_rsp_vld & i_rsp_rdy;

wire op_a_signed = (op_q == `MDU_OP_MULH) | (op_q == `MDU_OP_MULHSU);
wire op_b_signed = (op_q == `MDU_OP_MULH);
wire op_is_mul = (op_q == `MDU_OP_MUL);

wire [15:0] a_l = operand_a_q[15:0];
wire [15:0] a_h = operand_a_q[31:16];
wire [15:0] b_l = operand_b_q[15:0];
wire [15:0] b_h = operand_b_q[31:16];

reg signed [16:0] mac_op_a;
reg signed [16:0] mac_op_b;

always @(*) begin
    case (state_q)
        ST_ALBL: begin
            mac_op_a = $signed({1'b0, a_l});
            mac_op_b = $signed({1'b0, b_l});
        end

        ST_ALBH: begin
            mac_op_a = $signed({1'b0, a_l});
            mac_op_b = $signed({op_b_signed & operand_b_q[31], b_h});
        end

        ST_AHBL: begin
            mac_op_a = $signed({op_a_signed & operand_a_q[31], a_h});
            mac_op_b = $signed({1'b0, b_l});
        end

        ST_AHBH: begin
            mac_op_a = $signed({op_a_signed & operand_a_q[31], a_h});
            mac_op_b = $signed({op_b_signed & operand_b_q[31], b_h});
        end

        default: begin
            mac_op_a = 17'sd0;
            mac_op_b = 17'sd0;
        end
    endcase
end

wire signed [33:0] mac_product = mac_op_a * mac_op_b;
wire signed [34:0] acc_sum_ext = {acc_q[33], acc_q} + {mac_product[33], mac_product};
wire signed [33:0] acc_next = acc_sum_ext[33:0];
wire signed [33:0] acc_shift = acc_q >>> 16;
wire signed [34:0] high_sum_ext = {acc_shift[33], acc_shift} + {mac_product[33], mac_product};

assign o_req_rdy = (state_q == ST_IDLE);
assign o_rsp_vld = (state_q == ST_RESPONSE);
assign o_rsp_result = rsp_result_q;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= ST_IDLE;
        operand_a_q <= 32'd0;
        operand_b_q <= 32'd0;
        op_q <= `MDU_OP_MUL;
        result_low16_q <= 16'd0;
        acc_q <= 34'sd0;
        rsp_result_q <= 32'd0;
    end
    else if (i_kill) begin
        state_q <= ST_IDLE;
        operand_a_q <= 32'd0;
        operand_b_q <= 32'd0;
        op_q <= `MDU_OP_MUL;
        result_low16_q <= 16'd0;
        acc_q <= 34'sd0;
        rsp_result_q <= 32'd0;
    end
    else begin
        case (state_q)
            ST_IDLE: begin
                if (req_fire) begin
                    operand_a_q <= i_req_operand_a;
                    operand_b_q <= i_req_operand_b;
                    op_q <= i_req_op;
                    state_q <= ST_ALBL;
                end
            end

            ST_ALBL: begin
                result_low16_q <= mac_product[15:0];
                acc_q <= $signed({18'd0, mac_product[31:16]});
                state_q <= ST_ALBH;
            end

            ST_ALBH: begin
                acc_q <= acc_next;
                state_q <= ST_AHBL;
            end

            ST_AHBL: begin
                if (op_is_mul) begin
                    rsp_result_q <= {acc_next[15:0], result_low16_q};
                    state_q <= ST_RESPONSE;
                end
                else begin
                    acc_q <= acc_next;
                    state_q <= ST_AHBH;
                end
            end

            ST_AHBH: begin
                rsp_result_q <= high_sum_ext[31:0];
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
