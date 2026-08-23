`timescale 1ns / 1ps
`include "config.v"

module exu_muldiv(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_req_vld,
    output wire        o_req_rdy,
    input  wire [`DECINFO_BUS_MDU_WIDTH-1:0] i_dec_info_bus_mdu,
    input  wire [31:0] i_req_rs1,
    input  wire [31:0] i_req_rs2,
    input  wire        i_rsp_rdy,
    output wire        o_rsp_vld,
    output wire [31:0] o_rsp_result,
    input  wire        i_kill
    );

wire [2:0] mdu_op = i_dec_info_bus_mdu[`DECINFO_MDU_OP];
wire [1:0] mul_op = mdu_op[1:0];
wire [1:0] div_op = mdu_op[1:0];
wire req_is_div = mdu_op[2];

wire mul_req_vld = i_req_vld & (~req_is_div);
wire mul_req_rdy;
wire mul_rsp_vld;
wire [31:0] mul_rsp_result;

wire div_req_vld = i_req_vld & req_is_div;
wire div_req_rdy;
wire div_rsp_vld;
wire [31:0] div_rsp_result;

assign o_req_rdy = req_is_div ? div_req_rdy : mul_req_rdy;
assign o_rsp_vld = req_is_div ? div_rsp_vld : mul_rsp_vld;
assign o_rsp_result = req_is_div ? div_rsp_result : mul_rsp_result;

mul_fast17 u_mul_fast17(
    .clk             (clk           ),
    .rst_n           (rst_n         ),
    .i_req_vld       (mul_req_vld   ),
    .o_req_rdy       (mul_req_rdy   ),
    .i_req_op        (mul_op        ),
    .i_req_operand_a (i_req_rs1     ),
    .i_req_operand_b (i_req_rs2     ),
    .o_rsp_vld       (mul_rsp_vld   ),
    .i_rsp_rdy       (i_rsp_rdy     ),
    .o_rsp_result    (mul_rsp_result),
    .i_kill          (i_kill        )
    );

// Switch to the Phase1 multiplier baseline by commenting u_mul_fast17 above and
// uncommenting this instance.
// mul_radix2 u_mul_radix2(
//     .clk             (clk           ),
//     .rst_n           (rst_n         ),
//     .i_req_vld       (mul_req_vld   ),
//     .o_req_rdy       (mul_req_rdy   ),
//     .i_req_op        (mul_op        ),
//     .i_req_operand_a (i_req_rs1     ),
//     .i_req_operand_b (i_req_rs2     ),
//     .o_rsp_vld       (mul_rsp_vld   ),
//     .i_rsp_rdy       (i_rsp_rdy     ),
//     .o_rsp_result    (mul_rsp_result),
//     .i_kill          (i_kill        )
//     );

div_radix2 u_div_radix2(
    .clk             (clk           ),
    .rst_n           (rst_n         ),
    .i_req_vld       (div_req_vld   ),
    .o_req_rdy       (div_req_rdy   ),
    .i_req_op        (div_op        ),
    .i_req_operand_a (i_req_rs1     ),
    .i_req_operand_b (i_req_rs2     ),
    .o_rsp_vld       (div_rsp_vld   ),
    .i_rsp_rdy       (i_rsp_rdy     ),
    .o_rsp_result    (div_rsp_result),
    .i_kill          (i_kill        )
    );

endmodule
