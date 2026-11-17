#!/usr/bin/env python3
"""Simulate movez strength days and prove the strength rules hold (S10).

    python3 -I scripts/simulate_strength.py

Mirrors Sources/movez/Strength/ as of the strength simulation: StrengthDayPlanner (letters, set orders),
StrengthBreakBuilder, EndRangeBreakBuilder and StrengthMicroBuilder, down to the SplitMix64
generator, the id-sorted weighted draw and each slot's relaxation ladder, so the same context
draws the same moves as the app. CrossModeUsage's widening of "used today" through `same`
overlaps and their movement-library families is mirrored too, which is why the movement library
is read as well.

Every break built is checked by a rule checker written against scripts/strength-rules.json, not
against the builders: a hard rule counts as broken whenever the break breaks it, a where-possible
rule only when another move that keeps it, and keeps every other rule the served move keeps, was
there for the same slot. Tests/movezTests/StrengthRuleChecker.swift implements the same list, so
the script and the Swift cross-check agree on what a violation is.

The sixteen configurations are dumbbells x kettlebell x wall at difficulty caps 2 and 3 with every
difficulty-3 pattern unlocked. Each simulates whole days of six full breaks and six micro-breaks,
the strength breaks a day cycling through 1-4 so every setting is exercised, one strength break in
ten skipped so the planner has to offer it again, until each kind reaches 5,000. The weekly tables
come from 5-day weeks at the app's default settings with every break taken.

Writes docs/strength-simulation.md and prints a summary. Exits 1 on any violation, any eligible
move never served, or when the default week (3 a day, 5 days) leaves the research targets; exits 2
when this script and strength-rules.json disagree on the rule list.
"""
import json
import os
import sys
import time
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRENGTH = json.load(open(os.path.join(ROOT, "strength-library-v1.json")))
MOVEMENT = json.load(open(os.path.join(ROOT, "movement-library-v4.json")))
RULES = json.load(open(os.path.join(ROOT, "scripts", "strength-rules.json")))["rules"]
REPORT = os.path.join(ROOT, "docs", "strength-simulation.md")

TARGET = 5000
FULL_PER_DAY = 6
SKIP_ONE_IN = 10
WEEK_RUNS = 20
MASK = (1 << 64) - 1

# Weekly hard sets each working set adds, a helper muscle counting a half (research/muscle-volume.md).
PART_SETS = {
    "SQT": {"quads": 1, "glutes": 0.5},
    "HNG": {"hamstrings": 1, "glutes": 1},
    "PSH": {"chest": 1, "triceps": 0.5},
    "PUL": {"back": 1, "biceps": 0.5},
    "COR": {"core": 1},
}
PARTS = ["quads", "glutes", "hamstrings", "chest", "back", "biceps", "triceps", "core"]
# The default week must land in these (S10); core counts direct sets only.
RANGES = {"quads": (8, 12), "chest": (8, 12), "back": (8, 12), "hamstrings": (8, 12),
          "glutes": (12, 18), "biceps": (4, 7), "triceps": (4, 7), "core": (4, 6)}


# ---------------------------------------------------------------- library


class Move:
    __slots__ = ("id", "name", "bucket", "regions", "dose", "per_side", "difficulty", "settings",
                 "floor", "equipment", "bodyweight", "grip", "micro", "seated", "same")

    def __init__(self, raw):
        self.id = raw["id"]
        self.name = raw["name"]
        self.bucket = raw["bucket"]
        self.regions = frozenset(raw["regions"])
        self.dose = raw["dose"]
        self.per_side = raw["per_side"]
        self.difficulty = raw["difficulty"]
        self.settings = frozenset(raw["settings"])
        self.floor = raw["on_floor"]
        self.equipment = frozenset(raw["equipment"])
        self.bodyweight = not raw["equipment"]
        self.grip = raw["grip_demand"]
        self.micro = raw["micro_eligible"]
        self.seated = "Chair" in self.settings
        overlap = raw.get("v4_overlap")
        self.same = overlap["id"] if overlap and overlap["kind"] == "same" else None


LIB = [Move(m) for m in STRENGTH["movements"]]
BY_ID = {m.id: m for m in LIB}
BUCKET = defaultdict(list)
for _m in LIB:
    BUCKET[_m.bucket].append(_m)
MICRO_POOL = [m for m in LIB if m.micro]
PATTERNS = {"A": ("SQT", "PSH"), "B": ("HNG", "PUL")}

FAMILY = {m["id"]: m.get("family") or m["id"] for m in MOVEMENT["movements"]}
# Each strength id with a `same` overlap, keyed by its twin's movement-library family.
SAME_BY_FAMILY = defaultdict(set)
for _m in LIB:
    if _m.same:
        SAME_BY_FAMILY[FAMILY.get(_m.same, _m.same)].add(_m.id)


def widen(served):
    """CrossModeUsage.used(...).strengthIds for a strength-only day."""
    used = set(served)
    for sid in served:
        twin = BY_ID[sid].same
        if twin:
            used |= SAME_BY_FAMILY[FAMILY.get(twin, twin)]
    return used


# ---------------------------------------------------------------- generator


class SplitMix64:
    def __init__(self, seed):
        self.state = seed & MASK

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        return z ^ (z >> 31)

    def unit(self):
        return (self.next() >> 11) * (1.0 / 9007199254740992.0)

    def weighted_index(self, weights):
        total = 0.0
        for w in weights:
            total += w
        if total <= 0:
            return None
        ticket = self.unit() * total
        for i, w in enumerate(weights):
            ticket -= w
            if ticket < 0:
                return i
        return len(weights) - 1


def weighted(pool, rng, weight):
    if not pool:
        return None
    ordered = sorted(pool, key=lambda m: m.id)
    index = rng.weighted_index([weight(m) for m in ordered])
    return ordered[0] if index is None else ordered[index]


def recency_multiplier(m, recency):
    return 1 / (1 + 2.0 * max(0.0, recency.get(m.id, 0.0)))


# ---------------------------------------------------------------- rules shared by the builders


