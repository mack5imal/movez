#!/usr/bin/env python3
"""Prove strength-library-v1.json changed only where the agreed edits allow (SPEC S4).

    python3 -I scripts/diff_strength_library.py --base <git-ref>

The owner's library must not drift beyond the agreed edits, so this compares the working copy
with the library at <git-ref> (read through `git show`, never copied to disk) and fails if
anything changed outside: the dose of the seven dose-adjusted moves, the equipment and
instructions of the eight dumbbell-only moves, the five new curls (and the v4 overlap pair of the
one that is a v4 movement), the counts the file states and the Arm documentation. Each expected
change must also be present, so the listing it prints is exactly the agreed set.
"""
import argparse
import json
import subprocess
import sys

LIBRARY = "strength-library-v1.json"
DOSE_EDITS = {"SQT-01", "HNG-10", "HNG-16", "PSH-01", "ACC-05", "ACC-06", "ACC-09"}
DUMBBELL_ONLY = {"PSH-12", "PSH-15", "HNG-13", "COR-02", "COR-11", "COR-14", "COR-16", "COR-17"}
NEW_IDS = ["PUL-19", "PUL-20", "PUL-21", "PUL-22", "PUL-23"]
ALLOWED_FIELDS = {mid: {"dose"} for mid in DOSE_EDITS}
ALLOWED_FIELDS.update({mid: {"equipment", "instructions"} for mid in DUMBBELL_ONLY})
# Top-level sections compared field by field below; every other section must be identical.
SPECIAL = {"movements", "schema", "buckets", "coverage", "overlap_with_movement_library"}

problems = []


def say(line):
    sys.stdout.write(line + "\n")


def problem(message):
    problems.append(message)


def load_base(ref):
    try:
        text = subprocess.run(["git", "show", f"{ref}:{LIBRARY}"], check=True,
                              capture_output=True, text=True).stdout
    except subprocess.CalledProcessError as error:
        sys.exit(f"git show {ref}:{LIBRARY} failed: {error.stderr.strip()}")
    return json.loads(text)


def count_paths(base, work, path, changed):
    """Collect the paths of changed integers in two count trees that must share one shape."""
    if isinstance(base, dict) and isinstance(work, dict):
        if list(base.keys()) != list(work.keys()):
            problem(f"{path}: keys changed")
            return
        for key in base:
            count_paths(base[key], work[key], f"{path}.{key}", changed)
    elif isinstance(base, int) and isinstance(work, int):
        if base != work:
            changed.append(f"{path}: {base} -> {work}")
    elif base != work:
        problem(f"{path}: changed and is not a count")


def compare_movements(base, work):
    base_ids = [m["id"] for m in base]
    work_ids = [m["id"] for m in work]
    added = [mid for mid in work_ids if mid not in base_ids]
    removed = [mid for mid in base_ids if mid not in work_ids]
    if removed:
        problem(f"movements removed: {removed}")
    if added != NEW_IDS:
        problem(f"movements added {added}, expected {NEW_IDS}")
    if [mid for mid in work_ids if mid in base_ids] != base_ids:
        problem("existing movements were reordered")

    work_by_id = {m["id"]: m for m in work}
    changed = {}
    for old in base:
        new = work_by_id.get(old["id"])
        if new is None:
            continue
        if list(old.keys()) != list(new.keys()):
            problem(f"{old['id']}: field set or order changed")
        fields = sorted(k for k in old if old.get(k) != new.get(k))
        if fields:
            changed[old["id"]] = fields
            extra = set(fields) - ALLOWED_FIELDS.get(old["id"], set())
            if extra:
                problem(f"{old['id']}: changed fields not allowed: {sorted(extra)}")
    for mid, fields in sorted(ALLOWED_FIELDS.items()):
        if set(changed.get(mid, [])) != fields:
            problem(f"{mid}: expected {sorted(fields)} to change, changed {changed.get(mid, [])}")
    return changed, added


def compare_pairs(base, work):
    base_pairs = base["pairs"]
    work_pairs = work["pairs"]
    if base["meaning"] != work["meaning"]:
        problem("overlap_with_movement_library.meaning changed")
    remaining = [p for p in work_pairs if p not in base_pairs]
    if [p for p in work_pairs if p in base_pairs] != base_pairs:
        problem("overlap_with_movement_library.pairs: existing pairs changed or reordered")
    for pair in remaining:
        if pair.get("strength") not in NEW_IDS:
            problem(f"overlap_with_movement_library.pairs: unexpected pair {pair}")
    return remaining


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", required=True, help="git ref holding the baseline library")
    args = parser.parse_args()

    base = load_base(args.base)
    with open(LIBRARY, encoding="utf-8") as f:
        work = json.load(f)

    if list(base.keys()) != list(work.keys()):
        problem("top-level sections added, removed or reordered")
    for key in base:
        if key not in SPECIAL and base[key] != work.get(key):
            problem(f"{key}: changed")

    changed, added = compare_movements(base["movements"], work["movements"])
    new_pairs = compare_pairs(base["overlap_with_movement_library"],
                              work["overlap_with_movement_library"])
    work_by_id = {m["id"]: m for m in work["movements"]}
    for pair in new_pairs:
        overlap = work_by_id.get(pair["strength"], {}).get("v4_overlap")
        if overlap != {"id": pair["movement"], "kind": pair["kind"]}:
            problem(f"overlap pair {pair} does not match {pair['strength']}.v4_overlap")

    schema_changes = []
    base_schema, work_schema = dict(base["schema"]), dict(work["schema"])
    base_movement = dict(base_schema.pop("movement"))
    work_movement = dict(work_schema.pop("movement"))
    if base_schema != work_schema:
        problem("schema: changed outside schema.movement")
    old_regions, new_regions = base_movement.pop("regions"), work_movement.pop("regions")
    if base_movement != work_movement:
        problem("schema.movement: changed outside the regions note")
    if old_regions != new_regions:
        if "biceps and triceps" not in new_regions:
            problem("schema.movement.regions changed but does not document Arm")
        schema_changes.append(f"schema.movement.regions: {old_regions!r} -> {new_regions!r}")
    else:
        problem("schema.movement.regions: Arm documentation missing")

    count_changes = []
    base_buckets = [{k: v for k, v in b.items() if k != "count"} for b in base["buckets"]]
    work_buckets = [{k: v for k, v in b.items() if k != "count"} for b in work["buckets"]]
    if base_buckets != work_buckets:
        problem("buckets: changed outside the counts")
    else:
        for old, new in zip(base["buckets"], work["buckets"]):
            if old["count"] != new["count"]:
                count_changes.append(f"buckets.{old['id']}.count: {old['count']} -> {new['count']}")
    count_paths(base["coverage"], work["coverage"], "coverage", count_changes)

    say("dose edits: " + ", ".join(sorted(m for m in changed if m in DOSE_EDITS)))
    say("dumbbell-only: " + ", ".join(sorted(m for m in changed if m in DUMBBELL_ONLY)))
    say("new movements: " + ", ".join(added))
    for pair in new_pairs:
        say(f"new overlap pair: {pair['strength']} = {pair['movement']} ({pair['kind']})")
    say(f"count fields: {len(count_changes)}")
    for line in count_changes:
        say(f"  {line}")
    say("Arm documentation:")
    for line in schema_changes:
        say(f"  {line}")
    for message in problems:
        say(f"FAIL: {message}")
    if problems:
        say(f"{len(problems)} problem(s)")
        return 1
    say(f"ok: only the agreed edits differ from {args.base}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
