"""Convert movez strength-library-vN.md to JSON and validate it.

Usage: python3 strength_md_to_json.py strength-library-v1.md [out.json]

Mirrors md_to_json.py (the v4 movement-library converter) but for the strength mode, whose
equipment is required rather than optional, and which adds load tiers and a grip flag.
Every assertion below encodes a rule from the library's design rules or routine rules, so a
library edit that breaks one fails loudly here instead of in the app.
"""
import json
import re
import sys

MD = sys.argv[1] if len(sys.argv) > 1 else 'strength-library-v1.md'
OUT = sys.argv[2] if len(sys.argv) > 2 else MD.replace('.md', '.json')
src = open(MD, encoding='utf-8').read()

BUCKETS = {
    "SQT": "Squat & lunge", "HNG": "Hinge & bridge", "PSH": "Push", "PUL": "Pull & upper back",
    "COR": "Core", "ACC": "Accessory & joint resilience", "END": "End-range strength & active flexibility",
}
FULL_BUCKETS = ["SQT", "PSH", "HNG", "PUL", "COR", "ACC"]
EQUIP = {"DB": "dumbbells", "KB": "kettlebell"}
LOAD = {"L": "light", "M": "moderate", "H": "heavy"}
REGIONS = {"Neck", "Shoulder", "Chest", "T-spine", "L-spine/Core", "Hip", "Glute", "Ham", "Quad",
           "Adductor", "Calf/Ankle", "Foot/Shin", "Wrist/Forearm", "Full", "Arm"}
SETTINGS = {"Stand", "Chair", "Desk", "Wall", "Floor", "Any"}

hdr = re.compile(
    r'^\*\*([A-Z]{3}-\d{2}) · (.+?)\*\* — (.+?) · (.+?) · (\d+) · Diff (\d) · (.+?)'
    r'(?: · Load ([LMH]))?(?: · (\*\*Grip\*\*))?(?: · (\*\*Micro\*\*))? · Counteracts: (.+?)\.\s*$\n\n(.+?)\n',
    re.M)

movements = []
for m in hdr.finditer(src):
    mid, name, region, dose, block, diff, setting, load, grip, micro, counter, instr = m.groups()
    sm = re.match(r'^(.*?)(?: \((.+?)\))?$', setting)
    settings = [s.strip() for s in sm.group(1).split('/')]
    equipment = [EQUIP[e] for e in sm.group(2).split('/')] if sm.group(2) else []
    movements.append({
        "id": mid, "name": name, "bucket": mid[:3], "bucket_name": BUCKETS[mid[:3]],
        "regions": [r.strip() for r in region.split(',')],
        "dose": dose, "per_side": "/side" in dose, "block_seconds": int(block),
        "difficulty": int(diff), "settings": settings, "on_floor": "Floor" in settings,
        "equipment": equipment, "load": LOAD[load] if load else None,
        "grip_demand": bool(grip), "micro_eligible": bool(micro),
        "counteracts": counter.strip(), "instructions": instr.strip(),
    })

# Every bold ID header in the document must have parsed; a silent miss would drop a movement.
header_ids = re.findall(r'^\*\*([A-Z]{3}-\d{2}) · ', src, re.M)
parsed_ids = [m['id'] for m in movements]
assert header_ids == parsed_ids, sorted(set(header_ids) - set(parsed_ids))
assert len(parsed_ids) == len(set(parsed_ids)), "duplicate id"
by_id = {m['id']: m for m in movements}

# Counts line in section 16 must match the data.
counts_line = re.search(r'^SQT (\d+) · HNG (\d+) · PSH (\d+) · PUL (\d+) · COR (\d+) · ACC (\d+) · END (\d+) — \*\*(\d+) movements', src, re.M)
stated = dict(zip(["SQT", "HNG", "PSH", "PUL", "COR", "ACC", "END"], map(int, counts_line.groups()[:7])))
for b, n in stated.items():
    assert sum(m['bucket'] == b for m in movements) == n, (b, n)
