`timescale 1ns / 1ps

module tb_dcache_basic;

reg clk, rst_n;
reg cpu_req_vld, cpu_req_load, cpu_req_write, cpu_rsp_rdy;
reg [31:0] cpu_req_addr, cpu_req_wdata;
reg [1:0] cpu_req_size;
reg [3:0] cpu_req_wmask;
wire cpu_req_rdy, cpu_rsp_vld;
wire [31:0] cpu_rsp_data;

wire dc_req_vld, dc_req_rdy, dc_req_load, dc_req_write;
wire [31:0] dc_req_addr, dc_req_wdata;
wire [3:0] dc_req_wmask;
wire dc_rsp_vld, dc_rsp_rdy;
wire [31:0] dc_rsp_data;

wire dmem_req_vld, dmem_req_rdy, dmem_req_write;
wire [31:0] dmem_req_addr, dmem_req_wdata;
wire [3:0] dmem_req_wmask;
wire dmem_rsp_vld, dmem_rsp_rdy;
wire [31:0] dmem_rsp_data;

wire imem_en, imem_we;
wire [31:0] imem_addr, imem_wdata;
wire [3:0] imem_wmask;
reg [31:0] imem_rdata;
wire [31:0] uart_addr, uart_wdata;
wire uart_we;
reg [31:0] uart_rdata;

integer backend_req_count, backend_write_count;
integer imem_access_count, uart_write_count, replacement_count;
integer i;
reg check_refill_sequence;
reg [31:0] expected_refill_addr;
reg [31:0] imem_model [0:63];

soc_bus u_bus (
    .clk(clk), .rst_n(rst_n),
    .i_mem_req_vld(cpu_req_vld), .o_mem_req_rdy(cpu_req_rdy),
    .i_mem_addr(cpu_req_addr), .i_mem_req_load(cpu_req_load),
    .i_mem_wr_en(cpu_req_write), .i_mem_size(cpu_req_size),
    .i_mem_wr_mask(cpu_req_wmask), .i_mem_wr_data(cpu_req_wdata),
    .o_mem_rsp_vld(cpu_rsp_vld), .i_mem_rsp_rdy(cpu_rsp_rdy),
    .o_mem_rd_data(cpu_rsp_data),
    .o_dcache_req_vld(dc_req_vld), .i_dcache_req_rdy(dc_req_rdy),
    .o_dcache_req_addr(dc_req_addr), .o_dcache_req_load(dc_req_load),
    .o_dcache_req_write(dc_req_write), .o_dcache_req_wmask(dc_req_wmask),
    .o_dcache_req_wdata(dc_req_wdata), .i_dcache_rsp_vld(dc_rsp_vld),
    .o_dcache_rsp_rdy(dc_rsp_rdy), .i_dcache_rsp_data(dc_rsp_data),
    .o_imem_p1_en(imem_en), .o_imem_p1_we(imem_we),
    .o_imem_p1_addr(imem_addr), .o_imem_p1_wmask(imem_wmask),
    .o_imem_p1_wdata(imem_wdata), .i_imem_p1_rdata(imem_rdata),
    .o_uart_addr(uart_addr), .o_uart_wr_en(uart_we),
    .o_uart_wr_data(uart_wdata), .i_uart_rd_data(uart_rdata)
);

dcache u_dcache (
    .clk(clk), .rst_n(rst_n),
    .i_cpu_req_vld(dc_req_vld), .o_cpu_req_rdy(dc_req_rdy),
    .i_cpu_req_addr(dc_req_addr), .i_cpu_req_load(dc_req_load),
    .i_cpu_req_write(dc_req_write), .i_cpu_req_wmask(dc_req_wmask),
    .i_cpu_req_wdata(dc_req_wdata), .o_cpu_rsp_vld(dc_rsp_vld),
    .i_cpu_rsp_rdy(dc_rsp_rdy), .o_cpu_rsp_data(dc_rsp_data),
    .o_mem_req_vld(dmem_req_vld), .i_mem_req_rdy(dmem_req_rdy),
    .o_mem_req_addr(dmem_req_addr), .o_mem_req_write(dmem_req_write),
    .o_mem_req_wmask(dmem_req_wmask), .o_mem_req_wdata(dmem_req_wdata),
    .i_mem_rsp_vld(dmem_rsp_vld), .o_mem_rsp_rdy(dmem_rsp_rdy),
    .i_mem_rsp_data(dmem_rsp_data)
);

backing_dmem u_dmem (
    .clk(clk), .rst_n(rst_n), .i_req_vld(dmem_req_vld),
    .o_req_rdy(dmem_req_rdy), .i_req_addr(dmem_req_addr),
    .i_req_write(dmem_req_write), .i_req_wmask(dmem_req_wmask),
    .i_req_wdata(dmem_req_wdata), .o_rsp_vld(dmem_rsp_vld),
    .i_rsp_rdy(dmem_rsp_rdy), .o_rsp_data(dmem_rsp_data)
);

function automatic [31:0] initial_dmem_word(input [31:0] addr);
    initial_dmem_word = 32'hd500_0000 ^ addr;
endfunction

task automatic fail(input string message);
    begin
        $display("[FAIL] %s", message);
        $finish;
    end
endtask

task automatic send_request(
    input [31:0] addr,
    input load,
    input write,
    input [3:0] wmask,
    input [31:0] wdata
);
    begin
        @(negedge clk);
        cpu_req_addr = addr;
        cpu_req_load = load;
        cpu_req_write = write;
        cpu_req_wmask = wmask;
        cpu_req_wdata = wdata;
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

task automatic load_and_check(input [31:0] addr, input [31:0] expected);
    begin
        send_request(addr, 1'b1, 1'b0, 4'b0000, 32'b0);
        accept_response(expected);
    end
endtask

task automatic store_and_complete(
    input [31:0] addr, input [3:0] mask, input [31:0] data
);
    begin
        send_request(addr, 1'b0, 1'b1, mask, data);
        accept_response(32'b0);
    end
endtask

always #5 clk = ~clk;

always @(posedge clk) begin
    if (rst_n && dmem_req_vld && dmem_req_rdy) begin
        backend_req_count = backend_req_count + 1;
        if (dmem_req_write)
            backend_write_count = backend_write_count + 1;
        if (check_refill_sequence) begin
            if (dmem_req_write)
                fail("write observed during line refill");
            if (dmem_req_addr !== expected_refill_addr)
                fail($sformatf("refill expected %08x got %08x",
                               expected_refill_addr, dmem_req_addr));
            expected_refill_addr = expected_refill_addr + 4;
        end
    end
    if (rst_n && imem_en)
        imem_access_count = imem_access_count + 1;
    if (rst_n && uart_we)
        uart_write_count = uart_write_count + 1;
    if (rst_n && cpu_rsp_vld && cpu_rsp_rdy && cpu_req_vld && cpu_req_rdy)
        replacement_count = replacement_count + 1;
end

always @(posedge clk) begin
    if (imem_en) begin
        if (imem_we) begin
            if (imem_wmask[0]) imem_model[imem_addr[7:2]][7:0] <= imem_wdata[7:0];
            if (imem_wmask[1]) imem_model[imem_addr[7:2]][15:8] <= imem_wdata[15:8];
            if (imem_wmask[2]) imem_model[imem_addr[7:2]][23:16] <= imem_wdata[23:16];
            if (imem_wmask[3]) imem_model[imem_addr[7:2]][31:24] <= imem_wdata[31:24];
        end else begin
            imem_rdata <= imem_model[imem_addr[7:2]];
        end
    end
end

integer count_before;
reg [31:0] held_data;
reg [31:0] word0;
initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cpu_req_vld = 1'b0;
    cpu_req_load = 1'b0;
    cpu_req_write = 1'b0;
    cpu_req_addr = 32'b0;
    cpu_req_size = 2'b10;
    cpu_req_wmask = 4'b0;
    cpu_req_wdata = 32'b0;
    cpu_rsp_rdy = 1'b0;
    imem_rdata = 32'b0;
    uart_rdata = 32'h0000_0041;
    backend_req_count = 0;
    backend_write_count = 0;
    imem_access_count = 0;
    uart_write_count = 0;
    replacement_count = 0;
    check_refill_sequence = 1'b0;
    expected_refill_addr = 32'b0;
    for (i = 0; i < 4096; i = i + 1)
        u_dmem.r_backing_dmem[i] = initial_dmem_word(32'h1000_0000 + (i * 4));
    for (i = 0; i < 64; i = i + 1)
        imem_model[i] = 32'he100_0000 ^ (i * 4);

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    check_refill_sequence = 1'b1;
    expected_refill_addr = 32'h1000_0000;
    load_and_check(32'h1000_000c, initial_dmem_word(32'h1000_000c));
    check_refill_sequence = 1'b0;
    if (backend_req_count != 8)
        fail("cold load did not perform exactly eight refill reads");

    count_before = backend_req_count;
    load_and_check(32'h1000_0014, initial_dmem_word(32'h1000_0014));
    if (backend_req_count != count_before)
        fail("warm load hit accessed backing DMEM");

    // Byte, halfword and word write-through hits with cache update.
    word0 = initial_dmem_word(32'h1000_0010);
    store_and_complete(32'h1000_0010, 4'b0001, 32'h0000_00aa);
    word0 = {word0[31:8], 8'haa};
    load_and_check(32'h1000_0010, word0);
    store_and_complete(32'h1000_0010, 4'b1100, 32'hbeef_0000);
    word0 = {16'hbeef, word0[15:0]};
    load_and_check(32'h1000_0010, word0);
    store_and_complete(32'h1000_0010, 4'b1111, 32'h1234_5678);
    word0 = 32'h1234_5678;
    load_and_check(32'h1000_0010, word0);
    if (backend_write_count != 3)
        fail("write-through hit count mismatch");

    // Conflict store miss must be NWA and preserve the resident line.
    count_before = backend_req_count;
    store_and_complete(32'h1000_100c, 4'b1111, 32'hface_cafe);
    if (backend_req_count != count_before + 1 || backend_write_count != 4)
        fail("store miss was not exactly one no-write-allocate backend write");
    load_and_check(32'h1000_0010, word0);
    if (backend_req_count != count_before + 1)
        fail("conflict store miss evicted the resident line");

    check_refill_sequence = 1'b1;
    expected_refill_addr = 32'h1000_1000;
    load_and_check(32'h1000_100c, 32'hface_cafe);
    check_refill_sequence = 1'b0;
    if (backend_req_count != count_before + 9)
        fail("load after NWA store did not refill exactly once");

    // Held response and same-edge response/request replacement.
    send_request(32'h1000_1008, 1'b1, 1'b0, 4'b0, 32'b0);
    while (!cpu_rsp_vld) @(posedge clk);
    held_data = cpu_rsp_data;
    repeat (3) begin
        @(posedge clk);
        if (!cpu_rsp_vld || cpu_rsp_data !== held_data)
            fail("CPU response changed under backpressure");
    end
    @(negedge clk);
    cpu_rsp_rdy = 1'b1;
    cpu_req_addr = 32'h1000_1004;
    cpu_req_load = 1'b1;
    cpu_req_write = 1'b0;
    cpu_req_vld = 1'b1;
    @(posedge clk);
    if (!(cpu_rsp_vld && cpu_req_rdy))
        fail("response/request replacement did not fire");
    @(negedge clk);
    cpu_rsp_rdy = 1'b0;
    cpu_req_vld = 1'b0;
    accept_response(initial_dmem_word(32'h1000_1004));
    if (replacement_count == 0)
        fail("replacement event was not counted");

    // IMEM and UART are always bypassed; unmapped accesses complete benignly.
    count_before = imem_access_count;
    load_and_check(32'h0000_0008, imem_model[2]);
    load_and_check(32'h0000_0008, imem_model[2]);
    if (imem_access_count != count_before + 2)
        fail("uncached IMEM loads did not bypass on every access");
    load_and_check(32'h3000_0000, 32'h0000_0041);
    store_and_complete(32'h3000_0000, 4'b1111, 32'h0000_0003);
    if (uart_write_count != 1)
        fail("UART store side effect was not exactly once");
    count_before = backend_req_count;
    load_and_check(32'hf000_0000, 32'b0);
    store_and_complete(32'hf000_0004, 4'b1111, 32'hdead_beef);
    if (backend_req_count != count_before)
        fail("unmapped access reached backing DMEM");

    $display("[PASS] Phase 2 basic D-Cache and bypass directed test");
    $finish;
end

initial begin
    #200000;
    $display("bus active=%b rsp=%b dcache state=%0d backend req=%0d rsp=%0d",
             u_bus.r_active, cpu_rsp_vld, u_dcache.r_state,
             u_dcache.r_refill_req_count, u_dcache.r_refill_rsp_count);
    fail("timeout");
end

endmodule
