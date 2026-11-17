#!/usr/bin/env python3
"""Check strength-library-v1.json against the agreed library edits (SPEC S4).

    python3 -I scripts/check_strength_library.py [strength-library-v1.json]

The strength library is the only copy (DECISIONS 50), so it is edited by hand. This script is the
guard on those edits: every working-bucket dose sits in the agreed ranges, the kettlebell is listed
only where one heavy bell suits the move, the five curls exist, and every count the file states
matches the movements it holds. It prints one line per failure and exits 1 if there is any, so a
later edit that drifts from the agreed program is caught before a builder reads it.
"""
import json
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "strength-library-v1.json"

WORKING_BUCKETS = ("SQT", "HNG", "PSH", "PUL", "COR", "ACC")
TWO_SIDED = re.compile(r"^(\d+) reps$")
PER_SIDE = re.compile(r"^(\d+)/side$")
ALTERNATING = re.compile(r"^(\d+) reps, alternating$")
# Doses in seconds are holds sized to the block, not rep targets, so the rep ranges don't apply.
SECONDS = (
    re.compile(r"^\d+(–\d+)? s$"),
    re.compile(r"^\d+ s/side$"),
    re.compile(r"^\d+ × \d+ s$"),
)
TWO_SIDED_RANGE = (10, 15)
PER_SIDE_RANGE = (8, 10)
ALTERNATING_RANGE = (16, 20)

# The slow multi-part moves keep their lower doses so every rep stays controlled (SPEC S4).
SLOW_EXCEPTIONS = {
    "PUL-01": "5 of each",
    "HNG-17": "6 reps",
    "COR-11": "8 each direction",
    "COR-14": "5/side",
    "COR-15": "6/side",
    "COR-16": "3/side",
}
# Out of range but outside the agreed edits, so they are kept and reported for the owner to
# decide rather than changed silently. Pinning the exact dose still catches any later drift.
RECORDED_FINDINGS = {
    "COR-05": "12 reps, alternating, 2 s hold",
    "COR-17": "12 reps, alternating",
}

# Moves that keep the kettlebell besides the heavy tier: one heavy bell suits them.
KETTLEBELL_KEPT = {
    "SQT-04", "SQT-06", "SQT-08", "SQT-10", "SQT-12", "SQT-15",
    "HNG-14", "HNG-18", "PUL-10", "PUL-18",
}
DUMBBELL_ONLY = {"PSH-12", "PSH-15", "HNG-13", "COR-02", "COR-11", "COR-14", "COR-16", "COR-17"}
NEW_CURLS = {
    "PUL-19": "dumbbell curl",
    "PUL-20": "hammer curl",
    "PUL-21": "under-desk isometric curl",
    "PUL-22": "seated concentration curl",
    "PUL-23": "reverse curl",
}
TOTAL = 145
PUL_COUNT = 23

failures = []


def say(line):
    sys.stdout.write(line + "\n")


def fail(message):
    failures.append(message)


def in_range(value, bounds):
    return bounds[0] <= value <= bounds[1]


def check_dose(movement):
    mid, dose = movement["id"], movement["dose"]
    if mid in SLOW_EXCEPTIONS:
        if dose != SLOW_EXCEPTIONS[mid]:
            fail(f"{mid}: slow multi-part dose must stay {SLOW_EXCEPTIONS[mid]!r}, is {dose!r}")
        return
    if mid in RECORDED_FINDINGS:
        if dose != RECORDED_FINDINGS[mid]:
            fail(f"{mid}: recorded dose {RECORDED_FINDINGS[mid]!r} changed to {dose!r}")
        return
    if any(p.match(dose) for p in SECONDS):
        return
    for pattern, bounds, label in (
        (TWO_SIDED, TWO_SIDED_RANGE, "two-sided"),
        (PER_SIDE, PER_SIDE_RANGE, "per-side"),
        (ALTERNATING, ALTERNATING_RANGE, "alternating"),
    ):
        match = pattern.match(dose)
        if match:
            if not in_range(int(match.group(1)), bounds):
                fail(f"{mid}: {label} dose {dose!r} is outside {bounds[0]}–{bounds[1]}")
            if label == "per-side" and not movement["per_side"]:
                fail(f"{mid}: per-side dose {dose!r} on a two-sided movement")
            return
    fail(f"{mid}: dose {dose!r} matches no agreed notation")


