#-------------------------------------------------------------------------------
# Paths setup
#-------------------------------------------------------------------------------
set DESIGN_TOP      [getenv DESIGN_TOP]
set RTL_PATH        [getenv RTL_PATH]
set DEFINE_PATH     [getenv DEFINE_PATH]
set LIB_PATH        [getenv LIB_PATH]
set SYN_FILELIST    [getenv SYN_FILELIST]
set SRAM_MACRO_ROOT [getenv SRAM_MACRO_ROOT]
set SRAM_MACRO_DB_FILES  [getenv SRAM_MACRO_DB_FILES]
set OUT_DIR         [getenv OUT_DIR]

set RPT_PATH        $OUT_DIR/rpt

# Make missing directories
file mkdir $OUT_DIR $RPT_PATH

#-------------------------------------------------------------------------------
# Library configuration
#-------------------------------------------------------------------------------
set search_path [concat $search_path $LIB_PATH $RTL_PATH $DEFINE_PATH $SRAM_MACRO_ROOT]
set synthetic_library "dw_foundation.sldb"

set target_library "scc55ulp_hdlp_rvt_ss_v1p08_125c_ccs.db"

foreach macro_db $SRAM_MACRO_DB_FILES {
    if {![file exists $macro_db]} {
        echo "Error: SRAM macro DB not found: $macro_db"
        exit
    }
    lappend target_library $macro_db
}

set link_library "* $target_library $synthetic_library"

#-------------------------------------------------------------------------------
# Variables configuration
#-------------------------------------------------------------------------------
set verilogout_no_tri true
set verilogout_show_unconnected_pins true
set hdlin_enable_rtldrc_info true
set hdlin_enable_presto true
set hdlin_preserve_sequential true
set hdlin_keep_signal_name all
set power_preserve_rtl_hier_names true

# Suppress messages
suppress_message VER-130
suppress_message VER-129
suppress_message VER-318
suppress_message ELAB-311
suppress_message VER-936
suppress_message LINT-1
suppress_message LINT-28
suppress_message LINT-32
suppress_message LINT-33

#-------------------------------------------------------------------------------
# Analyze & Elaborate & Link
#-------------------------------------------------------------------------------
set_svf $OUT_DIR/$DESIGN_TOP.svf

# Define work library directory
define_design_lib WORK -path ./WORK

set vcs_args "+define+SYNTHESIS +incdir+${RTL_PATH} +incdir+${DEFINE_PATH}"
append vcs_args " -f $SYN_FILELIST"

echo "Analyzing design with VCS-style filelist: $SYN_FILELIST"
analyze -vcs $vcs_args -format sverilog

# Elaborate
elaborate $DESIGN_TOP

# Set the current design context
current_design $DESIGN_TOP

# Link
link

# Perform design check and abort if there are errors
if {[check_design > $RPT_PATH/${DESIGN_TOP}_chk_design.rpt] == 0} {
    echo "Error: Check Design failed! Please check report at $RPT_PATH/${DESIGN_TOP}_chk_design.rpt"
    exit
}