assert int(counts_line.group(8)) == len(movements)

LOW_REP = []
for m in movements:
    tag = m['id']
    assert set(m['regions']) <= REGIONS, (tag, m['regions'])
    assert set(m['settings']) <= SETTINGS, (tag, m['settings'])
    assert 1 <= m['difficulty'] <= 3, tag
    # Loaded movements carry a load tier; bodyweight movements don't.
    assert bool(m['equipment']) == (m['load'] is not None), tag
    # Swings are kettlebell-only by design.
    if 'swing' in m['name'].lower():
        assert m['equipment'] == ['kettlebell'], tag
    if m['bucket'] == 'END':
        # Micro pool: every END movement, bodyweight only, block 60 per-side or 30 two-sided.
        assert m['micro_eligible'] and not m['equipment'] and not m['grip_demand'], tag
        assert m['block_seconds'] == (60 if m['per_side'] else 30), tag
    else:
        assert not m['micro_eligible'], tag
        assert m['block_seconds'] == 60, tag
    # Rep targets fit the window: 12-20 two-sided, 8-12 a side. Slow multi-part reps (tempo
    # push-ups, walkouts, windmills, get-ups) go lower and are listed for review; holds are exempt.
    reps = re.match(r'^(\d+) reps', m['dose'])
    side = re.match(r'^(\d+)/side$', m['dose'])
    if reps and m['bucket'] != 'END':
        assert 6 <= int(reps.group(1)) <= 20, (tag, m['dose'])
        if int(reps.group(1)) < 12: LOW_REP.append((tag, m['dose']))
    if side and m['bucket'] != 'END':
        assert 3 <= int(side.group(1)) <= 12, (tag, m['dose'])
        if int(side.group(1)) < 8: LOW_REP.append((tag, m['dose']))

# Coverage: every full-routine slot can be filled without repeats on a busy day for every
# equipment selection, including bodyweight only.
SELECTIONS = {"none": set(), "dumbbells": {"dumbbells"}, "kettlebell": {"kettlebell"},
              "both": {"dumbbells", "kettlebell"}}

def eligible(m, owned):
    return not m['equipment'] or bool(owned & set(m['equipment']))

coverage = {}
for sel, owned in SELECTIONS.items():
    row = {}
    for b in FULL_BUCKETS:
        pool = [m for m in movements if m['bucket'] == b and eligible(m, owned)]
        row[b] = {"eligible": len(pool), "loaded": sum(bool(m['equipment']) for m in pool),
                  "diff_1_2": sum(m['difficulty'] <= 2 for m in pool)}
    row["COR+ACC"] = {"eligible": row["COR"]["eligible"] + row["ACC"]["eligible"]}
    coverage[sel] = row
    for b in ["SQT", "PSH", "HNG", "PUL"]:
        assert row[b]["diff_1_2"] >= 6, (sel, b, row[b])
    # Slot 1 needs warm-up-friendly squats: Diff 1-2, not heavy, not a swing.
    slot1 = [m for m in movements if m['bucket'] == 'SQT' and eligible(m, owned)
             and m['difficulty'] <= 2 and m['load'] != 'heavy']
    assert len(slot1) >= 6, (sel, len(slot1))
    if owned:
        for b in ["SQT", "PSH", "HNG", "PUL"]:
            assert row[b]["loaded"] >= 2, (sel, b)

def parse_blocks(line):
    blocks = []
    for chunk in line.split(' → '):
        ident = re.match(r'([A-Z]{3}-\d{2})', chunk.strip()).group(1)
        secs = int(re.search(r'\((\d+)\)\s*$', chunk.strip()).group(1))
        assert ident in by_id, ident
        blocks.append({"movement_id": ident, "seconds": secs})
    return blocks

