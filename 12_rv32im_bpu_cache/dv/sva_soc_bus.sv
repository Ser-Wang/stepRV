`timescale 1ns / 1ps

module sva_soc_bus (
    input wire clk,
    input wire rst_n,
    input wire mem_req_vld,
    input wire mem_req_rdy,
    input wire mem_req_write,
    input wire [31:0] mem_req_addr,
    input wire imem_write,
    input wire dcache_store_fire,
    input wire uart_write
);

wire mem_req_fire = mem_req_vld && mem_req_rdy;

assert_target_write_has_request:
assert property (@(posedge clk) disable iff (!rst_n)
    (imem_write || dcache_store_fire || uart_write) |->
        (mem_req_fire && mem_req_write))
else $error("[Phase2 SVA][BUS] target write without store request fire at %h",
            mem_req_addr);

assert_at_most_one_write_target:
assert property (@(posedge clk) disable iff (!rst_n)
    $onehot0({imem_write, dcache_store_fire, uart_write}))
else $error("[Phase2 SVA][BUS] multiple write targets selected");

endmodule
