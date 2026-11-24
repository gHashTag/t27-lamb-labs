# PROVENANCE — M1 host-ABI contract (vertical stack)

Session: 2026-11-23 (Asia/Bangkok), CPU-only. No CUDA init, no kernel launches, no
host<->device transfers, no GPU execution (M4 NOT_AUTHORIZED). Baseline commit
`71745d5fa4cd6a17bc749a1108d6839fb80ed859`; M0 commit `9186a24` on top.

## Chain of custody

1. **Numeric SSOT** `specs/numeric/gf16.t27`
   sha256 `b6324424a887cd93b697732f90445861850fa8d36b38098eab2d578b2c26d532`
   (`gf16_decode_to_f32`, lines 172–198). Read-only reference for semantics.

2. **Kernel spec** `specs/igla/coder/gf16_dot4_ptx.t27`
   sha256 `dd74e62584a0aa8896eaf125a43828c593a4b11038b2445590d11df42e227914`
   (golden tests lines 217–277). Closed earlier in this lane; PTX bundle
   `artifacts/gf16-dot4-ptx/` (index 17 entries, cubin sha256 `35e07b5f…`).

3. **Human ABI contract** `evidence/vertical_stack/HOST_ABI.md` — derived from the hashed
   PTX/cubin + kernel spec; 9 sections; updated 2026-11-23 with the oracle result
   (see step 6).

4. **Machine ABI twin** `evidence/vertical_stack/host_abi_vectors.json`
   (schema `host-abi-vectors-v1`) — kernel entry/params/geometry, buffer layout and
   alignment, lane packing, numeric contract, compare rules, adopted vectors with
   provenance and SHA-256s, 4 spec-golden vectors with spec line references.

5. **Adopted vectors** `evidence/vertical_stack/vectors/{gf16_dot4_a,gf16_dot4_b,
   gf16_dot4_expected}.bin` — byte-copies (SHA-256 verified) of upstream
   `/Users/playra/t27/artifacts/golden-chain/2026-11-19-night/research_tools/`
   (read-only upstream tree; `a` `6f2bddc4…`, `b` `ad4246d5…`, `expected` `35a90eef…`).
   Upstream `gf16_dot4_c.bin` (sha256 identical to `expected.bin`) was NOT adopted.

6. **Exact CPU oracle** `scripts/gf16_dot4_host/gf16_cpu.py` — pure-stdlib Fraction core:
   SSOT decode, exact products (≤22 significand bits ⇒ exact in f32), RN-even binary32
   rounding, chained-fma accumulation, NaN-aware/signed-zero-aware compare, little-endian
   expected decoding. Measured run: `reports/oracle_selfcheck_m1.txt`
   → **PASS 12/12 bit-exact** (8/8 adopted groups, 4/4 spec golden), exit 0.

## Diagnostic history (honest record)

- First JSON generation attempt refused to write (`host_abi_vectors.json` absent): oracle
  appeared to mismatch 0/8 adopted groups. Diagnosis: `expected.bin` stores
  **little-endian f32**; the earlier check parsed the hex as big-endian u32 words. After
  correcting byte order, all 8 groups reproduce exactly. A transient NaN scare
  (`0x7dff`) was a hex misread (`0x7dff` is e=62 finite; only `0x7fff`/e=63 lanes are
  special). Oracle bugs found and fixed during this work: lane slice stride, u16-hex vs
  byte-hex convention. All recorded in `reports/oracle_selfcheck_m1.txt` (final state)
  and this file.

## Standing conflicts (documented, unresolved by assertion)

- Upstream `conformance/gf16_ref.py` + `gf16_conformance_v0.json` decode E=0,M≠0 as
  subnormal `M·2^-39`; lane SSOT/PTX decode as `2^-31·(1+M/512)`. The adopted bins do
  NOT discriminate the two conventions (e0-subnormal contributions are absorbed by f32
  rounding in every adopted group); the conflict affects other inputs and remains open
  for M2 boundary vectors.
- Upstream `gf16_ref.py` dot4 re-rounds products through GF16 → NOT a valid oracle for
  the f32-FMA-chain kernel. Conformance set is cross-reference only.
- `ZIG_CONFIRMATION.md:24-27` vs `OVERNIGHT_SUMMARY.md:1150-1153` contradiction — cited
  both in M0, unchanged.

## Unverified

