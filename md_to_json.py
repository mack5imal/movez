"""Convert movez movement-library-vN.md to JSON. Usage: python3 md_to_json.py movement-library-v4.md [out.json]"""
import re, json
import sys
MD = sys.argv[1] if len(sys.argv)>1 else 'movement-library-v4.md'
OUT = sys.argv[2] if len(sys.argv)>2 else MD.replace('.md','.json')
src = open(MD).read()

BUCKETS = {"FLX":"Flexibility & mobility","CIR":"Blood flow & circulation","STR":"Strength","BAL":"Balance & proprioception","HWF":"Hands, wrists & forearms","EYE":"Eyes","BRE":"Breathing"}
EQUIP = {"KB":"kettlebell_or_dumbbell","Band":"band","Roller":"foam_roller","Ball":"ball"}

hdr = re.compile(r'^\*\*([A-Z]{3}-\d{2}) · (.+?)\*\* — (.+?) · (.+?) · (\d+) · Diff (\d) · (.+?) ·(?: \*\*Micro\*\* ·)? Counteracts: (.+?)\.?\s*$\n\n(.+?)\n', re.M)
movements=[]
for m in hdr.finditer(src):
    mid,name,region,dose,block,diff,setting,counter,instr = m.groups()
    micro = '**Micro**' in m.group(0)
    eq=[]
    sm = re.match(r'^(.*?)(?: \((.+?)\))?$', setting)
    settings = [s.strip() for s in sm.group(1).split('/')]
    if sm.group(2): eq=[EQUIP[e] for e in sm.group(2).split('/')]
    movements.append({
        "id":mid,"name":name,"bucket":mid[:3],"bucket_name":BUCKETS[mid[:3]],
        "regions":[r.strip() for r in region.split(',')],
        "dose":dose,"per_side":"/side" in dose,"block_seconds":int(block),
        "difficulty":int(diff),"settings":settings,"equipment_optional":eq,
        "micro_eligible":micro,"counteracts":counter.strip(),"instructions":instr.strip()})
assert len(movements)==147, len(movements)
assert sum(m['micro_eligible'] for m in movements)==65

def parse_blocks(line):
    blocks=[]
    for chunk in line.split(' → '):
        pieces=[p.strip() for p in chunk.split(' + ')]
        parsed=[]
        for p in pieces:
            ids=re.findall(r'[A-Z]{3}-\d{2}',p)
            secs=re.search(r'\((\d+)(?:, ([^)]+))?\)',p)
            note=None
            nm=re.search(r'[A-Z]{3}-\d{2}\s+(.*?)(?:\s*\(|$)',p)
            label=nm.group(1).strip() if nm else ''
            if ',' in label: label,note = [x.strip() for x in label.split(',',1)]
            if secs and secs.group(2): note=(note+'; ' if note else '')+secs.group(2)
            parsed.append({"ids":ids,"secs":int(secs.group(1)) if secs else None,"label":label,"note":note})
        # pieces without seconds share the next piece's seconds (e.g. "HWF-01 + HWF-02 ... (90)")
        missing=[q for q in parsed if q['secs'] is None]
        if missing:
            total=[q for q in parsed if q['secs']][-1]['secs']
            n=len(missing)+1
            for q in parsed: q['secs']=total//n
        for q in parsed:
            for i in q['ids']:
                blocks.append({"movement_id":i,"seconds":q['secs'],**({"note":q['note']} if q['note'] else {})})
    return blocks

routines=[]
for m in re.finditer(r'^\*\*(R\d) — (.+?)\*\* \((.+?)\) — (\d+) s\n(.+)$', src, re.M):
    rid,name,focus,total,line=m.groups()
    blocks=parse_blocks(line)
    routines.append({"id":rid,"name":name,"focus":focus,"target_seconds":int(total),"sum_of_blocks":sum(b['seconds'] for b in blocks),"blocks":blocks})
micro_routines=[]
for m in re.finditer(r'^(M\d) — (.+?): (.+)$', src, re.M):
    rid,name,line=m.groups()
    blocks=parse_blocks(line)
    micro_routines.append({"id":rid,"name":name,"target_seconds":60,"sum_of_blocks":sum(b['seconds'] for b in blocks),"blocks":blocks})

def numbered(section_start, section_end):
    seg=src[src.index(section_start):src.index(section_end)]
    return [re.sub(r'\*\*','',t).strip() for t in re.findall(r'^\d+\. (.+)$',seg,re.M)]
micro_rules=numbered("### Micro-break rules","### Micro-eligible movements")
chain_rules=numbered("## 12. Chaining rules","## 13. Sample full-break")

