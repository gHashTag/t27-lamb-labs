# M4 stage 1: GPU golden-vector smoke of the accepted GF16 dot4 cubin

Authorization: LAMB_LABS_GF16_GPU_CORRECTNESS (owner, 2026-11-23). Machine:
win11-3070, WSL2, CUDA 12.4 (ptxas V12.4.131). This is the FIRST GPU execution
recorded in this lane. Older GPU_NOT_RUN.md statements remain historically
true; this file is a NEW stage, not a rewrite.

## Pre-launch gates (owner order, all PASS)
1. Oracle/comparator: native .t27, M2 suite 13/13 PASS.
2. ABI/packing/byte order/args/grid/bounds: M1 HOST_ABI.md + M3 harness 9/9.
3. Comparator negative tests: M2 corruption test + M3 G7 flip detection.
4. Hash gate BEFORE launch: sha256sum on the GPU machine over the uploaded
   accepted cubin = 35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc
   == artifacts/gf16-dot4-ptx/ARTIFACT_HASHES.txt (baseline chain). See
   reports/gpu_smoke_run1.log section 1 (run 1 = failed gate probe on device
   ordinal; hash gate already PASSed in run 1).
5. Small golden smoke: 8 adopted groups (below).

## Run 1 (reports/gpu_smoke_run1.log): ordinal 1 rejected
cuDeviceGet(ordinal 1) -> CUDA error 101 (invalid device ordinal): WSL2
exposes exactly ONE device. No launch happened; state preserved; runner
cleaned up. device_probe (reports/device_probe.log): device_count=1,
"RTX 3070 Laptop GPU", free 15275/16384 MiB. The free-memory profile matches
the IDLE physical GPU 1 (nvidia-smi Windows-side: GPU 0 used 14540 MiB,
GPU 1 used 14 MiB). LIMITATION: inside WSL the virtual device cannot be
pinned to a physical index; identity rests on the memory profile.

## Run 2 (reports/gpu_smoke_run2.log): success
Runner scripts/gf16_dot4_host/cuda_smoke.c (driver API only; every CUDA call
checked; any failure prints call name + error and aborts before any claim):
cuInit(0) -> cuDeviceGet(0) -> cuCtxCreate_v2 -> cuModuleLoadData(cubin bytes)
-> cuModuleGetFunction("gf16_dot4") -> cuMemAlloc_v2(a,b,c) ->
cuMemcpyHtoD_v2(a,b) -> cuLaunchKernel(grid 1x1x1, block 256x1x1, smem 0,
stream 0, args = {&da,&db,&dc,&n=8}) -> cuCtxSynchronize -> cuMemcpyDtoH_v2
(full 32 bytes) -> cuMemFree -> cuModuleUnload -> cuCtxDestroy. Exit 0,
no CUDA errors, output fully read (32/32 bytes; completeness check in the
smoke script section 6).

GPU output words (little-endian f32 bits):
  C0 4127A000  C1 00000000  C2 C0400000  C3 409B4000
  C4 7F800000  C5 FF800000  C6 50275620  C7 BFB10000

Comparison: performed by the NATIVE .t27 verdict spec
scripts/gf16_dot4_host/gf16_gpu_smoke_verdict.t27 against the M2 adopted
expected table ADOPTED_EXP: groups_checked=8, mismatch_count=0, test PASS
(reports/test_report_gf16_gpu_smoke_verdict.txt). NaN contract: the smoke
set contains no NaN-producing products; all 8 expected values are finite,
so the payload-vs-canonical NaN divergence (documented in M2) cannot affect
this stage.

## Result
STATUS: PASS. GPU_EXECUTION: EXECUTED (run 2, device WSL ordinal 0).
Checked groups: 8. Mismatches: 0. CUDA errors: 0. Synchronized: yes
(cuCtxSynchronize before readback). This satisfies the owner PASS criterion
for the golden smoke slice; edge/randomized extension is stage 2.

## Not yet claimed
- Edge-case and seeded-randomized batches (stage 2) - NEXT.
- Performance/power: NOT measured, NOT authorized.

--- attached: t27c test-report of the verdict spec ---
--- test report: scripts/gf16_dot4_host/gf16_gpu_smoke_verdict.t27 ---

  tests       1
  pass        1
  FAIL        0
  rate    100.0%

  runtime asserts per test (#6509; 0 with a folded check is CT-VERIFIED, 0 with neither is vacuous, T730):
       ?  gpu_smoke_eight_groups_bit_exact   (passed, not counted)
  vacuous passes  unknown  (the counting build did not compile: counting build: assert_eq not in source .t27 spec)