def coverage_for(movements, owned):
    result = {}
    for bucket in WORKING_BUCKETS:
        eligible = [m for m in movements
                    if m["bucket"] == bucket and (not m["equipment"] or owned & set(m["equipment"]))]
        result[bucket] = {
            "eligible": len(eligible),
            "loaded": sum(1 for m in eligible if m["equipment"]),
            "diff_1_2": sum(1 for m in eligible if m["difficulty"] <= 2),
        }
    return result


def main():
    with open(PATH, encoding="utf-8") as f:
        library = json.load(f)
    movements = library["movements"]
    by_id = {m["id"]: m for m in movements}

    if len(by_id) != len(movements):
        fail("movement ids are not unique")
    if len(movements) != TOTAL:
        fail(f"expected {TOTAL} movements, found {len(movements)}")
    pul = sum(1 for m in movements if m["bucket"] == "PUL")
    if pul != PUL_COUNT:
        fail(f"expected {PUL_COUNT} PUL movements, found {pul}")

    fields = list(movements[0].keys())
    for m in movements:
        if list(m.keys()) != fields:
            fail(f"{m['id']}: field set or order differs from {movements[0]['id']}")
        if not str(m.get("dose") or "").strip():
            fail(f"{m['id']}: empty dose")
        if not str(m.get("instructions") or "").strip():
            fail(f"{m['id']}: empty instructions")
        if m["bucket"] in WORKING_BUCKETS:
            check_dose(m)

    heavy = {m["id"] for m in movements if m["load"] == "heavy"}
    with_bell = {m["id"] for m in movements if "kettlebell" in m["equipment"]}
    expected_bell = KETTLEBELL_KEPT | heavy
    for mid in sorted(with_bell - expected_bell):
        fail(f"{mid}: lists the kettlebell but is neither heavy-tier nor a kept kettlebell move")
    for mid in sorted(expected_bell - with_bell):
        fail(f"{mid}: should list the kettlebell")

    for mid in sorted(DUMBBELL_ONLY):
        m = by_id.get(mid)
        if m is None:
            fail(f"{mid}: missing")
            continue
        if m["equipment"] != ["dumbbells"]:
            fail(f"{mid}: equipment should be ['dumbbells'], is {m['equipment']}")
        if "kettlebell" in m["instructions"].lower():
            fail(f"{mid}: instructions still offer a kettlebell")

    for mid, name in NEW_CURLS.items():
        m = by_id.get(mid)
        if m is None:
            fail(f"{mid}: missing ({name})")
            continue
        if m["name"].lower() != name:
            fail(f"{mid}: name should be {name!r}, is {m['name']!r}")
        if m["bucket"] != "PUL":
            fail(f"{mid}: bucket should be PUL")
        if "Arm" not in m["regions"]:
            fail(f"{mid}: regions should include Arm")
        if not 1 <= m["difficulty"] <= 2:
            fail(f"{mid}: difficulty should be 1 or 2")
        if m["on_floor"] or m["micro_eligible"]:
            fail(f"{mid}: should be off the floor and not micro-eligible")

    if "biceps and triceps" not in library["schema"]["movement"]["regions"]:
        fail("schema.movement.regions does not document Arm as biceps and triceps")

    for bucket in library["buckets"]:
        actual = sum(1 for m in movements if m["bucket"] == bucket["id"])
        if bucket["count"] != actual:
            fail(f"buckets.{bucket['id']}.count is {bucket['count']}, library has {actual}")

    configs = {"none": set(), "dumbbells": {"dumbbells"}, "kettlebell": {"kettlebell"},
               "both": {"dumbbells", "kettlebell"}}
    for config, owned in configs.items():
        stated = library["coverage"][config]
        computed = coverage_for(movements, owned)
        for bucket, counts in computed.items():
            if stated[bucket] != counts:
                fail(f"coverage.{config}.{bucket} is {stated[bucket]}, library gives {counts}")
        combined = computed["COR"]["eligible"] + computed["ACC"]["eligible"]
        if stated["COR+ACC"]["eligible"] != combined:
            fail(f"coverage.{config}.COR+ACC.eligible is {stated['COR+ACC']['eligible']}, library gives {combined}")

    for mid, dose in RECORDED_FINDINGS.items():
        say(f"finding: {mid} dose {dose!r} is outside the alternating range and was left for the owner")
    for message in failures:
        say(f"FAIL: {message}")
    if failures:
        say(f"{len(failures)} failure(s)")
        return 1
    say(f"ok: {len(movements)} movements, PUL {pul}, kettlebell on {len(with_bell)} moves")
    return 0


if __name__ == "__main__":
    sys.exit(main())
