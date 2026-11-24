# Owner Decisions — Lamb Labs Vertical Stack (M3 collection)

STATUS: OPEN. Collected 2026-11-25 so the owner can answer all of them in one reply.
Each decision names its current in-chat state and what it unblocks. Nothing here is
self-granted: a decision takes effect only when the owner answers and a record is
committed.

## D1 — GPU correctness acceptance

- Question: accept M4 GPU correctness in its declared scope (smoke 8/8, batch 250
  finite bit-exact, 38 NaN per policy, 0 CUDA errors)?
- In-chat state: declared `ACCEPTED_IN_DECLARED_SCOPE` in U17 (`GPU_ACCEPTANCE_AND_TOOLCHAIN_PIN`),
  but no acceptance record exists in evidence; current consolidation order lists it PENDING.
- Unblocks: closing readiness row L6; closing HANDOFF "Open owner decisions" #1.
- On "PIN": I commit `gpu/GPU_ACCEPTANCE_RECORD.md` citing run logs + SHA-256, status
  ACCEPTED_IN_DECLARED_SCOPE with the scope text verbatim.

## D2 — Performance/power methodology (M6)

- Question: authorize a perf/power methodology task (separate, GPU runs at owner's
  discretion), or keep M6 NOT_RUN?
- In-chat state: NOT_RUN, separate task (U17). No methodology has been proposed yet.
- Unblocks: readiness row L7; HANDOFF #3 (additional kernels is a separate decision).

## D3 — Merge go/no-go (consolidation M1)

- Question: execute `CONSOLIDATION_PLAN.md` as written — GPU lane (`dsh-5344b40f-4225`,
  15+1 commits to `fce605a`) into master first, then hardware lane
  (`dsh-e6e4cd9f-d7f1`, 49 commits) evidence-only; manifests regenerated after each;
  **no push to origin** without a separate approval?
- In-chat state: no go issued yet.
- Unblocks: M2 matrix loses branch labels; master sees readiness artifacts and r12 gates.

## D4 — Canonical toolchain record

- Question: pin w3070 `t27c 5785e3ca…` + zig 0.16.0 as canonical (Mac stock build stays
  known-blocked for conformance)?
- In-chat state: declared canonical in U17; no evidence record yet.
- Unblocks: readiness link X5; reproducibility section of M5 review.
- On "PIN": I commit a `CANONICAL_TOOLCHAIN.md` record with the build hash and the
  Mac-blocked note.

## D5 — Hardware lane fate

- Question: keep HOLD with silicon claims withdrawn (current state), or fund the repair
  chain (spec→RTL for the shipped artefact, real testbench with waveforms, rebuilt
  bitstream, openXC7 install approval for the r4t4c board rebuild, Vivado power/timing)?
- In-chat state: HOLD / NOT_RESTORED (U17). The consolidation merge does not change this:
  it merges evidence, not claims.
- Unblocks: readiness rows H5 board rebuild, H8 spec→RTL, H9; HANDOFF #2.

## D6 — Publication corrections

- Question: apply the three corrections from `reports/CLAIMS_AUDIT_OWNER_TABLE.md` §5
  (rewrite owner-table rows 1–4 to measured numbers) wherever the table is reused?
- In-chat state: corrections recorded in evidence only; the owner's original message is
  not an artifact I can edit.
- Unblocks: any future README/issue text that cites the FPGA table.
