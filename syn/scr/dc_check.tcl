#-------------------------------------------------------------------------------
# Fast Design Compiler front-end check script
#-------------------------------------------------------------------------------

# 1. Environment, libraries setup and RTL analysis/elaboration/link/check_design
source ./scr/1_dc_setup.tcl

# 2. Load constraints for timing sanity checks
source ./scr/2_dc_const.tcl

# 3. Fast reports without compile/netlist generation
check_timing > $RPT_PATH/${DESIGN_TOP}_check_timing.rpt
report_constraint -all_violators > $RPT_PATH/${DESIGN_TOP}_constraints_check.rpt

echo "DC quick check finished successfully!"
exit