def possible(m, equipment, wall):
    if not m.bodyweight and not (equipment & m.equipment):
        return False
    if not wall and "Wall" in m.settings:
        return False
    return True


def within_difficulty(m, cap, unlocked):
    if m.difficulty > cap:
        return False
    if m.difficulty >= 3 and m.bucket not in unlocked:
        return False
    return True


def warm_up_shaped(m):
    return m.bodyweight and not m.floor and m.difficulty == 1 and not m.per_side


def fits_break_limits(m, chosen):
    return all(allows(m, chosen) for allows in BREAK_LIMITS)


BREAK_LIMITS = [
    lambda m, chosen: not (m.per_side and any(c.per_side for c in chosen)),
    lambda m, chosen: not (m.floor and any(c.floor for c in chosen)),
    lambda m, chosen: not (m.grip and any(c.grip for c in chosen)),
]


def narrow_break_limits(pool, let_go, chosen):
    if "breakLimits" not in let_go:
        return pool
    for allows in BREAK_LIMITS:
        pool = preferring(pool, lambda m, a=allows: a(m, chosen))
    return pool


class Context:
    """StrengthContext and StrengthMicroContext in one."""

    def __init__(self, cfg, used, recency, seed, last_micro=(), next_full=()):
        self.used = used
        self.equipment = cfg["equipment"]
        self.wall = cfg["wall"]
        self.cap = cfg["cap"]
        self.unlocked = cfg["unlocked"]
        self.excluded = frozenset()
        self.recency = recency
        self.seed = seed & MASK
        self.last_micro = set(last_micro)
        self.next_full = set(next_full)


def passes_shared(m, ctx, let_go):
    if not possible(m, ctx.equipment, ctx.wall):
        return False
    if "servedToday" not in let_go and m.id in ctx.used:
        return False
    if "excluded" not in let_go and m.id in ctx.excluded:
        return False
    if "difficulty" not in let_go and not within_difficulty(m, ctx.cap, ctx.unlocked):
        return False
    return True


class DrawState:
    def __init__(self, seed):
        self.rng = SplitMix64(seed)
        self.relaxed = []
        self.let_go = set()


def ladder_pick(slot, ladder, state, weight, candidates):
    let_go = set()
    order = []
    pool = candidates(let_go)
    for rule in ladder:
        if pool:
            break
        let_go.add(rule)
        order.append(rule)
        pool = candidates(let_go)
    # Each rule let go of before the last is taken back, the most important first, wherever the
    # pool still has a move that keeps it.
    for rule in reversed(order[:-1]):
        kept = let_go - {rule}
        narrower = candidates(kept)
        if narrower:
            let_go, pool = kept, narrower
    state.relaxed += [(slot, rule) for rule in order if rule in let_go]
    state.let_go = let_go
    return weighted(pool, state.rng, weight)


def preferring(options, preferred):
    fresh = [m for m in options if preferred(m)]
    return fresh or options


# ---------------------------------------------------------------- planner (StrengthDayPlanner)


def choose_lead(first, second, sets, led_at, prior_lead):
    if sets[first] != sets[second]:
        return first if sets[first] < sets[second] else second
    if led_at:
        return first if led_at.get(first, -1) <= led_at.get(second, -1) else second
    if prior_lead:
        return second if prior_lead == first else first
    return first


def replay(letter, breaks, prior_lead):
    first, second = PATTERNS[letter]
    sets = {first: 0, second: 0}
    led_at = {}
    last_lead = None
    orders = []
    for index in range(max(0, breaks)):
        if index == 0:
            orders.append([first, second, "COR"])
            sets[first] += 1
            sets[second] += 1
            continue
        lead = choose_lead(first, second, sets, led_at, prior_lead)
        other = second if lead == first else first
        orders.append([lead, other, lead])
        sets[lead] += 2
        sets[other] += 1
        led_at[lead] = index
        last_lead = lead
    return orders, last_lead


class Planner:
    """StrengthDayPlanner.next over the completed strength breaks, one list of letters per day."""

    def __init__(self):
        self.days = {}

    def letter(self, day):
        if self.days.get(day):
            return self.days[day][0]
        earlier = [k for k in self.days if k < day]
        if not earlier:
            return "A"
        return "B" if self.days[max(earlier)][0] == "A" else "A"

    def last_lead(self, day, letter):
        lead = None
        for key in sorted(k for k in self.days if k < day):
            breaks = self.days[key]
            if breaks[0] != letter:
                continue
            day_lead = replay(letter, len(breaks), lead)[1]
            if day_lead:
                lead = day_lead
        return lead

    def next(self, per_day, day, prior_leads):
        letter = self.letter(day)
        completed = len(self.days.get(day, []))
        if completed >= per_day:
            return ("endRange", None, None)
        orders = replay(letter, completed + 1, prior_leads.get(letter))[0]
        return ("strength", letter, orders[completed])

    def complete(self, day, letter):
        self.days.setdefault(day, []).append(letter)


# ---------------------------------------------------------------- builders


WORKING_LADDER = ["breakLimits", "servedToday", "excluded", "difficulty", "anything"]
WARM_UP_LADDER = ["warmUpShape", "servedToday", "excluded", "difficulty", "anything"]
COOL_DOWN_LADDER = ["coolDownRegion", "servedToday", "excluded", "difficulty", "anything"]
END_RANGE_LADDER = ["servedToday", "excluded", "difficulty", "anything"]
MICRO_LADDER = ["servedToday", "previousMicroRegion", "excluded", "difficulty", "anything"]


def draw_slot(slot, bucket, ladder, taken, ctx, state, slot_rule, narrow=None):
    in_bucket = BUCKET[bucket]

    def candidates(let_go):
        out = []
        for m in in_bucket:
            if m.id in taken:
                continue
            if "anything" in let_go:
                if possible(m, ctx.equipment, ctx.wall):
                    out.append(m)
                continue
            if passes_shared(m, ctx, let_go) and slot_rule(m, let_go):
                out.append(m)
        return narrow(out, let_go) if narrow else out

    pick = ladder_pick(slot, ladder, state, lambda m: recency_multiplier(m, ctx.recency), candidates)
    return pick or (in_bucket[0] if in_bucket else LIB[0])


