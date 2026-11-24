# scripts/gf16_dot4_host — host-side GF16 dot4 harness and GPU runner

Host side of the GPU branch of the Lamb Labs vertical stack. Everything semantic — oracle,
comparator, verdict, vector generation — is **native `.t27`**. The only non-`.t27` file is the CUDA
driver-API bridge (`cuda_smoke.c`), whose sole job is to call the CUDA driver API and move bytes.

## Files

| File | Language | Role |
|---|---|---|
| `gf16_harness.t27` | `.t27` | CPU-only gate harness G1–G7: cubin SHA-256 identity + corruption rejection, packing vs measured binary words, little-endian byte order, grid/bounds semantics, alignment, mock execution respecting bounds, comparator negative test. **Never touches CUDA.** |
| `gf16_gpu_smoke_verdict.t27` | `.t27` | 8-group golden smoke verdict against the observed GPU words (stage 1). |
| `gf16_gpu_batch.t27` | `.t27` | Stage 2: 32 predefined edge groups + 256 seeded random groups (SEED 20261124), the pre-declared arithmetic contract, the exact-oracle verdict over the 288 observed GPU words, and `batch_stats_dump`. Generator and verifier live in **one module** on purpose: `.t27` `use` does not resolve scripts-local modules by file stem, and a hyphenated module name cannot be called qualified. |
| `cuda_smoke.c` | C | CUDA **driver API** bridge: init → device → context → module load → function → allocations → H2D → launch → synchronize → D2H → free → unload → destroy. Every call is checked. Grid is derived from `p_n`: `gx = (n + 255) / 256`. |
| `gpu_smoke.sh` | shell | Gated remote transcript: hash gate **before** launch → GPU inventory/free-memory gate → build → launch → synchronize → D2H → completeness check. |
| `device_probe.c` | C | Read-only probe of the CUDA-visible device count and free memory. |
| `gf16_cpu.py` | Python | **Superseded** exact CPU oracle, kept only for cross-checking older evidence. Not used by any current verdict path. |

## Run the native parts (no GPU required)

```sh
t27c test-report scripts/gf16_dot4_host/gf16_harness.t27          # 9/9 PASS
t27c test-report scripts/gf16_dot4_host/gf16_gpu_smoke_verdict.t27 # 1/1 PASS
t27c test-report scripts/gf16_dot4_host/gf16_gpu_batch.t27         # 6/6 PASS
```

`test-report` is authoritative; plain `t27c test` only lists declarations and can exit 0 with
unresolved imports. A "vacuous passes unknown" line in a report is informational and also appears in
passing reports — the header count line plus the per-test `(passed)` lines are the verdict.

## Run the GPU part

On the CUDA host (WSL2 / CUDA 12.4), with the accepted cubin and the input binaries in the lane
scratch directory:

```sh
./gpu_smoke.sh    # n=8 golden smoke, device ordinal 0
```

Device ordinal: the CUDA driver inside this container exposes exactly **one** logical device
(`cuDeviceGetCount == 1`) — the free physical RTX 3070 Laptop (physical nvidia-smi index 1).
Ordinal 1 returns `CUDA_ERROR_INVALID_DEVICE (101)` and launches nothing. The busy physical GPU0
is not exposed to CUDA here and is never touched.

## Rules that must not be broken

* The cubin SHA-256 must be checked against the accepted manifest **before** `cuModuleLoadData`.
* The grid must be derived from `p_n`; a hard-coded `gx=1` silently truncates `n > 256` and returns
  uninitialized device memory for the tail (this defect was found in stage 2 and the first attempt
  was discarded **before** any oracle comparison).
* The expected values always come from the native exact engine. A GPU result is never used as an
  oracle, and no tolerance is adjusted after an inconvenient observation.
* NaN contract (declared before the run): a group whose exact result is NaN must produce a NaN on
  the GPU; the payload is not compared, because the kernel keeps the hardware payload while the
  SSOT canonicalizes it.
* `cuCtxSynchronize()` must be checked before the D2H copy, and the number of checked groups and
  the mismatch count must be reported.
* `TRAINING_APPROVED=false`; no training or tuning in this directory.
