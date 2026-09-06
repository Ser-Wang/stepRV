`timescale 1ns / 1ps
`include "config.v"

module tb_mau_variable_latency;
reg clk, rst_n;
reg ex_vld, wb_rdy, req_rdy, rsp_vld;
reg [31:0] addr, wr_data, wb_data, rsp_data;
reg wr_en, rd_wen;
reg [3:0] wr_mask, req_info;
reg [`RFIDX_WIDTH-1:0] rd_idx;
wire ex_rdy, wb_vld, req_vld, req_load, mem_wr_en, rsp_rdy;
wire [31:0] mem_addr, mem_wr_data, wb_result, fwd_result;
wire [1:0] mem_size;
wire [3:0] mem_wr_mask;
wire [`RFIDX_WIDTH-1:0] wb_rd_idx;
wire wb_rd_wen;
integer failures, req_count, rsp_count, wb_count, store_write_count;

mau u_mau (
    .clk(clk), .rst_n(rst_n), .i_ex_ma_vld(ex_vld), .o_ex_ma_rdy(ex_rdy),
    .o_ma_wb_vld(wb_vld), .i_ma_wb_rdy(wb_rdy),
    .i_mem_addr_exu(addr), .i_mem_wr_data_exu(wr_data),
    .i_mem_wr_en_exu(wr_en), .i_mem_wr_mask_exu(wr_mask),
    .i_mem_req_info_bus(req_info), .o_mem_req_vld(req_vld),
    .i_mem_req_rdy(req_rdy), .o_mem_addr(mem_addr),
    .o_mem_req_load(req_load), .o_mem_wr_en(mem_wr_en),
    .o_mem_size(mem_size), .o_mem_wr_mask(mem_wr_mask),
    .o_mem_wr_data(mem_wr_data), .i_mem_rsp_vld(rsp_vld),
    .o_mem_rsp_rdy(rsp_rdy), .i_mem_rsp_data(rsp_data),
    .i_wb_data_exu(wb_data), .i_wb_rd_idx_exu(rd_idx),
    .i_wb_rd_wen_exu(rd_wen), .o_wb_data_mau(wb_result),
    .o_fwd_data_mau(fwd_result), .o_wb_rd_idx_mau(wb_rd_idx),
    .o_wb_rd_wen_mau(wb_rd_wen)
);

always #5 clk = ~clk;
always @(posedge clk) if (rst_n) begin
    if (req_vld && req_rdy) begin
        req_count = req_count + 1;
        if (mem_wr_en) store_write_count = store_write_count + 1;
    end
    if (rsp_vld && rsp_rdy) rsp_count = rsp_count + 1;
    if (wb_vld && wb_rdy) wb_count = wb_count + 1;
end

task automatic check;
    input condition;
    input [8*112-1:0] message;
    begin if (!condition) begin failures = failures + 1; $display("FAIL: %0s", message); end end
endtask

