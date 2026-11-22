# Outreach draft - artifacts, not claims

**Status: DRAFT, NOT SENT.** Prepared for review. The contact is `contact@lamb-labs.com`.
No message is sent until the owner approves it, and nothing in it is sent before the artifacts
it points at are published.

---

## Subject

Measured ternary MAC variance study on Kria-class FPGA

## Body

Hi Niki,

I built a reproducible ternary MAC variance study on a Kria-class FPGA (ALINX AX7203,
xc7a200tfbg484-2), focused on the relationship between quantization choices, FPGA resource use,
latency, power, tokens/sec and measured J/token.

Artifacts:

- [link to README] - the evidence index, with every number labelled MEASURED / ESTIMATED /
  SUSPECT and the claims we withdrew kept in the record
- [link to the evidence dashboard] - `target/lamb_labs_evidence.md`: nine co-design iterations,
  each with a controlled change, measured resources and an accept/reject decision
- [link to the machine-readable benchmark] - `benchmark/rl_ready_benchmark.json`: state / action /
  reward contract with 19 already-evaluated states, plus a validator that fails if any state
  drifts from the evidence
- [link to the raw measurement logs] - `evidence/`: utilisation, the attention sweeps, the quality
  metric, the board clock and die telemetry, each directory with its own SHA256 manifest
- [link to the bitstream and build evidence] - `bitstream/` and `evidence/ax7203_build/`

Current honest scope: an edge-scale ternary inference prototype - a ternary MAC plus a minimal
attention path with a bounded quantised KV-cache. Not a full LLM, and not an MPU parity claim.

What is actually measured: zero-DSP attention with a bounded quantised KV-cache across 22
configurations; external DRAM reads per token = 0; a bit-exact quality metric against a
full-precision golden; and the board's own clock measured on silicon at 67.16 MHz.

What is not measured, and labelled as such: power and J/token (the XC7A200T has no on-die current
sensor, so those need an external meter), and the achievable clock of the adopted attention
design. We also withdrew two of our own claims after our own measurement contradicted them -
both withdrawals are in the record rather than erased.

Question: for your MPU co-design loop, which interface would be most useful for an external FPGA
prototype - a machine-readable architecture/quantization benchmark, or a reproducible J/token +
DRAM-reads-per-token case study?

Would a 15-minute technical conversation be useful?

Best,
[your name]

---

## Checklist before sending

- [ ] the repository is published at a URL the recipient can reach
- [ ] the five links resolve
- [ ] `python3 benchmark/validate_benchmark.py` passes on the published tree
- [ ] `python3 scripts/manifest.py` matches the published tree
- [ ] the owner has read the "What is not measured" paragraph and agrees with it
- [ ] the owner has approved sending
