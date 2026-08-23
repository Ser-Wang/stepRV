`timescale 1ns / 1ps
//--------------------------------------------------------------------------------
// Engineer: Wang Jianghao
// Create Date: 2026/05/25
// Design Name: StepRV_v0
// Module Name: tb_soctop_userprog
// Description: Testbench for user-defined programs.
//--------------------------------------------------------------------------------
`include "config.v"

module tb_soctop_userprog();

// --- Configuration -------------------------------------------------------


`define ENABLE_SVA 1    // Comment out this macro for faster simulation.

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
wire uart_tx;
reg uart_rx;

// Buffer for UART TX Monitor
string uart_buffer = "";
string uart_line_buffer = "";

// ---------------- CoreMark Branch-Prediction Statistics ----------------
// coremark_10 defaults. Runtime plusargs may override these values.
localparam [31:0] COREMARK_STATS_START_PC_DEFAULT = 32'h0000_08fc;
localparam [31:0] COREMARK_STATS_STOP_PC_DEFAULT  = 32'h0000_4638;

localparam [1:0] COREMARK_STAGE_WAIT_START  = 2'd0;
localparam [1:0] COREMARK_STAGE_BENCHMARK   = 2'd1;
localparam [1:0] COREMARK_STAGE_WAIT_RESULT = 2'd2;

reg        bpu_stats_enable;
reg [31:0] bpu_stats_start_pc;
reg [31:0] bpu_stats_stop_pc;
reg [1:0]  coremark_stage;
reg        bpu_stats_done;

longint unsigned coremark_stage_cycles;
longint unsigned coremark_heartbeat_cycles;
longint unsigned coremark_start_timeout_cycles;
longint unsigned coremark_run_timeout_cycles;
longint unsigned coremark_result_timeout_cycles;
longint unsigned coremark_heartbeat_countdown;
longint unsigned coremark_last_heartbeat_committed;

longint unsigned normal_total;
longint unsigned normal_correct;
longint unsigned control_total;
longint unsigned control_correct;
longint unsigned cond_total;
longint unsigned cond_correct;
longint unsigned cond_taken_total;
longint unsigned cond_taken_correct;
longint unsigned cond_not_taken_total;
longint unsigned cond_not_taken_correct;
longint unsigned jal_total;
longint unsigned jal_correct;
longint unsigned jalr_return_total;
longint unsigned jalr_return_correct;
longint unsigned jalr_other_total;
longint unsigned jalr_other_correct;
longint unsigned prediction_recovery_count;
longint unsigned non_control_wrong_count;
longint unsigned stats_consistency_errors;

event coremark_result_event;
reg    coremark_result_pass;
reg    coremark_terminal_seen;
reg    coremark_duration_warning_seen;
reg    coremark_functional_error_seen;
string coremark_terminal_line = "";

// Keep all implementation-specific hierarchy references in one place.
wire        stats_ex_commit_fire          = u_soc_top.u_core.u_exu.ex_commit_fire;
wire        stats_exc_req                 = u_soc_top.u_core.u_exu.o_exc_req;
wire        stats_trap_ret_req            = u_soc_top.u_core.u_exu.o_trap_ret_req;
wire        stats_bru_fence_i             = u_soc_top.u_core.u_exu.bru_fence_i;
wire        stats_bru_is_control          = u_soc_top.u_core.u_exu.bru_is_control;
wire        stats_bru_is_cond             = u_soc_top.u_core.u_exu.bru_is_cond;
wire        stats_bru_taken               = u_soc_top.u_core.u_exu.bru_taken;
wire        stats_ras_is_jal              = u_soc_top.u_core.u_exu.ras_is_jal;
wire        stats_ras_is_jalr             = u_soc_top.u_core.u_exu.ras_is_jalr;
wire        stats_ras_resolve_pop_raw     = u_soc_top.u_core.u_exu.ras_resolve_pop_raw;
wire [31:0] stats_pc_ex                   = u_soc_top.u_core.u_exu.r_pc_exu;
wire [31:0] stats_pred_next_pc_ex         = u_soc_top.u_core.u_exu.r_pred_next_pc_ex;
wire [31:0] stats_actual_next_pc          = u_soc_top.u_core.u_exu.actual_next_pc;
wire        stats_prediction_recovery_req = u_soc_top.u_core.u_exu.prediction_recovery_req;

wire stats_normal_resolve_event = stats_ex_commit_fire
                                && !stats_exc_req
                                && !stats_trap_ret_req
                                && !stats_bru_fence_i;
wire stats_control_resolve_event = stats_normal_resolve_event
                                 && stats_bru_is_control;
wire stats_next_pc_correct = (stats_pred_next_pc_ex == stats_actual_next_pc);
wire stats_next_pc_wrong = !stats_next_pc_correct;

wire stats_class_cond = stats_bru_is_cond;
wire stats_class_jal = stats_ras_is_jal;
wire stats_class_jalr_return = stats_ras_is_jalr
                             && stats_ras_resolve_pop_raw;
wire stats_class_jalr_other = stats_ras_is_jalr
                            && !stats_ras_resolve_pop_raw;
wire [2:0] stats_control_class_count = {2'b0, stats_class_cond}
                                     + {2'b0, stats_class_jal}
                                     + {2'b0, stats_class_jalr_return}
                                     + {2'b0, stats_class_jalr_other};
wire stats_recovery_consistency_error = stats_normal_resolve_event
                                      && (stats_prediction_recovery_req
                                          !== stats_next_pc_wrong);
wire stats_classification_error = stats_control_resolve_event
                                && (stats_control_class_count != 1);
wire [1:0] stats_event_error_count = {1'b0, stats_recovery_consistency_error}
                                   + {1'b0, stats_classification_error};

// ---------------- Instantiations ----------------
soc_top u_soc_top(
    .clk       (clk),
    .rst_n     (rst_n),
    .o_uart_tx (uart_tx),
    .i_uart_rx (uart_rx)
);

// ---------------- Memory Loading ----------------
task automatic load_inst_mem(input string data_path);
`ifdef USE_SRAM_MACRO
    $display("[Memory Load] ITCM SRAM macro <= %s", data_path);
    $readmemh(data_path, u_soc_top.u_imem.u_itcm_sram_wrapper.u_smic55_8192x32_2p.mem_array);
