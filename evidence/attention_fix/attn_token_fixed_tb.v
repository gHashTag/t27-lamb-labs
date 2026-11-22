`timescale 1ns/1ps
// Verify the CORRECTED token-sequential attention against a CPU golden, in Verilog.
//
// WHAT THIS CHECKS: the change fixed the STORAGE LAYOUT and the INDEXING, and removed the
// score's factor-of-16 overflow. The equations are the ones the Python golden model verified
// over 12000 randomised trials; this testbench verifies them in the actual Verilog, including
// the new indexing.
module attn_clean_tb;
  localparam HD = 4;
  localparam KV = 8;
  localparam QW = 8;

  reg clk = 0;
  always #5 clk = ~clk;

  reg signed [HD*8-1:0] q;
  reg [HD*2-1:0] w_code;
  reg signed [HD*8-1:0] k_new, v_new;
  reg kv_write = 1;
  reg rst_n = 0;
  wire signed [HD*16-1:0] attn_out;
  wire [$clog2(KV+1)-1:0] kv_count;
  wire done;

  attn_token #(.HEAD_DIM(HD), .KV_LEN(KV), .QUANT_W(QW), .ACT_BITS(8)) u (
      .clk(clk), .rst_n(rst_n), .en(1'b1),
      .q(q), .w_code(w_code), .k_new(k_new), .v_new(v_new), .kv_write(kv_write),
      .attn_out(attn_out), .kv_count(kv_count), .done(done));

  reg [QW-1:0] g_k [0:HD-1][0:KV-1];
  reg         g_ks[0:HD-1][0:KV-1];
  reg [QW-1:0] g_v [0:HD-1][0:KV-1];
  reg         g_vs[0:HD-1][0:KV-1];
  integer c, s;
  reg signed [31:0] acc, sc, vv;

  integer tb_slot = 0;
  task mirror_write;
    begin
      for (c = 0; c < HD; c = c + 1) begin
        g_ks[c][tb_slot] = k_new[c*8+7];
        g_k [c][tb_slot] = k_new[c*8 +: QW];
        g_vs[c][tb_slot] = v_new[c*8+7];
        g_v [c][tb_slot] = v_new[c*8 +: QW];
      end
      tb_slot = tb_slot + 1;
    end
  endtask

  reg signed [HD*16-1:0] g_out;
  task golden;
    begin
      g_out = 0;
      for (s = 0; s < KV; s = s + 1) begin
        acc = 0;
        for (c = 0; c < HD; c = c + 1) begin
          if (g_ks[c][s]) sc = -$signed({1'b0, g_k[c][s]});
          else         sc =  $signed({1'b0, g_k[c][s]});
          if (w_code[c*2 +: 2] == 2'b01) sc =  sc;
          else if (w_code[c*2 +: 2] == 2'b10) sc = -sc;
          else sc = 0;
          acc = acc + q[c*8 +: 8] * sc;
        end
        for (c = 0; c < HD; c = c + 1) begin
          // the value carries its own stored sign, and the score's sign selects whether it
          // is added or subtracted
          if (g_vs[c][s]) vv = -$signed({1'b0, g_v[c][s]});
          else            vv =  $signed({1'b0, g_v[c][s]});
          if (acc < 0) g_out[c*16 +: 16] = g_out[c*16 +: 16] - vv;
          else         g_out[c*16 +: 16] = g_out[c*16 +: 16] + vv;
        end
      end
    end
  endtask

  integer errors, trials, tok;
  initial begin
    errors = 0;
    for (trials = 0; trials < 40; trials = trials + 1) begin
      // Reset per trial: without it the DUT is still finishing the previous trial's token
      // while the stimulus has already changed, and the two would mix.
      rst_n = 0;
      repeat (3) @(posedge clk);
      rst_n = 1;
      q = $random; w_code = $random; k_new = $random; v_new = $random;
      tb_slot = 0;
      for (c = 0; c < HD; c = c + 1)
        for (s = 0; s < KV; s = s + 1) begin
          g_k[c][s]=0; g_ks[c][s]=0; g_v[c][s]=0; g_vs[c][s]=0;
        end
      // Run KV+1 tokens. The first KV writes fill the cache; the (KV+1)-th token is the
      // one whose scan sees a FULL and STABLE cache, so the golden can use it. Counting
      // tokens (rather than waiting on `done` directly) avoids starting the comparison
      // while the fill token's done pulse is still high.
      tok = 0;
      while (tok < KV + 1) begin
        @(posedge clk);
        if (done) begin
          tok = tok + 1;
          if (tok <= KV) mirror_write;
        end
      end
      golden;
      if (attn_out !== g_out) begin
        errors = errors + 1;
        if (errors <= 1) begin
          $display("MISMATCH trial %0d: dut=%h golden=%h (slot %0d)", trials, attn_out, g_out, tb_slot);
          $display("  q=%h w_code=%h", q, w_code);
          for (c = 0; c < HD; c = c + 1) begin
            $write("  ch%0d: ", c);
            for (s = 0; s < KV; s = s + 1)
              $write("k=%h/%b v=%h/%b  ", g_k[c][s], g_ks[c][s], g_v[c][s], g_vs[c][s]);
            $display("");
          end
          $display("  DUT cache kmag=%h vmag=%h ksign=%h vsign=%h",
                   u.kv_kmag, u.kv_vmag, u.kv_ksign, u.kv_vsign);
        end
      end
    end
    $display("ATTENTION VERIFICATION: %0d trials, %0d mismatches", trials, errors);
    if (errors == 0) $display("RESULT: MATCH - the CORRECTED attention equals the golden");
    else              $display("RESULT: FAIL");
    $finish;
  end
endmodule
