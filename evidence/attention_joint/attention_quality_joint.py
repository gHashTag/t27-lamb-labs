#!/usr/bin/env python3
"""Joint design space: activation width x KV quantisation width.

The KV cache stores sign + QUANT_W magnitude bits of an ACT_BITS-wide signed value.
Losslessness therefore requires QUANT_W >= ACT_BITS (the magnitude range must fit).
This script measures the lossless frontier and the error cost of violating it.
"""
import random

def qval(x, quant_w):
    mag = abs(x); keep = (1 << quant_w) - 1
    qm = mag & keep
    return -qm if (x < 0) else qm

def attention(q, w_code, K, V, quant_w, quantised):
    SLOTS, HD = len(K), len(q)
    score = []
    for s in range(SLOTS):
        acc = 0
        for c in range(HD):
            k = qval(K[s][c], quant_w) if quantised else K[s][c]
            w = +1 if w_code[c] == 0b01 else (-1 if w_code[c] == 0b10 else 0)
            acc += q[c] * (k * w)
        score.append(acc)
    out = []
    for c in range(HD):
        acc = 0
        for s in range(SLOTS):
            v = qval(V[s][c], quant_w) if quantised else V[s][c]
            acc += -v if score[s] < 0 else v
        out.append(acc)
    return out

def rel_err(got, want):
    den = sum(abs(b) for b in want)
    return (sum(abs(a-b) for a,b in zip(got,want))/den) if den else 0.0

def run(act_bits, quant_w, head_dim=8, kv_len=16, trials=1500, seed=99):
    rng = random.Random(seed)
    lo, hi = -(1 << (act_bits-1)), (1 << (act_bits-1)) - 1
    errs, exact = [], 0
    for _ in range(trials):
        q  = [rng.randint(lo, hi) for _ in range(head_dim)]
        wc = [rng.choice([0b00,0b01,0b10,0b11]) for _ in range(head_dim)]
        K  = [[rng.randint(lo, hi) for _ in range(head_dim)] for _ in range(kv_len)]
        V  = [[rng.randint(lo, hi) for _ in range(head_dim)] for _ in range(kv_len)]
        g = attention(q,wc,K,V,quant_w,False)
        qq = attention(q,wc,K,V,quant_w,True)
        e = rel_err(qq,g); errs.append(e)
        if e == 0.0: exact += 1
    errs.sort(); n=len(errs)
    return {"act_bits": act_bits, "quant_w": quant_w,
            "mean_rel_err": sum(errs)/n, "p95_rel_err": errs[int(n*.95)],
            "exact_match_rate": exact/n}

if __name__ == "__main__":
    print(f"{'ACT':>4} {'QW':>3} {'lossless?':>10} {'mean_err':>10} {'p95_err':>10} {'exact%':>8}")
    for act in (8, 6, 4):
        for qw in (8, 6, 4):
            r = run(act, qw)
            loss = "YES" if r["exact_match_rate"] == 1.0 else "no"
            print(f"{act:>4} {qw:>3} {loss:>10} {r['mean_rel_err']:>10.6f} "
                  f"{r['p95_rel_err']:>10.6f} {r['exact_match_rate']*100:>7.2f}%")
    print()
    print("RULE: the KV cache stores sign + QUANT_W magnitude bits of an ACT_BITS-wide")
    print("      signed value, so losslessness requires QUANT_W >= ACT_BITS.")
