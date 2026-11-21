#!/usr/bin/env python3
"""
Co-design Iteration Documentation for Lamb Labs

Documents one complete iteration:
baseline ternary config -> one controlled change
-> LUT/FF/BRAM/DSP -> clock -> latency -> power
-> tok/s -> J/token -> quality metric
-> decision (accept/reject/iterate)
"""

import json
from datetime import datetime
from pathlib import Path

class CoDesignIteration:
    def __init__(self):
        self.iterations = []
        
    def add_iteration(self, name, baseline, change, resources, timing, power, performance, quality, decision, notes=""):
        iteration = {
            "iteration_id": len(self.iterations) + 1,
            "name": name,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "baseline_config": baseline,
            "change": change,
            "resources": resources,
            "timing": timing,
            "power": power,
            "performance": performance,
            "quality": quality,
            "decision": decision,
            "notes": notes
        }
        self.iterations.append(iteration)
        return iteration
    
    def generate_report(self, output_path):
        report = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "co_design_goal": "Iterative ternary MAC optimization with measured feedback",
            "total_iterations": len(self.iterations),
            "iterations": self.iterations,
            "summary": {
                "total_iterations": len(self.iterations),
                "accepted": len([i for i in self.iterations if i["decision"] == "accept"]),
                "rejected": len([i for i in self.iterations if i["decision"] == "reject"]),
                "iterated": len([i for i in self.iterations if i["decision"] == "iterate"])
            }
        }
        with open(output_path, 'w') as f:
            json.dump(report, f, indent=2)
        return report

if __name__ == "__main__":
    cd = CoDesignIteration()
    
    # Document the baseline iteration (current state)
    cd.add_iteration(
        name="baseline_ternary_mac",
        baseline={
            "config": "ternary_mac_synth.v baseline",
            "quantization": "ternary (-1,0,+1) 2-bit",
            "accumulator": "32-bit signed integer",
            "weight_encoding": "2-bit (01=+1, 10=-1, 00/11=0)",
            "bitstream": "ternary_mac_demo_top_200t.bit"
        },
        change="baseline measurement - no change",
        resources={
            "LUTs": "TBD (measure from bitstream)",
            "FFs": "TBD",
            "BRAM": "used for weights",
            "DSP": 0,
            "LUT_Utilization": "TBD %",
            "FF_Utilization": "TBD %",
            "BRAM_Utilization": "TBD %",
            "DSP_Utilization": "0%"
        },
        timing={
            "clock_mhz": 150,  # ring oscillator estimate
            "jtag_mhz": 6,
            "latency_cycles_per_mac": 1,
            "latency_ns": 6.67  # at 150 MHz
        },
        power={
            "measured_watts": None,
            "measurement_method": "external_meter_required",
            "thermal_state": "ambient",
            "ambient_temp_c": 25
        },
        performance={
            "tok_s": None,  # requires measurement
            "macs_per_sec": None,
            "latency_per_mac_ns": 6.67,
            "j_per_token": None
        },
        quality={
            "metric": "bit_exact_match_golden",
            "value": 1.0,
            "test_vectors": "5 cycle-1 runs PASSED"
        },
        decision="baseline",
        notes="Baseline configuration for ternary MAC demo. Ring oscillator clock ~150MHz. 5 cycle-1 runs passed bit-exact match."
    )
    
    # Add a hypothetical optimization iteration
    cd.add_iteration(
        name="optimize_ring_oscillator",
        baseline="baseline_ternary_mac",
        change="Increase ring oscillator stages for higher frequency",
        resources={
            "LUTs": "+100",
            "FFs": "+50",
            "BRAM": "same",
            "DSP": 0
        },
        timing={
            "clock_mhz": 180,
            "latency_ns": 5.56
        },
        power={
            "estimated_watts": "slightly_higher"
        },
        performance={
            "tok_s_estimated": "higher",
            "latency_per_mac_ns": 5.56
        },
        quality={
            "metric": "bit_exact_match_golden",
            "value": 1.0
        },
        decision="proposed",
        notes="Proposed: increase ring oscillator stages to 22 for ~180MHz. Requires timing closure verification."
    )
    
    report = cd.generate_report("codesign_iteration_report.json")
    print("Co-design iteration report generated")
    print(json.dumps(cd.iterations, indent=2))