sitting_effects=[]
seg=src[src.index("## 2. What sitting does"):src.index("## 3. Metadata schema")]
for row in re.findall(r'^\| (.+?) \| (.+?) \| (.+?) \|$',seg,re.M)[2:]:
    sitting_effects.append({"effect":row[0],"primary":row[1],"secondary":row[2]})

lib={
 "library":"movez movement library","version":"4","source":"movement-library-v4.md","generated":"2026-09-11",
 "schema":{
   "movement":{"id":"bucket prefix + 2-digit number","bucket":"FLX|CIR|STR|BAL|HWF|EYE|BRE","regions":"list of body regions","dose":"human-readable time or reps; per_side=true means both sides and block_seconds already includes both","block_seconds":"approximate total block time","difficulty":"1 easy, 2 moderate, 3 harder / more control","settings":"where it can be done: Stand, Chair, Wall, Desk, Floor, Any","equipment_optional":"optional equipment; every item has a bodyweight substitute per chaining rule 6","micro_eligible":"true if allowed in the 1-minute micro-break","counteracts":"sitting effect targeted","instructions":"in-app instruction text"},
   "regions":sorted({r for m in movements for r in m['regions']}),
   "settings":sorted({s for m in movements for s in m['settings']}),
   "equipment":sorted(set(EQUIP.values()))},
 "design_rules":{"full_break_seconds":300,"blocks_per_break":{"default":4,"min":3,"max":5},"block_seconds_range":[60,90],"micro_break_seconds":60,"intensity":"low-sweat, RPE 5-6, 1-2 sets, no grip/forearm fatigue before typing","goal":"maintain or gradually increase strength; not hypertrophy"},
 "sitting_effects":sitting_effects,
 "buckets":[{"id":k,"name":v,"count":sum(m['bucket']==k for m in movements)} for k,v in BUCKETS.items()],
 "presets":[
   {"id":"25/5","sit_minutes":25,"break_minutes":5,"cycle_minutes":30,"micro_breaks_at_minutes":[],"micro_default_on":False,"label":"Evidence-optimal","description":"Matches the ~30-minute sitting-bout threshold in the research"},
   {"id":"55/5","sit_minutes":55,"break_minutes":5,"cycle_minutes":60,"micro_breaks_at_minutes":[30],"micro_default_on":True,"label":"Default","description":"Full dose every hour; micro-break keeps bouts under 30 min","default":True},
   {"id":"85/5","sit_minutes":85,"break_minutes":5,"cycle_minutes":90,"micro_breaks_at_minutes":[30,60],"micro_default_on":True,"label":"Deep work","description":"Long focus blocks, micro-breaks on by default"}],
 "custom_preset_rule":"micro-break every 30 minutes of sitting; drop any that would fall within 10 minutes of the full break",
 "micro_break":{"seconds":60,"structure":"one 60 s block or two 30 s blocks","eligibility":{"max_block_seconds":60,"no_floor":True,"no_equipment":True,"no_warmup":True,"no_sweat":True},"rules":micro_rules,"eligible_ids":[m['id'] for m in movements if m['micro_eligible']]},
 "chaining_rules":chain_rules,
 "balance_progression":["fingertip on wall","hands free","arms moving","head turning","eyes closed","soft surface"],
 "movements":movements,
 "routines":routines,
 "micro_routines":micro_routines}
# post-processing: trims, region normalisation, validation
ids={m['id'] for m in movements}
for r in routines+micro_routines:
    for b in r['blocks']:
        assert b['movement_id'] in ids, b
        t=re.search(r'trim to (\d+)', b.get('note',''))
        if t: b['seconds']=int(t.group(1))
    r['sum_of_blocks']=sum(b['seconds'] for b in r['blocks'])
    assert r['sum_of_blocks']==r['target_seconds'], (r['id'], r['sum_of_blocks'])
for m in movements:
    regs=[]
    for rg in m['regions']:
        if rg=='Core': rg='L-spine/Core'
        if rg=='Full spine': regs+=['T-spine','L-spine/Core']; continue
        regs.append(rg)
    m['regions']=list(dict.fromkeys(regs))
lib['schema']['regions']=sorted({rg for m in movements for rg in m['regions']})
lib['notes']=["Region labels normalised from the markdown: 'Core' -> 'L-spine/Core'; 'Full spine' -> ['T-spine','L-spine/Core'].",
              "block_seconds is the scheduling unit; dose is display text.",
              "Routine block 'note' carries per-routine adjustments (e.g. 'trim to 60', 'one direction only')."]
json.dump(lib, open(OUT,'w'), indent=2, ensure_ascii=False)
for r in routines+micro_routines: print(r['id'], r['target_seconds'], r['sum_of_blocks'], [ (b['movement_id'],b['seconds']) for b in r['blocks']])
print(len(micro_rules), len(chain_rules), len(sitting_effects))