`else
    $display("[Memory Load] ITCM RTL memory <= %s", data_path);
    $readmemh(data_path, u_soc_top.u_imem.r_itcm);
`endif
endtask

initial begin
    #1;
    load_inst_mem(INST_DATA_PATH);
    
    // $readmemh(INST_DATA_PATH, u_soc_top.u_dmem.r_dtcm);
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

// coremark_10 is enabled automatically by the simulation Makefile. The same
// monitor can be enabled manually for another image with +BPU_STATS and both
// PC plusargs.
initial begin : configure_bpu_stats
    integer start_pc_override;
    integer stop_pc_override;
    integer heartbeat_override;
    integer start_timeout_override;
    integer run_timeout_override;
    integer result_timeout_override;
    integer manual_enable;

    bpu_stats_enable = 1'b0;
    bpu_stats_start_pc = COREMARK_STATS_START_PC_DEFAULT;
    bpu_stats_stop_pc = COREMARK_STATS_STOP_PC_DEFAULT;
    coremark_heartbeat_cycles = 64'd1_000_000;
    coremark_start_timeout_cycles = 64'd5_000_000;
    coremark_run_timeout_cycles = 64'd20_000_000;
    coremark_result_timeout_cycles = 64'd10_000_000;
    coremark_terminal_seen = 1'b0;
    coremark_result_pass = 1'b0;
    coremark_duration_warning_seen = 1'b0;
    coremark_functional_error_seen = 1'b0;

`ifdef PROG_COREMARK_10
    bpu_stats_enable = 1'b1;
`endif

    manual_enable = $test$plusargs("BPU_STATS");
    if (manual_enable != 0)
        bpu_stats_enable = 1'b1;

    start_pc_override = $value$plusargs("BPU_STATS_START_PC=%h",
                                        bpu_stats_start_pc);
    stop_pc_override = $value$plusargs("BPU_STATS_STOP_PC=%h",
                                       bpu_stats_stop_pc);
    heartbeat_override = $value$plusargs("BPU_STATS_HEARTBEAT_CYCLES=%d",
                                          coremark_heartbeat_cycles);
    start_timeout_override = $value$plusargs("BPU_STATS_START_TIMEOUT_CYCLES=%d",
                                              coremark_start_timeout_cycles);
    run_timeout_override = $value$plusargs("BPU_STATS_RUN_TIMEOUT_CYCLES=%d",
                                            coremark_run_timeout_cycles);
    result_timeout_override = $value$plusargs("BPU_STATS_RESULT_TIMEOUT_CYCLES=%d",
                                               coremark_result_timeout_cycles);

