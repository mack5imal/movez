#!/usr/bin/env python3
"""Simulate movez routine and micro-break draws under the current rules and the proposed ones.

    python3 -I scripts/simulate_selection.py movement-library-v4.json [--keep-rotation]

"current" mirrors Sources/movez/Routine/RoutineBuilder.swift and MicroBreakBuilder.swift as of
5270fe2, before the October 2026 rules. "proposed" follows docs/rule-changes-2026-10.md (C1-C11),
which is what the app now ships (DECISIONS.md 28-34), so it is the model to re-run. Settings match the
user's: no equipment, difficulty cap 3, no exclusions, no focus, always-normal time of day. Every
break served is treated as completed. --keep-rotation leaves the target-area x3 weight in the
proposed rules, to measure what dropping it (C9) costs.

Re-run it whenever the library changes: the closer and micro-break draws are pooled, so a category
that grows takes a larger share of them.
"""
import json
import random
import statistics
import sys
from collections import Counter, defaultdict

LIB = json.load(open(sys.argv[1]))["movements"]
BY_ID = {m["id"]: m for m in LIB}
BUCKETS = ["CIR", "FLX", "STR", "BAL", "HWF", "EYE", "BRE"]
ALWAYS_REPEATABLE = {"CIR-01", "EYE-01", "BRE-01"}
SLOTS = [
    ("hips", {"Hip", "Glute", "Quad", "Adductor"}),
    ("upper back", {"T-spine", "Chest", "Shoulder"}),
    ("neck & shoulders", {"Neck", "Shoulder"}),
    ("posterior chain", {"Ham", "Glute"}),
    ("core", {"L-spine/Core"}),
    ("ankles & feet", {"Calf/Ankle", "Foot/Shin"}),
]
DIFF_CAP = 3
SHORTAGE = {}  # fewest options any proposed draw had, per category
# Set by --keep-rotation: the proposed rules with the target-area x3 weight left in.
KEEP_ROTATION = "--keep-rotation" in sys.argv


def recency_weight(mid, history, day):
    score = 0.0
    for d, ids in history.items():
        ago = day - d
        if 1 <= ago <= 3:
            score += ids.count(mid) * (3 - ago + 1) / 3
    return 1 / (1 + 2 * score)


def unlocked_diff3(counts):
    out = set()
    for m in LIB:
        if m["difficulty"] < 3:
            continue
        for p in LIB:
            if (p["difficulty"] == 2 and p["bucket"] == m["bucket"]
                    and set(p["regions"]) & set(m["regions"]) and counts[p["id"]] >= 5):
                out.add(m["id"])
                break
    return out


def full_pool(used_today, counts, exempt=ALWAYS_REPEATABLE):
    unlocked = unlocked_diff3(counts)
    pool = []
    for m in LIB:
        if m["equipment_optional"]:
            continue  # resolved to a bodyweight peer that is already in the pool
        if m["id"] in used_today and m["id"] not in exempt:
            continue
        if m["difficulty"] > DIFF_CAP or (m["difficulty"] >= 3 and m["id"] not in unlocked):
            continue
        pool.append(m)
    return pool


def micro_pool():
    return [m for m in LIB if m["micro_eligible"] and not m["equipment_optional"] and m["settings"] != ["floor"]]


def weighted(options, weightf, rng):
    if not options:
        return None
    return rng.choices(options, [weightf(m) for m in options])[0]


# ---------------------------------------------------------------- current rules

