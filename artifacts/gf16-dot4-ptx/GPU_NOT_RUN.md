# GPU_NOT_RUN — GF16 dot4 PTX lane

**Statement of record for this artifact bundle.**

The GF16 dot4 kernel in this bundle was **compiled and assembled, but never executed on a GPU.**

What was done:

* `t27c test-report` on the kernel spec and the emitter spec (host-side, CPU only) — 10/10 and 14/14.
* `t27c gen-text … --fn emit_ptx` — PTX text produced from the spec (host-side, CPU only).
* `ptxas -arch=sm_86` on win11-3070 — offline assembly of that PTX into a cubin/ELF.
* `cuobjdump -sass` — static disassembly listing of the assembled code.

What was **not** done, deliberately:

* No kernel launch, no `cudaLaunchKernel`, no driver API call.
* No `t27c ptx-run` and no `t27c ptx-run-gf16` (neither is a shipped execution path here; the
  host build exposes them as validation commands only, and they were not invoked).
* No host↔device data transfer, no output tensor, no numerical parity check against a GPU run.
* No timing, throughput, occupancy, latency, power or energy measurement.
* No training of any kind (`TRAINING_APPROVED=false`; no training step was started or altered).
* No tapeout/FPGA/silicon statement is implied by this bundle.

GPU inventory was *listed* on the remote host (`nvidia-smi -L` → 2× NVIDIA GeForce RTX 3070
Laptop GPU) purely to document where the assembly happened. Listing is not execution.

Consequence for readers: the hashes in `ARTIFACT_HASHES.txt` attest that **these exact bytes**
were produced by the recorded commands. They do **not** attest that the kernel computes the
expected sum on a GPU. A GPU-result claim requires a separate, recorded execution run, which
this lane did not perform.

Verdict label for this lane: **ASSEMBLED_AND_HASHED / NOT_EXECUTED**.
