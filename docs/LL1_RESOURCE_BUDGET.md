# LL-1R: Lamb Labs Resource Reality Check
**Generated**: 2026-11-19T17:52+07:00  
**Objective**: Establish verifiable Kria KV260 resource and performance budget for ternary transformer MVP

## Executive Summary

This document corrects the LL-1 strategy by replacing unfounded "TinyLlama on Kria" claims with a resource reality check. The first FPGA target is explicitly defined as a **tiny ternary transformer block or tiny LM**, not the full TinyLlama-1.1B model. All performance metrics are marked as `TARGET` (estimated) rather than `MEASURED` (verified).

## 1. Kria KV260 Reality Check

### Official Resource Budget
| Resource | Available | Notes |
|----------|-----------|-------|
| Logic Cells | 256K | Xilinx 7-series Artix-7 FPGA |
| BRAM | 144 | 36Kb each |
| URAM | 64 | 256Kb each |
| DSP | 1.2K | 18-bit multiplier blocks |
| DDR Memory | 4 GB | System memory |
| PS-PL Interface | AXI4 | High-bandwidth memory access |

### Critical Correction
**Previous Error**: Assuming TinyLlama-1.1B (1.1B parameters) could fit on-chip  
**Reality Check**: 1.1B parameters require ~8.8GB at 8-bit precision, exceeding Kria's 4GB DDR and making on-chip placement impossible.

## 2. Memory Hierarchy Analysis

### On-Chip Memory (KV260 FPGA Resources)
- **Weights**: Cannot store 1.1B parameters on-chip
- **Activations**: Limited by BRAM/URAM for intermediate states
- **KV-Cache**: Must be DDR-backed for reasonable sequence length
- **Buffers**: Control state and temporary accumulators only

### DDR Memory (4GB System)
- **Weights**: 4GB max (8-bit: 512M parameters, 4-bit: 1B parameters)
- **Activations**: Remaining memory for KV-cache, streaming, overhead
- **Bandwidth**: Limited by PS-PL interface (~25-50 GB/s theoretical)

## 3. First FPGA Target Selection

### Selected Target: Tiny Ternary Transformer Block
**Rationale**: Prove datapath, verifier, compiler, and measurement loop before scaling

#### Component Breakdown
| Component | Ternary Parameters | Estimated FPGA Resources |
|-----------|-------------------|--------------------------|
| Linear Layer (Q/K/V) | 3× tiny transformer | 10-20K logic cells |
| Ternary Multiply-Free | Weight application | 5-10K logic cells |
| TNF Accumulator | Exact integer path | 3-5K logic cells |
| Control FSM | Streaming interface | 2-3K logic cells |
| **Total** | **~1-2M parameters max** | **20-41K logic cells** |

#### Resource Utilization (Conservative Estimate)
```
Logic Cells:    41K / 256K (16%) - Safe margin
BRAM:           10 / 144 (7%)    - For small buffers  
URAM:           0 / 64 (0%)       - Not needed for MVP
DSP:            0 / 1.2K (0%)    - Multiplier-free design
```

## 4. Memory Bandwidth Analysis

### Streaming Architecture
- **On-chip**: Compute engine with small buffers
- **DDR**: Weight/KV-cache streaming via AXI4
- **Bandwidth Requirement**: 
  - 2M parameters × 4-bit weights = 1MB weights
  - Small activations streamed per token
  - **Target: < 1 GB/s** (well within Kria capabilities)

### Performance Estimates (TARGET - NOT MEASURED)
| Metric | Target Range | Notes |
|--------|--------------|-------|
| Tokens/sec | 50-200 | Limited by DDR streaming, not compute |
| Latency/token | 5-20 μs | On-chip compute dominates |
| Energy/token | 10-100 nJ | Preliminary ternary datapath estimate |
| Power | 2-5 W | Typical Kria operating range |

## 5. Corrected LL-1 Model Strategy

```text
LL1_MODEL_STRATEGY:
  long_term_target: TinyLlama-1.1B-Chat-v1.0
  first_fpga_target: tiny ternary transformer block (1-2M params)
  reason: prove datapath, verifier, compiler, and measurement loop first
  forbidden_claim: "TinyLlama fully on Kria"
  forbidden_claim: "10-15 tokens/sec measured" 
  forbidden_claim: "80-120 J/token measured"
  acceptance_criteria:
    - Exact integer datapath bit-exact
    - Multiplier-free weight application
    - Working on-chip computation
    - DDR streaming interface
    - Verified timing and resource utilization
```

## 6. Scaling Path to TinyLlama

### Phase 1: MVP (This Work)
- Single ternary linear block
- 1-2M parameters
- Proof of datapath and verification

### Phase 2: Tiny LM
- Complete tiny transformer (attention + MLP)
- 10-50M parameters  
- Multi-block verification

### Phase 3: Full TinyLlama Planning
- Memory tiling strategy
- DDR bandwidth optimization
- KV-cache management
- **No fabrication of performance claims**

## 7. Verification Requirements

### T27 Verification Stack
- **Spec**: `.t27` specification with exact integer arithmetic
- **Compiler**: t27c → Verilog generation
- **Test**: t27b fast verification loop
- **Golden Model**: Python/C reference for bit-exact comparison
- **Simulation**: Icarus/Verilator timing validation
- **Board Test**: Kria KV260 measurement

### Acceptance Criteria
1. ✅ Resource estimates match official Kria specifications
2. ✅ On-chip vs DDR residency clearly separated  
3. ✅ Performance marked as `TARGET` not `MEASURED`
4. ✅ First target is tiny transformer block, not full model
5. ✅ No public claims without board verification

## 8. Next Steps

### Immediate Actions
1. **LL-2**: Implement ternary datapath MVP (`ternary_linear_block.t27`)
2. **LL-3**: Create golden model with exact integer arithmetic
3. **LL-4**: Generate RTL from t27c specifications

### Verification Dependencies
- All components must pass t27b verification
- Golden model conformance required
- Board testing before any public performance claims

---

**Document Status**: ✅ COMPLETE - Resource reality check established  
**Next Phase**: LL-2 Ternary Datapath MVP  
**Review Required**: Before proceeding to RTL implementation