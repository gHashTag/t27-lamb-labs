# Open-source engagement protocol (ONE SHOT block 8)

**Status: PREPARED, NOT EXECUTED.** This file is the procedure that will be run when Lamb Labs
releases an open model. Nothing in it has been executed, and no open-source release has been
observed yet.

## Trigger

This protocol activates when a Lamb Labs open model appears with:
- a public model card, and
- a license that permits reproduction and derivative publication.

Until then the status is `WAITING`.

## Step 1 - read and record the licence and model card

Before anything else, record:

| Field | Value |
|---|---|
| Repository / model URL | (filled at execution time) |
| Licence name and version | (filled at execution time) |
| Permits redistribution? | yes / no |
| Permits commercial use? | yes / no |
| Permits derivative models? | yes / no |
| Attribution requirement | (verbatim) |
| Model card claims to reproduce | (verbatim list) |
| Model card claims to NOT reproduce | (verbatim list) |

**If the licence forbids redistribution or derivative publication, this protocol stops here.**
The ternary experiment may still be run privately, but nothing may be published.

## Step 2 - reproduce the baseline on CPU or GPU

Run the released model through the same harness used for the ternary experiments:

1. Load the released checkpoint.
2. Run the reference inference path (CPU first; GPU if a CUDA build is available).
3. Record: tokens/sec, latency distribution (p50/p95), peak memory, and the output token ids
   for a fixed seed and a fixed prompt set.
4. Hash every artifact (checkpoint, prompt set, output log).

The recorded outputs are the **golden** that the ternary experiment must be compared against.

## Step 3 - ternary quantisation experiment

Apply the same quantisation recipe that this repository already uses:

| Parameter | Value |
|---|---|
| Weight quantisation | ternary {-1, 0, +1} |
| Weight encoding | 2-bit (01=+1, 10=-1, 00/11=0) |
| Activation width | 8-bit (ACT_BITS) |
| KV quantisation | sign + QUANT_W magnitude bits |
| Lossless rule | QUANT_W >= ACT_BITS |

Sweep at minimum: `ACT_BITS` in {4, 6, 8} and `QUANT_W` in {4, 6, 8}, and record for each point:

- output agreement rate against the golden (exact token match, and edit distance for the rest)
- the quality metric used in this repository (relative error against a full-precision golden)
- resource cost on AX7203 (LUT/FF/BRAM/DSP via the same yosys flow)
- DRAM reads per token

## Step 4 - publish with the same evidence protocol

The publication MUST reuse the repository's existing structure:

- `evidence/<experiment>/` with the raw logs
- `ARTIFACT_HASHES.txt` with a SHA256 for every artifact
- a JSON report separating MEASURED / ESTIMATED / TARGET
- the validator (`benchmark/validate_benchmark.py`) extended with the new states

Publication format: an issue, a discussion, or a pull request in the released repository -
whichever the project's own contribution rules allow. **No claim without an artifact.**

## Step 5 - what must NOT be said

- No production-readiness claim.
- No parity claim against the Lamb Labs MPU or Larry.
- No "TinyLlama fully on Kria".
- No tokens/sec, J/token or energy figure that is not backed by a hashed artifact.
- No comparison to a 27B-class MPU beyond the normalised per-parameter label:
  *edge-scale prototype comparison, not performance parity with 27B-class MPU*.

## Step 6 - outreach, with artifacts

The outreach message links the artefacts; it does not assert performance.

```text
Subject: Measured ternary MAC variance study on Kria-class FPGA

Hi Niki,

I built a reproducible ternary MAC variance study
on a Kria-class FPGA, focused on the relationship between
quantization choices, FPGA resource use, latency,
power, tokens/sec, and measured J/token.

Artifacts:
- [link to README]
- [link to raw measurement logs]
- [link to bitstream/build evidence]

Current honest scope:
[edge-scale ternary MAC prototype,
not a full LLM and not an MPU parity claim].

Question:
For your MPU co-design loop, which interface
would be most useful for an external FPGA prototype:
a machine-readable architecture/quantization benchmark,
or a reproducible J/token + DRAM-reads-per-token case study?

Would a 15-minute technical conversation be useful?
```

Contact: contact@lamb-labs.com

## Known gap in this protocol

Step 3 assumes the released model can be loaded into the local harness. If the released artefact
uses a custom architecture or a non-public format, step 3 becomes a re-implementation task and
the protocol must be amended before running. This is recorded rather than glossed over.
