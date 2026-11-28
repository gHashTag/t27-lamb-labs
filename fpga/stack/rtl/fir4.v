// fpga/stack/rtl/fir4.v — 4-tap direct-form FIR, 8-bit signed data/coeffs.
// Coefficients are PORTS (not constants) so multipliers are not constant-folded
// and yosys DSP48E1 inference is exercised honestly.
module fir4 (
    input  wire               clk,
    input  wire               rstn,
    input  wire               en,
    input  wire signed [7:0]  x,
    input  wire signed [7:0]  c0,
    input  wire signed [7:0]  c1,
    input  wire signed [7:0]  c2,
    input  wire signed [7:0]  c3,
    output reg  signed [23:0] y
);
    reg signed [7:0]  d0, d1, d2, d3;
    reg signed [15:0] m0, m1, m2, m3;
    reg signed [23:0] a0, a1;

    always @(posedge clk) begin
        if (!rstn) begin
            d0 <= 8'sd0; d1 <= 8'sd0; d2 <= 8'sd0; d3 <= 8'sd0;
            m0 <= 16'sd0; m1 <= 16'sd0; m2 <= 16'sd0; m3 <= 16'sd0;
            a0 <= 24'sd0; a1 <= 24'sd0; y <= 24'sd0;
        end else if (en) begin
            d0 <= x;
            d1 <= d0;
            d2 <= d1;
            d3 <= d2;
            m0 <= d0 * c0;
            m1 <= d1 * c1;
            m2 <= d2 * c2;
            m3 <= d3 * c3;
            a0 <= m0 + m1;
            a1 <= m2 + m3;
            y  <= a0 + a1;
        end
    end
endmodule
