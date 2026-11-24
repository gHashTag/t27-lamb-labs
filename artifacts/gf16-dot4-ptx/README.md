# GF16 dot4 PTX — assembled, hashed artifacts

Lane: `gf16-dot4-ptx` · Worktree: `.agents/worktrees/dsh-5344b40f-4225` (branch `dsh-5344b40f-4225`)
Run window (UTC): 2026-11-23T07:15Z … 2026-11-23T07:36Z (remote host), 2026-11-23T07:1x–07:3xZ (local)
Scope: finish the GF16 dot4 PTX path up to **assembled, hashed PTX artifacts**.

> **NO GPU RESULT IS CLAIMED.** Nothing was executed on a GPU. No kernel launch, no `ptx-run`,
> no `ptx-run-gf16`, no timing, no throughput, no power, no parity, no tapeout-readiness claim.
> `ptxas` is an **offline assembler**: a successful assembly proves the PTX is *accepted* by the
> CUDA 12.4 assembler for `sm_86` and nothing more.

---

## 1. STATUS

| Item | State | Evidence |
|---|---|---|
| Spec sources vendored into this repo | DONE | `spec/igla/coder/gf16_dot4_ptx.t27`, `spec/igla/coder/ptx_emit.t27`, `spec/numeric/gf16.t27` |
| `#14150` golden constants (π = 3.140625, sum = 10.4765625) | CONFIRMED in source | §3 |
| `#14149` emitter header cites `#10947` | CONFIRMED in source | §3 |
| Spec tests (`t27c test-report`, import-resolving) | **10/10** + **14/14**, exit 0 | `test_report_*.txt` |
| PTX emission (`t27c gen-text --fn emit_ptx`) | exit 0, 4952 B | `gf16_dot4.ptx` |
| PTX assembly (`ptxas -arch=sm_86`) on win11-3070 | **exit 0**, 4648 B ELF | `ptxas_verbose.log`, `gf16_dot4.cubin` |
| Independent host-side re-emission + re-assembly | byte-identical PTX **and** cubin | §2.3 |
| Hashes, provenance, command transcript | DONE | `ARTIFACT_HASHES.txt`, `PROVENANCE.md`, `command_transcript.txt` |
| GPU execution | **NOT RUN — deliberately out of scope** | `GPU_NOT_RUN.md` |

---

## 2. MEASURED results

All values below were produced by the commands in `command_transcript.txt` during this run.
Labels: **MEASURED** = observed output of a recorded command. Nothing here is estimated.

### 2.1 Toolchains (MEASURED)

| Tool | Location | Version / identity |
|---|---|---|
| `t27c` (local, macOS arm64) | `/Users/playra/.local/bin/t27c` | `t27c 0.5.2`, sha256 `5da927dffa5eeaad195243cd809e34d316279c614065c8af788c52a256c4ff40` |
| `t27c` (source build, local) | `/Users/playra/t27/target/release/t27c` | same sha256 `5da927df…` (identical binary) |
| `zig` (local) | `/opt/homebrew/bin/zig` | `0.17.1` |
| `t27c` (remote, win11-3070 / WSL2) | `~/t27os/bin/t27c` | `t27c 0.5.2`, sha256 `5785e3ca7b021fc51f1fed9f67dbe6a8ff8a6b99b2862ddf35838c9c44a91cce` |
| `zig` (remote) | `~/t27os/bin/zig` | `0.16.0` |
| `ptxas` (remote) | CUDA toolkit on host | `release 12.4, V12.4.131` |
| `cuobjdump` (remote) | `/usr/bin/cuobjdump` | used for SASS listing only |

Remote host: `Linux win11-3070 6.18.58.1-microsoft-standard-WSL2 … x86_64`.
GPU inventory was *listed* (`nvidia-smi -L` → 2× NVIDIA GeForce RTX 3070 Laptop GPU) for context only;
**no GPU command was executed**.

### 2.2 Spec tests (MEASURED)

`t27c test-report` is the import-resolving test path (`bootstrap/src/test_report.rs:521` calls
`use_resolve::resolve` before compiling):

```
t27c test-report specs/igla/coder/gf16_dot4_ptx.t27   -> exit 0   tests 10 / pass 10 / FAIL 0 / invariants 1
t27c test-report specs/igla/coder/ptx_emit.t27        -> exit 0   tests 14 / pass 14 / FAIL 0 / invariants 0
```

Full output: `test_report_gf16_dot4_ptx.txt`, `test_report_ptx_emit.txt`.

`ptx_emit.t27` is self-contained, so the plain `t27c test` path also passes it (14/14, exit 0) —
see `t27c_test_ptx_emit.txt`.

