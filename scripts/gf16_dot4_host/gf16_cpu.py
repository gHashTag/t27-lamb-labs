#!/usr/bin/env python3
"""gf16_cpu.py -- exact CPU oracle for the gf16_dot4 kernel ABI (M1/M2, CPU-only).

Numeric SSOT: specs/numeric/gf16.t27:172-198 (gf16_decode_to_f32)
Kernel contract: evidence/vertical_stack/HOST_ABI.md + host_abi_vectors.json

Semantics implemented:
  decode(value) = (-1)^S * 2^(E-31) * (1 + M/512), E in 0..62 (no subnormals);
  E==0 && M==0 -> signed zero;  E==63 && M==0 -> +/-Inf;
  E==63 && M!=0 -> canonical NaN (payload divergence documented, NaN-aware compare).
  dot4: acc = +0.0; acc = rn_f32(acc + decode(a_j)*decode(b_j)) for j = 0..3 chained,
  product computed EXACTLY (<=22 significand bits, exponent 2^-62..2^62) then one
  RN-even f32 rounding per fma.rn.f32 step -- identical to hardware FMA.

No CUDA imports, no GPU calls. Pure stdlib. Python >= 3.10.
"""
from __future__ import annotations

import json
import math
import struct
import sys
from fractions import Fraction

PTX_SHA256 = "b9a79404bb5c06095fa1b831ad45f3bf1eef2378b74702bad1615237534d5e51"
CUBIN_SHA256 = "35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc"


# ---------------------------------------------------------------- exact core
def gf16_decode(value: int):
    """SSOT decode -> ('num', Fraction) | ('inf', sign) | ('nan',)."""
    sign = -1 if (value >> 15) & 1 else 1
    exp = (value >> 9) & 0x3F
    mant = value & 0x1FF
    if exp == 63:
        return ("nan",) if mant else ("inf", sign)
    if exp == 0 and mant == 0:
        return ("num", Fraction(0))
    return ("num", Fraction(sign) * (1 + Fraction(mant, 512)) * Fraction(2) ** (exp - 31))


def mul_exact(x, y):
    """IEEE-754 product in exact space (finite GF16 products are exact in f32)."""
    if x[0] == "nan" or y[0] == "nan":
        return ("nan",)
    if x[0] == "inf" and y[0] == "inf":
        return ("inf", x[1] * y[1])
    if x[0] == "inf" or y[0] == "inf":
        inf_side = x if x[0] == "inf" else y
        other = y if x[0] == "inf" else x
        if other[0] == "num" and other[1] == 0:
            return ("nan",)  # 0 * Inf
        return ("inf", inf_side[1])
    return ("num", x[1] * y[1])


def add_exact(x, y):
    if x[0] == "nan" or y[0] == "nan":
        return ("nan",)
    if x[0] == "inf" and y[0] == "inf":
        return ("inf", x[1]) if x[1] == y[1] else ("nan",)
    if x[0] == "inf":
        return x
    if y[0] == "inf":
        return y
    return ("num", x[1] + y[1])


def _round_half_even(fr: Fraction) -> int:
    n, d = fr.numerator, fr.denominator
    q, r = divmod(n, d)
    if r == 0:
        return q
    if r < 0:
        q, r = q - 1, r + d
    twice = 2 * r
    if twice > d or (twice == d and q % 2 == 1):
        q += 1
    return q


def rn_f32(x):
    """Round exact value to binary32 (RN-even, subnormals, overflow) -- stays exact."""
    if x[0] != "num":
        return x
    fr = x[1]
    if fr == 0:
        return x
    sign = -1 if fr < 0 else 1
    fr = abs(fr)
    exp = fr.numerator.bit_length() - fr.denominator.bit_length()
    val = fr / Fraction(2) ** exp
    while val >= 2:
        exp += 1
        val /= 2
    while val < 1:
        exp -= 1
        val *= 2
    if exp > 127:
        return ("inf", sign)
    if exp < -126:  # subnormal
        m = _round_half_even(fr * Fraction(2) ** 149)
        if m == 0:
            return ("num", Fraction(0))
        return ("num", Fraction(sign) * Fraction(m, 2 ** 149))
    m = _round_half_even((val - 1) * 8388608)
    if m >= 8388608:
        m = 0
        exp += 1
    if exp > 127:
        return ("inf", sign)
    return ("num", Fraction(sign) * (1 + Fraction(m, 8388608)) * Fraction(2) ** exp)


def dot4(a_group: bytes, b_group: bytes):
    """Kernel semantics for one 8-byte A group and one 8-byte B group -> f32 state."""
    acc = ("num", Fraction(0))
    for j in range(4):
        va = gf16_decode(int.from_bytes(a_group[2 * j:2 * j + 2], "little"))
        vb = gf16_decode(int.from_bytes(b_group[2 * j:2 * j + 2], "little"))
        acc = rn_f32(add_exact(acc, mul_exact(va, vb)))  # fma.rn.f32
    return acc


