// RECONSTRUCTION NOTICE.
//
// This file was reconstructed AFTER the session was interrupted, because the original
// source was lost with /tmp. The reconstruction was re-synthesised and compared against the
// netlist that produced the measured bitstream:
//
//   reconstructed : BSCANE2 1, BUFG 3, FDRE 62, FDSE 6, IBUFDS 1, INV 3, LUT2 40, LUT3 20, LUT4 0
//   built netlist : BSCANE2 1, BUFG 3, FDRE 63, FDSE 6, IBUFDS 1, INV 2, LUT2 21, LUT3 21, LUT4 19
//
// THEY DIFFER. The GROUND TRUTH is the netlist and the bitstream, both of which are in this
// directory; the source here is a faithful IN INTENT (two-stage Johnson prescaler, tick on
// the rising edge, same counter and readback) but it is NOT the file that produced the
// measurement. Do not cite this file as the source of the measured bitstream.
//
// The R4/T4 measurement is NOT PUBLISHED anyway - see r4t4_measurement.log for why.

// Clock probe on the AX7203's 200 MHz differential oscillator (R4/T4).
//
// The ring-oscillator probe returned a FROZEN counter over 20 reads, which says either
// (a) the fabric oscillator does not oscillate, or (b) the readback/counter chain is broken.
// This design is the control: the SAME readback, the SAME counter style, but clocked from
// STARTUPE2.CFGMCLK, the Artix-7 configuration oscillator the parent repository documents
// as the canonical and only working clock on this board family.
//
// If the counter advances here, the readback and the counter are proven good, and the
// ring-oscillator probe's frozen counter is a property of the oscillator.
//
// WHY NO CARRY CHAIN. openXC7's placer kept splitting the counter's CARRY4 chain across
// non-adjacent slices, which made the design unroutable at every seed. The counters here
// are plain flip-flop ripple counters: the increment is a chain of XOR/AND in FF feedback,
// with NO CARRY4 and NO adder. That is affordable because the main counter advances only
// once per prescaler tick, so its feedback path has thousands of clock cycles to settle.
//
// Readback register (32 bits):
//   [31:20] 12-bit magic 0xA5A - proves the bits below came from this design
//   [19:0]  20-bit binary counter

module clock_probe_r4t4 (
    input  wire clk200_p,
    input  wire clk200_n
);

    localparam integer PW = 8;    // prescaler width (divide by 2^8)
    localparam integer CW = 20;   // counter width

    // ---- the AX7203's DIFFERENTIAL OSCILLATOR on R4 (P) / T4 (N) ----
    // DIFF_SSTL15, per fpga/HARDWARE_SSOT.md in the parent repository.
    wire cfgmclk;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IOSTANDARD("DIFF_SSTL15")
    ) clk200_buf (
        .I(clk200_p), .IB(clk200_n), .O(cfgmclk)
    );

    // ---- TWO-STAGE JOHNSON PRESCALER ----
    //
    // A ripple prescaler does not settle inside 200 MHz's 5 ns cycle: the first R4/T4 build
    // used an 8-level ripple and read a FROZEN counter. A carry-chain prescaler was tried and
    // openXC7 split that CARRY4 chain across non-adjacent slices. A JOHNSON SHIFT REGISTER has
    // ONE level of feedback, so it runs at any clock, and its MSB is a clean square wave.
    //
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

    reg tick_q = 0;
    wire tick_rise = tick & ~tick_q;

    // ---- 20-bit ripple counter, one tick per 2^8 CFGMCLK edges ----
    reg [CW-1:0] cnt = 0;
    reg cnt_carry;
    integer k;
    always @(posedge cfgmclk) begin
        // DEFECT (documented 2026-11-23, do NOT rebuild from this file):
        // `presc` is undeclared. iverilog: elaboration error. yosys: implicitly
        // declares a 1-bit wire, out-of-range select -> UNDEF -> tick_rise never
        // true -> counter frozen at 0 (this is the r4t4b.bit C6 failure mode;
        // see remeasure_2026-11-23/ and x_mechanism_sim.v). Correct line is
        // `tick_q <= tick;` (as in clock_probe_ctrl.v). The MEASURED bitstream
        // clock_probe_r4t4.bit (md5 56a2e448) came from the original, lost source.
        tick_q <= presc[PW-1];
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
