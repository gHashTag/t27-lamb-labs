#!/bin/bash
# Verify the CORRECTED token-sequential attention against a CPU golden.
#
# Verilator is used rather than Icarus because Verilator enforces the semantics a synthesizer
# sees: a memory of packed words with a variable element index, a signed part-select and a
# variable-offset part-select write are all accepted or rejected the way yosys accepts or
# rejects them. Icarus accepted the variable-offset write that yosys silently drops.
#
# Usage: verify_attention.sh [HD] [KV] [trials]
HD=${1:-4}; KV=${2:-8}; TRIALS=${3:-120}
cd "$(dirname "$0")"
sed -e "s/localparam HD = 4;/localparam HD = $HD;/" \
    -e "s/localparam KV = 8;/localparam KV = $KV;/" \
    -e "s/trials < 40/trials < $TRIALS/" attn_token_fixed_tb.v > /tmp/_attn_tb.v
verilator --binary -Wno-fatal --top-module attn_clean_tb \
  attn_token_verified.v /tmp/_attn_tb.v -o attn_vtb --Mdir /tmp/obj_attn_v >/dev/null 2>&1 || {
    echo "verilator build FAILED"; exit 1; }
/tmp/obj_attn_v/attn_vtb | grep -E "ATTENTION VERIFICATION|RESULT"
