`timescale 1ns / 1ps

module tb_icache_final;

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

integer cycle_count;
integer last_req_cycle;
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
            fail($sformatf("response expected %08x got %08x",
                           expected, cpu_rsp_data));
        if (cycle_count <= last_req_cycle)
            fail("synchronous lookup responded in the request acceptance cycle");
        @(negedge clk);
        cpu_rsp_rdy = 1'b0;
    end
endtask

task automatic fetch_and_check(input [31:0] addr);
    begin
        send_request(addr);
        accept_response(memory_word(addr));
    end
endtask

always #5 clk = ~clk;

// One-entry synchronous backing response with response/request replacement.
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
    if (!rst_n) begin
        cycle_count = 0;
        last_req_cycle = -1;
    end else begin
        cycle_count = cycle_count + 1;
        if (cpu_req_vld && cpu_req_rdy)
            last_req_cycle = cycle_count;
    end

    if (rst_n && mem_req_vld && mem_req_rdy) begin
        backend_req_count = backend_req_count + 1;
        if (check_refill_sequence) begin
            if (mem_req_addr !== expected_refill_addr)
                fail($sformatf("refill expected %08x got %08x",
                               expected_refill_addr, mem_req_addr));
            expected_refill_addr = expected_refill_addr + 4;
        end
    end

    if (rst_n && cpu_rsp_vld && cpu_rsp_rdy
        && cpu_req_vld && cpu_req_rdy)
        replacement_count = replacement_count + 1;
end

localparam [31:0] ADDR_A = 32'h0000_006c;
localparam [31:0] ADDR_B = 32'h0000_106c;
localparam [31:0] ADDR_C = 32'h0000_206c;
localparam [31:0] ADDR_D = 32'h0000_00a4;

integer count_before;
reg [31:0] held_data;
initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cpu_req_vld = 1'b0;
    cpu_req_addr = 32'b0;
    cpu_rsp_rdy = 1'b0;
    mem_req_rdy = 1'b1;
    mem_rsp_vld = 1'b0;
    mem_rsp_data = 32'b0;
    cycle_count = 0;
    last_req_cycle = -1;
    backend_req_count = 0;
    replacement_count = 0;
    expected_refill_addr = 32'b0;
    check_refill_sequence = 1'b0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Empty set chooses way0 and performs one ordered whole-line refill.
    check_refill_sequence = 1'b1;
    expected_refill_addr = {ADDR_A[31:5], 5'b0};
    fetch_and_check(ADDR_A);
    check_refill_sequence = 1'b0;
    if (backend_req_count != 8)
        fail("first line did not perform exactly eight refill reads");
    if (!u_dut.r_valid_way0[ADDR_A[11:5]]
        || u_dut.r_valid_way1[ADDR_A[11:5]])
        fail("empty set did not install its first line in way0");

    // The second same-set tag must use invalid way1 and coexist with A.
    count_before = backend_req_count;
    fetch_and_check(ADDR_B);
    if (backend_req_count != count_before + 8)
        fail("second same-set line did not refill once");
    if (!u_dut.r_valid_way0[ADDR_A[11:5]]
        || !u_dut.r_valid_way1[ADDR_A[11:5]])
        fail("two same-set lines did not occupy both ways");

    count_before = backend_req_count;
    fetch_and_check(ADDR_A);
    fetch_and_check(ADDR_B);
    if (backend_req_count != count_before)
        fail("two resident same-set lines did not both hit");
    if (u_dut.r_rr[ADDR_A[11:5]] !== 1'b0)
        fail("cache hit changed round-robin state");

    // Third tag uses rr=0, replacing A while B survives.
    fetch_and_check(ADDR_C);
    count_before = backend_req_count;
    fetch_and_check(ADDR_C);
    fetch_and_check(ADDR_B);
    if (backend_req_count != count_before)
        fail("round-robin victim selection corrupted the surviving way");

    // A was the selected victim and must miss again.
    count_before = backend_req_count;
    fetch_and_check(ADDR_A);
    if (backend_req_count != count_before + 8)
        fail("round-robin victim unexpectedly remained resident");

    // A different set is independent.
    fetch_and_check(ADDR_D);
    count_before = backend_req_count;
    fetch_and_check(ADDR_D);
    if (backend_req_count != count_before)
        fail("different-set line was not retained");

    // A hit response must remain stable under CPU backpressure.
    send_request(ADDR_D);
    while (!cpu_rsp_vld) @(posedge clk);
    held_data = cpu_rsp_data;
    repeat (3) begin
        @(posedge clk);
        if (!cpu_rsp_vld || cpu_rsp_data !== held_data)
            fail("response changed under CPU backpressure");
    end
    @(negedge clk);
    cpu_rsp_rdy = 1'b1;
    @(posedge clk);
    @(negedge clk);
    cpu_rsp_rdy = 1'b0;

    // Warm response A and request B replace one another on the same edge.
    send_request(ADDR_D);
    while (!cpu_rsp_vld) @(posedge clk);
    @(negedge clk);
    cpu_req_addr = ADDR_D + 4;
    cpu_req_vld = 1'b1;
    cpu_rsp_rdy = 1'b1;
    @(posedge clk);
    if (!(cpu_rsp_vld && cpu_req_rdy))
        fail("response/request replacement did not fire");
    @(negedge clk);
    cpu_req_vld = 1'b0;
    cpu_rsp_rdy = 1'b0;
    accept_response(memory_word(ADDR_D + 4));
    if (replacement_count == 0)
        fail("response/request replacement was not observed");

    $display("[PASS] Phase 3 final 2-way I-Cache directed test");
    $finish;
end

initial begin
    #300000;
    $display("state=%0d refill_req=%0d refill_rsp=%0d install=%0d",
             u_dut.r_state, u_dut.r_refill_req_count,
             u_dut.r_refill_rsp_count, u_dut.r_install_count);
    fail("timeout");
end

endmodule
