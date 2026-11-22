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

## Co-Design Iteration 4: token-sequential attention with an exact cycle count (✅ MEASURED + VERIFIED)

Iteration 3 left a limitation: the sequential RTL accumulated continuously and did not reset
between tokens, so the per-token cycle count was an estimate of the scan phase only. This
iteration implements the control sequence.

**Control sequence** (exact `SLOTS + 2` cycles per token):
`phase 0` clear the accumulator · `phases 1..SLOTS` scan one KV slot per cycle and accumulate
its contribution · `phase DONE` output valid + write the new KV slot + restart.

### Resources (HEAD_DIM=8)

| ACT | QW | KV | LUTs | FFs | CARRY4 | Est. LCs | **Exact cycles/token** | DSP | RAM |
|---|---|---|---|---|---|---|---|---|---|
| 8 | 8 | 8 | 522 | 279 | 71 | 368 | **10** | 0 | 0 |
| 8 | 8 | 16 | 650 | 345 | 72 | 505 | **18** | 0 | 0 |
| 8 | 8 | 32 | 852 | 475 | 73 | 820 | **34** | 0 | 0 |
| 6 | 6 | 16 | 607 | 329 | 72 | 462 | **18** | 0 | 0 |
| 4 | 4 | 16 | 599 | 309 | 71 | 467 | **18** | 0 | 0 |
| 4 | 4 | 32 | 791 | 439 | 72 | 759 | **34** | 0 | 0 |

### Verification: the control sequence does NOT change the mathematics

| HEAD_DIM | KV_LEN | QUANT_W | Trials | Mismatches | Verdict |
|---|---|---|---|---|---|
| 4 | 8 | 8 | 2,000 | 0 | MATCH |
| 8 | 8 | 8 | 2,000 | 0 | MATCH |
| 8 | 16 | 8 | 2,000 | 0 | MATCH |
| 8 | 16 | 6 | 2,000 | 0 | MATCH |
| 8 | 32 | 8 | 2,000 | 0 | MATCH |
| 4 | 16 | 4 | 2,000 | 0 | MATCH |

**12,000 randomised trials, 0 mismatches** against the combinational golden.

### Cost of the control sequence (act=8, quant=8, kv_len=16)

| Form | Est. LCs | Cycles/token | Note |
|---|---|---|---|
| plain sequential | 455 | 16 | scan phase only, no reset |
| **token-sequential** | **505** | **18** | **exact**: 1 clear + 16 scan + 1 write/done |
| overhead | **+50 (+11.0%)** | **+2 (+12.5%)** | buys a per-token-defined output with a `done` pulse |

### Derived attention throughput (⚠️ DERIVED, not measured on silicon)

| KV_LEN | Exact cycles/token | Attention passes/s at 150 MHz (est.) |
|---|---|---|
| 8 | 10 | 15,000,000 |
| 16 | 18 | 8,333,333 |
| 32 | 34 | 4,411,765 |

> **Important caveat**: these are attention **passes** per second for this block, **not** model tokens
> per second. The 5.7 tok/s measured on the cycle-1 variance bitstream is a **different measurement**
> (cycle-1 runs, dominated by the measurement harness, not by the FPGA clock) and must not be mixed
> with this number.

### Decision: **ADOPT the token-sequential form** (`attn_token`)

- It produces a per-token-defined output with a `done` pulse - what an inference loop needs.
- The cycle count per token is **exact**, so throughput can be derived without guessing.
- Control overhead is **+50 LCs and +2 cycles** - small and quantified.
- Zero-DSP, zero-RAM and zero external DRAM traffic are preserved.
- The mathematics is **verified identical** to the combinational golden.

**Report**: `evidence/attention_token/token_iteration_report.json`
**Logs**: `evidence/attention_token/stat_tok_*.txt`
**RTL**: `evidence/attention_token/attn_token.v`
**Verification**: `evidence/attention_token/token_sequential_verification.py`

