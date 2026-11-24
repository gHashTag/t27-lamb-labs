# Provenance — GF16 dot4 PTX artifacts

Every byte in this bundle traces to a commit, a command or a measured output.
Labels: **MEASURED** (observed in this run), **REUSED** (artifact carried over from an earlier,
already-hashed run and re-verified here by hash comparison).

## 1. Vendored specification sources

The two lane specs were taken from the canonical upstream t27 commit and copied into this
repository byte-for-byte; the numeric dependency was taken from upstream `master`.

| File in this repo | Upstream commit | Upstream path | sha256 (MEASURED) |
|---|---|---|---|
| `specs/igla/coder/gf16_dot4_ptx.t27` | `44c8c62a73d689f20c713a0e1da563825a0361ee` | `specs/igla/coder/gf16_dot4_ptx.t27` | `dd74e62584a0aa8896eaf125a43828c593a4b11038b2445590d11df42e227914` |
| `specs/igla/coder/ptx_emit.t27` | `44c8c62a73d689f20c713a0e1da563825a0361ee` | `specs/igla/coder/ptx_emit.t27` | `4e18124466c59291836dc1c48367f13a3b6ece913c5551f78cb182b93ce0eaf5` |
| `specs/numeric/gf16.t27` | `8c6395e9dc8f35fc4f5b622a86107bd65b8b703f` | `specs/numeric/gf16.t27` | `b6324424a887cd93b697732f90445861850fa8d36b38098eab2d578b2c26d532` |

`44c8c62a73d689f20c713a0e1da563825a0361ee`
— *feat(igla/coder): GF16 dot4 PTX emitter and w3070 access spec (M6 steps 1-8)*,
branch `claude/gpu-desktop-client-port-d4b13e`, refs #14143, #14155.
It is the commit that carries both requested fixes: `#14150` (golden π / sum constants) and
`#14149` (emitter header issue reference).

`77802e31457293e8c4b4c22e7dff924268d17bcd`
— *PTX: the 12 emitter helpers live once in ptx_emit.t27 and both kernel specs use it
(Closes #10947) (#14148)* — the anchor for the `#10947` citation that `#14149` asks for.

`8c6395e9dc8f35fc4f5b622a86107bd65b8b703f`
— upstream `master` tip touching `specs/numeric/gf16.t27`
(*specs(numeric,t27os): close coverage gaps — negative-control tests + re-seal*);
it provides `gf16_decode_to_f32`, the numeric SSOT used by the kernel spec.

Copies inside this bundle (`spec/…`) are byte-identical to the repository copies
(`cmp` exit 0) and therefore carry the same hashes as the table above.

### Known upstream discrepancies (recorded, resolved by measurement)

* A stale copy of the emitter spec carrying the old `#10930` citation exists in an unrelated
  worktree (`.claude/worktrees/strange-varahamihira-ce2fa9`) and in older local checkouts.
  It was **not** used. The copy used here (from `44c8c62a73` and from the remote host) cites
  `#10947`, satisfying `#14149`.
* The `[v; N]` array-repeat literal is avoided in these specs via a `fill_u16` helper loop
  ("Stands in for the [v; N] literal until t27#14155 lands"), because the Zig 0.16/0.17
  lowering of array-repeat literals is defective (`t27#14155`). The workaround is inside the
  vendored source and is not a local modification of it.

## 2. Emitted and assembled artifacts

| Artifact | Origin | Status | sha256 |
|---|---|---|---|
| `gf16_dot4.ptx` | **MEASURED** — emitted in this run, local `t27c gen-text … --fn emit_ptx` (Zig 0.17.1) | fresh, this run | `b9a79404bb5c06095fa1b831ad45f3bf1eef2378b74702bad1615237534d5e51` |
| `gf16_dot4.cubin` | **MEASURED** — assembled in this run on win11-3070, `ptxas -arch=sm_86` (CUDA 12.4 V12.4.131) | fresh, this run | `35e07b5f2413ccfb63b64572c3bd08c6587da8a288254b1ccfa2eb1f1ff987cc` |
| `ptxas_verbose.log` | **MEASURED** — `ptxas -arch=sm_86 -v` in this run | fresh, this run | see `ARTIFACT_HASHES.txt` |
| `ptxas_stdout.log` | **MEASURED** — raw stdout/stderr of the plain `ptxas` run (empty ⇒ no diagnostics) | fresh, this run | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `cuobjdump_sass.log` | **MEASURED** — `cuobjdump -sass` of this run's cubin | fresh, this run | see `ARTIFACT_HASHES.txt` |
| `test_report_*.txt`, `t27c_test_*.txt` | **MEASURED** — test runs in this run | fresh, this run | see `ARTIFACT_HASHES.txt` |

### Cross-checks against previously attested artifacts (REUSED, re-verified)

The earlier golden-chain run (upstream `artifacts/golden-chain/2026-11-19-night/research_tools/`)
contains `gf16_dot4_emitted.ptx` (sha256 `b9a79404…`) and `gf16_dot4_sm86.cubin`
(sha256 `35e07b5f…`). In this run the *fresh* outputs hash **identically** to those two
attested files:

* local fresh PTX `b9a79404…` == attested golden PTX `b9a79404…` (`cmp` exit 0);
* fresh host cubin `35e07b5f…` == attested golden cubin `35e07b5f…`;
* host-side independent re-emission `b9a79404…` and re-assembly `35e07b5f…` — same bytes on a
  different host with a different Zig version (0.16.0).

The golden files themselves are **not** copied into this bundle; only this run's outputs are,
and their identity with the golden ones is asserted by the hashes above.

## 3. Toolchain provenance

| Tool | Identity | Where |
|---|---|---|
| local `t27c` | `t27c 0.5.2`, sha256 `5da927dffa5eeaad195243cd809e34d316279c614065c8af788c52a256c4ff40` | `/Users/playra/.local/bin/t27c` (identical bytes to `/Users/playra/t27/target/release/t27c`) |
| local `zig` | `0.17.1` | `/opt/homebrew/bin/zig` |
| host `t27c` | `t27c 0.5.2`, sha256 `5785e3ca7b021fc51f1fed9f67dbe6a8ff8a6b99b2862ddf35838c9c44a91cce` | `~/t27os/bin/t27c` → `~/t27os/src/target/release/t27c` |
| host `zig` | `0.16.0` | `~/t27os/bin/zig` → `~/t27os/zig-x86_64-linux-0.16.0/zig` |
| host `ptxas` | CUDA 12.4, V12.4.131 | CUDA toolkit on win11-3070 |

The local and host `t27c` binaries are **different builds** (different sha256) — which is why
the host-side re-emission in §2 is an independent check rather than a repeat.

## 4. Repository state at commit time

* Worktree branch: `dsh-5344b40f-4225`; base HEAD before this lane's commit: `a7ef7518784e61ad813ffbb69ea9cf83306f4f39`.
* Only lane-owned paths are staged (explicit pathspecs): `specs/igla/coder/gf16_dot4_ptx.t27`,
  `specs/igla/coder/ptx_emit.t27`, `specs/numeric/gf16.t27`, `artifacts/gf16-dot4-ptx/**`,
  `scripts/manifest.py`, `ARTIFACT_MANIFEST.txt`, `ARTIFACT_HASHES.txt`.
* `.scratch/` (session scratch) stays untracked and is never committed.
* The upstream t27 checkout `/Users/playra/t27` and the remote `~/t27os/src` were **read only**;
  no file in either was modified by this lane.
