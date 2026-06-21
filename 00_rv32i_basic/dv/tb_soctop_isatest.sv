`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/14
// Design Name: StepRV_v0
// Module Name: tb_soctop_isatest
// Description: Unified Testbench for both ISA tests and Compliance tests.
//              Use +define+RVTEST_ISA or +define+RVTEST_COMPLIANCE to select mode.
//--------------------------------------------------------------------------------
`include "config.v"

module tb_soctop_isatest();

// --- Configuration -------------------------------------------------------

// --- Mode Selection (For tools like Vivado, uncomment one to select mode) ---

`ifndef VCS
  `ifndef IVERILOG
    `define VIVADO_MANUAL 1
  `endif
`endif

// `if !defined(VCS) && !defined(IVERILOG)  // iverilog cannot use this
`ifdef VIVADO_MANUAL
`define RVTEST_ISA 1
// `define RVTEST_COMPLIANCE 1

    parameter INST_DATA_PATH = "d:/myProj_WJH/11_myRV/tests/programs/simple/simple.data";
    parameter DMEM_DATA_PATH = "d:/myProj_WJH/11_myRV/tests/programs/simple/simple.dmem.data";
    parameter TEST_NAME      = "I-ADD-01";
    // parameter INST_DATA_PATH = {"d:/myProj_WJH/11_myRV/tests/rv_compliance/rv32i/", TEST_NAME, ".data"};
    // parameter REF_FILE_PATH  = {"d:/myProj_WJH/11_myRV/tests/rv_compliance/rv32i/", TEST_NAME, ".ref"};
`else
    // ---- When using VCS or iverilog (Batch/Scripted Mode) ----
    parameter INST_DATA_PATH = "./inst.data";
    parameter DMEM_DATA_PATH = "./dmem.data";
    parameter REF_FILE_PATH  = "./out.ref";
`endif

parameter SIGNATURE_OUT  = "signature.output";



reg clk;
reg rst_n;

// =============================================================================
// ----------------        Shared Tasks          ----------------
// =============================================================================


task report_result;     // Unified result reporting task
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

// =============================================================================
// ----------------        Instantiations        ----------------
// =============================================================================
soc_top_v0 u_soc_top_v0(
    .clk    (clk),
    .rst_n  (rst_n)
);

// =============================================================================
// ----------------        Clock & Reset         ----------------
// =============================================================================
always #10 clk = ~clk;     // 50MHz

initial begin
    clk = 0;
    rst_n = 0;
    #40;
    rst_n = 1;
end

// =============================================================================
// ----------------        Test Execution Logic  ----------------
// =============================================================================

// --- Case A: ISA Tests ---
`ifdef RVTEST_ISA
wire [31:0] x3  = u_soc_top_v0.u_core.u_regfile.r_regfile[3];
wire [31:0] x26 = u_soc_top_v0.u_core.u_regfile.r_regfile[26];
wire [31:0] x27 = u_soc_top_v0.u_core.u_regfile.r_regfile[27];

initial begin
    $display("ISA Test: [riscv-tests] running...");
    wait(x26 == 32'h1);
    #25;
    if (x27 == 32'h1) begin
        report_result(1, "ISA");
    end else begin
        report_result(0, "ISA");
        $display("  Failed at test #%0d", x3);
    end
    $finish;
end
`endif

