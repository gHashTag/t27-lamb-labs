FUNCTIONAL HARDWARE SMOKE — PLAN (stated BEFORE running)
Date: 2026-11-23 (UTC+7)
Board: ALINX AX7203 (XC7A200T-FBG484-2, idcode 0x3636093), Digilent HS2, serial 210512180081
Linked issue: gHashTag/t27-lamb-labs #5 [R5]
Predecessor evidence: evidence/recovery_demo_top/recovery_2026-11-23.log (R8 closed this morning)

ROUTE SELECTION (honest, pre-declared)
--------------------------------------
Route (a) — drive the shipped demo top's (a, w_code, acc_in) and observe acc_out:
  FALSIFIED as unviable by the R8 recovery:
  1. its clock is a fabric ring oscillator, probe-verified DEAD
     (evidence/clock_probe/shipped_bitstream_analysis.log: all 6 FDRE clocked by
     net 'osc'; frozen counter in ring_oscillator probe) -> acc_out never advances;
  2. its LED pins R23/T23 belong to the QMTech Wukong pinout; the AX7203 routes
     those pins elsewhere (its LEDs are B13/C13) -> nothing observable anyway.
  No stimulus plan can resurrect a design with a dead clock and off-board outputs.

Route (b) — rebuild committed ax7203_attn and verify UART @160000:
  BLOCKED on this host: nextpnr-xilinx and xc7frames2bit are not installed
  (recorded in R8 log). A UART smoke requires a NEW bitstream; without PnR tools
  it cannot be produced today. Honest blocker, not a claim of failure.

Route (c) — SELECTED: live-datapath smoke via the ALREADY-BUILT, ALREADY-COMMITTED
  clock probes, read back over BSCANE2 USER1 through the committed HS2 JTAG reader.
  This proves the thing route (a) could never prove: state elements ON THE BOARD,
  clocked by a REAL board clock, ADVANCING — i.e. a functional live datapath, not
  just DONE=1. It also revalidates 2026-11-22 measurements with the board live now.

BITSTREAMS (hash-verified against evidence/clock_probe/ARTIFACT_HASHES.txt just now)
------------------------------------------------------------------------------------
P1: evidence/clock_probe/clock_probe_ctrl.bit   sha256 7a06144e4a3a531d910b5605cc6908e4e6e4d389c0baaa61fdc534551bd6a8ea
    Clock: STARTUPE2.CFGMCLK. Readback (committed clock_probe_ctrl.v header):
    USER1[31:20] = 12-bit magic 0xA5A, [19:0] = 20-bit binary counter,
    one count per 256 CFGMCLK edges. Reader: measure_clock.py layout.
P2: evidence/clock_probe/clock_probe_r4t4b.bit  sha256 1953c59762dca066c5bf5df1268869c5d055581d75ce941e22e6fe28de9f3761
    Clock: AX7203's on-board 200 MHz differential oscillator on R4/T4.
    Readback (committed read_user1.py docstring): USER1[31:4] = magic 0xA5A5A5A,
    [3]=0, [2]=1, [1]=counter bit 28, [0]=counter bit 0. Reader: read_user1.py.

IO: NONE external. Both probes touch no package pin except the R4/T4 differential
input (P2) already characterised by an .xdc committed here. LEDs untouched.
Readback path: JTAG (BSCANE2 USER1) via /Users/playra/t27/tools/jtag/mpsse_jtag.py
over the HS2 — no board pins involved, no flash write anywhere (SRAM only).

PRE-STATED PASS CRITERIA (all must hold; 100%, no partial credit)
-----------------------------------------------------------------
C1  Load: openFPGALoader reports isc_done 1 / done 1 for BOTH probes.
C2  P1 magic: all 10 reads return USER1[31:20] == 0xA5A.
C3  P1 liveness: the 20-bit counter strictly advances across the 10 reads
    (non-decreasing with >= 1 increment per interval; wraps counted as advance).
C4  P1 frequency: implied CFGMCLK in the 55..80 MHz band
    (family nominal ~66 MHz; 2026-11-22 runs measured 66.82/67.16 MHz mean;
    CFGMCLK is PVT-dependent, so today's value must land in-band, not match).
C5  P2 magic: all 10 reads return USER1[31:4] == 0xA5A5A5A, bit[3]==0, bit[2]==1.
C6  P2 liveness: the counter is NOT frozen — bit0 and/or bit28 change value
    across the 10 reads (>= 1 change).
C7  Board health after each load: XADC temp < 60 C, vccint in 0.95..1.05 V.

PRE-STATED FAILURE DISPOSITION
------------------------------
Any failed criterion => the smoke FAILS overall; the log records which criterion,
the raw transcript, and NO partial-credit language. Rerun allowed only with a new
timestamped plan addendum.

COMMANDS (as they will be run)
------------------------------
openFPGALoader -c digilent_hs2 evidence/clock_probe/clock_probe_ctrl.bit
python3 evidence/clock_probe/measure_clock.py 10 0.5        # P1, committed copy
openFPGALoader -c digilent_hs2 evidence/clock_probe/clock_probe_r4t4b.bit
python3 evidence/clock_probe/read_user1.py 10 0.3           # P2, committed copy
openFPGALoader -c digilent_hs2 --read-xadc                  # after each load

NOTE ON READERS: measure_clock.py and read_user1.py are the committed copies in
evidence/clock_probe/; both import the MPSSE JTAG library from the original
working repo (/Users/playra/t27/tools/jtag/mpsse_jtag.py) — dependency recorded,
library unchanged (reads only; no write path to the board).

RESULT LOG: evidence/functional_smoke_2026-11-23/measured_log.txt (after run)
VERDICT:    evidence/functional_smoke_2026-11-23/verdict.txt (after run)
