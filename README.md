# t27-lamb-labs

**Ternary transformer research on a Kria-class FPGA (ALINX AX7203, `xc7a200tfbg484-2`).**

An evidence-first model-hardware co-design portfolio. Every number below is labelled
**MEASURED**, **ESTIMATED**, **TARGET** or **SUSPECT**, and every measured number has a hashed
artifact behind it. Claims that this project withdrew are kept in the record, not erased.

---

## Scope, stated honestly

**What this is:** a tiny ternary transformer inference prototype on XC7A200T, with the
attention + bounded quantised KV-cache measured across 22 configurations, a machine-readable
co-design benchmark, and a measured board clock.

**What this is not:**

- **Not** TinyLlama-1.1B on Kria. We do not claim it and do not measure it.
- **Not** a full transformer. The demonstrated workload is a ternary MAC plus a minimal
  attention path with a bounded KV-cache.
- **Not** a parity benchmark against the Lamb Labs MPU or Larry.
- **Not** an RL system. The benchmark is a *contract*; no state-action-reward loop exists yet.
- **Not** a power measurement. See the table below - power is **ESTIMATED**.

Wording used throughout: **ternary weights resident in on-chip memory for the demonstrated
workload; external weight reads per generated token: measured value.**

---

## Evidence status

### MEASURED (on the AX7203, or by exact synthesis of the same flow)

| Result | Value | Evidence |
|---|---|---|
| **Board clock (CFGMCLK)** | **67.16 MHz** mean, 67.39 median, σ 1.33, n=9 - and a second independent run at **66.85 MHz**, agreeing to 0.5% | `evidence/clock_probe/cfgmclk_measurement.log` |
| **Board clock (R4/T4 oscillator)** | **398.3 MHz** - two runs at 398.69 (σ 7.57) and 397.93 (σ 13.52), n=9 each. The Johnson prescaler's divide ratio was **experimentally confirmed** first, with a cell-identical CFGMCLK control reading 66.86 / 66.82 MHz. The ratio R4/T4 ÷ CFGMCLK = **5.95–5.97** holds independently of any divide ratio. | `evidence/clock_probe/divide_ratio_control.log` |
| **Die temperature** | 44.681 °C idle → **45.271 °C** with the design loaded (+0.590 °C) | `evidence/clock_probe/xadc_measurement.log` |
| Rail voltages | VCCINT 0.99926 V, VCCAUX 1.80532 V | `evidence/clock_probe/xadc_measurement.log` |
| **External DRAM reads / token** | **0** | `evidence/` (DRAM reads report) |
| **Attention quality** | **bit-exact** vs a full-precision golden - 12,000 randomised trials, **0 mismatches** | `evidence/attention_token/token_sequential_verification.py` |
| Attention resources | **CORRECTED and VERIFIED.** The committed module's KV cache was dead, so 505 LCs / 345 FF was a cache-less design. Five defects were found and fixed; the corrected module passes **1,200 randomised Verilog trials** against a CPU golden with 0 mismatches. At the adopted HEAD_DIM=8 / KV_LEN=16: **2,763 LCs** with a distributed-RAM cache (2.05% of the fabric, zero BRAM), **2,934 LCs** with 6 block RAMs (2.17%), or **18,695 LCs** with the cache in registers (13.9%, outside the 10% cap). **The cache implementation is a first-class co-design choice.** | `evidence/attention_fix/attention_correction_report.json` |
| Combinational attention (rejected) | 28,582 LCs = **21.3% of the fabric** | `evidence/attention/` |
| KV-cache per-slot cost | **9.3 LCs + 6.6 FFs** per slot | `evidence/attention_seq/` |
| Zero-DSP | **DSP48E1 = 0** in all 22 attention configurations | `benchmark/validate_benchmark.py` |
| Lossless rule | **QUANT_W ≥ ACT_BITS** | `evidence/attention_joint/joint_iteration_report.json` |
| Chipdb | rebuilt from source; **size and md5 both match the SSOT** | `evidence/ax7203_build/chipdb_provenance.txt` |
| Bitstream flashed | `isc_done 1` confirmed | `evidence/clock_probe/*.log` |

### ESTIMATED (derived, not measured)

| Quantity | Estimate | Why it is an estimate |
|---|---|---|
| `POWER_WATTS` | ~0.7 W | The XC7A200T has no on-die current sensor. The XADC senses voltage and temperature only. A current measurement in series with the rail is required. |
| `J/token` | ~0.12 | Derived from the estimated power. |
| `J_token` confidence | ±20% | The power band, not a measurement. |

### WITHDRAWN (previously published, withdrawn by our own measurement)

| Quantity | Why it was withdrawn |
|---|---|
| **~5.7 tok/s** | The shipped bitstream's only clock is the **dead** fabric ring oscillator, and its 32-bit accumulator was **pruned to 2 bits**. Two defects, both verified from the netlist. |
| **The closed variance gate** | The `accumulator_final` values in the old cycle-1 runs cannot have come from that bitstream. Their provenance is unexplained, so the gate is **REOPENED**, not closed. |

