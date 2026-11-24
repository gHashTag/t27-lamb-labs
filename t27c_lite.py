#!/usr/bin/env python3
"""t27c_lite.py — spec-first subset compiler for the ternary dot-product pattern.

Compiles TWO spec patterns to structural Verilog:
  1. `specs/ternary/stream_ternary_mac.t27` (clocked: dot27 + var/on_clock/en
     streaming wrapper) -> dot27_top.v + stream_ternary_mac_top.v;
  2. `specs/ternary/comb_ternary_dot.t27` (combinational: on_comb(a,b) -> i8)
     -> comb_ternary_dot_top.v.

NOTHING is hand-transcribed: the emitted RTL is derived from the parsed spec
text —
  - trit code constants from the spec's own code table comment {N=..., Z=..., P=...};
  - the tmul truth table by symbolically evaluating the spec's if/return chain
    for every defined (ta, tb) code pair;
  - the trit-field encoding (2 bits, shift, mask) from the tp body;
  - the trit position list from the tp(a,b,i) terms in the dot27 body;
  - the streaming wrapper (stream_ternary_mac_top.v) from the parsed
    `var acc : i32 = 0` initializer, the on_clock body, and the spec-header
    `en` contract — plus reuse of the emitted dot27_top (no re-derivation);
  - the spec's own `test` blocks become mandatory conformance vectors.
Out-of-spec 2-bit codes (2'b11 on either operand) map to 0 by the committed
cell convention (ternary_mac_top: 2'b00 and 2'b11 decode to 0); vectors never
exercise them, and the emitted header says so.

Pipeline: parse -> validate golden against spec tests -> emit Verilog ->
iverilog bit-exact run (spec tests + edges + randomized vectors) -> yosys
synth_xilinx (must be clean) -> evidence JSON + sha256. Gates 1-6 cover the
streaming spec, gates 7-9 the combinational spec. Exit non-zero on any failure.
"""
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(REPO, "specs", "ternary", "stream_ternary_mac.t27")
OUTDIR = os.path.join(REPO, "rtl", "t27c_lite")
SPEC_SHA = hashlib.sha256(open(SPEC, "rb").read()).hexdigest()
COMB_SPEC = os.path.join(REPO, "specs", "ternary", "comb_ternary_dot.t27")
COMB_SPEC_SHA = hashlib.sha256(open(COMB_SPEC, "rb").read()).hexdigest()

log_lines = []
def log(s):
    print(s)
    log_lines.append(s)

# ---------------- 1. PARSE ----------------
def _parse_codes(text):
    m = re.search(r"\{((?:[NZP]=0b[01]{2}(?:,\s*)?)+)\}", text)
    codes = {}
    for name, val in re.findall(r"([NZP])=0b([01]{2})", m.group(1)):
        codes[name] = int(val, 2)
    if sorted(codes) != ["N", "P", "Z"]:
        fail("code table parse: %r" % codes)
    return codes

def _parse_tmul(text, codes):
    fn_m = re.search(r"fn tmul\(ta: u8, tb: u8\) -> i8 \{(.*?)\n\}", text, re.S)
    chain = []
    for cond, ret in re.findall(r"if \((ta == [^)]+|tb == [^)]+)\) \{ return (-?\d+); \}", fn_m.group(1)):
        chain.append((cond, int(ret)))
    tail = re.findall(r"return (-?\d+);", fn_m.group(1))[-1]

    def cond_holds(cond, ta, tb):
        var, rhs = cond.split("==")
        var, rhs = var.strip(), rhs.strip()
        lhs = {"ta": ta, "tb": tb}[var]
        if rhs in ("ta", "tb"):
            rv = {"ta": ta, "tb": tb}[rhs]
        elif rhs in codes:
            rv = codes[rhs]
        else:
            rv = int(rhs)
        return lhs == rv

    table = {}
    for ta in codes.values():
        for tb in codes.values():
            for cond, ret in chain:
                if cond_holds(cond, ta, tb):
                    table[(ta, tb)] = ret
                    break
            else:
                table[(ta, tb)] = int(tail)
    if len(table) != 9:
        fail("tmul table incomplete: %r" % table)
    return table

def _parse_tp(text):
    tp_m = re.search(r"fn tp\(a: u64, b: u64, i: u32\) -> i8 \{\s*return (.*?);", text, re.S)
    sh_m = re.search(r"\(a >> \(i << (\d+)\)\) & (\d+)", tp_m.group(1))
    trit_shift, trit_mask = int(sh_m.group(1)), int(sh_m.group(2))
    bits_per_trit = trit_shift + 1  # i << 1 -> 2 bits per trit field
    if trit_mask != (1 << bits_per_trit) - 1:
        fail("mask %d inconsistent with %d-bit fields" % (trit_mask, bits_per_trit))
    return bits_per_trit

