#!/usr/bin/env python3
"""Prove strength-library-v1.json changed only where the agreed edits allow (SPEC S4).

    python3 -I scripts/diff_strength_library.py [--base <git-ref>]

Run it from the repo root. The base defaults to PRE_STRENGTH (94a59ea, "fix: the build
number is stamped after Xcode writes the Info.plist"), the last commit before the strength-mode
work began. The strength branch is merged now, so `main` no longer means "before the edits":
passing `--base main` would report every agreed edit as missing. Keep the default unless a new,
reviewed round of edits moves the baseline, and then change PRE_STRENGTH and the lists below
together.

The owner's library must not drift beyond the agreed edits, so this compares the working copy
with the library at <git-ref> (read through `git show`, never copied to disk) and fails if
anything changed outside them. The agreed edits are two rounds:

- DECISIONS 62: the dose of the seven dose-adjusted moves, the equipment and instructions of the
  eight dumbbell-only moves, the five curls and the Arm documentation.
- DECISIONS 70 and 71: the Biceps and Triceps buckets (the curls filed as BIC-01..05, three PSH
  triceps moves renamed TRI-01..03, BIC-06 and TRI-04..06 new), two new loaded lunges (SQT-17,
  SQT-18), the `vigorous` flag on every movement, the bucket enum and the routine and overlap
  references that follow the renames.

- The November 2026 review: COR-17's dose raised to 16 alternating (TST-24).

The baseline is the library before the strength-mode edits, 378386c. The counts the file states
may change with them. Each expected change must also be present, so
the listing it prints is exactly the agreed set.
"""
import argparse
import json
import subprocess
import sys

LIBRARY = "strength-library-v1.json"
# The last commit before the strength-mode edits; see the module docstring.
PRE_STRENGTH = "94a59ea7b207abc82cf9515f065d8912db3de7ab"
DOSE_EDITS = {"SQT-01", "HNG-10", "HNG-16", "PSH-01", "ACC-05", "ACC-06", "ACC-09"}
DUMBBELL_ONLY = {"PSH-12", "PSH-15", "HNG-13", "COR-02", "COR-11", "COR-14", "COR-16", "COR-17"}
# Baseline movements that moved into the triceps bucket under a new id (DECISIONS 70).
RENAMED = {"PSH-18": "TRI-01", "PSH-06": "TRI-02", "PSH-09": "TRI-03"}
RENAME_FIELDS = {"id", "bucket", "bucket_name"}
NEW_BUCKETS = {"BIC": "Biceps", "TRI": "Triceps"}
# Added since the baseline, in file order: the two lunges, the five curls (first added as
# PUL-19..23), the self-resisted curl and the three new triceps moves.
NEW_IDS = ["SQT-17", "SQT-18", "BIC-01", "BIC-02", "BIC-03", "BIC-04", "BIC-05", "BIC-06",
           "TRI-04", "TRI-05", "TRI-06"]
BUCKET_ORDER = ["SQT", "HNG", "PSH", "PUL", "BIC", "TRI", "COR", "ACC", "END"]
BUCKET_ENUM = "|".join(BUCKET_ORDER)
# The flag every movement gains (DECISIONS 71): equipment moves are always vigorous; bodyweight
# moves are vigorous only for this list and the whole of COR.
BODYWEIGHT_VIGOROUS = {"PSH-04", "PSH-05", "PSH-07", "PSH-08", "HNG-02", "HNG-06", "TRI-03"}
BODYWEIGHT_VIGOROUS_BUCKETS = {"COR"}
ALLOWED_FIELDS = {mid: {"dose"} for mid in DOSE_EDITS}
ALLOWED_FIELDS.update({mid: {"equipment", "instructions"} for mid in DUMBBELL_ONLY})
ALLOWED_FIELDS.update({mid: set(RENAME_FIELDS) for mid in RENAMED})
# The November 2026 review (TST-24): COR-17 raised from 12 to 16 alternating, into DECISIONS 60's
# range. It is a dumbbell-only move as well, so its dose joins the fields that change.
REVIEW_DOSE_EDITS = {"COR-17"}
for _mid in REVIEW_DOSE_EDITS:
    ALLOWED_FIELDS.setdefault(_mid, set()).add("dose")
# Top-level sections compared field by field below; every other section must be identical.
SPECIAL = {"movements", "schema", "buckets", "coverage", "overlap_with_movement_library", "routines"}

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