`ifndef PROG_COREMARK_10
    if ((manual_enable != 0)
        && ((start_pc_override == 0) || (stop_pc_override == 0))) begin
        $fatal(1,
               "[COREMARK ERROR] +BPU_STATS requires both START_PC and STOP_PC for a non-coremark_10 image");
    end
`endif

    if (bpu_stats_enable
        && ((coremark_heartbeat_cycles == 0)
            || (coremark_start_timeout_cycles == 0)
            || (coremark_run_timeout_cycles == 0)
            || (coremark_result_timeout_cycles == 0))) begin
        $fatal(1, "[COREMARK ERROR] heartbeat and timeout cycle values must be non-zero");
    end

    if (bpu_stats_enable) begin
        $display("[COREMARK STAGE] ARMED start_pc=%08h stop_pc=%08h heartbeat_cycles=%0d",
                 bpu_stats_start_pc, bpu_stats_stop_pc,
                 coremark_heartbeat_cycles);
    end
end

// ---------------- Test Execution & Monitoring ----------------
initial begin
    $display("User Program Test running...");
    fork
        // check_x26_x27();
        // monitor_pc();
        uart_tx_monitor();
        print_sim_time(1_000_000);
    join_none
end

// ---------------- Helper Tasks & Functions ----------------

// Print simulation time at the caller-specified interval.
task automatic print_sim_time(input time interval);
    forever begin
        #(interval);
        $display("\n[Simulation Progress] Current simulation time: %0d ms",
                 $time / 1_000_000);
    end
endtask

task automatic print_uart_buffer();
    if (uart_buffer != "") begin
        $display("\n--- UART TX Buffered Output ---");
        $display("%s", uart_buffer);
        $display("-------------------------------\n");
    end
endtask

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

function automatic bit string_contains(input string text, input string pattern);
    integer i;
    begin
        string_contains = 1'b0;
        if ((pattern.len() != 0) && (text.len() >= pattern.len())) begin
            for (i = 0; i <= (text.len() - pattern.len()); i = i + 1) begin
                if (text.substr(i, i + pattern.len() - 1) == pattern)
                    string_contains = 1'b1;
            end
        end
    end
endfunction

task automatic process_coremark_uart_line(input string line);
    begin
        if (bpu_stats_enable && !coremark_terminal_seen) begin
            if (string_contains(line, "Correct operation validated.")) begin
                coremark_terminal_seen = 1'b1;
                coremark_result_pass = 1'b1;
                coremark_terminal_line = line;
                -> coremark_result_event;
            end
            else if (string_contains(
                         line,
                         "ERROR! Must execute for at least 10 secs")) begin
                // coremark_10 deliberately trades official run duration for
                // fast RTL bring-up. This warning alone is not a CRC failure.
                coremark_duration_warning_seen = 1'b1;
                $display("\n[COREMARK WARNING] expected short-run duration warning observed");
            end
            else if (string_contains(line, "Cannot validate operation")
                     || string_contains(line, "ERROR")) begin
                coremark_functional_error_seen = 1'b1;
                coremark_terminal_seen = 1'b1;
                coremark_result_pass = 1'b0;
                coremark_terminal_line = line;
                -> coremark_result_event;
            end
            else if (string_contains(line, "Errors detected")) begin
                coremark_terminal_seen = 1'b1;
                coremark_result_pass = coremark_duration_warning_seen
                                     && !coremark_functional_error_seen;
                coremark_terminal_line = line;
                -> coremark_result_event;
            end
        end
    end
endtask

task automatic print_bpu_metric(
    input string metric_name,
    input longint unsigned metric_total,
    input longint unsigned metric_correct
);
    longint unsigned metric_wrong;
    real metric_accuracy;
    begin
        metric_wrong = metric_total - metric_correct;
        if (metric_total == 0) begin
            $display("[BPU STATS] %s total=0 correct=0 wrong=0 accuracy=N/A",
                     metric_name);
        end
        else begin
            metric_accuracy = (100.0 * metric_correct) / metric_total;
            $display("[BPU STATS] %s total=%0d correct=%0d wrong=%0d accuracy=%0.2f%%",
                     metric_name, metric_total, metric_correct, metric_wrong,
                     metric_accuracy);
        end
    end
endtask

