#!/usr/bin/env python3
"""Wrap-aware copy of measure_clock.py.

Defect fixed here (found 2026-11-23, session 3): the parent script takes counter
deltas modulo 2^20. At the measured R4/T4 rate (~1.55e6 counts/s through the
/256 Johnson prescaler) the counter wraps every ~0.675 s, so any window longer
than that reports a tiny aliased delta and the summary collapses into MHz noise.

Fix: recover the wrap count k from continuity with the previous window's rate:
true_delta = dc + k * 2^20, k chosen to minimize |rate - prev_rate|.
The FIRST window has no prior, so its k is guessed from the published prior band
(397.6e6/256 counts/s) and EXCLUDED from summary statistics - it is printed,
flagged, and never counted.
Default interval lowered to 0.2 s (window ~0.38 s < 0.8 * wrap period).

Usage: measure_clock_wrap.py [n_readings] [interval_seconds]
       measure_clock_wrap.py --selftest        (offline, no hardware)
"""
import sys, time, statistics

sys.path.insert(0, "/Users/playra/t27/tools/jtag")
from mpsse_jtag import Mpsse

MAGIC = 0xA5A
CW = 20
PRESCALE = 1 << 8
SPAN = 1 << CW


def recover(dc, dt, prev_rate, prior_rate=1553125):
    # prior_rate = published 3-session R4/T4 prior: 397.6e6 / 256 counts/s
    """Return (true_delta, k, flag) for a modulo-2^20 delta.

    flag: 'ok' | 'recovered' | 'first-window-prior-guessed'.
    """
    ks = range(0, 4)
    ref = prev_rate if prev_rate else prior_rate
    best = None
    for k in ks:
        r = (dc + k * SPAN) / dt
        score = abs(r - ref)
        if best is None or score < best[2]:
            best = (k, r, score)
    k, r, _ = best
    if prev_rate is None:
        # first window: k guessed from the published prior band, NOT trustworthy ->
        # the caller must exclude it from summary statistics
        return dc + k * SPAN, k, "first-window-prior-guessed"
    return dc + k * SPAN, k, ("ok" if k == 0 else "recovered")


def shift_ir(m, ir):
    m.tms([1, 1, 1, 1, 1])
    m.tms([0, 1, 1, 0, 0])
    for i in range(6):
        m.tms([1 if i == 5 else 0], tdi_level=(ir >> i) & 1)
    m.tms([1, 0])


def read_raw(m):
    m.tms([0])
    m.tms([1, 0, 0])
    raw = m.shift_dr_read(32)
    m.tms([1, 1, 0])
    if len(raw) < 4:
        return None
    return int.from_bytes(raw[:4], "little")


def selftest():
    """Synthetic 20-bit counter at the measured R4/T4 rate, random long windows."""
    import random
    random.seed(20261123)
    rate = 397.6e6 / PRESCALE  # counts/s, the measured value
    t = 0.0
    cnt = int(rate * 0.3) % SPAN
    prev = None
    rows = []
    for i in range(12):
        dt = random.uniform(0.35, 0.75)  # straddles the 0.675 s wrap period
        t += dt
        cnt = (cnt + int(rate * dt)) % SPAN
        dc = cnt if prev is None else (cnt - prev) % SPAN
        true, k, flag = recover(dc, dt, prev_rate=prev_rate_acc(rows))
        rows.append((dt, dc, true, k, flag))
        prev = cnt
    checked = rows[1:]  # first window is prior-guessed and excluded by design
    bad = [r for r in checked if abs(r[2] / r[0] - rate) / rate > 0.05]
    for dt, dc, true, k, flag in rows:
        print(f"  dt={dt*1000:5.1f} ms dc={dc:7d} k={k} {flag:17s} "
              f"-> {true*PRESCALE/dt/1e6:8.3f} MHz")
    print(f"SELFTEST: {len(checked)-len(bad)}/{len(checked)} windows recovered within 5% "
          f"of {rate*PRESCALE/1e6:.1f} MHz")
    return 0 if not bad else 1


def prev_rate_acc(rows):
    """Previous window's recovered rate, or None for the first window."""
    if not rows:
        return None
    dt, _, true, _, _ = rows[-1]
    return true / dt


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        return selftest()
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 0.2
    m = Mpsse(0)
    try:
        shift_ir(m, 0x02)
        rows = []
        for i in range(n):
            v = read_raw(m)
            t = time.time()
            if v is None:
                print(f"  read {i+1}: SHORT")
                continue
            magic = (v >> 20) & 0xFFF
            cnt = v & 0xFFFFF
            rows.append({"t": t, "raw": v, "magic_ok": magic == MAGIC, "count": cnt})
            print(f"  read {i+1}: raw=0x{v:08X} magic={'OK' if magic==MAGIC else 'BAD'} "
                  f"count={cnt}")
            time.sleep(interval)

        good = [r for r in rows if r["magic_ok"]]
        print(f"--- {len(good)}/{len(rows)} reads carried the magic ---")
        if len(good) < 2:
            print("NOT ENOUGH READS")
            return 1
        freqs = []
        prev_counts_per_s = None  # chains INDEPENDENTLY of summary exclusion
        for a, b in zip(good, good[1:]):
            dt = b["t"] - a["t"]
            dc = (b["count"] - a["count"]) % SPAN
            if dt <= 0:
                continue
            true, k, flag = recover(dc, dt, prev_rate=prev_counts_per_s)
            f = true * PRESCALE / dt  # Hz at the probe clock
            guard = " WRAP-GUARD" if dt * true / SPAN > 0.8 else ""
            print(f"  delta: {dc} counts (+{k} wrap) in {dt*1000:.1f} ms -> "
                  f"{f/1e6:.4f} MHz [{flag}]{guard}")
            prev_counts_per_s = true / dt  # continuity for the NEXT window
            if flag == "first-window-prior-guessed":
                continue  # excluded from summary by design
            freqs.append(f)
        if not freqs:
            print("NO USABLE DELTAS")
            return 1
        print("--- SUMMARY ---")
        print(f"  clock frequency: mean {statistics.mean(freqs)/1e6:.4f} MHz, "
              f"median {statistics.median(freqs)/1e6:.4f} MHz, "
              f"stdev {statistics.stdev(freqs)/1e6:.4f} MHz, n={len(freqs)}")
        print(f"  min {min(freqs)/1e6:.4f} MHz, max {max(freqs)/1e6:.4f} MHz")
        return 0
    finally:
        m.close()


if __name__ == "__main__":
    sys.exit(main())
