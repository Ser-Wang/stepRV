`timescale 1ns / 1ps

module tb_dcache_final;

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

wire backing_req_vld, backing_req_rdy;
wire backing_rsp_vld, backing_rsp_rdy;
wire [31:0] backing_rsp_data;
reg backend_req_gate, backend_rsp_gate;

wire imem_en, imem_we;
wire [31:0] imem_addr, imem_wdata;
wire [3:0] imem_wmask;
reg [31:0] imem_rdata;
wire [31:0] uart_addr, uart_wdata;
wire uart_we;
reg [31:0] uart_rdata;

integer backend_req_count, backend_read_count, backend_write_count;
integer imem_access_count, uart_write_count, replacement_count;
integer i;
reg check_refill_sequence;
reg [31:0] expected_refill_addr;
reg dirty_sequence_active;
reg [31:0] dirty_victim_base, dirty_refill_base;
integer dirty_write_index, dirty_refill_index;
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

assign backing_req_vld = dmem_req_vld && backend_req_gate;
assign dmem_req_rdy = backing_req_rdy && backend_req_gate;
assign dmem_rsp_vld = backing_rsp_vld && backend_rsp_gate;
assign dmem_rsp_data = backing_rsp_data;
assign backing_rsp_rdy = dmem_rsp_rdy && backend_rsp_gate;

backing_dmem u_dmem (
    .clk(clk), .rst_n(rst_n), .i_req_vld(backing_req_vld),
    .o_req_rdy(backing_req_rdy), .i_req_addr(dmem_req_addr),
    .i_req_write(dmem_req_write), .i_req_wmask(dmem_req_wmask),
    .i_req_wdata(dmem_req_wdata), .o_rsp_vld(backing_rsp_vld),
    .i_rsp_rdy(backing_rsp_rdy), .o_rsp_data(backing_rsp_data)
);

function automatic [31:0] initial_dmem_word(input [31:0] addr);
    initial_dmem_word = 32'hd500_0000 ^ addr;
endfunction

localparam [31:0] ADDR_A = 32'h1000_000c;
localparam [31:0] ADDR_B = 32'h1000_100c;
localparam [31:0] ADDR_C = 32'h1000_200c;
localparam [31:0] ADDR_S = 32'h1000_002c;
localparam [31:0] ADDR_E = 32'h1000_102c;
localparam [31:0] ADDR_F = 32'h1000_202c;
localparam [31:0] ADDR_S_W4 = 32'h1000_0030;
localparam [31:0] ADDR_S_W5 = 32'h1000_0034;
localparam [31:0] ADDR_S_W6 = 32'h1000_0038;

function automatic [31:0] expected_s_word(input integer word_index);
    reg [31:0] word_addr;
    reg [31:0] value;
    begin
        word_addr = {ADDR_S[31:5], 5'b0} + (word_index * 4);
        value = initial_dmem_word(word_addr);
        case (word_index)
            3: value = 32'hface_cafe;
            4: value = {value[31:8], 8'haa};
            5: value = {16'hbeef, value[15:0]};
            6: value = 32'h1234_5678;
            default: value = value;
        endcase
        expected_s_word = value;
    end
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
            fail($sformatf("response expected %08x got %08x",
                           expected, cpu_rsp_data));
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
        else
            backend_read_count = backend_read_count + 1;

        if (dirty_sequence_active) begin
            if (dmem_req_write) begin
                if (dirty_refill_index != 0)
                    fail("dirty writeback appeared after refill started");
                if (dmem_req_addr !== dirty_victim_base + (dirty_write_index * 4))
                    fail($sformatf("writeback address index %0d got %08x",
                                   dirty_write_index, dmem_req_addr));
                if (dmem_req_wmask !== 4'b1111)
                    fail("dirty writeback did not use a full-word mask");
                if (dmem_req_wdata !== expected_s_word(dirty_write_index))
                    fail($sformatf("writeback data index %0d expected %08x got %08x",
                                   dirty_write_index,
                                   expected_s_word(dirty_write_index),
                                   dmem_req_wdata));
                dirty_write_index = dirty_write_index + 1;
            end else begin
                if (dirty_write_index != 8)
                    fail("refill started before all eight dirty words were written");
                if (dmem_req_addr !== dirty_refill_base + (dirty_refill_index * 4))
                    fail($sformatf("post-writeback refill index %0d got %08x",
                                   dirty_refill_index, dmem_req_addr));
                dirty_refill_index = dirty_refill_index + 1;
            end
        end else if (check_refill_sequence) begin
            if (dmem_req_write)
                fail("write observed during clean line refill");
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
    if (rst_n && cpu_rsp_vld && cpu_rsp_rdy
        && cpu_req_vld && cpu_req_rdy)
        replacement_count = replacement_count + 1;
end

always @(posedge clk) begin
    if (imem_en) begin
        if (imem_we) begin
            if (imem_wmask[0]) imem_model[imem_addr[7:2]][7:0]
                <= imem_wdata[7:0];
            if (imem_wmask[1]) imem_model[imem_addr[7:2]][15:8]
                <= imem_wdata[15:8];
            if (imem_wmask[2]) imem_model[imem_addr[7:2]][23:16]
                <= imem_wdata[23:16];
            if (imem_wmask[3]) imem_model[imem_addr[7:2]][31:24]
                <= imem_wdata[31:24];
        end else begin
            imem_rdata <= imem_model[imem_addr[7:2]];
        end
    end
end

integer count_before;
integer writes_before;
reg [31:0] held_data;
reg [31:0] held_backend_addr, held_backend_data;
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
    backend_req_gate = 1'b1;
    backend_rsp_gate = 1'b1;
    imem_rdata = 32'b0;
    uart_rdata = 32'h0000_0041;
    backend_req_count = 0;
    backend_read_count = 0;
    backend_write_count = 0;
    imem_access_count = 0;
    uart_write_count = 0;
    replacement_count = 0;
    check_refill_sequence = 1'b0;
    expected_refill_addr = 32'b0;
    dirty_sequence_active = 1'b0;
    dirty_victim_base = 32'b0;
    dirty_refill_base = 32'b0;
    dirty_write_index = 0;
    dirty_refill_index = 0;
    for (i = 0; i < 4096; i = i + 1)
        u_dmem.r_backing_dmem[i]
            = initial_dmem_word(32'h1000_0000 + (i * 4));
    for (i = 0; i < 64; i = i + 1)
        imem_model[i] = 32'he100_0000 ^ (i * 4);

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Two clean same-set lines occupy way0/way1; the third replaces rr way0.
    check_refill_sequence = 1'b1;
    expected_refill_addr = {ADDR_A[31:5], 5'b0};
    load_and_check(ADDR_A, initial_dmem_word(ADDR_A));
    check_refill_sequence = 1'b0;
    if (backend_read_count != 8 || backend_write_count != 0)
        fail("cold load refill count mismatch");

    load_and_check(ADDR_B, initial_dmem_word(ADDR_B));
    count_before = backend_req_count;
    load_and_check(ADDR_A, initial_dmem_word(ADDR_A));
    load_and_check(ADDR_B, initial_dmem_word(ADDR_B));
    if (backend_req_count != count_before)
        fail("two resident same-set D-Cache lines did not both hit");

    writes_before = backend_write_count;
    load_and_check(ADDR_C, initial_dmem_word(ADDR_C));
    if (backend_write_count != writes_before)
        fail("clean victim generated a writeback");
    count_before = backend_req_count;
    load_and_check(ADDR_B, initial_dmem_word(ADDR_B));
    if (backend_req_count != count_before)
        fail("clean round-robin replacement corrupted surviving way1");

    // Store miss must refill/allocate and remain private until dirty eviction.
    count_before = backend_req_count;
    store_and_complete(ADDR_S, 4'b1111, 32'hface_cafe);
    if (backend_req_count != count_before + 8
        || backend_write_count != writes_before)
        fail("store miss did not perform write-allocate without write-through");
    if (u_dmem.r_backing_dmem[ADDR_S[13:2]]
        !== initial_dmem_word(ADDR_S))
        fail("write-allocate store modified backing memory before eviction");
    load_and_check(ADDR_S, 32'hface_cafe);

    // Byte, halfword and word store hits only update the dirty resident line.
    count_before = backend_req_count;
    store_and_complete(ADDR_S_W4, 4'b0001, 32'h0000_00aa);
    load_and_check(ADDR_S_W4, expected_s_word(4));
    store_and_complete(ADDR_S_W5, 4'b1100, 32'hbeef_0000);
    load_and_check(ADDR_S_W5, expected_s_word(5));
    store_and_complete(ADDR_S_W6, 4'b1111, 32'h1234_5678);
    load_and_check(ADDR_S_W6, expected_s_word(6));
    if (backend_req_count != count_before)
        fail("store hit generated a write-through backend transaction");

    // Fill way1 clean, then a third tag must evict dirty way0 before refill.
    load_and_check(ADDR_E, initial_dmem_word(ADDR_E));
    count_before = backend_req_count;
    writes_before = backend_write_count;
    dirty_sequence_active = 1'b1;
    dirty_victim_base = {ADDR_S[31:5], 5'b0};
    dirty_refill_base = {ADDR_F[31:5], 5'b0};
    dirty_write_index = 0;
    dirty_refill_index = 0;
    backend_req_gate = 1'b0;
    send_request(ADDR_F, 1'b1, 1'b0, 4'b0, 32'b0);

    while (!dmem_req_vld) @(posedge clk);
    held_backend_addr = dmem_req_addr;
    held_backend_data = dmem_req_wdata;
    repeat (3) begin
        @(posedge clk);
        if (!dmem_req_vld || dmem_req_addr !== held_backend_addr
            || dmem_req_wdata !== held_backend_data)
            fail("writeback request changed under backend backpressure");
    end
    @(negedge clk);
    backend_req_gate = 1'b1;
    accept_response(initial_dmem_word(ADDR_F));
    dirty_sequence_active = 1'b0;

    if (dirty_write_index != 8 || dirty_refill_index != 8)
        fail("dirty eviction did not perform eight writes before eight reads");
    if (backend_write_count != writes_before + 8
        || backend_req_count != count_before + 16)
        fail("dirty eviction backend transaction counts mismatch");
    if (u_dmem.r_backing_dmem[ADDR_S[13:2]] !== expected_s_word(3)
        || u_dmem.r_backing_dmem[ADDR_S_W4[13:2]] !== expected_s_word(4)
        || u_dmem.r_backing_dmem[ADDR_S_W5[13:2]] !== expected_s_word(5)
        || u_dmem.r_backing_dmem[ADDR_S_W6[13:2]] !== expected_s_word(6))
        fail("dirty eviction did not preserve all merged store bytes");

    // Held CPU response and same-edge router response/request replacement.
    send_request(ADDR_F, 1'b1, 1'b0, 4'b0, 32'b0);
    while (!cpu_rsp_vld) @(posedge clk);
    held_data = cpu_rsp_data;
    repeat (3) begin
        @(posedge clk);
        if (!cpu_rsp_vld || cpu_rsp_data !== held_data)
            fail("CPU response changed under backpressure");
    end
    @(negedge clk);
    cpu_rsp_rdy = 1'b1;
    cpu_req_addr = ADDR_F + 4;
    cpu_req_load = 1'b1;
    cpu_req_write = 1'b0;
    cpu_req_vld = 1'b1;
    @(posedge clk);
    if (!(cpu_rsp_vld && cpu_req_rdy))
        fail("CPU response/request replacement did not fire");
    @(negedge clk);
    cpu_rsp_rdy = 1'b0;
    cpu_req_vld = 1'b0;
    accept_response(initial_dmem_word(ADDR_F + 4));
    if (replacement_count == 0)
        fail("CPU response/request replacement was not observed");

    // IMEM/UART bypass each time; unmapped accesses complete benignly.
    count_before = imem_access_count;
    load_and_check(32'h0000_0008, imem_model[2]);
    load_and_check(32'h0000_0008, imem_model[2]);
    if (imem_access_count != count_before + 2)
        fail("uncached IMEM did not bypass on every access");
    load_and_check(32'h3000_0000, 32'h0000_0041);
    store_and_complete(32'h3000_0000, 4'b1111, 32'h0000_0003);
    if (uart_write_count != 1)
        fail("UART store side effect was not exactly once");
    count_before = backend_req_count;
    load_and_check(32'hf000_0000, 32'b0);
    store_and_complete(32'hf000_0004, 4'b1111, 32'hdead_beef);
    if (backend_req_count != count_before)
        fail("unmapped access reached backing DMEM");

    $display("[PASS] Phase 3 final 2-way WB/WA D-Cache directed test");
    $finish;
end

initial begin
    #600000;
    $display("bus_active=%b dcache_state=%0d wb=%0d/%0d refill=%0d/%0d",
             u_bus.r_active, u_dcache.r_state,
             u_dcache.r_wb_req_count, u_dcache.r_wb_rsp_count,
             u_dcache.r_refill_req_count, u_dcache.r_refill_rsp_count);
    fail("timeout");
end

endmodule
