# ==============================================================================
# Tcl script to automatically create and setup Vivado project for 16-bit Fixed-Point Adder
# Usage in Vivado Tcl Console:
#   cd D:/2026/FPGA/learning/AISeQLab/BASIC_IC_COURSE/16-bit-Fixed-Point-Adder
#   source create_project.tcl
# ==============================================================================

set proj_name "Fixed_Point_Adder_16bit"
set proj_dir  [file normalize "./vivado_project"]

# Target part: xcku3p-ffva676-1-e (Kintex UltraScale+ available in your Vivado)
set target_part "xcku3p-ffva676-1-e"

puts "===> Creating Vivado project: $proj_name at $proj_dir with part: $target_part"
create_project $proj_name $proj_dir -part $target_part -force

# Add RTL Design Sources
puts "===> Adding RTL sources from ./RTL"
add_files -fileset sources_1 [glob -nocomplain [file normalize "./RTL/*.v"]]
set_property top Add_IP [current_fileset]

# Add Simulation Sources
puts "===> Adding Simulation sources from ./TB"
add_files -fileset sim_1 [glob -nocomplain [file normalize "./TB/*.v"]]
set_property top Core_tb [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "===> Project setup completed successfully!"
puts "===> To launch waveform simulation, type: launch_simulation"