def _dot_positions(body, ap, bp, label):
    positions = [int(p) for p in re.findall(r"tp\(%s,%s,(\d+)\)" % (ap, bp), body)]
    if positions != list(range(len(positions))):
        fail("%s body: positions not contiguous 0..%d: %r"
             % (label, len(positions) - 1, positions))
    return positions

def parse_spec():
    text = open(SPEC).read()
    codes = _parse_codes(text)
    table = _parse_tmul(text, codes)
    bits_per_trit = _parse_tp(text)

    dot_m = re.search(r"fn dot27\(a: u64, b: u64\) -> i8 \{\s*return (.*?);\s*\}", text, re.S)
    positions = _dot_positions(dot_m.group(1), "a", "b", "dot27")

    tests = [(int(va), int(vb), int(vx)) for va, vb, vx in
             re.findall(r"assert_eq\(dot27\((\d+), (\d+)\), (-?\d+)\);", text)]
    if not tests:
        fail("no spec tests parsed")

    # streaming layer: var declaration, on_clock body, en contract (spec header).
    # Every emitted port/behavior below maps to one of these parsed items - the
    # compiler invents no reset, no extra ports, no semantics.
    var_m = re.search(r"var (\w+) : i(\d+) = (-?\d+)", text)
    if not var_m:
        fail("var declaration (acc) not parsed")
    acc = dict(name=var_m.group(1), bits=int(var_m.group(2)),
               init=int(var_m.group(3)))
    oc_m = re.search(r"fn on_clock\((\w+): u64, (\w+): u64\) \{\s*(\w+) = (\w+) \+ "
                     r"\(dot27\((\w+), (\w+)\) as i(\d+)\)\s*\}", text)
    if not oc_m:
        fail("on_clock body not in the supported shape "
             "`acc = acc + (dot27(a, b) as i32)`")
    a_p, b_p, lhs, rhs, da, db, wid = oc_m.groups()
    if not (lhs == rhs == acc["name"] and da == a_p and db == b_p
            and int(wid) == acc["bits"]):
        fail("on_clock body inconsistent with var declaration")
    # the spec line-wraps the sentence across `//` comment lines:
    # "...and `en` gates the\n// accumulation so a caller..."
    en_m = re.search(r"`en` gates the\s*(?://\s*)?accumulation", text)
    if not en_m:
        fail("en-gating contract sentence missing from spec header")
    return dict(codes=codes, table=table, positions=positions,
                bits_per_trit=bits_per_trit, tests=tests,
                acc=acc, on_clock=dict(a=a_p, b=b_p), en_gated=True)

def parse_comb_spec():
    """Second spec pattern: combinational on_comb(a, b) -> i8 (no state, no clk).

    Parsed items -> emitted RTL:
      on_comb(a: u64, b: u64)  -> input ports a [53:0], b [53:0]
      -> i8 return type        -> output wire signed [7:0] result
      `output wire result`     -> the output port is continuously driven
                                  (spec-header sentence, may wrap across //)
      tp(a,b,i) sum in body    -> positional structure (contiguous 0..N-1)
      tmul if/return chain     -> truth table by symbolic eval (shared helper)
    """
    text = open(COMB_SPEC).read()
    codes = _parse_codes(text)
    table = _parse_tmul(text, codes)
    bits_per_trit = _parse_tp(text)
    oc_m = re.search(r"fn on_comb\((\w+): u64, (\w+): u64\) -> i(\d+) \{\s*return (.*?);\s*\}",
                     text, re.S)
    if not oc_m:
        fail("on_comb body not in the supported shape "
             "`return tp(a,b,0) + ... + tp(a,b,N)`")
    a_p, b_p, rw, body = oc_m.groups()
    positions = _dot_positions(body, a_p, b_p, "on_comb")
    # spec-header port contract; the sentence wraps across // comment lines
    om = re.search(r"`output wire\s*(?://\s*)?result`", text)
    if not om:
        fail("spec-header contract `output wire result` missing")
    tests = [(int(va), int(vb), int(vx)) for va, vb, vx in
             re.findall(r"assert_eq\(on_comb\((\d+), (\d+)\), (-?\d+)\);", text)]
    if not tests:
        fail("no on_comb spec tests parsed")
    return dict(codes=codes, table=table, positions=positions,
                bits_per_trit=bits_per_trit, tests=tests,
                result_bits=int(rw), on_comb=dict(a=a_p, b=b_p))

def fail(msg):
    log("FAIL: " + msg)
    write_evidence(False, None)
    sys.exit(1)

