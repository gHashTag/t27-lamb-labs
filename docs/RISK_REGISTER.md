# Risk Register — t27-lamb-labs

Issue: #6 [R6] · M4. Every row: severity × likelihood, mitigation, status, evidence pointer.
Convention: **S**everity and **L**ikelihood in {LOW, MED, HIGH}; every claim links to a
committed artifact. No silicon/foundry claims anywhere (law DONE_WHEN 9).

| # | Risk | S | L | Mitigation / control | Status & evidence |
|---|---|---|---|---|---|
| 1 | **Single-board dependency.** All measured hardware evidence flows through ONE AX7203 (serial 210512180081). Board loss invalidates the hardware leg until a replacement is validated. | HIGH | MED | Board-independent evidence legs maintained: yosys/sim packs, semantic netlist proofs, committed probe RTL; `docs/ROLLBACK_RECOVERY.md` makes any new board bootstrap a procedure, not an adventure. Second USB-serial node (`/dev/cu.usbserial-1130`) present, unprobed. | OPEN (structural). `evidence/board_reconnect/`, `evidence/rollback_recovery/` |
| 2 | **openXC7 placer CARRY4 trap.** The placer splits CARRY chains across non-adjacent slices; designs with carry-chain counters were unroutable at every seed tried. | HIGH | HIGH (without workaround) | Recorded design rule: plain-FF ripple counters or one-level Johnson prescalers; no CARRY4 in probe-family designs. | MITIGATED (design rule). `evidence/clock_probe/clock_probe_ctrl.v` header (WHY NO CARRY CHAIN), `r4t4_measurement.log` |
| 3 | **LUT-packing trap** (recorded in README §Reproducing this): specific packing order required for routability. | MED | MED | Documented in README with the recorded workaround; treated as a reproducibility constraint, not a mystery. | MITIGATED (documented). README |
| 4 | **Chipdb provenance.** Placement chipdb `xc7a200tfbg484-2.bin` (333,207,792 B, md5 `59f828c4…`) was built on the Railway lab machine and is NOT committed (size). Die-level `fbg676` chipdb resolved the shipped demo — pin-resolution quirks possible for off-die packages. | MED | MED | Hash recorded in `fpga/HARDWARE_SSOT.md` (parent repo); die-vs-package quirk recorded as SUSPECT-cosmetic after live IDCODE load. Any local rebuild must re-derive and re-hash before use. | OPEN (needs local rebuild or a committed, hash-verified binary). `docs/M0_M5_CAPABILITY_MAP.md`, R8 log |
| 5 | **R4/T4 clock marginality.** Board's 200 MHz differential oscillator probe (`clock_probe_r4t4b.bit`) showed a FROZEN counter in the 2026-11-23 replication (magic OK, count 0, 10/10) while 2026-11-22 runs implied ~398 MHz with an unvalidated divide ratio. Ripple prescaler feedback does not settle in 5 ns — metastability-dependent behaviour. | HIGH | MED | R4/T4 numbers remain **NOT PUBLISHED**; any future probe must use a Johnson prescaler (recorded fix). Do not cite R4/T4 frequency anywhere until a settled-feedback probe reproduces it. | OPEN (rebuild blocked on PnR tools). `evidence/functional_smoke_2026-11-23/verdict.txt` C6 |
| 6 | **Toolchain availability.** No Vivado (AMD login wall; ~3.9 GiB free disk historically), no nextpnr-xilinx/fasm2frames/xc7frames2bit on this host → no NEW bitstreams, no byte-level re-cut, no report_power. | HIGH | CURRENT | yosys-only proof tier (stat + semantic netlist identity) established as the honest fallback (R8). Unblocking requires the openXC7 flow install or GPU-box rebuild — owner decision pending. | OPEN (owner decision). `evidence/recovery_demo_top/recovery_2026-11-23.log`, R8 issue comment |
| 7 | **Power unknowns.** No current measurement path exists on this board as-used; XADC gives die temp + rails only. No watt number may be published. | MED | CERTAIN | Methodology decision below: XADC-differential as MEASURED activity proxy with observed-repeatability error bars; watts require inline shunt (owner hardware) or Vivado report_power (blocked). Until then: zero watt claims. | MITIGATED BY DECISION (below) |
| 8 | **FPGA-proven vs ASIC-unproven boundary.** Everything in this lab is FPGA + simulation evidence. Nothing has reached silicon; tapeout is not claimed anywhere. Risk: narrative drift ("chip" language). | HIGH | MED if unwatched | Law DONE_WHEN 9 + ledger discipline: every doc labels provenance (MEASURED / SIMULATED / SPEC-VERIFIED / NOT-PUBLISHED / WITHDRAWN). `target/lamb_labs_evidence.md` ledger; withdrawals preserved (ring-osc clock, 5.7 tok/s, CV). | CONTROLLED (continuous). `evidence/clock_probe/shipped_bitstream_analysis.log`, ledger |
| 9 | **Evidence integrity / silent rewrites.** Withdrawn or failed results must stay visible; a clean tree must not mean a curated one. | MED | LOW | Every failure mode committed (smoke FAIL C6, frozen R4/T4, reader-layout defect). Verdict files state FAIL in the first line. | CONTROLLED. `evidence/functional_smoke_2026-11-23/` |
| 10 | **Secret hygiene.** dsh.json/.env/keys entering git, logs, or release assets. | HIGH | LOW | Full-history scan CLEAN (2026-11-23, 669 blobs / 28 commits, 1 reviewed false positive); .gitignore active; scan re-run required before any release (R7 gate). | CONTROLLED. `evidence/security/secret_scan_2026-11-23.log` |

## Power methodology decision (recorded 2026-11-23)

**Decision: XADC-differential telemetry is the adopted MEASURED proxy; watts stay
unpublished until an inline-current or Vivado path exists.**

- **MEASURED (adopted):** XADC die temp, vccint, vccaux per load state, with the
  **observed repeatability** as the error bar — NOT vendor accuracy, NOT calibration:
  today's reads: temp 42.0535 / 42.3477 °C (spread ≈ 0.29 °C across loads),
  vccint 0.999023 / 0.999756 V, vccaux 1.80396 V (constant across reads).
  Interpretation rule: deltas inside the observed spread are NOISE, not activity.
  Every such number is labelled **MEASURED (XADC, repeatability error bar as stated;
  absolute accuracy not independently calibrated on this board)**.
- **ESTIMATED:** none published. Vivado `report_power` remains unavailable (AMD login
  wall) — recorded as the alternate ESTIMATED path if access is ever obtained.
- **MEASURED watts (future):** inline series shunt + DMM/scope on the board supply —
  requires owner hardware action; becomes the only path to real watt numbers.
- Enforcement: any published number failing this labelling is a law violation
  (README hard rules, DONE_WHEN 9).
