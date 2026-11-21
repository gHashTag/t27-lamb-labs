#!/bin/bash
# $1=HEAD_DIM $2=KV_LEN $3=QUANT_W $4=outfile $5=module
HD=$1; KV=$2; QW=$3; OUT=$4; MOD=$5
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

    // Reset must actually pulse once so kv_count is a defined value; otherwise the
    // write index is undefined and synthesis prunes the whole KV cache.
    reg [3:0] rst_cnt = 0;
    always @(posedge osc) begin
        rst_cnt <= rst_cnt + 1'b1;
    end
    wire rst_n = (rst_cnt != 0);
    wire en    = 1'b1;

    // Query: rotating signed channels derived from the counter.
    wire signed [$((HD*8-1)):0] q;
    genvar g;
    generate
        for (g = 0; g < $HD; g = g + 1) begin : qgen
            assign q[g*8 +: 8] = counter[7:0] ^ (g * 8'h11);
        end
    endgenerate

    // Ternary weight codes: rotate +1 / 0 / -1 across channels.
    wire [$((HD*2-1)):0] w_code;
    generate
        for (g = 0; g < $HD; g = g + 1) begin : wgen
            assign w_code[g*2 +: 2] = counter[2+g%3] ? 2'b01 : 2'b10;
        end
    endgenerate

    wire signed [$((HD*8-1)):0] k_new = q;
    wire signed [$((HD*8-1)):0] v_new = q;
    wire kv_write = 1'b1;
    wire signed [$((HD*16-1)):0] attn_out;
    wire [$clog2($KV+1)-1:0] kv_count;

    attn_kv #(.HEAD_DIM($HD), .KV_LEN($KV), .QUANT_W($QW)) u_attn (
        .clk(osc), .rst_n(rst_n), .en(en),
        .q(q), .w_code(w_code), .k_new(k_new), .v_new(v_new), .kv_write(kv_write),
        .attn_out(attn_out), .kv_count(kv_count));

    always @(posedge osc) begin
        counter <= counter + 1;
    end

    // Observe the whole attention output and the KV count.
    wire fold = ^attn_out;
    assign led_r23 = fold;
    assign led_t23 = kv_count[0];
endmodule
EOF
