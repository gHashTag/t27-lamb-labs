// TOKEN-SEQUENTIAL single-head attention with a bounded quantised KV-cache.
//
// Adds an explicit per-token control sequence to the sequential form:
//   phase 0          : clear the accumulator (1 cycle)
//   phase 1..SLOTS   : scan one KV slot per cycle, accumulate its contribution
//   phase DONE       : output valid for this cycle, then write the new KV slot
//
// Cycle count per token is therefore EXACT: 1 (clear) + SLOTS (scan) + 1 (write/done)
// = SLOTS + 2 cycles. The `done` pulse marks the cycle the output is valid.
//
// score[s] = sum_c q[c] * K[s][c]                    (integer, exact)
// out[c]   = sum_s sign(score[s]) * V[s][c]
//
// The KV cache is ON-CHIP registers -> external DRAM reads per token = 0.
//
// HEAD_DIM : key/value channels
// KV_LEN   : bounded number of cached slots
// QUANT_W  : magnitude bits per cached value (sign stored separately)
// ACT_BITS : activation width; the cache stores sign + QUANT_W magnitude bits of it

module attn_token #(
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
    output reg [$clog2(KV_LEN+1)-1:0] kv_count,
    output reg done
);

  localparam integer SLOTS = KV_LEN;
  // phase: 0 = clear, 1..SLOTS = scan slot (phase-1), SLOTS+1 = write/done
  localparam integer PH_DONE = SLOTS + 1;

  reg [$clog2(PH_DONE+1)-1:0] phase;

  // ---- quantised KV cache ----
  reg [SLOTS-1:0]                       kv_ksign [0:HEAD_DIM-1];
  reg [SLOTS-1:0]                       kv_vsign [0:HEAD_DIM-1];
  reg [HEAD_DIM*QUANT_W-1:0]            kv_kmag  [0:SLOTS-1];
  reg [HEAD_DIM*QUANT_W-1:0]            kv_vmag  [0:SLOTS-1];

  // ---- slot pointer: which slot is scored this cycle ----
  reg [$clog2(SLOTS)-1:0] slot_ptr;

  // ---- score of the slot under the pointer ----
  reg signed [16:0] score_reg;
  reg signed [16:0] score_acc;
  reg signed [ACT_BITS-1:0] q_ext;       // query activation, ACT_BITS wide
  reg signed [QUANT_W:0]   kq_ext;      // key magnitude + sign, QUANT_W+1 wide
  reg                     k_neg;       // ternary code applied as sign selection
  integer c;
  integer s;

  always @* begin
    score_acc = 17'sd0;
    for (c = 0; c < HEAD_DIM; c = c + 1) begin
      q_ext = $signed(q[c*ACT_BITS +: ACT_BITS]);
      kq_ext = $signed({1'b0, kv_kmag[slot_ptr][c*QUANT_W +: QUANT_W]});
      if (kv_ksign[c][slot_ptr]) kq_ext = -kq_ext;
      // The ternary weight is a sign/zero select, NOT a multiplier: it negates or
      // zeroes the key. This keeps ONE (ACT_BITS x QUANT_W) multiply per channel
      // instead of a 17x17 one, which is what lets the design meet 200 MHz.
      k_neg = (w_code[c*2 +: 2] == 2'b01) ? 1'b0 :
              (w_code[c*2 +: 2] == 2'b10) ? 1'b1 : 1'b0;
      if (w_code[c*2 +: 2] == 2'b00 || w_code[c*2 +: 2] == 2'b11)
        kq_ext = '0;
      else if (k_neg)
        kq_ext = -kq_ext;
      // VARIANT B: score is a constant, so the score chain is removed.
      score_acc = score_acc + q_ext;
    end
    score_reg = score_acc;
  end

  // ---- accumulate the current slot's value contribution ----
  reg signed [QUANT_W:0] vq_ext;
  reg signed [HEAD_DIM*16-1:0] out_next;

  always @* begin
    out_next = attn_out;
    if (phase >= 1 && phase <= SLOTS) begin
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        vq_ext = $signed({1'b0, kv_vmag[slot_ptr][c*QUANT_W +: QUANT_W]});
        if (kv_vsign[c][slot_ptr]) vq_ext = -vq_ext;
        out_next[c*16 +: 16] = out_next[c*16 +: 16] +
            (score_reg[16] ? -vq_ext : vq_ext);
      end
    end
  end

  // ---- sequential control: one token = SLOTS + 2 cycles ----
  always @(posedge clk) begin
    if (!rst_n) begin
      kv_count <= 0;
      slot_ptr  <= 0;
      phase     <= 0;
      score_reg <= 17'sd0;
      attn_out  <= {HEAD_DIM*16{1'b0}};
      done      <= 1'b0;
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        kv_ksign[c] <= {SLOTS{1'b0}};
        kv_vsign[c] <= {SLOTS{1'b0}};
        for (s = 0; s < SLOTS; s = s + 1) begin
          kv_kmag[s] <= {HEAD_DIM*QUANT_W{1'b0}};
          kv_vmag[s] <= {HEAD_DIM*QUANT_W{1'b0}};
        end
      end
    end else if (en) begin
      done <= 1'b0;
      if (phase == 0) begin
        // clear the accumulator for the new token
        attn_out <= {HEAD_DIM*16{1'b0}};
        phase    <= 1;
        slot_ptr <= 0;
      end else if (phase <= SLOTS) begin
        // scan one slot: accumulate its contribution and advance
        attn_out <= out_next;
        if (slot_ptr == SLOTS - 1) begin
          slot_ptr <= 0;
          phase    <= PH_DONE;
        end else begin
          slot_ptr <= slot_ptr + 1'b1;
        end
      end else begin
        // write/done phase: the output above is the finished attention result
        done <= 1'b1;
        if (kv_write && kv_count < SLOTS) begin
          for (c = 0; c < HEAD_DIM; c = c + 1) begin
            kv_ksign[c][kv_count] <= k_new[c*ACT_BITS + ACT_BITS - 1];
            kv_kmag[kv_count][c*QUANT_W +: QUANT_W] <= k_new[c*ACT_BITS +: QUANT_W];
            kv_vsign[c][kv_count] <= v_new[c*ACT_BITS + ACT_BITS - 1];
            kv_vmag[kv_count][c*QUANT_W +: QUANT_W] <= v_new[c*ACT_BITS +: QUANT_W];
          end
          kv_count <= kv_count + 1'b1;
        end
        phase <= 0;   // start the next token
      end
    end
  end

endmodule
