# AX7203 token-rate probe: the 200 MHz differential oscillator on R4 (P) / T4 (N), the user
# LED on B13, and the UART TX pin left unconnected.
set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL15} [get_ports clk200_p]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD DIFF_SSTL15} [get_ports clk200_n]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports led_b13]
create_clock -period 5.000 -name clk200 [get_ports clk200_p]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
