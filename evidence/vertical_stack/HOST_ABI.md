# GF16_DOT4_HOST_ABI_V1 — exact contract for launching `gf16_dot4`

- Source of truth: hashed kernel text `artifacts/gf16-dot4-ptx/gf16_dot4.ptx`
  (sha256 `b9a79404bb5c06095fa1b831ad45f3bf1eef2378b74702bad1615237534d5e51`)
  and its SASS dump `artifacts/gf16-dot4-ptx/cuobjdump_sass.log`; emitter
  `specs/igla/coder/gf16_dot4_ptx.t27` (sha256 `dd74e625…`). Everything below is
  DERIVED_FROM_ARTIFACT unless marked INFERENCE or UNVERIFIED.
- Machine-readable twin: `host_abi_vectors.json` in this directory (schema + adopted
  vectors + provenance). This file and the JSON must be updated together.

## 1. Kernel identity

| field | value | source |
|---|---|---|
| entry name | `gf16_dot4` | PTX `.visible .entry gf16_dot4(`; `KERNEL_NAME` gf16_dot4_ptx.t27:33 |
| target | `sm_86` (PTX 7.1, `.address_size 64`) | PTX header; cubin built by ptxas CUDA 12.4.131 |
| threads/block | exactly 256 (`.maxntid 256, 1, 1`) | PTX; `THREADS` gf16_dot4_ptx.t27:35 |
| shared memory | 0 | no `.shared` in PTX/SASS (DERIVED_FROM_ARTIFACT) |
| registers/thread | 22, 0 spill bytes | `artifacts/gf16-dot4-ptx/ptxas_verbose.log` (MEASURED 2026-11-23T07:15Z) |

## 2. Parameters (cuLaunchKernel `kernelParams` order is fixed)

| # | name | type | bytes | meaning |
|---|---|---|---|---|
| 1 | `p_a` | `.u64` device pointer | 8 | base of the A group array |
| 2 | `p_b` | `.u64` device pointer | 8 | base of the B group array |
| 3 | `p_c` | `.u64` device pointer | 8 | base of the f32 output array |
| 4 | `p_n` | `.u32` | 4 | group count n (also output count) |

- The kernel runs `cvta.to.global.u64` on all three pointers (PTX prologue,
  gf16_dot4_ptx.t27:74-76): pass plain `CUdeviceptr` values from `cuMemAlloc_v2`; do not
  pre-offset into a space window.
