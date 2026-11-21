# Benchmark artifacts

Machine-readable co-design interface for the Lamb Labs ternary model-hardware loop.

| File | Purpose |
|---|---|
| `rl_ready_benchmark.json` | state / action / reward contract + the 11 already-evaluated states |
| `per_param_efficiency.json` | normalised per-parameter table with the required non-parity label |
| `validate_benchmark.py` | checks every number against the measured evidence; fails on drift |

## Validate

```bash
python3 benchmark/validate_benchmark.py
```

The validator fails if:
- an evaluated state has no matching measured configuration in `evidence/`
- a state's LUT/LC/DSP count disagrees with the measured value
- a state exceeds the resource cap but is marked ACCEPTed
- a per-parameter row marked `NOT MEASURED` carries a number
- the required non-parity label is missing
- the zero-DSP invariant is broken in any measured configuration

## What this is NOT

This is a **benchmark contract**, not an RL system. No state-action-reward loop exists yet.
The reward is defined so that such a loop would be reproducible against this evidence;
calling the current work "RL" would be false.

## Normalisation label

Every per-parameter figure is labelled:

> edge-scale prototype comparison, not performance parity with 27B-class MPU

The only measured throughput belongs to the demonstrated ternary-MAC primitive. The 1M and 2M
rows are scope markers with an open feasibility question, explicitly `NOT MEASURED`.
