// Clock probe on CFGMCLK: the CONTROL for the ring-oscillator probe.
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

module clock_probe_ctrl (
    output wire led_b13
);

    localparam integer PW = 8;    // prescaler width (divide by 2^8)
    localparam integer CW = 20;   // counter width

    // ---- CFGMCLK: the Artix-7 configuration oscillator ----
    wire cfgmclk;
    STARTUPE2 #(
        .PROG_USR("FALSE"),
        .SIM_CCLK_FREQ(10.0)
    ) startup (
        .CFGCLK(), .CFGMCLK(cfgmclk), .EOS(), .PREQ(),
        .CLK(1'b0), .GSR(1'b0), .GTS(1'b0), .KEYCLEARB(1'b0),
        .PACK(1'b0), .USRCCLKO(1'b0), .USRCCLKTS(1'b0),
        .USRDONEO(1'b1), .USRDONETS(1'b1)
    );

    // ---- TWO-STAGE JOHNSON PRESCALER ----
    //
    // A JOHNSON shift register has ONE level of feedback, so it runs at any clock, and its
    // MSB is a clean square wave. A ripple prescaler does not settle inside 200 MHz's 5 ns
    // cycle, which is why the R4/T4 probe needed this form.
    //
    //   stage 1: 8-bit Johnson -> MSB is a square wave at f/16
    //   stage 2: 8-bit Johnson -> MSB is a square wave at f/256
    //   tick    : one tick per 256 clock edges, taken on its RISING EDGE
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

    // ---- 20-bit counter, one increment per tick ----
    // The ground-truth netlist shows this is a plain binary increment (`cnt <= cnt + 1'b1`)
    // with an ABC-generated adder and no CARRY4; xilinx_dffopt then merges that increment
    // logic into the FFs, which is where the design's 19 LUT4s come from. An explicit
    // flip-flop ripple loop produces a DIFFERENT netlist and was not what was measured.
    reg [CW-1:0] cnt = 0;
    always @(posedge cfgmclk) begin
        tick_q <= tick;
        if (tick_rise)
            cnt <= cnt + 1'b1;
    end

    // The LED is a TAP of an existing counter bit: one output buffer, no extra flip-flop,
    // so the divide chain is identical to the measured R4/T4 design. Its only job is to give
    // the placer a package pin to anchor on.
    assign led_b13 = cnt[0];

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
