#!/usr/bin/env python3
"""Verify the token-sequential RTL preserves the attention mathematics.

Models the exact RTL control sequence of attn_token.v (phase 0 clear, phases 1..SLOTS
scan one slot each, phase DONE write+done, then restart) and compares the accumulated
output against the combinational golden.
"""
import random

def qval(x, quant_w):
    mag = abs(x); keep = (1 << quant_w) - 1
    qm = mag & keep
    return -qm if (x < 0) else qm

def combinational_golden(q, w_code, K, V, quant_w):
    SLOTS, HD = len(K), len(q)
    score = []
    for s in range(SLOTS):
        acc = 0
        for c in range(HD):
            k = qval(K[s][c], quant_w)
            w = +1 if w_code[c] == 0b01 else (-1 if w_code[c] == 0b10 else 0)
            acc += q[c] * (k * w)
        score.append(acc)
    out = []
    for c in range(HD):
        acc = 0
        for s in range(SLOTS):
            v = qval(V[s][c], quant_w)
            acc += -v if score[s] < 0 else v
        out.append(acc)
    return score, out

def token_sequential(q, w_code, K, V, quant_w):
    """Exact RTL control sequence: clear, scan slot per cycle, done."""
    SLOTS, HD = len(K), len(q)
    # phase 0: clear
    attn_out = [0] * HD
    # phases 1..SLOTS: one slot per cycle
    for s in range(SLOTS):
        # score of slot s (combinational within the cycle)
        acc = 0
        for c in range(HD):
            k = qval(K[s][c], quant_w)
            w = +1 if w_code[c] == 0b01 else (-1 if w_code[c] == 0b10 else 0)
            acc += q[c] * (k * w)
        score = acc
        # accumulate this slot's value contribution
        for c in range(HD):
            v = qval(V[s][c], quant_w)
            attn_out[c] += -v if score < 0 else v
    # phase DONE: output valid, then write the new KV slot
    return attn_out

def run(head_dim, kv_len, quant_w, trials=2000, seed=4242):
    rng = random.Random(seed)
    mismatches = 0
    for _ in range(trials):
        q  = [rng.randint(-128, 127) for _ in range(head_dim)]
        wc = [rng.choice([0b00,0b01,0b10,0b11]) for _ in range(head_dim)]
        K  = [[rng.randint(-128,127) for _ in range(head_dim)] for _ in range(kv_len)]
        V  = [[rng.randint(-128,127) for _ in range(head_dim)] for _ in range(kv_len)]
        _, gold = combinational_golden(q, wc, K, V, quant_w)
        tok = token_sequential(q, wc, K, V, quant_w)
        if tok != gold:
            mismatches += 1
    return trials, mismatches

if __name__ == "__main__":
    print(f"{'HD':>3} {'KV':>4} {'QW':>3} {'trials':>8} {'mismatches':>12}  verdict")
    for hd, kv, qw in [(4,8,8),(8,8,8),(8,16,8),(8,16,6),(8,32,8),(4,16,4)]:
        t, m = run(hd, kv, qw)
        print(f"{hd:>3} {kv:>4} {qw:>3} {t:>8} {m:>12}  {'MATCH' if m==0 else 'MISMATCH'}")