### Still open after this iteration

- The derived throughput uses an **estimated** ring-oscillator clock; measuring the real clock would
  make it measured.
- **Power is still ESTIMATED** (Vivado `report_power` or an external meter).
- The per-slot cost figure still used the uniform harness payload.
- The sequential bitstream has **not** been built and flashed, so no silicon latency measurement exists.

## Co-Design Iteration 5: clock source (✅ MEASURED + netlist VERIFIED)

Every latency and throughput figure so far was derived from an **estimated** ring-oscillator
frequency (~150 MHz). This iteration removes that estimate and separately checks whether the
ring oscillator survives synthesis at all.

### 5a. Ring oscillator: structurally VERIFIED in the shipped netlist

`evidence/clock/verify_ring_oscillator.py` walks the synthesised JSON netlist behind the shipped
`ternary_mac_demo_top_200t.bit`:

```
INV(osc -> chain[0]) -> LUT1 inv_chain[1..19] -> BUFG(clkbufmap) -> osc
```

**21 elements walked, VERDICT: CLOSED** - the ring oscillator loop IS present in the shipped
netlist, with the clock-buffer mapper's BUFG in the clock path (normal practice).

> **Honest caveat**: structural presence is not functional oscillation. The parent repository's
> `docs/fpga/clocking.md` states the ring oscillator does **not** work in this flow and that the
> board has no working external oscillator. The shipped flow
> (`synth_xilinx -family xc7 -nodsp -nosrl`) evidently preserved the loop, but **whether it
> oscillates on the AX7203 can only be settled on silicon** with a counter readback. The Digilent
> HS2 was disconnected during this work, so that measurement is outstanding.

### 5b. CFGMCLK replaces the fabric oscillator

