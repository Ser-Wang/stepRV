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

# Report the current WBU write-back index to UART read-data path family explicitly
# redirect $RPT_PATH/${DESIGN_TOP}_timing_wbu_to_uart_rd.rpt {
#     report_timing -delay max -nets -capacitance -max_paths 10 \
#         -from [get_pins -quiet -hierarchical u_core/u_wbu/r_wb_rd_idx_wbu_reg*/Q] \
#         -to   [get_pins -quiet -hierarchical u_soc_bus/r_uart_rd_data_d1_reg*/D]
# }
