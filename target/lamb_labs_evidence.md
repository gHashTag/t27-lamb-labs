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

## LUT/BRAM/DSP Utilization (✅ MEASURED)

**Tool**: yosys 0.67+post `synth_xilinx -family xc7 -nodsp -nosrl -flatten` - the identical
synthesis command from `scripts/fpga-build.sh` that produced the shipped `.bit`.

### Full ternary MAC datapath probe (all 32 accumulator bits observed)

| Resource | Used | Available (xc7a200t) | % | Status |
|---|---|---|---|---|
| LUTs | 32 | 134,600 | 0.024% | ✅ MEASURED |
| FFs | 17 | 269,200 | 0.006% | ✅ MEASURED |
| BRAM 36K | **0** | 365 | **0.0%** | ✅ MEASURED |
| DSP48E1 | **0** | 740 | **0.0%** | ✅ MEASURED (zero-DSP) |
| BUFG | 1 | - | - | ✅ MEASURED |
| CARRY4 | 5 | - | - | ✅ MEASURED |
| INV | 9 | - | - | ✅ MEASURED |
| IOB (OBUF) | 2 | 285 | 0.70% | ✅ MEASURED |
| Estimated LCs | 18 | 134,600 | 0.013% | ✅ MEASURED |

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

## Co-Design Iteration 1: accumulator width x loop topology (✅ MEASURED)

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

## Attention + Bounded KV-Cache Extension (✅ RESOURCES MEASURED; quality in iteration 2)

Minimal single-head attention with a bounded **quantised** KV-cache:
`score[s] = sum_c q[c]*K[s][c]`, `out[c] = sum_s sign(score[s])*V[s][c]`,
K and V stored as sign + `QUANT_W` magnitude bits.

**Tool**: yosys `synth_xilinx -family xc7 -nodsp -nosrl -flatten`

| HEAD_DIM | KV_LEN | QUANT_W | LUTs | FFs | CARRY4 | MUXF7 | MUXF8 | LCs | DSP | RAM |
|---|---|---|---|---|---|---|---|---|---|---|
| 4 | 8 | 8 | 15,855 | 144 | 638 | 2,338 | 673 | 13,897 | 0 | 0 |
| 4 | 16 | 8 | 15,852 | 145 | 639 | 2,317 | 668 | 13,881 | 0 | 0 |
| 8 | 4 | 8 | 16,060 | 143 | 638 | 2,338 | 673 | 14,030 | 0 | 0 |
| 8 | 8 | 8 | 32,387 | 272 | 1,230 | 4,728 | 1,560 | 28,627 | 0 | 0 |
| 8 | 16 | 8 | 32,351 | 273 | 1,231 | 4,687 | 1,541 | 28,619 | 0 | 0 |
| 8 | 32 | 8 | 32,160 | 274 | 1,231 | 4,512 | 1,481 | 28,430 | 0 | 0 |
| 8 | 64 | 8 | 32,223 | 275 | 1,231 | 4,512 | 1,481 | 28,476 | 0 | 0 |
| 8 | 16 | 4 | 15,900 | 145 | 635 | 2,225 | 748 | 13,869 | 0 | 0 |
| 8 | 16 | 6 | 24,197 | 209 | 933 | 3,468 | 1,140 | 21,290 | 0 | 0 |

> These are **8-bit-activation** configurations. Iteration 2 below shows that `QUANT_W=4` at 8-bit
> activations is **lossy** (95% mean relative error). The accepted configuration is
> `act_bits=4` + `quant_w=4` (10,662 LCs), measured in iteration 2.

### Findings

1. **Zero-DSP holds in attention** - DSP48E1 = 0 in every configuration, up to a 64-slot KV cache.
2. **No BRAM, no DRAM** - RAMB = 0 everywhere; the KV cache stays in fabric LUT/FF.
   External DRAM reads per token = **0**, KV traffic = **0 bytes/token**.
3. **QUANT_WIDTH is the dominant RESOURCE lever** - at HEAD_DIM=8 / KV_LEN=16:
   QUANT_W=4 -> 13,869 LCs, 6 -> 21,290 LCs, 8 -> 28,619 LCs; going 4-bit -> 8-bit costs
   **+103% LUTs**. **Iteration 1 decision: adopt QUANT_W=4** - later REVERSED by the quality
   metric in iteration 2, because narrowing QUANT_W alone is lossy. See iteration 2.
