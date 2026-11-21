#!/bin/bash
# Token-sequential attention clocked by STARTUPE2.CFGMCLK (~66 MHz, Artix-7 family
# nominal, per the repo's docs/fpga/clocking.md) instead of a fabric ring oscillator.
# $1=ACT_BITS $2=QUANT_W $3=KV_LEN $4=outfile $5=module
AB=$1; QW=$2; KV=$3; OUT=$4; MOD=$5
HD=8
cat > "$OUT" << EOF
module $MOD (
    output wire led_r23,
    output wire led_t23
);
    // CFGMCLK: the Artix-7 internal configuration oscillator. No fabric ring
    // oscillator, so the clock is a silicon-specified source, not an estimate.
    wire cfgmclk;
    STARTUPE2 #(
        .PROG_USR("FALSE"),
        .SIM_CCLK_FREQ(10.0)
    ) startup (
        .CFGCLK(), .CFGMCLK(cfgmclk), .EOS(), .PREQ(),
        .CLK(1'b0), .GSR(1'b0), .GTS(1'b0), .KEYCLEARB(1'b0),
        .PACK(1'b0), .USRCCLKO(1'b0), .USRCCLKTS(1'b0),
        .USRDONEO(1'b1), .USRDONETS(1'b1)
    );

    reg [22:0] counter = 0;
    wire signed [$((HD*AB-1)):0] q;
    genvar g;
    generate
        for (g = 0; g < $HD; g = g + 1) begin : qgen
            assign q[g*$AB +: $AB] = counter[$((AB-1)):0] ^ (g * 8'h11);
        end
    endgenerate
    wire [$((HD*2-1)):0] w_code;
    generate
        for (g = 0; g < $HD; g = g + 1) begin : wgen
            assign w_code[g*2 +: 2] = counter[2+g%3] ? 2'b01 : 2'b10;
        end
    endgenerate
    wire signed [$((HD*AB-1)):0] k_new = q;
    wire signed [$((HD*AB-1)):0] v_new = q;
    wire kv_write = 1'b1;
    wire signed [$((HD*16-1)):0] attn_out;
    wire [$clog2($KV+1)-1:0] kv_count;
    wire done;
    attn_token #(.HEAD_DIM($HD), .KV_LEN($KV), .QUANT_W($QW), .ACT_BITS($AB)) u_attn (
        .clk(cfgmclk), .rst_n(1'b1), .en(1'b1),
        .q(q), .w_code(w_code), .k_new(k_new), .v_new(v_new), .kv_write(kv_write),
        .attn_out(attn_out), .kv_count(kv_count), .done(done));
    always @(posedge cfgmclk) counter <= counter + 1;
    wire fold = ^attn_out;
    assign led_r23 = fold;
    assign led_t23 = done;
endmodule
EOF
