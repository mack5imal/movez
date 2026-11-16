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

The planner's arm break (the fourth break, the third under More arms, none for a kettlebell-only
kit), the builder's slot-keyed repeats, its arm warm-up and cool-down, the vigorous rung and the
focus weighting are mirrored as well.

The sixteen configurations are dumbbells x kettlebell x wall at difficulty caps 2 and 3 with every
difficulty-3 pattern unlocked, then each kit again with the More arms focus (wall, cap 2). Each
simulates whole days of six full breaks and six micro-breaks, the strength breaks a day cycling
through 1-4 so every setting is exercised, one strength break in ten skipped so the planner has to
offer it again, until each kind reaches 5,000. The weekly tables come from 5-day weeks at the app's
default settings, and at those defaults with dumbbells, with and without More arms, with every
break taken.

Writes docs/strength-simulation.md and Tests/movezTests/Fixtures/strength-simulation-picks.json,
four days of every configuration with each break's explicit context and the moves drawn, which
StrengthSimulationPicksTests rebuilds with the Swift code: that test, not this docstring, is what
shows the mirror is exact (DECISIONS 81). Prints a summary. Exits 1 on any violation, any eligible
move never served, or when the default week (3 a day, no focus, 5 days) leaves the research
targets; exits 2 when this script and strength-rules.json disagree on the rule list. With
`--check` it writes nothing and exits 3 when either committed file differs from what it would
write (`make simulate-check`).
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
PICKS = os.path.join(ROOT, "Tests", "movezTests", "Fixtures", "strength-simulation-picks.json")
PICK_DAYS = 4

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
    "BIC": {"biceps": 1},
    "TRI": {"triceps": 1},
    "COR": {"core": 1},
}
PARTS = ["quads", "glutes", "hamstrings", "chest", "back", "biceps", "triceps", "core"]
# The default week must land in these (S10); core counts direct sets only.
RANGES = {"quads": (8, 12), "chest": (8, 12), "back": (8, 12), "hamstrings": (8, 12),
          "glutes": (12, 18), "biceps": (4, 7), "triceps": (4, 7), "core": (4, 6)}


# ---------------------------------------------------------------- library


class Move:
    __slots__ = ("id", "name", "bucket", "regions", "dose", "per_side", "difficulty", "settings",
                 "floor", "equipment", "bodyweight", "vigorous", "grip", "micro", "seated", "same")

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
        self.vigorous = raw["vigorous"]
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
# StrengthDayLetter.armBucket: triceps on a push day, biceps on a pull day.
ARM = {"A": "TRI", "B": "BIC"}
# StrengthFocus.boostedRegions, weighted x3 in every strength-break draw.
BOOSTED = {"none": frozenset(), "moreLegsAndGlutes": frozenset({"Quad", "Glute", "Ham", "Adductor"}),
           "moreBackAndShoulders": frozenset({"T-spine", "Shoulder"}), "moreCore": frozenset({"L-spine/Core"}),
           "moreArms": frozenset({"Arm", "Wrist/Forearm"})}
# StrengthBreakBuilder.armCoolDownRegions: no END move stretches the arm, so the joints around it.
ARM_COOL_DOWN_REGIONS = frozenset({"Shoulder", "Chest", "Arm", "Wrist/Forearm"})

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
        self.boosted = BOOSTED[cfg["focus"]]
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


def arm_break_possible(equipment):
    """StrengthDayPlanner.armBreakPossible: the arm buckets have no kettlebell moves, so a
    kettlebell-only user has no vigorous arm move and no arm break."""
    return not equipment or "dumbbells" in equipment


def arm_position(focus, possible):
    """StrengthDayPlanner.armBreakPosition: 0-based, the fourth break or the third under More arms."""
    if not possible:
        return None
    return 2 if focus == "moreArms" else 3


def arm_index(per_day, focus, possible):
    """StrengthDayPlanner.armBreakIndex: the position, only when the day has more breaks than it."""
    position = arm_position(focus, possible)
    return position if position is not None and per_day > position else None


def is_arm(slot):
    return slot[0] in ("arm", "armAlternate")