// --- Case B: Compliance Tests ---
`ifdef RVTEST_COMPLIANCE
reg [31:0] ex_end_flag     = 0;
reg [31:0] begin_signature = 0;
reg [31:0] end_signature   = 0;

wire [31:0] mema_addr    = u_soc_top_v0.u_core.o_mema_addr;
wire        mema_wren    = u_soc_top_v0.u_core.o_mema_wren;
wire [31:0] mema_wr_data = u_soc_top_v0.u_core.o_mema_wr_data;

function automatic [31:0] read_signature_word;
    input [31:0] addr;
    begin
        if ((addr >= `DTCM_BASE) && (addr < (`DTCM_BASE + `DTCM_SIZE)))
            read_signature_word = u_soc_top_v0.u_dmem.r_dtcm[(addr - `DTCM_BASE) >> 2];
        else if ((addr >= `ITCM_BASE) && (addr < (`ITCM_BASE + `ITCM_SIZE)))
            read_signature_word = u_soc_top_v0.u_imem.r_itcm[(addr - `ITCM_BASE) >> 2];
        else
            read_signature_word = 32'hxxxx_xxxx;
    end
endfunction

// Bus snoop: Capture compliance test control registers
always @(posedge clk) begin
    if (rst_n && mema_wren) begin
        if (mema_addr == 32'h10000008)      begin_signature <= mema_wr_data;
        else if (mema_addr == 32'h1000000c) end_signature   <= mema_wr_data;
        else if (mema_addr == 32'h10000010) ex_end_flag     <= mema_wr_data;
    end
end

integer r, fd;

initial begin
    $display("ISA Test: [riscv-compliance] running...");
    wait(ex_end_flag == 32'h1);

    // 1. Dump signature file (always, for debug)
    fd = $fopen(SIGNATURE_OUT);
    if (fd) begin
        for (r = begin_signature; r < end_signature; r = r + 4)
            $fdisplay(fd, "%08x", read_signature_word(r));
        $fclose(fd);
        $display("  Signature saved to %s", SIGNATURE_OUT);
    end

    // 2. Live comparison against reference file (VCS/Vivado)
`ifndef IVERILOG
    begin : live_comparison
        integer ref_fd, fail_count;
        reg [31:0] val_ref, val_out;

        fail_count = 0;
        ref_fd = $fopen(REF_FILE_PATH, "r");
        if (ref_fd == 0) begin
            $display("  !!! Error: Ref file not found: %s", REF_FILE_PATH);
        end else begin
            $display("  Comparing with reference: %s", REF_FILE_PATH);
            for (r = begin_signature; r < end_signature; r = r + 4) begin
                if ($fscanf(ref_fd, "%h", val_ref) != 1) begin
                    $display("  !!! Length Mismatch (Ref too short)");
                    fail_count = fail_count + 1;
                    break;
                end
                val_out = read_signature_word(r);
                if (val_out !== val_ref) begin
                    $display("  !!! MISMATCH [0x%h]: Expect=0x%h, Got=0x%h", r, val_ref, val_out);
                    fail_count = fail_count + 1;
                end
            end

            // Check if ref file has extra entries
            if (fail_count == 0 && $fscanf(ref_fd, "%h", val_ref) == 1) begin
                $display("  !!! Length Mismatch (Ref too long)");
                fail_count = fail_count + 1;
            end

            report_result(fail_count == 0, "COMPLIANCE");
            if (fail_count > 0)
                $display("  Total Mismatches: %0d", fail_count);
            $fclose(ref_fd);
        end
    end
`endif

    $finish;
end
`endif

// =============================================================================
// ----------------        Memory Loading        ----------------
// =============================================================================
initial begin
    $readmemh(INST_DATA_PATH, u_soc_top_v0.u_imem.r_itcm);
    $readmemh(DMEM_DATA_PATH, u_soc_top_v0.u_dmem.r_dtcm);
end

// =============================================================================
// ----------------        Waveform Dump          ----------------
// =============================================================================
`ifdef DUMP_FSDB
initial begin
    $fsdbDumpfile("tb_top.fsdb");
    $fsdbDumpvars(0, tb_soctop_isatest);
end
`endif

// Global Timeout
initial begin
    #1000000;
    $display("Simulation Time Out.");
    $finish;
end

// =============================================================================
// ----------------        SVA Bindings          ----------------
// =============================================================================
`ifndef IVERILOG
bind soc_bus_v0 sva_soc_bus u_sva_soc_bus (
    .clk(u_soc_top_v0.clk),
    .rst_n(u_soc_top_v0.rst_n),
    .mau_req_load_mau(u_soc_top_v0.u_core.u_mau.mau_req_load),
    .sel_itcm_bus(sel_itcm),
    .mema_addr_bus(i_mema_addr)
);

bind exu sva_exu_lsu u_sva_exu_lsu (
    .clk(clk),
    .rst_n(rst_n),
    .pc_exu(r_pc_exu),
    .lsu_req_load_lsu(u_exu_lsu.lsu_req_load),
    .lsu_req_store_lsu(u_exu_lsu.lsu_req_store),
    .mema_addr_lsu(u_exu_lsu.mema_addr),
    .lsu_req_info_size_lsu(u_exu_lsu.lsu_req_info_size)
);

bind exu sva_csr u_sva_csr (
    .clk(clk),
    .rst_n(rst_n),
    .i_csr_idx(o_csr_idx),
    .i_csr_wr_en(o_csr_wr_en),
    .o_csr_ill_exc(o_csr_ill_exc_exu),
    .req_disp_csr(req_disp_csr)
);
`endif

endmodule
