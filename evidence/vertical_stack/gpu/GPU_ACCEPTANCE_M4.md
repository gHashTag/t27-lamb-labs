# GPU CORRECTNESS ACCEPTANCE — GF16 dot4 (M4 stage 1 + stage 2)

Date: 2026-11-24 (Asia/Bangkok). Lane `dsh-5344b40f-4225`. Owner gate
`LAMB_LABS_GF16_GPU_CORRECTNESS`. Status: **GPU_RUN_PASS / ACCEPTANCE_PENDING**
(this document answers the owner's final arithmetic-contract question; the
owner decides acceptance).

HEAD at time of writing: `5cdf614` + the commit created by this round (see §6).

---

## 1. The real PTX: four chained FMAs, one rounding each

Source: `artifacts/gf16-dot4-ptx/gf16_dot4.ptx` (sha256
`b9a79404bb5c06095fa1b831ad45f3bf1eef2378b74702bad1615237534d5e51`,
4952 B, 184 lines). The kernel body contains EXACTLY FOUR `fma.rn.f32`
instructions and one final store (line numbers from the hashed file):

```ptx
%r5 = mad.lo.u32 ...            // gid = ctaid.x*ntid.x + tid.x   (l.30)
...bounds guard...              // gid >= p_n -> bra DONE        (l.31-32)
ld.global.v2.u32 {%r6,%r7}, [%rd5];   // A group (2 u32 lane words)  (l.36)
ld.global.v2.u32 {%r8,%r9}, [%rd6];   // B group (2 u32 lane words)  (l.37)
...decode lane a0 -> %f1, lane b0 -> %f2...           (l.38-72)
fma.rn.f32 %f0, %f1, %f2, %f0;  // FMA 1:  %f0 = RN(%f1*%f2 + %f0)  (l.73)
...decode lane a1 -> %f1, lane b1 -> %f2...           (l.74-107)
fma.rn.f32 %f0, %f1, %f2, %f0;  // FMA 2                            (l.108)
...decode lane a2 -> %f1, lane b2 -> %f2...           (l.109-142)
fma.rn.f32 %f0, %f1, %f2, %f0;  // FMA 3                            (l.143)
...decode lane a3 -> %f1, lane b3 -> %f2...           (l.144-177)
fma.rn.f32 %f0, %f1, %f2, %f0;  // FMA 4                            (l.178)
st.global.f32 [%rd7], %f0;      // store s4                        (l.181)
```

`fma.rn.f32 %f0, %f1, %f2, %f0` computes `%f1 * %f2 + %f0` with NO
intermediate rounding inside the instruction and ONE round-to-nearest-even
into f32 on the result; the accumulator `%f0` feeds itself. The register
`%f0` starts at +0 (PTX f32 registers initialize to +0.0; the kernel never
writes `%f0` before FMA 1).

## 2. The exact arithmetic contract of THIS kernel

```
s0 = +0                                      (f32 +0, 0x00000000)
s(i+1) = RN_f32( a_i * b_i + s_i )           i = 0,1,2,3, lane order 0,1,2,3
store s4
```

Four FMAs = FOUR rounding points, one per step. This is NOT
`RN_f32(a0*b0 + a1*b1 + a2*b2 + a3*b3)` (one rounding of the total exact
sum) — that is a different algorithm and is NOT what this kernel computes.

Signed-zero / special semantics (IEEE RN, per FMA step):
accumulator starts +0; `(+0) + (-0) = +0`; product `-0 * x = -0`;
dot4 of all-signed-zeros yields `0x00000000`; `-0 + -0 = -0` (0x80000000);
`Inf*0 = NaN`; `Inf + (-Inf) = NaN`; NaN payload of a NaN lane input flows
through FMA operands as produced by the decode below.

