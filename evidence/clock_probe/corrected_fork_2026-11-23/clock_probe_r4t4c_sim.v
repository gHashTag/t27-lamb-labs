// CORRECTED FORK — SIMULATION ONLY. DO NOT SYNTHESIZE FROM THIS FILE YET.
//
// Status (2026-11-23): simulation evidence only. No bitstream exists from this
// file. Rebuilding an FPGA image requires the openXC7 flow (nextpnr-xilinx,
// fasm2frames.py, xc7frames2bit), which is NOT installed on this host; the
// rebuild is gated on explicit owner approval. Until then:
//   - cite clock_probe_r4t4.bit (md5 56a2e448) for the MEASURED hardware run;
//   - cite THIS file + clock_probe_r4t4c_tb.v + r4t4c_sim_*.log for the
//     corrected-RTL simulation proof only.
//
// Provenance: byte-derived fork of evidence/clock_probe/clock_probe_r4t4.v
// (the post-loss RECONSTRUCTION, which carries the documented inline DEFECT).
// The fork differs from that reconstruction in exactly ONE functional line:
//
//   DEFECT (r4t4.v):  tick_q <= presc[PW-1];   // `presc` undeclared:
//                     yosys implicit 1-bit net, out-of-range select -> UNDEF
//                     -> tick_rise stuck 0 -> counter frozen at 0 == the
//                     observed clock_probe_r4t4b.bit C6 failure mode.
//   FIX   (this file): tick_q <= tick;         // as in the silicon-proven
//                     control design clock_probe_ctrl.v (CFGMCLK probe).
//
// The historical reconstruction evidence/clock_probe/clock_probe_r4t4.v is
// intentionally LEFT UNCHANGED: it documents what was reconstructed after the
// /tmp loss and why the r4t4b bitstream froze. Do not "repair" history.
//
// Everything else — IBUFDS DIFF_SSTL15 input buffer, two-stage 8-bit Johnson
// prescaler (/16 then /16 = /256), 20-bit ripple counter, BSCANE2 USER1
// readback with 12-bit magic 0xA5A — is structurally identical to
// clock_probe_r4t4.v and clock_probe_ctrl.v. WHY NO CARRY4: same as the
// reconstruction header — placer-split carry chains were unroutable in the
// openXC7 flow; the ripple counter settles between 1/256-rate ticks.

module clock_probe_r4t4c (
    input  wire clk200_p,
    input  wire clk200_n
);

    localparam integer PW = 8;    // prescaler width (divide by 2^8)
    localparam integer CW = 20;   // counter width

    // ---- the AX7203's DIFFERENTIAL OSCILLATOR on R4 (P) / T4 (N) ----
    wire cfgmclk;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IOSTANDARD("DIFF_SSTL15")
    ) clk200_buf (
        .I(clk200_p), .IB(clk200_n), .O(cfgmclk)
    );

    // ---- TWO-STAGE JOHNSON PRESCALER ----
    //   stage 1: 8-bit Johnson -> MSB is a square wave at f/16
    //   stage 2: 8-bit Johnson -> MSB is a square wave at f/256
    //   tick    : one tick per 256 oscillator edges, taken on its RISING EDGE
    reg [PW-1:0] j1 = 0;
    integer i1;
    always @(posedge cfgmclk) begin
        j1[0] <= ~j1[PW-1];
        for (i1 = 1; i1 < PW; i1 = i1 + 1)
            j1[i1] <= j1[i1-1];
    end
    wire j1_msb = j1[PW-1];

    reg [PW-1:0] j2 = 0;
    integer i2;
    always @(posedge j1_msb) begin
        j2[0] <= ~j2[PW-1];
        for (i2 = 1; i2 < PW; i2 = i2 + 1)
            j2[i2] <= j2[i2-1];
    end
    wire tick = j2[PW-1];

    // THE FIX (relative to the defect-bearing reconstruction):
    reg tick_q = 0;
    wire tick_rise = tick & ~tick_q;

    // ---- 20-bit ripple counter, one tick per 2^8 CFGMCLK edges ----
    reg [CW-1:0] cnt = 0;
    reg cnt_carry;
    integer k;
    always @(posedge cfgmclk) begin
        tick_q <= tick;   // FIX: was `tick_q <= presc[PW-1];` (undeclared presc)
        if (tick_rise) begin
            cnt_carry = 1'b1;
            for (k = 0; k < CW; k = k + 1) begin
                cnt[k] <= cnt[k] ^ cnt_carry;
                cnt_carry = cnt_carry & cnt[k];
            end
        end
    end

    // ---- JTAG USER1 readback ----
    wire drck, sel, shift, capture, tdi, tdo;
    BSCANE2 #(.JTAG_CHAIN(1)) bscan (
        .CAPTURE(capture), .DRCK(drck), .RESET(), .RUNTEST(),
        .SEL(sel), .SHIFT(shift), .TCK(), .TDI(tdi), .TMS(), .UPDATE(), .TDO(tdo)
    );

    reg [31:0] sr = 32'hA5A00000;
    always @(posedge drck) begin
        if (sel) begin
            if (capture)    sr <= {12'hA5A, cnt};
            else if (shift) sr <= {tdi, sr[31:1]};
        end
    end
    assign tdo = sr[0];

endmodule
