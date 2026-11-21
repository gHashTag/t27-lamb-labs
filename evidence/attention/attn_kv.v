// Minimal single-head attention with a bounded, QUANTISED KV-cache.
//
//   score[s] = sum_c  q[c] * K[s][c]                    (integer, exact)
//   out[c]   = sum_s  sign(score[s]) * V[s][c]           (binary sign selection)
//
// K and V are stored per slot as sign + magnitude (QUANT_W magnitude bits), i.e. the
// cache is QUANTISED. The whole cache is ON-CHIP registers -> external DRAM reads per
// token = 0.
//
// HEAD_DIM : key/value channels
// KV_LEN   : bounded number of cached slots
// QUANT_W  : magnitude bits per cached value (1..8); sign is stored separately

module attn_kv #(
    parameter integer HEAD_DIM = 8,
    parameter integer KV_LEN   = 16,
    parameter integer QUANT_W  = 8
) (
    input  wire clk,
    input  wire rst_n,
    input  wire en,
    input  wire signed [HEAD_DIM*8-1:0] q,      // query activations
    input  wire [HEAD_DIM*2-1:0] w_code,         // ternary codes applied to the KEY
    input  wire signed [HEAD_DIM*8-1:0] k_new,    // new key vector
    input  wire signed [HEAD_DIM*8-1:0] v_new,    // new value vector
    input  wire kv_write,
    output reg signed [HEAD_DIM*16-1:0] attn_out,
    output reg [$clog2(KV_LEN+1)-1:0] kv_count
);

  localparam integer SLOTS = KV_LEN;

  // ---- quantised KV cache: sign bit + magnitude per channel per slot ----
  reg [SLOTS-1:0]           kv_ksign [0:HEAD_DIM-1];
  reg [SLOTS-1:0]           kv_vsign [0:HEAD_DIM-1];
  reg [QUANT_W-1:0]         kv_kmag  [0:HEAD_DIM-1];
  reg [QUANT_W-1:0]         kv_vmag  [0:HEAD_DIM-1];

  integer s, c;

  // ---- score[slot] = sum_c q[c] * decode(K[slot][c]) ----
  reg signed [16:0] score   [0:SLOTS-1];
  reg signed [16:0] score_acc;
  reg signed [16:0] q_ext;
  reg signed [16:0] kq_ext;
  reg signed [16:0] w_ext;

  always @* begin
    for (s = 0; s < SLOTS; s = s + 1) begin
      score_acc = 17'sd0;
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        q_ext = $signed(q[c*8 +: 8]);
        // key magnitude is QUANT_W bits, sign-extended into the 17-bit datapath
        kq_ext = $signed({1'b0, kv_kmag[c][s], 1'b0});
        if (kv_ksign[c][s]) kq_ext = -kq_ext;
        // the ternary code selects +1 / -1 / 0 applied to the key
        case (w_code[c*2 +: 2])
          2'b01: w_ext =  17'sd1;
          2'b10: w_ext = -17'sd1;
          default: w_ext = 17'sd0;
        endcase
        score_acc = score_acc + (q_ext * (kq_ext * w_ext));
      end
      score[s] = score_acc;
    end
  end

  // ---- out[c] = sum_s sign(score[s]) * V[s][c] ----
  reg signed [HEAD_DIM*16-1:0] out_acc;
  reg signed [16:0] sc_ext;
  reg signed [16:0] vq_ext;

  always @* begin
    out_acc = {HEAD_DIM*16{1'b0}};
    for (s = 0; s < SLOTS; s = s + 1) begin
      sc_ext = score[s];
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        vq_ext = $signed({1'b0, kv_vmag[c][s], 1'b0});
        if (kv_vsign[c][s]) vq_ext = -vq_ext;
        out_acc[c*16 +: 16] = out_acc[c*16 +: 16] +
            (sc_ext[16] ? -vq_ext : vq_ext);
      end
    end
    attn_out = out_acc;
  end

  // ---- sequential: write the quantised KV slot, advance the count ----
  always @(posedge clk) begin
    if (!rst_n) begin
      kv_count <= 0;
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        kv_ksign[c] <= {SLOTS{1'b0}};
        kv_vsign[c] <= {SLOTS{1'b0}};
        kv_kmag[c]  <= {SLOTS{1'b0}};
        kv_vmag[c]  <= {SLOTS{1'b0}};
      end
    end else if (en && kv_write) begin
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        kv_ksign[c][kv_count] <= k_new[c*8+7];
        kv_kmag[c][kv_count]  <= k_new[c*8 +: QUANT_W];
        kv_vsign[c][kv_count] <= v_new[c*8+7];
        kv_vmag[c][kv_count]  <= v_new[c*8 +: QUANT_W];
      end
      if (kv_count < SLOTS) kv_count <= kv_count + 1'b1;
    end
  end

endmodule