# ---------------- 2. GOLDEN (from parsed spec only) ----------------
def golden_dot27(sp, a, b):
    s = 0
    for i in sp["positions"]:
        ta = (a >> (i << (sp["bits_per_trit"] - 1))) & sp["__mask"]
        tb = (b >> (i << (sp["bits_per_trit"] - 1))) & sp["__mask"]
        s += sp["table"][(ta, tb)]
    return s

# ---------------- 3. EMIT ----------------
TMUL_TXT = {1: "2'b01", 0: "2'b00", -1: "2'b11"}  # signed 2-bit two's complement
def emit_verilog(sp):
    lines = [
        "`default_nettype none",
        "// dot27_top.v — GENERATED by t27c_lite.py — DO NOT HAND-EDIT (law L2 spirit).",
        "// Source spec: specs/ternary/stream_ternary_mac.t27",
        "// Spec sha256: %s" % SPEC_SHA,
        "// Derived from spec text: trit codes %s; tmul truth table (symbolic eval of"
        " the spec if/return chain over all 9 defined code pairs); %d trit positions"
        " (from the dot27 body); %d-bit fields (from the tp body)."
        % (sp["codes"], len(sp["positions"]), sp["bits_per_trit"]),
        "// Out-of-spec operand code 2'b11 maps to 0 by committed cell convention",
        "// (ternary_mac_top: 2'b00 and 2'b11 decode to 0). Vectors never use it.",
        "module tmul_lut(input [1:0] ta, input [1:0] tb, output reg signed [1:0] y);",
        "    always @(*) case ({ta, tb})",
    ]
    for (ta, tb), v in sorted(sp["table"].items()):
        lines.append("        4'b%04d: y = %s;  // %s*%s"
                     % (int(format(ta, "02b") + format(tb, "02b")), TMUL_TXT[v],
                        {v: k for k, v in sp["codes"].items()}.get(ta, "?"),
                        {v: k for k, v in sp["codes"].items()}.get(tb, "?")))
    lines += ["        default: y = 2'b00;  // out-of-spec operand code -> 0 (cell convention)",
              "    endcase", "endmodule", "",
              "module dot27_top(input [53:0] a, input [53:0] b, output signed [5:0] y);"]
    for i in sp["positions"]:
        lo = i << (sp["bits_per_trit"] - 1)
        hi = lo + sp["bits_per_trit"] - 1
        lines.append("    wire [%d:0] fa%d = a[%d:%d]; wire [%d:0] fb%d = b[%d:%d];"
                     % (sp["bits_per_trit"] - 1, i, hi, lo, sp["bits_per_trit"] - 1, i, hi, lo))
        lines.append("    wire signed [1:0] t%d;" % i)
        lines.append("    tmul_lut lut%d(.ta(fa%d), .tb(fb%d), .y(t%d));" % (i, i, i, i))
    # balanced adder tree, sign-extended to 6 bits
    level = ["{{4{%s[1]}}, %s}" % ("t%d" % i, "t%d" % i) for i in sp["positions"]]
    n = 0
    while len(level) > 1:
        nxt = []
        for j in range(0, len(level) - 1, 2):
            lines.append("    wire signed [5:0] s%d = $signed(%s) + $signed(%s);" % (n, level[j], level[j + 1]))
            nxt.append("s%d" % n); n += 1
        if len(level) % 2:
            nxt.append(level[-1])
        level = nxt
    lines += ["    assign y = $signed(%s);" % level[0], "endmodule", "`default_nettype wire", ""]
    return "\n".join(lines)

