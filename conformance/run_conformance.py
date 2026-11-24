#!/usr/bin/env python3
"""run_conformance.py — TNF/GF16 numeric-core conformance pack (issue #2 [R4]).

One entrypoint. Tiers, honestly labelled:
  TIER A (RTL leg): committed rtl core `ternary_mac_top` (evidence/codesign/
    ternary_mac_synth.v == the byte-exact recovered synth source) simulated with
    iverilog; every measured acc_out compared bit-exact against an INDEPENDENT
    python golden derived from the RTL contract (sign-extend, 9-bit negate,
    32-bit wrap). Any mismatch -> non-zero exit.
  TIER B (spec leg): dot27 semantics transcribed from specs/ternary/
    stream_ternary_mac.t27 (trits {N=0b00,Z=0b01,P=0b10}; tmul/tp/dot27) +
    the spec's own 4 embedded tests + enumerated edge vectors. No RTL leg for
    dot27 exists in this lab yet (t27c compiler = issue #3 [R3]) — the tier is
    labelled SPEC-VERIFIED, not RTL-verified.
  TIER B2 (RTL leg): t27c_lite-emitted dot27_top.v vs the same independent
    spec golden (spec tests + edges + 40 randomized, seed 424242).
  TIER B3 (RTL leg, streaming): t27c_lite-emitted stream_ternary_mac_top.v
    (the spec's on_clock/var-acc/en contract) vs independent spec golden over
    16 randomized streams with en=0 hold cycles (seed 777).

Exit code 0 = all vectors pass. Evidence JSON + sha256 written to
evidence/conformance/ per ARTIFACT_HASHES convention.
"""
import hashlib
import json
import os
import random
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAC_RTL = os.path.join(REPO, "evidence", "codesign", "ternary_mac_synth.v")
TB = os.path.join(REPO, "conformance", "tb_ternary_mac.v")

U32 = 1 << 32
def wrap32(x):  # Verilog signed 32-bit two's-complement wrap
    return ((x + (1 << 31)) % U32) - (1 << 31)

def sext(v, w):  # two's-complement sign extension from width w to python int
    v &= (1 << w) - 1
    return v - (1 << w) if v >> (w - 1) else v

# ---------------- TIER A golden: ternary_mac_top cell ----------------
def golden_mac(a, w, acc_in):
    """Registered contract: acc_out <= acc_in + sext9(prod) when en&rst_n; 0 on rst; hold on !en."""
    a9 = sext(a, 8) & 0x1FF           # {a[7],a}: sign-extend a to 9 bits
    if w == 0b01:      prod9 = a9
    elif w == 0b10:    prod9 = (-a9) & 0x1FF        # 9-bit negate of sign-extended a
    else:              prod9 = 0                    # 2'b00 and 2'b11 decode to 0
    prod = sext(prod9, 9)
    return prod

def sim_mac(vectors):
    """Sequential golden register model mirroring the RTL always block."""
    out, acc_reg = [], 0
    for (a, w, acc_in, rst_n, en) in vectors:
        if not rst_n:
            acc_reg = 0
        elif en:
            acc_reg = wrap32(acc_in + golden_mac(a, w, acc_in))
        out.append(acc_reg)   # registered output observed after the edge
    return out

# ---------------- TIER B golden: dot27 per spec ----------------
N, Z, P = 0b00, 0b01, 0b10
def tmul(ta, tb):  # verbatim spec semantics
    if ta == Z: return 0
    if tb == Z: return 0
    if ta == tb: return 1
    return -1
def pack27(trits):
    v = 0
    for i, t in enumerate(trits):
        v |= (t & 3) << (i << 1)
    return v
def dot27(a, b):  # spec: 27 positions, sum of tmul over 2-bit fields
    return sum(tmul((a >> (i << 1)) & 3, (b >> (i << 1)) & 3) for i in range(27))

ALL_N, ALL_Z, ALL_P = pack27([N]*27), pack27([Z]*27), pack27([P]*27)
MIXED = pack27([P, Z, N]*9)                       # 9*(+1+0-1) = 0
MIXED2 = pack27([P, P, N]*9)                      # 9*(+1+1-1) = 9
BOUND_26 = pack27([P]*26 + [Z])                   # +26 boundary inside [-27,27]
BOUND_27N_NP = (ALL_N, ALL_P)                     # -27 exact lower bound