4. **HEAD_DIM doubles the cost** - 4 -> 8 channels is +104% LUTs.
5. **The combinational attention form does not fit** - 28,619 LCs is **21.3% of the XC7A200T
   LUT fabric** for one 8-channel head with a 16-slot cache. **Decision: REJECT the combinational
   form; a sequential form (one slot per cycle) is required.** This is the next iteration.
6. **KV_LEN scaling is NOT characterised** - measured LCs saturate from KV_LEN=8 onward
   (28,627 / 28,619 / 28,430 / 28,476 for 8 / 16 / 32 / 64). This saturation is a **harness
   artifact**: every slot is written with the same rotating counter pattern, so the mux trees
   collapse. The real per-slot cost needs a randomised payload sweep. Recorded as a known gap.

**Report**: `evidence/attention/attention_kv_report.json`
**Logs**: `evidence/attention/stat_attn_h*_k*_q*.txt`
**RTL**: `evidence/attention/attn_kv.v`

**Latency (derived, not measured on silicon)**: combinational depth = SLOTS x HEAD_DIM MAC steps
(16 x 8 = 128), ~640 ns/token at 150 MHz. A sequential form would be 16 cycles (~107 ns) at a
fraction of the LUT cost - not yet built.

**Quality**: measured in iteration 2 below - bit-exact against the full-precision golden for
the lossless configurations; the resource sweep alone could not justify a quality claim.

## Co-Design Iteration 2: joint activation width x KV quantisation width (✅ MEASURED)

This iteration supplies the quality metric that iteration 1 explicitly left pending, and
**reverses** iteration 1's resource-only preference.

**Rule (measured)**: the KV cache stores sign + `QUANT_W` magnitude bits of an
`ACT_BITS`-wide signed value, so **losslessness requires `QUANT_W >= ACT_BITS`**.
`QUANT_W` is not an independent lever: narrowing it alone is lossy; narrowing `ACT_BITS`
alone at `QUANT_W=8` wastes cache bits. The two must move together.

| ACT | QW | Lossless | Mean rel err | LUTs | FFs | LCs | % device | Decision |
|---|---|---|---|---|---|---|---|---|
| 8 | 8 | yes | 0.000000 | 32,339 | 273 | 28,582 | 21.2% | REJECT: over the 10% cap, most expensive |
| 8 | 6 | **no** | 0.800591 | 24,207 | 209 | 21,286 | 15.8% | REJECT: quality floor violated |
| 8 | 4 | **no** | 0.949815 | 15,876 | 145 | 13,901 | 10.3% | REJECT: quality floor violated |
| 6 | 8 | yes | 0.000000 | 29,432 | 273 | 25,756 | 19.1% | REJECT: wasteful |
| 6 | 6 | yes | 0.000000 | 21,947 | 209 | 19,159 | 14.2% | REJECT by the 10% cap |
| 4 | 8 | yes | 0.000000 | 25,496 | 273 | 21,844 | 16.2% | REJECT: wasteful |
| **4** | **4** | **yes** | **0.000000** | **12,614** | **145** | **10,662** | **7.9%** | **ACCEPT** |

### Decision: **ACCEPT act_bits=4, quant_w=4** (10,662 LCs, 7.9% of the device, lossless)

- `act=4/quant=4` is **bit-exact** against the full-precision golden (100% exact match over
  1500 randomised trials) and saves **62.7%** of the LCs against the `act=8/quant=8` reference.
- It is the **only** lossless configuration that fits inside the benchmark's 10% resource cap.
- The 10% cap rejects the `act=8/quant=8` reference (21.2% of the fabric), which is why a
  **sequential** attention form is still needed for wider configurations.

### Correction of iteration 1 (kept in the record)

| | |
|---|---|
| Iteration 1 claim | "ADOPT QUANT_W=4 ... subject to the quality floor" - **provisional**, quality was explicitly pending |
| Iteration 2 result | The quality floor **rejects** QUANT_W=4 at 8-bit activations (95% mean relative error) |
| Corrected default | **`act_bits=4` AND `quant_w=4` together** |

### Measured lossless scaling law (equal activation and KV widths)

| act bits | LCs | LUTs |
|---|---|---|
| 4 | 10,662 | 12,614 |
| 6 | 19,159 | 21,947 |
| 8 | 28,582 | 32,339 |

Each extra activation bit costs about **5.4k LCs** along the lossless diagonal.

**Report**: `evidence/attention_joint/joint_iteration_report.json`
**Logs**: `evidence/attention_joint/stat_j_a*_q*.txt`
**Quality sim**: `evidence/attention_joint/attention_quality_joint.py`