def emit_stream_verilog(sp):
    """Emit the streaming wrapper from the parsed var/on_clock/en spec items.

    Every line below traces to spec text:
      clk               <- the construct IS on_clock (a clocked process);
      a, b [53:0]       <- on_clock(a: u64, b: u64) input ports;
      acc [31:0]        <- var acc : i32 = 0  (also the initial value);
      en gate           <- spec-header contract "`en` gates the accumulation";
      acc <= acc + dot  <- on_clock body `acc = acc + (dot27(a, b) as i32)`;
      dot27 reuse       <- the already-emitted, bit-exact-verified dot27_top.
    No reset port: the spec subset declares none; acc initialization comes
    from the var initializer only.
    """
    A, N = sp["acc"]["name"], sp["acc"]["bits"]
    hi = sp["acc"]["bits"] - 1
    return "\n".join([
        "`default_nettype none",
        "// stream_ternary_mac_top.v — GENERATED by t27c_lite.py — DO NOT HAND-EDIT.",
        "// Source spec: specs/ternary/stream_ternary_mac.t27",
        "// Spec sha256: %s" % SPEC_SHA,
        "// Derived from spec text: %s [%d:0] = var %s : i%d = %d; en gate = the"
        " spec-header contract \"`en` gates the accumulation\"; per-cycle update"
        " = the on_clock body `%s = %s + (dot27(a, b) as i%d)`; dot product = the"
        " emitted, bit-exact-verified dot27_top (no re-derivation here)."
        % (A, hi, A, N, sp["acc"]["init"], A, A, N),
        "// No reset port: the spec subset declares none; initialization is the",
        "// var initializer, not an invented reset. en=0 holds acc (streams N then",
        "// read the running sum, per the spec header).",
        "module stream_ternary_mac_top(input wire clk, input wire en,",
        "    input wire [53:0] a, input wire [53:0] b,",
        "    output reg signed [%d:0] %s);" % (hi, A),
        "    wire signed [5:0] dot;",
        "    dot27_top dot27_i(.a(a), .b(b), .y(dot));",
        "    initial %s = %d'sd%d;" % (A, N, sp["acc"]["init"]),
        "    always @(posedge clk)",
        "        if (en) %s <= %s + $signed({{%d{dot[5]}}, dot});"
        % (A, A, N - 6),
        "endmodule",
        "`default_nettype wire",
        "",
    ])

def emit_comb_verilog(csp):
    """Emit comb_ternary_dot_top.v from the parsed comb-spec items (gates 7-9).

    Every line below traces to the comb spec text:
      a, b [53:0]      <- on_comb(a: u64, b: u64) parameters; width = positions
                          x bits-per-trit (both from the parsed spec);
      result [7:0]     <- `-> i8` return type;
      output wire      <- the spec-header contract "`output wire result`";
      continuously     <- "continuously-driven output wire" -> a single assign,
      driven             no clock, no register;
      tmul_lut_c       <- symbolic eval of the spec's own if/return chain;
      adder tree       <- the tp(a,b,i) sum in the on_comb body.
    The spec declares no state -> no clock, no reset, no initial block.
    """
    W = (max(csp["positions"]) + 1) * csp["bits_per_trit"]
    R = csp["result_bits"]
    lines = [
        "`default_nettype none",
        "// comb_ternary_dot_top.v — GENERATED by t27c_lite.py — DO NOT HAND-EDIT.",
        "// Source spec: specs/ternary/comb_ternary_dot.t27",
        "// Spec sha256: %s" % COMB_SPEC_SHA,
        "// Derived from spec text: ports from on_comb(%s: u64, %s: u64);"
        " output wire result, signed to i%d from the return type; continuously"
        " driven per the spec-header `output wire result` contract; tmul truth"
        " table by symbolic eval of the spec if/return chain over all 9 code"
        " pairs; %d trit positions from the on_comb body; %d-bit fields from"
        " the tp body. No clock, no reset: the spec declares no state."
        % (csp["on_comb"]["a"], csp["on_comb"]["b"], R, len(csp["positions"]),
           csp["bits_per_trit"]),
        "// Out-of-spec operand code 2'b11 maps to 0 by committed cell convention",
        "// (ternary_mac_top: 2'b00 and 2'b11 decode to 0). Vectors never use it.",
        "module tmul_lut_c(input [1:0] ta, input [1:0] tb, output reg signed [1:0] y);",
        "    always @(*) case ({ta, tb})",
    ]
    for (ta, tb), v in sorted(csp["table"].items()):
        lines.append("        4'b%04d: y = %s;  // %s*%s"
                     % (int(format(ta, "02b") + format(tb, "02b")), TMUL_TXT[v],
                        {v: k for k, v in csp["codes"].items()}.get(ta, "?"),
                        {v: k for k, v in csp["codes"].items()}.get(tb, "?")))
    lines += ["        default: y = 2'b00;  // out-of-spec operand code -> 0 (cell convention)",
              "    endcase", "endmodule", "",
              "module comb_ternary_dot_top(input [%d:0] a, input [%d:0] b,"
              " output wire signed [%d:0] result);" % (W - 1, W - 1, R - 1)]
    for i in csp["positions"]:
        lo = i << (csp["bits_per_trit"] - 1)
        hi = lo + csp["bits_per_trit"] - 1
        lines.append("    wire [%d:0] fa%d = a[%d:%d]; wire [%d:0] fb%d = b[%d:%d];"
                     % (csp["bits_per_trit"] - 1, i, hi, lo,
                        csp["bits_per_trit"] - 1, i, hi, lo))
        lines.append("    wire signed [1:0] t%d;" % i)
        lines.append("    tmul_lut_c lut%d(.ta(fa%d), .tb(fb%d), .y(t%d));"
                     % (i, i, i, i))
    # balanced adder tree, sign-extended to the spec's return width
    level = ["{{%d{%s[1]}}, %s}" % (R - 2, "t%d" % i, "t%d" % i)
             for i in csp["positions"]]
    n = 0
    while len(level) > 1:
        nxt = []
        for j in range(0, len(level) - 1, 2):
            lines.append("    wire signed [%d:0] s%d = $signed(%s) + $signed(%s);"
                         % (R - 1, n, level[j], level[j + 1]))
            nxt.append("s%d" % n); n += 1
        if len(level) % 2:
            nxt.append(level[-1])
        level = nxt
    lines += ["    assign result = $signed(%s);" % level[0],
              "endmodule", "`default_nettype wire", ""]
    return "\n".join(lines)

