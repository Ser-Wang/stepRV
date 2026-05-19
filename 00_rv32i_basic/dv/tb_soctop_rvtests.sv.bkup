`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/01/14 09:05:32
// Design Name: 
// Module Name: tb_soctop_rvtests
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// `include "G:/myProjs/11_myRV/myProj_RV/ref_TinyRV/ref_TinyRV.srcs/sources_1/imports/core/defines.v"
// `include "../sources_1/defines/config.v"


module tb_soctop_rvtests(

    );

// Change this path to run different tests

parameter INST_DATA_PATH = "./inst.data";   // when using iverilog in ./sim dir
// parameter INST_DATA_PATH = "../../../../inst_fence_i.data";   // when using VIVADO, copy inst.data into {proj_name} dir.


// select one option only
`define TEST_PROG  1
//`define TEST_JTAG  1



reg clk;
reg rst_n;


////******** Instantiations ********////
soc_top_v0 u_soc_top_v0(
    .clk    (clk),
    .rst_n    (rst_n)
);


// wire[32-1:0] x3;
// wire[32-1:0] x26;
// wire[32-1:0] x27;
wire[32-1:0] x3 = u_soc_top_v0.u_core.u_regfile.r_regfile[3];
wire[32-1:0] x26 = u_soc_top_v0.u_core.u_regfile.r_regfile[26];
wire[32-1:0] x27 = u_soc_top_v0.u_core.u_regfile.r_regfile[27];

integer r;


////******** clk & rst ********////
always #10 clk = ~clk;     // 50MHz
initial begin
    clk = 0;
    rst_n = 0;  
    #40;
    rst_n = 1;
    #200;
end


////******** wait result ********////

initial begin
    $display("test running...");
`ifdef TEST_PROG
    wait(x26 == 32'b1)   // wait sim end, when x26 == 1
    #25    // wait for a period, so that x27 is written, otherwise x27 hasn't been written yet.
    if (x27 == 32'b1) begin
        $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~ #####     ##     ####    ####  ~~~~~~~~~");
        $display("~~~~~~~~~ #    #   #  #   #       #      ~~~~~~~~~");
        $display("~~~~~~~~~ #    #  #    #   ####    ####  ~~~~~~~~~");
        $display("~~~~~~~~~ #####   ######       #       # ~~~~~~~~~");
        $display("~~~~~~~~~ #       #    #  #    #  #    # ~~~~~~~~~");
        $display("~~~~~~~~~ #       #    #   ####    ####  ~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    end else begin
        $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("fail testnum = %2d", x3);
        // for (r = 0; r < 32; r = r + 1)
        //     $display("x%2d = 0x%x", r, u_soc_top_v0.u_core.u_regfile.r_regfile[r]);
    end
`endif

    $finish;

end



// read mem data
initial begin
    $readmemh (INST_DATA_PATH, u_soc_top_v0.u_imem.r_itcm);
    $readmemh (INST_DATA_PATH, u_soc_top_v0.u_dmem.r_dtcm);
end

// sim timeout
initial begin
    #500000
    $display("Time Out.");
    $finish;
end


//---- generate wave file, used by gtkwave
// initial begin
//     $dumpfile("tb_soc_top.vcd");
//     $dumpvars(0, tb_soc_top);
// end




`ifndef IVERILOG
bind soc_bus_v0 soc_bus_sva u_soc_bus_sva (
    .clk(u_soc_top_v0.clk),
    .rst_n(u_soc_top_v0.rst_n),
    .mau_req_load_mau(u_soc_top_v0.u_core.u_mau.mau_req_load),
    .sel_itcm_bus(sel_itcm),
    .mema_addr_bus(i_mema_addr)
);

bind exu_lsu exu_lsu_sva u_exu_lsu_sva (
    .clk(clk),
    .rst_n(rst_n),
    .lsu_req_load_lsu(lsu_req_load),
    .lsu_req_store_lsu(lsu_req_store),
    .mema_addr_lsu(mema_addr),
    .lsu_req_info_size_lsu(lsu_req_info_size)
);
`endif

endmodule
