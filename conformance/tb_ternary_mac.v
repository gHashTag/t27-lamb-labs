`default_nettype none
// tb_ternary_mac.v — conformance testbench for the committed ternary_mac_top cell.
// Protocol: reads vector lines "<a> <w> <acc_in> <rst_n> <en>" (signed decimal),
// applies each for exactly one posedge, prints the measured registered acc_out.
// Expected values are NOT embedded here — the python golden computes them from
// the RTL contract independently; comparison lives in run_conformance.py.
`timescale 1ns/1ps
module tb_ternary_mac;
    reg clk = 0;
    reg rst_n, en;
    reg signed [7:0]  a;
    reg        [1:0]  w_code;
    reg signed [31:0] acc_in;
    wire signed [31:0] acc_out;
    integer fd, n, k;
    integer va, vw, vacc, vrst, ven;

    ternary_mac_top dut (.clk(clk), .rst_n(rst_n), .en(en),
                         .a(a), .w_code(w_code), .acc_in(acc_in), .acc_out(acc_out));

    always #5 clk = ~clk;

    initial begin
        fd = $fopen("vectors_mac.txt", "r");
        if (fd == 0) begin $display("TBERROR no vector file"); $finish; end
        while (!$feof(fd)) begin
            n = $fscanf(fd, "%d %d %d %d %d", va, vw, vacc, vrst, ven);
            if (n == 5) begin
                a = va; w_code = vw[1:0]; acc_in = vacc; rst_n = vrst[0]; en = ven[0];
                @(posedge clk);
                #1;
                $display("MACRESULT %0d %0d %0d %0d %0d %0d", va, vw, vacc, vrst, ven, acc_out);
            end
        end
        $fclose(fd);
        $display("MACDONE");
        $finish;
    end
endmodule
`default_nettype wire