def run_mac_tier(tmpdir, log):
    vectors = []
    # enumeration: every weight code x activation edges (zero-trit weight paths
    # = 2'b00 and 2'b11; activation edges -128/-1/0/+1/+127)
    for w in (0b00, 0b01, 0b10, 0b11):
        for a in (-128, -1, 0, 1, 127):
            vectors.append((a, w, 0, 1, 1))
    # accumulator overflow boundaries (32-bit wrap both directions)
    vectors.append((127,  0b01,  2147483647, 1, 1))
    vectors.append((127,  0b01,  2147483647 - 126, 1, 1))   # lands exactly at MAX then wraps
    vectors.append((-128, 0b10, -2147483648, 1, 1))
    vectors.append((1,    0b01,  2147483646, 1, 1))
    # control/gating: async clear, enable hold, then a 3-step stream
    vectors.append((5, 0b01, 12345, 0, 1))    # rst_n=0 -> acc_out must be 0
    vectors.append((5, 0b01, 999,   1, 0))    # en=0 -> hold previous (0 after reset)
    vectors.append((7, 0b01, 100,   1, 1))    # stream step 1 -> 107
    vectors.append((3, 0b10, 107,   1, 1))    # stream step 2 -> 110
    vectors.append((0, 0b11, 110,   1, 1))    # stream step 3 -> 110 (zero weight)

    vecfile = os.path.join(tmpdir, "vectors_mac.txt")
    with open(vecfile, "w") as f:
        for v in vectors:
            f.write("%d %d %d %d %d\n" % v)

    simfile = os.path.join(tmpdir, "sim.v")
    comp = subprocess.run(["iverilog", "-g2012", "-o", simfile, TB, MAC_RTL],
                          capture_output=True, text=True, cwd=tmpdir)
    if comp.returncode != 0:
        log("iverilog compile FAILED:\n" + comp.stderr)
        return None, vectors
    run = subprocess.run(["vvp", simfile, "-n"],
                         capture_output=True, text=True, cwd=tmpdir)
    measured = []
    for line in run.stdout.splitlines():
        if line.startswith("MACRESULT"):
            _, va, vw, vacc, vrst, ven, acc = line.split()
            measured.append(int(acc))
    if "MACDONE" not in run.stdout or len(measured) != len(vectors):
        log("TB run incomplete: %d/%d results" % (len(measured), len(vectors)))
        log("vvp stdout tail: %r" % run.stdout[-300:])
        log("vvp stderr: %r" % run.stderr[-300:])
        return None, vectors

    expected = sim_mac(vectors)
    rows = []
    npass = 0
    for v, exp, got in zip(vectors, expected, measured):
        ok = exp == got
        npass += ok
        rows.append({"vector": v, "expected": exp, "measured_rtl": got, "pass": ok})
    log("TIER A (RTL, iverilog): %d/%d pass" % (npass, len(vectors)))
    return {"tier": "A", "label": "RTL-VERIFIED (ternary_mac_top, iverilog)",
            "vectors": rows, "npass": npass, "ntotal": len(vectors)}, vectors

def run_dot27_tier(log):
    spec_tests = [
        ("dot_all_n_x_all_n",  ALL_N, ALL_N, 27),
        ("dot_all_n_x_all_p",  ALL_N, ALL_P, -27),
        ("dot_all_p_x_all_p",  ALL_P, ALL_P, 27),
        ("dot_all_z",          ALL_Z, ALL_Z, 0),
    ]
    edges = [
        ("single_pos_plus",   pack27([P]+[Z]*26), pack27([P]+[Z]*26), 1),
        ("single_pos_minus",  pack27([P]+[Z]*26), pack27([N]+[Z]*26), -1),
        ("boundary_26",       BOUND_26, BOUND_26, 26),
        ("boundary_minus_27", BOUND_27N_NP[0], BOUND_27N_NP[1], -27),
        ("self_dot_mixed_18", MIXED, MIXED, 18),            # self-dot: 9*(1+0+1)
        ("cross_mixed_minus9", MIXED2, pack27([N, P, P]*9), -9),  # 9*(-1+1-1)
    ]
    rows, npass = [], 0
    for name, va, vb, exp in spec_tests + edges:
        got = dot27(va, vb)
        ok = got == exp
        npass += ok
        rows.append({"name": name, "a": va, "b": vb, "expected": exp,
                     "golden_dot27": got, "pass": ok})
    log("TIER B (spec golden): %d/%d pass" % (npass, len(rows)))
    return {"tier": "B", "label": "SPEC-VERIFIED (stream_ternary_mac.t27; RTL leg pending R3)",
            "vectors": rows, "npass": npass, "ntotal": len(rows)}

