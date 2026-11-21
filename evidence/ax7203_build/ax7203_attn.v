// AX7203-native token-sequential attention with a UART timing beacon.
//
// Board facts (fpga/HARDWARE_SSOT.md):
//   200 MHz differential oscillator: R4 (P) / T4 (N), DIFF_SSTL15
//   user LEDs (active low):        B13 C13 D14 D15
//   UART TX:                       N15   (host reads it on the Digilent HS2 serial channel)
//   chipdb:                        xc7a200tfbg484-2
//
// The attention block is the adopted token-sequential form (attn_token.v):
// one KV slot scored per cycle, exact SLOTS + 2 cycles per token, zero DSP, zero BRAM.
//
// A UART transmitter emits ONE byte per `done` pulse. The host timestamps the bytes, so the
// token interval is measured on silicon rather than derived.

module ax7203_attn #(
    parameter integer HEAD_DIM = 8,
    parameter integer KV_LEN   = 16,
    parameter integer QUANT_W  = 8,
    parameter integer ACT_BITS = 8,
    parameter integer BAUD     = 160000
) (
    input  wire clk200_p,
    input  wire clk200_n,
    output wire led0,
    output wire led1,
    output wire uart_tx
);

  // ---- 200 MHz differential clock ----
  wire clk200;
  IBUFDS #(
      .DIFF_TERM("FALSE"),
      .IOSTANDARD("DIFF_SSTL15")
  ) clk200_buf (
      .I(clk200_p), .IB(clk200_n), .O(clk200)
  );

  // ---- deterministic stimulus ----
  reg [22:0] counter = 0;
  always @(posedge clk200) counter <= counter + 1;

  wire signed [HEAD_DIM*ACT_BITS-1:0] q;
  genvar g;
  generate
    for (g = 0; g < HEAD_DIM; g = g + 1) begin : qgen
      assign q[g*ACT_BITS +: ACT_BITS] = counter[ACT_BITS-1:0] ^ (g * 8'h11);
    end
  endgenerate

  wire [HEAD_DIM*2-1:0] w_code;
  generate
    for (g = 0; g < HEAD_DIM; g = g + 1) begin : wgen
      assign w_code[g*2 +: 2] = counter[2+g%3] ? 2'b01 : 2'b10;
    end
  endgenerate

  wire signed [HEAD_DIM*ACT_BITS-1:0] k_new = q;
  wire signed [HEAD_DIM*ACT_BITS-1:0] v_new = q;

  wire signed [HEAD_DIM*16-1:0] attn_out;
  wire [$clog2(KV_LEN+1)-1:0] kv_count;
  wire done;

  attn_token #(
      .HEAD_DIM(HEAD_DIM), .KV_LEN(KV_LEN),
      .QUANT_W(QUANT_W), .ACT_BITS(ACT_BITS)
  ) u_attn (
      .clk(clk200), .rst_n(1'b1), .en(1'b1),
      .q(q), .w_code(w_code), .k_new(k_new), .v_new(v_new), .kv_write(1'b1),
      .attn_out(attn_out), .kv_count(kv_count), .done(done)
  );

  // ---- UART transmitter: one byte per done pulse ----
  // 200 MHz / 160000 baud = 1250 clocks per bit.
  localparam integer CLKS_PER_BIT = 200000000 / BAUD;

  // One counter drives both the bit timing and the bit index: a single counter
  // avoids the multi-driver arc conflict the router reported for two counters.
  localparam integer FRAME_BITS = 11;         // start + 8 data + stop
  reg [15:0] tx_count = 0;
  reg [7:0]  tx_byte  = 8'h55;
  reg        tx_busy  = 1'b0;

  wire [3:0] tx_index = (tx_count / CLKS_PER_BIT);
  wire       tx_bit   = tx_busy
      ? (tx_index == 0)                    ? 1'b0  // start bit
      : (tx_index <= 8)                    ? tx_byte[tx_index - 1]
                                            : 1'b1  // stop bit
      : 1'b1;                                // idle high

  always @(posedge clk200) begin
    if (!tx_busy) begin
      if (done) begin
        tx_busy  <= 1'b1;
        tx_count <= 0;
        tx_byte  <= tx_byte + 1'b1;          // the byte value counts the tokens
      end
    end else if (tx_count == CLKS_PER_BIT * FRAME_BITS - 1) begin
      tx_busy  <= 1'b0;
      tx_count <= 0;
    end else begin
      tx_count <= tx_count + 1'b1;
    end
  end

  assign uart_tx = tx_bit;

  // ---- LEDs (active low) ----
  assign led0 = ~done;
  assign led1 = ~attn_out[0];

endmodule
