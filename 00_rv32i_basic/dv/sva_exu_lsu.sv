`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/18
// Design Name: StepRV_v0
// Module Name: sva_exu_lsu
// Description:
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------


module sva_exu_lsu (
    input wire clk,
    input wire rst_n,
    input wire [31:0] pc_exu,
    // From LSU (Load Store Unit)
    input wire lsu_req_load_lsu,
    input wire lsu_req_store_lsu,
    input wire [31:0] mema_addr_lsu,
    input wire [1:0] lsu_req_info_size_lsu
);

    // SystemVerilog Assertion: for any load/store request, low two bits must be 00 (Word alignment enforced for now)
    // property p_mema_addr_align;
    //     @(posedge clk) disable iff (!rst_n)
    //         ( (lsu_req_load_lsu || lsu_req_store_lsu) |-> (mema_addr_lsu[1:0] == 2'b00) );
    // endproperty

    // assert_mema_addr_align: assert property (p_mema_addr_align) else begin
    //     $display("[SVA Warning] mema_addr[1:0] is not 2'b00. Addr: 0x%h",  $sampled(mema_addr_lsu));
    //     // $fatal(1);
    // end

    // 1. Word alignment check: if size is Word (10), address must be 4-byte aligned
    property p_word_align;
        @(posedge clk) disable iff (!rst_n)
            ((lsu_req_load_lsu || lsu_req_store_lsu) && (mema_addr_lsu[1:0] != 2'b00)) |-> (lsu_req_info_size_lsu != 2'b10);
    endproperty
    cover_word_misalign: cover property (
        @(posedge clk) disable iff (!rst_n)
            (lsu_req_load_lsu || lsu_req_store_lsu) &&
            (lsu_req_info_size_lsu == 2'b10) &&
            (mema_addr_lsu[1:0] != 2'b00)
    );

    // 2. Halfword alignment check: if size is Halfword (01), address must be 2-byte aligned
    property p_halfword_align;
        @(posedge clk) disable iff (!rst_n)
            ((lsu_req_load_lsu || lsu_req_store_lsu) && (lsu_req_info_size_lsu == 2'b01)) |-> (mema_addr_lsu[0] == 1'b0);
    endproperty
    cover_halfword_misalign: cover property (
        @(posedge clk) disable iff (!rst_n)
            (lsu_req_load_lsu || lsu_req_store_lsu) &&
            (lsu_req_info_size_lsu == 2'b01) &&
            (mema_addr_lsu[0] != 1'b0)
    );

    // // 3. Mandatory Bit 0 Zero: any load/store address bit 0 must be 0
    // property p_addr_bit0_zero;
    //     @(posedge clk) disable iff (!rst_n)
    //         (lsu_req_load_lsu || lsu_req_store_lsu) |-> (mema_addr_lsu[0] == 1'b0);
    // endproperty
    // assert_addr_bit0_zero: assert property (p_addr_bit0_zero) else begin
    //     $display("[SVA Warning] mema_addr[0] happend to be 1'b1. Addr: 0x%h", $sampled(mema_addr_lsu));
    //     // $fatal(1);
    // end

endmodule
