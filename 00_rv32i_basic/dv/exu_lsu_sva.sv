`timescale 1ns / 1ps

module exu_lsu_sva (
    input wire clk,
    input wire rst_n,
    // From LSU (Load Store Unit)
    input wire lsu_req_load_lsu,
    input wire lsu_req_store_lsu,
    input wire [31:0] mema_addr_lsu,
    input wire [1:0] lsu_req_info_size_lsu
);

    // SystemVerilog Assertion: for any load/store request, low two bits must be 00 (Word alignment enforced for now)
    property p_mema_addr_align;
        @(posedge clk) disable iff (!rst_n)
            ( (lsu_req_load_lsu || lsu_req_store_lsu) |-> (mema_addr_lsu[1:0] == 2'b00) );
    endproperty

    assert_mema_addr_align: assert property (p_mema_addr_align) else begin
        $display("SVA ASSERTION FAILED: mema_addr[1:0] is not 2'b00. Addr: 0x%h",  $sampled(mema_addr_lsu));
        $fatal(1);
    end

    // 1. Word alignment check: if size is Word (10), address must be 4-byte aligned
    property p_word_align;
        @(posedge clk) disable iff (!rst_n)
            ((lsu_req_load_lsu || lsu_req_store_lsu) && (mema_addr_lsu[1:0] != 2'b00)) |-> (lsu_req_info_size_lsu != 2'b10);
    endproperty
    assert_word_align: assert property (p_word_align) else begin
        $display("SVA ASSERTION FAILED: Word access must be 4-byte aligned. Addr: 0x%h", $sampled(mema_addr_lsu));
        $fatal(1);
    end

    // 2. Halfword alignment check: if size is Halfword (01), address must be 2-byte aligned
    property p_halfword_align;
        @(posedge clk) disable iff (!rst_n)
            ((lsu_req_load_lsu || lsu_req_store_lsu) && (lsu_req_info_size_lsu == 2'b01)) |-> (mema_addr_lsu[0] == 1'b0);
    endproperty
    assert_halfword_align: assert property (p_halfword_align) else begin
        $display("SVA ASSERTION FAILED: Halfword access must be 2-byte aligned. Addr: 0x%h", $sampled(mema_addr_lsu));
        $fatal(1);
    end

    // 3. Mandatory Bit 0 Zero: any load/store address bit 0 must be 0
    property p_addr_bit0_zero;
        @(posedge clk) disable iff (!rst_n)
            (lsu_req_load_lsu || lsu_req_store_lsu) |-> (mema_addr_lsu[0] == 1'b0);
    endproperty
    assert_addr_bit0_zero: assert property (p_addr_bit0_zero) else begin
        $display("SVA ASSERTION FAILED: mema_addr[0] must be 0 for any load/store. Addr: 0x%h", $sampled(mema_addr_lsu));
        $fatal(1);
    end

endmodule
