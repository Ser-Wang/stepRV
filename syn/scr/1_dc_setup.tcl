#-------------------------------------------------------------------------------
# Paths setup
#-------------------------------------------------------------------------------
set DESIGN_TOP      [getenv DESIGN_TOP]
set RTL_PATH        [getenv RTL_PATH]
set DEFINE_PATH     [getenv DEFINE_PATH]
set LIB_PATH        [getenv LIB_PATH]
set OUT_DIR         [getenv OUT_DIR]

set RPT_PATH        $OUT_DIR/rpt

# Make missing directories
file mkdir $OUT_DIR $RPT_PATH

#-------------------------------------------------------------------------------
# Library configuration
#-------------------------------------------------------------------------------
set search_path [concat $search_path $LIB_PATH $RTL_PATH $DEFINE_PATH]
set synthetic_library "dw_foundation.sldb"

# Industry practice: target_library should only specify the worst-case setup corner (SS) for single-corner optimization
# Original three-corner configuration:
# set target_library "scc55ulp_hdlp_rvt_ss_v1p08_125c_ccs.db scc55ulp_hdlp_rvt_ff_v1p32_-40c_ccs.db scc55ulp_hdlp_rvt_tt_v1p2_25c_ccs.db"
set target_library "scc55ulp_hdlp_rvt_ss_v1p08_125c_ccs.db"

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

# Helper procedure to read standard .f filelists
proc read_filelist {filelist} {
    set fp [open $filelist r]
    set files {}
    while {[gets $fp line] >= 0} {
        set line [string trim $line]
        if {$line == "" || [string match "#*" $line] || [string match "//*" $line]} {
            continue
        }
        lappend files $line
    }
    close $fp
    return $files
}

# Sourcing file list
set filelist_path "./filelist/${DESIGN_TOP}.f"
if {[file exists $filelist_path]} {
    echo "Reading design filelist from $filelist_path"
    set hdl_files [read_filelist $filelist_path]
} else {
    echo "Error: Filelist $filelist_path not found!"
    exit
}

# Analyze Verilog/SystemVerilog files
foreach file $hdl_files {
    set file_ext [file extension $file]
    if {[file pathtype $file] == "absolute"} {
        set full_path $file
    } else {
        set full_path [file join $RTL_PATH $file]
    }

    if {$file_ext == ".sv" || $file_ext == ".sverilog"} {
        analyze -format sverilog $full_path
    } else {
        analyze -format verilog $full_path
    }
}

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
