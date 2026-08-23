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
    input wire [31:0] mem_addr_lsu,
    input wire [1:0] lsu_req_info_size_lsu
);

    // The assertions below intentionally report when a misaligned LSU access
    // occurs. They are debug breadcrumbs for finding the triggering instruction
    // and address, not a full correctness proof of the exception flow.
    //
    // Since the RTL now raises load/store address-misaligned exceptions, a
    // stricter future checker may also verify exception generation and write
    // suppression.
    wire lsu_check_known = !$isunknown({
        lsu_req_load_lsu,
        lsu_req_store_lsu,
        lsu_req_info_size_lsu,
        mem_addr_lsu
    });

    property p_word_misalign;
        @(posedge clk) disable iff (!rst_n || !lsu_check_known)
            !((lsu_req_load_lsu || lsu_req_store_lsu) &&
              (lsu_req_info_size_lsu == 2'b10) &&
              (mem_addr_lsu[1:0] != 2'b00));
    endproperty
    assert_word_misalign: assert property (p_word_misalign) else begin
        $display("[SVA Warning] LSU word misalign. PC: 0x%h, Addr: 0x%h",
                 $sampled(pc_exu), $sampled(mem_addr_lsu));
    end

    // Coverage companion: show whether tests exercised the same debug case.
    cover_word_misalign: cover property (
        @(posedge clk) disable iff (!rst_n || !lsu_check_known)
            (lsu_req_load_lsu || lsu_req_store_lsu) &&
            (lsu_req_info_size_lsu == 2'b10) &&
            (mem_addr_lsu[1:0] != 2'b00)
    );

    property p_halfword_misalign;
        @(posedge clk) disable iff (!rst_n || !lsu_check_known)
            !((lsu_req_load_lsu || lsu_req_store_lsu) &&
              (lsu_req_info_size_lsu == 2'b01) &&
              (mem_addr_lsu[0] != 1'b0));
    endproperty
    assert_halfword_misalign: assert property (p_halfword_misalign) else begin
        $display("[SVA Warning] LSU halfword misalign. PC: 0x%h, Addr: 0x%h",
                 $sampled(pc_exu), $sampled(mem_addr_lsu));
    end

    // Coverage companion: show whether tests exercised the same debug case.
    cover_halfword_misalign: cover property (
        @(posedge clk) disable iff (!rst_n || !lsu_check_known)
            (lsu_req_load_lsu || lsu_req_store_lsu) &&
            (lsu_req_info_size_lsu == 2'b01) &&
            (mem_addr_lsu[0] != 1'b0)
    );

endmodule