routines = []
for m in re.finditer(r'^\*\*(SR\d+) — (.+?)\*\* \((.+?)\) — (\d+) s\n(.+)$', src, re.M):
    rid, name, focus, total, line = m.groups()
    blocks = parse_blocks(line)
    ms = [by_id[b['movement_id']] for b in blocks]
    # Section 11 rules, checked on every sample.
    assert [x['bucket'] for x in ms[:4]] == ["SQT", "PSH", "HNG", "PUL"], rid
    assert ms[4]['bucket'] in ("COR", "ACC"), rid
    assert ms[0]['difficulty'] <= 2 and ms[0]['load'] != 'heavy' and 'swing' not in ms[0]['name'].lower(), rid
    assert all('swing' not in x['name'].lower() for i, x in enumerate(ms) if i != 2), rid
    assert sum(x['on_floor'] for x in ms) <= 2, (rid, 'floor')
    assert sum(x['grip_demand'] for x in ms) <= 2 and not ms[4]['grip_demand'], (rid, 'grip')
    assert all(b['seconds'] == 60 for b in blocks), rid
    # Rule 8: Diff 3 only in samples labelled as past the unlock.
    if any(x['difficulty'] == 3 for x in ms):
        assert 'Diff 3 unlocked' in focus, (rid, 'diff 3')
    sum_blocks = sum(b['seconds'] for b in blocks)
    assert sum_blocks == int(total), rid
    routines.append({"id": rid, "name": name, "focus": focus, "target_seconds": int(total),
                     "sum_of_blocks": sum_blocks,
                     "equipment_used": sorted({e for x in ms for e in x['equipment']}),
                     "blocks": blocks})

micro_routines = []
for m in re.finditer(r'^(SM\d+) — (.+?): (.+)$', src, re.M):
    rid, name, line = m.groups()
    blocks = parse_blocks(line)
    ms = [by_id[b['movement_id']] for b in blocks]
    assert all(x['micro_eligible'] for x in ms), rid
    if len(ms) == 1:
        assert ms[0]['per_side'] and blocks[0]['seconds'] == 60, rid
    else:
        assert len(ms) == 2 and not any(x['per_side'] for x in ms), rid
        assert all(b['seconds'] == 30 for b in blocks), rid
        assert ms[0]['on_floor'] == ms[1]['on_floor'], (rid, 'level')
    micro_routines.append({"id": rid, "name": name, "target_seconds": 60,
                           "sum_of_blocks": sum(b['seconds'] for b in blocks), "blocks": blocks})

assert len(routines) == 8 and len(micro_routines) == 9, (len(routines), len(micro_routines))

# Section 15: overlap with v4, attached to each movement for cross-mode no-repeat.
seg = src[src.index("## 15. Overlap"):src.index("## 16. Counts")]
for sid, vid, kind in re.findall(r'^\| ([A-Z]{3}-\d{2}) \| ([A-Z]{3}-\d{2}) \| (same|similar) \|$', seg, re.M):
    assert sid in by_id, sid
    by_id[sid]['v4_overlap'] = {"id": vid, "kind": kind}
for m in movements:
    m.setdefault('v4_overlap', None)

def numbered(start, end):
    s = src[src.index(start):src.index(end)]
    return [re.sub(r'\*\*', '', t).strip() for t in re.findall(r'^\d+\. (.+)$', s, re.M)]

desk_effects = []
seg = src[src.index("## 2. What desk work does"):src.index("## 3. Metadata schema")]
for row in re.findall(r'^\| (.+?) \| (.+?) \| (.+?) \|$', seg, re.M)[2:]:
    desk_effects.append({"effect": row[0], "primary": row[1], "secondary": row[2]})

