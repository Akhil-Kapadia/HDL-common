# CDC Synchronizer Constraints
# This script applies the ASYNC_REG property to all registers inside cdc_sync modules
# to ensure they are placed close together in the FPGA fabric, reducing MTBF.

set cdc_cells [get_cells -hier -filter {ORIG_REF_NAME == cdc_sync || REF_NAME == cdc_sync}]

if {[llength $cdc_cells] > 0} {
    puts "Found [llength $cdc_cells] cdc_sync instances. Applying ASYNC_REG property."
    foreach cell $cdc_cells {
        set sync_regs [get_cells -hier -filter "NAME =~ $cell/sync_regs_reg*" -within $cell]
        if {[llength $sync_regs] > 0} {
            set_property ASYNC_REG TRUE $sync_regs
            # Optional: false path for the first stage of the synchronizer
            # This is often handled at a higher level, but can be done here if needed.
            # set_false_path -to [get_pins -filter {REF_PIN_NAME == D} -within [lindex $sync_regs 0]]
        }
    }
} else {
    puts "No cdc_sync instances found in the design."
}
