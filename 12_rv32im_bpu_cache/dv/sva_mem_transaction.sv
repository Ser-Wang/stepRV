`timescale 1ns / 1ps

module sva_if_transaction (
    input wire clk, input wire rst_n,
    input wire req_vld, input wire req_rdy, input wire [31:0] req_addr,
    input wire rsp_vld, input wire rsp_rdy, input wire [31:0] rsp_data,
    input wire outstanding
);
assert_if_req_hold: assert property (@(posedge clk) disable iff (!rst_n)
    req_vld && !req_rdy |=> req_vld && $stable(req_addr))
else $error("[Phase0 SVA][IF] request changed while stalled");
assert_if_rsp_hold: assert property (@(posedge clk) disable iff (!rst_n)
    rsp_vld && !rsp_rdy |=> rsp_vld && $stable(rsp_data))
else $error("[Phase0 SVA][IF] response changed while stalled");
assert_if_rsp_has_request: assert property (@(posedge clk) disable iff (!rst_n)
    rsp_vld && rsp_rdy |-> outstanding)
else $error("[Phase0 SVA][IF] response fire without outstanding request");
endmodule

module sva_mau_transaction (
    input wire clk, input wire rst_n,
    input wire req_vld, input wire req_rdy,
    input wire [31:0] req_addr, input wire req_load, input wire req_write,
    input wire [1:0] req_size, input wire [3:0] req_mask,
    input wire [31:0] req_data,
    input wire rsp_vld, input wire rsp_rdy, input wire [31:0] rsp_data,
    input wire outstanding
);
assert_lsu_req_hold: assert property (@(posedge clk) disable iff (!rst_n)
    req_vld && !req_rdy |=> req_vld &&
        $stable({req_addr, req_load, req_write, req_size, req_mask, req_data}))
else $error("[Phase0 SVA][MAU] request changed while stalled");
assert_lsu_rsp_hold: assert property (@(posedge clk) disable iff (!rst_n)
    rsp_vld && !rsp_rdy |=> rsp_vld && $stable(rsp_data))
else $error("[Phase0 SVA][MAU] response changed while stalled");
assert_response_has_request: assert property (@(posedge clk) disable iff (!rst_n)
    rsp_vld && rsp_rdy |-> outstanding)
else $error("[Phase0 SVA][MAU] response fire without outstanding request");
endmodule

`ifndef PHASE0_MAU_ONLY
bind ifu sva_if_transaction u_sva_if_transaction (
    .clk(clk), .rst_n(rst_n),
    .req_vld(o_if_req_vld), .req_rdy(i_if_req_rdy), .req_addr(o_if_req_addr),
    .rsp_vld(i_if_rsp_vld), .rsp_rdy(o_if_rsp_rdy), .rsp_data(i_if_rsp_data),
    .outstanding(outstanding_r)
);
`endif

`ifndef PHASE0_IF_ONLY
bind mau sva_mau_transaction u_sva_mau_transaction (
    .clk(clk), .rst_n(rst_n),
    .req_vld(o_mem_req_vld), .req_rdy(i_mem_req_rdy),
    .req_addr(o_mem_addr), .req_load(o_mem_req_load), .req_write(o_mem_wr_en),
    .req_size(o_mem_size), .req_mask(o_mem_wr_mask), .req_data(o_mem_wr_data),
    .rsp_vld(i_mem_rsp_vld), .rsp_rdy(o_mem_rsp_rdy), .rsp_data(i_mem_rsp_data),
    .outstanding(outstanding_r)
);
`endif
