`timescale 1ns / 1ps

`ifndef OUTPUT
`define OUTPUT "signature.output"   // iverilog编译脚本compile_rtl.py会加上这个宏
`endif

module tb_soctop_rvcompilance(

    );

parameter INST_DATA_PATH = "./inst.data";

reg clk;
reg rst_n;

////******** Instantiations ********////
soc_top_v0 u_soc_top_v0(
    .clk    (clk),
    .rst_n    (rst_n)
);

wire[32-1:0] x3 = u_soc_top_v0.u_core.u_regfile.r_regfile[3];
wire[32-1:0] x26 = u_soc_top_v0.u_core.u_regfile.r_regfile[26];
wire[32-1:0] x27 = u_soc_top_v0.u_core.u_regfile.r_regfile[27];

// 在 my-RISCV-Projs 的架构中，数据存放在 dmem 中
// wire[31:0] ex_end_flag = u_soc_top_v0.u_dmem.r_dtcm[4];
// wire[31:0] begin_signature = u_soc_top_v0.u_dmem.r_dtcm[2];
// wire[31:0] end_signature = u_soc_top_v0.u_dmem.r_dtcm[3];

// 采用总线嗅探的方式捕获 compliance 测试特有的标志位地址
// 因为原测试程序会将 end_flag 写入 0x10000010，这个地址在当前 ITCM 深度（8192）之外会被丢弃
reg [31:0] ex_end_flag = 0;
reg [31:0] begin_signature = 0;
reg [31:0] end_signature = 0;

wire [31:0] mema_addr    = u_soc_top_v0.u_core.o_mema_addr;
wire        mema_wren    = u_soc_top_v0.u_core.o_mema_wren;
wire [31:0] mema_wr_data = u_soc_top_v0.u_core.o_mema_wr_data;

always @(posedge clk) begin
    if (rst_n && mema_wren) begin
        if (mema_addr == 32'h10000008)
            begin_signature <= mema_wr_data;
        else if (mema_addr == 32'h1000000c)
            end_signature <= mema_wr_data;
        else if (mema_addr == 32'h10000010)
            ex_end_flag <= mema_wr_data;
    end
end

integer r;
integer fd;

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
    integer ref_fd;
    reg [31:0] val_ref, val_out;
    integer fail_count;
    reg [8*256-1:0] ref_file_name;
    
    $display("compliance test running...");

    wait(ex_end_flag == 32'h1);  // wait sim end

    fd = $fopen(`OUTPUT);   // OUTPUT的值在命令行里定义
    for (r = begin_signature; r < end_signature; r = r + 4) begin
        // // RISC-V compliance 验证的数据存放在 dmem 中
        // // 采用 %08x 防止前导0丢失导致与标准参考文件比对失败
        // $fdisplay(fd, "%08x", u_soc_top_v0.u_dmem.r_dtcm[r[31:2]]);
        // RISC-V compliance 验证的数据存放在低地址（如 0x2000）
        // 在该项目的内存映射中，低地址会被写入 ITCM
        $fdisplay(fd, "%08x", u_soc_top_v0.u_imem.r_itcm[r[31:2]]);
    end
    $fclose(fd);

    // Result Comparison
    begin : comparison
        fail_count = 0;
        if ($value$plusargs("REF_FILE=%s", ref_file_name)) begin
            ref_fd = $fopen(ref_file_name, "r");
            if (ref_fd == 0) begin
                $display("No ref file found: %s", ref_file_name);
            end else begin
                $display("Comparing with reference file: %s", ref_file_name);
                for (r = begin_signature; r < end_signature; r = r + 4) begin
                    if ($fscanf(ref_fd, "%h", val_ref) != 1) begin
                        $display("!!! FAIL, size != (ref shorter) !!!");
                        fail_count = fail_count + 1;
                        break;
                    end
                    val_out = u_soc_top_v0.u_imem.r_itcm[r[31:2]];
                    if (val_out !== val_ref) begin
                        $display("!!! FAIL, content != at addr 0x%h, expect 0x%h, got 0x%h !!!", r, val_ref, val_out);
                        fail_count = fail_count + 1;
                    end
                end
                // Check if ref file has extra lines
                if (fail_count == 0 && $fscanf(ref_fd, "%h", val_ref) == 1) begin
                    $display("!!! FAIL, size != (ref longer) !!!");
                    fail_count = fail_count + 1;
                end
                
                if (fail_count == 0) begin
                    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                    $display("~~~~~~~~~~~ ### PASS ### ~~~~~~~~~~~~~~~~~~~~~~~~~");
                    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                end else begin
                    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                    $display("~~~~~~~~~~~ !!! FAIL !!! ~~~~~~~~~~~~~~~~~~~~~~~~~");
                    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
                end
                $fclose(ref_fd);
            end
        end else begin
            $display("No REF_FILE plusarg found, skipping comparison.");
        end
    end

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
//     $dumpfile("tb_soctop_rvcompilance.vcd");
//     $dumpvars(0, tb_soctop_rvcompilance);
// end


`ifdef SIMULATION
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