### SUSPECT (published, and now questioned by our own measurement)

| Quantity | Status |
|---|---|
| **~5.7 tok/s** | **WITHDRAWN.** The shipped `ternary_mac_demo_top_200t.bit` has **two** independent defects, both verified from its netlist: (1) all six flip-flops are clocked by the fabric ring oscillator, which **does not oscillate** - confirmed by a controlled experiment, 30 reads over 15 s with the counter never moving while a CFGMCLK control of the same design counted correctly; (2) `acc_in` is constant 0 and `w_code` constant −1, so synthesis **pruned the 32-bit accumulator to 2 bits**. The bitstream does not exercise the ternary MAC datapath at all, and the `accumulator_final` values in the old variance runs cannot have come from it. **The variance gate is REOPENED.** |

### TARGET (not attempted, not claimed)

1–2M-parameter transformer blocks; any tok/s or J/token figure at that scale.

### Withdrawn by our own measurement (kept in the record)

| Claim | Why withdrawn |
|---|---|
| The documented "200 MHz oscillator on R4/T4" | **The measurement says ~398 MHz, about twice the documented value.** The measurement is repeatable (two runs) and the ratio argument is independent of the instrument. *Why* the documentation says 200 MHz is recorded as **unknown**: the board may run a ~400 MHz oscillator, the pin assignment may refer to a different board revision, or the documented value may be a nominal the board does not run at. The measurement stands; the explanation does not. |
| A ~150 MHz fabric ring-oscillator clock | **CONFIRMED withdrawn.** The controlled pair was run back-to-back in one session: the ring-oscillator probe's counter **never moved** over 30 reads / 15 s, while the CFGMCLK probe - the same design with one differing line - counted correctly at **66.85 MHz**. Two independent CFGMCLK runs agree to within 0.5% (67.16 and 66.85 MHz). The parent repo's `docs/fpga/clocking.md` says the same: *"Ring Oscillator (DOES NOT WORK)"*. |
| A "3× clock shortfall" against the board's 200 MHz | The same byte-identical netlist measured **45.13 – 73.15 MHz** across five seed/router combinations (a 62% spread). nextpnr's reported Fmax is **placement noise** on this design, not a measure of logic depth. |
| "The KV read mux is the critical path" | Inferred by exclusion, then contradicted: deleting the mux made the reported number **worse** (55.03 MHz), and the BRAM version was **identical** (71.86 MHz). |
| A 32-bit accumulator as the critical path | Removing the accumulator feedback made Fmax **worse** (71.86 → 59.77 MHz). |

The design's achievable clock is therefore recorded as **UNKNOWN** pending Vivado's timing report
or a silicon measurement against the board's 200 MHz oscillator on R4/T4.

---

## The co-design results

Nine documented iterations, each with a controlled change, measured resources, and an
accept/reject decision. Full record: `target/lamb_labs_evidence.md`.

| # | Question | Result |
|---|---|---|
| 1 | accumulator width × loop topology | 32-bit accumulator **ACCEPT** (peak 1,048,671 needs 21 bits); 16-bit **REJECT** (overflow) |
| 2 | activation width × KV quant width | **QUANT_W ≥ ACT_BITS** for losslessness; 8-bit activation with 4-bit KV is **80–95% error** → REJECT |
| 3 | combinational vs sequential attention | sequential is **−98.4% LCs** (455 vs 28,582) and every configuration fits the 10% cap |
| 4 | per-token control sequence | exact **SLOTS + 2** cycles/token; **verified identical** to the combinational golden, 0 mismatches in 12,000 trials |
| 5 | clock source | the fabric ring oscillator **does not oscillate** (confirmed); CFGMCLK **measured 67.16 MHz** |
| 6 | AX7203-native build | chipdb **built and verified**; openXC7 **cannot route** the design (LUT6 packing + carry-chain splitting) |
| 7 | critical-path isolation | the accumulator and the score multiply are **not** the limiter; the Fmax metric itself was shown unreliable |
| 8 | Fmax noise audit | two frequency claims **withdrawn**; resource results survive |
| 9 | silicon measurements | clock **67.16 MHz**, die telemetry, ring oscillator suspect |

---

## The benchmark (Block 6)

`benchmark/rl_ready_benchmark.json` - a machine-readable co-design contract:

- **state**: arch, acc_bits, act_bits, head_dim, kv_len, quant_w, loop_topology, seq_len, batch, clock
- **action**: one single-field change from a declared domain
- **reward**: `-(J_per_token / reference)`, gated by
  - quality floor: `bit_exact_match_rate >= 1.0`
  - resource cap: `estimated_lcs <= 13,460` (10% of the XC7A200T LUT fabric)
- **reproducible protocol**: synthesis + 5 cycle-1 runs + SHA256 of netlist, stats and quality logs
- **19 already-evaluated states**, each carrying its measured numbers

> **This is a benchmark contract, not an RL system.** No state-action-reward loop exists yet.
> Calling the current work "RL" would be false.

