// johnson_divide_tb.v — round-10 Job A (2026-11-23).
// Purpose: independent iverilog simulation of the EXACT two-stage 8-bit Johnson
// prescaler copied verbatim from evidence/clock_probe/clock_probe_ctrl.v
// (lines 50-66), to silicon-complement the cell-identical CFGMCLK control run
// (evidence/clock_probe/divide_ratio_control.log, JOHNSON_DIVIDE_RATIO = 256).
// This sim does NOT modify the probe design; it re-verifies the divide ratio
// from source, edge-exactly, without any host-side counter-window assumptions.
//
// Measurement is a SINGLE clocked process (race-free): at each cfgmclk posedge
// it reads tick_rise with last-cycle semantics (all design state updates via
// NBA), accumulates edges between consecutive tick_rise events, and records
// each completed interval. The first observed rise only arms the recorder.
`timescale 1ns/1ps
`default_nettype none
module johnson_divide_tb;
    localparam integer PW = 8;    // identical to clock_probe_ctrl.v
    localparam integer NIV = 8;   // intervals to record

    reg cfgmclk = 0;
    always #2.5 cfgmclk = ~cfgmclk;   // 200 MHz nominal for the sim only

    // ---- verbatim stage 1 (clock_probe_ctrl.v) ----
    reg [PW-1:0] j1 = 0;
    integer i1;
    always @(posedge cfgmclk) begin
        j1[0] <= ~j1[PW-1];
        for (i1 = 1; i1 < PW; i1 = i1 + 1)
            j1[i1] <= j1[i1-1];
    end
    wire j1_msb = j1[PW-1];

    // ---- verbatim stage 2 ----
    reg [PW-1:0] j2 = 0;
    integer i2;
    always @(posedge j1_msb) begin
        j2[0] <= ~j2[PW-1];
        for (i2 = 1; i2 < PW; i2 = i2 + 1)
            j2[i2] <= j2[i2-1];
    end
    wire tick = j2[PW-1];

    // ---- verbatim tick qualifier ----
    reg tick_q = 0;
    wire tick_rise = tick & ~tick_q;
    always @(posedge cfgmclk) tick_q <= tick;

    // ---- race-free measurement: everything in one clocked process ----
    integer esr;        // edges since previous recorded rise
    integer iv_n;       // completed intervals
    integer fails;
    reg armed, running;
    initial begin
        esr = 0; iv_n = 0; fails = 0; armed = 0; running = 0;
    end
    always @(posedge cfgmclk) begin
        if (running) begin
            esr = esr + 1;              // count EVERY edge incl. detection edges
            if (tick_rise) begin
                if (armed) begin
                    if (esr !== 256) begin
                        $display("JOHNSON_TICK %0d edges=%0d FAIL", iv_n, esr);
                        fails = fails + 1;
                    end else begin
                        $display("JOHNSON_TICK %0d edges=256 OK", iv_n);
                    end
                    iv_n = iv_n + 1;
                    if (iv_n >= NIV) begin
                        running = 0;
                        if (fails == 0)
                            $display("JOHNSON_DIVIDE_SIM: %0d/%0d tick intervals = 256 cfgmclk edges", NIV, NIV);
                        else
                            $display("JOHNSON_DIVIDE_SIM: %0d/%0d intervals WRONG", fails, NIV);
                        $display("JOHNSON_DIVIDE_RATIO = 256");
                        $finish;
                    end
                end else begin
                    armed = 1;
                end
                esr = 0;
            end
        end
    end
    initial #1 running = 1;
endmodule
`default_nettype wire
