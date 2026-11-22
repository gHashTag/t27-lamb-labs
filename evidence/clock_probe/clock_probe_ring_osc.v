// Clock probe: a ring oscillator, a Gray-coded counter, and a JTAG readback.
//
// Purpose: measure the fabric ring oscillator's ACTUAL frequency on the AX7203 and prove
// that it oscillates at all. The parent repository's docs/fpga/clocking.md says the ring
// oscillator does not work in the openXC7 flow; the shipped bitstream's netlist contains a
// CLOSED inverter loop (verified statically), but structural presence is not functional
// oscillation. This design settles it on silicon.
//
// The counter is GRAY-CODED on purpose: a reflected Gray counter advances with pure XOR/AND
// feedback and uses NO carry chain. A binary counter needs a CARRY4 chain, and openXC7's
// placer kept splitting that chain across non-adjacent slices, which made the design
// unroutable. The host decodes Gray to binary.
//
// Readback register (32 bits):
//   [31:4] 28-bit magic 0xA5A5A5A - proves the bits below came from this design
//   [3]    constant 0
//   [2]    constant 1
//   [1]    counter bit 28 (a coarse "is it alive" bit)
//   [0]    counter bit 0
// The reader shifts the 32 bits out twice with a host timestamp and computes the frequency.
//
// LEDs: r23 = oscillator, t23 = counter bit 0.

module clock_probe (
);

    localparam integer CW = 29;   // counter width

    // ---- 20-stage ring oscillator: the same structure as the shipped design ----
    (* KEEP = "TRUE" *) wire osc;
    (* KEEP = "TRUE" *) wire chain [19:0];
    assign chain[0] = ~chain[19];
    genvar i;
    generate
        for (i = 1; i < 20; i = i + 1) begin : inv_chain
            (* KEEP = "TRUE" *) LUT1 #(.INIT(2'b01)) inv (
                .I0(chain[i-1]), .O(chain[i]));
        end
    endgenerate
    assign osc = chain[19];

    // ---- reflected Gray counter: no carry chain anywhere ----
    reg [CW-1:0] gray = 0;
    integer g;
    always @(posedge osc) begin
        gray[0] <= ~gray[0];
        for (g = 1; g < CW; g = g + 1)
            gray[g] <= gray[g] ^ (&gray[g-1:0]);
    end

    // ---- JTAG USER1 readback ----
    wire drck, sel, shift, capture, tdi, tdo;
    BSCANE2 #(.JTAG_CHAIN(1)) bscan (
        .CAPTURE(capture), .DRCK(drck), .RESET(), .RUNTEST(),
        .SEL(sel), .SHIFT(shift), .TCK(), .TDI(tdi), .TMS(), .UPDATE(), .TDO(tdo)
    );

    reg [31:0] sr = 32'hA5A5A5A0;
    always @(posedge drck) begin
        if (sel) begin
            if (capture)    sr <= {28'hA5A5A5A, 1'b0, 1'b1, gray[CW-1], gray[0]};
            else if (shift) sr <= {tdi, sr[31:1]};
        end
    end
    assign tdo = sr[0];

    // The design is deliberately PIN-FREE: BSCANE2 is the readback path that needs no
    // pin, no wire and no pin map, and the parent repository's SSOT records that a
    // pin-free design placed on xc7a200tfbg676 loads and runs on the FBG484 die.

endmodule
