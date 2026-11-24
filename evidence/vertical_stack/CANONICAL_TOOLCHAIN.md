# Canonical Toolchain Record — D4 PIN (ORDER LAMB_LABS_VERTICAL_CONSOLIDATION_MERGE_GO)

STATUS: PINNED by owner decision D4, 2026-11-25. Records the canonical conformance
runner for any rerun of the vertical stack. Adds no new builds.

## Canonical runner

| Component | Value |
|---|---|
| Host | win11-3070 (w3070) |
| Binary | `/home/t27ssh/t27os/bin/t27c` |
| Binary sha256 | `5785e3ca…` (full hash in `HANDOFF.md` provenance) |
| Zig | 0.16.0 on PATH |
| Verified | 2026-11-24, conformance 13/13 PASS (65,536 GF16 codes), regression suites exit 0 |

## Non-canonical, recorded traps

- Mac stock `t27c` (`~/.cargo/bin/t27c`, Nov 13) **blocks the conformance spec**
  (`spec.zig:539:30`, slice-coercion defect class). PIN does not fix this; it pins the
  w3070 runner as the rerun basis instead.
- The lane-local build (`/Users/playra/.local/bin/t27c`, sha `5da927df…`) was removed
  from its host.
- The w3070 scratch regression environment was swept by idle snapshot cleanup and was
  an unpacked tar, not a git clone: post-hoc hash verification of that environment is
  impossible; the committed tree is the source of truth (`LIMITATIONS.md`).

## Rerun procedure (from `HANDOFF.md`, unchanged)

Check the toolchain sha first; `t27c test-report` (not plain `t27c test`, which exits 0
on unresolved imports) over `scripts/gf16_dot4_host/{gf16_harness,gf16_gpu_smoke_verdict,
gf16_gpu_batch}.t27`; GPU host runs via `scripts/gf16_dot4_host/gpu_smoke.sh`.
