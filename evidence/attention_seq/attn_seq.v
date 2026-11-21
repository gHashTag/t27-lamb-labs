// SEQUENTIAL single-head attention with a bounded quantised KV-cache.
//
// One KV slot is scored per cycle, so the combinational depth is HEAD_DIM MAC steps
// instead of SLOTS x HEAD_DIM. The score of slot s is computed when s == slot_ptr,
// latched into score_reg, and used to accumulate that slot's value contribution.
//
// score[s] = sum_c q[c] * K[s][c]                    (integer, exact)
// out[c]  = sum_s sign(score[s]) * V[s][c]
//
// The KV cache is ON-CHIP registers -> external DRAM reads per token = 0.
//
// HEAD_DIM : key/value channels
// KV_LEN   : bounded number of cached slots
// QUANT_W  : magnitude bits per cached value (sign stored separately)
// ACT_BITS : activation width; the cache stores sign + QUANT_W magnitude bits of it

module attn_seq #(
    parameter integer HEAD_DIM = 8,
    parameter integer KV_LEN   = 16,
    parameter integer QUANT_W  = 8,
    parameter integer ACT_BITS = 8
) (
    input  wire clk,
    input  wire rst_n,
    input  wire en,
    input  wire signed [HEAD_DIM*ACT_BITS-1:0] q,
    input  wire [HEAD_DIM*2-1:0] w_code,
    input  wire signed [HEAD_DIM*ACT_BITS-1:0] k_new,
    input  wire signed [HEAD_DIM*ACT_BITS-1:0] v_new,
    input  wire kv_write,
    output reg signed [HEAD_DIM*16-1:0] attn_out,
    output reg [$clog2(KV_LEN+1)-1:0] kv_count
);

  localparam integer SLOTS = KV_LEN;

  // ---- quantised KV cache ----
  reg [SLOTS-1:0]       kv_ksign [0:HEAD_DIM-1];
  reg [SLOTS-1:0]       kv_vsign [0:HEAD_DIM-1];
  reg [QUANT_W-1:0]     kv_kmag  [0:HEAD_DIM-1];
  reg [QUANT_W-1:0]     kv_vmag  [0:HEAD_DIM-1];

  // ---- slot pointer: which slot is being scored this cycle ----
  reg [$clog2(SLOTS)-1:0] slot_ptr;

  // ---- score of the slot currently under the pointer ----
  reg signed [16:0] score_reg;
  reg signed [16:0] score_acc;
  reg signed [16:0] q_ext;
  reg signed [16:0] kq_ext;
  reg signed [16:0] w_ext;

  always @* begin
    score_acc = 17'sd0;
    for (c = 0; c < HEAD_DIM; c = c + 1) begin
      q_ext = $signed(q[c*ACT_BITS +: ACT_BITS]);
      kq_ext = $signed({1'b0, kv_kmag[c][slot_ptr], 1'b0});
      if (kv_ksign[c][slot_ptr]) kq_ext = -kq_ext;
      case (w_code[c*2 +: 2])
        2'b01: w_ext =  17'sd1;
        2'b10: w_ext = -17'sd1;
        default: w_ext = 17'sd0;
      endcase
      score_acc = score_acc + (q_ext * (kq_ext * w_ext));
    end
    score_reg = score_acc;
  end

  // ---- accumulate the current slot's value contribution ----
  integer c;
  reg signed [16:0] vq_ext;
  reg signed [HEAD_DIM*16-1:0] out_next;

  always @* begin
    out_next = attn_out;
    for (c = 0; c < HEAD_DIM; c = c + 1) begin
      vq_ext = $signed({1'b0, kv_vmag[c][slot_ptr], 1'b0});
      if (kv_vsign[c][slot_ptr]) vq_ext = -vq_ext;
      out_next[c*16 +: 16] = out_next[c*16 +: 16] +
          (score_reg[16] ? -vq_ext : vq_ext);
    end
  end

  // ---- sequential control ----
  always @(posedge clk) begin
    if (!rst_n) begin
      kv_count <= 0;
      slot_ptr <= 0;
      score_reg <= 17'sd0;
      attn_out  <= {HEAD_DIM*16{1'b0}};
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        kv_ksign[c] <= {SLOTS{1'b0}};
        kv_vsign[c] <= {SLOTS{1'b0}};
        kv_kmag[c]  <= {SLOTS{1'b0}};
        kv_vmag[c]  <= {SLOTS{1'b0}};
      end
    end else if (en) begin
      attn_out <= out_next;
      // advance the slot pointer; wrap after the last slot
      if (slot_ptr == SLOTS - 1) slot_ptr <= 0;
      else slot_ptr <= slot_ptr + 1'b1;
      // write the new key/value into the slot the pointer just left
      if (kv_write && kv_count < SLOTS) begin
        for (c = 0; c < HEAD_DIM; c = c + 1) begin
          kv_ksign[c][kv_count] <= k_new[c*ACT_BITS + ACT_BITS - 1];
          kv_kmag[c][kv_count]  <= k_new[c*ACT_BITS +: QUANT_W];
          kv_vsign[c][kv_count] <= v_new[c*ACT_BITS + ACT_BITS - 1];
          kv_vmag[c][kv_count]  <= v_new[c*ACT_BITS +: QUANT_W];
        end
        kv_count <= kv_count + 1'b1;
      end
    end
  end

endmodule
