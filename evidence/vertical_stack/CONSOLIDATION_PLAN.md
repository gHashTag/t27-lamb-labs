# Consolidation Plan — LAMB_LABS_VERTICAL_CONSOLIDATION_V1 / M1

STATUS: READY, awaiting owner go. No merge is performed by this document.

## 1. Branch inventory (measured 2026-11-24 ~23:50 +07)

| Branch | Tip | Ahead of master | Contents |
|---|---|---|---|
| `master` = `origin/master` | `a7ef751` | — | hardware portfolio through CODESIGN_ITERATION_10 + `.gitignore` |
| `dsh-5344b40f-4225` (GPU/software vertical) | `4a17447` | **15 commits** | M0–M5, M7: specs, conformance, PTX, cubin, HOST_ABI, GPU acceptance, claims audit (this lane) |
| `dsh-e6e4cd9f-d7f1` (hardware r10–r12) | `c4d20fc` | **49 commits** | clock hardening, wrap-aware live R4/T4 399.08 MHz (n=8), Johnson /256 SIM 8/8, comb-pattern gates, r12 ALL GATES PASS, capability map 275 rows |

Merge bases (verified with `git merge-base`):

- `git merge-base master dsh-5344b40f-4225` = `a7ef751` → GPU lane is a clean descendant of master.
- `git merge-base master dsh-e6e4cd9f-d7f1` = `a7ef751` → hardware lane is a clean descendant of master.

## 2. Conflict assessment

Changed-path overlap between the two lanes (verified with `comm -12` over
`git diff --name-only` of each lane vs its base):

```
ARTIFACT_HASHES.txt
ARTIFACT_MANIFEST.txt
scripts/manifest.py
```

Only the auto-generated repo-root manifests and the manifest generator overlap.
Everything else is disjoint: GPU lane writes `evidence/vertical_stack/**`,
`artifacts/**`, `specs/igla/coder/**`; hardware lane writes `evidence/clock_probe/**`,
`releases/**`, `rtl/**`, `docs/**`, `target/lamb_labs_evidence.md`.

## 3. Merge order and rationale

1. **GPU lane first** (`dsh-5344b40f-4225` → master).
   Rationale: it is the lane under active acceptance; it carries the claims audit
   (`reports/CLAIMS_AUDIT_OWNER_TABLE.md`) that corrects owner-table numbers, and the
   owner has hardware lane on HOLD. 15 commits, one merge.
2. **Hardware lane second** (`dsh-e6e4cd9f-d7f1` → master), evidence-only: it adds
   clock-probe evidence and gate logs behind a HOLD notice; no silicon claims are
   restored by the merge itself.
3. **Manifest regeneration after each merge**: run `scripts/manifest.py` (or the
   documented regeneration command) so `ARTIFACT_HASHES.txt` / `ARTIFACT_MANIFEST.txt`
   are regenerated from the merged tree instead of hand-resolved. This avoids a
   conflict resolution that could silently drop a hash.
4. **Not pushed.** `origin/master` updates only after explicit owner approval
   (approval gate; GODMODE §1).

## 4. Acceptance criteria for M1

- [ ] `git merge master` of each lane leaves zero conflicts outside regenerated manifests.
- [ ] Post-merge `scripts/manifest.py` run exits 0 and hash counts match
      `git ls-files | wc -l` expectations recorded at merge time.
- [ ] `READINESS_MATRIX.md` (M2) references both lanes' evidence from the merged tree.
- [ ] No silicon-claim wording is restored; HOLD notices preserved.
- [ ] Merge commits link this plan and the claims audit by path + SHA-256.

## 5. After M1 (for context, not part of this plan's gate)

M2 unified readiness matrix → M3 owner decisions (acceptance record, perf/power
methodology, hardware funding vs silicon-claims removal, canonical `t27c`) →
M4 next scoped work → M5 vertical stack review.