`gf16_dot4_ptx.t27` imports two other modules (`use igla::coder::ptx_emit;`, `use numeric::gf16;`).
The plain `t27c test` code path compiles the file **without** resolving cross-module `use`
(generated Zig then references undeclared `put_s`, `ins`, `at_text`, `count_text`, `fill_u8`,
`gf16_decode_to_f32`, `emit_op3`), so that path cannot validate the kernel spec. This is a
**tooling limitation of `t27c test`, not a defect of the spec** — the same spec passes 10/10
through `t27c test-report`, which does resolve imports. Raw output kept verbatim in
`t27c_test_gf16_dot4_ptx.txt` (note: that command still exits 0 despite the compile errors in its
output, so the exit code alone must not be used as the verdict — the report output must be read).

### 2.3 PTX emission and assembly (MEASURED)

Local emission (macOS, Zig 0.17.1):

```
t27c gen-text specs/igla/coder/gf16_dot4_ptx.t27 --fn emit_ptx -o .scratch/gf16/gf16_dot4_local.ptx
-> exit 0, "gen-text: wrote …", 4952 bytes
sha256 = b9a79404bb5c06095fa1b831ad45f3bf1eef2378b74702bad1615237534d5e51
```

This is byte-identical (`cmp` → identical) to the previously attested golden PTX
`artifacts/golden-chain/2026-11-19-night/research_tools/gf16_dot4_emitted.ptx`
(same sha256 `b9a79404…`), i.e. the emission is reproducible from the vendored spec.

Remote assembly (win11-3070, WSL2, CUDA 12.4):

```
ptxas -arch=sm_86 out/gf16_dot4_local.ptx -o out/gf16_dot4.cubin
-> ptxas_exit=0
   cubin_bytes=4648
   sha256 = 35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc
   file   = ELF 64-bit LSB executable, NVIDIA CUDA architecture,, statically linked, not stripped
```

The cubin is byte-identical to the previously attested golden cubin
`…/golden-chain/2026-11-19-night/research_tools/gf16_dot4_sm86.cubin` (same sha256 `35e07b5f…`).

`ptxas -arch=sm_86 -v` (raw: `ptxas_verbose.log`):

```
ptxas info    : 0 bytes gmem
ptxas info    : Compiling entry function 'gf16_dot4' for 'sm_86'
ptxas info    : Function properties for gf16_dot4
    0 bytes stack frame, 0 bytes spill stores, 0 bytes spill loads
ptxas info    : Used 22 registers, 380 bytes cmem[0]
```

`cuobjdump -sass` (raw: `cuobjdump_sass.log`, 279 lines) shows `code for sm_86`,
`Function : gf16_dot4`, headerflags `EF_CUDA_SM86`.

Independent host-side re-emission and re-assembly (remote `t27c` + remote Zig 0.16.0, i.e. a
different compiler host and a different Zig version than the local run):

```
t27c gen-text specs/igla/coder/gf16_dot4_ptx.t27 --fn emit_ptx -o out/gf16_dot4_host.ptx
-> exit 0, 4952 bytes, sha256 b9a79404…   HOST_REEMIT_MATCHES_LOCAL=YES
ptxas -arch=sm_86 out/gf16_dot4_host.ptx -o out/gf16_dot4_host.cubin
-> exit 0, sha256 35e07b5f…  (identical cubin)
```

So: **the same spec, on two different hosts and two different Zig versions, yields the same PTX
bytes and the same cubin bytes.** This is the reproducibility result of this lane — an artifact
result, not a GPU result.

### 2.4 Isolation checks (MEASURED)

* All remote writes were confined to the new lane scratch tree
  `~/t27os/lanes/gf16-dot4-ptx-20261123T071500Z/`.
* The host checkout `~/t27os/src` was **not modified**: `git status --porcelain` after the run is
  identical to the pre-run snapshot (pre-existing dirty files only, `HEAD f1d68fb4af89ce5d46abbc0cf262d501a8d651d6`).
* The pre-existing host artifacts `~/t27os/out/gf16_dot4.ptx` (`b9a79404…`) and
  `~/t27os/out/gf16_dot4.cubin` (`35e07b5f…`) were read only; their hashes are unchanged.

---

## 3. Requested fixes — confirmed in the source of record

`#14150` (stale GF16 golden constants) — `spec/igla/coder/gf16_dot4_ptx.t27`:

```
236: // a = pos_one x4; b = e (0x40B8 = 2.71875), pi (0x4124 = 3.140625), phi (0x3F3C = 1.6171875),
237: // three (0x4100). Sum = 10.4765625, exact in f32.
243:     b[1] = 0x4124;
246:     assert dot4_golden(&a, &b, 0) == 10.4765625;
```

No occurrence of the stale values `3.12890625` / `10.46484375` remains in the file.

`#14149` (emitter header cited the wrong issue) — `spec/igla/coder/ptx_emit.t27`:

```
3: ; Issue #10947 (duplicate-bodies, 12 helpers copied between ternary_gemm_ptx.t27 and hslm_bwd_ptx.t27).
```

No `#10930` citation remains in that file.

---

## 4. Deviations from the task text (recorded, not silent)

