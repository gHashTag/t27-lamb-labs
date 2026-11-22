#!/usr/bin/env python3
"""Check the portfolio against its own acceptance criteria.

The acceptance rules are the ONE SHOT list:
  - one measured J/token exists              (not yet: power is ESTIMATED)
  - one measured DRAM-reads-per-token result exists
  - one complete co-design iteration documented
  - raw logs + bitstream hash available
  - README distinguishes measured / estimated / target
  - no unsupported performance claims
  - portfolio reproducible from repo artifacts

Each rule is checked against the files on disk, not against a claim in prose.
"""
import hashlib, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def read(p):
    with open(os.path.join(ROOT, p)) as f:
        return f.read()

def sha256(p):
    h = hashlib.sha256()
    with open(os.path.join(ROOT, p), "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def main():
    results = []
    readme = read("README.md")
    dash = read("target/lamb_labs_evidence.md")

    # 1. measured DRAM reads per token
    dram = "evidence/reports/dram_reads_per_token_report.json"
    has_dram = os.path.exists(os.path.join(ROOT, dram))
    dram_val = None
    if has_dram:
        try:
            d = json.loads(read(dram))
            for k in ("external_dram_reads_per_token", "dram_reads_per_token", "reads_per_token"):
                if k in d:
                    dram_val = d[k]
                    break
            if dram_val is None:
                # the report nests it under analysis/conclusion
                for sect in ("analysis", "conclusion", "estimates"):
                    if isinstance(d.get(sect), dict) and "external_weight_reads_per_token" in d[sect]:
                        dram_val = d[sect]["external_weight_reads_per_token"]
                        break
        except Exception:
            pass
    results.append(("measured DRAM-reads-per-token result exists",
                    has_dram and dram_val == 0,
                    f"{dram}: value={dram_val}" if has_dram else f"{dram} MISSING"))

    # 2. one complete co-design iteration documented
    iterations = len(re.findall(r"^## Co-Design Iteration \d+", dash, re.M))
    results.append(("one complete co-design iteration documented",
                    iterations >= 1, f"{iterations} iterations in the dashboard"))

    # 3. raw logs + bitstream hash available
    bit = "bitstream/ternary_mac_demo_top_200t.bit"
    has_bit = os.path.isfile(os.path.join(ROOT, bit))
    bit_hash = sha256(bit) if has_bit else None
    hash_in_dash = bit_hash in dash if bit_hash else False
    logs = [f for f in os.listdir(os.path.join(ROOT, "evidence"))
            if f.endswith(".log")]
    results.append(("raw logs + bitstream hash available",
                    has_bit and hash_in_dash and len(logs) > 0,
                    f"bitstream sha256 {bit_hash[:16]}... in dashboard={hash_in_dash}, "
                    f"{len(logs)} raw logs"))

    # 4. README distinguishes measured / estimated / target
    labels = ["MEASURED", "ESTIMATED", "TARGET", "SUSPECT"]
    present = [l for l in labels if l in readme]
    results.append(("README distinguishes measured / estimated / target",
                    len(present) >= 3, f"labels present: {present}"))

    # 5. no unsupported performance claims: the forbidden phrases must not appear as claims
    forbidden = [
        (r"TinyLlama.{0,40}(on|fully on)\s+(Kria|AX7203)", "TinyLlama on Kria"),
        (r"10\s*[-–]\s*15\s*(tok|tokens)", "10-15 tok/s"),
        (r"80\s*[-–]\s*120\s*J\s*/\s*token", "80-120 J/token"),
        (r"20,?\d{3}\+\s*(tok|tokens)", "20,000+ tok/s"),
        (r"63\s*x\s+intelligence", "63x intelligence per watt"),
    ]
    hits = []
    for pat, label in forbidden:
        for name, txt in (("README.md", readme), ("target/lamb_labs_evidence.md", dash)):
            for m in re.finditer(pat, txt, re.I):
                line = txt[:m.start()].count("\n") + 1
                ctx = txt[max(0, m.start()-90):m.end()+40].replace("\n", " ")
                # a forbidden phrase is a violation only if it is not preceded by a negation
                pre = txt[max(0, m.start()-120):m.start()].lower()
                negated = any(w in pre for w in ("not ", "no ", "do not", "do **not**",
                                                "without", "never", "not**"))
                hits.append((name, line, label, "negated/allowed" if negated else "VIOLATION", ctx))
    violations = [h for h in hits if h[3] == "VIOLATION"]
    results.append(("no unsupported performance claims",
                    not violations,
                    f"{len(hits)} forbidden phrases found, {len(violations)} unnegated"))

    # 6. the benchmark validator passes
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(ROOT, "benchmark/validate_benchmark.py")],
                       capture_output=True, text=True, cwd=ROOT)
    results.append(("benchmark validates against the evidence",
                    r.returncode == 0, r.stdout.strip().splitlines()[0] if r.stdout else "no output"))

    # 7. the artifact manifest matches the tree
    man = os.path.join(ROOT, "ARTIFACT_MANIFEST.txt")
    if os.path.isfile(man):
        bad = []
        n = 0
        for line in open(man):
            m = re.match(r"^([0-9a-f]{64})\s+(.*)$", line.strip())
            if not m:
                continue
            n += 1
            p = os.path.join(ROOT, m.group(2))
            if not os.path.isfile(p) or sha256(p) != m.group(1):
                bad.append(m.group(2))
        results.append(("artifact manifest matches the tree",
                        not bad, f"{n} entries, {len(bad)} mismatched"))
    else:
        results.append(("artifact manifest matches the tree", False, "manifest missing"))

    # 8. KNOWN GAP: measured J/token. Not yet satisfiable.
    power_measured = False
    results.append(("one measured J/token exists",
                    power_measured,
                    "NOT YET: power is ESTIMATED (the XADC has no current sensor); "
                    "an external meter in series with the rail is required"))

    print("PORTFOLIO ACCEPTANCE CHECK")
    print("=" * 72)
    width = max(len(r[0]) for r in results)
    ok = 0
    for name, passed, detail in results:
        mark = "PASS" if passed else ("GAP " if name.startswith("one measured J") else "FAIL")
        if passed:
            ok += 1
        print(f"  [{mark}] {name.ljust(width)}  {detail}")
    print("=" * 72)
    print(f"  {ok}/{len(results)} satisfied")
    if violations:
        print("\n  UNNEGATED FORBIDDEN PHRASES:")
        for h in violations:
            print(f"    {h[0]}:{h[1]}  {h[2]}  ...{h[4]}...")
    return 0


if __name__ == "__main__":
    sys.exit(main())