def renamed(mid):
    return RENAMED.get(mid, mid)


def with_vigorous(keys):
    """The baseline field order with `vigorous` inserted straight after `equipment`."""
    result = []
    for key in keys:
        result.append(key)
        if key == "equipment":
            result.append("vigorous")
    return result


def expected_vigorous(movement):
    if movement["equipment"]:
        return True
    return movement["id"] in BODYWEIGHT_VIGOROUS or movement["bucket"] in BODYWEIGHT_VIGOROUS_BUCKETS


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
    base_ids = [renamed(m["id"]) for m in base]
    work_ids = [m["id"] for m in work]
    added = [mid for mid in work_ids if mid not in base_ids]
    removed = [mid for mid in base_ids if mid not in work_ids]
    if removed:
        problem(f"movements removed: {removed}")
    if added != NEW_IDS:
        problem(f"movements added {added}, expected {NEW_IDS}")
    # The renamed moves change bucket, so they leave their old position; everything else keeps
    # its baseline order.
    kept = set(RENAMED.values())
    if [mid for mid in work_ids if mid in base_ids and mid not in kept] != \
            [mid for mid in base_ids if mid not in kept]:
        problem("existing movements were reordered")
    buckets = [m["bucket"] for m in work]
    grouped = [b for i, b in enumerate(buckets) if i == 0 or buckets[i - 1] != b]
    if grouped != BUCKET_ORDER:
        problem(f"movements are not grouped by bucket in {BUCKET_ORDER}: {grouped}")

    reference_keys = with_vigorous(list(base[0].keys()))
    for m in work:
        if list(m.keys()) != reference_keys:
            problem(f"{m['id']}: field set or order differs from the baseline plus vigorous")
        if m.get("vigorous") is not expected_vigorous(m):
            problem(f"{m['id']}: vigorous is {m.get('vigorous')!r}, the agreed rule gives "
                    f"{expected_vigorous(m)}")
        if m["id"][:3] in NEW_BUCKETS and m["bucket_name"] != NEW_BUCKETS[m["id"][:3]]:
            problem(f"{m['id']}: bucket_name should be {NEW_BUCKETS[m['id'][:3]]!r}")

    work_by_id = {m["id"]: m for m in work}
    changed = {}
    for old in base:
        new = work_by_id.get(renamed(old["id"]))
        if new is None:
            continue
        fields = sorted(k for k in old if old.get(k) != new.get(k))
        if fields:
            changed[old["id"]] = fields
            extra = set(fields) - ALLOWED_FIELDS.get(old["id"], set())
            if extra:
                problem(f"{old['id']}: changed fields not allowed: {sorted(extra)}")
    for mid, fields in sorted(ALLOWED_FIELDS.items()):
        if set(changed.get(mid, [])) != fields:
            problem(f"{mid}: expected {sorted(fields)} to change, changed {changed.get(mid, [])}")
    for old, new in RENAMED.items():
        moved = work_by_id.get(new)
        if moved is not None and moved["bucket"] != new[:3]:
            problem(f"{new}: bucket should be {new[:3]}")
    return changed, added


def compare_pairs(base, work):
    base_pairs = [dict(p, strength=renamed(p["strength"])) for p in base["pairs"]]
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


def compare_routines(base, work):
    """Routines may change only where a block names a renamed movement."""
    changes = []
    mapped = json.loads(json.dumps(base))
    for routine in mapped:
        for block in routine["blocks"]:
            if block["movement_id"] in RENAMED:
                changes.append(f"{routine['id']}: {block['movement_id']} -> {renamed(block['movement_id'])}")
                block["movement_id"] = renamed(block["movement_id"])
    if mapped != work:
        problem("routines: changed beyond the renamed movement ids")
    return changes


