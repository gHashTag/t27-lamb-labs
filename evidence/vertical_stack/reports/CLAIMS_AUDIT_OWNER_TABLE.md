# Claims Audit — Owner FPGA Table (2026-11-24)

STATUS: COMPLETE. Every verdict below cites the exact command that produced it and the
evidence file that supports or refutes the claim. This report closes the audit that was
interrupted in session `8f57f2cf` on 2026-11-24 ~22:17 (+07).

## 1. Provenance of the audited claims

- Source: owner message U15 in DSH session `8f57f2cf-f6ab-41d7-bbe2-beef305093be`
  (log: `~/.dsh/sessions/--Users-playra-t27-lamb-labs--/8f57f2cf-.../session.v4.jsonl.zstd`,
  read 2026-11-24), message beginning `обнови цело!! твой фокус FGPA`.
- Audited object: the 8-row table "Что уже сделано по FPGA" in that message.
- Repos checked (all tracked files, read-only `git grep`):
  - GPU/software lane `dsh-5344b40f-4225` @ `4a174471e50d74e7282b02ed73f4a8e90f86ea83`
  - hardware lane `dsh-e6e4cd9f-d7f1` @ `c4d20fc` (49 commits, unmerged)
  - master `a7ef751` (= `origin/master`)
  - upstream monorepo `/Users/playra/t27` @ `ba23e49f0`

## 2. Method

`git grep -l -iE <pattern>` per repository; file counts recorded. Patterns and counts:

| Pattern | GPU lane files | HW lane files | Upstream files |
|---|---|---|---|
| `403[,_]?200` | **0** | **0** | 6 (all `0x4032000000000000`, see §3) |
| `33[,_]?792` | 1 | 1 | 14 (all substrings, see §3) |
| `42 +trained` | **0** | **0** | 0 |
| `trained +matrices` | **0** | **0** | 0 |

## 3. Number audit

| Claimed number | Verdict | Where the digits actually occur |
|---|---|---|
| 403,200 "receipts" | **NOT_FOUND as a claim of this work** | Only as the hex substring of `0x4032000000000000` in upstream conformance vectors (`conformance/vectors/*.json`). Decoded as IEEE-754 binary64 that constant is exactly **18.0** (`python3 -c "import struct; struct.unpack('>d', bytes.fromhex('4032000000000000'))[0]"` → `18.0`). It is a float literal, not a receipt count. |
| 33,792 "rows bit-exact" | **NOT_FOUND as a claim of this work** | Lane + HW lane: one hit each, and it is the yosys provenance string `cells_xtra.v:33792.17-33792.30` inside generated netlists (`evidence/clock_probe/clock_probe_r4t4.netlist.json:193593`, upstream `fpga/openxc7-synth/*.json:193596`). Upstream: substrings inside seal hashes and long decimal digit runs of GF(256) test vectors. None is a measured row count. |
| "42 trained matrices" | **NOT_FOUND** | Zero hits for `42 trained` / `trained matrices` in all four repos. No training was ever authorized or run in the Lamb Labs scope; no training artifact exists. |

## 4. Verdicts per owner table row

| # | Owner row (U15) | Verdict | Correction — what the evidence actually supports |
|---|---|---|---|
| 1 | GF16 dot4 RTL — "RTL/Verilog и тесты, bit-exact conformance" | **PARTIAL** | Bit-exact conformance FOUND, but at CPU/PTX/GPU layers, not RTL: conformance spec 13/13 PASS (`specs/igla/coder/gf16_dot4_conformance.t27`, `reports/test_report_gf16_dot4_conformance.txt`), PTX vs CPU oracle 288 groups (`gpu/GPU_RUN_M4_STAGE2.md`). **No GF16 dot4 RTL/Verilog exists**; names matching `gf16_dot4` in `port/fpga/...` are unrelated modules (`rtl_fpga_inventory.md` §2, §6). |
| 2 | FPGA execution — "AX7203 / Artix-7, реальные прогоны на board" | **FOUND, different design** | Board runs are real: `isc_done 1`, CFGMCLK 67.16 MHz (n=9), R4/T4 398.3 MHz / live 399.08 MHz (n=8, HW lane r10–12), XADC telemetry. But the shipped bitstream is the **ternary MAC demo**, not GF16 dot4. GF16 dot4 has never executed on the FPGA. Hardware lane is on owner HOLD since U17. |
| 3 | Corrected attention — "42 trained matrices, 403,200 receipts, 33,792 rows bit-exact" | **NOT_FOUND** | All three numbers absent (§3). What exists: attention token verification **12,000 randomised trials, 0 mismatches** across 6 configs (`evidence/attention_token/token_iteration_report.json:61`, master); corrected attention **1,200 randomised Verilog trials, 0 mismatches** (10 configs × 120, `evidence/attention_fix/attention_correction_report.json:375`, master). These are CPU-golden/Verilog comparisons — no "receipts", no "trained matrices". |
| 4 | Ternary matmul — "GF16/TNF путь, bit-exact сверка с reference" | **PARTIAL** | Ternary MAC attention path with bit-exact CPU golden: FOUND (row 3 sources). A GF16/TNF **FPGA** path: NOT_FOUND (spec→RTL chain broken for the shipped `.bit`, `rtl_fpga_inventory.md` G1–G18). |
| 5 | Silicon-facing evidence — "Receipts, KAT vectors, board runs" | **PARTIAL** | Board runs: FOUND (row 2). Receipts as spec-checked artifacts: FOUND (`specs/fpga/adapter.t27`). KAT vectors executed on board for GF16: NOT_FOUND. |
| 6 | Host integration — "CPU reference / conformance есть, host↔GPU path — отдельный слой" | **FOUND as stated** | `HOST_ABI.md` + `host_abi_vectors.json` verified (readiness A6); host↔device transfers remain out of scope, as stated. |
| 7 | GPU correctness — "smoke + batch evidence есть, но не «все входы»" | **FOUND as stated** | Smoke 8/8 bit-exact, batch 250 finite bit-exact, 38 NaN per policy, 0 CUDA errors (`gpu/GPU_ACCEPTANCE_M4.md:235-240`). Acceptance was declared in chat (U17 `GPU_ACCEPTANCE_AND_TOOLCHAIN_PIN`) but no acceptance record exists in evidence — recorded PENDING per the owner's current state (2026-11-24 consolidation order). |
| 8 | Performance/power NOT_RUN; Tapeout readiness GAP | **CONFIRMED as stated** | M6 not authorized, not run. B4 (silicon readiness) = GAP in `READINESS_MATRIX.md`. |

## 5. Required corrections before any publication

1. Row 3 must be rewritten to the measured numbers: 12,000 + 1,200 randomised trials,
   0 mismatches, with the two report files as sources. "403,200 receipts",
   "33,792 rows", "42 trained matrices" must not be used anywhere.
2. Row 1 must say "bit-exact conformance at CPU/PTX/GPU layers; no RTL for GF16 dot4".
3. Row 2 must name the design that ran on the board (ternary MAC demo + clock probes),
   and that GF16 dot4 has not run on FPGA.

## 6. Limitations of this audit

- `git grep` covers tracked files only; untracked scratch was excluded by design.
- Upstream `/Users/playra/t27` is a fast-moving monorepo; counts are pinned to
  `ba23e49f0` and may differ at other revisions.
- The audit verifies number provenance; it does not re-run any measurement.
