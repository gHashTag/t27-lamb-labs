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
| Rollback and recovery procedure documented | ~~GAP → R1~~ **SATISFIED (2026-11-23, owner verification pending)** | `docs/ROLLBACK_RECOVERY.md` committed + **every command executed once** against live repo/board: tag restore 9,730,768 B, SHA256 gate PASS (== manifest row 11), SRAM load `done 1`, manifest integrity 0 real mismatches. `evidence/rollback_recovery/rollback_recovery_2026-11-23.log` |

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
| Builds reproducibly | **SATISFIED (recovered 2026-11-23, owner verification pending)** | R8 gap closed by recovery: `rtl/ternary_mac_demo_top.v` + `rtl/ternary_mac_demo_top.xdc` recovered byte-exact from the original working repo (`/Users/playra/t27/fpga/verilog/`), provenance chain hash-verified end-to-end (recovered `.bit` on disk = shipped `a82c260d…` byte-identical; core = committed `c6d50bbf…`). Rebuild proof with the recorded yosys flow: stat EXACT match + semantic netlist identity (0 differing net bits, 23/23 shared cells identical, only yosys session-counter renames) — `evidence/recovery_demo_top/recovery_2026-11-23.log`. Honest limits recorded there: XDC targets Wukong pins (R23/T23 ≠ AX7203 B13/C13 LEDs); ring-osc clock probe-verified dead, so the shipped .bit proves loadability, not datapath behaviour; byte-level .bit re-cut deferred (no nextpnr/xc7frames2bit on this host). Flow + chipdb provenance as before |
| Board-measured performance | **SATISFIED** | CFGMCLK 67.16 MHz (σ 1.33, n=9, second run agrees to 0.5%); R4/T4 oscillator 398.3 MHz with divide ratio experimentally confirmed first (`evidence/clock_probe/`) |
| Hardware smoke tests | **PARTIAL → R5** | Configuration-level smoke re-confirmed live 2026-11-23: JTAG detect `idcode 0x3636093`, shipped bitstream sha256-identical, SRAM load `isc_done 1 done 1`, XADC 41.9 °C / rails nominal (`evidence/board_reconnect/board_reconnect_2026-11-23.log`). **Functional** datapath smoke over UART/IP for the shipped demo bitstream: not yet done (the historical 512/512 UART run was a different bitstream) |
| Measured power | **GAP (tool-bound) → R6** | Vivado unavailable (AMD login wall, 3.9 GiB free disk); power = ESTIMATED only. XADC telemetry is the measured proxy |

## M4 — Tapeout readiness

| DoD item | Status | Evidence / note |
|---|---|---|
| Constraints under version control | **SATISFIED (board level)** | `specs/fpga/constraints/{arty_a7,qmtech_a100t}.xdc`, `evidence/ax7203_build/ax7203_attn.xdc` — FPGA package constraints, not ASIC IO/timing constraints |
| Architecture trade-offs documented | **PARTIAL** | README co-design results + `docs/LL1_RESOURCE_BUDGET.md`, `docs/LL1_TARGET_MODEL.md`; no consolidated trade-study doc |
| Risk register | ~~GAP → R6~~ **SATISFIED (2026-11-23, owner verification pending)** | `docs/RISK_REGISTER.md`: 10 rows (S×L, mitigation, evidence pointers) incl. fresh R4/T4 marginality; power methodology DECIDED: XADC-differential = MEASURED proxy w/ observed-repeatability error bars, watts unpublished until shunt/Vivado path |
| Honest FPGA-proven vs ASIC-unproven separation | **SATISFIED** | README §Hard rules + WITHDRAWN/SUSPECT sections keep withdrawn claims in the record; no silicon language anywhere |

## M5 — Silicon-facing release

| DoD item | Status | Evidence / note |
|---|---|---|
| Tagged milestone line with hashes | **SATISFIED** | 19 tags, root `ARTIFACT_MANIFEST.txt` + per-dir `ARTIFACT_HASHES.txt`; artifact identity re-verified live today (bitstream sha256 match) |
| GitHub Release objects with rollback path | **GAP → R7** | No GitHub Releases on `gHashTag/t27-lamb-labs` (the pinned release `t27os-ladder-512k-caps` belongs to `Trinity-S-AI-DNA/t27`, not this lab). Rollback path per release = undocumented (ties to R1) |
| Regression suite | **PARTIAL** | `benchmark/validate_benchmark.py` + published reproduce commands; no single entrypoint that runs spec checks + benchmarks + evidence-hash verification in one command |
| Portfolio narrative | **SATISFIED** | `README.md` ("Scope, stated honestly") + `target/lamb_labs_evidence.md` dashboard |

---

## Gap register → GitHub issues (filed 2026-11-23, repo milestones #1–#6)

| ID | Issue | Gap | Milestone |
|---|---|---|---|
| **R1** | [#1](https://github.com/gHashTag/t27-lamb-labs/issues/1) | Rollback & recovery procedure doc | M0 (#1) |
| **R4** | [#2](https://github.com/gHashTag/t27-lamb-labs/issues/2) | Standalone TNF/GF16 conformance pack | M1 (#2) |
| **R3** | [#3](https://github.com/gHashTag/t27-lamb-labs/issues/3) | `t27c` spec-first compiler emit path | M2 (#3) |
| **R8** | [#4](https://github.com/gHashTag/t27-lamb-labs/issues/4) | ~~Recover/commit `ternary_mac_demo_top.v` + XDC~~ **RECOVERED 2026-11-23**: `rtl/*` committed byte-exact, rebuild proof = stat match + netlist identity (`evidence/recovery_demo_top/`); owner verification pending | M3 (#4) |
| **R5** | [#5](https://github.com/gHashTag/t27-lamb-labs/issues/5) | Functional hardware smoke (no UART on shipped top; plan needed first) | M3 (#4) |
| **R6** | [#6](https://github.com/gHashTag/t27-lamb-labs/issues/6) | Risk register + measured-power upgrade path | M4 (#5) |
| **R7** | [#7](https://github.com/gHashTag/t27-lamb-labs/issues/7) | GitHub Release objects with sha256 + rollback notes | M5 (#6) |

Every issue carries explicit acceptance criteria and the owner-verification-before-close law. Deliberately **not** gaps: silicon/tapeout claims (none exist, none claimed — DONE_WHEN 9), DSH defaults (verified; cosmetic registry field documented above), secret hygiene (clean, artifact committed as evidence).

## Live hardware status (2026-11-23)

AX7203 powered and answering on Digilent HS2 (serial 210512180081). 2026-11-23 functional smoke (`evidence/functional_smoke_2026-11-23/`): CFGMCLK-domain live datapath PROVEN (magic 10/10, counter >10⁶ ticks, 66.88 MHz in band); R4/T4 probe counter FROZEN (fail C6) — board-clock liveness on R4/T4 not demonstrated today, 2026-11-22 ~398 MHz numbers stay NOT PUBLISHED. R5 full completion still blocked on missing nextpnr/xc7frames2bit (route (b) UART smoke) and on a Johnson-prescaler rebuild (corrected R4/T4 probe).