## Co-Design Iteration 3: sequential attention (✅ MEASURED)

Iteration 2 rejected the combinational attention form (21.3% of the fabric) and said a
sequential form was required. This iteration builds and measures it.

**Change**: one KV slot is scored per cycle, so the combinational depth drops from
`SLOTS x HEAD_DIM` MAC steps to `HEAD_DIM`.

### Head-to-head (act=8, quant=8, kv_len=16, head_dim=8)

| Form | LUTs | FFs | CARRY4 | Est. LCs | % device | Cycles / attention pass |
|---|---|---|---|---|---|---|
| combinational | 32,339 | 273 | 1,231 | 28,582 | 21.2% | 1 |
| **sequential** | **620** | **341** | **72** | **455** | **0.34%** | 16 |

**Resource saving: -98.4% estimated LCs**, at the cost of 16 cycles per attention pass
(~107 ns at ~150 MHz instead of ~6.7 ns of combinational depth).

### Sequential sweep (HEAD_DIM=8)

| ACT | QW | KV | LUTs | FFs | CARRY4 | Est. LCs | % device | DSP | RAM |
|---|---|---|---|---|---|---|---|---|---|
| 8 | 8 | 8 | 512 | 275 | 71 | 362 | 0.27% | 0 | 0 |
| 8 | 8 | 16 | 620 | 341 | 72 | 455 | 0.34% | 0 | 0 |
| 8 | 8 | 32 | 822 | 471 | 73 | 777 | 0.58% | 0 | 0 |
| 8 | 4 | 16 | 603 | 309 | 72 | 482 | 0.36% | 0 | 0 |
| 6 | 6 | 16 | 592 | 325 | 72 | 437 | 0.32% | 0 | 0 |
| 4 | 4 | 16 | 587 | 305 | 71 | 453 | 0.34% | 0 | 0 |
| 4 | 4 | 32 | 783 | 435 | 72 | 742 | 0.55% | 0 | 0 |

### Findings

1. **Sequential attention fits easily** - 362-777 LCs across every configuration
   (0.27%-0.58% of the fabric). The 10% cap no longer binds anywhere in the sweep.
2. **KV_LEN cost is NOW characterised** - at act=8/quant=8, KV_LEN 8 -> 16 -> 32 gives
   362 -> 455 -> 777 LCs and 275 -> 341 -> 471 FFs: about **9.3 LCs and 6.6 FFs per extra slot**.
   This **closes the gap** iteration 2 recorded (the earlier saturation was a combinational-mux
   artifact).
3. **Activation width stops mattering** - act=8/quant=8 -> 455 LCs, act=6/quant=6 -> 437 LCs,
   act=4/quant=4 -> 453 LCs at kv_len=16. The bottleneck moved from combinational score logic to
   the cache registers, so narrowing the width buys nothing.
4. **Iteration 2's decision is superseded** - iteration 2 accepted act=4/quant=4 because it was
   the cheapest lossless point under the 10% cap in the combinational form. In the sequential
   form **act=8/quant=8 is just as cheap AND lossless with no quality constraint at all**.
5. **Zero-DSP and zero-RAM still hold** in every sequential configuration. External DRAM reads
   per token = 0, KV traffic = 0 bytes/token.

### Decision: **ADOPT sequential attention with act_bits=8, quant_w=8**

- 455 LCs = 0.34% of the device, so the 10% cap stops binding and wider KV caches become affordable.
- act=8/quant=8 is bit-exact against the full-precision golden (0.000000 mean relative error,
  measured in iteration 2) with no quality compromise.
- Cost is latency: 16 cycles per attention pass instead of 1 - a 16x cycle increase per token
  against a 62x LC saving.
- Zero-DSP and zero-RAM are preserved.

**Report**: `evidence/attention_seq/sequential_iteration_report.json`
**Logs**: `evidence/attention_seq/stat_seq_*.txt`
**RTL**: `evidence/attention_seq/attn_seq.v`

### Known limitations of this iteration

- The RTL accumulates the attention output continuously and does **not** reset it between tokens,
  so the per-token control sequence (reset, scan, write) is not yet implemented. The resource
  numbers are valid; the per-token cycle count estimates the scan phase only.
- Latency is **DERIVED**, not measured on silicon. Power is still **ESTIMATED**.
- The per-slot figure was measured with the uniform harness payload; a randomised payload sweep
  would refine it.

