# Next Scoped Work — candidate tracks (M4 planning, non-binding)

STATUS: PLANNING. No track is started here; each names its gate and first scoped slice.
Gates refer to `OWNER_DECISIONS.md` (D1–D6).

| Track | First scoped slice | Gate | Precondition met? |
|---|---|---|---|
| T1 power/timing (FPGA) | install Vivado WebPACK; `report_power` on shipped `.bit` netlist → replace ~0.7 W / ~0.12 J/token ESTIMATE band with a tool number (still not external-meter MEASURED) | owner approves ~20–30 GB install | no (install approval) |
| T2 external meter | serial current meter on AX7203 rail → J/token MEASURED | owner provides meter | no |
| T3 spec→RTL repair | write `.t27` spec for `ternary_mac_demo_top`, regenerate RTL, diff vs shipped netlist | D5 (HOLD lift) | no |
| T4 variance gate closure | re-run variance on rebuilt bitstream (depends on T3) | D5 | no |
| T5 r4t4c board rebuild | flash corrected fork, re-run live measurement, close the 200-vs-397.62 MHz discrepancy | openXC7 install approval (part of D5) | no |
| T6 new GPU kernels | only after D2 methodology decides how perf is measured | D2 | no |
| T7 acceptance/toolchain records | commit `GPU_ACCEPTANCE_RECORD.md` + `CANONICAL_TOOLCHAIN.md` | D1 + D4 "PIN" | no (answers pending) |
| T8 engagement (Block 8) | wait on Lamb Labs open model release | external | n/a |

Sequencing intent: D3 merge → T7 records → owner chooses among T1/T3/T5/T6.
T2 and T8 are owner-dependency tracks. Nothing in this table overrides a HOLD.

## Track selection after consolidation (ORDER LAMB_LABS_VERTICAL_CONSOLIDATION_NEXT, 2026-11-25)

Consolidation is DONE (master `0392c39`, origin untouched). The owner ORDER renumbers
tracks; mapping to the table above: ORDER T1=T1 power/timing, ORDER T2=new kernels=T6,
ORDER T3=spec→RTL=T3, ORDER T4=variance gate=T4, ORDER T5=engagement=T8, ORDER
T6=Mac toolchain fix (new, not in table), ORDER T7=push origin (new), ORDER T8=hold.

SELECTED_TRACK: **T1 power/timing** (owner hinted "скорее всего T1").
Precondition state, recorded honestly:

- Vivado is NOT installed (verified earlier this consolidation). EXECUTE_NOW.md manual
  Tcl steps exist for `utilization_report.txt` / `power_report.txt`; the shipped
  bitstream artifact is in `bitstream/`.
- Install cost: WebPACK-class download ~20–30 GB, no-cost license expected for
  xc7a200t but to be confirmed at install time (constraint: no paid resources).
- Output honesty: `report_power` on the shipped netlist replaces the ~0.7 W /
  ~0.12 J/token ESTIMATED band with a **tool number**, not an external-meter MEASURED
  (meter track stays T2/doc-numbering). It also characterizes the **defective shipped
  design** (dead `osc` clock, pruned accumulator) — results describe that artifact,
  not a corrected one.
- Not affected by D5 HOLD as scoped: this is local tooling on existing artifacts, no
  board runs, no new FPGA bitstream builds.
- Approval needed from owner: Vivado install. Push origin remains a separate gate.

No track is executed in this commit; execution starts only after the owner's explicit
approval in chat.

