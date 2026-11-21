# t27-lamb-labs

**Lamb Labs** — FPGA/ternary MAC/variance research for t27 project.

## Scope

This repository contains all Lamb Labs FPGA/ternary MAC/variance research work, separated from the main t27 GODMODE repository.

## Structure

```
t27-lamb-labs/
├── bitstream/           # Pre-built bitstreams (ternary_mac_demo_top_200t.bit)
├── evidence/            # Variance test evidence (5 runs + SHA256)
├── toolchain/           # FPGA toolchain (yosys, prjxray, oss-cad-suite, openFPGALoader)
├── specs/               # Lamb-specific .t27 specs
├── fpga/                # FPGA designs and constraints
├── scripts/             # Build/deploy scripts (handoff.sh)
└── docs/                # Documentation (LL1_RESOURCE_BUDGET, LL1_TARGET_MODEL)
```

## Scope

**Lamb Labs (this repo):**
- FPGA/ternary MAC/variance research
- Bitstream generation and flashing
- Variance test evidence
- FPGA toolchain (yosys, prjxray, openFPGALoader)
- FPGA specifications and designs

**GODMODE (stays in t27):**
- Backend generation, CI
- arXiv package, handoff
- GPU port, keys.t27
- All non-FPGA work

## Quick Start

```bash
# Flash bitstream (Mac with Digilent HS2 cable)
openFPGALoader -c digilent_hs2 bitstream/ternary_mac_demo_top_200t.bit

# Run variance tests (5 cycle-1 runs)
./scripts/variance_test.sh

# Verify evidence
cat evidence/ARTIFACT_HASHES.txt
```

## License

Apache-2.0 (same as t27)
