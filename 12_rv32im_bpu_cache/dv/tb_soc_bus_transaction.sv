`timescale 1ns / 1ps

module tb_soc_bus_transaction;
reg clk, rst_n, req_vld, req_load, req_write, rsp_rdy;
reg [31:0] req_addr, req_wdata;
reg [1:0] req_size;
reg [3:0] req_mask;
wire req_rdy, rsp_vld;
wire [31:0] rsp_data;
wire itcm_en, itcm_we, dtcm_en, dtcm_we, uart_we;
wire [31:0] unused_addr0, unused_addr1, unused_addr2;
wire [3:0] unused_mask0, unused_mask1;
wire [31:0] unused_data0, unused_data1, unused_data2;
integer failures, req_count, rsp_count, target_write_count, n;

soc_bus u_bus (
    .clk(clk), .rst_n(rst_n), .i_mem_req_vld(req_vld), .o_mem_req_rdy(req_rdy),
    .i_mem_addr(req_addr), .i_mem_req_load(req_load), .i_mem_wr_en(req_write),
    .i_mem_size(req_size), .i_mem_wr_mask(req_mask), .i_mem_wr_data(req_wdata),
    .o_mem_rsp_vld(rsp_vld), .i_mem_rsp_rdy(rsp_rdy), .o_mem_rd_data(rsp_data),
    .o_itcm_p1_en(itcm_en), .o_itcm_p1_we(itcm_we), .o_itcm_p1_addr(unused_addr0),
    .o_itcm_p1_wmask(unused_mask0), .o_itcm_p1_wdata(unused_data0),
    .i_itcm_p1_rdata(32'haaaa_5555), .o_dtcm_en(dtcm_en),
    .o_dtcm_addr(unused_addr1), .o_dtcm_wr_en(dtcm_we),
    .o_dtcm_wr_mask(unused_mask1), .o_dtcm_wr_data(unused_data1),
    .i_dtcm_rd_data(32'h1234_5678), .o_uart_addr(unused_addr2),
    .o_uart_wr_en(uart_we), .o_uart_wr_data(unused_data2),
    .i_uart_rd_data(32'h0000_0041)
);

bind soc_bus sva_soc_bus u_sva_soc_bus (
    .clk(clk), .rst_n(rst_n), .mem_req_vld(i_mem_req_vld),
    .mem_req_rdy(o_mem_req_rdy), .mem_req_write(i_mem_wr_en),
    .mem_req_addr(i_mem_addr), .itcm_write(o_itcm_p1_we),
    .dtcm_write(o_dtcm_wr_en), .uart_write(o_uart_wr_en)
);

always #5 clk=~clk;
always @(posedge clk) if (rst_n) begin
    if (req_vld && req_rdy) req_count=req_count+1;
    if (rsp_vld && rsp_rdy) rsp_count=rsp_count+1;
    if (itcm_we || dtcm_we || uart_we) target_write_count=target_write_count+1;
end

task automatic check;
    input condition;
    input [8*104-1:0] message;
    begin if (!condition) begin failures=failures+1; $display("FAIL: %0s", message); end end
endtask

task automatic request;
    input [31:0] addr;
    input load, write;
    begin
        @(negedge clk); req_addr=addr; req_load=load; req_write=write; req_vld=1;
        wait(req_rdy===1'b1);
        @(posedge clk); #1 req_vld=0;
    end
endtask

task automatic consume_response;
    begin
        @(negedge clk); rsp_rdy=1;
        @(posedge clk); #1 rsp_rdy=0;
    end
endtask

initial begin
    clk=0; rst_n=0; req_vld=0; req_load=0; req_write=0; rsp_rdy=0;
    req_addr=0; req_wdata=32'hcafe_babe; req_size=2'b10; req_mask=4'hf;
    failures=0; req_count=0; rsp_count=0; target_write_count=0;
    repeat(2) @(posedge clk); #1 rst_n=1;

    request(32'h1000_0010, 1'b0, 1'b1);
    check(rsp_vld && dtcm_en==0 && target_write_count==1,
          "DTCM store must create one write pulse and a held completion response");
    for(n=0;n<3;n=n+1) begin
        @(posedge clk); #1;
        check(rsp_vld && rsp_data==0 && !dtcm_we,
              "store response must hold without repeating the target write");
    end
    consume_response();

    request(32'hf000_0000, 1'b1, 1'b0);
    check(rsp_vld && rsp_data==0 && !itcm_en && !dtcm_en,
          "unmapped load must return one benign zero completion without target access");
    consume_response();

    request(32'h3000_0000, 1'b0, 1'b1);
    check(target_write_count==2 && uart_we==0,
          "UART store side effect must occur only on its request-fire cycle");
    consume_response();

    check(req_count==3 && rsp_count==3 && target_write_count==2,
          "bus scoreboard must match requests, responses and mapped store side effects");
    if(failures==0) $display("PASS: Phase0 bus completion and store exactly-once directed test");
    else $display("FAIL: Phase0 bus directed test, failures=%0d", failures);
    $finish;
end
endmodule
