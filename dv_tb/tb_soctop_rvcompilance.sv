`timescale 1ns / 1ps

// `ifndef OUTPUT
// `define OUTPUT "signature.output"   // iverilog编译脚本compile_rtl.py会加上这个宏
// `endif

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
    $display("compliance test running...");

    wait(ex_end_flag == 32'h1);  // wait sim end

    fd = $fopen(`OUTPUT);   // OUTPUT的值在命令行里定义
    for (r = begin_signature; r < end_signature; r = r + 4) begin
        // // RISC-V compliance 验证的数据存放在 dmem 中
        // // 采用 %08x 防止前导0丢失导致与标准参考文件比对失败
        // $fdisplay(fd, "%08x", u_soc_top_v0.u_dmem.r_dtcm[r[31:2]]);
        // RISC-V compliance 验证的数据存放在低地址（如 0x2000）
        // 在该项目的内存映射中，低地址会被写入 ITCM
        $fdisplay(fd, "%08x", u_soc_top_v0.u_dmem.r_dtcm[r[31:2]]);
        // $fdisplay(fd, "%08x", u_soc_top_v0.u_imem.r_itcm[r[31:2]]);
    end
    $fclose(fd);
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

endmodule
