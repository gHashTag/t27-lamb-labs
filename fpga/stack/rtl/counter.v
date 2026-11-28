// fpga/stack/rtl/counter.v — 32-bit enable counter (B-ESTIMATE smoke design)
module counter #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rstn,
    input  wire             en,
    output reg  [WIDTH-1:0] count
);
    always @(posedge clk) begin
        if (!rstn)
            count <= {WIDTH{1'b0}};
        else if (en)
            count <= count + 1'b1;
    end
endmodule
