# T1 variant B: synthesized-only power/utilization ESTIMATE via Vivado batch mode.
# Input: committed rtl/ternary_mac_demo_top.v (Vivado re-synthesis = ESTIMATE class,
# NOT routed, NOT the shipped bitstream). Host: w3070 (Windows), Vivado batch mode:
#   vivado -mode batch -source t1_b_estimate_vivado.tcl -journal b.log -log b_run.log
# Honest label: ESTIMATE. Never quote these numbers as routed or measured-on-board.
open_project -reset t1_b_estimate
read_verilog rtl/ternary_mac_demo_top.v
synth_design -top ternary_mac_demo_top -part xc7a200tfbg484-2
report_power -file t1_b_power_estimate.txt
report_utilization -file t1_b_utilization.txt
write_file -force power_estimate_summary.txt [report_power -summary]
close_project