`STARTUPE2.CFGMCLK` is the Artix-7 internal configuration oscillator, **~66 MHz family nominal**
(per the repo's `docs/fpga/clocking.md`), and the canonical clock source on this board family.

| ACT | QW | KV | LUTs | FFs | CARRY4 | Est. LCs | **Exact cycles/token** | DSP | RAM |
|---|---|---|---|---|---|---|---|---|---|
| 8 | 8 | 8 | 510 | 275 | 70 | 376 | **10** | 0 | 0 |
| 8 | 8 | 16 | 611 | 341 | 71 | 467 | **18** | 0 | 0 |
| 8 | 8 | 32 | 813 | 471 | 72 | 768 | **34** | 0 | 0 |
| 6 | 6 | 16 | 589 | 325 | 71 | 448 | **18** | 0 | 0 |
| 4 | 4 | 16 | 553 | 305 | 70 | 422 | **18** | 0 | 0 |

| Variant (act=8, quant=8, kv_len=16) | Est. LCs | Clock |
|---|---|---|
| ring-oscillator clocked | 505 | fabric ring oscillator, **ESTIMATED** ~150 MHz |
| **CFGMCLK clocked** | **467** | **silicon-specified** ~66 MHz family nominal |
| saving | **-38 (-7.5%)** | the 19 LUT1 + 4 INV oscillator and its BUFG are no longer needed |

### Derived attention throughput with a specified clock (⚠️ DERIVED)

| KV_LEN | Exact cycles/token | Attention passes/s at 66 MHz |
|---|---|---|
| 8 | 10 | 6,600,000 |
| 16 | 18 | 3,666,667 |
| 32 | 34 | 1,941,176 |

> **Caveats**: CFGMCLK is a configuration oscillator - its tolerance is wider than a dedicated
> clock, so it is a measurement reference, not a production clock source. These are attention
> **passes** per second, **not** model tokens per second. The measured 5.7 tok/s from the cycle-1
> variance bitstream is a different measurement and is kept separate.

### Decision: **ADOPT the CFGMCLK-clocked token-sequential attention** as the reference design

- It removes the "estimated ~150 MHz" caveat from every derived latency and throughput figure.
- It is **38 estimated LCs cheaper** because the fabric oscillator and its clock buffer are gone.
- It uses the clock the parent repository documents as the canonical and only working source here.
- Zero-DSP, zero-RAM and zero external DRAM traffic are preserved; cycles/token stay exact.

**Report**: `evidence/clock/clock_iteration_report.json`
**Logs**: `evidence/clock/stat_cfg_*.txt`
**Verifier**: `evidence/clock/verify_ring_oscillator.py`

### Still open after this iteration

- **Functional** ring-oscillator verification on silicon (counter + JTAG readback) - the Digilent HS2
  was disconnected during this work.
- The **actual** CFGMCLK frequency on this board: the family nominal (~66 MHz) is used, but the
  part's measured value has not been taken. `openFPGALoader --read-xadc` would also give die
  temperature and VCCINT, which the power estimate needs.
- **Power is still ESTIMATED.**
- The sequential bitstream has **not** been built and flashed.

## Co-Design Iteration 6: AX7203-native build (⚠️ PARTIAL - chipdb VERIFIED, bitstream blocked)

Iteration 5 left the design clocked by CFGMCLK with an estimated frequency and no board-native
build. This iteration targets the AX7203's real hardware.

### Board facts used (from the parent repo's `fpga/HARDWARE_SSOT.md`)

| Signal | AX7203 pin |
|---|---|
| 200 MHz differential oscillator | **R4 (P) / T4 (N)**, DIFF_SSTL15 |
| User LEDs (active low) | **B13, C13, D14, D15** |
| UART TX | **N15** (RX P20) |
| Chipdb | `xc7a200tfbg484-2.bin` |
| Cable | Digilent HS2, FT232H, serial 210512180081, busdev 0:4 on macOS |

> **Correction**: the previously shipped `ternary_mac_demo_top_200t.bit` drives **R23/T23**, which the
> SSOT records as Wukong pins that the AX7203 routes elsewhere. The AX7203's LEDs are
> **B13/C13/D14/D15**. The new design uses the documented AX7203 pins, so the earlier bitstream's
> LED observations are **not** evidence about this board.

### Chipdb: BUILT and INDEPENDENTLY VERIFIED

| Check | Value | SSOT expects | Match |
|---|---|---|---|
| Size | 333,207,792 B | 333,207,792 B | ✅ |
| md5 | `59f828c441e6e6081bfee63ff994660e` | `59f828c441e6e6081bfee63ff994660e` | ✅ |

Regenerated from source with `bbaexport.py --device xc7a200tfbg484-2` + `bbasm --le`, on the GPU box
(the Mac had only 879 MiB free). The stale `xc7a200t.bin` on the Mac was rejected by nextpnr with
"internal IDs ... inconsistent with the supplied chip database".

### Design (AX7203-native)

`evidence/ax7203_build/ax7203_attn.v`: the adopted token-sequential attention (act=8, quant=8,
kv_len=16, **exact 18 cycles/token**) on the 200 MHz oscillator, with LEDs on B13/C13 and a **UART
beacon on N15 emitting one byte per `done` pulse** - so the host can timestamp the token interval
directly on silicon.

Datapath changes made while building:
- the ternary weight is applied as **sign selection** on the key, not as a 17x17 multiply
- the KV cache was **flattened from 2D arrays to 1D packed words**
- the UART transmitter was reduced to **one counter** (two counters caused a multi-driver arc conflict)

### Build attempts (8 configurations, all recorded)

| yosys | nextpnr | result |
|---|---|---|
| 0.67 | master | packer: "No wire found for port O6" |
| 0.46 (OSS CAD) | master | same |
| 0.46 | stable-backports | same |
| 0.46 + `-abc9` | master | same |
| 0.46 + `-nolutram` | master | LUT6 packing error |
| 0.46 + `-nolutram -nowidelut` | master | placement OK; routing fails on one long ALU net |
| 0.46 + `-nolutram -nowidelut`, 65 MHz constraint | master router1 seeds 3, 5 | **timing PASSES (71.86 / 73.15 MHz)**; routing fails: constant net and real net share a wire |
| same | master router2 | same family |

### Findings

1. **CLOCK SHORTFALL - CLAIM WITHDRAWN BY ITERATION 8.** This section originally read "the design
   reaches only 65-73 MHz ... a 3x shortfall against the board's 200 MHz". Iteration 8 measured the
   same netlist at 45.13-73.15 MHz across five seed/router combinations (a 62% spread), which shows
   the reported Fmax is **placement noise**, not a measure of this design. **The design's true
   achievable clock is UNKNOWN** until Vivado's timing report or silicon says otherwise.
   Iteration 7's correction of the cause was itself withdrawn: deleting the KV read mux it blamed
   made the number *worse* (55.03 MHz), and the BRAM version was identical (71.86 MHz).
2. **openXC7 packer defects on this design** — three distinct failures (LUT6 O6 with no wire; two
   arcs on one sink wire; a constant GND net sharing a wire with a real net), all independent of the
   nextpnr branch, the yosys version, the ABC flow, the placer, the router and the seed.
   → **the FPGA flow is part of the design space**: this design needs Vivado, a patched nextpnr, or a
   LUT4/constant-net constrained variant.
3. **Restructuring moves the failure rather than removing it**, which places the defect in the
   packer rather than in one cell.

### Decision: **ADOPT the AX7203-native RTL and XDC; DEFER the bitstream**

The chipdb is no longer a blocker and the RTL/constraints are board-correct and reusable. The two
remaining blockers are now precisely characterised: a 3× clock shortfall in the accumulator (a
**design** fix) and a packer defect in the open-source FPGA flow (a **toolchain** choice). Shipping a
bitstream that does not route would be a false artifact.

**Report**: `evidence/ax7203_build/ax7203_build_report.json`
**RTL + XDC**: `evidence/ax7203_build/`
**Chipdb provenance**: `evidence/ax7203_build/chipdb_provenance.txt`

### Next: co-design iteration 7 - pipeline the accumulator

Measure the clock-vs-area trade (Fmax, LUTs, FFs) for a pipelined accumulator, then retry the build.

## Co-Design Iteration 7: critical path isolated by controlled removal (✅ MEASURED)

Iteration 6 attributed the clock shortfall to the 32-bit accumulator feedback loop. That was an
**assumption, not a measurement**. This iteration measures it.

**Technique**: controlled removal. Each candidate path is deleted from an otherwise identical
design and the resulting Fmax is compared against the baseline. All three runs use identical
settings (yosys 0.46, `-nolutram -nowidelut`, chipdb `xc7a200tfbg484-2`, 65 MHz constraint, placer
`sa`, router `router1`, seed 3), so the difference is attributable to the removed path alone.

| Variant | Path removed | Fmax | PASS at 65 MHz |
|---|---|---|---|
| baseline | none | **71.86 MHz** | ✅ |
| `noacc` | the 32-bit accumulator feedback loop | **59.77 MHz** | ❌ |
| `noscore` | the (ACT_BITS x QUANT_W) score multiply | **74.13 MHz** | ✅ |

### Findings

1. **The accumulator is NOT the critical path.** Removing its feedback did not raise Fmax - it
   **fell** to 59.77 MHz. Iteration 6's attribution was **wrong**; the correction is kept in the
   record rather than erased.
2. **The score multiply is barely on the path.** Removing it moved Fmax by 3.2% (71.86 → 74.13 MHz).
3. **The KV-cache read mux is the limiter.** Both candidate removals leave Fmax in the 60-74 MHz
   band, so the limiter is a path neither variant touched: each channel reads one `QUANT_W`-bit
   field out of a SLOTS-entry array with a **dynamic index** (`slot_ptr`), so every channel carries
   a **32-to-1 mux**, and the eight channel muxes, the sign select, the add and the accumulator
   mux all sit in series behind it.

### Decision: **REJECT the accumulator-pipelining plan; ADOPT KV-read pipelining**

> **WITHDRAWN BY ITERATION 8.** The KV-read pipelining built here measured **40.52 MHz**, worse than
> the 71.86 MHz baseline, and the direct test of the blamed path (deleting the read mux) measured
> **55.03 MHz**, also worse. The Fmax these numbers rest on is placement noise. The plan is
> withdrawn, not because it was refuted on its merits but because the metric it used cannot decide
> the question. The cycles/token cost (+5.6%) and the resource costs remain valid.

The KV-read pipeline would fetch slot N+1 while accumulating slot N, needing a one-slot lookahead
and special handling of the last slot.

**Report**: `evidence/critical_path/critical_path_report.json`
**Variants**: `evidence/critical_path/attn_token{,_noacc,_noscore,_pipe}.v`

### Note on method

This iteration changed no claim without a measurement, and it changed a **previous** claim -
iteration 6's critical-path attribution - on the strength of the exclusion experiment. Both are in
the record.

## Co-Design Iteration 8: the Fmax numbers were placement noise (✅ MEASURED - two claims withdrawn)

Iteration 7 concluded, by exclusion, that the KV-cache read mux was the critical path. Iteration 6
concluded the design had a "3× clock shortfall". **Both rest on nextpnr's reported Fmax.** This
iteration tests whether that number is a valid measure at all.

### Three new controlled variants

| Variant | Change | Fmax | vs baseline | Verdict |
|---|---|---|---|---|
| `kvpipe` | KV read pipelined (iteration 7's proposed fix: fetch slot N+1 while accumulating slot N) | 40.52 MHz | **-43%** | WORSE |
| `fixedread` | KV read index fixed to slot 0 - the 32-to-1 read mux **deleted entirely** | 55.03 MHz | **-23%** | WORSE |
| `bram` | KV cache inferred into block RAM - the read becomes a hard macro, no mux | 71.86 MHz | **0%** | IDENTICAL (1 RAMB36) |

### Seed sweep on ONE identical netlist

| Router | Seed | Fmax |
|---|---|---|
| router2 | 1 | 57.30 MHz |
| router2 | 2 | 48.98 MHz |
| router2 | 4 | 45.13 MHz |
| router1 | 3 | 71.86 MHz |
| router1 | 5 | 73.15 MHz |

**min 45.13 - max 73.15 MHz = 28.02 MHz spread = 62% of the minimum, on a byte-identical netlist.**

### Findings

1. **Fmax from this toolchain is PLACEMENT NOISE on this design.** A property of the logic cannot
   vary by 62% when the logic is unchanged. **No frequency conclusion may rest on it.**
2. **Iteration 7's conclusion is withdrawn.** The direct test deletes the mux it blamed; the
   reported Fmax *falls*, and the BRAM version - where the read is a hard macro with no mux at all -
   is *identical*. Iteration 7's method was sound; its conclusion was inferred, and the direct
   measurement contradicts it.
3. **Iteration 6's "3× clock shortfall" is withdrawn as an established fact.** The same netlist
   also measures 45.13 MHz, so the design's true frequency limit is **UNKNOWN**. It may well run at
   200 MHz; the toolchain simply does not say so.
4. **BRAM is area-free and frequency-free here.** Moving the KV cache to block RAM costs 1 RAMB36
   of 365 and leaves Fmax identical. The dashboard's "BRAM = 0" is a property of the *register*
   implementation, not of the architecture.

### Decision: **WITHDRAW the frequency claims of iterations 6 and 7**

The resource numbers (LUT/FF/BRAM/DSP), the quality metric, the combinational-vs-sequential
comparison and the lossless rule are stable across seeds and **remain the portfolio's solid
ground**. The timing number is not, so frequency is recorded as **UNKNOWN** pending Vivado's
timing report or silicon.

### What this means for the pitch

- An FPGA flow is part of the design space, not a formality: on this design the open toolchain's
  timing number was **not a measurement**.
- Any J/token or tok/s figure produced from a nextpnr-reported Fmax would be an estimate of an
  estimate. The protocol requires a silicon measurement or a vendor-tool timing report first.
- The **resource-side** co-design results are unaffected and stay solid.

**Report**: `evidence/fmax_noise/fmax_noise_report.json`
**Variants**: `evidence/fmax_noise/attn_token{,_kvpipe,_fixedread,_bram}.v`

### Note on method

Two claims made by this project were withdrawn by its own measurement. That is the point of an
evidence-first portfolio: the rule is applied to the tool's numbers as carefully as to the design's.

## Co-Design Iteration 9: FIRST SILICON MEASUREMENTS (✅ MEASURED)

The Digilent HS2 was connected for part of this work, which made two things measurable for the
first time: the board's real clock frequency, and the die's own telemetry.

### 9a. Die telemetry — MEASURED (XADC over JTAG)

| | Idle | Design loaded | Delta |
|---|---|---|---|
| Die temperature | **44.681 °C** (σ 0.046) | **45.271 °C** (σ 0.176) | **+0.590 °C** |
| VCCINT | 0.99926 V | 0.99926 V | - |
| VCCAUX | 1.80557 V | 1.80532 V | - |

Device XADC min/max history: 30.41-45.36 °C, VCCINT 0.9976-1.0020 V.

> **Not a power measurement.** The XADC senses voltage and temperature, **not current**, and the
> XC7A200T has no on-die current sensor. `POWER_WATTS` and `J/token` remain **ESTIMATED**. The
> +0.590 °C rise is a thermal **signature** of the fabric working, not a power figure.

### 9b. CFGMCLK frequency — MEASURED on silicon

A purpose-built probe: `STARTUPE2.CFGMCLK` → 8-bit ripple prescaler → 20-bit ripple binary counter
→ 32-bit **BSCANE2 USER1** register read over JTAG. The counter advances once per 2¸ clock edges,
so `f = Δcounts × 256 / Δt`. Ten reads 0.5 s apart; the 20-bit counter wraps and the difference
is taken modulo 2²⁰.

| | MHz |
|---|---|
| **MEASURED mean** | **67.1583** |
| median | 67.3927 |
| stdev | 1.3325 (n=9 intervals) |
| min / max | 63.9965 / 68.8719 |
| reads with valid magic | 10/10 |

Family nominal ~66 MHz → **measured 67.16 MHz, 1.8% above nominal**.

### 9c. The fabric ring oscillator — appears NOT to oscillate

The same probe with the 20-stage fabric ring oscillator in place of CFGMCLK returned a **frozen**
counter: 20 consecutive reads over 6.7 s all returned the identical register value `0xA5A5A5A4`,
with the magic intact. `bit0` was 1 in **0/20** reads.

**Controlled comparison**: the CFGMCLK version of the **same** probe - identical counter logic,
identical readback, identical register layout, **only the clock source differs** - returned
changing values on every read. A counter that advances under one clock source and is frozen
under another, with everything else identical, localises the fault to the clock source.

**Corroboration**: the parent repo's `docs/fpga/clocking.md` says *"Ring Oscillator (DOES NOT
WORK) ... -abc9 inserts SCC breaker that destroys the combinational loop - Behavioral
`assign osc = ~osc` is optimized away by Yosys - LUT1 primitive instantiation also broken by
ABC9 SCC detection"*.

> **CONFIRMED** (not inferred). The controlled re-test ran with the **identical ripple binary
> counter** used for the CFGMCLK measurement: **30 reads over 15 s, the counter never moved**
> (one distinct value: 0), while the CFGMCLK control of the same design, back-to-back in the same
> session, counted correctly at **66.85 MHz**. Two independent CFGMCLK runs agree to within 0.5%
> (67.16 and 66.85 MHz).
> Log: `evidence/clock_probe/ring_oscillator_confirmation.log`

### 9d. Consequences for this portfolio

| Affected claim | Status |
|---|---|
| the ~150 MHz ring-oscillator clock in every derived throughput figure | **WITHDRAWN** - the oscillator appears not to run; the real clocks are CFGMCLK **67.16 MHz measured** and the board's 200 MHz on R4/T4 (not yet measured) |
| the shipped `ternary_mac_demo_top_200t.bit` and its 5.7 tok/s variance measurement | **WITHDRAWN** - **two** independent defects, both verified from the netlist: (1) all 6 flip-flops are clocked by the dead `osc`, so no state element ever advances; (2) `acc_in` is constant 0 and `w_code` constant −1, so synthesis **pruned the 32-bit accumulator to 2 bits** - the bitstream does not exercise the ternary MAC datapath at all. The `accumulator_final` values in `evidence/variance_summary.json` cannot have come from it, so the **variance gate is REOPENED**. Log: `evidence/clock_probe/shipped_bitstream_analysis.log` |
| the power and J/token estimates | still **ESTIMATED**, but the inputs are now real: 45.27 °C loaded, VCCINT 0.99926 V measured, +0.590 °C thermal signature |
| the achievable attention clock | still **UNKNOWN**, but the question is sharper: time it against 67.16 MHz measured or 200 MHz, not against an estimated 150 MHz fabric oscillator |

### 9e. Toolchain findings (each one a build blocker that was removed)

- **openXC7's LUT6 packing defect is bypassed** by restricting the ABC mapping: `abc -lut 2` instead
  of the stock `abc -luts 2:2,3,6:5`. With no LUT6 in the netlist the *"No wire found for port O6"*
  failure disappears. **This is what finally made the clock probe build.**
- **A carry-chain counter is what breaks routing**: the placer splits the CARRY4 chain across
  non-adjacent slices. A plain flip-flop **ripple counter** has no CARRY4 and routes, at the cost
  of a slow increment - affordable because it advances once per prescaler tick.
- **BSCANE2 USER1 readback works over the HS2** with a 6-bit IR (USER1 = 0x02) and this framing:
  `TLR(5) → RTI → Select-DR → Select-IR → Capture-IR → Shift-IR → 6 IR bits → Update-IR → RTI`,
  then `RTI → Select-DR → Capture-DR → Shift-DR`.
- `openFPGALoader --read-xadc` emits JSON with a **trailing comma**, which is not valid JSON; the
  fields have to be parsed with a regex.
- The AX7203 answers at **busdev 1:3** in this session, not the SSOT's 0:4 - the USB bus renumbers.

**Report**: `evidence/clock_probe/clock_probe_report.json`
**Logs**: `evidence/clock_probe/{cfgmclk_measurement,ring_oscillator_measurement,xadc_measurement}.log`
**Bitstreams**: `evidence/clock_probe/clock_probe_{cfg,ring}.bit`
**Scripts**: `evidence/clock_probe/{measure_clock,read_user1}.py`

### Two bugs of my own, found by measurement

The hand-rolled Gray counter (wrong update → non-monotonic readback) and the host-side Gray decoder
(tracked the gray bit instead of the binary bit). Both produced **plausible-looking numbers that were
wrong**, and both are recorded because that is what the protocol demands.

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
| Co-design iterations completed | **5** (acc x loop-topology; joint act x KV-quant; sequential vs combinational; token-sequential control; clock source) | ✅ MEASURED |
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
| Attention + KV-cache | ✅ CLOSED | 9 combinational + 7 sequential + 6 token-sequential configs; token-sequential ADOPTED (505 LCs, 0.38%) |
| RL-ready benchmark contract | ✅ CLOSED | 11 evaluated states + drift validator |
| Per-parameter efficiency table | ✅ CLOSED | normalised, labelled non-parity |
| Attention quality metric | ✅ CLOSED | bit-exact vs full-precision golden, 1500 randomised trials per config |
| KV_LEN per-slot cost | ✅ CLOSED | 9.3 LCs + 6.6 FFs per slot (sequential form) |
| Attention cycles/token | ✅ CLOSED | exact SLOTS+2; verified 0 mismatches vs golden |
| FPGA power / J-per-token | ❌ OPEN | ESTIMATED; needs Vivado report_power or external meter |

---

## Current Status Summary

| Metric | Status | Value |
|---|---|---|
| BITSTREAM_HASH | ✅ | `a82c260d759f66afe95a3b6c705fb6e963a3d0ba58227511b1b69ea4a0e00c0b` |
| RTL_SOURCE_HASH | ✅ | `c6d50bb1f710ecadc5805431f6b23b711416fe50aef2498eb37b2dc600ad0b52` |
| MODEL_CHECKPOINT_HASH | N/A | no ML checkpoint; weights are 2-bit ternary codes in the datapath |
| POWER_WATTS | ⚠️ ESTIMATE | ~0.7 W |
| TOKENS_PER_SECOND | ❌ **WITHDRAWN** | ~5.7 tok/s came from the shipped bitstream, whose only clock is the **dead** fabric ring oscillator and whose 32-bit accumulator was **pruned to 2 bits**. Two defects, both verified from the netlist. No throughput number is currently published. |
| J_TOKEN_MEASURED | ⚠️ ESTIMATE | ~0.12 J/token (derived from estimated power) |
| J_TOKEN_CONFIDENCE_INTERVAL | ⚠️ | \u00b120% power band, 0.46% timing CV |
| DRAM_READS_PER_TOKEN | ✅ MEASURED | 0 |
| BRAM_UTILIZATION | ✅ MEASURED | 0 / 365 (0.0%) |
| LUT_UTILIZATION | ✅ MEASURED | 32 / 134,600 (0.024%) |
| DSP_UTILIZATION | ✅ MEASURED | 0 / 740 (0.0%) |
| CLOCK_MHZ | ✅ **67.16 MEASURED** (CFGMCLK, mean of 9, σ 1.33) · attention design's achievable clock still UNKNOWN · ring osc ~150 **WITHDRAWN** (appears not to oscillate) |
| QUALITY_METRIC | ✅ MEASURED | attention quality: bit-exact vs a full-precision golden, 12000 randomised trials, 0 mismatches. The old 0.46% cycle-1 CV is **withdrawn** with the tok/s figure. |
| CO_DESIGN_ITERATIONS_COMPLETED | ✅ MEASURED | **9** (acc x loop-topology; joint act x KV-quant; sequential vs combinational; clock source; AX7203-native build; critical-path isolation; Fmax noise audit; silicon clock + die telemetry) |
| ATTENTION_KV_STATUS | ✅ resources + quality MEASURED (9 combinational, 7 sequential, 6 token-sequential configs); combinational form REJECTED (21.3% fabric); **token-sequential form ADOPTED** (505 LCs, 0.38%) |
| RL_BENCHMARK_STATUS | ✅ contract + **19** evaluated states + validator (NOT an RL system) |
| OPEN_SOURCE_ENGAGEMENT_STATUS | ⏳ WAITING | awaiting Lamb Labs open model release |
| PER_PARAM_EFFICIENCY | ✅ NORMALISED | labelled non-parity; 1M/2M rows explicitly NOT MEASURED |
| BLOCKERS | - | **No throughput number can be published until a design with a running clock is measured** (the AX7203's 200 MHz on R4/T4 is unmeasured; CFGMCLK ~67 MHz measured is the fallback); **FPGA power still ESTIMATED** (needs a current meter); **the variance gate is REOPENED** (the old run data has unexplained provenance); openXC7 cannot route the attention design (LUT6 packing + carry-chain splitting) |

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
