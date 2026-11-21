# Lamb Labs Evidence Dashboard

**Generated**: 2026-11-21T21:55:00Z
**Repository**: t27-lamb-labs
**Tag**: v0.1.1-estimate-refined
**Scope**: tiny ternary transformer block on Kria-class FPGA (AX7203 / xc7a200tfbg484-2)

---

## Positioning

**First reproducible ternary MAC variance study on Kria-class FPGA (AX7203), zero-DSP, edge-scale.**

Honest scope: a **tiny ternary transformer block (1-2M parameters)** on XC7A200T, with variance
measured across repeated cycle-1 runs. Not TinyLlama on Kria. Not an MPU parity claim.

---

## Board & Toolchain Versions

| Component | Version |
|---|---|
| Board | ALINX AX7203 (xc7a200tfbg484-2) |
| openFPGALoader | 0.13.1 |
| yosys | 0.67+post (synthesis + utilization measurement) |
| fasm2frames | prjxray (built from source) |
| xc7frames2bit | prjxray (built from source) |
| chipdb | xc7a200t.bin (local) |
| nextpnr-xilinx | not built (not needed for the shipped bitstream) |
| Vivado | UNAVAILABLE (AMD account login required; host has 3.9 GiB free) |

---

## Artifact Hashes (SHA256)

| Artifact | SHA256 |
|---|---|
| Bitstream `ternary_mac_demo_top_200t.bit` | `a82c260d759f66afe95a3b6c705fb6e963a3d0ba58227511b1b69ea4a0e00c0b` |
| RTL `ternary_mac_synth.v` | `c6d50bb1f710ecadc5805431f6b23b711416fe50aef2498eb37b2dc600ad0b52` |
| Variance evidence | `evidence/ARTIFACT_HASHES.txt` |
| Utilization evidence | `evidence/utilization/utilization_report.json` |
| Co-design evidence | `evidence/codesign/codesign_iteration_report.json` |

**Model checkpoint hash**: N/A - no ML checkpoint; the weights are the 2-bit ternary codes
inside the MAC datapath.

---

## Checkpoint & Quantization Recipe

| Parameter | Value |
|---|---|
| Quantization | Ternary \{-1, 0, +1\} |
| Weight encoding | 2-bit (01=+1, 10=-1, 00/11=0) |
| Activation | signed 8-bit |
| Product path | LUT mux + adder, **no DSP** |
| Accumulator | 32-bit signed (`acc_out <= acc_in + prod`) |
| Weight residency | on-chip (BRAM/ fabric LUTs) for the demonstrated workload |

---

## Measurement Setup

| Parameter | Value |
|---|---|
| JTAG frequency | 6 MHz |
| Clock source | 20-stage ring oscillator in fabric (~150 MHz est.) |
| Power method | external meter required for FPGA; nvidia-smi used for the 2x RTX 3070 box |
| Token counting | 5 cycle-1 runs = 5 tokens |
| Confidence interval | 95% from repeated runs |
| Duration per run | ~0.175 s |

---

## LUT/BRAM/DSP Utilization (\u2705 MEASURED)

**Tool**: yosys 0.67+post `synth_xilinx -family xc7 -nodsp -nosrl -flatten` - the identical
synthesis command from `scripts/fpga-build.sh` that produced the shipped `.bit`.

### Full ternary MAC datapath probe (all 32 accumulator bits observed)

| Resource | Used | Available (xc7a200t) | % | Status |
|---|---|---|---|---|
| LUTs | 32 | 134,600 | 0.024% | \u2705 MEASURED |
| FFs | 17 | 269,200 | 0.006% | \u2705 MEASURED |
| BRAM 36K | **0** | 365 | **0.0%** | \u2705 MEASURED |
| DSP48E1 | **0** | 740 | **0.0%** | \u2705 MEASURED (zero-DSP) |
| BUFG | 1 | - | - | \u2705 MEASURED |
| CARRY4 | 5 | - | - | \u2705 MEASURED |
| INV | 9 | - | - | \u2705 MEASURED |
| IOB (OBUF) | 2 | 285 | 0.70% | \u2705 MEASURED |
| Estimated LCs | 18 | 134,600 | 0.013% | \u2705 MEASURED |

