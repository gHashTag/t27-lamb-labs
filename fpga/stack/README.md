# fpga/stack — Artix-7 (xc7) vertical stack

RTL -> yosys `synth_xilinx` -> raw evidence -> B-ESTIMATE reduction.

## Layout

- `rtl/` — hand-written Verilog designs (counter, fir4) plus the spec-emitted
  tops consumed from `specs/ternary/` (dot27_top, comb_ternary_dot_top live in
  the compiler output; their stat evidence is committed here).
- `scripts/run_stack.sh` — thin glue: yosys synth + stat + netlist JSON;
  optional `BESTIMATE_BIN` attaches the `.t27` reporter (never reduces
  numbers itself).
- `results/` — committed evidence per design: `.stat` (verbatim yosys),
  `.netlist.json` (yosys write_json), `.bestimate.json` (ESTIMATE headline,
  schema in docs/EVIDENCE_SCHEMA.md).

## Current headline (ESTIMATE, from the .t27 reporter)

| Design | LUT | FF | DSP | BRAM | cells |
|---|---|---|---|---|---|
| counter | 0 | 32 | 0 | 0 | 109 |
| fir4 | 17 | 34 | 4 | 0 | 163 |
| dot27_top | 186 | 0 | 0 | 0 | 358 |
| comb_ternary_dot_top | 191 | 0 | 0 | 0 | 370 |

Notes stated honestly: `counter` needs zero LUTs because its increment maps to
the CARRY4 chain alone (8 CARRY4 cells); `fir4` infers exactly 4 DSP48E1 for
its 4 taps. Synthesis ran with yosys 0.33 on the lab's Linux box; the reporter
is the compiled `specs/fpga/bestimate_stat.t27` (golden tests embed these very
stat artifacts).

## Run it

Host with t27c + zig (reporter): `make stack-bestimate`.
Box with yosys (synthesis): `BESTIMATE_BIN=/tmp/bestimate_stat bash scripts/run_stack.sh <stack_root> <file.v> <top>`;
scratch synthesis without touching repo evidence: `make stack-synth`.