def run_dot27_rtl_tier(log, spec_vectors):
    """Tier B2: dot27 RTL leg — t27c_lite-emitted dot27_top.v (spec-derived,
    byte-identical regeneration proven) simulated with iverilog vs golden."""
    rtl = os.path.join(REPO, "rtl", "t27c_lite", "dot27_top.v")
    if not os.path.exists(rtl):
        log("B2 skipped: %s missing (run t27c_lite.py first)" % os.path.relpath(rtl, REPO))
        return None
    rng = random.Random(424242)  # fixed seed: evidence reproducibility
    Nv, Zv, Pv = 0, 1, 2
    def pk(trits):
        v = 0
        for i, t in enumerate(trits):
            v |= t << (i << 1)
        return v
    vecs = [(r["name"], r["a"], r["b"]) for r in spec_vectors]
    for k in range(40):
        a = b = 0
        for i in range(27):
            a |= rng.choice((Nv, Zv, Pv)) << (i << 1)
            b |= rng.choice((Nv, Zv, Pv)) << (i << 1)
        vecs.append(("random_%02d" % k, a, b))
    rows, npass = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        vf = os.path.join(tmp, "v.txt")
        with open(vf, "w") as f:
            for n, a, b in vecs:
                f.write("%s %d %d\n" % (n, a, b))
        tb = os.path.join(tmp, "tb.v")
        with open(tb, "w") as f:
            f.write("`timescale 1ns/1ps\nmodule tb;\n"
                    "  reg [53:0] a, b; wire signed [5:0] y;\n"
                    "  integer fd, n; reg [255:0] name;\n"
                    "  dot27_top dut(.a(a), .b(b), .y(y));\n"
                    "  initial begin\n"
                    "    fd = $fopen(\"v.txt\", \"r\");\n"
                    "    while (!$feof(fd)) begin\n"
                    "      n = $fscanf(fd, \"%s %d %d\", name, a, b);\n"
                    "      if (n == 3) begin #1; $display(\"D27RESULT %0s %0d\", name, y); end\n"
                    "    end\n $display(\"D27DONE\"); $finish;\n end\nendmodule\n")
        c = subprocess.run(["iverilog", "-g2012", "-o", os.path.join(tmp, "sim"),
                            tb, rtl], capture_output=True, text=True, cwd=tmp)
        if c.returncode != 0:
            log("B2 iverilog compile FAILED:\n" + c.stderr)
            return None
        r = subprocess.run(["vvp", os.path.join(tmp, "sim"), "-n"],
                           capture_output=True, text=True, cwd=tmp)
        got = {}
        for line in r.stdout.splitlines():
            if line.startswith("D27RESULT"):
                _, nm, val = line.split()
                got[nm] = int(val)
    if "D27DONE" not in r.stdout or len(got) != len(vecs):
        log("B2 sim incomplete %d/%d" % (len(got), len(vecs)))
        return None
    for n, a, b in vecs:
        exp = dot27(a, b)
        ok = got[n] == exp
        npass += ok
        rows.append({"name": n, "a": a, "b": b, "expected": exp,
                     "measured_rtl": got[n], "pass": ok})
    log("TIER B2 (dot27 RTL leg, t27c_lite emission): %d/%d pass" % (npass, len(rows)))
    return {"tier": "B2", "label": "RTL-VERIFIED (dot27_top.v, t27c_lite-emitted, iverilog)",
            "vectors": rows, "npass": npass, "ntotal": len(rows)}

