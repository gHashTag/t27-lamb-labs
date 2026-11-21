#!/bin/bash
# $1=ACT_BITS $2=QUANT_W $3=KV_LEN $4=outfile $5=module
AB=$1; QW=$2; KV=$3; OUT=$4; MOD=$5
HD=8
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
    reg [3:0] rst_cnt = 0;
    always @(posedge osc) rst_cnt <= rst_cnt + 1'b1;
    wire rst_n = (rst_cnt != 0);
    wire en = 1'b1;
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
    attn_seq #(.HEAD_DIM($HD), .KV_LEN($KV), .QUANT_W($QW), .ACT_BITS($AB)) u_attn (
        .clk(osc), .rst_n(rst_n), .en(en),
        .q(q), .w_code(w_code), .k_new(k_new), .v_new(v_new), .kv_write(kv_write),
        .attn_out(attn_out), .kv_count(kv_count));
    always @(posedge osc) counter <= counter + 1;
    wire fold = ^attn_out;
    assign led_r23 = fold;
    assign led_t23 = kv_count[0];
endmodule
EOF
