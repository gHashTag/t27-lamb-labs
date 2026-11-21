# ALINX AX7203 (xc7a200tfbg484-2) - token-sequential attention with a UART timing beacon.
# Pins from fpga/HARDWARE_SSOT.md (ALINX AX7103/AX7203 manual; base board shared).
# One port per line: nextpnr's XDC reader does not expand [*].
set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL15} [get_ports clk200_p]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD DIFF_SSTL15} [get_ports clk200_n]
create_clock -period 5.000 -name clk200 [get_ports clk200_p]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports led0]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports led1]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33 SLEW FAST} [get_ports uart_tx]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
