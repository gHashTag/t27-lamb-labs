#!/bin/bash
# $1=acc width $2=mode(open|closed) $3=outfile $4=module
W=$1; MODE=$2; OUT=$3; MOD=$4
if [ "$MODE" = "closed" ]; then FB="acc_out"; else FB="{ $W {1'b0} }"; fi
cat > "$OUT" << EOF
module $MOD (
    output wire led_r23,
    output wire led_t23
);
    (* KEEP = "TRUE" *) wire osc;
    (* KEEP = "TRUE" *) wire chain [19:0];
    reg [22:0] counter = 0;
    assign chain[0] = ~chain[19];
    genvar i;
    generate
        for (i = 1; i < 20; i = i + 1) begin : inv_chain
            (* KEEP = "TRUE" *) LUT1 #(.INIT(2'b01)) inv (
                .I0(chain[i-1]), .O(chain[i]));
        end
    endgenerate
    assign osc = chain[19];
    wire        rst_n = 1'b1;
    wire        en    = 1'b1;
    wire signed [7:0] a = counter[7:0];
    wire        [1:0] w_code = {counter[1], counter[0]};
    wire signed [$((W-1)):0] acc_in = $FB;
    wire signed [$((W-1)):0] acc_out;
    ternary_mac_top mac (
        .clk(osc), .rst_n(rst_n), .en(en), .a(a),
        .w_code(w_code), .acc_in(acc_in), .acc_out(acc_out));
    always @(posedge osc) begin
        counter <= counter + 1;
    end
    wire fold = ^acc_out;
    assign led_r23 = fold;
    assign led_t23 = acc_out[$((W-1))];
endmodule
EOF
