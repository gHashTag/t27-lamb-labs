#!/usr/bin/env python3
"""draft_releases.py — mechanically draft GitHub Releases for the preserved v0.1.x line.

Nothing hand-transcribed: every note = tag subject + tag message + full
ARTIFACT_MANIFEST.txt as of that tag (the sha256 list by construction) +
standard rollback/provenance trailer. Releases are created as DRAFTS
(reversible; publishing is the owner's one-click decision). No binary assets
are attached, so no asset can carry secrets.

Prereq: `gh auth ok` on gHashTag/t27-lamb-labs; tags already on remote.
Exit non-zero on any failure. Evidence: evidence/releases/.
"""
import hashlib
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLUG = "gHashTag/t27-lamb-labs"
OUTDIR = os.path.join(REPO, "releases", "notes")
EVDIR = os.path.join(REPO, "evidence", "releases")

TRAILER = """
---
- **Commit:** {sha}
- **Rollback:** see `docs/ROLLBACK_RECOVERY.md` (repo checkout: `git checkout {tag}`; FPGA artifacts reload over JTAG SRAM-only). Artifact integrity: verify each file above with `sha256sum -c` on the manifest at this tag.
- **Provenance:** this tag's numbers carry the provenance labels of its own date. Where later measurement withdrew a claim (dead ring oscillator, tok/s, two frequency claims), the withdrawing tags `v0.1.11`–`v0.1.14` and `evidence/clock_probe/shipped_bitstream_analysis.log` are authoritative — withdrawn claims stay recorded, never silently deleted.
- **Assets:** none. Notes-only release; no binary asset can carry secrets.
- **Generated:** `scripts/draft_releases.py` (mechanical composition, no hand edits), 2026-11-23.
"""

def git(*args):
    r = subprocess.run(["git"] + list(args), capture_output=True, text=True, cwd=REPO)
    if r.returncode != 0:
        fail("git %s: %s" % (" ".join(args[:3]), r.stderr.strip()[:200]))
    return r.stdout

def fail(msg):
    print("FAIL: " + msg)
    sys.exit(1)

def main():
    os.makedirs(OUTDIR, exist_ok=True)
    os.makedirs(EVDIR, exist_ok=True)
    tags = [l.split()[0] for l in git("for-each-ref", "refs/tags",
            "--format=%(refname:short)").splitlines()]
    if len(tags) != 19:
        fail("expected 19 tags, got %d" % len(tags))
    log, created = [], []
    for tag in sorted(tags):
        commit = git("rev-parse", tag + "^{}").strip()
        subject = git("for-each-ref", "refs/tags/" + tag,
                      "--format=%(contents:subject)").strip()
        tagmsg = git("tag", "-l", tag, "--format=%(contents)").strip()
        body = tagmsg if tagmsg and tagmsg != subject else ""
        manifest = None
        for cand in ("ARTIFACT_MANIFEST.txt", "docs/ARTIFACT_MANIFEST.txt"):
            r = subprocess.run(["git", "show", tag + ":" + cand],
                               capture_output=True, text=True, cwd=REPO)
            if r.returncode == 0:
                manifest = r.stdout.rstrip() + "\n"
                break
        if manifest:
            mblock = ("## Artifact manifest at this tag (%d sha256 rows)\n\n```text\n%s```\n"
                      % (sum(1 for l in manifest.splitlines()
                             if len(l) >= 66 and l[64:66] == "  "), manifest))
        else:
            mblock = ("## Artifact manifest at this tag\n\n"
                      "`ARTIFACT_MANIFEST.txt` did not exist yet at this tag "
                      "(introduced later in the line); artifact sha256 coverage "
                      "for this tag is partial — see later tags for the full manifest.\n\n")
        note = ("# %s\n\n%s%s\n\n%s%s") % (
            subject, body + "\n\n" if body else "",
            commit, mblock, TRAILER.format(sha=commit, tag=tag))
        path = os.path.join(OUTDIR, "%s.md" % tag)
        with open(path, "w") as f:
            f.write(note)
        gh = subprocess.run(["gh", "release", "create", tag, "--repo", SLUG,
                             "--title", subject, "--notes-file", path, "--draft"],
                            capture_output=True, text=True, cwd=REPO)
        if gh.returncode != 0 and "already_exists" not in gh.stderr:
            fail("gh release create %s: %s %s" % (tag, gh.stdout[-200:], gh.stderr[-200:]))
        url = gh.stdout.strip() or "already-exists"
        created.append(tag)
        nrows = mblock.count(" sha256") or mblock.count("  ")
        log.append("drafted %s -> %s (note sha256: %s)"
                   % (tag, url, hashlib.sha256(note.encode()).hexdigest()[:16]))
        print(log[-1])
    # evidence record
    chk = subprocess.run(["gh", "release", "list", "--repo", SLUG, "--limit", "100"],
                         capture_output=True, text=True, cwd=REPO)
    log.append("gh release list: %d rows\n%s" % (len(chk.stdout.strip().splitlines()), chk.stdout))
    blob = json.dumps({"date": "2026-11-23", "drafted": created, "log": log}, indent=1)
    with open(os.path.join(EVDIR, "draft_releases_2026-11-23.json"), "w") as f:
        f.write(blob + "\nSHA256_SELF: %s\n"
                % hashlib.sha256(blob.encode()).hexdigest())
    print("WROTE evidence/releases/draft_releases_2026-11-23.json")
    return 0

if __name__ == "__main__":
    sys.exit(main())
