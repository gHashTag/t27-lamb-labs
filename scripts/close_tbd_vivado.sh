#!/bin/bash
# EXECUTE_NOW: Close all TBDs using Vivado
# Run this script AFTER Vivado is installed and project is open

set -e

echo "=== CLOSING TBDs WITH VIVADO ==="

# Navigate to project directory
cd /Users/playra/t27-lamb-labs

# Find the Vivado project or create a project from bitstream
# We need to open the routed design checkpoint (.dcp) or recreate project from bitstream

# For now, let's create the Tcl script that will be run in Vivado
cat > /tmp/vivado_reports.tcl << 'TCL_EOF'
# Vivado Tcl commands to close TBDs
# Run this in Vivado Tcl Console after opening routed design

# 1. LUT/BRAM Utilization - MEASURED
puts "=== Running report_utilization ==="
report_utilization
report_ram_utilization -include_lutram

# Save utilization report
write_file -force utilization_report.txt [report_utilization]
write_file -force ram_utilization.txt [report_ram_utilization -include_lutram]

# 2. Power estimation
puts "=== Running report_power ==="
report_power

# Save power report
write_file -force power_report.txt [report_power]

# 3. Also get detailed resource info
report_timing_summary
write_file -force timing_report.txt [report_timing_summary]

puts "=== Reports generated ==="
exit
TCL_EOF

echo "=== Tcl script created at /tmp/vivado_reports.tcl ==="
echo ""
echo "=== INSTRUCTIONS TO RUN ==="
echo "1. Install Vivado ML Standard (free WebPACK):"
echo "   https://www.xilinx.com/products/design-tools/vivado.html"
echo "   Select 'Vivado ML Standard Edition' -> 'WebPACK' (free, no license needed for Artix-7)"
echo ""
echo "3. Open Vivado and load the project:"
echo "   Option A: Open routed design checkpoint (.dcp)"
echo "   Option B: Create project from bitstream + sources"
echo ""
echo "3. Run in Vivado Tcl Console:"
echo "   source /tmp/vivado_reports.tcl"
echo ""
echo "3. After reports generate, run the parsing script:"
echo "   python3 scripts/parse_vivado_reports.py"
echo ""
echo "=== Files generated ==="
ls -la /tmp/vivado_reports.tcl
