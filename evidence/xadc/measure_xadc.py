#!/usr/bin/env python3
"""Measure die temperature and rail voltages from the AX7203's XADC over JTAG.

openFPGALoader's --read-xadc emits JSON with a trailing comma, which is not valid JSON,
so the fields are read with a regex instead.

Usage: measure_xadc.py <label> <n_readings> [busdev]
Prints one line per reading and a summary; writes the summary as JSON to stdout's
last block for the caller to capture.
"""
import json, re, subprocess, sys, time, statistics

OPENFPGALOADER = "/opt/homebrew/bin/openFPGALoader"
FIELDS = ("temp", "maxtemp", "mintemp", "vccint", "maxvccint", "minvccint",
          "vccaux", "maxvccaux", "minvccaux")

def read_once(busdev):
    out = subprocess.run(
        [OPENFPGALOADER, "-c", "digilent_hs2", "--busdev-num", busdev, "--read-xadc"],
        capture_output=True, text=True).stdout
    d = {}
    for f in FIELDS:
        m = re.search(r'"%s"\s*:\s*([0-9.eE+-]+)' % f, out)
        if m:
            d[f] = float(m.group(1))
    return d, out

def main():
    label = sys.argv[1] if len(sys.argv) > 1 else "run"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    busdev = sys.argv[3] if len(sys.argv) > 3 else "1:3"

    rows = []
    for i in range(n):
        d, raw = read_once(busdev)
        if "temp" not in d:
            print(f"READING {i+1} FAILED: no XADC data", file=sys.stderr)
            print(raw[:400], file=sys.stderr)
            continue
        d["reading"] = i + 1
        d["unix_time"] = round(time.time(), 3)
        rows.append(d)
        print(f"  [{label}] reading {i+1}/{n}: temp={d['temp']:.3f} C  "
              f"vccint={d['vccint']:.6f} V  vccaux={d['vccaux']:.6f} V")
        time.sleep(2)

    if not rows:
        print("NO READINGS", file=sys.stderr)
        return 1

    temps = [r["temp"] for r in rows]
    summary = {
        "label": label,
        "busdev": busdev,
        "n_readings": len(rows),
        "interval_seconds": 2,
        "temp_c": {
            "mean": round(statistics.mean(temps), 4),
            "median": round(statistics.median(temps), 4),
            "stdev": round(statistics.stdev(temps), 4) if len(temps) > 1 else 0.0,
            "min": round(min(temps), 4),
            "max": round(max(temps), 4),
            "xadc_internal_max": rows[-1].get("maxtemp"),
            "xadc_internal_min": rows[-1].get("mintemp"),
        },
        "vccint_v": {
            "mean": round(statistics.mean([r["vccint"] for r in rows]), 6),
            "min": round(min(r["vccint"] for r in rows), 6),
            "max": round(max(r["vccint"] for r in rows), 6),
        },
        "vccaux_v": {
            "mean": round(statistics.mean([r["vccaux"] for r in rows]), 6),
            "min": round(min(r["vccaux"] for r in rows), 6),
            "max": round(max(r["vccaux"] for r in rows), 6),
        },
        "readings": rows,
    }
    print("--- SUMMARY ---")
    print(json.dumps(summary, indent=2))
    return 0

if __name__ == "__main__":
    sys.exit(main())
