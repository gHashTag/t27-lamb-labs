# t27-lamb-labs

**Lamb Labs — ternary transformer research on Kria-class FPGA (AX7203).**

This repository isolates the FPGA / ternary-MAC / variance-measurement work
from the main `t27` repository. It is a self-contained
research repo: bitstream, evidence, toolchain configs, and specs live here.

---

## Positioning

**First reproducible ternary MAC variance study on Kria-class FPGA (AX7203),
zero-DSP, edge-scale.**

We do **not** claim to run TinyLlama-1.1B on Kria. The honest scope is a
**tiny ternary transformer block (1–2M parameters)** on XC7A200T, with
variance measured across repeated cycle-1 runs.

---

## What is measured (not claimed)

| Metric | Status | Evidence |
|---|---|---|
| Power measurement | MEASURED | 60 samples, `power_log.csv`, SHA256 `323c735d...` |
| UDP benchmark | MEASURED | 10/10 successes, `udp_log.json`, SHA256 `80bdaf2e...` |
| Variance rerun (FPGA) | MEASURED | 5/5 cycle-1 runs, SHA256 in `evidence/variance_rerun/` |
| Bitstream flashed | MEASURED | `ternary_mac_demo_top_200t.bit` (ternary MAC) |
| Toolchain | VERIFIED | yosys, fasm2frames, xc7frames2bit, openFPGALoader v0.13.1 |

All performance numbers are **MEASURED**, not TARGET. Nothing is claimed
beyond what the artifacts show.

---

## Variance protocol (first-class artifact)

No prior ternary-FPGA work in our survey publishes variance as a separate,
auditable artifact. We do.

Per run we record:
- seed
- timestamp
- environment (OS, tool versions)
- bitstream version (SHA256)
- raw log
- SHA256 of every artifact

Acceptance rule: a transfer/run is accepted **only on a matching SHA256**,
never on file size.

Reference CV% from literature: latency 0.8–1.2%, energy 1.5–2.1%
(FPGA RISC-V extensions study, arXiv:2511.06955). We report our own CV%
alongside this baseline.

---

## Zero-DSP ternary MAC

The ternary MAC is implemented without DSP blocks (LUT-based sign-select +
adder tree), consistent with the approach in ELiTeFormer (bitmasking) and
RTN (Boolean ops).

To be measured and documented:
- LUT vs DSP utilization in `ternary_mac_demo_top_200t.bit`
- MACs/sec
- power
- latency per MAC
- comparison vs TeLLMe (52,094 LUTs, 9.51 tok/s, 7 W on Kria KV260)

Claim: **"zero-DSP ternary MAC with measured variance on AX7203."**

---

## Edge-scale honest baseline

We keep the scope at **1–2M parameters**, not TinyLlama-1.1B.

Reference points (not our claims, literature baselines):
- TeLLMe (Kria KV260): 0.7B @ 9.51 tok/s, 7 W
- PENSA (Alveo U50, HBM): BitNet b1.58 2B4T end-to-end
- TerEffic: 6× power efficiency vs BitNet on 7B

We publish a scaling relation: **params vs tok/s vs power on AX7203**,
within our honest 1–2M scope.

---

## Repository layout

t27-lamb-labs/
├── bitstream/
│ └── ternary_mac_demo_top_200t.bit
├── docs/
│ ├── LL1_RESOURCE_BUDGET.md
│ └── LL1_TARGET_MODEL.md
├── evidence/
│ ├── artifact_run_1-5.json
│ ├── variance_summary.json
│ ├── ARTIFACT_HASHES.txt
│ └── run_1-5.log
├── specs/
│ ├── variance_ingest.t27
│ ├── power_ingest.t27
│ ├── udp_ingest.t27
│ ├── research_ingest.t27
│ ├── fpga/
│ └── ternary/
├── toolchain/
│ ├── oss-cad-suite/
│ ├── prjxray/
│ └── openfpgaloader/
├── scripts/
│ └── handoff.sh
└── README.md

---

## DO NOT (hard rules)

- Do **not** claim "TinyLlama fully on Kria".
- Do **not** claim "10–15 tokens/sec measured".
- Do **not** claim "80–120 J/token measured".
- Do **not** accept a transfer on size alone — SHA256 only.
- Do **not** mix Lamb Labs artifacts with other project artifacts.

---

## Current status

- Variance gate: **CLOSED** (5/5 cycle-1 runs, SHA256 verified)
- Power gate: **CLOSED**
- UDP gate: **CLOSED**
- Next: formalize variance protocol as first-class artifact, profile
  zero-DSP, publish edge-scale baseline.

**CLAIMED_READY = INVALID** until the variance protocol is formalized and
the zero-DSP profile is measured.
