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

module clock_probe_ring (
);

    localparam integer PW = 8;    // prescaler width (divide by 2^8)
    localparam integer CW = 20;   // counter width

    // ---- THE ONLY DIFFERENCE FROM clock_probe_cfg: the clock source ----
    // A 20-stage fabric ring oscillator, the same structure as the shipped
    // ternary_mac_demo_top_200t.bit. Everything else - the prescaler, the ripple
    // counter, the JTAG readback - is identical, so the two designs form a
    // controlled pair.
    wire cfgmclk;
    (* KEEP = "TRUE" *) wire osc;
    (* KEEP = "TRUE" *) wire chain [19:0];
    assign chain[0] = ~chain[19];
    genvar oi;
    generate
        for (oi = 1; oi < 20; oi = oi + 1) begin : inv_chain
            (* KEEP = "TRUE" *) LUT1 #(.INIT(2'b01)) inv (
                .I0(chain[oi-1]), .O(chain[oi]));
        end
    endgenerate
    assign osc = chain[19];
    assign cfgmclk = osc;

    // ---- 8-bit ripple prescaler: its MSB toggles every 2^7 edges ----
    reg [PW-1:0] presc = 0;
    reg pres_carry;
    integer p;
    always @(posedge cfgmclk) begin
        pres_carry = 1'b1;
        for (p = 0; p < PW; p = p + 1) begin
            presc[p] <= presc[p] ^ pres_carry;
            pres_carry = pres_carry & presc[p];
        end
    end

    // The prescaler's MSB is a LEVEL; the tick is its RISING EDGE.
    reg tick_q = 0;
    wire tick_rise = presc[PW-1] & ~tick_q;

    // ---- 20-bit ripple counter, one tick per 2^8 CFGMCLK edges ----
    reg [CW-1:0] cnt = 0;
    reg cnt_carry;
    integer k;
    always @(posedge cfgmclk) begin
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