def current_full(state, rng):
    pool = full_pool(state["used_today"], state["counts"])
    slot_regions = SLOTS[state["rotation"] % 6][1]
    last_str = state["last_str_regions"]
    bal_today = state["bal_today"]
    day, hist = state["day"], state["history"]

    def w(m):
        x = 3.0 if set(m["regions"]) & slot_regions else 1.0
        return x * recency_weight(m["id"], hist, day)

    def plan(n):
        p = [["CIR"], ["FLX"], ["STR", "BAL"]]
        if not bal_today:
            p[2] = ["BAL"]
        if n >= 5:
            p.append(["FLX"])
        p.append(["HWF", "EYE", "BRE"])
        return p

    def options(pos, allowed, chosen):
        taken = {m["id"] for m in chosen}
        base = [m for m in pool if m["bucket"] in allowed and m["id"] not in taken]
        if pos == 2 and last_str:
            fresh = [m for m in base if not set(m["regions"]) & last_str]
            return fresh or base
        return base

    def assemble(n):
        chosen = []
        for pos, allowed in enumerate(plan(n)):
            avail = options(pos, allowed, chosen)
            present = [b for b in allowed if any(m["bucket"] == b for m in avail)]
            if not present:
                continue
            b = rng.choice(present)
            pick = weighted([m for m in avail if m["bucket"] == b], w, rng)
            chosen.append(pick)
        return chosen

    def total(bl):
        return sum(m["block_seconds"] for m in bl) + 5 * (len(bl) - 1)

    blocks = assemble(4)
    if total(blocks) < 270:
        blocks = assemble(5)
    p = plan(len(blocks))
    for keep in (True, False):
        for _ in range(6):
            if total(blocks) >= 270:
                break
            improved = False
            for i in sorted(range(len(blocks)), key=lambda i: blocks[i]["block_seconds"]):
                others = [m for j, m in enumerate(blocks) if j != i]
                allowed = [blocks[i]["bucket"]] if keep else p[i]
                opts = [m for m in options(i, allowed, others) if m["block_seconds"] > blocks[i]["block_seconds"]]
                if not opts:
                    continue
                blocks[i] = weighted(opts, w, rng)
                improved = True
                break
            if not improved:
                break
    s = blocks[2] if len(blocks) > 2 else None
    state["last_str_regions"] = set(s["regions"]) if s else set()
    state["bal_today"] = bal_today or any(m["bucket"] == "BAL" for m in blocks)
    return blocks


def current_micro(state, rng, next_full_ids):
    emph = state["micro_index"] % 3
    order = {
        0: [["CIR", "BAL", "STR"], ["FLX", "BRE", "EYE", "HWF"]],
        1: [["EYE", "HWF"], ["CIR", "BAL", "FLX"]],
        2: [["FLX", "BRE"], ["CIR", "BAL", "STR"]],
    }[emph]
    pool = [m for m in micro_pool() if m["id"] not in state["last_micro"] and m["id"] not in next_full_ids]
    day, hist = state["day"], state["history"]

    def choose(opts):
        present = [b for b in BUCKETS if any(m["bucket"] == b for m in opts)]
        if not present:
            return None
        b = rng.choice(present)
        return weighted([m for m in opts if m["bucket"] == b], lambda m: recency_weight(m["id"], hist, day), rng)

    blocks = []
    for allowed in order:
        opts = [m for m in pool if m["bucket"] in allowed and m not in blocks and m["block_seconds"] >= 30]
        pick = choose(opts)
        if pick:
            blocks.append(pick)
    if len(blocks) < 2:
        single = choose([m for m in pool if m["block_seconds"] >= 60])
        blocks = [single] if single else blocks
    return blocks


# ---------------------------------------------------------------- proposed rules

def proposed_full(state, rng):
    pool = full_pool(state["used_today"], state["counts"], exempt=set())
    day, hist = state["day"], state["history"]
    last_str = state["last_str_regions"]

    slot_regions = SLOTS[state["rotation"] % 6][1]

    def w(m):
        x = 3.0 if KEEP_ROTATION and set(m["regions"]) & slot_regions else 1.0
        return x * recency_weight(m["id"], hist, day)

    middle = ["BAL", "FLX", "STR"]
    rng.shuffle(middle)
    blocks = []
    for b in ["CIR"] + middle + ["CLOSER"]:
        allowed = {"HWF", "EYE", "BRE"} if b == "CLOSER" else {b}
        taken = {m["id"] for m in blocks}
        opts = [m for m in pool if m["bucket"] in allowed and m["id"] not in taken]
        if b == "STR" and last_str:
            opts = [m for m in opts if not set(m["regions"]) & last_str] or opts
        if not state.get("preview"):
            SHORTAGE[b] = min(SHORTAGE.get(b, 99), len(opts))
        pick = weighted(opts, w, rng)
        if pick:
            blocks.append(pick)
    s = next((m for m in blocks if m["bucket"] == "STR"), None)
    state["last_str_regions"] = set(s["regions"]) if s else set()
    return blocks