# ---------------- 4. VECTORS ----------------
def build_vectors(sp):
    vecs = [("spec_test_%d" % k, a, b, x) for k, (a, b, x) in enumerate(sp["tests"])]
    Nc, Zc, Pc = sp["codes"]["N"], sp["codes"]["Z"], sp["codes"]["P"]
    vecs += [
        ("edge_single_plus",  sp2pack(sp, [Pc] + [Zc] * 26), sp2pack(sp, [Pc] + [Zc] * 26), 1),
        ("edge_single_minus", sp2pack(sp, [Pc] + [Zc] * 26), sp2pack(sp, [Nc] + [Zc] * 26), -1),
        ("edge_bound_26",     sp2pack(sp, [Pc] * 26 + [Zc]), sp2pack(sp, [Pc] * 26 + [Zc]), 26),
        ("edge_bound_minus27", sp2pack(sp, [Nc] * 27), sp2pack(sp, [Pc] * 27), -27),
        ("edge_all_zero",     sp2pack(sp, [Zc] * 27), sp2pack(sp, [Zc] * 27), 0),
    ]
    codes = sorted(sp["codes"].values())
    rng = random.Random(20261123)  # fixed seed: evidence reproducibility
    for k in range(108):
        a = b = 0
        for i in sp["positions"]:
            a |= rng.choice(codes) << (i << (sp["bits_per_trit"] - 1))
            b |= rng.choice(codes) << (i << (sp["bits_per_trit"] - 1))
        vecs.append(("random_%03d" % k, a, b, golden_dot27(sp, a, b)))
    return vecs

def sp2pack(sp, trits):
    v = 0
    for i, t in enumerate(trits):
        v |= t << (i << (sp["bits_per_trit"] - 1))
    return v

def build_comb_vectors(csp):
    """Vectors for the comb pattern: spec tests + edges + randomized (fixed seed)."""
    vecs = [("spec_test_%d" % k, a, b, x) for k, (a, b, x) in enumerate(csp["tests"])]
    Nc, Zc, Pc = csp["codes"]["N"], csp["codes"]["Z"], csp["codes"]["P"]
    vecs += [
        ("edge_single_plus",  sp2pack(csp, [Pc] + [Zc] * 26), sp2pack(csp, [Pc] + [Zc] * 26), 1),
        ("edge_single_minus", sp2pack(csp, [Pc] + [Zc] * 26), sp2pack(csp, [Nc] + [Zc] * 26), -1),
        ("edge_bound_26",     sp2pack(csp, [Pc] * 26 + [Zc]), sp2pack(csp, [Pc] * 26 + [Zc]), 26),
        ("edge_bound_minus27", sp2pack(csp, [Nc] * 27), sp2pack(csp, [Pc] * 27), -27),
        ("edge_all_zero",     sp2pack(csp, [Zc] * 27), sp2pack(csp, [Zc] * 27), 0),
    ]
    codes = sorted(csp["codes"].values())
    rng = random.Random(20261125)  # fixed seed: evidence reproducibility
    for k in range(60):
        a = b = 0
        for i in csp["positions"]:
            a |= rng.choice(codes) << (i << (csp["bits_per_trit"] - 1))
            b |= rng.choice(codes) << (i << (csp["bits_per_trit"] - 1))
        vecs.append(("crandom_%03d" % k, a, b, golden_dot27(csp, a, b)))
    return vecs

def write_evidence(ok, extra):
    outdir = os.path.join(REPO, "evidence", "t27c_lite")
    os.makedirs(outdir, exist_ok=True)
    data = {"date": "2026-11-23", "status": "PASS" if ok else "FAIL",
            "spec": os.path.relpath(SPEC, REPO), "spec_sha256": SPEC_SHA,
            "log": log_lines, "extra": extra}
    blob = json.dumps(data, indent=1)
    p = os.path.join(outdir, "t27c_lite_run_2026-11-23.json")
    with open(p, "w") as f:
        f.write(blob + "\nSHA256_SELF: %s\n" % hashlib.sha256(blob.encode()).hexdigest())
    log("WROTE %s" % os.path.relpath(p, REPO))