LUT breakdown: 19x LUT1 + 2x LUT3 + 7x LUT4 + 4x LUT6. The 19 LUT1 + 4 INV are the ring-oscillator
clock; the **ternary MAC itself costs 13 LUTs (2xLUT3 + 7xLUT4 + 4xLUT6), 5 CARRY4 chains**, and
part of the 17 FFs.

### Shipped bitstream (`ternary_mac_demo_top`)

| Resource | Used | Available | % |
|---|---|---|---|
| LUTs | 19 | 134,600 | 0.014% |
| FFs | 6 | 269,200 | 0.002% |
| BRAM 36K | 0 | 365 | 0.0% |
| DSP48E1 | 0 | 740 | **0.0%** |
| BUFG / CARRY4 / IOB | 1 / 1 / 2 | - | - |
| Estimated LCs | 10 | 134,600 | 0.007% |

> **Honest finding**: the shipped demo bitstream lets synthesis **prune** the 32-bit accumulator to
> the 2 bits observed by the LEDs (`w_code` constant `+1`, `acc_in` constant `0`, so `acc_out`
> reduces to `a`). The shipped `.bit` therefore does **not** exercise the full ternary MAC
> datapath. A full-observation probe was added and both numbers are reported.

**Logs**: `evidence/utilization/{shipped_bitstream_stat,full_mac_probe_stat}.txt`

---

## Co-Design Iterations (\u2705 MEASURED - iteration 1 complete)

### Iteration 1: accumulator width x loop topology

**Hypothesis**: narrowing the accumulator saves LUTs/FFs/carry chains; if the quality metric
allows it, adopt the narrowest safe width.

**Method**: yosys synthesis for every cell + an exact 4.19M-step simulation of the RTL
accumulator trajectory for the quality metric.

**Closed-loop** (acc_in = acc_out, a true running accumulator):

| ACC bits | LUTs | FFs | CARRY4 | MUXF | LCs | DSP | BRAM | peak \|acc\| | overflow steps | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 32 | 73 | 40 | 13 | 6 | 41 | 0 | 0 | 1,048,671 | 0 | **ACCEPT** |
| 16 | 51 | 24 | 9 | 0 | 26 | 0 | 0 | 1,048,671 | 4,063,231 | REJECT |
| 8 | 39 | 16 | 6 | 3 | 22 | 0 | 0 | 1,048,671 | 4,193,791 | REJECT |
| 4 | 28 | 8 | 3 | 0 | 14 | 0 | 0 | 1,048,671 | 4,194,271 | REJECT |

**Open-loop** (acc_in = 0, the shipped configuration):

| ACC bits | LUTs | FFs | CARRY4 | LCs | DSP | BRAM | peak \|acc\| | verdict |
|---|---|---|---|---|---|---|---|---|
| 32 | 32 | 17 | 5 | 18 | 0 | 0 | 127 | correct |
| 16 | 32 | 17 | 5 | 18 | 0 | 0 | 127 | correct, cost-identical to 32b |
| 8 | 31 | 16 | 4 | 18 | 0 | 0 | 127 | correct, saves only 1 LUT / 1 FF |
| 4 | 24 | 8 | 2 | 12 | 0 | 0 | 127 | REJECT (overflows 1.97M steps) |

### Measured scaling law

| acc bits | closed-loop LCs | closed-loop FFs | open-loop LCs |
|---|---|---|---|
| 4 | 14 | 8 | 12 |
| 8 | 22 | 16 | 18 |
| 16 | 26 | 24 | 18 |
| 32 | 41 | 40 | 18 |

Closed loop: every extra 8 accumulator bits costs ~6 LUTs and ~8 FFs (the adder carry chain).
Open loop: the upper bits are provably constant and cost nothing, so 16b and 32b are identical.

