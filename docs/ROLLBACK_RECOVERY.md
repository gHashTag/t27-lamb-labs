# Rollback & Recovery Procedure

Scope: every live artifact of this lab (repo state, evidence, FPGA bitstreams on the AX7203).
Law: every command below was executed once against the real repo/board and logged in
`evidence/rollback_recovery/rollback_recovery_2026-11-23.log` (linked issue: #1 [R1]).

## 1. Artifact inventory and sources of truth

| Artifact | Source of truth (sha256) | Restore source |
|---|---|---|
| Any tracked file at any milestone | `ARTIFACT_MANIFEST.txt` (root), per-dir `evidence/*/ARTIFACT_HASHES.txt` | `git show <tag>:<path>` |
| `bitstream/ternary_mac_demo_top_200t.bit` | manifest row 11 = `a82c260d…c0b` | tag `v0.1.2-codesign-measured` (blob `813c457a`) |
| Clock probes (`evidence/clock_probe/*.bit`) | `evidence/clock_probe/ARTIFACT_HASHES.txt` | working tree / any tag ≥ `v0.1.15` |
| RTL sources (`rtl/`, `specs/`, `evidence/codesign/`) | per-dir `ARTIFACT_HASHES.txt` + git history | `git show <tag>:<path>` |
| Board: ALINX AX7203 (XC7A200T-FBG484), JTAG idcode `0x3636093`, HS2 serial `210512180081` | — | `openFPGALoader` (below) |

Tag → milestone mapping: `v0.1.0` MVP … `v0.1.18` attention-verified (19 tags, all pushed).
Current branch tip carries the newest docs/evidence; tags carry the milestone-frozen state.

## 2. Repo rollback (any file, any milestone)

```bash
# exact single-file restore without moving HEAD (works in partial clones):
git show v0.1.2-codesign-measured:bitstream/ternary_mac_demo_top_200t.bit > RESTORED_FILE

# whole-tree rollback (detached inspection, non-destructive):
git checkout v0.1.2-codesign-measured          # Detached HEAD; git switch - to return

# verify restored bytes against the manifest line:
shasum -a 256 RESTORED_FILE
grep 'bitstream/ternary_mac_demo_top_200t.bit' ARTIFACT_MANIFEST.txt
```

PASS = `shasum` output equals the manifest line byte-for-byte. That check IS the worked
example's gate (executed 2026-11-23, log under `evidence/rollback_recovery/`).

## 3. FPGA rollback (SRAM restore — the lab norm)

```bash
# 3.1 board identity (pre-check):
openFPGALoader -c digilent_hs2 --detect

# 3.2 SRAM load of the restored bitstream (NO flash write; volatile by design):
openFPGALoader -c digilent_hs2 RESTORED_FILE

# 3.3 post-load health:
openFPGALoader -c digilent_hs2 --read-xadc
```

PASS = `isc_done 1` + `done 1` on 3.2, idcode `0x3636093` on 3.1, XADC nominal on 3.3.
DONE=1 proves CONFIGURATION only — never datapath behaviour (see #5 smoke evidence).

**Flash restore is deliberately out of scope of the executed procedure**: `openFPGALoader
-f` overwrites the board's persistent boot image — an owner-level decision, not a routine
rollback step. The command exists (`openFPGALoader -c digilent_hs2 -f FILE`) but was NOT
executed in the evidence run.

## 4. Evidence integrity after any restore

```bash
# full manifest verification (header lines are prose; hash only ^[0-9a-f]{64} rows):
awk '/^[0-9a-f]{64}  / {print}' ARTIFACT_MANIFEST.txt | while read -r h f; do
  [ -f "$f" ] && [ "$(shasum -a 256 "$f" | cut -d" " -f1)" = "$h" ] || echo "REAL MISMATCH: $f"
done ; echo REAL_ROWS_CHECK_DONE
```

Any `REAL MISMATCH:` line = evidence tampering or partial restore; stop and re-derive from git.
Executed 2026-11-23: 0 real mismatches over all manifest rows (log §4 CORRECTED).

## 5. Recovery decision tree

1. **Bad bitstream on board** → §3 with the tag-restored file.
2. **Suspect evidence file** → §4, then `git show <tag>:<path>` for the tagged version.
3. **Broken working tree** → `git status`, `git stash`, `git switch master`.
4. **Lost branch tip (crash before push)** → local refs: `git reflog`, restore by sha.
5. **Lost remote** → origin `https://github.com/gHashTag/t27-lamb-labs.git`; re-push
   `master` + `--tags` (owner approval required for force operations).
