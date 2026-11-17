#!/usr/bin/env python3
"""Compare two folders of snapshot PNGs pixel by pixel, against the list of agreed changes.

    python3 scripts/compare_snapshots.py [--baseline DIR] [--current DIR] [--agreed FILE]
                                         [--base-ref SHA] [--match NAME ...]

The defaults compare build/baseline-snapshots (rendered from the tree before the strength-mode
work) with build/snapshots (what `make snapshots` just rendered). Every image is reported on one
line as `identical`, `changed (agreed)`, `changed (NOT agreed)`, `new` or `removed`. The run fails
(exit 1) when an image outside scripts/snapshot-agreed-changes.txt changed or was removed. A new
image never fails: the strength surfaces are new by design.

Pixels, not bytes, are compared: each PNG is decoded to an uncompressed BMP with `sips`, so two
renders of the same picture match even when their encoders wrote different chunks.

build/ is not committed, so when the baseline folder is missing and --base-ref is given the script
renders the baseline itself: a temporary git worktree at that ref, a Debug build into a temporary
DerivedData, `--snapshot all` into the baseline folder, and the worktree removed afterwards.

--match prints whether each name is covered by the agreed list, using the same matcher as the
comparison, and exits 0.
"""
import argparse
import fnmatch
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_BASELINE = os.path.join(REPO, "build", "baseline-snapshots")
DEFAULT_CURRENT = os.path.join(REPO, "build", "snapshots")
DEFAULT_AGREED = os.path.join(REPO, "scripts", "snapshot-agreed-changes.txt")


def load_agreed(path):
    """One glob per line; blank lines and `#` comments are ignored."""
    patterns = []
    with open(path) as handle:
        for line in handle:
            line = line.split("#", 1)[0].strip()
            if line:
                patterns.append(line)
    return patterns


def is_agreed(name, patterns):
    """A pattern may name the file (`toast.png`) or its surface (`toast`)."""
    stem = name[:-4] if name.endswith(".png") else name
    return any(fnmatch.fnmatchcase(name, p) or fnmatch.fnmatchcase(stem, p) for p in patterns)


def pngs(folder):
    return {name for name in os.listdir(folder) if name.endswith(".png")}


def decoded(path, scratch, tag):
    """The image's pixels as `sips` writes them to a BMP."""
    out = os.path.join(scratch, tag + "-" + os.path.basename(path) + ".bmp")
    subprocess.run(
        ["sips", "-s", "format", "bmp", path, "--out", out],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with open(out, "rb") as handle:
        return handle.read()


def same_pixels(first, second, scratch):
    with open(first, "rb") as a, open(second, "rb") as b:
        if a.read() == b.read():
            return True
    return decoded(first, scratch, "a") == decoded(second, scratch, "b")


def render_baseline(ref, out):
    """Renders the snapshots of `ref` into `out` from a throwaway worktree."""
    temp = tempfile.mkdtemp(prefix="movez-baseline-")
    tree = os.path.join(temp, "tree")
    derived = os.path.join(temp, "DerivedData")
    try:
        subprocess.run(["git", "-C", REPO, "worktree", "add", "--detach", tree, ref], check=True)
        subprocess.run(["xcodegen", "generate", "--spec", "project.yml"], cwd=tree, check=True)
        subprocess.run(
            [
                "xcodebuild", "-project", "movez.xcodeproj", "-scheme", "movez",
                "-configuration", "Debug", "-destination", "platform=macOS",
                "-derivedDataPath", derived, "-quiet", "build",
            ],
            cwd=tree,
            check=True,
        )
        binary = os.path.join(derived, "Build", "Products", "Debug", "movez.app", "Contents", "MacOS", "movez")
        # The render goes into the temp dir and is moved into place only once it succeeds: a
        # partial baseline folder would be taken as complete on the next run, and every surface
        # missing from it would be reported `new`, which never fails.
        staged = os.path.join(temp, "snapshots")
        os.makedirs(staged)
        subprocess.run([binary, "--snapshot", "all", "--out", staged], check=True)
        parent = os.path.dirname(os.path.abspath(out))
        os.makedirs(parent, exist_ok=True)
        shutil.move(staged, out)
    finally:
        subprocess.run(["git", "-C", REPO, "worktree", "remove", "--force", tree], check=False)
        shutil.rmtree(temp, ignore_errors=True)


def compare(baseline, current, patterns):
    """Prints one line per image and returns how many failed."""
    before, after = pngs(baseline), pngs(current)
    counts = {"identical": 0, "changed (agreed)": 0, "changed (NOT agreed)": 0, "new": 0, "removed": 0}
    failures = 0
    scratch = tempfile.mkdtemp(prefix="movez-compare-")
    try:
        for name in sorted(before | after):
            if name not in after:
                status = "removed"
                failures += 1
            elif name not in before:
                status = "new"
            elif same_pixels(os.path.join(baseline, name), os.path.join(current, name), scratch):
                status = "identical"
            elif is_agreed(name, patterns):
                status = "changed (agreed)"
            else:
                status = "changed (NOT agreed)"
                failures += 1
            counts[status] += 1
            print(f"{status:<22} {name}")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    changed = counts["changed (agreed)"] + counts["changed (NOT agreed)"]
    summary = ", ".join(f"{value} {key}" for key, value in counts.items())
    print(f"summary: {changed} changed — {summary}")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--baseline", default=DEFAULT_BASELINE, help="the folder rendered before the change")
    parser.add_argument("--current", default=DEFAULT_CURRENT, help="the folder rendered after it")
    parser.add_argument("--agreed", default=DEFAULT_AGREED, help="globs of images allowed to change")
    parser.add_argument("--base-ref", help="render the baseline from this commit when its folder is missing")
    parser.add_argument("--match", nargs="+", metavar="NAME", help="only report whether each name is agreed")
    args = parser.parse_args()

    patterns = load_agreed(args.agreed)
    if args.match:
        for name in args.match:
            print(f"{'agreed' if is_agreed(name, patterns) else 'NOT agreed':<11} {name}")
        return 0

    if not os.path.isdir(args.baseline):
        if not args.base_ref:
            print(f"no baseline at {args.baseline}; pass --base-ref <sha> to render one", file=sys.stderr)
            return 2
        render_baseline(args.base_ref, args.baseline)
    if not os.path.isdir(args.current):
        print(f"no snapshots at {args.current}; run `make snapshots` first", file=sys.stderr)
        return 2

    failures = compare(args.baseline, args.current, patterns)
    if failures:
        print(f"FAIL: {failures} image(s) changed or removed outside the agreed list", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
