// TOKEN-RATE PROBE: the first throughput measurement on a design with a running clock.
//
// The board's clocks are MEASURED: CFGMCLK 67.16 MHz and R4/T4 398.3 MHz. This probe runs the
// VERIFIED token-sequential attention architecture and counts completed tokens, so tokens per
// second is measured on silicon rather than derived.
//
// It is the adopted ARCHITECTURE at HEAD_DIM=2, KV_LEN=16. HEAD_DIM=2 is chosen because the
// corrected resource measurement puts HEAD_DIM=8 at a cost that no longer fits the 10% cap with
// a register cache, while HEAD_DIM=2 fits comfortably in every cache implementation. The cycle
// structure of the architecture depends on KV_LEN, not on HEAD_DIM, so KV_LEN=16 - the adopted
// value - is kept.
//
// The counter increments on `done`, so one count is one completed attention token.
//
// Readback register (32 bits):
//   [31:20] 12-bit magic 0xA5A - proves the bits below came from this design
//   [19:0]  20-bit completed-token counter
//
// The LED on B13 is a TAP of the token counter's LSB: one output buffer, no extra flip-flop.
// Its job is to give the placer a package pin to anchor on - without one, nextpnr scatters the
// BSCANE2 shift register and the design does not route.

module token_rate_probe (
    input  wire clk200_p,
    input  wire clk200_n,
    output wire led_b13
);

    localparam integer HD = 2;
    localparam integer KV = 16;

    // ---- the AX7203's R4/T4 differential oscillator, MEASURED at 398.3 MHz ----
    wire clk200;
    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IOSTANDARD("DIFF_SSTL15")
    ) clk200_buf (
        .I(clk200_p), .IB(clk200_n), .O(clk200)
    );

    wire signed [HD*16-1:0] attn_out;
    wire [$clog2(KV+1)-1:0] kv_count;
    wire done;

    // deterministic stimulus
    reg [22:0] stim = 0;
    always @(posedge clk200) stim <= stim + 1;

    wire signed [HD*8-1:0] q;
    assign q = stim[HD*8-1:0] ^ (8'h11 * HD);
    wire [HD*2-1:0] w_code;
    assign w_code = stim[2] ? 2'b01 : 2'b10;
    // The KV write depends on the attention OUTPUT, so the whole data path is live. Without
    // this, synthesis prunes the arithmetic AND the cache, and the probe would measure only
    // the control machine, not the attention.
    wire signed [HD*8-1:0] k_new = q ^ {7'b0, attn_out[0]};
    wire signed [HD*8-1:0] v_new = q ^ {7'b0, attn_out[0]};

    attn_token #(
        .HEAD_DIM(HD), .KV_LEN(KV), .QUANT_W(8), .ACT_BITS(8)
    ) u_attn (
        .clk(clk200), .rst_n(1'b1), .en(1'b1),
        .q(q), .w_code(w_code), .k_new(k_new), .v_new(v_new), .kv_write(1'b1),
        .attn_out(attn_out), .kv_count(kv_count), .done(done)
    );

    // ---- token counter: one count per completed attention token ----
    reg [19:0] tok_count = 0;
    always @(posedge clk200) begin
        if (done)
            tok_count <= tok_count + 1'b1;
    end

    // The LED carries the ATTENTION'S OUTPUT as well as the token counter's LSB. That is not
    // cosmetic: the token counter counts `done`, which depends only on the control machine,
    // so if the LED showed only the counter the attention's data path would be UNOBSERVABLE
    // and synthesis would prune the arithmetic and the cache away - the probe would look
    // absurdly small and would measure nothing. Making the output observable keeps it alive.
    assign led_b13 = attn_out[0] ^ tok_count[0];

    // ---- JTAG USER1 readback ----
    wire drck, sel, shift, capture, tdi, tdo;
    BSCANE2 #(.JTAG_CHAIN(1)) bscan (
        .CAPTURE(capture), .DRCK(drck), .RESET(), .RUNTEST(),
        .SEL(sel), .SHIFT(shift), .TCK(), .TDI(tdi), .TMS(), .UPDATE(), .TDO(tdo)
    );

    reg [31:0] sr = 32'hA5A00000;
    always @(posedge drck) begin
        if (sel) begin
            if (capture)    sr <= {12'hA5A, tok_count};
            else if (shift) sr <= {tdi, sr[31:1]};
        end
    end
    assign tdo = sr[0];

endmodule
