#!/usr/bin/env python3
"""Validate the RL-ready benchmark and the per-parameter table against the evidence.

Fails if a number in the benchmark is not backed by a measured value in the evidence
JSON files. This is the guard against the benchmark drifting into unsupported claims.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load(p):
    with open(os.path.join(ROOT, p)) as f:
        return json.load(f)

def main():
    errors = []
    bench = load("benchmark/rl_ready_benchmark.json")
    perpar = load("benchmark/per_param_efficiency.json")
    util   = load("evidence/utilization/utilization_report.json")
    cd     = load("evidence/codesign/codesign_iteration_report.json")
    attn   = load("evidence/attention/attention_kv_report.json")
    joint  = load("evidence/attention_joint/joint_iteration_report.json")

    # 1. every evaluated state must be traceable to a measured config
    measured = {}
    for m in cd["measurements"]:
        measured[(m["mode"], m["acc_bits"])] = m
    # The joint sweep uses the ACT_BITS-parameterised RTL and supersedes the earlier
    # fixed-8-bit attention sweep for any state that declares act_bits.
    for m in joint["quality_gated_frontier"]:
        if "estimated_lcs" in m:
            # the joint sweep fixes HEAD_DIM=8 and KV_LEN=16
            measured[("attn", 8, 16, m["quant_w"], m["act_bits"])] = m
    for m in attn["measurements"]:
        measured.setdefault(("attn", m["head_dim"], m["kv_len"], m["quant_w"]), m)

    for st in bench["already_evaluated_states"]:
        s = st["state"]
        if s["arch"] == "attention_kv":
            key = ("attn", s.get("head_dim"), s.get("kv_len"), s.get("quant_w"), s.get("act_bits"))
            if key not in measured:
                key = ("attn", s.get("head_dim"), s.get("kv_len"), s.get("quant_w"))
        else:
            key = (s.get("loop_topology"), s.get("acc_bits"))
        if key not in measured:
            errors.append(f"state {s} has no measured configuration in the evidence")
            continue
        src = measured[key]
        if "estimated_lcs" in src and src["estimated_lcs"] != st["estimated_lcs"]:
            errors.append(f"state {s}: lcs {st['estimated_lcs']} != measured {src['estimated_lcs']}")
        if "dsp48e1" in src and src["dsp48e1"] != st["dsp"]:
            errors.append(f"state {s}: dsp {st['dsp']} != measured {src['dsp48e1']}")
        if "exact_match_rate" in src and src["exact_match_rate"] != st.get("bit_exact"):
            errors.append(f"state {s}: bit_exact {st.get('bit_exact')} != measured {src['exact_match_rate']}")

    # 2. resource constraint must reject the measured combinational attention form
    cap = bench["reward"]["resource_constraint"]["max_estimated_lcs"]
    for st in bench["already_evaluated_states"]:
        if st["estimated_lcs"] > cap and st["decision"].startswith("ACCEPT"):
            errors.append(f"state {st['state']} exceeds the lcs cap but is ACCEPTed")

    # 3. per-parameter rows must not present unmeasured numbers as measured
    for row in perpar["per_parameter_table"]["rows"]:
        if row.get("status") == "NOT MEASURED":
            for k in ("tok_s_per_M_params", "j_per_token_per_M_params", "estimated_lcs_per_M_params"):
                if row.get(k) is not None:
                    errors.append(f"per-param row {row['workload']}: {k} must be null when NOT MEASURED")
        if "NOT MEASURED" not in row.get("status", "") and "ESTIMATED" not in row.get("status", "") \
           and "MEASURED" not in row.get("status", ""):
            errors.append(f"per-param row {row['workload']}: status must label measured/estimated")

    # 4. the required label must be present
    if "not performance parity with 27B-class MPU" not in perpar.get("label", ""):
        errors.append("per-param table is missing the required non-parity label")

    # 5. zero-DSP must hold in every recorded measurement
    for m in cd["measurements"]:
        if m.get("dsp48e1", 0) != 0:
            errors.append(f"codesign config {m['mode']}/{m['acc_bits']}b has DSP={m['dsp48e1']}")
    for m in attn["measurements"]:
        if m.get("dsp48e1", 0) != 0:
            errors.append(f"attention config {m['head_dim']}/{m['kv_len']}/{m['quant_w']} has DSP={m['dsp48e1']}")

    if errors:
        print("BENCHMARK VALIDATION FAILED")
        for e in errors:
            print("  -", e)
        return 1
    print("BENCHMARK VALIDATION PASSED")
    print(f"  states checked      : {len(bench['already_evaluated_states'])}")
    print(f"  per-param rows      : {len(perpar['per_parameter_table']['rows'])}")
    print("  zero-DSP invariant  : holds in every measured configuration")
    print("  non-parity label    : present")
    return 0

if __name__ == "__main__":
    sys.exit(main())