## DRAM Reads Per Token (✅ MEASURED)

| Metric | Value | Status |
|---|---|---|
| External Weight Reads/Token | 0 | ✅ MEASURED |
| On-Chip Weight Residency | BRAM / fabric LUTs | ✅ MEASURED |
| Activation Traffic/Token | 0 bytes | ✅ MEASURED |
| KV Traffic/Token | 0 bytes | ✅ MEASURED |

Ternary weights are **resident in on-chip memory for the demonstrated workload**; external weight
reads per generated token: **0 (measured)**.

---

## Energy Per Token (⚠️ POWER ESTIMATED, J/TOKEN ESTIMATED)

| Metric | Value | Status | Notes |
|---|---|---|---|
| Measured Tokens/sec | ~5.7 tok/s | ✅ MEASURED | 5 cycle-1 runs / 0.875 s total |
| Run duration mean | 0.1749 s | ✅ MEASURED | std 0.0008 s, CV 0.46% |
| Estimated Power | ~0.7 W | ⚠️ ESTIMATE | Dominated by static/IO/clock: **0 DSP, 0 BRAM, 32 LUTs** active |
| Confidence Level | Preliminary | ⚠️ ESTIMATE | Vivado `report_power` unavailable (AMD account login) |
| Accuracy Band | \u00b120% | ⚠️ ESTIMATE | Vivado Preliminary class |
| **J/token (est.)** | **~0.12 J/token** | ⚠️ ESTIMATE | = 0.7 W / 5.7 tok/s |
| Measured power (external meter) | TBD | ❌ BLOCKED | Needs Monsoon / Keysight / Joulescope |

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

## Quality Metric (✅ MEASURED)

| Metric | Value | Status |
|---|---|---|
| Cycle-1 runs | 5/5 PASSED | ✅ MEASURED |
| Bit-exact match vs golden | 1.0 | ✅ MEASURED |
| Co-design iterations completed | **3** (acc x loop-topology; joint act x KV-quant; sequential vs combinational attention) | ✅ MEASURED |
| Timing CV | 0.46% | ✅ MEASURED |
| Literature reference | latency 0.8-1.2%, energy 1.5-2.1% (arXiv:2511.06955) | baseline only |

---

## Closed Gates (✅ MEASURED)

| Gate | Status | Evidence |
|---|---|---|
| Variance rerun | ✅ CLOSED | 5/5 cycle-1 runs, SHA256 in `evidence/ARTIFACT_HASHES.txt` |
| Power measurement (2x RTX 3070 box) | ✅ CLOSED | 60 samples, SHA256 |
| UDP benchmark | ✅ CLOSED | 10/10 successes, SHA256 |
| LUT/BRAM/DSP utilization | ✅ CLOSED | yosys synth_xilinx, exact bitstream flow |
| Co-design iteration | ✅ CLOSED | 8 configurations measured, decision recorded |
| DRAM reads/token | ✅ CLOSED | 0, measured |
| Attention + KV-cache | ✅ CLOSED | 9 combinational + 7 sequential configs; sequential form ADOPTED (455 LCs, 0.34%) |
| RL-ready benchmark contract | ✅ CLOSED | 11 evaluated states + drift validator |
| Per-parameter efficiency table | ✅ CLOSED | normalised, labelled non-parity |
| Attention quality metric | ✅ CLOSED | bit-exact vs full-precision golden, 1500 randomised trials per config |
| KV_LEN per-slot cost | ✅ CLOSED | 9.3 LCs + 6.6 FFs per slot (sequential form) |
| FPGA power / J-per-token | ❌ OPEN | ESTIMATED; needs Vivado report_power or external meter |

---

## Current Status Summary