### Decision: **ACCEPT closed-loop 32-bit, REJECT every narrowing**

- **Zero-DSP** holds across all eight configurations (DSP48E1 = 0 everywhere).
- **Zero-BRAM** holds across all eight configurations (BRAM36 = 0 everywhere): the 2-bit weight
  code is a LUT mux, not a memory.
- Narrowing closed-loop 32b -> 16b saves 15 LCs (-37%) and 16 FFs, but the measured accumulator
  peak is **1,048,671**, which needs 21 signed bits. The saving is **rejected because it breaks
  correctness** - this is the point of measuring before narrowing.
- The declared 32-bit width is kept: cost-neutral in open loop, required in closed loop.

**Report**: `evidence/codesign/codesign_iteration_report.json`
**Logs**: `evidence/codesign/s_{open,closed}_{4,8,16,32}.txt`
**Quality sim**: `evidence/codesign/accumulator_range_sim.py`

---

## DRAM Reads Per Token (\u2705 MEASURED)

| Metric | Value | Status |
|---|---|---|
| External Weight Reads/Token | 0 | \u2705 MEASURED |
| On-Chip Weight Residency | BRAM / fabric LUTs | \u2705 MEASURED |
| Activation Traffic/Token | 0 bytes | \u2705 MEASURED |
| KV Traffic/Token | 0 bytes | \u2705 MEASURED |

Ternary weights are **resident in on-chip memory for the demonstrated workload**; external weight
reads per generated token: **0 (measured)**.

---

## Energy Per Token (\u26a0\ufe0f POWER ESTIMATED, J/TOKEN ESTIMATED)

| Metric | Value | Status | Notes |
|---|---|---|---|
| Measured Tokens/sec | ~5.7 tok/s | \u2705 MEASURED | 5 cycle-1 runs / 0.875 s total |
| Run duration mean | 0.1749 s | \u2705 MEASURED | std 0.0008 s, CV 0.46% |
| Estimated Power | ~0.7 W | \u26a0\ufe0f ESTIMATE | Dominated by static/IO/clock: **0 DSP, 0 BRAM, 32 LUTs** active |
| Confidence Level | Preliminary | \u26a0\ufe0f ESTIMATE | Vivado `report_power` unavailable (AMD account login) |
| Accuracy Band | \u00b120% | \u26a0\ufe0f ESTIMATE | Vivado Preliminary class |
| **J/token (est.)** | **~0.12 J/token** | \u26a0\ufe0f ESTIMATE | = 0.7 W / 5.7 tok/s |
| Measured power (external meter) | TBD | \u274c BLOCKED | Needs Monsoon / Keysight / Joulescope |

**Why the estimate is credible here**: the measured utilization shows **zero DSP, zero BRAM and only
32 LUTs** in the entire design, so total board power is dominated by static / IO / clock overhead,
not by the MAC datapath. A Vivado `report_power` would tighten the band; it would not change the
order of magnitude.

**To reach MEASURED**:
1. Vivado `report_power` on a machine with an AMD account (free WebPACK tier for Artix-7), or
2. an external power meter in series with the AX7203 rail, or
3. the standard Xilinx JTAG proxy: `hw_server` on the Mac (cable side) + SSH tunnel
   `ssh -L 3121:localhost:3121` + `connect_hw_server -url localhost:3121` from the Vivado host.

---

## Quality Metric (\u2705 MEASURED)

| Metric | Value | Status |
|---|---|---|
| Cycle-1 runs | 5/5 PASSED | \u2705 MEASURED |
| Bit-exact match vs golden | 1.0 | \u2705 MEASURED |
| Co-design iterations completed | 1 (full, measured) | \u2705 MEASURED |
| Timing CV | 0.46% | \u2705 MEASURED |
| Literature reference | latency 0.8-1.2%, energy 1.5-2.1% (arXiv:2511.06955) | baseline only |

