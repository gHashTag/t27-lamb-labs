#!/usr/bin/env bash
# One-command regression gate for the t27-lamb-labs laboratory.
#
# Runs, in order, every automated acceptance gate the lab owns:
#   G1 portfolio acceptance      scripts/verify_portfolio.py
#      (dashboard rules incl. artifact-manifest vs tree, forbidden-claims scan)
#   G2 spec-first compiler       t27c_lite.py   (.t27 spec -> Verilog, bit-exact 117/117,
#                                                yosys clean, byte-identical regeneration)
#   G3 conformance pack          conformance/run_conformance.py
#      (Tier A RTL 29/29, Tier B golden 10/10, Tier B2 dot27 RTL 50/50)
#   G4 manifest hash sweep       every ARTIFACT_MANIFEST.txt row re-hashed from disk
#   G5 tree drift                `git status --porcelain` must be EMPTY after the run
#      (proves the whole pipeline is deterministic: every regenerated artifact is
#       byte-identical to what is committed)
#
# Exit is non-zero if any gate fails. Usage:
#   bash scripts/regress_all.sh            # log -> evidence/regression/regress_<date>.log
#   OUT=path/to/log bash scripts/regress_all.sh
set -u
cd "$(dirname "$0")/.." || exit 1
OUT="${OUT:-evidence/regression/regress_$(date +%Y-%m-%d_%H%M%S).log}"
mkdir -p "$(dirname "$OUT")"

FAIL=0
say() { printf '%s\n' "$*" | tee -a "$OUT"; }
gate() { # gate <id> <desc> <cmd...>
  local id="$1" desc="$2"; shift 2
  say "=== $id: $desc"
  if "$@" >>"$OUT" 2>&1; then
    say "=== $id: PASS"
  else
    say "=== $id: FAIL (exit $?)"
    FAIL=1
  fi
}

: > "$OUT"
say "T27-LAMB-LABS REGRESSION GATE  $(date -u '+%Y-%m-%dT%H:%M:%SZ')  HEAD=$(git rev-parse --short HEAD)"gate G1 "portfolio acceptance"              python3 scripts/verify_portfolio.py
gate G2 "t27c_lite spec->Verilog compiler"  python3 t27c_lite.py
gate G3 "conformance pack (A/B/B2)"         python3 conformance/run_conformance.py

# G4: header-safe manifest sweep (skips the # comment header lines).
say "=== G4: artifact manifest hash sweep"
BAD=0; ROWS=0
while IFS= read -r line; do
  h="${line%%  *}"; f="${line#*  }"
  [ ${#h} -eq 64 ] || continue
  ROWS=$((ROWS+1))
  if [ ! -f "$f" ]; then say "MISSING: $f"; BAD=$((BAD+1));
  elif [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" != "$h" ]; then say "REAL MISMATCH: $f"; BAD=$((BAD+1)); fi
done < <(awk '/^[0-9a-f]{64}  / {print}' ARTIFACT_MANIFEST.txt)
say "=== G4: $ROWS rows checked, $BAD mismatches"
[ "$BAD" -eq 0 ] || FAIL=1

# G5: deterministic pipeline -> no uncommitted drift after a full re-run.
# (the run-once log directory is excluded — pending logs are evidence, not drift)
say "=== G5: tree drift after regeneration"
DRIFT="$(git status --porcelain -- . ":(exclude)$(dirname "$OUT")" || true)"
if [ -z "$DRIFT" ]; then
  say "=== G5: PASS (tree clean, all regenerated artifacts byte-identical)"
else
  say "$DRIFT"
  say "=== G5: FAIL (regenerated artifacts differ from the committed ones)"
  FAIL=1
fi

say "==========================================="
if [ "$FAIL" -eq 0 ]; then say "REGRESSION: ALL GATES PASS"; else say "REGRESSION: FAIL"; fi
exit "$FAIL"