task automatic report_branch_prediction_stats();
    longint unsigned normal_wrong;
    longint unsigned control_wrong;
    longint unsigned report_errors;
    real normal_accuracy;
    real mispredict_mpki;
    begin
        normal_wrong = normal_total - normal_correct;
        control_wrong = control_total - control_correct;
        report_errors = stats_consistency_errors;

        if (normal_wrong != prediction_recovery_count)
            report_errors = report_errors + 1;
        if (normal_wrong != (control_wrong + non_control_wrong_count))
            report_errors = report_errors + 1;
        if (control_total != (cond_total + jal_total
                              + jalr_return_total + jalr_other_total))
            report_errors = report_errors + 1;

        if (report_errors == 0)
            $display("[BPU STATS] status=VALID start_pc=%08h stop_pc=%08h",
                     bpu_stats_start_pc, bpu_stats_stop_pc);
        else
            $display("[BPU STATS] status=INVALID start_pc=%08h stop_pc=%08h",
                     bpu_stats_start_pc, bpu_stats_stop_pc);

        $display("[BPU STATS] config BPU_ENABLE=%0d BPU_RAS_ENABLE=%0d",
                 `BPU_ENABLE, `BPU_RAS_ENABLE);

        if (normal_total == 0) begin
            $display("[BPU STATS] NORMAL total=0 correct=0 wrong=0 accuracy=N/A mpki=N/A");
        end
        else begin
            normal_accuracy = (100.0 * normal_correct) / normal_total;
            mispredict_mpki = (1000.0 * normal_wrong) / normal_total;
            $display("[BPU STATS] NORMAL total=%0d correct=%0d wrong=%0d accuracy=%0.2f%% mpki=%0.3f",
                     normal_total, normal_correct, normal_wrong,
                     normal_accuracy, mispredict_mpki);
        end

        print_bpu_metric("CONTROL", control_total, control_correct);
        print_bpu_metric("COND", cond_total, cond_correct);
        print_bpu_metric("COND_TAKEN", cond_taken_total,
                         cond_taken_correct);
        print_bpu_metric("COND_NOT_TAKEN", cond_not_taken_total,
                         cond_not_taken_correct);
        print_bpu_metric("JAL", jal_total, jal_correct);
        print_bpu_metric("JALR_RETURN", jalr_return_total,
                         jalr_return_correct);
        print_bpu_metric("JALR_OTHER", jalr_other_total,
                         jalr_other_correct);
        $display("[BPU STATS] RECOVERY total=%0d non_control_wrong=%0d consistency_errors=%0d",
                 prediction_recovery_count, non_control_wrong_count,
                 report_errors);

        if (report_errors != 0)
            $fatal(1, "[COREMARK ERROR] branch-prediction statistics consistency failure");
    end
endtask

