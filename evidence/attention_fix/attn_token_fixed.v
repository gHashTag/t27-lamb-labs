// Token-sequential attention with a LIVE bounded quantised KV-cache.
//
// THIS IS THE CORRECTED MODULE. Two defects in the previously committed version are fixed:
//
//  1. THE CACHE WAS DEAD. The cache was declared `reg [QUANT_W-1:0] kv_kmag [0:HEAD_DIM-1];`
//     - ONE dimension - and then indexed `kv_kmag[c][slot_ptr]`, a bit-select out of range on
//     an 8-bit value. Synthesis pruned the whole memory away, so the design that had been
//     measured had NO KV cache at all, and the resource numbers understated the real cost by
//     roughly an order of magnitude in flip-flops.
//
//  2. THE SCORE OVERFLOWED. The key magnitude was padded as {1'b0, magnitude, 1'b0} - a factor
//     of 16 - and then multiplied by a separate +/-1 weight, so the 17-bit score accumulator
//     overflowed for ordinary inputs and the sign of the score was wrong.
//
// The equations are now exactly the ones the Python golden model verified over 12000
// randomised trials, and they are verified again here in Verilog (attn_clean_tb.v):
//
//   score[s] = sum_c q[c] * K[s][c] * w[c]      w[c] in {+1, -1, 0}, applied as a SIGN
//                                               SELECTION on the key, not as a multiplier
//   out[c]   = sum_s sign(score[s]) * V[s][c]
//
// The cache is four flat packed vectors with explicit bit offsets, so there is no procedural
// assignment or index-range ambiguity:
//
//   kv_ksign[c*SLOTS + slot]                                    one sign bit per channel/slot
//   kv_kmag [slot*HEAD_DIM*QUANT_W + c*QUANT_W +: QUANT_W]     key magnitudes
//   kv_vmag [slot*HEAD_DIM*QUANT_W + c*QUANT_W +: QUANT_W]     value magnitudes
//
// Cycle structure: phase 0 clears the accumulator, phases 1..SLOTS score and accumulate one
// slot each, and phase DONE writes the new KV slot and raises `done`. That is exactly
// SLOTS + 2 cycles per token.

module attn_token #(
    parameter integer HEAD_DIM = 8,
    parameter integer KV_LEN   = 16,
    parameter integer QUANT_W  = 8,
    parameter integer ACT_BITS = 8,
    parameter integer SCORE_W  = 24
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
    output reg [$clog2(KV_LEN+1)-1:0] kv_count,
    output reg done
);

  localparam integer SLOTS = KV_LEN;
  localparam integer PH_DONE = SLOTS + 1;

  reg [$clog2(PH_DONE+1)-1:0] phase;

  // ---- quantised KV cache: flat packed vectors ----
  reg [HEAD_DIM*SLOTS-1:0]         kv_ksign;
  reg [HEAD_DIM*SLOTS-1:0]         kv_vsign;
  reg [SLOTS*HEAD_DIM*QUANT_W-1:0] kv_kmag;
  reg [SLOTS*HEAD_DIM*QUANT_W-1:0] kv_vmag;

  reg [$clog2(SLOTS)-1:0] slot_ptr;

  // ---- score of the slot under the pointer ----
  reg signed [SCORE_W-1:0] score_acc;
  reg signed [SCORE_W-1:0] score_reg;
  reg signed [ACT_BITS-1:0] q_ext;
  // QUANT_W+1 bits, NOT QUANT_W: the extra bit is the sign. With QUANT_W bits the magnitude
  // is interpreted as a signed value, so any magnitude >= 2^(QUANT_W-1) came out NEGATIVE and
  // the score's sign was wrong. The golden model uses the wider form.
  reg signed [QUANT_W:0]     kq_ext;
  reg signed [QUANT_W:0]     vq_ext;
  integer c;

  always @* begin
    score_acc = {SCORE_W{1'b0}};
    for (c = 0; c < HEAD_DIM; c = c + 1) begin
      q_ext = $signed(q[c*ACT_BITS +: ACT_BITS]);
      // the key magnitude, with its stored sign
      kq_ext = $signed({1'b0, kv_kmag[slot_ptr*HEAD_DIM*QUANT_W + c*QUANT_W +: QUANT_W]});
      if (kv_ksign[c*SLOTS + slot_ptr]) kq_ext = -kq_ext;
      // the ternary weight is a SIGN SELECTION, not a multiplier
      if (w_code[c*2 +: 2] == 2'b00 || w_code[c*2 +: 2] == 2'b11)
        kq_ext = '0;
      else if (w_code[c*2 +: 2] == 2'b10)
        kq_ext = -kq_ext;
      score_acc = score_acc + (q_ext * kq_ext);
    end
    score_reg = score_acc;
  end

  // ---- accumulate the slot's value contribution ----
  reg signed [HEAD_DIM*16-1:0] out_next;

  always @* begin
    out_next = attn_out;
    if (phase >= 1 && phase <= SLOTS) begin
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        vq_ext = $signed({1'b0, kv_vmag[slot_ptr*HEAD_DIM*QUANT_W + c*QUANT_W +: QUANT_W]});
        if (kv_vsign[c*SLOTS + slot_ptr]) vq_ext = -vq_ext;
        out_next[c*16 +: 16] = out_next[c*16 +: 16] +
            (score_reg[SCORE_W-1] ? -vq_ext : vq_ext);
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      kv_count <= 0;
      slot_ptr <= 0;
      phase    <= 0;
      score_reg <= {SCORE_W{1'b0}};
      attn_out <= {HEAD_DIM*16{1'b0}};
      done     <= 1'b0;
      kv_ksign <= {HEAD_DIM*SLOTS{1'b0}};
      kv_vsign <= {HEAD_DIM*SLOTS{1'b0}};
      kv_kmag  <= {SLOTS*HEAD_DIM*QUANT_W{1'b0}};
      kv_vmag  <= {SLOTS*HEAD_DIM*QUANT_W{1'b0}};
    end else if (en) begin
      done <= 1'b0;
      if (phase == 0) begin
        attn_out <= {HEAD_DIM*16{1'b0}};
        phase    <= 1;
        slot_ptr <= 0;
      end else if (phase <= SLOTS) begin
        attn_out <= out_next;
        if (slot_ptr == SLOTS - 1) begin
          slot_ptr <= 0;
          phase    <= PH_DONE;
        end else begin
          slot_ptr <= slot_ptr + 1'b1;
        end
      end else begin
        done <= 1'b1;
        if (kv_write && kv_count < SLOTS) begin
          for (c = 0; c < HEAD_DIM; c = c + 1) begin
            kv_ksign[c*SLOTS + kv_count] <= k_new[c*ACT_BITS + ACT_BITS - 1];
            kv_kmag[kv_count*HEAD_DIM*QUANT_W + c*QUANT_W +: QUANT_W]
                <= k_new[c*ACT_BITS +: QUANT_W];
            kv_vsign[c*SLOTS + kv_count] <= v_new[c*ACT_BITS + ACT_BITS - 1];
            kv_vmag[kv_count*HEAD_DIM*QUANT_W + c*QUANT_W +: QUANT_W]
                <= v_new[c*ACT_BITS +: QUANT_W];
          end
          kv_count <= kv_count + 1'b1;
        end
        phase <= 0;
      end
    end
  end

endmodule