def build_strength(letter, order, ctx):
    state = DrawState(ctx.seed)
    warm = draw_slot("warmUp", order[0], WARM_UP_LADDER, set(), ctx, state,
                     lambda m, g: m.bodyweight if "warmUpShape" in g else warm_up_shaped(m))
    drawn = {}
    working = []
    for index, bucket in enumerate(order):
        if bucket in drawn:
            working.append(drawn[bucket])
            continue
        distinct = list(drawn.values())
        taken = {m.id for m in distinct} | {warm.id}
        pick = draw_slot(f"set{index + 1}", bucket, WORKING_LADDER, taken, ctx, state,
                         lambda m, g, d=distinct: "breakLimits" in g or fits_break_limits(m, d),
                         lambda pool, g, d=distinct: narrow_break_limits(pool, g, d))
        drawn[bucket] = pick
        working.append(pick)
    worked = set().union(*(m.regions for m in working))
    taken = {m.id for m in working} | {warm.id}
    cool = draw_slot("coolDown", "END", COOL_DOWN_LADDER, taken, ctx, state,
                     lambda m, g: "coolDownRegion" in g or bool(worked & m.regions))
    return {"kind": "strength", "letter": letter, "warm": (warm, 30),
            "sets": [(m, m.dose) for m in working], "cool": (cool, 30), "relaxed": state.relaxed}


def build_end_range(ctx, avoiding):
    state = DrawState(ctx.seed)
    pool = BUCKET["END"]
    chosen = []
    for index in range(4):
        taken = {m.id for m in chosen}

        def candidates(let_go, taken=taken):
            options = []
            for m in pool:
                if m.id in taken:
                    continue
                if "anything" in let_go:
                    if possible(m, frozenset(), ctx.wall):
                        options.append(m)
                elif passes_shared(m, ctx, let_go):
                    options.append(m)
            return preferring(options, lambda m: not (avoiding & m.regions))

        pick = ladder_pick(f"block{index + 1}", END_RANGE_LADDER, state,
                           lambda m: recency_multiplier(m, ctx.recency), candidates)
        if pick is None:
            break
        chosen.append(pick)
    return {"kind": "endRange", "blocks": [(m, 60) for m in chosen], "relaxed": state.relaxed}


def is_partner(c, first):
    return c.id != first.id and not c.per_side and c.seated == first.seated


def regions_of(ids):
    out = set()
    for i in ids:
        out |= BY_ID[i].regions
    return out


def build_micro(ctx):
    state = DrawState(ctx.seed)
    previous = regions_of(ctx.last_micro)
    upcoming = regions_of(ctx.next_full)
    weight = lambda m: recency_multiplier(m, ctx.recency)  # noqa: E731
    def raw_pool(let_go):
        pool = []
        for m in MICRO_POOL:
            if m.bucket != "END" or m.floor or not possible(m, frozenset(), ctx.wall):
                continue
            if "anything" not in let_go:
                if "servedToday" not in let_go and m.id in ctx.used:
                    continue
                if "previousMicroRegion" not in let_go and previous & m.regions:
                    continue
                if "excluded" not in let_go and m.id in ctx.excluded:
                    continue
                if "difficulty" not in let_go and not within_difficulty(m, ctx.cap, ctx.unlocked):
                    continue
            pool.append(m)
        return pool

    def candidates(let_go):
        pool = raw_pool(let_go)
        openers = [m for m in pool if m.per_side or any(is_partner(p, m) for p in pool)]
        return preferring(openers, lambda m: not (upcoming & m.regions))

    first = ladder_pick("block1", MICRO_LADDER, state, weight, candidates)
    final_pool = raw_pool(state.let_go)
    first = first or weighted(final_pool, state.rng, weight)
    if first is None:
        return {"kind": "micro", "blocks": [], "relaxed": state.relaxed}
    if first.per_side:
        return {"kind": "micro", "blocks": [(first, 60)], "relaxed": state.relaxed}
    partners = [m for m in final_pool if is_partner(m, first)]
    let_go = set(state.let_go)
    for rule in reversed(MICRO_LADDER):
        if rule not in let_go:
            continue
        kept = let_go - {rule}
        stricter = {m.id for m in raw_pool(kept)}
        narrower = [m for m in partners if m.id in stricter]
        if narrower:
            partners, let_go = narrower, kept
    partners = preferring(partners, lambda m: not (upcoming & m.regions))
    second = weighted(partners, state.rng, weight)
    if second is None:
        state.relaxed.append(("block2", "microShape"))
        return {"kind": "micro", "blocks": [(first, 60)], "relaxed": state.relaxed}
    return {"kind": "micro", "blocks": [(first, 30), (second, 30)], "relaxed": state.relaxed}


# ---------------------------------------------------------------- the rule checker


def soft_breaks(pick, universe, soft, alternative=None):
    """The where-possible rules `pick` broke needlessly: those for which some other move in
    `universe` keeps the rule and every other rule `pick` keeps. `alternative` narrows what
    counts as a usable alternative under a given set of kept rules."""
    kept = [pred for _, pred in soft if pred(pick)]
    broken = []
    for rule, pred in soft:
        if pred(pick):
            continue
        need = kept + [pred]
        for c in universe:
            if c is pick or not all(p(c) for p in need):
                continue
            if alternative is None or alternative(c, need):
                broken.append(rule)
                break
    return broken


