# GPU Acceptance Record — D1 PIN (ORDER LAMB_LABS_VERTICAL_CONSOLIDATION_MERGE_GO)

STATUS: PINNED by owner decision D1, 2026-11-25. This file records that the owner has
pinned the GPU acceptance basis exactly as verified in `gpu/GPU_ACCEPTANCE_M4.md`.
It adds no new measurements and authorizes no new runs.

## Pinned result set (source: `gpu/GPU_ACCEPTANCE_M4.md:235-240`)

| Check | Result |
|---|---|
| Smoke | 8/8 bit-exact |
| Batch | 250 finite groups, mismatch 0 |
| NaN groups | 38 expected, violations 0 |
| CUDA errors | 0 |

Environment of record: win11-3070, CUDA 12.4.131, ptxas `sm_86`, artifacts
`gf16_dot4.ptx` (sha `b9a79404…`) / `gf16_dot4.cubin` (sha `35e07b5f…`), under the
owner authorization `LAMB_LABS_GF16_GPU_CORRECTNESS`.

## Scope of the PIN

- Acceptance is **correctness-scope only**. No GPU performance or power claim is pinned,
  exists, or is implied (L7 NOT_RUN; D2 keeps perf/power a separate, not-yet-authorized task).
- The pinned record lives in this repository; reruns require the canonical toolchain
  (`CANONICAL_TOOLCHAIN.md`) and owner approval for any new GPU run.
- Owner boundary honored: GPU acceptance is NOT part of FPGA acceptance; GF16-on-GPU and
  GF16-on-FPGA are different math (no GF16 dot4 RTL exists).