def proposed_micro(state, rng, next_full_ids):
    pool = [m for m in micro_pool() if m["id"] not in state["last_micro"] and m["id"] not in next_full_ids
            and m["id"] not in state["used_today"]]
    SHORTAGE["micro"] = min(SHORTAGE.get("micro", 99), len(pool))
    day, hist = state["day"], state["history"]
    w = lambda m: recency_weight(m["id"], hist, day)
    first = weighted(pool, w, rng)
    if first["per_side"]:
        return [first]
    second = weighted([m for m in pool if not m["per_side"] and m["id"] != first["id"]], w, rng)
    return [first, second]


# ---------------------------------------------------------------- driver

def run(rules, schedule, rng):
    full_fn, micro_fn = (current_full, current_micro) if rules == "current" else (proposed_full, proposed_micro)
    state = {"history": defaultdict(list), "counts": Counter(), "rotation": 0}
    log = []  # (day, kind, [ids])
    for day, (nf, nm) in enumerate(schedule(rng)):
        state.update(day=day, used_today=set(), last_str_regions=set(), bal_today=False,
                     micro_index=0, last_micro=set())
        routines_before = state["rotation"]
        # Interleave: a micro-break falls between full breaks.
        kinds = []
        for i in range(max(nf, nm)):
            if i < nm:
                kinds.append("micro")
            if i < nf:
                kinds.append("full")
        break_index = 0
        for kind in kinds:
            if kind == "full":
                state["rotation"] = routines_before + break_index
                blocks = full_fn(state, rng)
                break_index += 1
            else:
                # The next full break is previewed so the micro-break can avoid it.
                preview_state = dict(state, last_str_regions=set(state["last_str_regions"]), preview=True)
                state["rotation"] = routines_before + break_index
                preview = full_fn(preview_state, random.Random(rng.random()))
                blocks = micro_fn(state, rng, {m["id"] for m in preview})
                state["micro_index"] += 1
                state["last_micro"] = {m["id"] for m in blocks}
            ids = [m["id"] for m in blocks]
            log.append((day, kind, ids))
            for i in ids:
                state["used_today"].add(i)
                state["history"][day].append(i)
                state["counts"][i] += 1
        state["rotation"] = routines_before + break_index
    return log


