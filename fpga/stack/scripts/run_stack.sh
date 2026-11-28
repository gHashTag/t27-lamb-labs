#!/usr/bin/env bash
# fpga/stack/scripts/run_stack.sh — run the yosys-based B-ESTIMATE flow.
# Usage: run_stack.sh <stack_root> <design_file.v> <top_module>
# stack_root contains rtl/, scripts/, results/ (as checked into the repo).
set -euo pipefail
ROOT="${1:?stack root}"; FILE="${2:?verilog file}"; TOP="${3:?top module}"
VER="$(yosys -V)"
NAME="$(basename "$FILE" .v)"
mkdir -p "$ROOT/results"
yosys -q -p "read_verilog $FILE; synth_xilinx -family xc7 -top $TOP -flatten; tee -o $ROOT/results/$NAME.stat stat; write_json $ROOT/results/$NAME.netlist.json"
# B-ESTIMATE reduction lives in a .t27 spec (law: logic only in .t27, thin glue here);
# until the reporter spec lands, echo the raw cell histogram from the stat artifact.
echo "[$NAME] cell histogram:"
sed -n '/Number of cells:/,$p' "$ROOT/results/$NAME.stat"