`benchmark/validate_benchmark.py` fails if a state has no measured backing, if a count disagrees
with the evidence, if a state over the cap is marked ACCEPTed, if a `NOT MEASURED` row carries a
number, if the non-parity label is missing, or if the zero-DSP invariant breaks.

```
BENCHMARK VALIDATION PASSED
  states checked      : 19
  per-param rows      : 3
  zero-DSP invariant  : holds in every measured configuration
  non-parity label    : present
```

---

## Per-parameter efficiency (Block 7)

> **edge-scale prototype comparison, not performance parity with 27B-class MPU**

The only measured throughput belongs to the demonstrated MAC + attention primitive. The 1M and
2M rows are **NOT MEASURED** and carry the open feasibility question: 1M ternary weights at 2 bits
is 250 kB, and one MAC stage per weight would need roughly 281k LCs - more than twice the
XC7A200T fabric - so the weights must be BRAM-packed and streamed.

---

## Open-source engagement (Block 8)

`engagement/OPEN_SOURCE_PROTOCOL.md` - **PREPARED, NOT EXECUTED**. It activates when Lamb Labs
releases an open model: read the licence and model card first (and stop if redistribution is
forbidden), reproduce the baseline on CPU/GPU, apply this repo's own ternary recipe, and publish
under the same evidence protocol. The forbidden claims are written down explicitly.

---

## Repository layout

```
t27-lamb-labs/
├── target/lamb_labs_evidence.md     # the evidence dashboard: every claim, every artefact
├── benchmark/                        # Block 6 + 7: the co-design contract and the validator
├── engagement/                       # Block 8: the open-source protocol (prepared)
├── evidence/
│   ├── utilization/                  # LUT/BRAM/DSP from the same flow as the bitstream
│   ├── codesign/                     # iteration 1 + the accumulator-range simulation
│   ├── attention/                    # 9 combinational configurations
│   ├── attention_joint/              # the joint act x KV-quant frontier + the quality metric
│   ├── attention_seq/                # the sequential form and the per-slot cost
│   ├── attention_token/              # the token-sequential form and the exact cycle count
│   ├── critical_path/                # the controlled-removal isolation
│   ├── fmax_noise/                   # the Fmax placement-noise audit
│   ├── clock/                        # CFGMCLK variant + the ring-oscillator netlist check
│   ├── clock_probe/                  # Block 9: the silicon clock and die telemetry
│   ├── xadc/                         # the die-telemetry script and logs
│   └── ax7203_build/                 # the AX7203-native RTL/XDC and the chipdb provenance
├── bitstream/                        # the shipped bitstream + its SHA256
├── docs/                             # the resource budget and the target model
├── specs/                            # the .t27 specs
└── scripts/                          # the build and validation scripts
```

Every evidence directory carries its own `ARTIFACT_HASHES.txt`.

---

## Reproducing this

```bash
# validate the benchmark against the evidence
python3 benchmark/validate_benchmark.py

# measure the board clock and the die telemetry
python3 evidence/clock_probe/measure_clock.py 10 0.5
python3 evidence/xadc/measure_xadc.py idle 5
```

The synthesis path is the open one, and it is recorded exactly:

```sh
yosys -p "read_verilog -sv attn_token.v attention_probe.v; \
          synth_xilinx -family xc7 -nodsp -nosrl -nolutram -top attention_probe -flatten; \
          write_json attn_probe.json"
nextpnr-xilinx --chipdb xc7a200tfbg484-2.bin --json attn_probe.json --fasm attn_probe.fasm
python fasm2frames.py --db-root prjxray-db/artix7 --part xc7a200tfbg484-2 attn_probe.fasm
xc7frames2bit --part_file prjxray-db/artix7/xc7a200tfbg484-2/part.yaml \
               --part_name xc7a200tfbg484-2 --frm_file attn_probe.frames --output_file attn_probe.bit
openFPGALoader -c digilent_hs2 --busdev-num 1:3 attn_probe.bit
```

Two toolchain notes that are the difference between a build and a failure:

- **`abc -lut 2`** instead of the stock `abc -luts 2:2,3,6:5`. With no LUT6 in the netlist,
  openXC7's *"No wire found for port O6"* packing failure disappears.
- A **carry-chain counter is what breaks routing** - openXC7's placer splits the CARRY4 chain
  across non-adjacent slices. A plain flip-flop ripple counter has no CARRY4 and routes.

---

## Hard rules

- Do **not** claim "TinyLlama fully on Kria".
- Do **not** claim "10–15 tok/s measured" or "80–120 J/token measured".
- Do **not** claim parity with the Lamb Labs MPU or Larry.
- Do **not** claim 20,000+ tok/s, or any intelligence-per-watt figure.
- Do **not** call the benchmark "RL" until a state-action-reward loop exists.
- Do **not** accept a transfer on file size alone - SHA256 only.
- Do **not** publish a number that has no hashed artefact behind it.
- Do **not** mix Lamb Labs artefacts with other projects' artefacts.
