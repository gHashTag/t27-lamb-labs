# ALINX AX7203 (xc7a200tfbg484-2): the 200 MHz differential oscillator on R4 (P) / T4 (N).
# Pins from fpga/HARDWARE_SSOT.md in the parent repository (ALINX AX7103/AX7203 manual).
# One port per line: nextpnr's XDC reader does not expand [*].
set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL15} [get_ports clk200_p]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD DIFF_SSTL15} [get_ports clk200_n]
create_clock -period 5.000 -name clk200 [get_ports clk200_p]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
