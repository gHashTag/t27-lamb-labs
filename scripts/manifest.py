#!/usr/bin/env python3
"""Write the portfolio artifact manifest: every deliverable with its SHA256.

The manifest is the reproducibility index. A reviewer can hash any artifact and compare it
against the manifest, and a reviewer can see at a glance which files the portfolio consists of.

Usage: python3 scripts/manifest.py [output_path]
"""
import hashlib, os, sys, json, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Directories whose contents are the portfolio's deliverable artifacts.
# conformance, releases, rtl, specs arrive with the hardware-lane merge; specs also
# exists in this lane already (numeric + igla coder specs). Dry run 2026-11-25 showed
# 292 tracked files outside the index without this extension.
INCLUDE_DIRS = ["target", "benchmark", "engagement", "evidence", "bitstream", "docs", "scripts",
                "artifacts", "conformance", "releases", "rtl", "specs"]
# Files at the repository root that are part of the deliverable.
INCLUDE_ROOT_FILES = ["README.md", "ARTIFACT_HASHES.txt", "EXECUTE_NOW.md", "t27c_lite.py"]
# The root hash index cannot contain its own hash; the manifest (written after it) does.
HASHES_SELF = "ARTIFACT_HASHES.txt"
# Directories that are toolchain copies or scratch, not artifacts.
# (specs/fpga was previously excluded by name; removed 2026-11-25 so specs/fpga/*.t27
# land in the index — no nested specs|fpga dirs exist under the include trees.)
EXCLUDE_DIRS = {".git", "toolchain", "__pycache__", ".pytest_cache"}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def collect():
    out = []
    for name in INCLUDE_ROOT_FILES:
        p = os.path.join(ROOT, name)
        if os.path.isfile(p):
            out.append(name)
    for d in INCLUDE_DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [x for x in dirnames if x not in EXCLUDE_DIRS]
            for fn in sorted(filenames):
                if fn == ".DS_Store":
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fn), ROOT)
                out.append(rel)
    return sorted(set(out))


def write_hashes_index(files, dest):
    """Write the repo-root hash index: one "<sha256>  <repo-relative path>" line per file.

    The index excludes itself (a file cannot carry its own hash); ARTIFACT_MANIFEST.txt does
    include it, so the pair is cross-checkable.
    """
    lines = [
        "# t27-lamb-labs artifact hashes (sha256, repo-relative)",
        "# Machine-readable twin of ARTIFACT_MANIFEST.txt; excludes itself by construction.",
        "# Regenerate: python3 scripts/manifest.py",
    ]
    counted = 0
    for rel in files:
        if rel == HASHES_SELF:
            continue
        p = os.path.join(ROOT, rel)
        if os.path.isfile(p):
            lines.append(f"{sha256(p)}  {rel}")
            counted += 1
    lines.append(f"# {counted} files")
    with open(dest, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {dest}: {counted} files")


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "ARTIFACT_MANIFEST.txt")
    hashes_dest = os.path.join(ROOT, HASHES_SELF)

    # 1) hash index first, so that the manifest can hash it in turn
    write_hashes_index(collect(), hashes_dest)

    # 2) manifest over the same file set (now including the freshly written hash index)
    files = collect()
    lines = []
    lines.append("# t27-lamb-labs artifact manifest")
    lines.append("# Every deliverable file with its SHA256. Regenerate: python3 scripts/manifest.py")
    lines.append(f"# {len(files)} files")
    lines.append("")
    for rel in files:
        p = os.path.join(ROOT, rel)
        if os.path.isfile(p):
            lines.append(f"{sha256(p)}  {rel}")
    with open(dest, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {dest}: {len(files)} files")

    # also emit the git commit for traceability
    try:
        commit = subprocess.check_output(["git", "-C", ROOT, "rev-parse", "HEAD"], text=True).strip()
        print(f"git HEAD: {commit}")
    except Exception:
        pass


if __name__ == "__main__":
    main()
