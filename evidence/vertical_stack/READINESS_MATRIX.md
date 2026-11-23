# LAMB_LABS_VERTICAL_STACK_READINESS_MATRIX_V1

- Goal: `LAMB_LABS_VERTICAL_STACK_GOAL_V1` (goal-aa062e98-6c88-4949-8fe7-88d16618ba7e).
- Lane branch `dsh-5344b40f-4225`, baseline commit `71745d5fa4cd6a17bc749a1108d6839fb80ed859`.
- Generated: 2026-11-23 (Asia/Bangkok), CPU-only session. No CUDA init, no kernel launch, no
  host-device transfers, no `ptx-run`, no training anywhere in this matrix's evidence.
- Labels: `MEASURED` (a command ran and its output was captured), `ESTIMATED` (derived, not
  run), `TARGET` (goal, not evidence), `SUSPECT` (conflicting/unconfirmed), `GAP` (no evidence).
- Rule: historical reports are cited as MEASURED-at-timestamp, never re-presented as fresh runs.

## A. Vertical stack (GPU kernel path)

| # | layer | contract | evidence | status | limitation | next step |
|---|-------|----------|----------|--------|------------|-----------|
| A1 | numeric SSOT | `gf16_decode_to_f32` in `specs/numeric/gf16.t27:172-198` (sha256 `b6324424…`); value formula `(-1)^S*2^(E-31)*(1+M/512)`, E in 0..62, no subnormals, e==63 -> ±Inf (m==0) / NaN, e==0&&m==0 -> signed zero | spec tests pass via `artifacts/gf16-dot4-ptx/test_report_ptx_emit.txt` (MEASURED 2026-11-23, 14/14, exit 0); SSOT-vs-PTX decode branch audit done by reading both sources this session | VERIFIED (spec-level) | NaN payload: SSOT returns canonical `std.math.nan(f32)`, hardware keeps payload — comparisons must be NaN-aware, not bitwise | keep SSOT frozen; oracle (A3) must encode the NaN rule explicitly |
| A2 | executable specs | `specs/igla/coder/gf16_dot4_ptx.t27` (sha256 `dd74e625…`) emits the kernel text; `specs/igla/coder/ptx_emit.t27` (sha256 `4e181244…`) emits the decode sequence; deterministic, ASCII-only | `artifacts/gf16-dot4-ptx/test_report_gf16_dot4_ptx.txt` (MEASURED 2026-11-23, 10/10, exit 0); `t27c test` declaration logs kept as secondary evidence | VERIFIED | `t27c test` alone exits 0 even with unresolved `use`; only `t27c test-report` is authoritative | none pending; reuse test-report for any future spec change |
| A3 | CPU reference / conformance | `dot4_golden` (`specs/igla/coder/gf16_dot4_ptx.t27:144-152`): f32 accumulator from 0.0, lane order; vectors from upstream `conformance/vectors/gf16_conformance_v0.json` (sha256 `5081a1ec…`, verified byte-identical at upstream commit `44c8c62a…` this session) | 10 spec tests cover the 10 copied vectors incl. phi anchor; golden chain bins `gf16_dot4_{a,b,c,expected}.bin` exist upstream (sha256s `6f2bddc4…`, `ad4246d5…`, `35a90eef…` x2) | PARTIAL | no standalone machine-readable oracle/comparator artifact inside this lane yet; upstream `gf16_ref.py gf16_dot4` re-rounds through GF16 — a DIFFERENT semantic from the kernel's f32 accumulator, must not be used as bit-exact oracle | M2: exact single-rounding f32-FMA oracle + vector set (golden/boundary/seeded) in-lane |
| A4 | PTX emission | emitted text `artifacts/gf16-dot4-ptx/gf16_dot4.ptx` sha256 `b9a79404…`, 4952 B, `.target sm_86`, PTX 7.1 | byte-identical to upstream golden `gf16_dot4_emitted.ptx`; host re-emission match `HOST_REEMIT_MATCHES_LOCAL=YES` (MEASURED 2026-11-23, `command_transcript.txt`) | VERIFIED | emitter route was `t27c gen-text --fn emit_ptx` (no local `--features cuda` build) — documented deviation, output still byte-identical | none for emission |
| A5 | offline assembly | cubin `artifacts/gf16-dot4-ptx/gf16_dot4.cubin` sha256 `35e07b5f…`, 4648 B, from `ptxas -arch=sm_86` (CUDA 12.4.131, win11-3070 remote; MEASURED 2026-11-23T07:15Z) | `ptxas_verbose.log`: 22 regs, 0 spill stores, 0 spill loads, 380 B cmem[0]; `cuobjdump_sass.log`: sm_86 SASS, 279 lines | VERIFIED | remote-only; no local `ptxas`; remote writes were confined to the lane dir and out/ files untouched | re-run only if PTX changes |
| A6 | host integration | ABI from hashed PTX: `.entry gf16_dot4(.u64 p_a, .u64 p_b, .u64 p_c, .u32 p_n)`, `.maxntid 256,1,1`; 8-byte group stride in/out pointers, 4-byte f32 out stride; guard `gidx >= p_n` -> return | kernel text `gf16_dot4.ptx` (A4) + SASS `cuobjdump_sass.log` (A5); upstream `ptx_run` (commit `44c8c62a…:bootstrap/src/host/driver.rs:303`) audited this session: 6 args `(a,w,c,m,n,k)`, kernel ids 0/1/2 only, internal host data — cannot host this kernel (#14143/#10360) | PARTIAL | formal written ABI contract (M1) and CPU-only mock harness (M3) not yet in-lane; every future launcher must verify cubin hash before load | M1 ABI contract artifact; M3 CPU-only harness with explicit opt-in GPU path |
| A7 | GPU correctness | TARGET: bit-exact `c[i]` vs oracle on GPU | none in-lane; `artifacts/gf16-dot4-ptx/GPU_NOT_RUN.md` states execution forbidden this stage | NOT_AUTHORIZED (M4) | nothing measured on GPU; PTX/cubin correctness is offline evidence only | request separate owner gate AFTER M3 lands |
| A8 | performance / power | TARGET: J/token, tokens/s, power on RTX 3070 | none for this kernel; portfolio-level `~0.7 W`, `~0.12 J/token` are ESTIMATED only; `verify_portfolio.py` = 7/8 with J/token the open GAP | NOT_AUTHORIZED (M6) | no methodology approved; do not pursue 8/8 claim | separate methodology approval required |

## B. Hardware evidence chain (spec -> RTL -> simulation -> FPGA; separate branch, shared contracts only)

| # | layer | contract | evidence | status | limitation | next step |
|---|-------|----------|----------|--------|------------|-----------|
| B1 | RTL spec (GF16 branch) | `specs/fpga/gf16_accel.t27` + `specs/fpga/gf16_accel.v`; testbench `specs/fpga/testbench/gf16_accel_tb.{t27,v}` | files present in tree (this session inventory); M5 read-only audit delegated to docs-scout, report pending | PRESENT / AUDIT PENDING | not verified against A1 SSOT in this lane; must not be conflated with the corrected-attention branch evidence | fold docs-scout report into `evidence/vertical_stack/` when it lands |
| B2 | simulation | GF16 testbench run logs | none located in-lane yet | GAP | no sim log cited; unnamed sim results are not evidence | M5 inventory; only cite files that exist with hashes |
| B3 | FPGA implementation | ternary attention branch: `bitstream/ternary_mac_demo_top_200t.bit`; `evidence/clock_probe/*.log` `isc_done 1` flash; attention fabric 2 LCs = 21.3%, KV-cache 9.3 LCs + 6.6 FFs/slot, DSP48E1 = 0 across 22 configs (README MEASURED rows) | README.md MEASURED table + `evidence/` subdirs (clock, clock_probe, utilization, critical_path, ax7203_build) | MEASURED (historical, ternary/attention branch) | all historical; GF16-dot4 branch has NO FPGA bitstream or timing evidence | keep branches separate in any readiness claim |
| B4 | silicon readiness | TARGET only | no tapeout artifacts in repo | GAP | tapeout-readiness claims are out of scope by goal contract | none in this lane |

## C. Cross-branch contracts

- Shared contract between A-branch and B-branch is the numeric SSOT (A1) plus machine-readable
  vectors (A3). Names matching (`gf16_dot4` in `specs/port/fpga/vivado/` and
  `specs/port/trinity/fpga/gf16-pipelined/`) are UNRELATED modules — do not cite them as
  evidence for this stack.
- Every evidence file in this directory is hashed in `ARTIFACT_HASHES.txt` next to it; the
  repo-root pair `ARTIFACT_HASHES.txt` / `ARTIFACT_MANIFEST.txt` is regenerated after any
  change (scripts/manifest.py) and cross-checks this bundle.
