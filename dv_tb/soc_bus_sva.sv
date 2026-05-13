`timescale 1ns / 1ps

module soc_bus_sva (
    input wire clk,
    input wire rst_n,
    // From MAU (Memory Access Unit)
    input wire mau_req_load_mau,
    // From BUS (soc_bus_v0)
    input wire sel_itcm_bus,
    input wire [31:0] mema_addr_bus
);

    // SVA: ITCM does not support Data Load (only Data Write for SMC)
    property p_no_itcm_load;
        @(posedge clk) disable iff (!rst_n)
        (mau_req_load_mau && sel_itcm_bus) |-> 1'b0;
    endproperty

    assert_no_itcm_load: assert property (p_no_itcm_load) else begin
        $display("\n[SVA ERROR] LSU Load from ITCM is NOT supported! Addr: 0x%h", $sampled(mema_addr_bus));
        $fatal;
    end

endmodule