def slot_bucket(slot):
    """StrengthBreakBuilder.bucket(for:)."""
    return "COR" if slot[0] == "core" else slot[1]


def replay(letter, breaks, prior_lead, arm_at=None):
    """StrengthDayPlanner.replay. A set order is a list of slots: ("pattern", b), ("core",),
    ("arm", b) and ("armAlternate", b). The pattern breaks step over the arm break: it counts no
    sets, leads with nothing and leaves the pattern-break counter where it was."""
    first, second = PATTERNS[letter]
    arm = ARM[letter]
    sets = {first: 0, second: 0}
    led_at = {}
    last_lead = None
    orders = []
    pattern_break = 0
    for index in range(max(0, breaks)):
        if index == arm_at:
            orders.append([("arm", arm), ("arm", arm), ("armAlternate", arm)])
            continue
        if pattern_break == 0:
            orders.append([("pattern", first), ("pattern", second), ("core",)])
            sets[first] += 1
            sets[second] += 1
            pattern_break += 1
            continue
        lead = choose_lead(first, second, sets, led_at, prior_lead)
        other = second if lead == first else first
        orders.append([("pattern", lead), ("pattern", other), ("pattern", lead)])
        sets[lead] += 2
        sets[other] += 1
        led_at[lead] = pattern_break
        last_lead = lead
        pattern_break += 1
    return orders, last_lead


class Planner:
    """StrengthDayPlanner.next over the completed strength breaks, one list of letters per day."""

    def __init__(self, focus, arm_possible):
        self.days = {}
        self.focus = focus
        self.arm_possible = arm_possible

    def letter(self, day):
        if self.days.get(day):
            return self.days[day][0]
        earlier = [k for k in self.days if k < day]
        if not earlier:
            return "A"
        return "B" if self.days[max(earlier)][0] == "A" else "A"

    def day_lead(self, day, prior_lead):
        """The lead a finished day leaves for the next day with its letter. As in
        StrengthDayPlanner.lastLead, an earlier day is replayed with the arm break at the
        position, without the breaks-a-day gate."""
        breaks = self.days[day]
        position = arm_position(self.focus, self.arm_possible)
        return replay(breaks[0], len(breaks), prior_lead, position)[1]

    def next(self, per_day, day, prior_leads):
        letter = self.letter(day)
        completed = len(self.days.get(day, []))
        if completed >= per_day:
            return ("endRange", None, None)
        arm_at = arm_index(per_day, self.focus, self.arm_possible)
        orders = replay(letter, completed + 1, prior_leads.get(letter), arm_at)[0]
        return ("strength", letter, orders[completed])

    def complete(self, day, letter):
        self.days.setdefault(day, []).append(letter)


# ---------------------------------------------------------------- builders


WORKING_LADDER = ["breakLimits", "servedToday", "vigorous", "excluded", "difficulty", "anything"]
WARM_UP_LADDER = ["warmUpShape", "servedToday", "excluded", "difficulty", "anything"]
COOL_DOWN_LADDER = ["coolDownRegion", "servedToday", "excluded", "difficulty", "anything"]
END_RANGE_LADDER = ["servedToday", "excluded", "difficulty", "anything"]
MICRO_LADDER = ["servedToday", "previousMicroRegion", "excluded", "difficulty", "anything"]


def draw_slot(slot, bucket, ladder, taken, ctx, state, slot_rule, narrow=None, weight=None):
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

    weight = weight or (lambda m: recency_multiplier(m, ctx.recency))
    pick = ladder_pick(slot, ladder, state, weight, candidates)
    return pick or (in_bucket[0] if in_bucket else LIB[0])


def vigorous_enough(m, equipment):
    """StrengthBreakBuilder.isVigorousEnough: with any kit selected only a vigorous move is a set."""
    return not equipment or m.vigorous