- Parameter order in the PTX param block is exactly the declaration order above; the
  host passes an array of 4 pointers to these values in this order (DERIVED_FROM_ARTIFACT;
  byte-offset layout inside the param block is the driver's job, not ours — INFERENCE).

## 3. Memory layout and alignment

- A and B are arrays of 8-byte groups. Group i = bytes `[8i, 8i+8)`, loaded as one
  `ld.global.v2.u32 {w0, w1}` (little-endian: w0 = bytes 0..3, w1 = bytes 4..7).
- The four GF16 lanes of group i: lane 0 = low u16 of w0, lane 1 = high u16 of w0,
  lane 2 = low u16 of w1, lane 3 = high u16 of w1 (emit_lane mapping,
  gf16_dot4_ptx.t27:108-114). Equivalently: u16 element 2j of the byte stream is lane 2j/2
  ... concretely element k (0..3) = u16 at byte offset 8i + 2k.
- Required sizes: A and B each >= 8*n bytes; C >= 4*n bytes. The kernel does NO bounds
  check beyond the thread guard — undersized buffers are silent corruption, host's duty.
- Base alignment: A and B 8-byte aligned (v2.u32 loads), C 4-byte aligned
  (`st.global.f32`). `cuMemAlloc_v2` returns >= 256-byte alignment; sub-buffer offsets must
  preserve the per-array alignment above.
- Output: c[i] = one `st.global.f32` at byte offset 4*i, written iff thread's group i < n.

## 4. Grid / block / bounds semantics

- Thread gidx = `ctaid.x * ntid.x + tid.x` (`mad.lo.u32`), guard: `gidx >= p_n` ->
  branch to `DONE`, thread writes nothing and exits. Extra threads are free; the grid MAY
  exceed n, but wasted lanes are pure overhead — launch exactly ceil(n/256) blocks.
- `grid_dim(n) = ceil(n/256)` in x only; gridDim.y = gridDim.z = 1 (kernel only reads
  ctaid.x/tid.x/ntid.x); blockDim.x = 256, blockDim.y = blockDim.z = 1.
- n == 0: `grid_dim(0) = 0`; CUDA rejects a zero grid dimension (INFERENCE from the driver
  API contract). Host rule: skip the launch entirely; there are no outputs and nothing to
  compare.
- n max: p_n is u32 — n <= 2^32 - 1; also 8*n must fit the allocation size domain.
- No synchronization inside the kernel; correctness requires the host to
  `cuCtxSynchronize` (or stream-sync) before reading C.

## 5. Numeric contract (per output element)

- c[i] = (((d(a0)*d(b0) + d(a1)*d(b1)) + d(a2)*d(b2)) + d(a3)*d(b3)), each `+` a single
  `fma.rn.f32` (multiply-add fused, round-to-nearest-even), accumulator starts at +0.0,
  lane order 0,1,2,3 (four chained `fma.rn.f32`, gf16_dot4_ptx.t27:167-176 test).
- d = the PTX decode emitted by `emit_gf16_decode_f32` (specs/igla/coder/ptx_emit.t27),
  equivalent to SSOT `gf16_decode_to_f32` (specs/numeric/gf16.t27:172-198):
  value = (-1)^S * 2^(E-31) * (1 + M/512) for E in 0..62; e==0&&m!=0 gives
  2^-31*(1+m/512) on BOTH sides (verified this session by source audit); e==63&&m==0 -> ±Inf;
  e==63&&m!=0 -> NaN.
- The ONLY known SSOT-vs-hardware divergence: NaN payload. SSOT returns canonical
  `std.math.nan(f32)`; the hardware path keeps payload bits. Comparisons must be
  NaN-aware (both-NaN = equal), never bitwise over NaN.
- fma vs separate mul+add: a GF16*GF16 product has <= 22 significand bits (9+9+4 from the
  1+M/512 forms with exponent difference), exact in f32; with an exact product the fused
  and unfused roundings coincide, so `dot4_golden` (gf16_dot4_ptx.t27:144-152) and the
  kernel agree bitwise on finite values (DERIVED_FROM_ARTIFACT + arithmetic argument;
  the M2 oracle re-checks this numerically).
- Signed zero: +0.0 accumulator plus a -0.0 lane product stays +0.0 in RN arithmetic;
  -0.0 as a final result can only arise from negative products summing to zero — the M2
  oracle models this exactly; conformance JSON `neg_zero` (0x8000) decodes to -0.0 on
  both sides.

## 6. Existing host interface facts (upstream, read-only)

- `ptx_run` at upstream commit `44c8c62a73d689f20c713a0e1da563825a0361ee`,
  `bootstrap/src/host/driver.rs:303`: signature `(kernel: u32, m, n, k, iters, stride)`;
  kernel ids 0 = ternary_gemm, others routed to `hslm_bwd`-style names via encoded id;
  host data generated internally (`gen_a`, `gen_wp`); six launch args `(a,w,c,m,n,k)`;
  mismatch counters exist only for the two HSLM kernels; everything gated
  `#[cfg(feature = "cuda")]`.
- `bootstrap/src/main.rs` `Commands::PtxRun` ~L1576 dispatches that command; there is NO
  GF16 kernel id, no host-data input path, no per-group f32 output check there.
- Consequence: upstream `ptx_run` cannot launch `gf16_dot4`. A minimal launcher must
  load OUR PTX/cubin via `cuModuleLoadData` + `cuModuleGetFunction("gf16_dot4")` and
  launch with the section-2 params. This is the #14143/#10360 gap; nothing in this lane
  changes Rust or runs CUDA.

## 7. Host-side pre-launch checklist (any future launcher)

1. Hash-check the binary before load: cubin sha256 `35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc`
   (or PTX sha256 `b9a79404…` if loading text). Mismatch = abort, no launch.
2. Device must be sm_86 (compute capability 8.6) for the cubin; PTX text can JIT forward but
   that path is UNVERIFIED — do not claim correctness on other archs.
3. `cuInit(0)` -> `cuDeviceGet` -> `cuCtxCreate_v2` -> `cuModuleLoadData` ->
   `cuModuleGetFunction("gf16_dot4")`; then `cuMemAlloc_v2` A(8n), B(8n), C(4n);
   `cuMemcpyHtoD_v2` A, B; launch; `cuCtxSynchronize`; `cuMemcpyDtoH_v2` C.
4. Launch geometry: gridDimX = ceil(n/256), gridDimY = gridDimZ = 1, blockDimX = 256,
   blockDimY = blockDimZ = 1, sharedMemBytes = 0, stream = 0 (NULL stream acceptable).
5. n == 0 -> skip launch, report empty pass. Inputs validated BEFORE any CUDA call
   (sizes, alignment of any sub-offsets, vector file hashes).
6. Compare outputs to the oracle with the rules: bit-exact for finite values;
   both-NaN = pass; +0.0 vs -0.0 = FAIL unless the oracle says the sign matches.
   Count and report every mismatch index — a "summarize only" harness hides corruption.
7. Copy nothing to the GPU before 1-5 pass. Any failure path must leave no device state
   behind that a later authorized run could mistake for evidence.

## 8. Adopted machine-readable vectors (provenance)

- `vectors/gf16_dot4_a.bin` (64 B, 8 groups), `vectors/gf16_dot4_b.bin` (64 B),
  `vectors/gf16_dot4_expected.bin` (32 B, 8 f32) adopted from upstream
  `artifacts/golden-chain/2026-11-19-night/research_tools/` (read-only, upstream tree),
  sha256s `6f2bddc4…`, `ad4246d5…`, `35a90eef…` — exact hashes in host_abi_vectors.json.
- Upstream also has `gf16_dot4_c.bin` byte-identical to `..._expected.bin` (same sha256
  `35a90eef…`): likely the recorded output of the upstream night run. We adopt ONLY the
  (a, b, expected) triple as input/reference vectors; `c.bin` adds no information.
- VERIFIED-REPRODUCED (CPU, 2026-11-23): the exact oracle `scripts/gf16_dot4_host/gf16_cpu.py`
  re-derives all 8 `expected.bin` values bit-exactly from `a.bin`/`b.bin` under the SSOT decode
  + chained `fma.rn.f32` semantics (8/8 adopted + 4/4 spec golden = 12/12, see
  `reports/oracle_selfcheck_m1.txt`). Note: `expected.bin` stores LITTLE-ENDIAN f32; earlier
  "0/8 mismatch" was a byte-order misreading of this fact, not a semantic divergence. This is
  CPU corroboration only — it does NOT make the bins independent GPU evidence (M4 unrun).
- The 10 scalar GF16 vectors embedded in the spec tests
  (`pos_zero 0x0000 … pi 0x4124`) come from upstream
  `conformance/vectors/gf16_conformance_v0.json` (sha256 `5081a1ec…`, verified identical to
  canonical commit `44c8c62a…` this session); the 4 non-trivial dot4 test groups from
  gf16_dot4_ptx.t27:217-277 are included in the JSON as `spec_golden` vectors with their
  spec line references.
- Status of these vectors: MEASURED upstream (2026-11-19-night chain), re-derivable locally
  by the M2 oracle; no GPU is needed to validate them.

## 9. UNVERIFIED / open items

- UNVERIFIED: actual device execution of this cubin (M4, NOT_AUTHORIZED).
- UNVERIFIED: JIT-from-PTX behavior on non-sm_86 devices.
- UNVERIFIED: param-block byte offsets (driver-managed; section 2 notes the contract only
  in terms of kernelParams order).
- UNVERIFIED: whether upstream `ptx_run` could ever be extended in place without the
  #14143/#10360 fix — out of scope here.
- INFERENCE items are marked inline; every INFERENCE above must be re-derived (not copied)
  by the M3 harness checks before any authorized GPU run.