def run_stream_rtl_tier(log):
    """Tier B3: streaming on_clock leg — t27c_lite-emitted stream_ternary_mac_top.v
    (spec-derived: var acc + on_clock body + en contract) simulated with iverilog
    over 16 randomized streams (seed 777) vs the INDEPENDENT spec golden
    (dot27 above + 32-bit wrap). en=0 cycles must hold acc."""
    rtl = os.path.join(REPO, "rtl", "t27c_lite", "stream_ternary_mac_top.v")
    dot = os.path.join(REPO, "rtl", "t27c_lite", "dot27_top.v")
    if not os.path.exists(rtl):
        log("B3 skipped: %s missing (run t27c_lite.py first)" % os.path.relpath(rtl, REPO))
        return None
    rng = random.Random(777)  # fixed seed, distinct from the compiler's own vectors
    cyc, exp = [], []
    acc = 0
    for k in range(16):
        L = rng.randint(1, 12)
        for _ in range(rng.randint(1, 3)):          # en=0 hold cycles
            cyc.append((0, 0, 0)); exp.append(acc)
        for _ in range(L):
            a = b = 0
            for i in range(27):
                a |= rng.choice((N, Z, P)) << (i << 1)
                b |= rng.choice((N, Z, P)) << (i << 1)
            acc = wrap32(acc + dot27(a, b))
            cyc.append((a, b, 1)); exp.append(acc)
        cyc.append((0, 0, 0)); exp.append(acc)      # tail hold: read time
    rows, npass = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        vf = os.path.join(tmp, "sv.txt")
        with open(vf, "w") as f:
            for s, (a, b, en) in enumerate(cyc):
                f.write("%d %d %d %d\n" % (s, a, b, en))
        tb = os.path.join(tmp, "tb_stream.v")
        with open(tb, "w") as f:
            f.write("`timescale 1ns/1ps\nmodule tb_stream;\n"
                    "  reg clk = 0; reg en; reg [53:0] a, b;\n"
                    "  wire signed [31:0] acc; integer fd, n, stepno;\n"
                    "  stream_ternary_mac_top dut(.clk(clk), .en(en), .a(a), .b(b), .acc(acc));\n"
                    "  always #5 clk = ~clk;\n"
                    "  initial begin\n"
                    "    fd = $fopen(\"sv.txt\", \"r\");\n"
                    "    while (!$feof(fd)) begin\n"
                    "      n = $fscanf(fd, \"%d %d %d %d\", stepno, a, b, en);\n"
                    "      if (n == 4) begin @(posedge clk); #1;\n"
                    "        $display(\"B3RESULT %0d %0d\", stepno, acc); end\n"
                    "    end\n $display(\"B3DONE\"); $finish;\n end\nendmodule\n")
        c = subprocess.run(["iverilog", "-g2012", "-o", os.path.join(tmp, "sim3"),
                            tb, rtl, dot], capture_output=True, text=True, cwd=tmp)
        if c.returncode != 0:
            log("B3 iverilog compile FAILED:\n" + c.stderr)
            return None
        r = subprocess.run(["vvp", os.path.join(tmp, "sim3"), "-n"],
                           capture_output=True, text=True, cwd=tmp)
        got = {}
        for line in r.stdout.splitlines():
            if line.startswith("B3RESULT"):
                _, st, val = line.split()
                got[int(st)] = int(val)
    if "B3DONE" not in r.stdout or len(got) != len(cyc):
        log("B3 sim incomplete %d/%d" % (len(got), len(cyc)))
        return None
    for s, (a, b, en) in enumerate(cyc):
        ok = got[s] == exp[s]
        npass += ok
        rows.append({"cycle": s, "a": a, "b": b, "en": en, "expected_acc": exp[s],
                     "measured_rtl": got[s], "pass": ok})
    n_hold = sum(1 for _, _, en in cyc if en == 0)
    log("TIER B3 (stream on_clock RTL leg, %d cycles incl. %d en=0 holds): %d/%d pass"
        % (len(cyc), n_hold, npass, len(rows)))
    return {"tier": "B3", "label": "RTL-VERIFIED (stream_ternary_mac_top.v, on_clock leg)",
            "vectors": rows, "npass": npass, "ntotal": len(rows)}

def main():
    lines = []
    log = lines.append
    with tempfile.TemporaryDirectory() as tmpdir:
        tier_a, _ = run_mac_tier(tmpdir, log)
    tier_b = run_dot27_tier(log)
    tier_b2 = run_dot27_rtl_tier(log, tier_b["vectors"])
    tier_b3 = run_stream_rtl_tier(log)

    overall = bool(tier_a and tier_b["npass"] == tier_b["ntotal"]
                   and tier_a["npass"] == tier_a["ntotal"]
                   and tier_b2 and tier_b2["npass"] == tier_b2["ntotal"]
                   and tier_b3 and tier_b3["npass"] == tier_b3["ntotal"])
    for l in lines: print(l)
    print("OVERALL: %s" % ("PASS" if overall else "FAIL"))

    vinfo = subprocess.run(["iverilog", "-V"], capture_output=True, text=True)
    vbanner = next((l for l in (vinfo.stderr + vinfo.stdout).splitlines() if "Icarus" in l), "unknown")
    result = {"date": "2026-11-23", "overall": "PASS" if overall else "FAIL",
              "tiers": [tier_a, tier_b, tier_b2, tier_b3],
              "log": lines,
              "sources": {
                  "mac_rtl": os.path.relpath(MAC_RTL, REPO),
                  "tb": os.path.relpath(TB, REPO),
                  "spec": "specs/ternary/stream_ternary_mac.t27"},
              "toolchain": {"iverilog": vbanner}}
    outdir = os.path.join(REPO, "evidence", "conformance")
    os.makedirs(outdir, exist_ok=True)
    outfile = os.path.join(outdir, "conformance_result_2026-11-23.json")
    blob = json.dumps(result, indent=1)
    with open(outfile, "w") as f:
        f.write(blob)
    digest = hashlib.sha256(blob.encode()).hexdigest()
    with open(outfile, "a") as f:
        f.write("SHA256_SELF: %s\n" % digest)
    print("WROTE %s sha256=%s" % (os.path.relpath(outfile, REPO), digest[:16] + "..."))
    return 0 if overall else 1

if __name__ == "__main__":
    sys.exit(main())
