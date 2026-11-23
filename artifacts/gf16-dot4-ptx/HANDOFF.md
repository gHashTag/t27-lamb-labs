# HANDOFF — GF16 dot4 PTX lane (`gf16-dot4-ptx`)

State at handoff: **ASSEMBLED_AND_HASHED / NOT_EXECUTED**. Local scoped commit on branch
`dsh-5344b40f-4225` in worktree `.agents/worktrees/dsh-5344b40f-4225`.
No push, no PR, no merge, no release was performed.

## What is true now (all measured in this lane)

| Link in the chain | Result | Artifact |
|---|---|---|
| numeric/spec SSOT vendored | sha256 `b6324424…` | `spec/gf16.t27` |
| kernel spec (fixes #14150) | sha256 `dd74e625…` | `spec/gf16_dot4_ptx.t27` |
| emitter spec (fixes #14149) | sha256 `4e181244…` | `spec/ptx_emit.t27` |
| spec tests, import-resolving | 10/10 and 14/14, exit 0 | `test_report_*.txt` |
| PTX emission (`t27c gen-text`) | 4952 B, sha256 `b9a79404…` | `gf16_dot4.ptx` |
| assembly (`ptxas -arch=sm_86`, CUDA 12.4) | exit 0, 4648 B ELF, sha256 `35e07b5f…` | `gf16_dot4.cubin` |
| assembler accounting | 22 registers, 0 stack, 0 spills | `ptxas_verbose.log` |
| static SASS listing | 279 lines | `cuobjdump_sass.log` |
| independent host re-emit/re-assemble | byte-identical PTX **and** cubin | `command_transcript.txt` §B5 |
| hash indexes | 200 + 199 + 17 entries, 0 mismatches | root + bundle `ARTIFACT_HASHES.txt` |
| portfolio acceptance | 7/8 PASS, 1 pre-existing GAP (power) | `scripts/verify_portfolio.py` |

## Deviations from the original task wording (deliberate, documented)

1. `ptxas -arch=sm86` → **`-arch=sm_86`**: CUDA 12.4 rejects `sm86`
   (`fatal: Value 'sm86' is not defined for option 'gpu-name'`); `sm_86` is the same architecture.
2. `t27c --features cuda` → **no such flag exists** in either the local build
   (sha256 `5da927df…`) or the host build (sha256 `5785e3ca…`); PTX was emitted with
   `t27c gen-text <spec> --fn emit_ptx` instead, then assembled offline with `ptxas`.
3. `t27c test <file>` → **`t27c test-report <file>`** for the kernel spec: `test` does not resolve
   cross-module `use` and can print exit 0 despite Zig compile errors (both raw logs are kept).
4. Task paths `specs/igla-coder/gf16dot4ptx.t27` → real paths
   `specs/igla/coder/gf16_dot4_ptx.t27` and `specs/igla/coder/ptx_emit.t27`.

## Exact reproduction

```bash
# local (macOS, Zig 0.17.1)
t27c test-report specs/igla/coder/gf16_dot4_ptx.t27      # 10/10
t27c test-report specs/igla/coder/ptx_emit.t27           # 14/14
t27c gen-text specs/igla/coder/gf16_dot4_ptx.t27 --fn emit_ptx -o /tmp/gf16_dot4.ptx
sha256sum /tmp/gf16_dot4.ptx                              # b9a79404…

# remote (win11-3070 WSL2, CUDA 12.4) — lane scratch dir only
ptxas -arch=sm_86 /tmp/gf16_dot4.ptx -o /tmp/gf16_dot4.cubin
sha256sum /tmp/gf16_dot4.cubin                            # 35e07b5f…
```

## Remaining limitations (exact)

* **No GPU execution.** No kernel launch, no `ptx-run`, no `ptx-run-gf16`, no host↔device copy,
  no output tensor, no numerical parity check. Assembly proves the PTX is *accepted* by the
  assembler for `sm_86` — nothing about runtime correctness, performance, power or tapeout.
* **No training** was started or altered (`TRAINING_APPROVED=false`).
* `t27#14155` (Zig array-repeat literal lowering) is still open; these specs use the `fill_u16`
  helper workaround upstream already shipped in `44c8c62a73`.
* The local and host `t27c` binaries differ (different sha256); the host one is a *different build*,
  which is what makes the byte-identical re-emission an independent check rather than a repeat.
* Portfolio check 8/8 (measured J/token) remains a **pre-existing GAP** unrelated to this lane:
  power is ESTIMATED, an external rail meter is required.
* `.scratch/` (session scratch) is untracked by design and is not part of the commit.

## Suggested next step (Lamb Labs only, on request)

A separate, explicitly authorised GPU-execution lane: launch the assembled cubin on win11-3070,
transfer the GF16 group inputs/expected vector, and record mismatches — producing the first
*MEASURED* GPU-correctness evidence. Until that lane exists, every GF16 statement stays
"assembled and hashed, not executed".
