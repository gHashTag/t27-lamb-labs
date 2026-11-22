#!/usr/bin/env python3
"""Measure the AX7203's clock frequency from a counter read back over JTAG.

The counter is Gray-coded and prescaled by 2^16 CFGMCLK edges, so one count is
2^16 clock edges. The host decodes Gray to binary, differences consecutive
counts, and divides by the measured wall-clock interval.

Usage: measure_clock.py [n_readings] [interval_seconds] [prescale]
"""
import sys, time, statistics
sys.path.insert(0, "/Users/playra/t27/tools/jtag")
from mpsse_jtag import Mpsse

MAGIC = 0xA5A
CW = 20
PRESCALE = 1 << 8


# The counter is BINARY: the first build used a hand-rolled Gray counter whose
# reflected-Gray update was wrong, and the readback was non-monotonic.


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


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
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
        for a, b in zip(good, good[1:]):
            dt = b["t"] - a["t"]
            dc = (b["count"] - a["count"]) & 0xFFFFF  # modulo the 20-bit counter
            if dc == 0 or dt <= 0:
                continue
            f = dc * PRESCALE / dt
            freqs.append(f)
            print(f"  delta: {dc} counts in {dt*1000:.1f} ms -> {f/1e6:.4f} MHz")
        if not freqs:
            print("NO USABLE DELTAS")
            return 1
        print("--- SUMMARY ---")
        print(f"  CFGMCLK frequency: mean {statistics.mean(freqs)/1e6:.4f} MHz, "
              f"median {statistics.median(freqs)/1e6:.4f} MHz, "
              f"stdev {statistics.stdev(freqs)/1e6:.4f} MHz, n={len(freqs)}")
        print(f"  min {min(freqs)/1e6:.4f} MHz, max {max(freqs)/1e6:.4f} MHz")
        return 0
    finally:
        m.close()


if __name__ == "__main__":
    sys.exit(main())
