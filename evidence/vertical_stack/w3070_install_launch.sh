#!/bin/bash
# T1: launch Vivado ML Standard + Artix-7 ONLY install on w3070 (run via ssh w3070 'bash -s' < this)
set -e
C=~/.Xilinx/install_config.txt
sed -i 's|^Destination=.*|Destination=/home/t27ssh/tools/Xilinx|' $C
sed -i 's|^Modules=.*|Modules=Kintex UltraScale:0,Versal AI Edge Series:0,Vitis Networking P4:0,Artix UltraScale+:0,Spartan-7:0,Artix-7:1,Vitis Model Composer(Toolbox for MATLAB and Simulink. Includes the functionality of System Generator for DSP):0,Versal Prime Series:0,DocNav:0,Zynq UltraScale+ MPSoC:0,Zynq-7000:0,Virtex UltraScale+:0,Virtex UltraScale+ HBM:0,Power Design Manager (PDM):0,Vitis Embedded Development:0,Kintex UltraScale+:0,Virtex UltraScale+ 58G:0,Kintex-7:0,Install Devices for Kria SOMs and Starter Kits:0,Versal ACAP:0|' $C
sed -i -e 's|^CreateProgramGroupShortcuts=.*|CreateProgramGroupShortcuts=0|' -e 's|^CreateDesktopShortcuts=.*|CreateDesktopShortcuts=0|' -e 's|^CreateFileAssociation=.*|CreateFileAssociation=0|' $C
grep -E '^(Edition|Destination)' $C
grep -o 'Artix-7:1' $C
cd ~/vivado_inst/x
nohup ./xsetup -a XilinxEULA,3rdPartyEULA -b Install -c ~/.Xilinx/install_config.txt >/tmp/xinstall.log 2>&1 &
echo "INSTALL launched pid $!"
# LOG_GUARD: installer log writer is unbounded (2026-11-26 VPS incident: single
# 25 692 917 631-byte log). Watch 12h; kill xsetup if logs exceed 2048 MB.
( for i in $(seq 1 720); do
    sleep 60
    SZ=$(du -sm ~/.Xilinx/xinstall /tmp/xinstall.log 2>/dev/null | awk '{s+=$1} END{print s+0}')
    if [ "${SZ:-0}" -gt 2048 ]; then
      pkill -f xsetup
      echo "LOG_GUARD: killed xsetup at ${SZ}M" >> /tmp/xinstall_guard.log
      exit 0
    fi
  done ) &
sleep 15
ps aux | grep -c '[x]setup'
tail -5 /tmp/xinstall.log
