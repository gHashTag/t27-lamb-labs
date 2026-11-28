# Getting started with t27-lamb-labs

The lab is an **evidence-first** ternary-transformer / FPGA co-design portfolio.
Every number is labelled **MEASURED**, **ESTIMATED**, **TARGET** or **SUSPECT**;
see the README's "Evidence status" before quoting anything. This page is the
operator's path: what to run, in what order, and what "green" means.

## The law: spec first, thin glue

All logic lives in `.t27` specs under `specs/`. Shell scripts only move bytes;
Python exists as thin glue only (`t27c_lite.py`, gate scripts). Nothing is
hand-transcribed: emitted RTL is derived from the parsed spec text, and every
spec's own `test` blocks become mandatory conformance vectors.

## One command per intent

| Intent | Command | What it proves |
|---|---|---|
| Everything is green | `make regress` | All five gates G1-G5 (portfolio rules, spec-first compiler, conformance pack, manifest hashes, zero tree drift) |
| Regenerate RTL from specs | `make verilog` | `.t27` spec -> Verilog, iverilog bit-exact, yosys clean, byte-identical |
| Conformance tiers | `make conformance` | Tier A RTL 29/29, Tier B golden 10/10, Tier B2 dot27 50/50 |
| Portfolio rules | `make verify` | The ONE SHOT acceptance list checked against files on disk |
| Spec test reports | `make test-reports` | `t27c test-report` over every `specs/**/*.t27`, zero vacuous passes |
| FPGA stack synth (scratch) | `make stack-synth` | yosys `synth_xilinx` over `fpga/stack/rtl` into a /tmp root |
| B-ESTIMATE headline JSON | `make stack-bestimate` | The `.t27` reporter reduces committed `*.stat` artifacts into `*.bestimate.json` |

Tool prerequisites: `t27c` (>= 0.5.2), `iverilog`, `yosys`, `python3`, `zig`
(the last only for `make stack-bestimate` binary builds).

## Adding a new spec

1. Write `specs/<area>/<name>.t27` — `module PascalName;`, C-like bodies,
   ASCII only. Module name matches the file path.
2. Embed the spec's own `test` blocks with real vectors — a spec without tests
   is refused by policy (`0 vacuous passes` is the bar).
3. Verify: `t27c test-report specs/<area>/<name>.t27` — 100% rate, no vacuous.
4. If it feeds a pipeline (RTL emission, evidence reduction), wire the artifact
   into the gates: regression must stay green and byte-identical afterwards.

## The FPGA stack lane (fpga/stack/)

The Artix-7 (xc7) vertical: RTL -> yosys `synth_xilinx` -> raw `.stat` +
`.netlist.json` evidence -> B-ESTIMATE reduction by the `.t27` spec
`specs/fpga/bestimate_stat.t27` -> `*.bestimate.json` (label ESTIMATE).

- Synthesis currently runs on the lab's Linux box (yosys 0.33); the reporter
  binary builds anywhere `t27c` + `zig` exist (`make stack-bestimate`).
- `run_stack.sh` accepts `BESTIMATE_BIN=<path>` to attach the reduction;
  without it, it only echoes the raw cell histogram — never invent numbers.
- See `fpga/stack/README.md` for the file-by-file evidence layout.

## Evidence discipline

- Raw artifacts are committed: `.stat` (verbatim yosys output), logs, JSONs.
- `ARTIFACT_MANIFEST.txt` hashes every deliverable; gate G4 re-hashes from
  disk on every regression (edit a file -> refresh its manifest row).
- Regeneration must be byte-identical (gate G5): the pipeline is deterministic
  or it is broken.
- Labels: MEASURED (with artifact hash), ESTIMATED (method stated), TARGET
  (goal), SUSPECT (kept visible, not erased).
