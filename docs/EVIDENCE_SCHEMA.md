# Evidence schema

The lab's unit of truth is a committed artifact plus a label. This page pins
the artifact shapes so reviewers (and gates) can check them mechanically.

## Honesty labels

| Label | Meaning | Gate |
|---|---|---|
| MEASURED | Produced by the hardware or by exact synthesis of the same flow | raw log + hash in `ARTIFACT_MANIFEST.txt` |
| ESTIMATED | Reduced by a deterministic tool from a MEASURED artifact | method + input artifact named |
| TARGET | Goal, not a result | must not appear in result tables |
| SUSPECT | Known-weak data kept visible, not erased | RISK_REGISTER.md entry |

## fpga/stack/results/ — the B-ESTIMATE lane

Per design `<name>`:

| File | Producer | Shape |
|---|---|---|
| `<name>.stat` | yosys `stat` (verbatim) | plain text: header `=== <design> ===`, prose counters, then one line per cell: `<NAME_UPPER> <count>` |
| `<name>.netlist.json` | yosys `write_json` | standard yosys JSON netlist (modules, cells, ports) |
| `<name>.bestimate.json` | `.t27` reporter `specs/fpga/bestimate_stat.t27` | see below |

`bestimate.json` schema (one line, label ESTIMATE):

```json
{"label":"ESTIMATE","lut":N,"ff":N,"dsp":N,"bram":N,"cells":N}
```

- `lut`: LUT sites (`LUT1..LUT6`, `LUT6_2`)
- `ff`: flip-flops (`FD*`)
- `dsp`: DSP blocks (`DSP48*`)
- `bram`: BRAM blocks (`RAMB*`)
- `cells`: every recognized cell line (superset of the above)

Reduction contract: single forward pass, prose lines excluded (lowercase first
word), zero recognized cell lines -> refusal (exit 1, no JSON). The parser and
reduction logic live in the `.t27` spec with golden tests against the committed
`.stat` files; the shell never reduces numbers itself.

## Portfolio manifests

- `ARTIFACT_MANIFEST.txt` — `<sha256>  <path>` per deliverable, `#`-comment
  header. Gate G4 re-hashes every row from disk on each regression.
- `ARTIFACT_HASHES.txt` files (root and per artifact tree) — secondary hash
  indexes.
- Editing any manifested file requires refreshing its row in the same change
  (see docs/GETTING_STARTED.md).

## Regression logs

`evidence/regression/regress_*.log` — verbatim output of
`bash scripts/regress_all.sh` (G1-G5). Committed logs are historical evidence;
new runs for local iteration default to /tmp so the tree stays clean for G5.
