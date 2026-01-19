# CDC Constraints
# This script applies properties to ensure reliable clock domain crossing.

# 1. cdc_sync: Apply ASYNC_REG to all synchronizer chains
set cdc_sync_cells [get_cells -hier -filter {ORIG_REF_NAME == cdc_sync || REF_NAME == cdc_sync}]

if {[llength $cdc_sync_cells] > 0} {
    puts "Found [llength $cdc_sync_cells] cdc_sync instances. Applying ASYNC_REG property."
    foreach cell $cdc_sync_cells {
        set sync_regs [get_cells -hier -filter "NAME =~ $cell/sync_regs_reg*" -within $cell]
        if {[llength $sync_regs] > 0} {
            set_property ASYNC_REG TRUE $sync_regs
        }
    }
}

# 2. cdc_handshake: Apply data path constraints
# The data bus 'w_data_reg' crossing into the 'read' domain should be constrained 
# to ensure it arrives at the destination registers before the synchronized 'req' toggle.
set cdc_hs_cells [get_cells -hier -filter {ORIG_REF_NAME == cdc_handshake || REF_NAME == cdc_handshake}]

if {[llength $cdc_hs_cells] > 0} {
    puts "Found [llength $cdc_hs_cells] cdc_handshake instances. Applying datapath constraints."
    foreach cell $cdc_hs_cells {
        # Constraint the data bus crossing
        # We find the source pins (data register) and destination pins (read data register)
        set src_pins [get_pins -hier -filter {NAME =~ *w_data_reg_reg*/Q} -within $cell]
        set dest_pins [get_pins -hier -filter {NAME =~ *r_data_reg*/D} -within $cell]
        
        if {[llength $src_pins] > 0 && [llength $dest_pins] > 0} {
            # Use set_max_delay -datapath_only to ignore clock skew and just limit the path delay
            # Typically set to the period of the faster clock or a fixed small value
            set_max_delay -from $src_pins -to $dest_pins -datapath_only 4.0
            set_false_path -from $src_pins -to $dest_pins
        }
        
        # Also ensure the toggle signals are constrained
        set toggle_src [get_pins -hier -filter {NAME =~ *w_req_toggle_reg/Q} -within $cell]
        set toggle_dest [get_pins -hier -filter {NAME =~ *req_sync_inst/sync_regs_reg[0]/D} -within $cell]
        if {[llength $toggle_src] > 0 && [llength $toggle_dest] > 0} {
             set_max_delay -from $toggle_src -to $toggle_dest -datapath_only 4.0
        }
    }
}