lib = {
    "library": "movez strength library", "mode": "strength", "version": "1",
    "source": "strength-library-v1.md", "generated": "2026-10-09",
    "schema": {
        "movement": {
            "id": "bucket prefix + 2-digit number",
            "bucket": "|".join(BUCKETS),
            "regions": "list of body regions (v4 regions plus Arm)",
            "dose": "rep target or hold sized to the block; '/side' = both sides, 30 s each; 'alternating' = sides alternate inside the block",
            "per_side": "true when the block splits into two 30 s halves with a side switch at the halfway chime",
            "block_seconds": "60 for full-routine buckets; END is 60 per-side or 30 two-sided",
            "difficulty": "1 easy, 2 moderate, 3 harder / more control",
            "settings": "every surface used: Stand, Chair, Desk, Wall, Floor, Any",
            "on_floor": "true when Floor is among the settings (routine rule 5)",
            "equipment": "REQUIRED, any one of: dumbbells (a pair), kettlebell (one). Empty = bodyweight. Differs from v4's equipment_optional.",
            "load": "light|moderate|heavy relative to what the user owns; null for bodyweight",
            "grip_demand": "true when it counts against the grip budget (routine rule 6)",
            "micro_eligible": "true for every END movement and nothing else",
            "counteracts": "desk-work effect targeted",
            "instructions": "in-app instruction text",
            "v4_overlap": "{id, kind} when the movement matches a v4 movement; 'same' counts as one for no-repeat when modes mix",
        },
        "regions": sorted({r for m in movements for r in m['regions']}),
        "settings": sorted({s for m in movements for s in m['settings']}),
        "equipment": sorted(EQUIP.values()),
        "load_tiers": {"light": "typically 2-6 kg", "moderate": "typically 6-12 kg", "heavy": "the heaviest the user owns, typically 12-24 kg"},
    },
    "design_rules": {
        "full_routine": {"movements": 5, "seconds_per_movement": 60, "per_side_split": 30, "lead_in_seconds": 5,
                          "slot_order": ["SQT", "PSH", "HNG", "PUL", "COR|ACC"]},
        "micro_routine": {"seconds": 60, "structure": "one per-side END movement (30 s a side) or two two-sided END movements (30 s each)",
                          "pool": "END", "equipment": "none", "floor_allowed": True, "chair_allowed": True},
        "rep_targets": {"two_sided": [12, 20], "per_side": [8, 12], "tempo_seconds_per_rep": 3, "swing_seconds_per_rep": 2,
                        "rule": "the timer wins: rest if reps finish early, stop if the window ends first"},
        "intensity": "RPE <= 7, about three reps in reserve; no grinding, breath-holding or grunting",
        "environment": "quiet, small office or cubicle; no jumping, no dropping weights; kettlebell swings allowed and parked gently",
        "equipment_allowed": ["bodyweight", "dumbbells", "kettlebell", "chair", "floor", "desk", "wall"],
        "goal": "maintain or slowly build strength; not hypertrophy",
    },
    "desk_effects": desk_effects,
    "buckets": [{"id": k, "name": v, "count": sum(m['bucket'] == k for m in movements)} for k, v in BUCKETS.items()],
    "full_routine_rules": numbered("## 11. Full strength routines", "## 12. Micro strength routines"),
    "micro_routine_rules": numbered("## 12. Micro strength routines", "## 13. Sample full strength routines"),
    "coverage": coverage,
    "movements": movements,
    "routines": routines,
    "micro_routines": micro_routines,
    "notes": [
        "Separate from movement-library-v4.json; IDs use new prefixes so both can load together.",
        "block_seconds is the scheduling unit; dose is display text (a rep target).",
        "equipment is required (any one of), unlike v4's equipment_optional; bodyweight movements have an empty list.",
    ],
}
json.dump(lib, open(OUT, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)

print(f"{len(movements)} movements -> {OUT}")
print("buckets:", {b['id']: b['count'] for b in lib['buckets']})
print("micro-eligible:", sum(m['micro_eligible'] for m in movements),
      "| per-side END:", sum(m['per_side'] for m in movements if m['bucket'] == 'END'),
      "| two-sided END:", sum(not m['per_side'] for m in movements if m['bucket'] == 'END'))
print("below rep-target range (slow reps):", LOW_REP)
print("grip-tagged:", [m['id'] for m in movements if m['grip_demand']])
for sel, row in coverage.items():
    print(f"coverage[{sel}]:", {b: v['eligible'] for b, v in row.items()})
for r in routines + micro_routines:
    print(r['id'], r['sum_of_blocks'], [b['movement_id'] for b in r['blocks']])
