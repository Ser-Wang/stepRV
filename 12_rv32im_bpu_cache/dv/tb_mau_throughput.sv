`timescale 1ns / 1ps
`include "config.v"

module tb_mau_throughput;

localparam integer STREAM_LEN = 16;
localparam [31:0] BASE_ADDR = 32'h1000_0000;

reg         clk;
reg         rst_n;
reg         ex_vld;
wire        ex_rdy;
wire        wb_vld;
reg         wb_rdy;
reg  [31:0] addr;
reg  [31:0] wr_data;
reg         wr_en;
reg  [ 3:0] wr_mask;
reg  [ 3:0] req_info;
wire        req_vld;
wire        req_rdy;
wire [31:0] mem_addr;
wire        req_load;
wire        mem_wr_en;
wire [ 1:0] mem_size;
wire [ 3:0] mem_wr_mask;
wire [31:0] mem_wr_data;
reg         rsp_vld;
wire        rsp_rdy;
reg  [31:0] rsp_data;
reg  [31:0] wb_data;
reg  [`RFIDX_WIDTH-1:0] rd_idx;
reg         rd_wen;
wire [31:0] wb_result;
wire [31:0] fwd_result;
wire [`RFIDX_WIDTH-1:0] wb_rd_idx;
wire        wb_rd_wen;

integer cycle_count;
integer accepted_count;
integer req_count;
integer rsp_count;
integer wb_count;
integer replace_count;
integer completion_replace_count;
integer last_req_cycle;
integer last_rsp_cycle;
integer last_wb_cycle;
integer failures;

wire ex_fire = ex_vld & ex_rdy;
wire req_fire = req_vld & req_rdy;
wire rsp_fire = rsp_vld & rsp_rdy;
wire wb_fire = wb_vld & wb_rdy;

assign req_rdy = !rsp_vld | rsp_rdy;

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

task automatic check;
    input condition;
    input [8*112-1:0] message;
    begin
        if (!condition) begin
            failures = failures + 1;
            $display("FAIL: %0s", message);
        end
    end
endtask

// Model the existing EX-stage holding register: keep valid/payload stable until
// MAU accepts it, then present the next independent load on the next half-cycle.
always @(negedge clk) begin
    if (!rst_n) begin
        ex_vld = 1'b0;
        addr = BASE_ADDR;
        rd_idx = 1;
    end else if (accepted_count < STREAM_LEN) begin
        ex_vld = 1'b1;
        addr = BASE_ADDR + (accepted_count * 4);
        rd_idx = accepted_count + 1;
    end else begin
        ex_vld = 1'b0;
    end
end

// One-entry, one-cycle memory response slot with same-edge replacement.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rsp_vld <= 1'b0;
        rsp_data <= 32'b0;
    end else if (req_rdy) begin
        rsp_vld <= req_fire;
        if (req_fire)
            rsp_data <= 32'hcafe_0000 | ((mem_addr - BASE_ADDR) >> 2);
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_count = 0;
        accepted_count = 0;
        req_count = 0;
        rsp_count = 0;
        wb_count = 0;
        replace_count = 0;
        completion_replace_count = 0;
        last_req_cycle = -1;
        last_rsp_cycle = -1;
        last_wb_cycle = -1;
    end else begin
        cycle_count = cycle_count + 1;

        if (ex_fire)
            accepted_count = accepted_count + 1;

        if (req_fire) begin
            check(mem_addr == BASE_ADDR + (req_count * 4),
                  "LSU request address sequence mismatch");
            check(req_load && !mem_wr_en && mem_size == 2'b10,
                  "LSU throughput stream must issue word loads");
            if (req_count > 0)
                check(cycle_count - last_req_cycle == 1,
                      "steady-state LSU request interval must be one cycle");
            last_req_cycle = cycle_count;
            req_count = req_count + 1;
        end

        if (rsp_fire) begin
            if (rsp_count > 0)
                check(cycle_count - last_rsp_cycle == 1,
                      "steady-state LSU response interval must be one cycle");
            last_rsp_cycle = cycle_count;
            rsp_count = rsp_count + 1;
        end

        if (wb_fire) begin
            check(wb_result == (32'hcafe_0000 | wb_count),
                  "MA/WB result sequence mismatch");
            check(wb_rd_wen && wb_rd_idx == wb_count + 1,
                  "MA/WB rd metadata sequence mismatch");
            if (wb_count > 0)
                check(cycle_count - last_wb_cycle == 1,
                      "steady-state MA/WB completion interval must be one cycle");
            last_wb_cycle = cycle_count;
            wb_count = wb_count + 1;
        end

        if (rsp_fire && req_fire)
            replace_count = replace_count + 1;
        if (rsp_fire && wb_fire)
            completion_replace_count = completion_replace_count + 1;
    end
end

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    ex_vld = 1'b0;
    wb_rdy = 1'b1;
    addr = BASE_ADDR;
    wr_data = 32'b0;
    wr_en = 1'b0;
    wr_mask = 4'b0000;
    req_info = {1'b1, 2'b10, 1'b0};
    wb_data = 32'b0;
    rd_idx = 1;
    rd_wen = 1'b1;
    failures = 0;

    repeat (2) @(posedge clk);
    #1 rst_n = 1'b1;

    repeat (64) begin
        @(posedge clk);
        if (wb_count >= STREAM_LEN)
            break;
    end
    #1;

    check(accepted_count == STREAM_LEN,
          "EX/MA must transfer exactly sixteen operations");
    check(req_count == STREAM_LEN,
          "LSU stream must issue exactly sixteen requests");
    check(rsp_count == STREAM_LEN,
          "LSU stream must accept exactly sixteen responses");
    check(wb_count == STREAM_LEN,
          "LSU stream must complete exactly sixteen operations");
    check(replace_count >= STREAM_LEN-1,
          "LSU must replace response with next request every cycle");
    check(completion_replace_count >= STREAM_LEN-1,
          "MA/WB completion slot must pop and push every cycle");
    check(u_mau.outstanding_r inside {1'b0, 1'b1},
          "LSU unanswered depth must remain one-bit bounded");

    if (failures == 0)
        $display("PASS: Phase0 S2 MAU sixteen-entry one-cycle throughput test");
    else
        $display("FAIL: Phase0 S2 MAU throughput test, failures=%0d", failures);
    $finish;
end

endmodule
