# Unified Readiness Matrix — Lamb Labs Vertical Stack (M2 draft, pre-merge)

STATUS: DRAFT prepared in lane `dsh-5344b40f-4225` @ `fce605a` (2026-11-25). Every row names
the branch its evidence lives on; nothing is claimed as merged. Master-ready after M1 merge +
owner decisions (see `OWNER_DECISIONS.md`). Supersedes nothing: the GPU-only matrix stays in
`READINESS_MATRIX.md`; this file adds the hardware lane and cross-lane links.

Labels: VERIFIED / MEASURED (command + artifact cited) · PROVISIONAL (measured, caveat open) ·
PENDING (awaiting owner act) · NOT_RUN · GAP · WITHDRAWN (superseded, kept in record).

## 1. GPU / software lane (`dsh-5344b40f-4225`)

| Layer | Contract | Evidence | Status |
|---|---|---|---|
| L0 numeric SSOT | GF16 semantics | `specs/numeric/gf16.t27:172-198` sha `b6324424…` | VERIFIED (A1) |
| L1 executable specs | emit + arithmetic | `specs/igla/coder/gf16_dot4_ptx.t27` `dd74e625…`, `ptx_emit.t27` `4e181244…` | VERIFIED (A2) |
| L2 CPU conformance | 13/13 PASS, 65,536 codes | `reports/test_report_gf16_dot4_conformance.txt` | VERIFIED (A3) |
| L3 PTX | sm_86, 4952 B | `gf16_dot4.ptx` sha `b9a79404…` | VERIFIED (A4) |
| L4 cubin | 22 regs, 0 spills | `gf16_dot4.cubin` sha `35e07b5f…` | VERIFIED (A5) |
| L5 host ABI | vectors + audit | `HOST_ABI.md`, `host_abi_vectors.json`, `gpu/GPU_ACCEPTANCE_M4.md` | VERIFIED (A6/A7) |
| L6 GPU correctness | smoke 8/8 + batch 250 finite + 38 NaN, 0 CUDA errors | `gpu/GPU_RUN_M4_STAGE2.md`, `reports/gpu_smoke_gated.log` | VERIFIED in declared scope; **acceptance record PENDING** (D1) |
| L7 performance/power | methodology | none | NOT_RUN / NOT_AUTHORIZED (D2) |
| L8 silicon readiness | tapeout artifacts | — | GAP (B4, out of scope by order) |

## 2. Hardware lane (`dsh-e6e4cd9f-d7f1` @ `c4d20fc`, 49 commits unmerged, HOLD per U17)

| Layer | Contract | Evidence | Status |
|---|---|---|---|
| H1 board execution | bitstream loads | `isc_done 1`, chipdb size+md5 = SSOT | MEASURED |
| H2 clock CFGMCLK | live datapath | 67.16 MHz σ1.33 n=9; functional smoke 2026-11-23 magic 10/10, 66.88 MHz in band (`evidence/functional_smoke_2026-11-23/`) | MEASURED |
| H3 clock R4/T4 | 4-session pooled | mean 397.62 MHz (398.6926 / 397.9325 / 396.2419 / 399.0808 wrap-aware live n=8, exit 0); wrap-aliasing reader defect found+fixed; **SSOT says 200 MHz — discrepancy recorded, cause unknown** | MEASURED, **PROVISIONAL** (not a design input until explained) |
| H4 Johnson /256 | divide ratio | silicon control + iverilog sim 8/8 (`evidence/clock_probe/divide_ratio_control.log`, `johnson_divide_sim_2026-11-23_045517.log`) | MEASURED |
| H5 corrected fork r4t4c | presc defect fixed | SIM-VERIFIED 8/8, readback `{0xA5A, cnt}` = `0xA5A0000C`, yosys warning-clean (`evidence/clock_probe/corrected_fork_2026-11-23/`); hardware rebuild gated on openXC7 install (D5) | SIM-VERIFIED; board rebuild PENDING |
| H6 gate chain r10–r12 | manifest + drift | r12 ALL GATES PASS exit 0, G4 293 rows/0 mismatches, G5 tree clean; chain includes a real FAIL kept in record | MEASURED |
| H7 shipped `.bit` claims | tok/s / variance | two netlist-verified defects (dead `osc` clock; accumulator pruned to 2 bits) | **WITHDRAWN** (`59b260c`), kept in record |
| H8 spec→RTL for shipped artefact | `.t27` spec → `ternary_mac_demo_top.v` | absent | GAP |
| H9 tapeout readiness | tapeout artifacts | none | GAP (B4) |

## 3. Cross-lane links (shared contracts, not name matching)

| Link | Contract | Status |
|---|---|---|
| X1 GF16 domain boundary | GPU GF16 ≠ float-GF16; documented in `READINESS_MATRIX.md` B1 | DOCUMENTED |
| X2 attention numbers | owner-table row 3 corrected to 12,000 + 1,200 trials, 0 mismatches (`reports/CLAIMS_AUDIT_OWNER_TABLE.md` §4 row 3); sources on master | CORRECTED, publication rewrite PENDING |
| X3 "GF16 dot4 RTL" claim | no RTL exists; conformance is CPU/PTX/GPU layer only (audit §4 row 1) | CORRECTED |
| X4 FPGA execution claim | board runs are ternary-MAC demo + clock probes, not GF16 dot4 (audit §4 row 2) | CORRECTED |
| X5 toolchain | w3070 `t27c 5785e3ca…` + zig 0.16.0 declared canonical in chat (U17); no evidence record yet | PENDING (D4) |

## 4. What M1 merge changes

Nothing in this matrix becomes true because of a merge; only the branch labels drop.
After merge: re-run `scripts/manifest.py`, re-hash this tree, and move H-rows'
evidence paths from branch-relative to master-relative.