// CoreMark terminal status arrives after the benchmark statistics have already
// been frozen at stop_time. Finish here to avoid the startup assembly's loop.
initial begin : handle_coremark_result
    forever begin
        @coremark_result_event;
        if (coremark_result_pass) begin
            if (!bpu_stats_done)
                $fatal(1, "[COREMARK ERROR] UART PASS arrived before BENCHMARK_DONE");
            if (coremark_duration_warning_seen)
                $display("\n[COREMARK RESULT] PASS_BRINGUP: CRC checks passed; official duration requirement intentionally not met");
            else
                $display("\n[COREMARK RESULT] PASS: %s", coremark_terminal_line);
            report_result(1'b1, "COREMARK");
            $finish;
        end
        else begin
            $display("\n[COREMARK RESULT] FAIL: %s", coremark_terminal_line);
            report_result(1'b0, "COREMARK");
            $finish;
        end
    end
end

// PC Address to Function Name Lookup Function
function automatic string get_func_name(input [31:0] pc);
`ifdef PROG_ADDR_MAP
    `include `PROG_ADDR_MAP
`elsif PROG_SIMPLE
    `include "simple_map.sv"
`else
    // `include "uart_tx_map.sv"
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
            func_name = get_func_name(u_soc_top.u_core.u_exu.r_pc_exu);
            if (func_name != current_func) begin
                prev_func = current_func;
                current_func = func_name;
                $display("[PC Monitor] Time = %0t ns | PC = 32'h%08h | Function transition: %s -> %s", $time, u_soc_top.u_core.u_exu.r_pc_exu, prev_func, current_func);
            end
        end
    end
endtask

// Count only committed EX payloads inside the CoreMark benchmark window.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coremark_stage <= COREMARK_STAGE_WAIT_START;
        bpu_stats_done <= 1'b0;
        coremark_stage_cycles <= 0;
        coremark_heartbeat_countdown <= 0;
        coremark_last_heartbeat_committed <= 0;
        normal_total <= 0;
        normal_correct <= 0;
        control_total <= 0;
        control_correct <= 0;
        cond_total <= 0;
        cond_correct <= 0;
        cond_taken_total <= 0;
        cond_taken_correct <= 0;
        cond_not_taken_total <= 0;
        cond_not_taken_correct <= 0;
        jal_total <= 0;
        jal_correct <= 0;
        jalr_return_total <= 0;
        jalr_return_correct <= 0;
        jalr_other_total <= 0;
        jalr_other_correct <= 0;
        prediction_recovery_count <= 0;
        non_control_wrong_count <= 0;
        stats_consistency_errors <= 0;
    end
    else if (bpu_stats_enable) begin
        case (coremark_stage)
            COREMARK_STAGE_WAIT_START: begin
                if (stats_ex_commit_fire
                    && (stats_pc_ex == bpu_stats_start_pc)) begin
                    coremark_stage <= COREMARK_STAGE_BENCHMARK;
                    coremark_stage_cycles <= 0;
                    coremark_heartbeat_countdown <= coremark_heartbeat_cycles;
                    coremark_last_heartbeat_committed <= normal_total;
                    $display("[COREMARK STAGE] BENCHMARK_START time=%0t pc=%08h",
                             $time, stats_pc_ex);
                end
                else begin
                    coremark_stage_cycles <= coremark_stage_cycles + 1;
                    if (coremark_stage_cycles
                        >= (coremark_start_timeout_cycles - 1)) begin
                        $fatal(1,
                               "[COREMARK ERROR] start timeout pc=%08h committed=%0d",
                               stats_pc_ex, normal_total);
                    end
                end
            end

            COREMARK_STAGE_BENCHMARK: begin
                if (stats_ex_commit_fire
                    && (stats_pc_ex == bpu_stats_stop_pc)) begin
                    coremark_stage <= COREMARK_STAGE_WAIT_RESULT;
                    coremark_stage_cycles <= 0;
                    bpu_stats_done <= 1'b1;
                    $display("[COREMARK STAGE] BENCHMARK_DONE time=%0t pc=%08h",
                             $time, stats_pc_ex);
                    report_branch_prediction_stats();
                end
                else begin
                    coremark_stage_cycles <= coremark_stage_cycles + 1;

                    if (stats_normal_resolve_event) begin
                        normal_total <= normal_total + 1;
                        if (stats_next_pc_correct)
                            normal_correct <= normal_correct + 1;
                        if (stats_prediction_recovery_req)
                            prediction_recovery_count
                                <= prediction_recovery_count + 1;

                        if (stats_event_error_count != 0)
                            stats_consistency_errors
                                <= stats_consistency_errors
                                   + stats_event_error_count;

                        if (stats_recovery_consistency_error) begin
                            if (stats_consistency_errors == 0) begin
                                $display("[COREMARK ERROR] recovery mismatch pc=%08h predicted=%08h actual=%08h recovery=%0b",
                                         stats_pc_ex, stats_pred_next_pc_ex,
                                         stats_actual_next_pc,
                                         stats_prediction_recovery_req);
                            end
                        end

                        if (stats_control_resolve_event) begin
                            control_total <= control_total + 1;
                            if (stats_next_pc_correct)
                                control_correct <= control_correct + 1;

                            if (stats_classification_error) begin
                                if (stats_consistency_errors == 0)
                                    $display("[COREMARK ERROR] control classification mismatch pc=%08h class_count=%0d",
                                             stats_pc_ex,
                                             stats_control_class_count);
                            end

                            if (stats_class_cond) begin
                                cond_total <= cond_total + 1;
                                if (stats_next_pc_correct)
                                    cond_correct <= cond_correct + 1;
                                if (stats_bru_taken) begin
                                    cond_taken_total <= cond_taken_total + 1;
                                    if (stats_next_pc_correct)
                                        cond_taken_correct
                                            <= cond_taken_correct + 1;
                                end
                                else begin
                                    cond_not_taken_total
                                        <= cond_not_taken_total + 1;
                                    if (stats_next_pc_correct)
                                        cond_not_taken_correct
                                            <= cond_not_taken_correct + 1;
                                end
                            end
                            else if (stats_class_jal) begin
                                jal_total <= jal_total + 1;
                                if (stats_next_pc_correct)
                                    jal_correct <= jal_correct + 1;
                            end
                            else if (stats_class_jalr_return) begin
                                jalr_return_total <= jalr_return_total + 1;
                                if (stats_next_pc_correct)
                                    jalr_return_correct
                                        <= jalr_return_correct + 1;
                            end
                            else if (stats_class_jalr_other) begin
                                jalr_other_total <= jalr_other_total + 1;
                                if (stats_next_pc_correct)
                                    jalr_other_correct
                                        <= jalr_other_correct + 1;
                            end
                        end
                        else if (stats_next_pc_wrong) begin
                            non_control_wrong_count
                                <= non_control_wrong_count + 1;
                        end
                    end

                    if (coremark_heartbeat_countdown <= 1) begin
                        $display("[COREMARK HEARTBEAT] cycles=%0d pc=%08h committed=%0d delta_committed=%0d control=%0d recovery=%0d",
                                 coremark_stage_cycles, stats_pc_ex,
                                 normal_total,
                                 normal_total - coremark_last_heartbeat_committed,
                                 control_total, prediction_recovery_count);
                        if (normal_total == coremark_last_heartbeat_committed)
                            $fatal(1,
                                   "[COREMARK ERROR] no committed-instruction progress between heartbeats pc=%08h",
                                   stats_pc_ex);
                        coremark_last_heartbeat_committed <= normal_total;
                        coremark_heartbeat_countdown
                            <= coremark_heartbeat_cycles;
                    end
                    else begin
                        coremark_heartbeat_countdown
                            <= coremark_heartbeat_countdown - 1;
                    end

                    if (coremark_stage_cycles
                        >= (coremark_run_timeout_cycles - 1)) begin
                        $fatal(1,
                               "[COREMARK ERROR] benchmark timeout pc=%08h committed=%0d control=%0d recovery=%0d",
                               stats_pc_ex, normal_total, control_total,
                               prediction_recovery_count);
                    end
                end
            end

            COREMARK_STAGE_WAIT_RESULT: begin
                coremark_stage_cycles <= coremark_stage_cycles + 1;
                if (coremark_stage_cycles
                    >= (coremark_result_timeout_cycles - 1)) begin
                    $fatal(1,
                           "[COREMARK ERROR] UART result timeout pc=%08h committed=%0d",
                           stats_pc_ex, normal_total);
                end
            end

            default: begin
                $fatal(1, "[COREMARK ERROR] invalid monitor stage");
            end
        endcase
    end
end

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
        $display("----------------------------------------------------------");

        forever begin
            @(negedge uart_tx);
            baud_cycle_cnt = u_soc_top.u_uart.uart_baud[15:0];
            bit_period_ns = 20 * (baud_cycle_cnt + 1);

            #(bit_period_ns + (bit_period_ns / 2));
            rx_char = 8'h00;

            for (i = 0; i < 8; i = i + 1) begin
                rx_char[i] = uart_tx;
                #(bit_period_ns);
            end

            $write("%c", rx_char);
            uart_buffer = $sformatf("%s%c", uart_buffer, rx_char);
            if (rx_char == 8'h0a) begin
                process_coremark_uart_line(uart_line_buffer);
                uart_line_buffer = "";
            end
            else if (rx_char != 8'h0d) begin
                uart_line_buffer = $sformatf("%s%c", uart_line_buffer,
                                             rx_char);
            end
        end
    end
endtask

// --- Wires for User Program x26/x27 ISA checking ---
`ifdef CHECK_X26_X27
wire [31:0] x3  = u_soc_top.u_core.u_regfile.r_regfile[3];
wire [31:0] x26 = u_soc_top.u_core.u_regfile.r_regfile[26];
wire [31:0] x27 = u_soc_top.u_core.u_regfile.r_regfile[27];
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
    print_uart_buffer();
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

`ifdef IVERILOG
initial begin
    $dumpfile("tb_soc_top.vcd");
    $dumpvars(0, tb_soctop_userprog);
end
`endif

// Global Watchdog Timeout
initial begin
    #12_000_000_000;
    // #100_000_000;  // 100ms, enough for the CoreMark quick run.
    $display("\nSimulation Time Out.");
    print_uart_buffer();
    $finish;
end

// ---------------- SVA Bindings ----------------
`ifdef ENABLE_SVA
`ifndef IVERILOG
bind soc_bus sva_soc_bus u_sva_soc_bus (
    .clk(clk),
    .rst_n(rst_n),
    .mem_req_load_exu(i_mem_req_load),
    .sel_itcm_bus(sel_itcm),
    .mem_addr_bus(i_mem_addr)
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

endmodule