def summarise(logs, label):
    lines = [f"\n=== {label} ({len(logs)} runs) ==="]
    lib_n = Counter(m["bucket"] for m in LIB if not m["equipment_optional"])
    micro_n = Counter(m["bucket"] for m in micro_pool())

    distinct, distinct_shown, full_sizes, repeat3, top_share, micro_sizes = [], [], Counter(), [], [], Counter()
    cat = {"full": Counter(), "micro": Counter()}
    areas = Counter()
    full_slots = 0
    per_movement = Counter()
    for log in logs:
        seen = set()
        shown = set()
        appear = Counter()
        n_full = 0
        recent = defaultdict(set)
        reps = tot = 0
        for day, kind, ids in log:
            for i in ids:
                past = set().union(*(recent[d] for d in range(day - 3, day)))
                reps += i in past
                tot += 1
            for k, i in enumerate(ids):
                seen.add(i)
                cat[kind][BY_ID[i]["bucket"]] += 1
                per_movement[i] += 1
                if kind == "full" or k == 0 or label.startswith("PROPOSED"):
                    shown.add(i)
            recent[day] |= set(ids)
            if kind == "full":
                n_full += 1
                full_sizes[len(ids)] += 1
                for i in set(ids):
                    appear[i] += 1
                for i in ids:
                    full_slots += 1
                    for name, regs in SLOTS:
                        if set(BY_ID[i]["regions"]) & regs:
                            areas[name] += 1
            else:
                micro_sizes[len(ids)] += 1
        distinct.append(len(seen))
        distinct_shown.append(len(shown))
        repeat3.append(reps / tot)
        top_share.append(max(appear.values()) / n_full)

    def rng_str(xs, pct=False):
        f = (lambda v: f"{100 * v:.0f}%") if pct else (lambda v: f"{v:.0f}")
        xs = sorted(xs)
        return f"{f(statistics.mean(xs))} (range {f(xs[len(xs) // 20])}-{f(xs[-len(xs) // 20 - 1])})"

    lines.append(f"distinct movements served: {rng_str(distinct)}; shown on screen: {rng_str(distinct_shown)}")
    lines.append(f"movements per full break: {dict(sorted(full_sizes.items()))}")
    lines.append(f"movements per micro-break: {dict(sorted(micro_sizes.items()))}")
    lines.append(f"share of served movements also served in the 3 days before: {rng_str(repeat3, True)}")
    lines.append(f"most frequent movement appears in this share of full breaks: {rng_str(top_share, True)}")
    for kind, n in (("full", lib_n), ("micro", micro_n)):
        t = sum(cat[kind].values())
        lines.append(f"{kind} categories (share of slots / appearances per available movement per run):")
        for b in BUCKETS:
            if n[b]:
                lines.append(f"   {b}: {100 * cat[kind][b] / t:4.1f}%   {cat[kind][b] / len(logs) / n[b]:.2f}")
    allc = cat["full"] + cat["micro"]
    lines.append("overall appearances per available movement per run:")
    lines.append("   " + "  ".join(f"{b} {allc[b] / len(logs) / lib_n[b]:.2f}" for b in BUCKETS))
    lines.append("body areas touched (share of full-break movements touching each area):")
    lines.append("   " + "  ".join(f"{a} {100 * areas[a] / full_slots:.0f}%" for a, _ in SLOTS))
    top = per_movement.most_common(6)
    lines.append("most-served movements: " + ", ".join(f"{i} {BY_ID[i]['name']} ({c / len(logs):.1f})" for i, c in top))
    return "\n".join(lines)


if __name__ == "__main__":
    RUNS = 400
    # The user's last 14 days, day by day (full breaks shown, micro-breaks shown), 2026-09-26..10-09.
    actual = [(0, 0), (0, 0), (1, 0), (1, 2), (0, 2), (0, 0), (0, 1),
              (0, 0), (0, 0), (0, 0), (0, 0), (4, 3), (2, 4), (7, 5)]

    def triple(rng):
        # Three times the volume (45 full, ~51 micro) over ten working days in two weeks.
        days = []
        for week in range(2):
            for _ in range(5):
                days.append((rng.choice([4, 5]) if len(days) % 2 else 4 + (len(days) % 4 == 0), rng.choice([5, 5, 6, 4])))
            days += [(0, 0), (0, 0)]
        return days

    scenarios = {
        "your current rate (15 full, 17 micro in 14 days)": lambda rng: actual,
        "3x your current rate (~45 full, ~51 micro in 14 days)": triple,
    }
    for name, schedule in scenarios.items():
        for rules in ("current", "proposed"):
            SHORTAGE.clear()
            rng = random.Random(42)
            logs = [run(rules, schedule, rng) for _ in range(RUNS)]
            out = summarise(logs, f"{rules.upper()} rules, {name}")
            if rules == "proposed":
                out += "\nfewest options left at any draw: " + ", ".join(f"{k} {v}" for k, v in SHORTAGE.items())
            print(out)
