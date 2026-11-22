# SURGICAL CONTROL for the R4/T4 clock measurement.
#
# Same design as the measured R4/T4 probe (identical divide chain, counter and readback),
# with the clock taken from STARTUPE2.CFGMCLK instead of the R4/T4 oscillator.
#
# The R4/T4 pins are still constrained, and the differential clock is observed on the
# AX7203's user LED B13, so the placement is anchored by board pins exactly as in the build
# that produced the R4/T4 reading. Without a package pin, nextpnr's placer scatters the
# BSCANE2 shift register and the design does not route.
set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL15} [get_ports clk200_p]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD DIFF_SSTL15} [get_ports clk200_n]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports led_b13]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLDOWN [current_design]
