# ============================================
# Genus Synthesis TCL
# Top Module: cnn_top
# ============================================

# Read standard cell library
read_libs /home/install/FOUNDRY/digital/90nm/dig/lib/fast.lib

# Read SystemVerilog files
read_hdl -sv {
    control.sv
    im2col.sv
    mini_addr_gen.sv
    image_buffer.sv
    kernel_buffer.sv
    pe.sv
    systolic_array.sv
    output_buffer.sv
    top.sv
}

# Elaborate design
elaborate cnn_top

# Check design
check_design -unresolved

# ============================================
# SDC Constraints
# ============================================

create_clock -name clk -period 10.0 \
    -waveform {0.0 5.0} [get_ports clk]

set_clock_uncertainty 0.2 [get_clocks clk]
set_clock_transition 0.1 [get_clocks clk]

set_input_delay 1.0 -clock clk \
    [remove_from_collection [all_inputs] [get_ports clk]]

set_output_delay 1.0 -clock clk [all_outputs]

# ============================================
# Synthesis
# ============================================

set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high

syn_generic
syn_map
syn_opt

# ============================================
# Display Reports in Terminal
# ============================================

report_area
report_gates
report_timing

# ============================================
# Write Netlist and SDC
# ============================================

write_hdl > cnn_top_mapped.v
write_sdc cnn_top.sdc

puts "===================================="
puts "Synthesis completed: cnn_top"
puts "===================================="