class Checker:
    """Checks every built break against strength-rules.json, independently of the builders."""

    # Every rule id this checker can report. It must be strength-rules.json's list exactly.
    IMPLEMENTED = (
        "s6-shape", "s6-day-patterns", "s6-lead", "s6-same-move-twice", "s6-distinct",
        "s6-warm-up-pattern", "s6-warm-up-shape", "s6-warm-up-timing", "s6-cool-down-end",
        "s6-cool-down-region", "s6-per-side-limit", "s6-floor-limit", "s6-grip-limit", "s6-equipment",
        "s6-wall", "s6-served-today", "s6-excluded", "s6-difficulty", "s6-dose",
        "s7-end-only", "s7-no-floor", "s7-wall", "s7-distinct", "s7-shape", "s7-same-posture",
        "s7-previous-region", "s7-next-break-region", "s7-served-today", "s7-excluded", "s7-difficulty",
        "s22-letter", "s22-count", "s22-end-range-shape", "s22-end-range-distinct", "s22-end-range-wall",
        "s22-end-range-served-today", "s22-end-range-worked-regions", "s22-end-range-excluded",
        "s22-end-range-difficulty",
    )

    def __init__(self, cfg):
        self.cfg = cfg
        self.letters = {}  # day -> letter of its completed strength breaks
        self.last_led = {}  # pattern -> global index of the completed break it last led
        self.completed = 0

    def _shared(self, prefix, ctx):
        return [
            (f"{prefix}-served-today", lambda m: m.id not in ctx.used),
            (f"{prefix}-excluded", lambda m: m.id not in ctx.excluded),
            (f"{prefix}-difficulty", lambda m: within_difficulty(m, ctx.cap, ctx.unlocked)),
        ]

    def _possible(self, m):
        return possible(m, self.cfg["equipment"], self.cfg["wall"])

    # Planner rules, judged from the completed breaks alone.
    def expected_letter(self, day):
        if day in self.letters:
            return self.letters[day]
        earlier = [d for d in self.letters if d < day]
        if not earlier:
            return "A"
        return "B" if self.letters[max(earlier)] == "A" else "A"

    def check_plan(self, brk, day, per_day, done_today, sets_today):
        out = []
        should_be_strength = done_today < per_day
        if (brk["kind"] == "strength") != should_be_strength:
            out.append("s22-count")
        if brk["kind"] != "strength":
            return out
        letter = self.expected_letter(day)
        if brk["letter"] != letter:
            out.append("s22-letter")
        first, second = PATTERNS[letter]
        buckets = [m.bucket for m, _ in brk["sets"]]
        if done_today == 0:
            if buckets != [first, second, "COR"]:
                out.append("s6-day-patterns")
            return out
        if len(buckets) != 3 or buckets[0] != buckets[2] or {buckets[0], buckets[1]} != {first, second}:
            out.append("s6-day-patterns")
            return out
        lead, other = buckets[0], buckets[1]
        if sets_today[lead] > sets_today[other]:
            out.append("s6-lead")
        elif sets_today[lead] == sets_today[other]:
            led, other_led = self.last_led.get(lead, -1), self.last_led.get(other, -1)
            if led > other_led or (led == other_led and lead != first):
                out.append("s6-lead")
        return out

    def record_completed(self, brk, day, done_today):
        self.letters.setdefault(day, brk["letter"])
        if done_today > 0:
            self.last_led[brk["sets"][0][0].bucket] = self.completed
        self.completed += 1

    def check_strength(self, brk, ctx):
        out = []
        warm, warm_seconds = brk["warm"]
        cool, cool_seconds = brk["cool"]
        sets = brk["sets"]
        moves = [m for m, _ in sets]
        if len(sets) != 3 or warm is None or cool is None:
            out.append("s6-shape")
        by_bucket = defaultdict(set)
        for m in moves:
            by_bucket[m.bucket].add(m.id)
        if any(len(ids) > 1 for ids in by_bucket.values()):
            out.append("s6-same-move-twice")
        distinct = list(dict.fromkeys(moves))
        ids = [warm.id] + [m.id for m in distinct] + [cool.id]
        if len(set(ids)) != len(ids):
            out.append("s6-distinct")
        if warm.bucket != moves[0].bucket:
            out.append("s6-warm-up-pattern")
        if warm_seconds != 30:
            out.append("s6-warm-up-timing")
        if cool.bucket != "END" or cool_seconds != 30:
            out.append("s6-cool-down-end")
        for m in [warm, cool] + moves:
            if not m.bodyweight and not (self.cfg["equipment"] & m.equipment):
                out.append("s6-equipment")
            if not self.cfg["wall"] and "Wall" in m.settings:
                out.append("s6-wall")
        if any(dose != BY_ID[m.id].dose for m, dose in sets):
            out.append("s6-dose")

        shared = self._shared("s6", ctx)
        universe = [m for m in BUCKET[moves[0].bucket] if self._possible(m)]
        out += soft_breaks(warm, universe, [("s6-warm-up-shape", warm_up_shaped)] + shared)
        earlier = []
        for m in distinct:
            taken = {warm.id} | {e.id for e in earlier}
            universe = [c for c in BUCKET[m.bucket] if self._possible(c) and c.id not in taken]
            limits = [
                ("s6-per-side-limit", lambda c, e=earlier: not (c.per_side and any(x.per_side for x in e))),
                ("s6-floor-limit", lambda c, e=earlier: not (c.floor and any(x.floor for x in e))),
                ("s6-grip-limit", lambda c, e=earlier: not (c.grip and any(x.grip for x in e))),
            ]
            out += soft_breaks(m, universe, limits + shared)
            earlier.append(m)
        worked = set().union(*(m.regions for m in moves))
        taken = {warm.id} | {m.id for m in moves}
        universe = [c for c in BUCKET["END"] if self._possible(c) and c.id not in taken]
        out += soft_breaks(cool, universe, [("s6-cool-down-region", lambda c: bool(worked & c.regions))] + shared)
        return out

    def check_end_range(self, brk, ctx, worked_today):
        out = []
        blocks = brk["blocks"]
        if len(blocks) != 4 or any(m.bucket != "END" or s != 60 for m, s in blocks):
            out.append("s22-end-range-shape")
        ids = [m.id for m, _ in blocks]
        if len(set(ids)) != len(ids):
            out.append("s22-end-range-distinct")
        if not self.cfg["wall"] and any("Wall" in m.settings for m, _ in blocks):
            out.append("s22-end-range-wall")
        soft = self._shared("s22-end-range", ctx) + [
            ("s22-end-range-worked-regions", lambda c: not (worked_today & c.regions))]
        for index, (m, _) in enumerate(blocks):
            taken = set(ids[:index])
            universe = [c for c in BUCKET["END"] if possible(c, frozenset(), self.cfg["wall"]) and c.id not in taken]
            out += soft_breaks(m, universe, soft)
        return out

    def check_micro(self, brk, ctx):
        out = []
        blocks = brk["blocks"]
        moves = [m for m, _ in blocks]
        if any(m.bucket != "END" for m in moves):
            out.append("s7-end-only")
        if any(m.floor for m in moves):
            out.append("s7-no-floor")
        if not self.cfg["wall"] and any("Wall" in m.settings for m in moves):
            out.append("s7-wall")
        if len({m.id for m in moves}) != len(moves):
            out.append("s7-distinct")
        if len(blocks) == 2 and moves[0].seated != moves[1].seated:
            out.append("s7-same-posture")

        previous = regions_of(ctx.last_micro)
        upcoming = regions_of(ctx.next_full)
        pool = [m for m in MICRO_POOL if m.bucket == "END" and not m.floor
                and possible(m, frozenset(), self.cfg["wall"])]
        rules = [
            ("s7-served-today", lambda c: c.id not in ctx.used),
            ("s7-previous-region", lambda c: not (previous & c.regions)),
            ("s7-excluded", lambda c: c.id not in ctx.excluded),
            ("s7-difficulty", lambda c: within_difficulty(c, ctx.cap, ctx.unlocked)),
        ]
        soft = rules + [("s7-next-break-region", lambda c: not (upcoming & c.regions))]
        ladder_rules = [p for _, p in rules]

        def opener(c, need):
            # A first move is only an alternative when it can make a whole micro-break: per-side,
            # or with a partner that keeps the same rules (the next-break preference aside).
            kept = [p for p in need if p in ladder_rules]
            return c.per_side or any(is_partner(p, c) and all(q(p) for q in kept) for p in pool)

        if not blocks:
            out.append("s7-shape")
            return out
        first = moves[0]
        out += soft_breaks(first, pool, soft, alternative=opener)
        kept = [p for p in ladder_rules if p(first)]
        if len(blocks) == 1:
            seconds = blocks[0][1]
            if seconds != 60:
                out.append("s7-shape")
            elif not first.per_side:
                partner = any(is_partner(c, first) and all(p(c) for p in kept) for c in pool)
                per_side = any(c.per_side and all(p(c) for p in kept) for c in pool)
                if partner or per_side:
                    out.append("s7-shape")
        elif len(blocks) == 2:
            if first.per_side or moves[1].per_side or any(s != 30 for _, s in blocks):
                out.append("s7-shape")
            partners = [c for c in pool if is_partner(c, first)]
            out += soft_breaks(moves[1], partners, soft)
        else:
            out.append("s7-shape")
        return out


