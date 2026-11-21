#!/usr/bin/env python3
"""Exact simulation of the shipped RTL.

ternary_mac_synth.v:
  prod  = {+a, -a, 0} where a = signed 8-bit counter[7:0]
  acc_out <= acc_in + prod        (acc_in is an INPUT, not feedback)

Harness modes:
  open   : acc_in = 0               -> acc_out = prod           (no accumulation)
  closed : acc_in = acc_out         -> running accumulator      (acc += prod)
"""
STEPS = 1 << 22

def sim(mode):
    counter = 0
    acc = 0
    peak = 0
    peak_step = 0
    ov = {4: 0, 8: 0, 16: 0, 32: 0}
    for t in range(STEPS):
        a = counter & 0xFF
        if a & 0x80: a -= 256
        wb = counter & 0x3
        w = +1 if wb == 0x1 else (-1 if wb == 0x2 else 0)
        prod = w * a
        if mode == "closed":
            acc = acc + prod
        else:
            acc = prod
        if abs(acc) > peak:
            peak = abs(acc); peak_step = t
        for bits in ov:
            lim = (1 << (bits - 1)) - 1
            if acc > lim or acc < -lim - 1:
                ov[bits] += 1
        counter = (counter + 1) & 0x7FFFFF
    return peak, peak_step, ov

for mode in ("open", "closed"):
    peak, ps, ov = sim(mode)
    print(f"=== mode={mode} ===")
    print(f"  peak |acc| = {peak}  (step {ps})")
    for bits in (4, 8, 16, 32):
        lim = (1 << (bits - 1)) - 1
        ok = "SUFFICIENT" if ov[bits] == 0 else f"INSUFFICIENT ({ov[bits]} overflow steps)"
        print(f"  {bits:2d}-bit signed (max {lim:>10}): {ok}")
    print()