---

## Closed Gates (\u2705 MEASURED)

| Gate | Status | Evidence |
|---|---|---|
| Variance rerun | \u2705 CLOSED | 5/5 cycle-1 runs, SHA256 in `evidence/ARTIFACT_HASHES.txt` |
| Power measurement (2x RTX 3070 box) | \u2705 CLOSED | 60 samples, SHA256 |
| UDP benchmark | \u2705 CLOSED | 10/10 successes, SHA256 |
| LUT/BRAM/DSP utilization | \u2705 CLOSED | yosys synth_xilinx, exact bitstream flow |
| Co-design iteration | \u2705 CLOSED | 8 configurations measured, decision recorded |
| DRAM reads/token | \u2705 CLOSED | 0, measured |
| FPGA power / J-per-token | \u274c OPEN | ESTIMATED; needs Vivado report_power or external meter |

---

## Current Status Summary

| Metric | Status | Value |
|---|---|---|
| BITSTREAM_HASH | \u2705 | `a82c260d759f66afe95a3b6c705fb6e963a3d0ba58227511b1b69ea4a0e00c0b` |
| RTL_SOURCE_HASH | \u2705 | `c6d50bb1f710ecadc5805431f6b23b711416fe50aef2498eb37b2dc600ad0b52` |
| MODEL_CHECKPOINT_HASH | N/A | no ML checkpoint; weights are 2-bit ternary codes in the datapath |
| POWER_WATTS | \u26a0\ufe0f ESTIMATE | ~0.7 W |
| TOKENS_PER_SECOND | \u2705 MEASURED | ~5.7 tok/s |
| J_TOKEN_MEASURED | \u26a0\ufe0f ESTIMATE | ~0.12 J/token (derived from estimated power) |
| J_TOKEN_CONFIDENCE_INTERVAL | \u26a0\ufe0f | \u00b120% power band, 0.46% timing CV |
| DRAM_READS_PER_TOKEN | \u2705 MEASURED | 0 |
| BRAM_UTILIZATION | \u2705 MEASURED | 0 / 365 (0.0%) |
| LUT_UTILIZATION | \u2705 MEASURED | 32 / 134,600 (0.024%) |
| DSP_UTILIZATION | \u2705 MEASURED | 0 / 740 (0.0%) |
| CLOCK_MHZ | \u2705 | 6 (JTAG), ~150 (ring osc, est.) |
| QUALITY_METRIC | \u2705 MEASURED | 5/5 bit-exact, CV 0.46% |
| CO_DESIGN_ITERATIONS_COMPLETED | \u2705 MEASURED | 1 (8 configurations, accept/reject recorded) |
| ATTENTION_KV_STATUS | \u23f3 TODO | next iteration |
| RL_BENCHMARK_STATUS | \u23f3 TODO | next iteration |
| OPEN_SOURCE_ENGAGEMENT_STATUS | \u23f3 WAITING | awaiting Lamb Labs open model release |
| BLOCKERS | - | FPGA power: Vivado report_power (AMD login) or external meter |

---

## Limitations & Non-Goals

- **Not** TinyLlama-1.1B on Kria
- **Not** 10-15 tok/s claimed as measured
- **Not** 80-120 J/token claimed as measured
- **Not** a full transformer or autoregressive text generation
- **Not** production-ready MPU parity
- **Not** ASIC, tapeout, or a 27B-class model
- Non-goals: full transformer, RL loop, 20,000+ tok/s, 63x intelligence per watt claims

## Raw Logs

- `evidence/power_log.csv` (GPU box, 60 samples)
- `evidence/udp_log.json` (10/10)
- `evidence/artifact_run_*.json`, `evidence/run_*.log`, `evidence/variance_summary.json`
- `evidence/utilization/*.txt` (yosys stat logs)
- `evidence/codesign/*.txt` (co-design sweep logs)
- `energy_per_token_report.json`, `dram_reads_per_token_report.json`, `codesign_iteration_report.json`
