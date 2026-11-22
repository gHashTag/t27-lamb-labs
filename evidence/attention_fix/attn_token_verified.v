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
    parameter integer SCORE_W  = 24,
    parameter integer WORD_W   = QUANT_W + 1
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

  // ---- quantised KV cache ----
  //
  // A flat packed vector with a VARIABLE-OFFSET part-select write is not synthesizable as a
  // register file: yosys drops the write, the cache reads as constant, and the whole memory
  // is pruned from the netlist - while the SIMULATION still passes. The cache must therefore
  // be a MEMORY whose element index is variable and whose part-select inside the element is
  // constant. Each slot is one packed word holding every channel's sign and magnitude:
  //
  //   kv_kword[slot][c*WORD_W + QUANT_W]   the key sign for channel c
  //   kv_kword[slot][c*WORD_W +: QUANT_W]   the key magnitude for channel c
  reg [HEAD_DIM*WORD_W-1:0] kv_kword [0:SLOTS-1];
  reg [HEAD_DIM*WORD_W-1:0] kv_vword [0:SLOTS-1];

  reg [$clog2(SLOTS)-1:0] slot_ptr;

  // ---- score of the slot under the pointer ----
  reg  signed [SCORE_W-1:0] score_acc;
  // score_reg is a COMBINATIONAL wire: it was a reg with both a blocking assignment (in the
  // score block) and a non-blocking assignment (in the reset), which Verilator rejects as
  // BLKANDNBLK. The score needs no register: it is consumed in the same cycle it is produced.
  wire signed [SCORE_W-1:0] score_reg;
  // The cache word is read through a CONTINUOUS assignment: a part-select of a memory
  // element is not portable (Icarus cannot bind it), and a procedural read of a memory
  // element with a variable index is not either.
  wire [HEAD_DIM*WORD_W-1:0] kword_r = kv_kword[slot_ptr];
  wire [HEAD_DIM*WORD_W-1:0] vword_r = kv_vword[slot_ptr];

  reg signed [ACT_BITS-1:0] q_ext;
  // QUANT_W+1 bits, NOT QUANT_W: the extra bit is the sign. With QUANT_W bits the magnitude
  // is interpreted as a signed value, so any magnitude >= 2^(QUANT_W-1) came out NEGATIVE and
  // the score's sign was wrong. The golden model uses the wider form.
  reg signed [QUANT_W:0]     kq_ext;
  reg signed [QUANT_W:0]     vq_ext;
  integer c;

  assign score_reg = score_acc;

  always @* begin
    score_acc = {SCORE_W{1'b0}};
    for (c = 0; c < HEAD_DIM; c = c + 1) begin
      q_ext = $signed(q[c*ACT_BITS +: ACT_BITS]);
      // the key magnitude, with its stored sign
      kq_ext = $signed({1'b0, kword_r[c*WORD_W +: QUANT_W]});
      if (kword_r[c*WORD_W + QUANT_W]) kq_ext = -kq_ext;
      // the ternary weight is a SIGN SELECTION, not a multiplier
      if (w_code[c*2 +: 2] == 2'b00 || w_code[c*2 +: 2] == 2'b11)
        kq_ext = '0;
      else if (w_code[c*2 +: 2] == 2'b10)
        kq_ext = -kq_ext;
      score_acc = score_acc + (q_ext * kq_ext);
    end
  end

  // ---- accumulate the slot's value contribution ----
  reg signed [HEAD_DIM*16-1:0] out_next;

  always @* begin
    out_next = attn_out;
    if (phase >= 1 && phase <= SLOTS) begin
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        vq_ext = $signed({1'b0, vword_r[c*WORD_W +: QUANT_W]});
        if (vword_r[c*WORD_W + QUANT_W]) vq_ext = -vq_ext;
        // The accumulator addition must be SIGNED. A Verilog part-select is always
        // UNSIGNED, so `out_next[c*16 +: 16] + vq_ext` added a negative value
        // contribution as a large unsigned number (e.g. -240 became 272, and eight slots
        // gave 2176 instead of -1920). The $signed cast on the accumulator is what makes
        // the two's-complement arithmetic correct.
        out_next[c*16 +: 16] = $signed(out_next[c*16 +: 16]) +
            (score_reg[SCORE_W-1] ? -vq_ext : vq_ext);
      end
    end
  end

  // The cache memory is cleared by an initial block rather than by rst_n: a procedural write
  // to a memory element with a variable index is not portable, and on Xilinx the registers
  // power up to zero anyway. Synthesis turns this into the memory's INIT value.
  integer s;
  initial begin
    for (s = 0; s < SLOTS; s = s + 1) begin
      kv_kword[s] = {HEAD_DIM*WORD_W{1'b0}};
      kv_vword[s] = {HEAD_DIM*WORD_W{1'b0}};
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      kv_count <= 0;
      slot_ptr <= 0;
      phase    <= 0;
      attn_out <= {HEAD_DIM*16{1'b0}};
      done     <= 1'b0;
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
            kv_kword[kv_count][c*WORD_W +: WORD_W]
                <= {k_new[c*ACT_BITS + ACT_BITS - 1], k_new[c*ACT_BITS +: QUANT_W]};
            kv_vword[kv_count][c*WORD_W +: WORD_W]
                <= {v_new[c*ACT_BITS + ACT_BITS - 1], v_new[c*ACT_BITS +: QUANT_W]};
          end
          kv_count <= kv_count + 1'b1;
        end
        phase <= 0;
      end
    end
  end

endmodule
