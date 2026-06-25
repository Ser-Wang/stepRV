`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/18
// Design Name: StepRV_v0
// Module Name: sva_soc_bus
// Description:
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//--------------------------------------------------------------------------------


module sva_soc_bus (
    input wire clk,
    input wire rst_n,
    // From EXU LSU request
    input wire mem_req_load_exu,
    // From BUS (soc_bus_v0)
    input wire sel_itcm_bus,
    input wire [31:0] mem_addr_bus
);

    // SVA: ITCM does not support Data Load (only Data Write for SMC)
    property p_no_itcm_load;
        @(posedge clk) disable iff (!rst_n)
        (mem_req_load_exu && sel_itcm_bus) |-> 1'b0;
    endproperty

    assert_no_itcm_load: assert property (p_no_itcm_load) else begin
        $display("\n[SVA Warning] Detected load from ITCM. Addr: 0x%h", $sampled(mem_addr_bus));
        // $fatal
    end

endmodule
