// CAUSAL MECHANISM DEMO (simulation only): the reconstruction defect
// `tick_q <= presc[PW-1]` where `presc` is an undeclared identifier.
// yosys: implicitly declares presc as a 1-BIT wire, bit-select [7] is
// OUT OF RANGE -> result is 1'bx (warning: "Range select out of bounds").
// iverilog: models the same semantics with an x-initialized reg.
module xmech;
  localparam integer PW = 8;
  localparam integer CW = 20;
  reg clk = 0; always #2.5 clk = ~clk;  // 200 MHz-class stimulus
  reg tick = 0;
  // toggle tick every 16 clk edges (j2-MSB-like rate, 1 tick / 256 edges is slower;
  // 16 is enough to demonstrate the mechanism)
  integer e = 0; always @(posedge clk) begin e = e + 1; if (e % 16 == 0) tick = ~tick; end
  reg tick_q = 1'bx;                       // == presc[7] under yosys implicit-net rules
  wire tick_rise = tick & ~tick_q;
  reg [CW-1:0] cnt = 0; reg carry;
  always @(posedge clk) begin
    tick_q <= 1'bx;                        // every cycle re-derives x (presc[7] is constant x)
    if (tick_rise) begin
      carry = 1'b1;
      begin : inc
        integer k;
        for (k = 0; k < CW; k = k + 1) begin
          cnt[k] <= cnt[k] ^ carry;
          carry = carry & cnt[k];
        end
      end
    end
  end
  initial begin #400000;
    $display("XMECH_RESULT ticks_seen=%0d cnt=%0d tick_rise=%b", (e/16), cnt, tick_rise);
    if (cnt == 0) $display("XMECH_VERDICT FROZEN_AT_ZERO (matches r4t4b behavior)");
    else          $display("XMECH_VERDICT ADVANCING (defect model wrong)");
    $finish; end
endmodule
