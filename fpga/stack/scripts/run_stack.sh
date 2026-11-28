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
# B-ESTIMATE reduction: the .t27 spec specs/fpga/bestimate_stat.t27 (law: logic
# only in .t27). Provide the compiled reporter via BESTIMATE_BIN (host side:
# `make stack-bestimate` builds it with t27c+zig); without it, fall back to
# echoing the raw cell histogram.
if [ -n "${BESTIMATE_BIN:-}" ]; then
  "$BESTIMATE_BIN" < "$ROOT/results/$NAME.stat" > "$ROOT/results/$NAME.bestimate.json"
  cat "$ROOT/results/$NAME.bestimate.json"
else
  echo "[$NAME] cell histogram (BESTIMATE_BIN not set, no reduction):"
  sed -n '/Number of cells:/,$p' "$ROOT/results/$NAME.stat"
fi