def build_strength(letter, order, ctx):
    state = DrawState(ctx.seed)
    arm_break = any(is_arm(slot) for slot in order)

    def weight(m):
        # Every draw of a strength break is weighted x3 for a move in a focus region.
        focus = 3.0 if ctx.boosted & m.regions else 1.0
        return focus * recency_multiplier(m, ctx.recency)

    warm_bucket = PATTERNS[letter][1] if is_arm(order[0]) else slot_bucket(order[0])
    warm = draw_slot("warmUp", warm_bucket, WARM_UP_LADDER, set(), ctx, state,
                     lambda m, g: m.bodyweight if "warmUpShape" in g else warm_up_shaped(m), weight=weight)
    drawn = []  # (slot, move) in draw order: repeats are keyed by slot, not by bucket
    working = []
    for index, slot in enumerate(order):
        repeated = next((m for s, m in drawn if s == slot), None)
        if repeated is not None:
            working.append(repeated)
            continue
        distinct = [m for _, m in drawn]
        taken = {m.id for m in distinct} | {warm.id}
        pick = draw_slot(f"set{index + 1}", slot_bucket(slot), WORKING_LADDER, taken, ctx, state,
                         lambda m, g, d=distinct: ("breakLimits" in g or fits_break_limits(m, d))
                         and ("vigorous" in g or vigorous_enough(m, ctx.equipment)),
                         lambda pool, g, d=distinct: narrow_break_limits(pool, g, d), weight=weight)
        drawn.append((slot, pick))
        working.append(pick)
    worked = ARM_COOL_DOWN_REGIONS if arm_break else set().union(*(m.regions for m in working))
    taken = {m.id for m in working} | {warm.id}
    cool = draw_slot("coolDown", "END", COOL_DOWN_LADDER, taken, ctx, state,
                     lambda m, g: "coolDownRegion" in g or bool(worked & m.regions), weight=weight)
    return {"kind": "strength", "letter": letter, "order": order, "warm": (warm, 30),
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
        "s6-arm-break", "s6-arm-alternate", "s6-vigorous-sets",
        "s7-end-only", "s7-no-floor", "s7-wall", "s7-distinct", "s7-shape", "s7-same-posture",
        "s7-previous-region", "s7-next-break-region", "s7-served-today", "s7-excluded", "s7-difficulty",
        "s22-letter", "s22-count", "s22-end-range-shape", "s22-end-range-distinct", "s22-end-range-wall",
        "s22-end-range-served-today", "s22-end-range-worked-regions", "s22-end-range-excluded",
        "s22-end-range-difficulty", "s22-arm-break-position",
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

    def arm_index(self, per_day):
        """Where today's arm break must fall, from the rules alone: the fourth break, the third
        under More arms, only with no kit or with dumbbells, and only when the day reaches it."""
        if self.cfg["equipment"] and "dumbbells" not in self.cfg["equipment"]:
            return None
        position = 2 if self.cfg["focus"] == "moreArms" else 3
        return position if per_day > position else None

    def check_plan(self, brk, day, per_day, done_today, pattern_done, sets_today):
        """`pattern_done` counts today's completed pattern breaks, `sets_today` their sets."""
        out = []
        should_be_strength = done_today < per_day
        if (brk["kind"] == "strength") != should_be_strength:
            out.append("s22-count")
        if brk["kind"] != "strength":
            return out
        letter = self.expected_letter(day)
        if brk["letter"] != letter:
            out.append("s22-letter")
        arm_break = any(is_arm(slot) for slot in brk["order"])
        if arm_break != (done_today == self.arm_index(per_day)):
            out.append("s22-arm-break-position")
        buckets = [m.bucket for m, _ in brk["sets"]]
        if arm_break:
            arm = ARM[letter]
            if brk["order"] != [("arm", arm), ("arm", arm), ("armAlternate", arm)] or buckets != [arm] * 3:
                out.append("s6-arm-break")
            return out
        first, second = PATTERNS[letter]
        if pattern_done == 0:
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

    def record_completed(self, brk, day, pattern_done):
        """An arm break leads with nothing, so only a later pattern break moves a lead."""
        self.letters.setdefault(day, brk["letter"])
        arm_break = any(is_arm(slot) for slot in brk["order"])
        if pattern_done > 0 and not arm_break:
            self.last_led[brk["sets"][0][0].bucket] = self.completed
        self.completed += 1

    def check_strength(self, brk, ctx):
        out = []
        warm, warm_seconds = brk["warm"]
        cool, cool_seconds = brk["cool"]
        sets = brk["sets"]
        order = brk["order"]
        moves = [m for m, _ in sets]
        arm_break = any(is_arm(slot) for slot in order)
        if len(sets) != 3 or warm is None or cool is None:
            out.append("s6-shape")
        # The same slot twice is the same move; two different slots are two different moves.
        pairs = [(i, j) for i in range(len(moves)) for j in range(i + 1, len(moves))]
        if len(order) != len(moves) or any((order[i] == order[j]) != (moves[i].id == moves[j].id) for i, j in pairs):
            out.append("s6-same-move-twice")
        if arm_break and (len(moves) != 3 or moves[2].bucket != moves[0].bucket or moves[2].id == moves[0].id):
            out.append("s6-arm-alternate")
        distinct = list(dict.fromkeys(moves))
        ids = [warm.id] + [m.id for m in distinct] + [cool.id]
        if len(set(ids)) != len(ids):
            out.append("s6-distinct")
        warm_bucket = PATTERNS[brk["letter"]][1] if arm_break else moves[0].bucket
        if warm.bucket != warm_bucket:
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
        universe = [m for m in BUCKET[warm_bucket] if self._possible(m)]
        out += soft_breaks(warm, universe, [("s6-warm-up-shape", warm_up_shaped)] + shared)
        vigorous = [("s6-vigorous-sets", lambda c: c.vigorous)] if self.cfg["equipment"] else []
        earlier = []
        for m in distinct:
            taken = {warm.id} | {e.id for e in earlier}
            universe = [c for c in BUCKET[m.bucket] if self._possible(c) and c.id not in taken]
            limits = [
                ("s6-per-side-limit", lambda c, e=earlier: not (c.per_side and any(x.per_side for x in e))),
                ("s6-floor-limit", lambda c, e=earlier: not (c.floor and any(x.floor for x in e))),
                ("s6-grip-limit", lambda c, e=earlier: not (c.grip and any(x.grip for x in e))),
            ]
            out += soft_breaks(m, universe, limits + vigorous + shared)
            earlier.append(m)
        worked = ARM_COOL_DOWN_REGIONS if arm_break else set().union(*(m.regions for m in moves))
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


def slot_code(slot):
    """A set-order slot as the picks fixture spells it: `pattern:SQT`, `core`, `arm:TRI`."""
    return slot[0] if len(slot) == 1 else f"{slot[0]}:{slot[1]}"


def relaxed_codes(brk):
    return [f"{slot}:{rule}" for slot, rule in brk["relaxed"]]


def drawn_ids(brk):
    """Every move a break serves in order, a repeated set included."""
    if brk["kind"] == "strength":
        return [brk["warm"][0].id] + [m.id for m, _ in brk["sets"]] + [brk["cool"][0].id]
    return [m.id for m, _ in brk["blocks"]]


def simulate(cfg, seed, per_day_for, until=None, days=None, skip=True, tally=None, trace=None):
    """Runs whole days with `cfg` until each kind of break reaches `until`, or for `days` days.

    With `trace`, each day is appended to it with every break's explicit context and the moves
    drawn, which is the picks fixture the Swift builders are checked against."""
    tally = tally or Tally()
    rng = SplitMix64(seed)
    planner = Planner(cfg["focus"], arm_break_possible(cfg["equipment"]))
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
        pattern_done = 0
        sets_today = Counter()
        events = None
        if trace is not None:
            events = []
            trace.append({"day": day, "perDay": per_day,
                          "recency": {k: v for k, v in sorted(recency.items()) if v > 0}, "events": events})
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
            if events is not None:
                events.append({"kind": "micro", "seed": str(micro_seed), "used": sorted(micro_ctx.used),
                               "lastMicro": sorted(micro_ctx.last_micro), "nextFull": sorted(micro_ctx.next_full),
                               "ids": drawn_ids(micro), "relaxed": relaxed_codes(micro)})
            tally.counts["micro"] += 1
            tally.micro_shapes[micro_shape(micro)] += 1
            tally.add_violations(checker.check_micro(micro, micro_ctx), micro)
            note_relaxed(tally, micro)
            serve(micro, served, history[day], tally, "micro")
            last_micro = set(ids_of(micro))

            brk, ctx = build_full(widen(served))
            event = None
            if events is not None:
                event = {"kind": "full", "seed": str(full_seed), "used": sorted(ctx.used),
                         "plan": "endRange" if kind != "strength" else
                         " ".join([letter] + [slot_code(s) for s in order]),
                         "avoiding": sorted(worked) if kind != "strength" else [],
                         "ids": drawn_ids(brk), "relaxed": relaxed_codes(brk), "skipped": False}
                events.append(event)
            tally.add_violations(checker.check_plan(brk, day, per_day, done_today, pattern_done, sets_today), brk)
            note_relaxed(tally, brk)
            if brk["kind"] == "strength":
                arm_break = any(is_arm(slot) for slot in brk["order"])
                tally.counts["armBuilt"] += arm_break
                tally.add_violations(checker.check_strength(brk, ctx), brk)
                if skip and rng.next() % SKIP_ONE_IN == 0:
                    tally.counts["skipped"] += 1
                    if event is not None:
                        event["skipped"] = True
                    continue
                tally.counts["strength"] += 1
                tally.counts["arm"] += arm_break
                checker.record_completed(brk, day, pattern_done)
                planner.complete(day, brk["letter"])
                done_today += 1
                if not arm_break:
                    pattern_done += 1
                for m, _ in brk["sets"]:
                    if not arm_break:
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
            lead = planner.day_lead(day, prior_leads.get(letter))
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
    arm_break = brk["kind"] == "strength" and any(is_arm(slot) for slot in brk["order"])
    for slot, rule in brk["relaxed"]:
        tally.relaxed[(brk["kind"], rule)] += 1
        if arm_break:
            tally.relaxed[("arm break", rule)] += 1


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
        # With kit selected a light bodyweight move is a warm-up only (DECISIONS 71), and the arm
        # buckets are drawn only by the arm break, which a kettlebell-only user never gets.
        if cfg["equipment"] and not m.vigorous:
            return False
        if m.bucket in ARM.values():
            return arm_break_possible(cfg["equipment"])
        return m.bucket in PART_SETS
    if role == "warm-up":
        return m.bucket in ("SQT", "PSH", "HNG", "PUL") and warm_up_shaped(m) and not shadowed_warm_up(cfg, m)
    if role in ("cool-down", "end-range", "endRange"):
        return m.bucket == "END"
    if role == "micro":
        return m.bucket == "END" and m.micro and not m.floor
    return False


def same_family(m):
    return FAMILY.get(m.same, m.same) if m.same else None


def shadowed_warm_up(cfg, m):
    """A warm-up-only move whose pattern's every working move shares its `same` family. The day's
    first break serves one of those as its set before the pattern ever leads, and S8 then counts
    the warm-up as served for the rest of the day, so it can only come back by letting go of a rule.
    With a kettlebell alone at cap 2 the push-up is the only vigorous push, and the desk incline
    push-up is its family."""
    family = same_family(m)
    if not cfg["equipment"] or m.vigorous or family is None:
        return False
    sets = [c for c in BUCKET[m.bucket] if eligible(cfg, "set", c)]
    return bool(sets) and all(same_family(c) == family for c in sets)


ROLES = [("set", b) for b in ("SQT", "HNG", "PSH", "PUL", "BIC", "TRI", "COR")] + [
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


def per_day_cycle(day):
    """1, 2, 3, 4, shifted by one every four days. A plain 1-4 cycle would keep each setting on one
    letter, since the letters alternate daily, and the arm break of a 4-a-day day would only ever
    be biceps."""
    return 1 + (day + day // 4) % 4


def configuration(kit, wall, cap, focus="none"):
    name = (" + ".join(sorted(kit)) or "bodyweight") + (", wall" if wall else ", no wall") + f", cap {cap}"
    if focus == "moreArms":
        name += ", More arms"
    return {"name": name, "short": short_name(kit, wall, cap, focus), "equipment": frozenset(kit),
            "wall": wall, "cap": cap, "unlocked": frozenset(BUCKET), "focus": focus}


def configurations():
    """The sixteen kit x wall x cap configurations, then every kit with More arms at cap 2, so the
    arm break at the third break and the kettlebell-only path without one are both covered."""
    out = []
    for cap in (2, 3):
        for dumbbells in (False, True):
            for kettlebell in (False, True):
                for wall in (True, False):
                    kit = {e for e, has in (("dumbbells", dumbbells), ("kettlebell", kettlebell)) if has}
                    out.append(configuration(kit, wall, cap))
    for kit in (set(), {"dumbbells"}, {"kettlebell"}, {"dumbbells", "kettlebell"}):
        out.append(configuration(kit, True, 2, "moreArms"))
    return out


def short_name(kit, wall, cap, focus="none"):
    return ("D" if "dumbbells" in kit else "-") + ("K" if "kettlebell" in kit else "-") + \
        ("W" if wall else "-") + str(cap) + ("a" if focus == "moreArms" else "")


DEFAULT = {"name": "app defaults: bodyweight, wall, cap 1", "short": "def", "equipment": frozenset(),
           "wall": True, "cap": 1, "unlocked": frozenset(), "focus": "none"}
# The defaults with dumbbells, so the weekly tables show arm work drawn under the vigorous rule.
DUMBBELLS = dict(DEFAULT, name="app defaults with dumbbells: dumbbells, wall, cap 1", short="dbl",
                 equipment=frozenset({"dumbbells"}))
WEEK_CONFIGS = [DEFAULT, DUMBBELLS]
FOCI = ("none", "moreArms")
FOCUS_NAMES = {"none": "no focus", "moreArms": "More arms"}


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
        tally = simulate(cfg, 0x5EED_0000 + index, per_day_cycle, until=TARGET)
        tallies.append(tally)

    # Keyed (configuration code, focus, strength breaks a day); the default week keeps its seeds.
    week_tallies = {}
    for base in WEEK_CONFIGS:
        for focus in FOCI:
            cfg = dict(base, focus=focus)
            salt = 0 if base is DEFAULT and focus == "none" else 0x1000 * (1 + WEEK_CONFIGS.index(base)) + \
                (0x100 if focus == "moreArms" else 0)
            for per_day in (1, 2, 3, 4):
                tally = Tally()
                for run in range(WEEK_RUNS):
                    simulate(cfg, 0x7EE4_0000 + salt + 100 * per_day + run, lambda day, n=per_day: n,
                             days=10, skip=False, tally=tally)
                week_tallies[(base["short"], focus, per_day)] = tally

    problems = []
    lines = report(configs, tallies, week_tallies, problems)
    outputs = {REPORT: "\n".join(lines) + "\n", PICKS: picks_fixture(configs)}
    if "--check" in sys.argv[1:]:
        stale = [path for path, text in outputs.items() if not os.path.exists(path) or open(path).read() != text]
        for path in stale:
            say(f"{os.path.relpath(path, ROOT)} is out of date: run python3 -I scripts/simulate_strength.py", sys.stderr)
        if stale:
            return 3
    else:
        for path, text in outputs.items():
            with open(path, "w") as handle:
                handle.write(text)

    total_v = sum(sum(t.violations.values()) for t in tallies + list(week_tallies.values()))
    say(f"configurations: {len(configs)} + default weeks; elapsed {time.time() - started:.0f} s")
    for cfg, tally in zip(configs, tallies):
        c = tally.counts
        say(f"  {cfg['name']:<50} strength {c['strength']:>5} (skipped {c['skipped']:>4})  "
              f"end-range {c['endRange']:>5}  micro {c['micro']:>5}  violations {sum(tally.violations.values())}")
    week = week_tallies[("def", "none", 3)].weekly
    say("default week (3 a day, 5 days), weekly hard sets: " + ", ".join(
        f"{p} {week[0][0][p]:g}/{week[0][1][p]:g}" for p in PARTS) + " (week 1/week 2)")
    say(f"violations: {total_v}; problems: {len(problems)}")
    for problem in problems:
        say(f"  {problem}")
    say(f"report: {os.path.relpath(REPORT, ROOT)}")
    return 1 if problems else 0


def picks_fixture(configs):
    """Four days of every configuration, the strength breaks a day running 1 to 4 so the last day
    reaches the arm break, with each break's explicit context and the moves it drew.
    StrengthSimulationCrossCheckTests rebuilds every one with the Swift planner and builders and
    requires the same plan, the same moves and the same relaxations, so this script cannot drift
    from the app unnoticed (TST-1)."""
    out = []
    for index, cfg in enumerate(configs):
        trace = []
        simulate(cfg, 0xF1C5_0000 + index, lambda day: 1 + day % 4, days=PICK_DAYS, trace=trace)
        out.append({"name": cfg["name"], "equipment": sorted(cfg["equipment"]), "wall": cfg["wall"],
                    "cap": cfg["cap"], "unlocked": sorted(cfg["unlocked"]), "focus": cfg["focus"],
                    "days": trace})
    return json.dumps({"about": "Generated by scripts/simulate_strength.py; do not edit by hand.",
                       "configurations": out}, indent=1, sort_keys=True) + "\n"


def week_code(short, focus, per_day):
    return f"{short}{per_day}" + ("a" if focus == "moreArms" else "")


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
        f"{FULL_PER_DAY} micro-breaks with the strength breaks a day cycling 1, 2, 3, 4 (shifted a day every four",
        "days, so each setting meets both letters), skips one strength",
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
    for (short, focus, n), t in week_tallies.items():
        c = t.counts
        v = sum(t.violations.values())
        base = next(w for w in WEEK_CONFIGS if w["short"] == short)
        out.append(f"| {base['name']}, {FOCUS_NAMES[focus]}, {n} a day, {WEEK_RUNS} × 2 weeks | "
                   f"`{week_code(short, focus, n)}` | {c['strength']:,} | 0 | "
                   f"{c['endRange']:,} | {c['micro']:,} | {v} |")
        if v:
            problems.append(f"{base['name']} weeks, {FOCUS_NAMES[focus]}, {n} a day: {v} violations")

    out += ["", "The codes read dumbbells, kettlebell, wall, then the difficulty cap; a trailing `a` is the",
            "More arms focus. `def` is the app's defaults and `dbl` the defaults with dumbbells, followed",
            "by the strength breaks a day.", "",
            "## Violations by rule", "",
            "Every rule in `scripts/strength-rules.json`, per configuration. Every cell must be 0.", ""]
    codes = [c["short"] for c in configs] + [week_code(*key) for key in week_tallies]
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
            f"and rule, summed over the {len(configs)} configurations; the `arm break` rows are the part of the",
            "strength rows drawn for arm breaks. These are the ladders doing their job, not violations: each",
            "one was checked above and no move that kept the rule was available.", "",
            "| Break | Rule let go | Times | Per 1,000 breaks of that kind |", "|---|---|---:|---:|"]
    relaxed = Counter()
    totals = Counter()
    for t in tallies:
        relaxed.update(t.relaxed)
        totals["strength"] += t.counts["strength"] + t.counts["skipped"]
        totals["endRange"] += t.counts["endRange"]
        totals["micro"] += t.counts["micro"]
        totals["arm break"] += t.counts["armBuilt"]
    for (kind, rule), n in sorted(relaxed.items()):
        out.append(f"| {kind} | `{rule}` | {n:,} | {1000 * n / totals[kind]:.1f} |")
    out += per_config_relaxations(configs, tallies)
    shapes = Counter()
    for t in tallies:
        shapes.update(t.micro_shapes)
    out += ["", f"Micro-break shapes over the {len(configs)} configurations: " + ", ".join(
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
    out += ["", f"Not drawn by any strength-mode break: {acc}. The arm moves (BIC, TRI) are drawn only by the",
            "arm break (DECISIONS 70), which a kettlebell-only kit never gets, so they are eligible only where",
            "that break can happen. With any kit selected a working set must be vigorous (DECISIONS 71), so a",
            "light bodyweight move is eligible there only as a warm-up, and only when it has the warm-up shape."]

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


def per_config_relaxations(configs, tallies):
    """Strength-break relaxations per configuration, per 1,000 strength breaks built, so a kit whose
    pools run short (kettlebell-only, above all, under the vigorous rule) stands out."""
    rules = [r for r in WORKING_LADDER + WARM_UP_LADDER + COOL_DOWN_LADDER if r != "anything"]
    rules = list(dict.fromkeys(rules)) + ["anything"]
    # The vigorous rung is always shown, so that a column of zeros says it never had to let go.
    used = [r for r in rules if r == "vigorous" or any(t.relaxed[("strength", r)] for t in tallies)]
    out = ["", "Strength-break relaxations per configuration, per 1,000 strength breaks built (skipped ones",
           "included), with the arm-break share of the `vigorous` count in brackets. `vigorous` is the rung",
           "that lets a light bodyweight move be a working set when nothing vigorous is left.", ""]
    out.append("| Config | " + " | ".join(f"`{r}`" for r in used) + " |")
    out.append("|---|" + "---:|" * len(used))
    for cfg, t in zip(configs, tallies):
        built = t.counts["strength"] + t.counts["skipped"]
        cells = []
        for r in used:
            n = t.relaxed[("strength", r)]
            cell = f"{1000 * n / built:.1f}" if n else "0"
            if r == "vigorous" and n:
                cell += f" ({1000 * t.relaxed[('arm break', r)] / built:.1f})"
            cells.append(cell)
        out.append(f"| `{cfg['short']}` | " + " | ".join(cells) + " |")
    return out


def weekly(week_tallies, problems):
    out = ["## Weekly hard sets per body part", "",
           "From 5-day weeks with every break taken, at the app's default settings and at those defaults",
           "with dumbbells, each with no focus and with More arms. A direct set counts 1 and a helper set ½:",
           "squat/lunge gives quads 1 and glutes ½, hinge hamstrings 1 and glutes 1, push chest 1 and",
           "triceps ½, pull back 1 and biceps ½, core 1, and an arm break's biceps or triceps sets 1 each.",
           "The arm break is the fourth break of a day (the third under More arms), so it adds three biceps",
           "or triceps sets a day at 4 a day, and at 3 or 4 a day under More arms. Letters alternate across",
           "weeks, so week 1 starts on an A day (A B A B A) and week 2 on a B day (B A B A B); the plan is a",
           "function of the letters alone, so every run gives the same counts.", "",
           "Only the default week (3 a day, no focus, app defaults) is held to the S10 target row; the",
           "other tables are reported so that arm targets can be set from them.", ""]
    for base in WEEK_CONFIGS:
        out += [f"### {base['name']}", ""]
        for focus in FOCI:
            for per_day in (3, 1, 2, 4):
                runs = week_tallies[(base["short"], focus, per_day)].weekly
                weeks = runs[0]
                varied = any(r != runs[0] for r in runs)
                default = base is DEFAULT and focus == "none" and per_day == 3
                title = f"#### {per_day} strength break{'s' if per_day > 1 else ''} a day, {FOCUS_NAMES[focus]}"
                out += [title + (" (the default)" if default else ""), ""]
                out.append("| Week | " + " | ".join(PARTS) + " |")
                out.append("|---|" + "---:|" * len(PARTS))
                for index, week in enumerate(weeks):
                    out.append(f"| {index + 1} | " + " | ".join(f"{week[p]:g}" for p in PARTS) + " |")
                if default:
                    out.append("| target | " + " | ".join(f"{RANGES[p][0]}–{RANGES[p][1]}" for p in PARTS) + " |")
                    for index, week in enumerate(weeks):
                        for p in PARTS:
                            low, high = RANGES[p]
                            if not low <= week[p] <= high:
                                problems.append(f"default week {index + 1}: {p} {week[p]:g} outside {low}–{high}")
                if varied:
                    problems.append(f"weekly sets for {week_code(base['short'], focus, per_day)} differ between runs")
                out.append("")
    return out


if __name__ == "__main__":
    sys.exit(main())