def _det_stat(stdout, top="dot27_top"):
    """Deterministic slice of yosys output: the === stat blocks only."""
    s = stdout[stdout.rfind("=== %s ===" % top):]
    end = s.find("End of script.")
    if end >= 0:
        s = s[:end]
    return s.rstrip() + "\n[volatile yosys timing tail stripped for determinism]"


def main():
    sp = parse_spec()
    sp["__mask"] = (1 << sp["bits_per_trit"]) - 1
    log("parsed: codes=%s positions=%d bits/trit=%d spec_tests=%d"
        % (sp["codes"], len(sp["positions"]), sp["bits_per_trit"], len(sp["tests"])))

    # gate 1: golden (pure spec text) must satisfy the spec's own tests
    for a, b, x in sp["tests"]:
        g = golden_dot27(sp, a, b)
        if g != x:
            fail("spec test dot27(%d,%d): golden %d != spec %d" % (a, b, g, x))
    log("gate1 PASS: golden satisfies all %d spec-embedded tests" % len(sp["tests"]))

    # gate 2: emit
    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, "dot27_top.v")
    with open(out, "w") as f:
        f.write(emit_verilog(sp))
    log("gate2 PASS: emitted %s (%d bytes)" % (os.path.relpath(out, REPO), os.path.getsize(out)))

    # gate 3: bit-exact sim (iverilog)
    vecs = build_vectors(sp)
    with tempfile.TemporaryDirectory() as tmp:
        vf = os.path.join(tmp, "v.txt")
        with open(vf, "w") as f:
            for name, a, b, _ in vecs:
                f.write("%s %d %d\n" % (name, a, b))
        tb = os.path.join(tmp, "tb.v")
        with open(tb, "w") as f:
            f.write("""
`timescale 1ns/1ps
module tb;
  reg [53:0] a, b; wire signed [5:0] y; integer fd, n; reg [1023:0] name;
  dot27_top dut(.a(a), .b(b), .y(y));
  initial begin
    fd = $fopen("v.txt", "r");
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%s %d %d", name, a, b);
      if (n == 3) begin #1; $display("RESULT %0s %0d", name, y); end
    end
    $display("TBDONE"); $finish;
  end
endmodule
""")
        c = subprocess.run(["iverilog", "-g2012", "-o", os.path.join(tmp, "sim"),
                            tb, out], capture_output=True, text=True, cwd=tmp)
        if c.returncode != 0:
            fail("iverilog compile:\n" + c.stderr)
        r = subprocess.run(["vvp", os.path.join(tmp, "sim"), "-n"],
                           capture_output=True, text=True, cwd=tmp)
        got = {}
        for line in r.stdout.splitlines():
            if line.startswith("RESULT"):
                _, nm, val = line.split()
                got[nm] = int(val)
    if "TBDONE" not in r.stdout or len(got) != len(vecs):
        fail("sim incomplete %d/%d\n%s" % (len(got), len(vecs), r.stderr[-300:]))
    mism = [(nm, x, got[nm]) for nm, _, _, x in vecs if got[nm] != x]
    rand_n = sum(1 for nm, _, _, _ in vecs if nm.startswith("random_"))
    log("gate3 %s: %d/%d bit-exact (incl. %d randomized, seed 20261123)"
        % ("PASS" if not mism else "FAIL", len(vecs) - len(mism), len(vecs), rand_n))
    if mism:
        fail("first mismatches: %r" % mism[:5])

    # gate 4: yosys synth_xilinx clean + stat
    y = subprocess.run(["yosys", "-p", "read_verilog %s; synth_xilinx -family xc7 "
                        "-top dot27_top; stat" % out], capture_output=True, text=True)
    clean = y.returncode == 0 and "ERROR" not in y.stderr
    stat_lines = [l for l in y.stdout.splitlines() if l.strip().startswith(("Number of cells", " $_", "LUT", "CARRY", "FD", "=")) ]
    log("gate4 %s: yosys synth_xilinx %s" % ("PASS" if clean else "FAIL",
        "clean; stat captured" if clean else "dirty"))
    if not clean:
        fail("yosys rc=%d stderr=%s" % (y.returncode, y.stderr[-500:]))

    # ------- streaming layer (var acc / on_clock / en): gates 5 and 6 -------
    sout = os.path.join(OUTDIR, "stream_ternary_mac_top.v")
    with open(sout, "w") as f:
        f.write(emit_stream_verilog(sp))
    log("gate5a PASS: emitted %s (%d bytes)"
        % (os.path.relpath(sout, REPO), os.path.getsize(sout)))

    def wrap32(v):
        return ((v + (1 << 31)) % (1 << 32)) - (1 << 31)

    codes = sorted(sp["codes"].values())
    rng = random.Random(20261124)  # fixed seed: evidence reproducibility
    sv = []          # (a, b, en) applied for exactly one posedge each, in order
    sexp = []        # expected acc after that same edge (32-bit wrap, like i32)
    acc = sp["acc"]["init"]
    for k in range(24):
        L = rng.randint(1, 20)
        idle_head = rng.randint(1, 3)
        for _ in range(idle_head):           # en=0 cycles: acc must hold
            sv.append((0, 0, 0)); sexp.append(acc)
        for _ in range(L):
            a = b = 0
            for i in sp["positions"]:
                a |= rng.choice(codes) << (i << (sp["bits_per_trit"] - 1))
                b |= rng.choice(codes) << (i << (sp["bits_per_trit"] - 1))
            acc = wrap32(acc + golden_dot27(sp, a, b))
            sv.append((a, b, 1)); sexp.append(acc)
        sv.append((0, 0, 0)); sexp.append(acc)   # stream tail: en=0, read time
    with tempfile.TemporaryDirectory() as tmp:
        vf = os.path.join(tmp, "sv.txt")
        with open(vf, "w") as f:
            for step, (a, b, en) in enumerate(sv):
                f.write("%d %d %d %d\n" % (step, a, b, en))
        tb = os.path.join(tmp, "tb_stream.v")
        with open(tb, "w") as f:
            f.write("""
`timescale 1ns/1ps
module tb_stream;
  reg clk = 0; reg en; reg [53:0] a, b;
  wire signed [31:0] acc; integer fd, n, stepno;
  stream_ternary_mac_top dut(.clk(clk), .en(en), .a(a), .b(b), .acc(acc));
  always #5 clk = ~clk;
  initial begin
    fd = $fopen("sv.txt", "r");
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%d %d %d %d", stepno, a, b, en);
      if (n == 4) begin
        @(posedge clk); #1;
        $display("STREAMRESULT %0d %0d", stepno, acc);
      end
    end
    $display("STREAMDONE"); $finish;
  end
endmodule
""")
        c = subprocess.run(["iverilog", "-g2012", "-o", os.path.join(tmp, "sims"),
                            tb, sout, out], capture_output=True, text=True, cwd=tmp)
        if c.returncode != 0:
            fail("iverilog stream compile:\n" + c.stderr)
        r = subprocess.run(["vvp", os.path.join(tmp, "sims"), "-n"],
                           capture_output=True, text=True, cwd=tmp)
        got = {}
        for line in r.stdout.splitlines():
            if line.startswith("STREAMRESULT"):
                _, st, val = line.split()
                got[int(st)] = int(val)
    if "STREAMDONE" not in r.stdout or len(got) != len(sv):
        fail("stream sim incomplete %d/%d\n%s" % (len(got), len(sv), r.stderr[-300:]))
    smism = [(st, sexp[st], got[st]) for st in range(len(sv)) if got[st] != sexp[st]]
    n_en0 = sum(1 for _, _, en in sv if en == 0)
    log("gate5 %s: %d/%d bit-exact stream cycles (24 streams, en=0 holds: %d cycles)"
        % ("PASS" if not smism else "FAIL", len(sv) - len(smism), len(sv), n_en0))
    if smism:
        fail("first stream mismatches: %r" % smism[:5])

    # gate 6: yosys synth_xilinx clean on the streaming wrapper (both files)
    y2 = subprocess.run(["yosys", "-p", "read_verilog %s %s; synth_xilinx -family "
                         "xc7 -top stream_ternary_mac_top; stat" % (sout, out)],
                        capture_output=True, text=True)
    clean2 = y2.returncode == 0 and "ERROR" not in y2.stderr
    log("gate6 %s: yosys synth_xilinx %s" % ("PASS" if clean2 else "FAIL",
        "clean; stat captured" if clean2 else "dirty"))
    if not clean2:
        fail("yosys stream rc=%d stderr=%s" % (y2.returncode, y2.stderr[-500:]))

    # ------- combinational layer (comb spec): gates 7, 8, 9 -------
    csp = parse_comb_spec()
    csp["__mask"] = (1 << csp["bits_per_trit"]) - 1
    log("comb parsed: codes=%s positions=%d bits/trit=%d result=i%d spec_tests=%d"
        % (csp["codes"], len(csp["positions"]), csp["bits_per_trit"],
           csp["result_bits"], len(csp["tests"])))

    # gate 7: comb golden (pure comb-spec text) must satisfy the comb spec tests
    for a, b, x in csp["tests"]:
        g = golden_dot27(csp, a, b)
        if g != x:
            fail("comb spec test on_comb(%d,%d): golden %d != spec %d" % (a, b, g, x))
    log("gate7 PASS: comb golden satisfies all %d spec-embedded tests"
        % len(csp["tests"]))

    # gate 8: emit + bit-exact sim (comb spec tests + edges + 60 randomized)
    cout = os.path.join(OUTDIR, "comb_ternary_dot_top.v")
    with open(cout, "w") as f:
        f.write(emit_comb_verilog(csp))
    log("gate8a PASS: emitted %s (%d bytes)"
        % (os.path.relpath(cout, REPO), os.path.getsize(cout)))
    cvecs = build_comb_vectors(csp)
    with tempfile.TemporaryDirectory() as ctmp:
        vf = os.path.join(ctmp, "cv.txt")
        with open(vf, "w") as f:
            for name, a, b, _ in cvecs:
                f.write("%s %d %d\n" % (name, a, b))
        tb = os.path.join(ctmp, "tb_comb.v")
        with open(tb, "w") as f:
            f.write("""
`timescale 1ns/1ps
module tb_comb;
  reg [53:0] a, b; wire signed [7:0] result; integer fd, n; reg [1023:0] name;
  comb_ternary_dot_top dut(.a(a), .b(b), .result(result));
  initial begin
    fd = $fopen("cv.txt", "r");
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%s %d %d", name, a, b);
      if (n == 3) begin #1; $display("COMBRESULT %0s %0d", name, result); end
    end
    $display("COMBDONE"); $finish;
  end
endmodule
""")
        c = subprocess.run(["iverilog", "-g2012", "-o", os.path.join(ctmp, "simc"),
                            tb, cout], capture_output=True, text=True, cwd=ctmp)
        if c.returncode != 0:
            fail("iverilog comb compile:\n" + c.stderr)
        r3 = subprocess.run(["vvp", os.path.join(ctmp, "simc"), "-n"],
                            capture_output=True, text=True, cwd=ctmp)
        cg = {}
        for line in r3.stdout.splitlines():
            if line.startswith("COMBRESULT"):
                _, nm, val = line.split()
                cg[nm] = int(val)
    if "COMBDONE" not in r3.stdout or len(cg) != len(cvecs):
        fail("comb sim incomplete %d/%d\n%s"
             % (len(cg), len(cvecs), r3.stderr[-300:]))
    cmism = [(nm, x, cg[nm]) for nm, _, _, x in cvecs if cg[nm] != x]
    crand_n = sum(1 for nm, _, _, _ in cvecs if nm.startswith("crandom_"))
    log("gate8 %s: %d/%d bit-exact comb vectors (incl. %d randomized, seed 20261125)"
        % ("PASS" if not cmism else "FAIL", len(cvecs) - len(cmism),
           len(cvecs), crand_n))
    if cmism:
        fail("first comb mismatches: %r" % cmism[:5])

    # gate 9: yosys synth_xilinx clean on the comb top
    y3 = subprocess.run(["yosys", "-p", "read_verilog %s; synth_xilinx -family xc7 "
                         "-top comb_ternary_dot_top; stat" % cout],
                        capture_output=True, text=True)
    clean3 = y3.returncode == 0 and "ERROR" not in y3.stderr
    log("gate9 %s: yosys synth_xilinx %s" % ("PASS" if clean3 else "FAIL",
        "clean; stat captured" if clean3 else "dirty"))
    if not clean3:
        fail("yosys comb rc=%d stderr=%s" % (y3.returncode, y3.stderr[-500:]))

    write_evidence(True, {"vectors_total": len(vecs), "randomized": rand_n,
                          "mismatches": 0,
                          # store only the deterministic stat blocks; yosys appends a
                          # wall-clock tail ("Logfile hash ... time ...s, MEM ... MB")
                          # after "End of script." that differs run to run and would
                          # break byte-identical regeneration (caught by G5 drift gate)
                          "yosys_stat": _det_stat(y.stdout),
                          "stream": {"cycles_total": len(sv), "streams": 24,
                                     "en0_hold_cycles": n_en0, "mismatches": 0,
                                     "seed": 20261124,
                                     "yosys_stat": _det_stat(y2.stdout,
                                                             "stream_ternary_mac_top")},
                          "comb": {"spec": os.path.relpath(COMB_SPEC, REPO),
                                   "spec_sha256": COMB_SPEC_SHA,
                                   "vectors_total": len(cvecs),
                                   "randomized": crand_n, "mismatches": 0,
                                   "seed": 20261125,
                                   "yosys_stat": _det_stat(y3.stdout,
                                                           "comb_ternary_dot_top")}})
    log("OVERALL: PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