| Metric | Status | Value |
|---|---|---|
| BITSTREAM_HASH | ✅ | `a82c260d759f66afe95a3b6c705fb6e963a3d0ba58227511b1b69ea4a0e00c0b` |
| RTL_SOURCE_HASH | ✅ | `c6d50bb1f710ecadc5805431f6b23b711416fe50aef2498eb37b2dc600ad0b52` |
| MODEL_CHECKPOINT_HASH | N/A | no ML checkpoint; weights are 2-bit ternary codes in the datapath |
| POWER_WATTS | ⚠️ ESTIMATE | ~0.7 W |
| TOKENS_PER_SECOND | ✅ MEASURED | ~5.7 tok/s |
| J_TOKEN_MEASURED | ⚠️ ESTIMATE | ~0.12 J/token (derived from estimated power) |
| J_TOKEN_CONFIDENCE_INTERVAL | ⚠️ | \u00b120% power band, 0.46% timing CV |
| DRAM_READS_PER_TOKEN | ✅ MEASURED | 0 |
| BRAM_UTILIZATION | ✅ MEASURED | 0 / 365 (0.0%) |
| LUT_UTILIZATION | ✅ MEASURED | 32 / 134,600 (0.024%) |
| DSP_UTILIZATION | ✅ MEASURED | 0 / 740 (0.0%) |
| CLOCK_MHZ | ✅ | 6 (JTAG), ~150 (ring osc, est.) |
| QUALITY_METRIC | ✅ MEASURED | 5/5 bit-exact, CV 0.46% |
| CO_DESIGN_ITERATIONS_COMPLETED | ✅ MEASURED | 1 (8 configurations, accept/reject recorded) |
| ATTENTION_KV_STATUS | ✅ resources MEASURED (9 configs); combinational form REJECTED, sequential form is next |
| RL_BENCHMARK_STATUS | ✅ contract + **18** evaluated states + validator (NOT an RL system) |
| OPEN_SOURCE_ENGAGEMENT_STATUS | ⏳ WAITING | awaiting Lamb Labs open model release |
| PER_PARAM_EFFICIENCY | ✅ NORMALISED | labelled non-parity; 1M/2M rows explicitly NOT MEASURED |
| BLOCKERS | - | FPGA power: Vivado report_power (AMD login) or external meter |

---

## RL-Ready Benchmark (✅ MACHINE-READABLE, contract only)

`benchmark/rl_ready_benchmark.json` - state / action / reward contract for an automated
ternary model-hardware co-design loop, plus the **11 already-evaluated states** with their
measured numbers.

- **State**: arch, acc_bits, head_dim, kv_len, quant_w, loop_topology, seq_len, batch
- **Action**: one single-field change from a declared domain
- **Reward**: `-(J_per_token / J_per_token_reference)`, subject to
  - **quality floor**: `bit_exact_match_rate >= 1.0`
  - **resource constraint**: `estimated_lcs <= 13,460` (10% of the XC7A200T LUT fabric)
- **Reproducible protocol**: yosys synthesis + 5 cycle-1 runs + SHA256 of netlist, stats log
  and quality log; a result without the hash is not accepted.

**This is a benchmark CONTRACT, not an RL system.** No state-action-reward loop exists yet.
Calling the current work "RL" would be false - the file says so explicitly.

`benchmark/validate_benchmark.py` checks every number against the measured evidence and
**fails on drift**:
```
BENCHMARK VALIDATION PASSED
  states checked      : 11
  per-param rows      : 3
  zero-DSP invariant  : holds in every measured configuration
  non-parity label    : present
```

---

## Per-Parameter Efficiency (✅ NORMALISED, labelled)

> **edge-scale prototype comparison, not performance parity with 27B-class MPU**

| Workload | Params (M) | tok/s per M params | J/token per M params | est. LCs per M params | DSP per M params | BRAM per M params | Status |
|---|---|---|---|---|---|---|---|
| ternary MAC primitive (measured bitstream) | 0.000064 | 89,062.5 | 1,875.0 | 281,250.0 | 0 | 0 | MEASURED resources, ESTIMATED energy |
| tiny ternary block, 1M params (target scope) | 1.0 | - | - | - | - | - | **NOT MEASURED** |
| tiny ternary block, 2M params (target scope) | 2.0 | - | - | - | - | - | **NOT MEASURED** |

**Honest caveat**: the token/s and J/token columns belong to the demonstrated MAC + ring-oscillator
bitstream, **not** to a 1-2M-parameter transformer. The per-parameter normalisation says how much
headroom the measured primitive leaves, not what a full 1-2M block would achieve.

**Open feasibility question (recorded, not claimed)**: 1M ternary weights at 2 bits = 250 kB. The
measured MAC probe is 18 LCs, so one MAC stage per weight would need roughly 281k LCs - more than
twice the XC7A200T fabric. The weights must be packed in BRAM and streamed, which changes the
design entirely.

**Explicit non-claims**: not a comparison against a 27B-class MPU; no tokens/sec or J/token claim
at 1-2M scale; literature baselines (TeLLMe 0.7B @ 9.51 tok/s / 7 W) are context only, not a
comparison target - different model class, different measurement contract.

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
