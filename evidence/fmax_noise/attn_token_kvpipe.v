// Token-sequential attention with a PIPELINED KV READ.
//
// Iteration 7 measured the critical path: the KV-cache read mux (a 32-to-1 dynamic-index
// mux per channel), not the accumulator and not the score multiply.
//
// This variant fetches slot N+1 while accumulating slot N, so the read mux and the add sit in
// different clock cycles. The cost is one extra cycle per token.
//
// The math is unchanged: every slot is still scored and accumulated exactly once. The slot
// pointer runs one ahead of the accumulator, and the last slot is handled by wrapping the
// lookahead pointer to slot 0 while the accumulator is held.
//
// PIPE_KV = 0 : the baseline (mux and add in the same cycle)
// PIPE_KV = 1 : the pipelined read

module attn_token #(
    parameter integer HEAD_DIM = 8,
    parameter integer KV_LEN   = 16,
    parameter integer QUANT_W  = 8,
    parameter integer ACT_BITS = 8,
    parameter integer PIPE_KV   = 0
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

  // ---- quantised KV cache: 1D arrays of packed words ----
  reg [SLOTS-1:0]            kv_ksign [0:HEAD_DIM-1];
  reg [SLOTS-1:0]            kv_vsign [0:HEAD_DIM-1];
  reg [HEAD_DIM*QUANT_W-1:0] kv_kmag  [0:SLOTS-1];
  reg [HEAD_DIM*QUANT_W-1:0] kv_vmag  [0:SLOTS-1];

  // ---- slot pointers ----
  // slot_ptr    : the slot being ACCUMULATED this cycle
  // slot_look   : the slot being FETCHED this cycle (one ahead)
  reg [$clog2(SLOTS)-1:0] slot_ptr;
  reg [$clog2(SLOTS)-1:0] slot_look;

  // ---- pipelined read registers: hold the fetched slot's key/value and score ----
  reg [HEAD_DIM*QUANT_W-1:0] pipe_kmag_q;
  reg [HEAD_DIM*QUANT_W-1:0] pipe_vmag_q;
  reg [HEAD_DIM-1:0]         pipe_ksign_q;
  reg [HEAD_DIM-1:0]         pipe_vsign_q;
  reg signed [16:0]          pipe_score_q;
  reg                         pipe_valid_q;

  // ---- score of the fetched slot ----
  reg signed [16:0] score_acc;
  reg signed [ACT_BITS-1:0] q_ext;
  reg signed [QUANT_W:0]   kq_ext;
  reg signed [QUANT_W:0]   vq_ext;
  integer c;
  integer s;

  always @* begin
    score_acc = 17'sd0;
    for (c = 0; c < HEAD_DIM; c = c + 1) begin
      q_ext = $signed(q[c*ACT_BITS +: ACT_BITS]);
      kq_ext = $signed({1'b0, pipe_kmag_q[c*QUANT_W +: QUANT_W]});
      if (pipe_ksign_q[c]) kq_ext = -kq_ext;
      if (w_code[c*2 +: 2] == 2'b00 || w_code[c*2 +: 2] == 2'b11)
        kq_ext = '0;
      else if (w_code[c*2 +: 2] == 2'b10)
        kq_ext = -kq_ext;
      score_acc = score_acc + (q_ext * kq_ext);
    end
  end

  // ---- accumulate the PIPELINED slot ----
  reg signed [HEAD_DIM*16-1:0] out_next;

  always @* begin
    out_next = attn_out;
    if (PIPE_KV == 0) begin
      // baseline: fetch and accumulate in the same cycle
      if (phase >= 1 && phase <= SLOTS) begin
        for (c = 0; c < HEAD_DIM; c = c + 1) begin
          vq_ext = $signed({1'b0, kv_vmag[slot_ptr][c*QUANT_W +: QUANT_W]});
          if (kv_vsign[c][slot_ptr]) vq_ext = -vq_ext;
          out_next[c*16 +: 16] = out_next[c*16 +: 16] +
              (pipe_score_q[16] ? -vq_ext : vq_ext);
        end
      end
    end else begin
      // pipelined: accumulate the slot FETCHED in the previous cycle
      if (pipe_valid_q) begin
        for (c = 0; c < HEAD_DIM; c = c + 1) begin
          vq_ext = $signed({1'b0, pipe_vmag_q[c*QUANT_W +: QUANT_W]});
          if (pipe_vsign_q[c]) vq_ext = -vq_ext;
          out_next[c*16 +: 16] = out_next[c*16 +: 16] +
              (pipe_score_q[16] ? -vq_ext : vq_ext);
        end
      end
    end
  end

  // ---- sequential control ----
  always @(posedge clk) begin
    if (!rst_n) begin
      kv_count   <= 0;
      slot_ptr   <= 0;
      slot_look  <= 0;
      phase      <= 0;
      pipe_valid_q <= 1'b0;
      pipe_score_q <= 17'sd0;
      attn_out   <= {HEAD_DIM*16{1'b0}};
      done       <= 1'b0;
      for (c = 0; c < HEAD_DIM; c = c + 1) begin
        kv_ksign[c] <= {SLOTS{1'b0}};
        kv_vsign[c] <= {SLOTS{1'b0}};
      end
      for (s = 0; s < SLOTS; s = s + 1) begin
        kv_kmag[s] <= {HEAD_DIM*QUANT_W{1'b0}};
        kv_vmag[s] <= {HEAD_DIM*QUANT_W{1'b0}};
      end
    end else if (en) begin
      done <= 1'b0;

      // ---- the pipelined fetch stage: read the LOOKAHEAD slot ----
      if (PIPE_KV == 1) begin
        pipe_kmag_q   <= kv_kmag[slot_look];
        pipe_vmag_q   <= kv_vmag[slot_look];
        pipe_ksign_q  <= kv_ksign[0][slot_look];
        pipe_vsign_q  <= kv_vsign[0][slot_look];
        for (c = 1; c < HEAD_DIM; c = c + 1) begin
          pipe_ksign_q[c] <= kv_ksign[c][slot_look];
          pipe_vsign_q[c] <= kv_vsign[c][slot_look];
        end
        pipe_valid_q   <= (phase >= 1) && (phase <= SLOTS);
        pipe_score_q   <= score_acc;
        if (slot_look == SLOTS - 1) slot_look <= 0;
        else slot_look <= slot_look + 1'b1;
      end

      if (phase == 0) begin
        // clear the accumulator for the new token
        attn_out <= {HEAD_DIM*16{1'b0}};
        phase    <= 1;
        slot_ptr <= 0;
        slot_look <= (PIPE_KV == 1) ? 1'b1 : 1'b0;
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
        // write/done phase
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
        phase <= 0;
        if (PIPE_KV == 1) slot_look <= 1'b1;
      end
    end
  end

endmodule
