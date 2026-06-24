#-------------------------------------------------------------------------------
# Load constraints
#-------------------------------------------------------------------------------
set SDC_PATH ./sdc
set DESIGN_TOP [getenv DESIGN_TOP]
set SDC_NAME [getenv SDC_NAME]

if {$SDC_NAME == ""} {
    set SDC_NAME $DESIGN_TOP
}

# SDC constraints file path
set sdc_file "$SDC_PATH/${SDC_NAME}.sdc"

if {[file exists $sdc_file]} {
    echo "Sourcing constraints from $sdc_file"
    # Sourcing with echo: source -echo -verbose $sdc_file
    source $sdc_file
} else {
    echo "Error: SDC constraints file $sdc_file not found!"
    exit
}