Lane decode inside the kernel (`emit_gf16_decode_f32`,
`specs/igla/coder/ptx_emit.t27`, sha256
`4e18124466c59291836dc1c48367f13a3b6ece913c5551f78cb182b93ce0eaf5`):
`g0 = v>>15 (sign)`, `g1 = (v>>9)&63 (exp)`, `g2 = v&511 (mant)`;
`e==63 && m!=0` -> NaN with payload `m<<14` KEPT (this is the one
documented divergence from the SSOT, which canonicalizes to `0x7FC00000`);
otherwise `exp_field = (e+96)<<23`, `frac = m<<14`, sign in bit 31;
`e==0 && m!=0` decodes as the normal `(512+m)*2^-40` (SSOT no-subnormals
rule, issue #6940 D1). SSOT reference: `specs/numeric/gf16.t27`
`gf16_decode_to_f32` l.169-198 (sha256
`b6324424a887cd93b697732f90445861850fa8d36b38098eab2d578b2c26d532`).

## 3. The .t27 oracle: rounds PER STEP (not one final rounding)

Source: `specs/igla/coder/gf16_dot4_conformance.t27` (sha256 recorded in
`evidence/vertical_stack/reports/test_report_gf16_dot4_conformance.txt`;
763 lines, 13/13 PASS). The oracle engine C:

```t27
/// Engine C dot4: decode exactly, multiply exactly, add with one RN-even
/// rounding PER STEP, in lane order, from a +0 accumulator. This is the
/// fma.rn.f32 semantics of the kernel, computed without any floating point.
pub fn exact_dot4_bits(a, b) u32 {          // l.334-343
    var acc = Exact { .kind=0, .neg=0, .sig=0, .exp=-149 };   // s0 = +0
    while (j < 4) {
        const prod = exact_mul(c_decode(a[j]), c_decode(b[j]));  // exact
        acc = exact_add(acc, prod);         // ONE RN-even rounding HERE
        j = j + 1;
    }
    return exact_bits(acc);                 // pack Exact -> f32 bits
}
```

The single rounding point per arithmetic step is `norm_rn`
(l.183-186: "Normalize a magnitude that may reach 2^48 into [2^23, 2^24)
with ONE RN-even rounding ... this is the only rounding point of the exact
engine per arithmetic step"), called from `exact_add` l.283
(`norm_rn(total, small.exp)`) and from `exact_mul` l.218. `exact_mul`'s
rounding is a NO-OP for GF16 inputs: a GF16 product carries at most
9+9+2 = 20..22 significant bits, below the f32 significand of 24 bits, so
`norm_rn(prod)` returns the product unchanged (empirically covered by
`exact_engine_unit_probes` and `fma_single_round_criterion`).

So the executed recurrence is literally
`s(i+1) = RN_exact_f32grid( s_i + a_i*b_i )`, i = 0..3 — the same shape as
the PTX. The engine computes the accumulator in exact binary arithmetic
(u64 significands) and applies exactly one RN-even rounding at each of the
four accumulation steps, then packs once to f32 bits.

**Clarification of the phrase "one RN-even rounding of the sum"** (it
appears in `reports/test_report_gf16_dot4_conformance.txt` l.8 and in
`exact_add`'s doc comment l.222-223): it means ONE rounding PER ADDITION
CALL (per dot4 step), NOT one rounding of the final total. Four
`exact_add` calls => four roundings. The code has always implemented
per-step rounding; the descriptive wording in the captured report header
was ambiguous, which this section resolves. No oracle code needed to
change; no GPU outputs needed re-comparison for this reason.

## 4. What `fma_single_round_criterion` actually asserts

`specs/igla/coder/gf16_dot4_conformance.t27` l.653-682:

1. Loop 1 (64 groups): seeded xorshift lanes (`state = RANDOM_SEED + 1 =
   20261124`), builds random (a,b) lane quadruples, and asserts
   `values_match(ssot_dot4_bits(a,b), exact_dot4_bits(a,b))`.
   - `ssot_dot4_bits` (l.346-354) = engine A: native f32 chain
     `acc = acc + decode(a)*decode(b)` (one f32 rounding per step, mul
     before add), returning `@bitCast(acc)`.
   - So loop 1 asserts: f32 mul-then-add chain (4 roundings) ==
     exact integer chain with per-step RN-even rounding (4 roundings),
     NaN-aware.
2. Loop 2 (8 groups): the adopted golden vectors `ADOPTED_A/B` with the
   EXACT equality `ssot_dot4_bits(a,b) == exact_dot4_bits(a,b)` (bitwise,
   no NaN escape).
3. Engine B (`ptx_dot4_bits`, l.358-368: PTX-decode transcription + the
   same f32 chain) is asserted equal to C in two other places:
   - `random_256_groups_engines_agree` (l.596-629):
     `values_match(ssot,C) and values_match(ptx,C)` over 256 seeded groups;
   - batch test `batch_engines_agree_on_non_nan_groups`
     (`scripts/gf16_dot4_host/gf16_gpu_batch.t27`): all non-NaN groups of
     the 288-group batch agree across A/B/C.

What this does and does not prove: the per-step-rounding equivalence
(A == C) is argued mathematically from product exactness (<=22 significant
bits < 24) and asserted empirically over 64+256+288 computed groups and 12
golden groups. It is NOT an exhaustive proof over every partial-sum state;
that residual is listed in §8.

## 5. GPU_C provenance: ACTUAL observed GPU output

`scripts/gf16_dot4_host/gf16_gpu_batch.t27` `pub const GPU_C : [288]u32`
(l.228) is a transcription of the ACTUAL GPU OUTPUT WORDS of remote run 2
(`GPU_RUN_OK cubin_bytes=4648 n=288 dev=0`, grid gx=2 — the grid-fixed
run). Committed raw log: `evidence/vertical_stack/reports/gpu_batch_run2.log`
(e.g. `C0:7FFFFFFF ... C32:5D24CA8A ... C287:00000000`). Spot check:
GPU_C[0]=0x7FFFFFFF == log line `C0:7FFFFFFF`; GPU_C[32]=0x5D24CA8A ==
log line `C32:5D24CA8A`.

The comparator direction is oracle -> observed:
- `expected_bits(g)` (l.73-82) = `exact_dot4_bits` of the generated lanes
  (engine C, derived from SSOT decode rules) — this is the EXPECTED side;
- `GPU_C[g]` = OBSERVED GPU output.
- `finite_mismatch_count()` counts finite-expected groups where
  `expected_bits(g) != GPU_C[g]` (l.239 area) -> 0;
- `nan_contract_violations()` counts expected-NaN groups where `GPU_C[g]`
  is not a NaN (l.253 area) -> 0.

No engine is compared against its own dump: engine C consumes the SSOT
decode RULES (re-derived as exact dyadics), not any GPU/PTX output. The
PTX-vs-SSOT decode agreement is separately counted (64515/65536 codes
bit-identical; the 1022 NaN-payload codes are the documented divergence,
class-level policy).

Smoke side: `GPU_C_HEX` in `scripts/gf16_dot4_host/gf16_gpu_smoke_verdict.t27`
= 8 words transcribed from `gpu_smoke_run2.log` (run 2, ordinal 0), and
`gpu_mismatch_count()` compares them against the INDEPENDENT `ADOPTED_EXP`
table -> 0. (That the observed 8 words equal the adopted 8 expected words
is the verified RESULT, not an assumption of the comparator.)

## 6. Provenance / HEAD / dirty-diff state (honest record)

- The ONE and ONLY PROVENANCE file is
  **`evidence/vertical_stack/PROVENANCE.md`** (there is NO
  `evidence/vertical_stack/gpu/PROVENANCE.md`; an earlier chat reply
  mis-listed the path — corrected here).
- HEAD at the start of this round: `5cdf614` ("vertical-stack: final
  regression evidence at HEAD (7 native .t27 suites, all exit 0)").
  Baseline remains `71745d5fa4cd6a17bc749a1108d6839fb80ed859`.
- Dirty diff carried into this round (previously UNCOMMITTED, now being
  committed together with this document):
  1. `scripts/gf16_dot4_host/cuda_smoke.c` — header comment fix only:
     `grid 1x1x1 (n=8 -> ceil(8/256)=1)` -> `grid_x = (n + 255) / 256`
     (the code has computed gx from n since M4 stage 2; only the stale
     comment was wrong);
  2. `evidence/vertical_stack/PROVENANCE.md` — appended
     "Authorized GPU correctness addendum (M4 e409323 -> d702b8f)" while
     preserving the original M1 CPU-only statement.
- New in this round, committed together:
  `evidence/vertical_stack/gpu/GPU_ACCEPTANCE_M4.md` (this file),
  `HANDOFF.md` FPGA-GF16 domain note (§7), regenerated
  `evidence/vertical_stack/ARTIFACT_HASHES.txt` and root
  `ARTIFACT_HASHES.txt` / `ARTIFACT_MANIFEST.txt`.
- Reproduction commands (all recorded in evidence):
  - `t27c test-report specs/igla/coder/gf16_dot4_conformance.t27` -> 13/13;
  - `t27c test-report scripts/gf16_dot4_host/gf16_harness.t27` -> 9/9;
  - `t27c test-report scripts/gf16_dot4_host/gf16_gpu_smoke_verdict.t27` -> 1/1;
  - `t27c test-report scripts/gf16_dot4_host/gf16_gpu_batch.t27` -> 6/6;
  - `t27c gen-text scripts/gf16_dot4_host/gf16_gpu_batch.t27 --fn
    batch_stats_dump --buf 256 -o batch_stats.txt` ->
    `nan_grps=38 / fmmatch=0 / nanviol=0`;
  - remote `./gpu_smoke.sh` (hash gate -> launch -> sync -> D2H ->
    comparator inputs), evidence `reports/gpu_smoke_gated.log`,
    `reports/gpu_batch_run2.log`, cubin sha256
    `35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc`
    verified by HASH_GATE before every launch; CUDA ordinal 0.

## 7. FPGA GF(16) vs binary-float GF16 — domain boundary (recorded, no new FPGA work)

`specs/fpga/gf16_accel.t27` (`module Gf16Accel`, l.9; `GF16_BITS=4`,
`GF16_ELEMENTS=16`, `GF16_FIELD_POLY=19`, `PHI_WIDTH=64`) and its
generated `specs/fpga/gf16_accel.v` (header "Generated from t27 spec:
Gf16Accel", same parameters) implement GF(2^4) FIELD arithmetic
(gf_mul/gf_add/gf_mac/gf_dot/gf_fft...). Grep of the .v for
`exponent|mantissa|bias|float|f16|inf|nan` returns NOTHING. This is a
DIFFERENT numeric domain from the binary-float GF16 lane format of
`specs/numeric/gf16.t27` used by the GPU dot4 kernel. The two share only
the letters "GF16". Cross-branch connection must be proven by shared
contracts/tests, not by name (goal rule). The hardware-branch inventory
already records the branch separation (`evidence/vertical_stack/
rtl_fpga_inventory.md`); `HANDOFF.md` now carries the explicit
name-collision warning.

## 8. Result split and genuinely open items

Finite bit-exact (contract: finite expected -> GPU word must equal oracle
bits exactly):
- Smoke: 8/8 groups bit-exact (`gpu_smoke_eight_groups_bit_exact` PASS).
- Batch: 250 finite-expected groups, mismatch count 0
  (`gpu_batch_finite_groups_bit_exact` PASS).
NaN policy (contract: expected NaN -> GPU word class-level NaN, payload
not compared):
- Batch: 38 NaN-expected groups, violations 0
  (`gpu_batch_nan_groups_are_nan` PASS).
- CUDA errors: 0 across both stages; every CUDA call checked; execution
  synchronized before D2H; output fully read (32 B / 1152 B).
- 7 native .t27 suites PASS at HEAD (conformance 13, harness 9, smoke 1,
  batch 6, sha256 5, ptx 10, emitter 14).

Genuinely open (NOT claimed closed):
1. NaN payload-level comparison (policy deliberately class-level; payload
   divergence documented). A payload-exact check would need a new
   contract decision, not a bugfix.
2. Exhaustive proof that per-step FMA rounding == exact-chain rounding
   for EVERY finite GF16 input pair and every partial-sum state; today:
   mathematical exactness argument + 620 computed groups + 12 golden
   groups empirical agreement. Residual risk is theoretical, not observed.
3. 288+8 groups is a verification SET, not a proof over all inputs; more
   groups are cheap on the CPU side, but each GPU extension is a new
   authorized run decision for the owner.
4. WSL virtual device cannot be pinned to a physical GPU index; "dev 0"
   identity is the container's view.
5. M6 performance/power: NOT_RUN / NOT_AUTHORIZED. `~0.7 W` and
   `~0.12 J/token` remain ESTIMATED. No token/s or J/token claims follow
   from dot4 correctness.
6. Hardware branch (spec -> RTL -> simulation -> FPGA) remains GAP
   (see `rtl_fpga_inventory.md`); the shipped bitstream chain is BROKEN
   for its artefact; corrected-attention and GF16-dot4 stay separate.
7. No training (TRAINING_APPROVED=false), no push/PR/merge/release, no
   tapeout-readiness claims anywhere in this evidence.

## 9. Acceptance ask

Owner acceptance is requested for the FINITE verified scope exactly:

> Smoke: 8/8 bit-exact. Batch: 250 finite results bit-exact. 38
> NaN-expected groups match the NaN policy. CUDA errors: 0.

This is a statement about the checked groups under the pre-declared
contract of §2/§3 — NOT about all possible inputs and NOT a performance
measurement.