def compare_schema(base, work):
    changes = []
    base_schema, work_schema = dict(base), dict(work)
    base_movement = dict(base_schema.pop("movement"))
    work_movement = dict(work_schema.pop("movement"))
    if base_schema != work_schema:
        problem("schema: changed outside schema.movement")
    if list(work_movement.keys()) != with_vigorous(list(base_movement.keys())):
        problem("schema.movement: keys changed beyond adding vigorous after equipment")
    vigorous = work_movement.pop("vigorous", "")
    if "working set" not in vigorous or "equipment" not in vigorous:
        problem("schema.movement.vigorous does not document the working-set rule")
    changes.append(f"schema.movement.vigorous: added {vigorous!r}")
    old_bucket, new_bucket = base_movement.pop("bucket"), work_movement.pop("bucket")
    if new_bucket != BUCKET_ENUM:
        problem(f"schema.movement.bucket should be {BUCKET_ENUM!r}, is {new_bucket!r}")
    changes.append(f"schema.movement.bucket: {old_bucket!r} -> {new_bucket!r}")
    old_regions, new_regions = base_movement.pop("regions"), work_movement.pop("regions")
    if base_movement != work_movement:
        problem("schema.movement: changed outside the bucket, regions and vigorous notes")
    if old_regions != new_regions:
        if "biceps and triceps" not in new_regions:
            problem("schema.movement.regions changed but does not document Arm")
        changes.append(f"schema.movement.regions: {old_regions!r} -> {new_regions!r}")
    else:
        problem("schema.movement.regions: Arm documentation missing")
    return changes


def compare_counts(base, work):
    changes = []
    work_buckets = [{k: v for k, v in b.items() if k != "count"} for b in work["buckets"]]
    expected_buckets = []
    for b in base["buckets"]:
        expected_buckets.append({k: v for k, v in b.items() if k != "count"})
        if b["id"] == "PUL":
            expected_buckets.extend({"id": bid, "name": name} for bid, name in NEW_BUCKETS.items())
    if work_buckets != expected_buckets:
        problem("buckets: changed beyond the counts and the BIC and TRI buckets after PUL")
    else:
        base_counts = {b["id"]: b["count"] for b in base["buckets"]}
        for new in work["buckets"]:
            old = base_counts.get(new["id"])
            if old is None:
                changes.append(f"buckets.{new['id']}.count: added {new['count']}")
            elif old != new["count"]:
                changes.append(f"buckets.{new['id']}.count: {old} -> {new['count']}")

    base_coverage, work_coverage = base["coverage"], work["coverage"]
    if list(base_coverage.keys()) != list(work_coverage.keys()):
        problem("coverage: configurations added, removed or reordered")
        return changes
    trimmed = {}
    for config, buckets in work_coverage.items():
        keys = list(buckets.keys())
        expected = []
        for key in base_coverage[config]:
            expected.append(key)
            if key == "PUL":
                expected.extend(NEW_BUCKETS)
        if keys != expected:
            problem(f"coverage.{config}: keys should be {expected}, are {keys}")
            continue
        for bucket in NEW_BUCKETS:
            counts = buckets[bucket]
            if list(counts.keys()) != list(base_coverage[config]["PUL"].keys()) or \
                    not all(isinstance(v, int) for v in counts.values()):
                problem(f"coverage.{config}.{bucket}: not a count block shaped like PUL")
            changes.append(f"coverage.{config}.{bucket}: added {counts}")
        trimmed[config] = {k: v for k, v in buckets.items() if k not in NEW_BUCKETS}
    count_paths({k: v for k, v in base_coverage.items() if k in trimmed}, trimmed, "coverage", changes)
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default=PRE_STRENGTH,
                        help="git ref holding the baseline library (default: the pre-strength commit)")
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
    routine_changes = compare_routines(base["routines"], work["routines"])
    schema_changes = compare_schema(base["schema"], work["schema"])
    count_changes = compare_counts(base, work)

    say("dose edits: " + ", ".join(sorted(m for m in changed if m in DOSE_EDITS | REVIEW_DOSE_EDITS)))
    say("dumbbell-only: " + ", ".join(sorted(m for m in changed if m in DUMBBELL_ONLY)))
    say("renamed: " + ", ".join(f"{old} -> {new}" for old, new in RENAMED.items() if old in changed))
    say("new movements: " + ", ".join(added))
    vigorous = sum(1 for m in work["movements"] if m["vigorous"])
    say(f"vigorous: added to all {len(work['movements'])} movements, {vigorous} true")
    for pair in new_pairs:
        say(f"new overlap pair: {pair['strength']} = {pair['movement']} ({pair['kind']})")
    for line in routine_changes:
        say(f"routine block: {line}")
    say(f"count fields: {len(count_changes)}")
    for line in count_changes:
        say(f"  {line}")
    say("schema:")
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
