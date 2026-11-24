# HANDOFF — Lamb Labs vertical stack (GPU branch closed at M5, hardware branch audited)

Date: 2026-11-24 (Asia/Bangkok). Lane: `dsh-5344b40f-4225`.
Baseline (preserved, never rewritten): `71745d5fa4cd6a17bc749a1108d6839fb80ed859`.

## Commit chain

| Commit | Stage | Content |
|---|---|---|
| `71745d5` | baseline | closed GF16 dot4 PTX → cubin → hashes (pre-existing) |
| `9186a24` | M0 | readiness matrix over the closed chain |
| `2df7d58` | M1 | written host ABI contract + machine-readable vectors + cross-checked upstream host audit |
| `5562b1d` | M2 | native `.t27` exact oracle/conformance suite — 13/13 PASS |
| `d36dc85` | M3 | native `.t27` CPU-only gate harness — 9/9 PASS (+ SHA-256 module, 5/5) |
| `e409323` | M4 stage 1 | GPU golden smoke 8/8 bit-exact, hash-gated, zero CUDA errors |
| `d702b8f` | M4 stage 2 | GPU edge + seeded-random batch: 288 groups, 0 finite mismatches, 0 NaN-contract violations; host grid fix; ordinal fix |
| `5974a91` | M5 | read-only inventory of the spec→RTL→simulation→FPGA chain (hardware branch) |
| `5131ad9` | M7 | vertical-stack review docs: HANDOFF, bundle README, readiness updates |
| `002139f` | acceptance audit | `gpu/GPU_ACCEPTANCE_M4.md`: PTX FMA chain vs oracle per-step rounding, GPU_C provenance, path corrections |
| `5cdf614` | regression | 7 native suites re-run at HEAD, all exit 0 (`reports/final_regression_20261124.txt`) |
| `570bd19` | readiness | A7 cites the acceptance audit (per-step FMA contract, owner acceptance pending); B1 records GF(2^4) vs float-GF16 domain boundary |
| `af8991d` | regression | 7 suites re-verified on w3070 at HEAD `570bd19` (`reports/final_regression_head570bd19.txt`); Mac stock t27c blocks the conformance spec — toolchain trap recorded |

## Where the chain stands

**GPU branch (A):** closed and reproducible from the baseline through bit-exact GPU correctness on
288 groups. Every artifact is hashed; every CUDA call is checked; the oracle is native `.t27` and
never derived from the GPU. The arithmetic contract is pinned in `gpu/GPU_ACCEPTANCE_M4.md`:
`s0 = +0; s(i+1) = RN_f32(a_i*b_i + s_i)`, i = 0..3 — FOUR `fma.rn.f32` roundings, one per step
(`fma_single_round_criterion` asserts the exact oracle rounds identically per step; it is NOT one
final rounding of the whole dot4 sum).

**Hardware branch (B):** audited, not closed. The shipped `.bit`'s spec→RTL link is **broken**
(absent `ternary_mac_demo_top.v`, no `.t27` for it), the GF16 testbenches produce **no outputs**,
the MAC datapath on silicon is dead, and power is **not measured**. The corrected-attention branch
has verified math (12 000 trials, 0 mismatches) and measured resources, but **no spec** and
**no silicon**.

**Performance / power (third track):** still unauthorized. Portfolio `~0.7 W` / `~0.12 J/token`
remain ESTIMATED; the measured J/token gap stays open.

## Reproducibility recipe

1. `python3 scripts/manifest.py` → regenerate root hash index + manifest; compare with
   `evidence/vertical_stack/ARTIFACT_HASHES.txt`.
2. `t27c test-report scripts/gf16_dot4_host/gf16_harness.t27` → 9/9.
3. `t27c test-report scripts/gf16_dot4_host/gf16_gpu_smoke_verdict.t27` → 1/1.
4. `t27c test-report scripts/gf16_dot4_host/gf16_gpu_batch.t27` → 6/6.
5. On the CUDA host: `scripts/gf16_dot4_host/gpu_smoke.sh` → hash gate, GPU gate, build, launch,
   sync, D2H, completeness (ordinal 0).

## Known traps (each one cost a failed run)

* `t27c test` exits 0 with unresolved imports → use `t27c test-report`.
* `.t27` integer `*` traps on overflow → keep multipliers small or use `+%` / `-%`.
* An all-digit string literal is lexed as a number → emit digits arithmetically.
* `use` takes the **module name**, not the file stem; hyphenated module names cannot be called
  qualified → keep generator + verifier in one module.
* Never transcribe expected bit patterns or binary words by hand → read them from engine dumps or
  from the artifacts themselves.
* Host grid must be `ceil(p_n / 256)`; a fixed `gx=1` returns uninitialized memory for the tail.
* CUDA ordinal here is 0 even though the free physical GPU is nvidia-smi index 1.
* The upstream conformance set uses a different E=0 convention and re-rounds through GF16 → it is a
  cross-reference, never an oracle for this kernel.
* The local `t27c` binary can disappear or regress: the lane build (`/Users/playra/.local/bin/t27c`,
  sha `5da927df…`) was removed and the remaining Mac binary (`~/.cargo/bin/t27c`, Nov 13,
  sha `1f5728a1…`) is a stock build that BLOCKS the conformance spec
  (`spec.zig:539:30`, slice-coercion defect class). Check the toolchain sha BEFORE reruns;
  verified-good: w3070 `/home/t27ssh/t27os/bin/t27c` sha `5785e3ca…` + zig 0.16.0 on PATH.
  Never edit a passing spec to satisfy a stale compiler.
* w3070 scratch copies (`~/t27-work/<name>` WITHOUT a `.git`) are deleted by the idle-sweep and
  leave no rescue branch — hash-verify any remote snapshot IN THE SAME SESSION that produces it;
  the lane worktree is the source of truth for every rerun.
* `specs/fpga/gf16_accel.*` is GF(2^4) FIELD arithmetic (`GF16_FIELD_POLY=19`, no float tokens in
  the `.v`) — a DIFFERENT numeric domain from the binary-float lane GF16 of `specs/numeric/gf16.t27`;
  same letters "GF16", different math. FPGA is NOT part of GPU acceptance; connecting it is a
  separate owner decision (hardware chain currently GAP: broken spec→RTL for the shipped artefact,
  no testbench outputs, no measured power).

## Open owner decisions

1. Whether to authorize the performance/power methodology (separate task; no benchmarks run).
2. Whether to fund the hardware branch: spec→RTL for the shipped artefact, a real testbench run
   with waveforms, and a rebuilt bitstream — or to formally withdraw the silicon claims.
3. Whether the GPU branch should continue with additional kernels (out of scope without a new task).
4. Which `t27c` build is canonical for future reruns (w3070 `5785e3ca…` verified 2026-11-24; the
   Mac stock build blocks the conformance suite).