task automatic issue;
    input is_load, is_store;
    input [31:0] in_addr, in_wr_data, in_wb_data;
    input [1:0] size;
    input is_unsigned;
    input [3:0] mask;
    input [`RFIDX_WIDTH-1:0] in_rd;
    begin
        @(negedge clk);
        addr = in_addr; wr_data = in_wr_data; wb_data = in_wb_data;
        wr_en = is_store; wr_mask = mask;
        req_info = {is_load, size, is_unsigned};
        rd_idx = in_rd; rd_wen = is_load || (!is_store && in_rd != 0);
        ex_vld = 1'b1;
        // A memory payload remains in the existing EX holding until the
        // request-ready task below permits its request fire. Non-memory input
        // can complete immediately through the ordinary EX/MA handshake.
        if (!is_load && !is_store) begin
            wait(ex_rdy === 1'b1);
            @(posedge clk);
            #1 ex_vld = 1'b0;
        end
    end
endtask

task automatic accept_request_after;
    input integer cycles;
    integer n;
    reg [31:0] held_addr, held_data;
    begin
        wait(req_vld === 1'b1);
        held_addr = mem_addr; held_data = mem_wr_data;
        for (n = 0; n < cycles; n = n + 1) begin
            @(posedge clk); #1;
            check(req_vld && mem_addr == held_addr && mem_wr_data == held_data,
                  "request valid/payload must remain stable under ready backpressure");
        end
        @(negedge clk); req_rdy = 1'b1;
        @(posedge clk); #1 begin req_rdy = 1'b0; ex_vld = 1'b0; end
        check(!req_vld && rsp_rdy, "one request fire must transition MAU to WAIT");
    end
endtask

task automatic return_response_after;
    input integer cycles;
    input [31:0] data;
    integer n;
    begin
        for (n = 0; n < cycles; n = n + 1) begin
            @(posedge clk); #1;
            check(!wb_vld && !req_vld, "WAIT must neither complete nor reissue before response");
        end
        @(negedge clk); rsp_data = data; rsp_vld = 1'b1;
        @(posedge clk); #1 rsp_vld = 1'b0;
        check(wb_vld, "response fire must produce exactly one held MA/WB result");
    end
endtask

task automatic consume_wb;
    input [31:0] expected;
    integer n;
    begin
        for (n = 0; n < 3; n = n + 1) begin
            @(posedge clk); #1;
            check(wb_vld && wb_result == expected && fwd_result == expected,
                  "DONE result and forwarding data must hold under WB backpressure");
        end
        @(negedge clk); wb_rdy = 1'b1;
        @(posedge clk); #1 wb_rdy = 1'b0;
    end
endtask

initial begin
    clk=0; rst_n=0; ex_vld=0; wb_rdy=0; req_rdy=0; rsp_vld=0;
    addr=0; wr_data=0; wb_data=0; rsp_data=0; wr_en=0; rd_wen=0;
    wr_mask=0; req_info=0; rd_idx=0;
    failures=0; req_count=0; rsp_count=0; wb_count=0; store_write_count=0;
    repeat (2) @(posedge clk); #1 rst_n=1;

    // Signed byte load, request stalled 3 cycles, response delayed 7 cycles.
    issue(1'b1, 1'b0, 32'h1000_0002, 0, 32'hdead_beef, 2'b00, 1'b0, 0, 5'd5);
    accept_request_after(3);
    return_response_after(7, 32'h0080_0000);
    check(wb_rd_wen && wb_rd_idx == 5'd5, "load completion must carry its captured rd metadata");
    consume_wb(32'hffff_ff80);

    // Store side effect is counted only on the unique request fire and still waits for completion.
    issue(1'b0, 1'b1, 32'h1000_0010, 32'h1234_5678, 0, 2'b10, 1'b0, 4'b1111, 0);
    accept_request_after(2);
    return_response_after(2, 32'h0);
    consume_wb(32'h0);

    // Unsigned half load checks response-aligned formatting in MA, not EX.
    issue(1'b1, 1'b0, 32'h1000_0022, 0, 0, 2'b01, 1'b1, 0, 5'd7);
    accept_request_after(1);
    return_response_after(1, 32'hbeef_1234);
    consume_wb(32'h0000_beef);

    // Non-memory EX/MA traffic still uses the existing MA/WB elastic holding
    // path and must not create a memory transaction.
    issue(1'b0, 1'b0, 32'h0, 32'h0, 32'h1357_9bdf,
          2'b00, 1'b0, 4'b0000, 5'd9);
    wait(wb_vld === 1'b1);
    check(wb_vld && wb_result == 32'h1357_9bdf,
          "non-memory result must pass through MAU without a memory request");
    check(wb_rd_wen && wb_rd_idx == 5'd9,
          "non-memory completion must preserve rd metadata");
    consume_wb(32'h1357_9bdf);

    check(req_count == 3 && rsp_count == 3 && wb_count == 4,
          "scoreboard requires exact memory transactions and all completions");
    check(store_write_count == 1, "store target side effect must occur exactly once");
    if (failures == 0)
        $display("PASS: Phase0 MAU variable-latency and exactly-once directed test");
    else
        $display("FAIL: Phase0 MAU directed test, failures=%0d", failures);
    $finish;
end
endmodule
