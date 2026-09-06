`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/25
// Design Name: StepRV_v0
// Module Name: tb_soctop_userprog_wrapped
// Description: Testbench for user-defined programs.
//--------------------------------------------------------------------------------

module tb_soctop_userprog_wrapped();

// --- Configuration -------------------------------------------------------


// --- Mode Selection (For tools like Vivado, uncomment one to select mode) ---

// `ifndef VCS
//   `ifndef IVERILOG
//     `define VIVADO_MANUAL 1
//   `endif
// `endif

// `ifdef VIVADO_MANUAL

//     parameter INST_DATA_PATH = "d:/myProj_WJH/11_myRV/tests/programs/simple/simple.data";
// `else
//     // ---- When using VCS or iverilog (Batch/Scripted Mode) ----
//     parameter INST_DATA_PATH = "./inst.data";
// `endif


reg clk;
reg rst_n;
wire uart_tx;
reg uart_rx;

// Buffer for UART TX Monitor
string uart_buffer = "";

// Hierarchical alias for probes that still need to look inside the wrapped SoC.
// Keep this local to the testbench so the wrapper instance name remains explicit.
`define DUT_SOC u_wrapper_soc_top.u_soc_top

// ---------------- Instantiations ----------------
wrapper_soc_top u_wrapper_soc_top(
    .clk       (clk),
    .rst_n     (rst_n),
    .o_uart_tx (uart_tx),
    .i_uart_rx (uart_rx)
);

// ---------------- Memory Loading ----------------
initial begin
    // $readmemh(INST_DATA_PATH, `DUT_SOC.u_imem.r_itcm);
    
    // $readmemh(INST_DATA_PATH, `DUT_SOC.u_dmem.r_dtcm);
end

// ---------------- Clock & Reset ----------------
always #10 clk = ~clk;     // 50MHz

initial begin
    clk = 0;
    rst_n = 0;
    uart_rx = 1'b1;
    #40;
    rst_n = 1;
end

// ---------------- Test Execution & Monitoring ----------------
initial begin
    $display("User Program Test running...");
    fork
        uart_tx_monitor();
    join_none
end

// ---------------- Helper Tasks & Functions ----------------

task automatic print_uart_buffer();
    if (uart_buffer != "") begin
        $display("\n--- UART TX Buffered Output ---");
        $display("%s", uart_buffer);
        $display("-------------------------------\n");
    end
endtask


// UART TX monitor. Decodes 8-N-1 output and prints received characters.
task automatic uart_tx_monitor();
    integer baud_cycle_cnt;
    integer bit_period_ns;
    integer i;
    reg [7:0] rx_char;
    begin
        @(posedge rst_n);
        repeat (2) @(posedge clk);
        $display("[UART TX Monitor] Started monitoring UART TX output...");

        forever begin
            @(negedge uart_tx);
            baud_cycle_cnt = `DUT_SOC.u_uart.uart_baud[15:0];
            bit_period_ns = 20 * (baud_cycle_cnt + 1);

            #(bit_period_ns + (bit_period_ns / 2));
            rx_char = 8'h00;

            for (i = 0; i < 8; i = i + 1) begin
                rx_char[i] = uart_tx;
                #(bit_period_ns);
            end

            $write("%c", rx_char);
            uart_buffer = $sformatf("%s%c", uart_buffer, rx_char);
        end
    end
endtask




// ---------------- Waveform Dump ----------------
`ifdef DUMP_FSDB
initial begin
    $fsdbDumpfile("tb_top.fsdb");
    $fsdbDumpvars(0, tb_soctop_userprog_wrapped);
end
`endif

`ifdef IVERILOG
initial begin
    $dumpfile("tb_soc_top.vcd");
    $dumpvars(0, tb_soctop_userprog_wrapped);
end
`endif

// Global Watchdog Timeout
initial begin
    #1000000;   // 1ms, for "hello world" is just enough.
    $display("\nSimulation Time Out.");
    print_uart_buffer();
    $finish;
end

// ---------------- SVA Bindings ----------------
`ifndef IVERILOG
`ifdef VCS
bind soc_bus sva_soc_bus u_sva_soc_bus (
    .clk(`DUT_SOC.clk),
    .rst_n(`DUT_SOC.rst_n),
    .mem_req_vld(i_mem_req_vld),
    .mem_req_rdy(o_mem_req_rdy),
    .mem_req_write(i_mem_wr_en),
    .mem_req_addr(i_mem_addr),
    .itcm_write(o_itcm_p1_we),
    .dtcm_write(o_dtcm_wr_en),
    .uart_write(o_uart_wr_en)
);

bind exu sva_exu_lsu u_sva_exu_lsu (
    .clk(clk),
    .rst_n(rst_n),
    .pc_exu(r_pc_exu),
    .lsu_req_load_lsu(u_exu_lsu.lsu_req_load),
    .lsu_req_store_lsu(u_exu_lsu.lsu_req_store),
    .mem_addr_lsu(u_exu_lsu.mem_addr),
    .lsu_req_info_size_lsu(u_exu_lsu.lsu_req_info_size)
);

bind exu sva_csr u_sva_csr (
    .clk(clk),
    .rst_n(rst_n),
    .i_csr_idx(o_csr_idx),
    .i_csr_wr_req(o_csr_wr_req),
    .csr_illegal_access_raw(i_csr_illegal_access_raw),
    .req_disp_csr(req_disp_csr)
);
`endif
`endif

`undef DUT_SOC

endmodule
