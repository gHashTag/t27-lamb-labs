// SIMULATION-ONLY TESTBENCH for the corrected fork clock_probe_r4t4c_sim.v.
// DO NOT SYNTHESIZE THIS FILE. It contains behavioral stubs for the Xilinx
// primitives IBUFDS and BSCANE2; the stubs model just enough semantics for
// this proof:
//   IBUFDS  -> O = I & ~IB (stimulus keeps IB = ~I, so O follows I);
//   BSCANE2 -> TB pokes SEL/CAPTURE/SHIFT/DRCK/TDI hierarchically and reads
//              the user TDO, modeling a minimal USER1 DR-shift sequence.
//
// What this TB proves (and about what it does NOT):
//   1. end-to-end divide ratio: each of the first 8 tick intervals spans
//      exactly 256 cfgmclk edges through the FULL design (IBUFDS -> two-stage
//      Johnson -> tick detector), not just the prescaler in isolation;
//   2. tick detection fires (the defect fork's tick_rise is stuck at 0);
//   3. the 20-bit counter advances and equals the tick count (no wrap);
//   4. the USER1 readback returns {12'hA5A, cnt} over the shift register,
//      matching the read_user1.py read convention (LSB-first, magic in
//      bits [31:20]).
// It does NOT prove on-silicon behavior: no bitstream exists from this fork;
// the FPGA rebuild is blocked pending owner-approved openXC7 tools.
//
// Single-clock-domain discipline (same as the proven johnson_divide_tb.v):
// ONE process samples pre-edge reg values (inclusive detection edge), so the
// per-tick interval is exactly 256 edges with no fork/join race.

`timescale 1ns/1ps

module tb_r4t4c;

    // ---- 200 MHz-class differential stimulus, freezable ----
    reg stim_run = 1;
    reg clk_p = 0;
    wire clk_n = ~clk_p;
    always #2.5 if (stim_run) clk_p = ~clk_p;   // 5 ns period = 200 MHz

    clock_probe_r4t4c dut(.clk200_p(clk_p), .clk200_n(clk_n));

    // ---- counters, single process, inclusive detection edge ----
    integer edges = 0;
    integer ticks = 0;
    integer last_edges = 0;
    integer interval_edges = 0;
    integer bad_intervals = 0;
    integer reported = 0;

    always @(posedge dut.cfgmclk) begin
        edges = edges + 1;
        if (dut.tick && !dut.tick_q) begin          // pre-edge sample: tick_rise
            ticks = ticks + 1;
            interval_edges = edges - last_edges;    // includes this edge
            last_edges = edges;
            if (ticks >= 2 && ticks <= 9 && reported < 8) begin
                // ticks 2..9 are STEADY STATE. Tick 1 is intentionally excluded:
                // the first interval spans the two-stage Johnson fill-up from
                // cold start (8 j1 edges, then 8 j2 edges = 64 cfgmclk edges),
                // not the /256 steady-state period. Attempt-4 diagnosis measured
                // exactly that: interval 1 = 64 edges, intervals 2..8 all 256.
                reported = reported + 1;
                if (interval_edges !== 256) begin
                    bad_intervals = bad_intervals + 1;
                    $display("R4T4C_INTERVAL %0d edges=%0d FAIL (expected 256)",
                             ticks, interval_edges);
                end else
                    $display("R4T4C_INTERVAL %0d edges=256 OK", ticks);
            end
        end
    end

    // ---- readback exercise after 12 ticks ----
    integer b;
    reg [31:0] rb = 0;
    reg [31:0] expected = 0;
    integer rb_fail = 0;
    integer cnt_fail = 0;

    initial begin
        wait (ticks >= 12);
        #1;
        stim_run = 0;            // freeze CFGMCLK stimulus -> cnt frozen
        #2;

        if (dut.cnt !== ticks[19:0]) begin
            cnt_fail = 1;
            $display("R4T4C_CNT FAIL cnt=%0d ticks=%0d", dut.cnt, ticks);
        end else
            $display("R4T4C_CNT OK cnt=%0d == ticks_seen=%0d (advancing, no wrap)",
                     dut.cnt, ticks);

        expected = {12'hA5A, dut.cnt};
        dut.bscan.c_sel = 1;
        dut.bscan.c_cap = 1; dut.bscan.c_drck = 1; #1; dut.bscan.c_drck = 0; dut.bscan.c_cap = 0; #1;
        for (b = 0; b < 32; b = b + 1) begin
            rb[b] = dut.tdo;     // sr[0] before the shift edge -> LSB-first
            dut.bscan.c_sh = 1; dut.bscan.c_drck = 1; #1; dut.bscan.c_drck = 0; #1;
        end
        dut.bscan.c_sel = 0; dut.bscan.c_sh = 0;

        if (rb !== expected) begin
            rb_fail = 1;
            $display("R4T4C_READBACK FAIL got=0x%08h expected=0x%08h", rb, expected);
        end else
            $display("R4T4C_READBACK OK got=0x%08h == {12'hA5A, cnt} (magic %0d, cnt %0d)",
                     rb, rb[31:20], rb[19:0]);

        if (bad_intervals == 0 && cnt_fail == 0 && rb_fail == 0 && ticks == 12)
            $display("R4T4C_VERDICT PASS ticks=%0d cfgmclk_edges=%0d intervals_256=%0d/8 cnt=%0d readback=OK",
                     ticks, edges, 8 - bad_intervals, dut.cnt);
        else
            $display("R4T4C_VERDICT FAIL ticks=%0d edges=%0d bad_intervals=%0d cnt_fail=%0d rb_fail=%0d",
                     ticks, edges, bad_intervals, cnt_fail, rb_fail);
        $finish;
    end

    // watchdog: frozen-counter designs never reach 12 ticks
    initial begin
        #2000000;   // 2 ms of simulated time; defect fork stays at cnt=0
        $display("R4T4C_VERDICT FAIL watchdog timeout ticks=%0d cnt=%0d (counter frozen?)",
                 ticks, dut.cnt);
        $finish;
    end

endmodule

// ---- SIM-ONLY PRIMITIVE STUBS ----
module IBUFDS #(
    parameter DIFF_TERM = "FALSE",
    parameter IOSTANDARD = "DIFF_SSTL15"
) (
    input I, input IB, output O
);
    assign O = I & ~IB;
endmodule

module BSCANE2 #(parameter JTAG_CHAIN = 1) (
    output reg  CAPTURE,
    output reg  DRCK,
    output wire RESET,
    output wire RUNTEST,
    output reg  SEL,
    output reg  SHIFT,
    output wire TCK,
    output reg  TDI,
    output wire TMS,
    input  wire UPDATE,
    input  wire TDO
);
    // TB drives these INTERNAL regs hierarchically (iverilog forbids
    // procedural writes to port variables through a hierarchical reference);
    // the ports follow them combinationally.
    reg c_sel = 0, c_cap = 0, c_sh = 0, c_drck = 0, c_tdi = 0;
    always @(*) begin
        CAPTURE = c_cap; DRCK = c_drck; SEL = c_sel; SHIFT = c_sh; TDI = c_tdi;
    end
    assign RESET = 0; assign RUNTEST = 0; assign TCK = 0; assign TMS = 0;
endmodule
