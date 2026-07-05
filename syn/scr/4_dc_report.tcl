#-------------------------------------------------------------------------------
# Dump design to files
#-------------------------------------------------------------------------------
set DESIGN_TOP      [getenv DESIGN_TOP]
set OUT_DIR         [getenv OUT_DIR]
set RPT_PATH        $OUT_DIR/rpt

echo "Dumping synthesized design files..."
write -format ddc -hierarchy -output $OUT_DIR/${DESIGN_TOP}_syn.ddc    ;# Save Synopsys database file
write -format verilog -hierarchy -output $OUT_DIR/${DESIGN_TOP}_syn.v  ;# Save gate-level Verilog netlist
write_sdf -version 2.0 $OUT_DIR/${DESIGN_TOP}_syn.sdf                  ;# Save Standard Delay Format (SDF) timing file
write_sdc $OUT_DIR/${DESIGN_TOP}_syn.sdc                               ;# Save constraints in SDC format (avoiding overwriting input SDC)

#-------------------------------------------------------------------------------
# Redirect reports to files
#-------------------------------------------------------------------------------
echo "Generating synthesis reports..."
redirect $RPT_PATH/${DESIGN_TOP}_design.chk  {check_design}  
redirect $RPT_PATH/${DESIGN_TOP}_timing.chk  {check_timing}

# Report violated design constraints (setup, hold, design rules)
redirect $RPT_PATH/${DESIGN_TOP}_constraints.rpt {report_constraints -all_violators}

# Report clock settings and attributes
redirect $RPT_PATH/${DESIGN_TOP}_clock.rpt {report_clock -attributes}
# Report clock gating cells and performance
redirect $RPT_PATH/${DESIGN_TOP}_clock_gate.rpt {report_clock_gating}

# Report detailed timing paths (worst-case setup paths)
redirect $RPT_PATH/${DESIGN_TOP}_timing_max.rpt {report_timing -delay max -nets -capacitance}
# Report detailed timing paths (worst-case hold paths)
redirect $RPT_PATH/${DESIGN_TOP}_timing_min.rpt {report_timing -delay min -nets -capacitance}
# Report ungated clocks
redirect $RPT_PATH/${DESIGN_TOP}_clock_gate_ungated.rpt {report_clock_gating -ungated}
# Report cell, net, and total logic area
redirect $RPT_PATH/${DESIGN_TOP}_area.rpt {report_area}
# Report hierarchical area breakout
redirect $RPT_PATH/${DESIGN_TOP}_area_hierarchy.rpt {report_area -hierarchy}
# Report dynamic and leakage power consumption
redirect $RPT_PATH/${DESIGN_TOP}_power.rpt {report_power}
# Report hierarchical power consumption breakout
redirect $RPT_PATH/${DESIGN_TOP}_power_hierarchy.rpt {report_power -hierarchy}
# Report nets with fanout exceeding the specified threshold (e.g., 50)
redirect $RPT_PATH/${DESIGN_TOP}_fanout.rpt {report_net_fanout -threshold 50}
