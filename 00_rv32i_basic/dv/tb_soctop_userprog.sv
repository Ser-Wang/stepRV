`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/25
// Design Name: StepRV_v0
// Module Name: tb_soctop_userprog
// Description: Testbench for user-defined programs.
//--------------------------------------------------------------------------------

module tb_soctop_userprog();

// --- Configuration -------------------------------------------------------

// By default, enable the x26/x27 checking behavior
`define CHECK_X26_X27 1


// --- Mode Selection (For tools like Vivado, uncomment one to select mode) ---

`ifndef VCS
  `ifndef IVERILOG
    `define VIVADO_MANUAL 1
  `endif
`endif

`ifdef VIVADO_MANUAL

    parameter INST_DATA_PATH = "d:/myProj_WJH/11_myRV/tests/programs/simple/simple.data";
`else
    // ---- When using VCS or iverilog (Batch/Scripted Mode) ----
    parameter INST_DATA_PATH = "./inst.data";
`endif


reg clk;
reg rst_n;

// ---------------- Instantiations ----------------
soc_top_v0 u_soc_top_v0(
    .clk    (clk),
    .rst_n  (rst_n)
);

// ---------------- Memory Loading ----------------
initial begin
    $readmemh(INST_DATA_PATH, u_soc_top_v0.u_imem.r_itcm);
    // $readmemh(INST_DATA_PATH, u_soc_top_v0.u_dmem.r_dtcm);
end

// ---------------- Clock & Reset ----------------
always #10 clk = ~clk;     // 50MHz

initial begin
    clk = 0;
    rst_n = 0;
    #40;
    rst_n = 1;
end

// ---------------- Test Execution & Monitoring ----------------
initial begin
    $display("User Program Test running...");
    fork
        check_x26_x27();
        monitor_pc();
    join_none
end

// ---------------- Helper Tasks & Functions ----------------

// Unified result reporting task
task report_result;
    input        pass;
    input [8*32-1:0] mode_name;   // "ISA" or "COMPLIANCE"
    begin
        $display("\n*************************************************");
        if (pass)
            $display("****               %0s  [PASS]               ****", mode_name);
        else
            $display("****               %0s  [FAIL]               ****", mode_name);
        $display("*************************************************\n");
    end
endtask

// PC Address to Function Name Lookup Function
function automatic string get_func_name(input [31:0] pc);
`ifdef PROG_ADDR_MAP
    `include `PROG_ADDR_MAP
`elsif PROG_SIMPLE
    `include "simple_map.sv"
`else
    `include "uart_tx_map.sv"
`endif
endfunction

// PC Execution Monitor Task
task automatic monitor_pc();
    string current_func = "RESET";
    string prev_func = "RESET";
    string func_name;
    
    $display("[PC Monitor] Started monitoring EXU PC...");
    forever @(posedge clk) begin
        if (rst_n) begin
            func_name = get_func_name(u_soc_top_v0.u_core.u_exu.r_pc_exu);
            if (func_name != current_func) begin
                prev_func = current_func;
                current_func = func_name;
                $display("[PC Monitor] Time = %0t ns | PC = 32'h%08h | Function transition: %s -> %s", $time, u_soc_top_v0.u_core.u_exu.r_pc_exu, prev_func, current_func);
            end
        end
    end
endtask

// --- Wires for User Program x26/x27 ISA checking ---
`ifdef CHECK_X26_X27
wire [31:0] x3  = u_soc_top_v0.u_core.u_regfile.r_regfile[3];
wire [31:0] x26 = u_soc_top_v0.u_core.u_regfile.r_regfile[26];
wire [31:0] x27 = u_soc_top_v0.u_core.u_regfile.r_regfile[27];
`endif

// x26/x27 Result Checker Task
task automatic check_x26_x27();
`ifdef CHECK_X26_X27
    wait(x26 == 32'h1);
    #25;
    if (x27 == 32'h1) begin
        report_result(1, "USERPROG");
    end else begin
        report_result(0, "USERPROG");
        $display("  Failed at test #%0d", x3);
    end
    $finish;
`endif
endtask



// ---------------- Waveform Dump ----------------
`ifdef DUMP_FSDB
initial begin
    $fsdbDumpfile("tb_top.fsdb");
    $fsdbDumpvars(0, tb_soctop_userprog);
end
`endif

// Global Watchdog Timeout
initial begin
    #1000000;
    $display("Simulation Time Out.");
    $finish;
end

// ---------------- SVA Bindings ----------------
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

bind exu csr_sva u_csr_sva (
    .clk(clk),
    .rst_n(rst_n),
    .i_csr_idx(o_csr_idx),
    .i_csr_wr_en(o_csr_wr_en),
    .o_csr_ill_exc(o_csr_ill_exc_exu),
    .req_disp_csr(req_disp_csr)
);
`endif

endmodule
