#!/usr/bin/env python3
"""Read the 32-bit BSCANE2 USER1 register over the Digilent HS2 and time it.

The register layout of the clock probe is:
  [31:4] 28-bit magic 0xA5A5A5A
  [3]    constant 0
  [2]    constant 1
  [1]    counter bit 28
  [0]    counter bit 0

The magic proves the bits came from the probe design and not from a dead JTAG chain.

TAP sequence: reset -> RTI -> Select-IR-Scan -> shift USER1 (0x02) -> Update-IR ->
RTI -> Select-DR-Scan -> Capture-DR -> Shift-DR -> read 32 bits -> Exit1-DR -> Update-DR.

Usage: read_user1.py [n_readings] [interval_seconds]
"""
import sys, time
sys.path.insert(0, "/Users/playra/t27/tools/jtag")
from mpsse_jtag import Mpsse

MAGIC = 0xA5A5A5A
USER1_IR = 0x02


def shift_ir(m, ir):
    """Shift a 6-bit instruction register value (LSB first) and update it.

    The Xilinx IR is 6 bits wide. The framing is the one cli/dlc10 uses:
    TLR(5) -> RTI -> Select-DR -> Select-IR -> Capture-IR -> Shift-IR,
    then 6 IR bits with the last one exiting on TMS=1, then Update-IR -> RTI.
    """
    m.tms([1, 1, 1, 1, 1])          # Test-Logic-Reset
    m.tms([0, 1, 1, 0, 0])          # RTI, Select-DR, Select-IR, Capture-IR, Shift-IR
    for i in range(6):
        bit = (ir >> i) & 1
        m.tms([1 if i == 5 else 0], tdi_level=bit)
    m.tms([1, 0])                   # Exit1-IR -> Update-IR -> RTI


def read_user1(m):
    # RTI -> Select-DR-Scan, Capture-DR, Shift-DR
    m.tms([0])
    m.tms([1, 0, 0])
    raw = m.shift_dr_read(32)
    m.tms([1, 1, 0])   # Exit1-DR, Update-DR, RTI
    if len(raw) < 4:
        return None
    return int.from_bytes(raw[:4], "little")


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
    m = Mpsse(0)
    try:
        shift_ir(m, USER1_IR)
        rows = []
        for i in range(n):
            t0 = time.time()
            v = read_user1(m)
            t1 = time.time()
            if v is None:
                print(f"  read {i+1}: SHORT")
                continue
            magic = (v >> 4) & 0x0FFFFFFF
            ok = (magic == MAGIC) and ((v >> 2) & 1) == 1 and ((v >> 3) & 1) == 0
            c0 = v & 1
            c28 = (v >> 1) & 1
            rows.append({"t": t1, "v": v, "magic_ok": ok, "bit0": c0, "bit28": c28})
            print(f"  read {i+1}: raw=0x{v:08X} magic={'OK' if magic==MAGIC else 'BAD'} "
                  f"bit0={c0} bit28={c28} t={t1:.6f}")
            time.sleep(interval)
        return rows
    finally:
        m.close()


if __name__ == "__main__":
    main()
