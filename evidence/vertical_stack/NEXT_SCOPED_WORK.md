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


## T1 execution probe (2026-11-25, after owner approvals: install=yes, push=yes, local=no)

Owner correction: Vivado must NOT be installed on the local Mac — GPU box (w3070) and
VPS are for that. Probe results, recorded honestly:

- **Push origin: DONE.** `a7ef751..dfbb5d7 master -> master` (origin/master = dfbb5d7).
- **No routed checkpoint in the repo.** `find` finds only `.bit` files (shipped
  `ternary_mac_demo_top_200t.bit` + 4 clock_probe bits); zero `.dcp`. EXECUTE_NOW.md
  Option A (`open_checkpoint`) therefore has no input artifact. `report_power` on a
  `.bit` alone is not possible (Vivado cannot reopen a bitstream into a netlist) —
  the shipped-design tool number requires the ORIGINAL routed checkpoint from the
  machine that built it (machine unknown), or a new build (gated: "no new FPGA runs"),
  or a synthesized-only estimate (weaker, ESTIMATE-class, not a routed tool number).
- **w3070 unreachable right now**: `ssh t27ssh@pangolin.reactotron.ru:22022` →
  "Connection timed out during banner exchange". Disk/OS state unknown this session.
- **givel-vps (root@130.17.9.230) reachable**: Ubuntu, kernel 6.8.0-147, x86_64,
  `/` = 119G total, **19G free (84% used)** — smaller than the ~20–30 GB installer
  alone; Vivado Artix-7-only install does not fit without cleanup. No Xilinx dirs,
  no vivado in PATH.

T1 status: SELECTED, approvals obtained (install yes / local no), execution NOT
started — blocked on (a) routed checkpoint location and (b) a host that fits.
Cheapest first slice when resumed: locate the original Vivado project/.dcp (likely
on the machine that produced the shipped .bit), then install on w3070 or a cleaned VPS.

## ORDER T1_CHECKPOINT_DECISION — SELECTED: «checkpoint нет» (2026-11-25)

Not "lost" — **it never existed**. Provenance (both from committed evidence):
`ax7203_build_report.json` method line — the shipped bitstream was routed by
**openXC7/nextpnr-xilinx on the GPU box** (`bbaexport.py xc7a200tfbg484-2` → bbasm
chipdb); G17 — **Vivado was unavailable (AMD account login wall)**, "no vendor
timing/power report exists". A Vivado routed `.dcp` for this design was therefore
never produced on any host. Options re-derived honestly:

- **A «dcp on w3070» — dead as formulated.** What exists on the GPU box is the
  openXC7 flow, whose Fmax output is already WITHDRAWN as placement noise.
- **B (synthesized-only ESTIMATE)** — viable input exists: committed
  `evidence/codesign/ternary_mac_synth.v`. Still requires the Vivado WebPACK
  installer (AMD login = owner-side download) AND host disk (VPS has 19G free <
  ~20–30G installer; needs cleanup or another host). Output honestly ESTIMATE-class.
- **C (new FPGA build)** — RTL is committed (`rtl/ternary_mac_demo_top.v`); a Vivado
  rebuild is a NEW FPGA build → separate gate. It yields routed numbers for the same
  design (same two netlist-verified defects ride along and stay disclosed).

Common unblock for B and C (single action, cheapest-first): **owner downloads the
Vivado ML Standard WebPACK installer for the chosen host** (AMD login is not
agent-doable), then host decision (w3070 Windows / cleaned VPS Linux). B runs
immediately after install; C additionally needs the explicit new-build approval.
Until then T1 stays SELECTED-but-parked. No install performed on any host (none
fits today: w3070 closed-connection on retry, VPS disk short).

## ORDER T1_INSTALL_AND_RUN — progress log (2026-11-25)

- **VPS cleanup executed (owner-approved "Full cleanup ~17.6G")**: docker image prune
  (dangling 1.047GB + unused-extra 638MB) + approved caches (/root/.cache, /root/.npm,
  /tmp/hslm, /tmp/agent-work, /opt/zig*.tar.xz). Result: **19G → 29G free** (+10G).
  HONEST SHORTFALL vs the ~17.6G estimate: `docker system df` "reclaimable 12.46GB"
  turned out to be mostly container-backed image layers — docker itself refused to
  release them (all 9 running services intact and healthy after cleanup, verified).
- **Official Vivado disk requirements NOT yet confirmed**: docs.amd.com is a JS
  portal (no static text), legacy UG973 PDF URL dead (HTML redirect stub). Working
  figure — **ESTIMATE ~35–40GB installed for Vivado ML Standard + Artix-7 only**,
  plus ~11GB-class single-file download if the offline package is used. VPS 29G is
  therefore LIKELY SHORT; definitive numbers come from the web-installer's component
  selection screen or the docs page (needs BrowserOS).
- **w3070**: still down (3 probes: banner timeout ×2, connection closed ×1). Its
  disk state unknown; it remains the cleanest host (established openXC7 build box).
- **Download path**: AMD wall confirmed (301 → account.amd.com). BrowserOS neo MCP
  is NOT connected to this session yet — owner to start BrowserOS and connect the
  agent in cockpit. After connect: read exact UG973 requirements, download the
  Web installer (small) or single-file (large) via the signed-in AMD session.
- INSTALL: not started. B ESTIMATE: not run. C gate: not requested (per ORDER —
  only after B). No Mac install (staging Mac has 43G free, used only for file relay).
