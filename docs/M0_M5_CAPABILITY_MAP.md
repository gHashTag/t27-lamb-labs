# Capability map: existing repo state → M0–M5

**Generated**: 2026-11-23 ~01:00 UTC+7, DSH session `dsh-e6e4cd9f-d7f1`
**Baseline**: `master = origin/master = a7ef751` (code baseline `edb5b95`), 19 tags, private origin `gHashTag/t27-lamb-labs`
**Method**: every status below points to a committed artifact (file path, log, or measured run). Labels: SATISFIED / PARTIAL / GAP. No silicon claims anywhere — FPGA-only project, honestly labelled.

This is the M0–M5 mapping required by `T27_LAMB_LABS_MILESTONES_V1` step 3. Gaps feed the issue register at the bottom (step 4).

---

## M0 — Lab foundation

| DoD item | Status | Evidence / note |
|---|---|---|
| Private origin, clean `master`, tags preserved | **SATISFIED** | `origin = github.com/gHashTag/t27-lamb-labs` (private); `master = origin/master = a7ef751`; 19 tags `v0.1.0…v0.1.18`, each a semantic evidence milestone |
| `.gitignore` active, no credentials in history | **SATISFIED** | `.gitignore` = commit `a7ef751`; full-history scan re-run 2026-11-23 → `evidence/security/secret_scan_2026-11-23.log` = **CLEAN** (1 reviewed false positive: the ignore-file's own rule text) |
| DSH default workspace/cwd verified after restart | **SATISFIED (with nuance)** | Restart happened; this session opened in the `t27-lamb-labs` worktree (`session-e6e4cd9f…` = the blank session prepared on 2026-11-22). cwd override persists: `~/.dsh/profiles/web/cordis.patch.yml:941` `defaultDirectory: /Users/playra/t27-lamb-labs` (config, restart-safe). Nuance: registry `defaultWorkspaceId` regressed to dead id `282d09f6…` and first-durable is now `woody-weed-bot`; per harness source the GUI's real default is `recentWorkspace` (freshest session activity = this one), so the field is cosmetic — but it must be re-checked after every registry mutation |
| Evidence directory and artifact conventions | **SATISFIED** | `README.md` §Repository layout; per-experiment dirs under `evidence/`, each with `ARTIFACT_HASHES.txt`; `ARTIFACT_MANIFEST.txt` at root; sha256-only transfer rule |
| Rollback and recovery procedure documented | **GAP → R1** | No rollback/recovery doc in `docs/`, `scripts/` (`handoff.sh` is a release-gate script for another repo, not a lab rollback path). Tags + manifests exist; the *procedure* does not |

## M1 — Ternary numeric core

| DoD item | Status | Evidence / note |
|---|---|---|
| Ternary numeric specs with invariants and tests | **SATISFIED (block scale)** | `specs/ternary/`: `trits.t27`, `ternary_mac.t27`, `trit_codon.t27`, `ternary_full_adder.t27`, `ternary_ripple_adder.t27`, `ternary_xor.t27` — repo law L4 requires tests in every `.t27` |
| GF16 datapath spec + bit-exact golden | **SATISFIED (for attention path)** | `specs/fpga/gf16_accel.t27` + `gf16_accel.v` + `testbench/gf16_accel_tb.*`; attention verified bit-exact vs CPU golden: 1,200 randomized trials, 0 mismatches (`evidence/attention_fix/attention_correction_report.json`); earlier 12,000-trial pack (`evidence/attention_token/`) |
| Measured accuracy/performance baselines | **SATISFIED** | Variance study across repeated cycle-1 runs (`evidence/variance_summary*.json`, README MEASURED table); board clocks 67.16/398.3 MHz (`evidence/clock_probe/`) |
| Regression tests for format edge cases | **PARTIAL → R4** | `benchmark/validate_benchmark.py` validates the co-design contract; a standalone TNF/GF16 *conformance pack* (spec → golden vectors → RTL match, versioned artifact) is not yet a single reproducible unit |

## M2 — Bit-exact hardware pipeline

| DoD item | Status | Evidence / note |
|---|---|---|
| Spec ↔ RTL ↔ testbench convention | **SATISFIED** | `specs/fpga/**` carries paired `.t27` + `.v` + `testbench/*_tb.v` for ~40 modules (adapter, axi4, fifo, gf16_accel, ternary_isa, …) |
| RTL matches software reference | **SATISFIED (attention)** | Corrected attention module: 5 defects found+fixed, 1,200 randomized Verilog trials vs CPU golden, 0 mismatches; KV-cache is a first-class co-design choice (`evidence/attention_fix/`, commit `edb5b95`) |
| Compiler emits Verilog from spec (`t27c`) | **GAP → R3** | `t27c` is absent from this lab. All `.v` files are hand/synth-written against the `.t27` spec; spec-first *enforcement* is by review, not by toolchain. The lab thesis "spec-first → bit-exact RTL" is not yet compiler-backed |
| No silent numeric divergence / fuzz | **PARTIAL** | Randomized-trial packs exist for attention; no repo-wide fuzz/conformance harness across all 40+ spec modules |

## M3 — FPGA implementation

| DoD item | Status | Evidence / note |
|---|---|---|
| Synthesis + P&R + timing/resource evidence | **SATISFIED** | Full open flow: yosys (`abc -lut 2`), nextpnr-xilinx/fasm2frames/xc7frames2bit, chipdb provenance hash-matched (`evidence/ax7203_build/chipdb_provenance.txt`); utilization (`evidence/utilization/`), critical-path isolation (`evidence/critical_path/`), Fmax noise audit (`evidence/fmax_noise/`) |
| Builds reproducibly | **SATISFIED** | Exact command sequence published in README §Reproducing this, incl. two recorded toolchain traps (LUT packing, CARRY4 routing) |
| Board-measured performance | **SATISFIED** | CFGMCLK 67.16 MHz (σ 1.33, n=9, second run agrees to 0.5%); R4/T4 oscillator 398.3 MHz with divide ratio experimentally confirmed first (`evidence/clock_probe/`) |
| Hardware smoke tests | **PARTIAL → R5** | Configuration-level smoke re-confirmed live 2026-11-23: JTAG detect `idcode 0x3636093`, shipped bitstream sha256-identical, SRAM load `isc_done 1 done 1`, XADC 41.9 °C / rails nominal (`evidence/board_reconnect/board_reconnect_2026-11-23.log`). **Functional** datapath smoke over UART/IP for the shipped demo bitstream: not yet done (the historical 512/512 UART run was a different bitstream) |
| Measured power | **GAP (tool-bound) → R6** | Vivado unavailable (AMD login wall, 3.9 GiB free disk); power = ESTIMATED only. XADC telemetry is the measured proxy |

## M4 — Tapeout readiness

| DoD item | Status | Evidence / note |
|---|---|---|
| Constraints under version control | **SATISFIED (board level)** | `specs/fpga/constraints/{arty_a7,qmtech_a100t}.xdc`, `evidence/ax7203_build/ax7203_attn.xdc` — FPGA package constraints, not ASIC IO/timing constraints |
| Architecture trade-offs documented | **PARTIAL** | README co-design results + `docs/LL1_RESOURCE_BUDGET.md`, `docs/LL1_TARGET_MODEL.md`; no consolidated trade-study doc |
| Risk register | **GAP → R6** | No risk register file (ASIC-facing risks, toolchain risks, single-board dependency) |
| Honest FPGA-proven vs ASIC-unproven separation | **SATISFIED** | README §Hard rules + WITHDRAWN/SUSPECT sections keep withdrawn claims in the record; no silicon language anywhere |

## M5 — Silicon-facing release

| DoD item | Status | Evidence / note |
|---|---|---|
| Tagged milestone line with hashes | **SATISFIED** | 19 tags, root `ARTIFACT_MANIFEST.txt` + per-dir `ARTIFACT_HASHES.txt`; artifact identity re-verified live today (bitstream sha256 match) |
| GitHub Release objects with rollback path | **GAP → R7** | No GitHub Releases on `gHashTag/t27-lamb-labs` (the pinned release `t27os-ladder-512k-caps` belongs to `Trinity-S-AI-DNA/t27`, not this lab). Rollback path per release = undocumented (ties to R1) |
| Regression suite | **PARTIAL** | `benchmark/validate_benchmark.py` + published reproduce commands; no single entrypoint that runs spec checks + benchmarks + evidence-hash verification in one command |
| Portfolio narrative | **SATISFIED** | `README.md` ("Scope, stated honestly") + `target/lamb_labs_evidence.md` dashboard |

---

## Gap register (candidate issues, none filed yet)

| ID | Gap | Milestone | Why it is real (DoD ref) |
|---|---|---|---|
| **R1** | Rollback & recovery procedure doc (per release: artifact, sha256, restore command) | M0/M5 | M0 DoD bullet 5; DONE_WHEN 5 |
| **R3** | `t27c` spec-first compiler path: emit Verilog from a `.t27` spec and prove bit-exactness on conformance vectors | M2 | DONE_WHEN 1–3; the lab's core thesis |
| **R4** | Standalone TNF/GF16 conformance pack (spec + golden vectors + RTL-match artifact, one command) | M1 | M1 DoD bullet 4 |
| **R5** | Functional hardware smoke for the shipped demo bitstream (UART/IP), board is connected now | M3 | M3 DoD bullet 4; DONE_WHEN 4 |
| **R6** | Risk register + measured-power upgrade path (Vivado access or XADC-based methodology) | M4 | M4 DoD bullets 2–3 |
| **R7** | GitHub Release objects for the v0.1.x line with sha256 + rollback notes | M5 | DONE_WHEN 5 |

Deliberately **not** gaps: silicon/tapeout claims (none exist, none claimed — DONE_WHEN 9), DSH defaults (verified; cosmetic registry field documented above), secret hygiene (clean, artifact now committed as evidence).

## Live hardware status (2026-11-23)

AX7203 powered and answering on Digilent HS2 (serial 210512180081); shipped `ternary_mac_demo_top_200t.bit` loaded to SRAM successfully, `done 1`; XADC nominal. R5 is the natural next measurement while the board is up.