| Task text | What was actually used | Why |
|---|---|---|
| `specs/igla-coder/gf16dot4ptx.t27`, `specs/igla-coder/ptxemit.t27` | `specs/igla/coder/gf16_dot4_ptx.t27`, `specs/igla/coder/ptx_emit.t27` | The underscored, nested paths are the canonical ones (module names `igla-coder-gf16-dot4-ptx`, `igla-coder-ptx-emit`). The task-text paths do not exist in the upstream tree. |
| `t27c --features cuda` | `t27c gen-text … --fn emit_ptx` (local **and** remote), then `ptxas` | Neither t27c build exposes a `cuda`/`--features` entry (local sha `5da927df…`, host sha `5785e3ca…`; `--help` lists no such command). PTX emission therefore goes through the shipped `gen-text` path. |
| `ptxas -arch=sm86` | `ptxas -arch=sm_86` | MEASURED: CUDA 12.4 rejects `sm86` (`fatal : Value 'sm86' is not defined for option 'gpu-name'`, exit 255) and accepts `sm_86` (exit 0). |
| `t27c test <file>` as the gate | `t27c test-report <file>` as the gate (plus `t27c test` recorded verbatim) | `t27c test` does not resolve cross-module `use`; see §2.2. Both commands and their outputs are kept. |

---

## 5. What is explicitly NOT claimed

* **No GPU result.** The kernel was never launched; no output tensor was produced; no
  numerical parity against a GPU run exists in this bundle.
* **No performance data.** No latency, throughput, tokens/s, occupancy, power or energy numbers.
  `ptxas` register/stack numbers describe an offline compile, not runtime behaviour.
* **No training.** `TRAINING_APPROVED=false`; no training step was started or modified.
* **No tapeout-readiness claim** and no FPGA/silicon statement follows from PTX assembly.
* `cuobjdump` output is an SASS listing of the assembled code, not execution evidence.

---

## 6. Reproduction

```bash
# 1) tests (import-resolving path)
t27c test-report specs/igla/coder/gf16_dot4_ptx.t27     # expect exit 0, 10/10
t27c test-report specs/igla/coder/ptx_emit.t27          # expect exit 0, 14/14

# 2) emit PTX
t27c gen-text specs/igla/coder/gf16_dot4_ptx.t27 --fn emit_ptx -o gf16_dot4.ptx
sha256sum gf16_dot4.ptx        # b9a79404bb5c06095fa1b831ad45f3bf1eef2378b74702bad1615237534d5e51

# 3) assemble (needs CUDA toolkit; use a host with ptxas)
ptxas -arch=sm_86 gf16_dot4.ptx -o gf16_dot4.cubin
sha256sum gf16_dot4.cubin      # 35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc

# 4) verify every artifact hash
cd artifacts/gf16-dot4-ptx && sha256sum -c <(awk '{print $1"  "$2}' ARTIFACT_HASHES.txt)
```

Full command transcript (local + remote, with exit codes): `command_transcript.txt`.

---

## 7. Bundle inventory

| File | What it is |
|---|---|
| `gf16_dot4.ptx` | Emitted PTX (4952 B), sha256 `b9a79404…` |
| `gf16_dot4.cubin` | `ptxas -arch=sm_86` ELF (4648 B), sha256 `35e07b5f…` |
| `ptxas_verbose.log` | Raw `ptxas -v` output (registers / stack / spills) |
| `ptxas_stdout.log` | Raw stdout/stderr of the plain `ptxas` run (empty = no diagnostics) |
| `cuobjdump_sass.log` | Raw SASS listing (`code for sm_86`, `gf16_dot4`) |
| `test_report_gf16_dot4_ptx.txt` | Raw `t27c test-report` output, kernel spec (10/10) |
| `test_report_ptx_emit.txt` | Raw `t27c test-report` output, emitter spec (14/14) |
| `t27c_test_gf16_dot4_ptx.txt` | Raw `t27c test` output for the kernel spec (declaration listing + non-resolving compile attempt) |
| `t27c_test_ptx_emit.txt` | Raw `t27c test` output for the emitter spec (14/14) |
| `command_transcript.txt` | Every command run, with exit codes and key outputs |
| `spec/gf16_dot4_ptx.t27` | Vendored kernel spec (sha256 `dd74e625…`) |
| `spec/ptx_emit.t27` | Vendored emitter spec (sha256 `4e181244…`) |
| `spec/gf16.t27` | Vendored numeric SSOT dependency (sha256 `b6324424…`) |
| `PROVENANCE.md` | Upstream commits and byte-identity of every vendored source |
| `GPU_NOT_RUN.md` | Explicit no-GPU-execution marker |
| `ARTIFACT_HASHES.txt` | sha256 of every bundle file (self excluded) |

`ARTIFACT_HASHES.txt` lists the bundle's own files by name, relative to this directory.
The portfolio-wide index is the repository root `ARTIFACT_MANIFEST.txt` / `ARTIFACT_HASHES.txt`.
