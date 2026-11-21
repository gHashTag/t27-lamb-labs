module ax7203_min (
    input  wire clk200_p,
    input  wire clk200_n,
    output wire led0,
    output wire led1
);
  wire clk200;
  IBUFDS #(.DIFF_TERM("FALSE"), .IOSTANDARD("DIFF_SSTL15")) clk200_buf (
      .I(clk200_p), .IB(clk200_n), .O(clk200));

  reg [22:0] counter = 0;
  always @(posedge clk200) counter <= counter + 1;

  wire signed [63:0] q;
  genvar g;
  generate
    for (g = 0; g < 8; g = g + 1) begin : qgen
      assign q[g*8 +: 8] = counter[7:0] ^ (g * 8'h11);
    end
  endgenerate
  wire [15:0] w_code;
  generate
    for (g = 0; g < 8; g = g + 1) begin : wgen
      assign w_code[g*2 +: 2] = counter[2+g%3] ? 2'b01 : 2'b10;
    end
  endgenerate
  wire signed [63:0] k_new = q;
  wire signed [63:0] v_new = q;
  wire signed [127:0] attn_out;
  wire [4:0] kv_count;
  wire done;

  attn_token #(.HEAD_DIM(8), .KV_LEN(16), .QUANT_W(8), .ACT_BITS(8), .PIPE_KV(1)) u_attn (
      .clk(clk200), .rst_n(1'b1), .en(1'b1),
      .q(q), .w_code(w_code), .k_new(k_new), .v_new(v_new), .kv_write(1'b1),
      .attn_out(attn_out), .kv_count(kv_count), .done(done));

  assign led0 = ~done;
  assign led1 = ~attn_out[0];
endmodule
