# ==============================================================================
# Tcl script to create Vivado project for BASIC_SOC_COURSE Level 0 (MAC & PIO)
# Usage in Vivado Tcl Console:
#   cd D:/2026/FPGA/learning/AISeQLab/BASIC_SOC_COURSE/PIO-Transfer_Level0
#   source create_project.tcl
# ==============================================================================

set proj_name "MAC_SoC_Level0"
set proj_dir  [file normalize "./vivado_project"]

# Check if KV260 part (xck26-sfvc784-2LV-c) is available; if not, fallback to xcku3p-ffva676-1-e
set target_part "xcku3p-ffva676-1-e"
if {[llength [get_parts -quiet "xck26-sfvc784-2LV-c"]] > 0} {
    set target_part "xck26-sfvc784-2LV-c"
}

puts "===> Creating Vivado project: $proj_name at $proj_dir with part: $target_part"
create_project $proj_name $proj_dir -part $target_part -force

# Add RTL Design Sources
puts "===> Adding RTL sources from ./RTL"
add_files -fileset sources_1 [glob -nocomplain [file normalize "./RTL/*.v"]]
set_property top MY_IP [current_fileset]

# Add Simulation Sources
puts "===> Adding Simulation sources from ./TB"
add_files -fileset sim_1 [glob -nocomplain [file normalize "./TB/*.v"]]
set_property top TB_MAC [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "===> Project setup completed successfully!"
puts "===> To run simulation, type: launch_simulation"