# M4 stage 2 — GPU correctness on predefined edge cases and seeded random vectors

STATUS: PASS (MEASURED, GPU executed; not a simulation, not an estimate)
AUTHORIZATION: owner `LAMB_LABS_GF16_GPU_CORRECTNESS`
BASELINE: `71745d5fa4cd6a17bc749a1108d6839fb80ed859` (closed stage 1 chain preserved)
STAGE-1 COMMIT: `e409323` (8-group golden smoke, 8/8 bit-exact)

## 1. What this stage adds

Stage 1 proved one 8-group golden smoke on the accepted cubin. Stage 2 extends the
same, already-authorized, correctness-only scope to the two predefined families
that stage 1 explicitly did **not** claim:

* 32 predefined **edge groups** (signed zeros, subnormal-by-SSOT codes, Inf, NaN
  payloads, smallest normal, one-ulp neighbours);
* 256 **seeded random groups** (SEED = 20261124, xorshift32-derived full-range
  GF16 codes, both operands random).

Total 288 groups. No performance, no power, no occupancy, no new kernel.

## 2. Pre-declared arithmetic contract (declared BEFORE the GPU run)

Declared in `scripts/gf16_dot4_host/gf16_gpu_batch.t27` before the batch launch:

1. **Finite expected group** → the GPU word must equal the exact-oracle f32 bits
   **bit-for-bit** (no tolerance, no ULP slack).
2. **NaN expected group** (Inf×0, Inf+(−Inf), or a NaN input lane entering the
   fma chain) → the GPU word must be **a NaN** (exponent all ones, mantissa
   nonzero). The **payload is not compared**, because the M2 conformance suite
   already records the documented divergence: the kernel's PTX decode keeps the
   hardware NaN payload, while the lane SSOT canonicalizes to `0x7FC00000`.
   This is a contract about the *class* of the result, fixed in advance, not a
   tolerance chosen after seeing results.
3. Signed zero: the kernel accumulator starts at `+0`; IEEE `(+0) + (−0) = +0`;
   product-level `−0 × 2 = −0`; a dot4 of signed zeros yields `0x00000000`.
   `−0 + −0 = −0` (`0x80000000`) is reachable and is covered by the edge set.

Expected values come from the **native `.t27` exact engine**
(`exact_dot4_bits` in `specs/igla/coder/gf16_dot4_conformance.t27`, M2, 13/13
PASS), never from the GPU. The GPU result is never used as an oracle.

## 3. Gate chain actually executed (owner order)

| # | Gate | Result | Evidence |
|---|------|--------|----------|
| 1 | native `.t27` oracle/comparator | M2 13/13 PASS; batch self-tests 4/4 | `reports/test_report_gf16_dot4_conformance.txt` |
| 2 | ABI / packing / byte order / kernel args / grid / bounds | M1 `HOST_ABI.md` + M3 harness 9/9 | `reports/test_report_gf16_dot4_harness.txt` |
| 3 | comparator negative test (intentional error) | M3 `g7_comparator_catches_one_bit_flip` PASS | same |
| 4 | full SHA-256 of cubin vs accepted manifest, **before** launch | `HASH_GATE: PASS (35e07b5f…)` | `reports/gpu_batch_run2.log` |
| 5 | small golden-vector smoke | 8/8 bit-exact (stage 1) and again in the gated transcript | `reports/gpu_smoke_gated.log` |
| 6 | synchronization / CUDA errors / output completeness / mismatch count | `cuCtxSynchronize` checked, `GPU_RUN_OK`, 288/288 words read | `reports/gpu_batch_run2.log` |
| 7 | edge cases + seeded random vectors | 288 groups, 0 finite mismatches, 0 NaN-contract violations | `reports/test_report_gf16_gpu_batch.txt` |

Every CUDA driver call in `scripts/gf16_dot4_host/cuda_smoke.c` is checked
(`CUDA_CHECK` on `cuInit`, `cuDeviceGet`, `cuCtxCreate_v2`, `cuModuleLoadData`,
`cuModuleGetFunction`, `cuMemAlloc_v2` ×3, `cuMemcpyHtoD_v2` ×2,
`cuLaunchKernel`, `cuCtxSynchronize`, `cuMemcpyDtoH_v2`, `cuMemFree_v2` ×3,
`cuModuleUnload`, `cuCtxDestroy`).

## 4. Results (MEASURED)

```
groups_checked          = 288
finite groups           = 250
finite mismatch_count   = 0
NaN-expected groups     = 38
NaN-contract violations = 0
```

`reports/gpu_batch_stats.txt` (emitted by the `.t27` module through
`t27c gen-text --fn batch_stats_dump`):

```
nan_grps=38
fmmatch=0
nanviol=0
```

