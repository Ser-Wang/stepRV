#-------------------------------------------------------------------------------
# Temporary reports for active debug/optimization work
#-------------------------------------------------------------------------------
set DESIGN_TOP      [getenv DESIGN_TOP]
set OUT_DIR         [getenv OUT_DIR]
set RPT_PATH        $OUT_DIR/rpt

# Report top setup paths for path-family analysis
redirect $RPT_PATH/${DESIGN_TOP}_timing_max_top10.rpt {
    report_timing -delay max -nets -capacitance -max_paths 10
}

# Report SRAM macro clock-to-Q arcs explicitly
set SRAM_CLK_PINS [get_pins -quiet -hierarchical {
    u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p/CLKA
    u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p/CLKB
    u_dmem/u_dtcm_sram_wrapper/u_smic55_4096x32_1rw/CLK
}]
set SRAM_Q_PINS [get_pins -quiet -hierarchical {
    u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p/QA*
    u_imem/u_itcm_sram_wrapper/u_smic55_8192x32_2p/QB*
    u_dmem/u_dtcm_sram_wrapper/u_smic55_4096x32_1rw/Q*
}]

redirect $RPT_PATH/${DESIGN_TOP}_timing_sram_clk_to_q.rpt {
    if {[sizeof_collection $SRAM_CLK_PINS] == 0 || [sizeof_collection $SRAM_Q_PINS] == 0} {
        echo "Warning: SRAM clk-to-Q report skipped because SRAM clock or Q pins were not found."
    } else {
        report_timing -delay max -nets -capacitance -max_paths 20 \
            -from $SRAM_CLK_PINS \
            -to   $SRAM_Q_PINS
    }
}

# Report the max combinational path inside EXU ALU from rs1 input to WB data output
set ALU_RS1_PINS     [get_pins -quiet -hierarchical u_core/u_exu/u_exu_alu/i_alu_rs1*]
set ALU_WB_DATA_PINS [get_pins -quiet -hierarchical u_core/u_exu/u_exu_alu/o_alu_wb_data*]

redirect $RPT_PATH/${DESIGN_TOP}_timing_exu_alu_rs1_to_wb_data.rpt {
    if {[sizeof_collection $ALU_RS1_PINS] == 0 || [sizeof_collection $ALU_WB_DATA_PINS] == 0} {
        echo "Warning: EXU ALU rs1-to-wb-data report skipped because ALU pins were not found."
    } else {
        report_timing -delay max -nets -capacitance -max_paths 10 \
            -from $ALU_RS1_PINS \
            -to   $ALU_WB_DATA_PINS
    }
}

# Report the current WBU write-back index to UART read-data path family explicitly
# redirect $RPT_PATH/${DESIGN_TOP}_timing_wbu_to_uart_rd.rpt {
#     report_timing -delay max -nets -capacitance -max_paths 10 \
#         -from [get_pins -quiet -hierarchical u_core/u_wbu/r_wb_rd_idx_wbu_reg*/Q] \
#         -to   [get_pins -quiet -hierarchical u_soc_bus/r_uart_rd_data_d1_reg*/D]
# }