# ---------------------------------------------------------------- simulation


class Tally:
    def __init__(self):
        self.violations = Counter()
        self.examples = {}
        self.relaxed = Counter()
        self.counts = Counter()  # strength / skipped / endRange / micro
        self.served = defaultdict(Counter)  # (role, bucket) -> id -> breaks
        self.micro_shapes = Counter()
        self.weekly = []  # per run, per week, Counter of parts

    def add_violations(self, rules, brk):
        for rule in rules:
            assert rule in Checker.IMPLEMENTED, rule
            self.violations[rule] += 1
            self.examples.setdefault(rule, describe(brk))


def describe(brk):
    if brk["kind"] == "strength":
        return " · ".join([brk["warm"][0].id] + [m.id for m, _ in brk["sets"]] + [brk["cool"][0].id])
    return " · ".join(m.id for m, _ in brk["blocks"])


def simulate(cfg, seed, per_day_for, until=None, days=None, skip=True, tally=None):
    """Runs whole days with `cfg` until each kind of break reaches `until`, or for `days` days."""
    tally = tally or Tally()
    rng = SplitMix64(seed)
    planner = Planner()
    checker = Checker(cfg)
    history = defaultdict(Counter)  # day -> id -> servings
    prior_leads = {}
    weeks = defaultdict(Counter)
    day = 0
    while True:
        if days is not None and day >= days:
            break
        if until is not None and min(tally.counts["strength"], tally.counts["endRange"], tally.counts["micro"]) >= until:
            break
        per_day = per_day_for(day)
        recency = Counter()
        for back in (1, 2, 3):
            for sid, n in history.get(day - back, {}).items():
                recency[sid] += n * (3 - back + 1) / 3
        served = set()
        last_micro = set()
        worked = set()
        done_today = 0
        sets_today = Counter()
        for _ in range(FULL_PER_DAY):
            full_seed = rng.next()
            micro_seed = rng.next()
            kind, letter, order = planner.next(per_day, day, prior_leads)

            def build_full(used):
                ctx = Context(cfg, used, recency, full_seed)
                if kind == "strength":
                    return build_strength(letter, order, ctx), ctx
                return build_end_range(ctx, worked), ctx

            preview, _ = build_full(widen(served))
            micro_ctx = Context(cfg, widen(served), recency, micro_seed, last_micro, ids_of(preview))
            micro = build_micro(micro_ctx)
            tally.counts["micro"] += 1
            tally.micro_shapes[micro_shape(micro)] += 1
            tally.add_violations(checker.check_micro(micro, micro_ctx), micro)
            note_relaxed(tally, micro)
            serve(micro, served, history[day], tally, "micro")
            last_micro = set(ids_of(micro))

            brk, ctx = build_full(widen(served))
            tally.add_violations(checker.check_plan(brk, day, per_day, done_today, sets_today), brk)
            note_relaxed(tally, brk)
            if brk["kind"] == "strength":
                tally.add_violations(checker.check_strength(brk, ctx), brk)
                if skip and rng.next() % SKIP_ONE_IN == 0:
                    tally.counts["skipped"] += 1
                    continue
                tally.counts["strength"] += 1
                checker.record_completed(brk, day, done_today)
                planner.complete(day, brk["letter"])
                done_today += 1
                for m, _ in brk["sets"]:
                    sets_today[m.bucket] += 1
                    for part, n in PART_SETS[m.bucket].items():
                        weeks[day // 5][part] += n
                worked |= set().union(*(m.regions for m, _ in brk["sets"]))
                serve(brk, served, history[day], tally, None)
            else:
                tally.add_violations(checker.check_end_range(brk, ctx, worked), brk)
                tally.counts["endRange"] += 1
                serve(brk, served, history[day], tally, "endRange")
        if day in planner.days:
            letter = planner.days[day][0]
            lead = replay(letter, len(planner.days[day]), prior_leads.get(letter))[1]
            if lead:
                prior_leads[letter] = lead
        history.pop(day - 3, None)
        day += 1
    tally.weekly.append([weeks[w] for w in sorted(weeks)])
    return tally


def ids_of(brk):
    if brk["kind"] == "strength":
        return list(dict.fromkeys([brk["warm"][0].id] + [m.id for m, _ in brk["sets"]] + [brk["cool"][0].id]))
    return [m.id for m, _ in brk["blocks"]]


def micro_shape(brk):
    blocks = brk["blocks"]
    if len(blocks) == 2:
        return "two two-sided moves"
    if len(blocks) == 1 and blocks[0][0].per_side:
        return "one per-side move"
    return "one two-sided move alone"


def note_relaxed(tally, brk):
    for slot, rule in brk["relaxed"]:
        tally.relaxed[(brk["kind"], rule)] += 1


def serve(brk, served, today, tally, role):
    if brk["kind"] == "strength":
        roles = [("warm-up", brk["warm"][0])] + [("set", m) for m in dict.fromkeys(m for m, _ in brk["sets"])]
        roles.append(("cool-down", brk["cool"][0]))
    else:
        roles = [(role, m) for m, _ in brk["blocks"]]
    for r, m in roles:
        served.add(m.id)
        today[m.id] += 1
        tally.served[(r, m.bucket)][m.id] += 1


# ---------------------------------------------------------------- eligibility for the share tables


def eligible(cfg, role, m):
    if not possible(m, cfg["equipment"], cfg["wall"]) or not within_difficulty(m, cfg["cap"], cfg["unlocked"]):
        return False
    if role == "set":
        return m.bucket in PART_SETS
    if role == "warm-up":
        return m.bucket in ("SQT", "PSH", "HNG", "PUL") and warm_up_shaped(m)
    if role in ("cool-down", "end-range", "endRange"):
        return m.bucket == "END"
    if role == "micro":
        return m.bucket == "END" and m.micro and not m.floor
    return False


ROLES = [("set", b) for b in ("SQT", "HNG", "PSH", "PUL", "COR")] + [
    ("warm-up", b) for b in ("SQT", "HNG", "PSH", "PUL")] + [
    ("cool-down", "END"), ("endRange", "END"), ("micro", "END")]
ROLE_NAMES = {"set": "working sets", "warm-up": "warm-ups", "cool-down": "cool-downs",
              "endRange": "end-range blocks", "micro": "micro-breaks"}

def cause(cfg, role, bucket, move):
    """The rule that concentrates a slot's draw on `move`, worked out from the library."""
    pool = [m for m in BUCKET[bucket] if eligible(cfg, role, m)]
    regions = ", ".join(sorted(move.regions))
    if role == "set" and not move.floor and sum(m.floor for m in pool) > len(pool) / 2:
        off_floor = [m.id for m in pool if not m.floor]
        return (f"S6 floor limit: {len(pool) - len(off_floor)} of the {len(pool)} eligible {bucket} moves are on "
                f"the floor, so when another working move already is, the set falls to the "
                f"{len(off_floor)} that are not ({', '.join(off_floor)})")
    if role == "cool-down":
        legs = {"Glute", "Quad", "Ham"}
        reach = [m for m in pool if m.regions & legs]
        return (f"S6 cool-down region: it stretches {regions}; only {len(reach)} of the {len(pool)} eligible "
                f"END moves stretch a leg region the squat/lunge or hinge sets work every strength day")
    if role == "endRange":
        loaded = set()
        for b in PART_SETS:
            for m in BUCKET[b]:
                if eligible(cfg, "set", m):
                    loaded |= m.regions
        free = [m for m in pool if not (m.regions & loaded)]
        if not (move.regions & loaded):
            return (f"S22 worked regions: it stretches only {regions}, which no eligible working move loads, "
                    f"so it is one of the {len(free)} END moves left when the blocks avoid what the sets worked")
        return "S22 worked regions: end-range blocks avoid what the day's sets worked"
    if role == "warm-up":
        return (f"S6 warm-up shape: only {len(pool)} {bucket} moves are bodyweight, off the floor, difficulty 1 "
                f"and two-sided")
    if role == "micro":
        return "S7 shape and posture: a two-sided move needs a partner in the same posture"
    return f"S8 no repeats in a day: {len(pool)} eligible {bucket} moves share the day's breaks"


def configurations():
    out = []
    for cap in (2, 3):
        for dumbbells in (False, True):
            for kettlebell in (False, True):
                for wall in (True, False):
                    kit = {e for e, has in (("dumbbells", dumbbells), ("kettlebell", kettlebell)) if has}
                    name = (" + ".join(sorted(kit)) or "bodyweight") + (", wall" if wall else ", no wall")
                    out.append({"name": f"{name}, cap {cap}", "short": short_name(kit, wall, cap),
                                "equipment": frozenset(kit), "wall": wall, "cap": cap,
                                "unlocked": frozenset(BUCKET)})
    return out


def short_name(kit, wall, cap):
    return ("D" if "dumbbells" in kit else "-") + ("K" if "kettlebell" in kit else "-") + \
        ("W" if wall else "-") + str(cap)


DEFAULT = {"name": "app defaults: bodyweight, wall, cap 1", "short": "def", "equipment": frozenset(),
           "wall": True, "cap": 1, "unlocked": frozenset()}


# ---------------------------------------------------------------- report


def percent(n, total):
    return f"{100 * n / total:.1f}" if total else "–"


def say(line, stream=sys.stdout):
    """The summary the script reports on the command line."""
    stream.write(line + "\n")


def main():
    if sorted(Checker.IMPLEMENTED) != sorted(r["id"] for r in RULES):
        say("simulate_strength.py and strength-rules.json disagree on the rule list", sys.stderr)
        return 2
    started = time.time()
    configs = configurations()
    tallies = []
    for index, cfg in enumerate(configs):
        tally = simulate(cfg, 0x5EED_0000 + index, lambda day: 1 + day % 4, until=TARGET)
        tallies.append(tally)

    week_tallies = {}
    for per_day in (1, 2, 3, 4):
        tally = Tally()
        for run in range(WEEK_RUNS):
            simulate(DEFAULT, 0x7EE4_0000 + 100 * per_day + run, lambda day, n=per_day: n,
                     days=10, skip=False, tally=tally)
        week_tallies[per_day] = tally

    problems = []
    lines = report(configs, tallies, week_tallies, problems)
    with open(REPORT, "w") as handle:
        handle.write("\n".join(lines) + "\n")

    total_v = sum(sum(t.violations.values()) for t in tallies + list(week_tallies.values()))
    say(f"configurations: {len(configs)} + default weeks; elapsed {time.time() - started:.0f} s")
    for cfg, tally in zip(configs, tallies):
        c = tally.counts
        say(f"  {cfg['name']:<38} strength {c['strength']:>5} (skipped {c['skipped']:>4})  "
              f"end-range {c['endRange']:>5}  micro {c['micro']:>5}  violations {sum(tally.violations.values())}")
    week = week_tallies[3].weekly
    say("default week (3 a day, 5 days), weekly hard sets: " + ", ".join(
        f"{p} {week[0][0][p]:g}/{week[0][1][p]:g}" for p in PARTS) + " (week 1/week 2)")
    say(f"violations: {total_v}; problems: {len(problems)}")
    for problem in problems:
        say(f"  {problem}")
    say(f"report: {os.path.relpath(REPORT, ROOT)}")
    return 1 if problems else 0


def report(configs, tallies, week_tallies, problems):
    out = ["# Strength simulation", ""]
    out += [
        "Generated by `python3 -I scripts/simulate_strength.py`; do not edit by hand. Re-run it whenever",
        "`strength-library-v1.json` or a strength builder changes, since every draw below is pooled and a",
        "pattern that grows or loses a move changes its shares.",
        "",
        "The script mirrors `StrengthDayPlanner`, `StrengthBreakBuilder`, `EndRangeBreakBuilder` and",
        "`StrengthMicroBuilder`, including their generator and relaxation ladders, and checks every break",
        "it builds against `scripts/strength-rules.json`. A hard rule is broken whenever a break breaks it.",
        "A where-possible rule is broken only when another move that keeps it, and keeps every other rule",
        "the served move keeps, was there for the same slot: running short of moves late in a long day is",
        "what the relaxation ladders are for, and is counted under *Relaxations* instead. The recency and",
        "focus weights are distributions rather than per-break rules, so they show up in the share tables",
        "and not as violations. No configuration excludes anything, so the exclusion rules are vacuous here",
        "and are covered by the builders' unit tests.",
        "",
        f"Each configuration owns every difficulty-3 pattern, simulates days of {FULL_PER_DAY} full breaks and",
        f"{FULL_PER_DAY} micro-breaks with the strength breaks a day cycling 1, 2, 3, 4, skips one strength",
        f"break in {SKIP_ONE_IN} so the planner has to offer it again, and runs until each kind of break reaches",
        f"{TARGET:,}. A micro-break comes before each full break and avoids a preview of it.",
        "",
        "## Breaks simulated",
        "",
        "| Configuration | Code | Strength breaks | Skipped | End-range breaks | Micro-breaks | Violations |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for cfg, t in zip(configs, tallies):
        c = t.counts
        v = sum(t.violations.values())
        out.append(f"| {cfg['name']} | `{cfg['short']}` | {c['strength']:,} | {c['skipped']:,} | "
                   f"{c['endRange']:,} | {c['micro']:,} | {v} |")
        if v:
            problems.append(f"{cfg['name']}: {v} violations")
        for kind in ("strength", "endRange", "micro"):
            if c[kind] < TARGET:
                problems.append(f"{cfg['name']}: only {c[kind]} {kind} breaks")
    for n, t in week_tallies.items():
        c = t.counts
        v = sum(t.violations.values())
        out.append(f"| {DEFAULT['name']}, {n} a day, {WEEK_RUNS} × 2 weeks | `def{n}` | {c['strength']:,} | 0 | "
                   f"{c['endRange']:,} | {c['micro']:,} | {v} |")
        if v:
            problems.append(f"default weeks at {n} a day: {v} violations")

    out += ["", "The codes read dumbbells, kettlebell, wall, then the difficulty cap.", "",
            "## Violations by rule", "",
            "Every rule in `scripts/strength-rules.json`, per configuration. Every cell must be 0.", ""]
    codes = [c["short"] for c in configs] + [f"def{n}" for n in week_tallies]
    all_tallies = tallies + list(week_tallies.values())
    out.append("| Rule | Kind | " + " | ".join(f"`{c}`" for c in codes) + " |")
    out.append("|---|---|" + "---:|" * len(codes))
    for rule in RULES:
        cells = [str(t.violations[rule["id"]]) for t in all_tallies]
        out.append(f"| `{rule['id']}` {rule['text']} | {rule['kind']} | " + " | ".join(cells) + " |")
    examples = {r: t.examples[r] for t in all_tallies for r in t.examples}
    if examples:
        out += ["", "First break breaking each rule:", ""]
        out += [f"- `{r}`: {e}" for r, e in sorted(examples.items())]

    out += ["", "## Relaxations", "",
            "How often a builder had to let a rule go because nothing was left that kept it, per break kind",
            "and rule, summed over the sixteen configurations. These are the ladders doing their job, not",
            "violations: each one was checked above and no move that kept the rule was available.", "",
            "| Break | Rule let go | Times | Per 1,000 breaks of that kind |", "|---|---|---:|---:|"]
    relaxed = Counter()
    totals = Counter()
    for t in tallies:
        relaxed.update(t.relaxed)
        totals["strength"] += t.counts["strength"] + t.counts["skipped"]
        totals["endRange"] += t.counts["endRange"]
        totals["micro"] += t.counts["micro"]
    for (kind, rule), n in sorted(relaxed.items()):
        out.append(f"| {kind} | `{rule}` | {n:,} | {1000 * n / totals[kind]:.1f} |")
    shapes = Counter()
    for t in tallies:
        shapes.update(t.micro_shapes)
    out += ["", "Micro-break shapes over the sixteen configurations: " + ", ".join(
        f"{k} {percent(n, sum(shapes.values()))}%" for k, n in shapes.most_common()) + "."]

    out += ["", "## Eligible moves never served", "",
            "A move is eligible when the configuration can do it, its difficulty is allowed, and some break",
            "kind draws from its pattern (ACC is drawn by none of them, so its moves are listed apart).", "",
            "| Configuration | Eligible | Never served | Moves |", "|---|---:|---:|---|"]
    for cfg, t in zip(configs, tallies):
        served = Counter()
        for counter in t.served.values():
            served.update(counter)
        pool = [m for m in LIB if any(eligible(cfg, role, m) for role, _ in ROLES)]
        never = [m.id for m in pool if not served[m.id]]
        out.append(f"| {cfg['name']} | {len(pool)} | {len(never)} | {', '.join(never) or '–'} |")
        if never:
            problems.append(f"{cfg['name']}: never served {', '.join(never)}")
    acc = ", ".join(m.id for m in BUCKET["ACC"])
    out += ["", f"Not drawn by any strength-mode break: {acc}. S6 gives a strength break the day's two patterns",
            "and one core set, so the arm accessories wait for a later mode; their weekly sets below are 0."]

    out += over_share(configs, tallies)
    out += share_tables(configs, tallies)
    out += weekly(week_tallies, problems)
    return out


def over_share(configs, tallies):
    out = ["", "## Moves above three times their even share", "",
           "The even share of a slot is one over the moves eligible for it in that configuration. A move",
           "drawn for more than three times that share is listed with the rule that concentrates the draw.", ""]
    rows = []
    for cfg, t in zip(configs, tallies):
        for role, bucket in ROLES:
            counter = t.served[(role, bucket)]
            total = sum(counter.values())
            pool = [m for m in BUCKET[bucket] if eligible(cfg, role, m)]
            if not total or not pool:
                continue
            even = 1 / len(pool)
            for mid, n in counter.most_common():
                if n / total > 3 * even:
                    rows.append((cfg["short"], f"{bucket} {ROLE_NAMES[role]}", mid, BY_ID[mid].name,
                                 100 * n / total, 100 * even, cause(cfg, role, bucket, BY_ID[mid])))
    if not rows:
        out.append("None in any configuration.")
        return out
    out += ["| Config | Slot | Move | Share % | Even share % | Cause |", "|---|---|---|---:|---:|---|"]
    out += [f"| `{c}` | {slot} | {mid} {name} | {s:.1f} | {e:.1f} | {cause} |"
            for c, slot, mid, name, s, e, cause in rows]
    return out


def share_tables(configs, tallies):
    out = ["", "## Share per move", "",
           "Each move's share, in percent, of the breaks in which its slot drew from its pattern, per",
           "configuration code. A dash means the move is not eligible for that slot there.", ""]
    for role, bucket in ROLES:
        moves = [m for m in BUCKET[bucket] if any(eligible(cfg, role, m) for cfg in configs)]
        if not moves:
            continue
        out += [f"### {bucket} {ROLE_NAMES[role]}", ""]
        out.append("| Move | " + " | ".join(f"`{c['short']}`" for c in configs) + " |")
        out.append("|---|" + "---:|" * len(configs))
        for m in moves:
            cells = []
            for cfg, t in zip(configs, tallies):
                counter = t.served[(role, bucket)]
                cells.append(percent(counter[m.id], sum(counter.values())) if eligible(cfg, role, m) else "–")
            out.append(f"| {m.id} {m.name} | " + " | ".join(cells) + " |")
        out.append("")
    return out


def weekly(week_tallies, problems):
    out = ["## Weekly hard sets per body part", "",
           "From 5-day weeks at the app's default settings with every break taken. A direct set counts 1",
           "and a helper set ½: squat/lunge gives quads 1 and glutes ½, hinge hamstrings 1 and glutes 1,",
           "push chest 1 and triceps ½, pull back 1 and biceps ½, core 1; an arm move would give its own",
           "muscle 1, but no strength break draws one. Letters alternate across weeks, so week 1 starts on",
           "an A day (A B A B A) and week 2 on a B day (B A B A B); the plan is a function of the letters",
           "alone, so every run gives the same counts. The target row is the S10 range.", ""]
    for per_day in (3, 1, 2, 4):
        runs = week_tallies[per_day].weekly
        weeks = runs[0]
        varied = any(r != runs[0] for r in runs)
        title = f"### {per_day} strength break{'s' if per_day > 1 else ''} a day"
        out += [title + (" (the default)" if per_day == 3 else ""), ""]
        out.append("| Week | " + " | ".join(PARTS) + " |")
        out.append("|---|" + "---:|" * len(PARTS))
        for index, week in enumerate(weeks):
            out.append(f"| {index + 1} | " + " | ".join(f"{week[p]:g}" for p in PARTS) + " |")
        if per_day == 3:
            out.append("| target | " + " | ".join(f"{RANGES[p][0]}–{RANGES[p][1]}" for p in PARTS) + " |")
            for index, week in enumerate(weeks):
                for p in PARTS:
                    low, high = RANGES[p]
                    if not low <= week[p] <= high:
                        problems.append(f"default week {index + 1}: {p} {week[p]:g} outside {low}–{high}")
        if varied:
            problems.append(f"weekly sets at {per_day} a day differ between runs")
        out.append("")
    return out


if __name__ == "__main__":
    sys.exit(main())