- Device execution of cubin `35e07b5f…` — M4, NOT_AUTHORIZED (original M1 statement).
  Nothing in the sections above (items 1–5) is GPU evidence. All labels above are
  MEASURED (CPU) or pointers to upstream artifacts.

## Authorized GPU correctness addendum (M4 e409323 → d702b8f, owner gate
LAMB_LABS_GF16_GPU_CORRECTNESS)

Session: 2026-11-24 (Asia/Bangkok). M4 stage 1 (`e409323`) and stage 2 (`d702b8f`) GPU
correctness runs are separately authorized under the owner gate
`LAMB_LABS_GF16_GPU_CORRECTNESS`. The original CPU-only provenance above is preserved
as the state at generation time.

1. **M4 stage 1 smoke** (`evidence/vertical_stack/gpu/GPU_RUN_M4_STAGE1.md`):
   - Authorization + pre-launch gates (M2 oracle 13/13 PASS, ABI M1, comparator negative
     tests, hash gate PASS before launch, 8-group golden smoke).
   - Run-1 failure: device ordinal 1 → CUDA 101, no launch, state preserved.
   - Run-2 success: full CUDA call sequence with ordinal 0, output words all matching
     `ADOPTED_EXP` exactly (groups_checked=8, mismatch_count=0).
   - CUDA errors: 0.
   - NaN contract: no NaN products in the smoke set; all 8 groups finite.
   - Signed-zero semantics: acc starts +0; `(+0)+(−0)=+0`; `−0×2=−0`; dot4 of signed
     zeros → `0x00000000`; `−0+−0=−0` (0x80000000).
   - Limitations: WSL virtual device cannot be pinned to physical index; one kernel/sm_86/
     one cubin/one GPU; NaN payload not compared beyond class-level.

2. **M4 stage 2 batch** (`evidence/vertical_stack/reports/test_report_gf16_gpu_batch.txt`):
   - 288 groups checked (32 edge + 256 random, SEED=20261124).
   - Finite groups: 250; finite mismatch count: 0.
   - NaN-expected groups: 38; NaN contract violations: 0.
   - `nan_grps=38`, `fmmatch=0`, `nanviol=0`.
   - All 288 observed GPU words embedded; finite groups bit-exact to oracle.
   - NaN class-level contract: expected NaN groups produce NaN output (payload not
     compared per documented M2 divergence: kernel PTX keeps payload, SSOT canonicalizes).
   - CUDA errors: 0; all calls checked; execution synchronized; output fully read.
   - Grid geometry: `gx = ceil(n/256)` derived from `p_n`, not hard-coded.
   - Limitations: one kernel/sm_86/one cubin/one logical GPU; NaN payload not compared;
     288 groups ≠ proof; TRAINING_APPROVED=false; no performance/power experiments.

3. **Device-ordinal rule** (documented in `scripts/gf16_dot4_host/gpu_smoke.sh` lines 1–12,
   and `cuda_smoke.c`):
   - CUDA driver inside this WSL2 exposes exactly ONE logical device
     (`cuDeviceGetCount == 1`); dev 0 = free physical RTX 3070 Laptop with 15275 MiB free
     of 16384 MiB.
   - Physical nvidia-smi index 1 = the free GPU; index 0 = busy GPU (~14.5 GiB used).
   - Runner/script must use CUDA ordinal **0**; distinguish CUDA ordinal (0) from physical
     nvidia-smi index (1).
   - Run with ordinal 1 → `CUDA_ERROR_INVALID_DEVICE (101)`; no kernel launched, no
     context/device memory created beyond the failed `cuDeviceGet`.

4. **Hash-gate requirement**: Before `cuModuleLoadData`, the cubin SHA-256 must match the
   manifest `35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc`.
   Run-1 hash gate passed; run-2 hash gate passed after grid fix.

5. **Exit/verdict summary**:
   - M4 smoke: `GPU_RUN_OK cubin_bytes=4648 n=8 dev=0`, 8 output words all matching
     `ADOPTED_EXP` → PASS (1/1 test report).
   - M4 batch: exit 0, `GPU_RUN_OK cubin_bytes=4648 n=288 dev=0`, 288 output words;
     finite mismatch 0, NaN violations 0 → 6/6 test report PASS.
   - Evidence files: `.scratch/gf16/m4/gpu_smoke_run2.log`, `.scratch/gf16/m4/batch_run2.log`,
     `cuda_smoke.c` (patched grid fix), `gpu_smoke.sh` (ordinal fix).