def state_to_bits(st) -> int:
    if st[0] == "nan":
        return 0x7FC00000  # canonical SSOT NaN
    if st[0] == "inf":
        return 0x7F800000 | (0x80000000 if st[1] < 0 else 0)
    fr = st[1]
    sign = 0x80000000 if fr < 0 else 0
    fr = abs(fr)
    if fr == 0:
        return sign  # +0.0 / -0.0 distinguished
    if fr < Fraction(1, 2 ** 126):
        m = _round_half_even(fr * Fraction(2) ** 149)
        return sign | m
    exp = fr.numerator.bit_length() - fr.denominator.bit_length()
    val = fr / Fraction(2) ** exp
    while val >= 2:
        exp += 1
        val /= 2
    while val < 1:
        exp -= 1
        val *= 2
    m = _round_half_even((val - 1) * 8388608)
    if m >= 8388608:
        m = 0
        exp += 1
    return sign | ((exp + 127) << 23) | m


def f32_bits_of_float(x: float) -> int:
    """Bits of a python float interpreted as f32 (used only for expected decoding)."""
    return struct.unpack("<I", struct.pack("<f", x))[0]


# ---------------------------------------------------------------- comparison
def values_match(got_bits: int, want_bits: int) -> bool:
    """NaN-aware, signed-zero-aware f32 comparison per HOST_ABI.md section 5."""
    if got_bits == want_bits:
        return True
    got_nan = (got_bits & 0x7F800000) == 0x7F800000 and (got_bits & 0x007FFFFF) != 0
    want_nan = (want_bits & 0x7F800000) == 0x7F800000 and (want_bits & 0x007FFFFF) != 0
    if got_nan and want_nan:
        return True  # payload divergence tolerated, but must BOTH be NaN
    return False


# ---------------------------------------------------------------- verification
def verify_adopted(vectors_dir: str) -> list[dict]:
    """Reproduce the adopted golden-chain vectors from a.bin/b.bin vs expected.bin."""
    a = open(f"{vectors_dir}/gf16_dot4_a.bin", "rb").read()
    b = open(f"{vectors_dir}/gf16_dot4_b.bin", "rb").read()
    exp = open(f"{vectors_dir}/gf16_dot4_expected.bin", "rb").read()
    assert len(a) == len(b) == 8 * (len(exp) // 4), "adopted bin size contract violated"
    rows = []
    for g in range(len(exp) // 4):
        want = struct.unpack_from("<I", exp, 4 * g)[0]  # expected.bin is LITTLE-ENDIAN f32
        got = state_to_bits(dot4(a[8 * g:8 * g + 8], b[8 * g:8 * g + 8]))
        rows.append({"group": g, "got_bits": f"0x{got:08X}",
                     "want_bits": f"0x{want:08X}", "match": values_match(got, want)})
    return rows


def u16hex_to_bytes(hexstr: str) -> bytes:
    """u16-lane hex ('3e00be00...' = lanes 0x3E00,0xBE00,...) -> raw LE bytes."""
    return b"".join(int(hexstr[4 * j:4 * j + 4], 16).to_bytes(2, "little")
                    for j in range(len(hexstr) // 4))


def verify_spec_golden(doc: dict) -> list[dict]:
    rows = []
    for v in doc.get("spec_golden_vectors", []):
        a = u16hex_to_bytes(v["a_u16_hex"])
        b = u16hex_to_bytes(v["b_u16_hex"])
        want = int(v["expected_f32_bits_hex"], 16)
        got = state_to_bits(dot4(a, b))
        rows.append({"name": v["name"], "got_bits": f"0x{got:08X}",
                     "want_bits": f"0x{want:08X}", "match": values_match(got, want)})
    return rows


def main() -> int:
    vectors_dir = sys.argv[1] if len(sys.argv) > 1 else "evidence/vertical_stack/vectors"
    doc_path = sys.argv[2] if len(sys.argv) > 2 else "evidence/vertical_stack/host_abi_vectors.json"
    with open(doc_path) as f:
        doc = json.load(f)

    print(f"oracle=gf16_cpu.py (exact Fraction core, RN-even f32, chained fma)")
    print(f"kernel entry={doc['kernel']['entry']} cubin={doc['kernel']['cubin_sha256'][:16]}...")

    adopted = verify_adopted(vectors_dir)
    spec = verify_spec_golden(doc)

    print(f"adopted golden-chain groups: {sum(r['match'] for r in adopted)}/{len(adopted)}")
    for r in adopted:
        print(f"  g{r['group']}: got {r['got_bits']} want {r['want_bits']} "
              f"{'OK' if r['match'] else 'MISMATCH'}")
    print(f"spec golden vectors: {sum(r['match'] for r in spec)}/{len(spec)}")
    for r in spec:
        print(f"  {r['name']}: got {r['got_bits']} want {r['want_bits']} "
              f"{'OK' if r['match'] else 'MISMATCH'}")

    total = len(adopted) + len(spec)
    ok = sum(r["match"] for r in adopted) + sum(r["match"] for r in spec)
    verdict = "PASS" if ok == total else "FAIL"
    print(f"VERDICT: {verdict} ({ok}/{total} bit-exact, CPU-only, no CUDA initialized)")
    return 0 if ok == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
