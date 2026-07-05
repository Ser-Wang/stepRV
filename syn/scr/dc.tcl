#-------------------------------------------------------------------------------
# Master Design Compiler synthesis run script
#-------------------------------------------------------------------------------

# 1. Environment, libraries setup and RTL analysis/elaboration
# Sourcing with echo: source -echo -verbose ./scr/1_dc_setup.tcl
source ./scr/1_dc_setup.tcl

# 2. Loading constraints (SDC file)
# Sourcing with echo: source -echo -verbose ./scr/2_dc_const.tcl
source ./scr/2_dc_const.tcl

# 3. Compiling the design
# Sourcing with echo: source -echo -verbose ./scr/3_dc_compile.tcl
source ./scr/3_dc_compile.tcl

# 4. Generating outputs and reports
# Sourcing with echo: source -echo -verbose ./scr/4_dc_report.tcl
source ./scr/4_dc_report.tcl

# 5. Temporary reports for active debug/optimization work
source ./scr/5_dc_temp_report.tcl

echo "Synthesis finished successfully!"
exit
