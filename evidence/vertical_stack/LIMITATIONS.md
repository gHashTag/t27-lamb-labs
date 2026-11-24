# Vertical Stack Limitations — consolidated (M5, gate-free part)

STATUS: COMPLETE for what can be stated pre-merge, 2026-11-25. This file consolidates
limitation statements that were scattered across HANDOFF.md, `reports/`, and commit
messages. It adds no new measurements. Read together with `READINESS_MATRIX_UNIFIED.md`.

## Toolchain

- The only verified-good conformance runner is w3070 `t27c` sha `5785e3ca…` + zig 0.16.0.
  Mac stock `t27c` (Nov 13, `~/.cargo/bin/t27c`) blocks the conformance spec
  (`spec.zig:539:30` slice-coercion defect class). Check the toolchain sha before any rerun.
- The earlier lane-local `t27c` (`/Users/playra/.local/bin/t27c`, sha `5da927df…`) was
  removed from that host; reruns must pin the toolchain first (D4).
- The w3070 scratch regression clone was an unpacked tar, not a git clone, and idle-time
  snapshot sweeping destroyed the tree afterwards: **post-hoc hash verification of that
  regression environment is impossible**. The committed lane tree is the source of truth.

## Measured numbers and their ceilings

- R4/T4 397.62 MHz (4-session pooled mean) is MEASURED but **PROVISIONAL**: the SSOT says
  200 MHz, the discrepancy is recorded with unknown cause, and the number is not a design
  input until explained and timing-verified.
- Power/J-per-token on FPGA remain ESTIMATED (~0.7 W / ~0.12 J/token band). No external
  meter exists; Vivado is not installed; M6 is not authorized (D2).
- GPU numbers are correctness-scope only (smoke 8/8, batch 250 finite + 38 NaN, 0 CUDA
  errors). No GPU performance claim exists or is allowed.
- The owner-table numbers "403,200 receipts / 33,792 rows / 42 trained matrices" do not
  exist in any artifact (audit §3); the measured replacements are 12,000 + 1,200 trials,
  0 mismatches.

## Structural gaps

- No RTL exists for GF16 dot4; the vertical stack reaches bit-exactness at CPU/PTX/GPU
  layers only. Silicon readiness stays GAP (B4).
- The shipped FPGA bitstream (ternary MAC demo) has two netlist-verified defects; its
  tok/s claim and the closed variance gate stay WITHDRAWN.
- The spec→RTL chain for the shipped artefact is broken (GAP H8); the r4t4c corrected
  fork is SIM-VERIFIED only, board rebuild gated on openXC7 approval (D5/T5).

## Consolidation state

- Nothing is merged: master is `a7ef751`; this lane is 20 commits ahead; the hardware
  lane is 49 commits ahead and on HOLD. Merge happens only on owner go (D3), push only
  on a separate approval.
- The unified matrix's branch labels drop at merge; no row's status changes by merging.
