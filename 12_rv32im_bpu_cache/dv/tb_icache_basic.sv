`timescale 1ns / 1ps

module tb_icache_basic;

reg         clk;
reg         rst_n;
reg         cpu_req_vld;
wire        cpu_req_rdy;
reg  [31:0] cpu_req_addr;
wire        cpu_rsp_vld;
reg         cpu_rsp_rdy;
wire [31:0] cpu_rsp_data;
wire        mem_req_vld;
reg         mem_req_rdy;
wire [31:0] mem_req_addr;
reg         mem_rsp_vld;
wire        mem_rsp_rdy;
reg  [31:0] mem_rsp_data;

integer backend_req_count;
integer replacement_count;
reg [31:0] expected_refill_addr;
reg        check_refill_sequence;

icache u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .i_cpu_req_vld  (cpu_req_vld),
    .o_cpu_req_rdy  (cpu_req_rdy),
    .i_cpu_req_addr (cpu_req_addr),
    .o_cpu_rsp_vld  (cpu_rsp_vld),
    .i_cpu_rsp_rdy  (cpu_rsp_rdy),
    .o_cpu_rsp_data (cpu_rsp_data),
    .o_mem_req_vld  (mem_req_vld),
    .i_mem_req_rdy  (mem_req_rdy),
    .o_mem_req_addr (mem_req_addr),
    .i_mem_rsp_vld  (mem_rsp_vld),
    .o_mem_rsp_rdy  (mem_rsp_rdy),
    .i_mem_rsp_data (mem_rsp_data)
);

function automatic [31:0] memory_word(input [31:0] addr);
    memory_word = 32'ha500_0000 ^ addr;
endfunction

task automatic fail(input string message);
    begin
        $display("[FAIL] %s", message);
        $finish;
    end
endtask

task automatic send_request(input [31:0] addr);
    begin
        @(negedge clk);
        cpu_req_addr = addr;
        cpu_req_vld = 1'b1;
        do @(posedge clk); while (!cpu_req_rdy);
        @(negedge clk);
        cpu_req_vld = 1'b0;
    end
endtask

task automatic accept_response(input [31:0] expected);
    begin
        @(negedge clk);
        cpu_rsp_rdy = 1'b1;
        do @(posedge clk); while (!cpu_rsp_vld);
        if (cpu_rsp_data !== expected)
            fail($sformatf("response expected %08x got %08x", expected, cpu_rsp_data));
        @(negedge clk);
        cpu_rsp_rdy = 1'b0;
    end
endtask

// One-entry synchronous backing-memory response model.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_rsp_vld <= 1'b0;
        mem_rsp_data <= 32'b0;
    end else if (!mem_rsp_vld || mem_rsp_rdy) begin
        mem_rsp_vld <= mem_req_vld && mem_req_rdy;
        if (mem_req_vld && mem_req_rdy)
            mem_rsp_data <= memory_word(mem_req_addr);
    end
end

always @(posedge clk) begin
    if (rst_n && mem_req_vld && mem_req_rdy) begin
        backend_req_count = backend_req_count + 1;
        if (check_refill_sequence) begin
            if (mem_req_addr !== expected_refill_addr)
                fail($sformatf("refill address expected %08x got %08x",
                               expected_refill_addr, mem_req_addr));
            expected_refill_addr = expected_refill_addr + 4;
        end
    end
    if (rst_n && cpu_rsp_vld && cpu_rsp_rdy && cpu_req_vld && cpu_req_rdy)
        replacement_count = replacement_count + 1;
end

always #5 clk = ~clk;

integer count_before;
reg [31:0] held_data;
initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cpu_req_vld = 1'b0;
    cpu_req_addr = 32'b0;
    cpu_rsp_rdy = 1'b0;
    mem_req_rdy = 1'b1;
    backend_req_count = 0;
    replacement_count = 0;
    expected_refill_addr = 32'b0;
    check_refill_sequence = 1'b0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Cold miss: exactly eight ordered word requests, requested word returned.
    check_refill_sequence = 1'b1;
    expected_refill_addr = 32'h0000_0000;
    send_request(32'h0000_000c);
    accept_response(memory_word(32'h0000_000c));
    check_refill_sequence = 1'b0;
    if (backend_req_count != 8)
        fail($sformatf("cold refill request count expected 8 got %0d", backend_req_count));

    // Warm hit must not touch the backend.
    count_before = backend_req_count;
    send_request(32'h0000_0014);
    accept_response(memory_word(32'h0000_0014));
    if (backend_req_count != count_before)
        fail("warm hit accessed backend");

    // Response payload remains stable while the CPU applies backpressure.
    send_request(32'h0000_0010);
    while (!cpu_rsp_vld) @(posedge clk);
    held_data = cpu_rsp_data;
    repeat (3) begin
        @(posedge clk);
        if (!cpu_rsp_vld || cpu_rsp_data !== held_data)
            fail("response changed under backpressure");
    end
    @(negedge clk);
    cpu_rsp_rdy = 1'b1;
    @(posedge clk);
    @(negedge clk);
    cpu_rsp_rdy = 1'b0;

    // Warm response A and request B replace one another on the same edge.
    send_request(32'h0000_0000);
    while (!cpu_rsp_vld) @(posedge clk);
    @(negedge clk);
    cpu_req_addr = 32'h0000_0004;
    cpu_req_vld = 1'b1;
    cpu_rsp_rdy = 1'b1;
    @(posedge clk);
    if (!(cpu_req_rdy && cpu_rsp_vld))
        fail("warm response/request replacement did not fire");
    @(negedge clk);
    cpu_req_vld = 1'b0;
    cpu_rsp_rdy = 1'b0;
    accept_response(memory_word(32'h0000_0004));
    if (replacement_count == 0)
        fail("replacement event was not observed");

    // Same index, different tag: refill and install the conflicting line.
    count_before = backend_req_count;
    check_refill_sequence = 1'b1;
    expected_refill_addr = 32'h0000_1000;
    send_request(32'h0000_100c);
    accept_response(memory_word(32'h0000_100c));
    check_refill_sequence = 1'b0;
    if (backend_req_count != count_before + 8)
        fail("conflict miss did not perform one whole-line refill");

    count_before = backend_req_count;
    send_request(32'h0000_1018);
    accept_response(memory_word(32'h0000_1018));
    if (backend_req_count != count_before)
        fail("replacement line was not installed as a warm hit");

    $display("[PASS] Phase 1 basic I-Cache directed test");
    $finish;
end

initial begin
    #100000;
    $display("state=%0d req=%0d rsp=%0d cpu_req=%b/%b cpu_rsp=%b/%b mem=%b/%b rsp=%b/%b",
             u_dut.r_state, u_dut.r_refill_req_count, u_dut.r_refill_rsp_count,
             cpu_req_vld, cpu_req_rdy, cpu_rsp_vld, cpu_rsp_rdy,
             mem_req_vld, mem_req_rdy, mem_rsp_vld, mem_rsp_rdy);
    fail("timeout");
end

endmodule