`t27c test-report scripts/gf16_dot4_host/gf16_gpu_batch.t27` → **exit 0,
tests 6, pass 6, FAIL 0, rate 100.0 %** (authoritative header + per-test
`(passed)` lines; the "vacuous passes unknown" line is informational and also
appears in passing reports).

Raw artefacts (hashed in `../ARTIFACT_HASHES.txt`):

* `vectors/gf16_batch/a.bin` (2304 B) — packed A operands, 288 groups × 8 B;
* `vectors/gf16_batch/b.bin` (2304 B) — packed B operands;
* `vectors/gf16_batch/c_gpu.bin` (1152 B) — raw D2H output, 288 × f32 LE;
* `vectors/gf16_batch/c_gpu_smoke8.bin` (32 B) — raw D2H output of the 8-group
  gated smoke.

## 5. Defect found and fixed during this stage (no oracle tuning)

**Defect A — host runner grid did not cover `p_n` (host-side, found before any
oracle comparison).** The first batch launch used a hard-coded grid of
`1×1×1` (correct for the 8-group smoke). With 288 groups, block `256×1×1` and
grid `1` cover only `gid < 256`, so groups 256..287 were never computed and the
D2H read returned untouched allocation contents (`00000000`).
Evidence: `reports/gpu_batch_run1_grid_defect.log`. That attempt was discarded
**before** any comparison against the oracle — no expected value was ever
adjusted to a GPU observation. The runner was fixed to launch
`gx = ceil(n/256)` blocks (ABI rule: `gid = ctaid.x*ntid.x + tid.x`, grid may
exceed `p_n`), recompiled, and the batch was re-run from the same inputs:
`reports/gpu_batch_run2.log` (`GPU_RUN_OK cubin_bytes=4648 n=288 dev=0`).

**Defect B — `.t27` seed derivation overflow (oracle side, before the run).**
The first batch self-test run failed 4/4 because the seed derivation used
`g * 2654435761`, which overflows `u32` for `g >= 17` and traps in `.t27`.
Fixed by deriving the seed with small multipliers (`g*7919 + k*40503`) followed
by six xorshift32 rounds; the batch is therefore deterministic and
reproducible from `BATCH_SEED = 20261124` alone.

**Defect C — cross-file `.t27` imports do not resolve for scripts-local
modules.** A separate verdict module could not `use` the batch module
(`gf16_dot4_gpu_batch.zig: FileNotFound`; qualified access with a hyphenated
module name is not parseable). Resolved by keeping the verifier in the same
module as the generator (the M2 conformance pattern), so the verdict and the
oracle live in one compile unit.

**Defect D — device ordinal (stage-1 defect, fixed in the committed script).**
`scripts/gf16_dot4_host/gpu_smoke.sh` still passed ordinal `1`; the CUDA driver
in this WSL2 container exposes exactly one logical device (`cuDeviceGetCount
== 1`), which is the free physical RTX 3070 Laptop (physical nvidia-smi index
1). The committed script now uses CUDA ordinal `0`, with the reasoning recorded
in its header. `reports/gpu_smoke_gated.log` is the clean single-transcript run
of the corrected script: `HASH_GATE: PASS` → `GPU_GATE: PASS` → `BUILD: gcc
ok` → `GPU_RUN_OK … n=8 dev=0` → `runner_exit=0` → `smoke_c.bin bytes: 32` →
`M4_SMOKE_DONE rc=0`.

## 6. Device / environment facts used (MEASURED)

* `nvidia-smi` (WSL inventory): two RTX 3070 Laptop GPUs; physical GPU0 busy
  (~14.5 GiB used), physical GPU1 free (~15.3 GiB free of 16 GiB).
* CUDA driver API inside the container: `cuDeviceGetCount == 1`; ordinal 0 =
  the free RTX 3070 (15275 MiB free of 16384 MiB); ordinal 1 → CUDA error 101
  (`CUDA_ERROR_INVALID_DEVICE`) and **no launch, no context, no allocation**.
* The busy physical GPU0 is not exposed to CUDA here and was never touched.
* Remote lane (writes confined there):
  `/home/t27ssh/t27os/lanes/gf16-dot4-ptx-20261123T071500Z/`.

## 7. Limits of this stage (explicit, not hidden)

* Correctness only. **No** performance, throughput, occupancy, latency,
  bandwidth, power or energy numbers were produced or are claimed here.
* The verified surface is exactly one kernel (`gf16_dot4`), `sm_86`, one cubin
  (`35e07b5f…`), one host runner, one container GPU. No other kernel, no other
  architecture, no other consumer GPU is covered.
* The NaN payload of the kernel is not compared to the SSOT canonical payload
  (documented divergence, M2). Class-level NaN equality is the contract.
* 288 groups is a regression batch, not a proof for all 2^32 input pairs.
* `TRAINING_APPROVED=false`; no training or tuning was performed; no tolerance
  was adjusted after any inconvenient observation.
