# movez — Strength Library v1

Library of strength movements for the **Strength builder** mode planned for Movez v2. It sits beside `movement-library-v4.md`, which stays the library for the original movement mode. The format matches v4: one header line per movement, a blank line, then the in-app instructions. Bucket prefixes are new so no ID collides with v4.

The mode builds two things from this library. A **full strength routine** is five movements of 60 s each: a squat or lunge, a push, a hinge, a pull, and a core or accessory movement. A **micro-routine** is about 60 s of bodyweight end-range work: active stretching and strength in the parts of the range that a day at a desk never reaches.

## 1. Design rules

- **Shape.** A full routine is 5 movements × 60 s, or 30 s a side for a per-side movement, each after the app's 5 s lead-in (5:25 in total, the same shape as a movement-mode break). A micro-routine is one per-side movement at 30 s a side, or two two-sided movements at 30 s each (the movement-mode micro rule, DECISIONS 30).
- **Doses are rep targets sized to the window.** People think in reps when lifting, so each dose is the number of reps that fits the minute at a controlled tempo of about 3 s a rep (about 2 s for swings). Two-sided movements target **12–20 reps**. Per-side movements target **8–12 a side** in each 30 s half. Slow, multi-part movements (tempo push-ups, walkouts, windmills, get-ups) use fewer reps so every rep stays controlled. Isometric holds are given in seconds. The timer always wins: if the reps run out early, rest until the next movement; if the minute ends first, stop.
- **Effort ceiling: RPE 7.** Every set should end with about three good reps still in reserve. High reps at moderate effort mean no grinding, no breath-holding, and no grunting. If a rep target can't be reached in good form, the user drops the load or the app serves the bodyweight version.
- **Quiet and small.** No jumping and no dropping weights. Kettlebell swings are allowed, and the bell is always parked gently on the floor. Everything fits in a small office or cubicle: about a 2 m × 2 m square, with clear space in front of and behind the body for swings.
- **Equipment.** Bodyweight, **dumbbells** (assumed to be a pair), and **one kettlebell**. The user selects what they own and the app serves only movements they can do. Nothing else is allowed: no bands, rollers, balls, towels, steps, benches, or bars. A chair and the floor are always available. When a movement puts weight on the chair (a foot, the back, the hands or a knee on the seat), it should be a fixed four-legged chair, or an office chair with its swivel and tilt locked, pushed against a wall or the desk so it can't roll. **Wall** movements need a solid wall, not a cubicle partition; the user should be able to switch walls off the way they switch off equipment (section 11, rule 3).
- **Grip budget.** The user goes back to typing straight after a routine, so grip-heavy movements (tagged **Grip**) are capped per routine and never come last (section 11).
- **Goal.** Maintain strength or build it slowly; this is not a hypertrophy program. Progress comes from the difficulty ladder (tempo, range, single-leg versions, then load), not from adding reps beyond the target.
- **Micro-routines are bodyweight only.** The floor and the chair are both allowed, so floor-based end-range work (lift-offs, contract-relax holds) is in the pool.
- **No per-movement cautions.** Safety stays in the app disclaimer, as in v4.

## 2. What desk work does to strength, and which buckets answer it

| Effect of long days of sitting and screen work | Primary counter | Secondary |
|---|---|---|
| Glutes and hip extensors go unused for hours ("gluteal amnesia") | HNG | ACC (hip abduction) |
| Quad and sit-to-stand strength decline, faster with age | SQT | ACC (wall-free calf and shin work) |
| Mid/lower traps and rear shoulders weaken while pecs and upper traps dominate | PUL | END (shoulder lift-offs) |
| Pushing capacity fades with nothing to push against | PSH | COR |
| Trunk stabilizers switch off in a supported seat | COR | HNG (back extensions) |
| Calf, soleus, and shin strength lost to little walking | ACC | END (ankle) |
| Frontal-plane weakness (adductors, abductors) from forward-only movement | SQT (lateral lunges) | ACC |
| End ranges never visited: deep hip flexion, hip rotation, overhead and behind-the-back shoulder range, spinal extension and rotation | END | — |
| Weak deep neck flexors, forward head | ACC (head lift) | END (neck) |

## 3. Metadata schema

Each entry is formatted as:

**ID · Movement name** — Region · Dose · Block seconds · Diff · Setting (equipment) · [Load] · [**Grip**] · [**Micro**] · Counteracts: ….

Instructions (2–4 sentences: setup, the movement, the one cue that matters most), always separated from the header line by a blank line. The header ends with a period after the Counteracts text.

- **Region** — the v4 regions (Neck, Shoulder, Chest, T-spine, L-spine/Core, Hip, Glute, Ham, Quad, Adductor, Calf/Ankle, Foot/Shin, Wrist/Forearm, Full) plus **Arm** (triceps), which v4 never needed.
- **Dose** — a rep target or a hold. "/side" means both sides, 30 s each, with the switch at the halfway chime. "alternating" means sides alternate rep by rep inside the minute; it is not a per-side movement.
- **Block** — always 60 for full-routine buckets. In END, a per-side movement is 60 (30 s a side) and a two-sided movement is 30, so two of them make one micro-routine.
- **Diff** — 1 easy, 2 moderate, 3 harder or needs more control.
- **Setting** — every surface the movement uses, plus Stand when the user is on their feet: Stand, Chair, Desk, Wall, Floor. "Floor/Chair" means both, e.g. sitting on the floor with the back against a chair. Optional balance support (a fingertip on the desk) isn't listed, and where the instructions offer an alternative surface only the main one is. A movement with Floor anywhere in its setting gets the user down on the floor.
- **Equipment** — in parentheses, and **required, any one of**: (DB) a pair of dumbbells, (KB) the kettlebell, (DB/KB) either works and the instructions cover both. No parentheses means bodyweight. This is a change from v4, where equipment in parentheses was optional.
- **Load** — weighted movements only. How heavy the weight should be relative to what the user owns: **L** light (shoulder isolation work, typically 2–6 kg), **M** moderate (typically 6–12 kg), **H** heavy (the heaviest thing they own, typically a 12–24 kg kettlebell or the heavy dumbbells). The tiers let v2 match movements to the weights the user owns. A single kettlebell is often 12–24 kg, so a kettlebell listed on a Load M or L movement assumes a lighter bell (about 8–12 kg); if the user's bell is heavier, the app should skip the kettlebell version of those movements. Asking for the bell's weight at setup would settle this (section 11, rule 3).
- **Grip** — present when the movement taxes the grip or forearms enough to count against the grip budget.
- **Micro** — present when the movement is eligible for a micro-routine. Every END movement has it, and nothing outside END does.

Buckets: **SQT** squat & lunge, **HNG** hinge & bridge, **PSH** push, **PUL** pull & upper back, **COR** core, **ACC** accessory & joint resilience, **END** end-range strength & active flexibility.

---

## 4. SQT — Squat & lunge (knee-dominant)

**SQT-01 · Bodyweight squat** — Quad, Glute · 20 reps · 60 · Diff 1 · Stand · Counteracts: quad and glute deconditioning from sitting.

Stand with feet shoulder width, toes turned out slightly, arms reaching forward for balance. Sit the hips back and down as low as you can with the heels flat and the chest up, then stand and squeeze the glutes at the top. Keep a steady rhythm of about 3 s a rep, with the knees tracking over the toes.

**SQT-02 · Tempo squat** — Quad, Glute · 10 reps · 60 · Diff 2 · Stand · Counteracts: quad and glute deconditioning.

Same stance as the bodyweight squat. Take 3 s to lower, pause for 1 s at the bottom without bouncing, then stand up in 1 s. The slow lowering is the point: it builds strength without any load.

**SQT-03 · Chair sit-to-stand** — Quad, Glute · 15 reps · 60 · Diff 1 · Chair · Counteracts: loss of sit-to-stand strength.

Sit on the front half of the chair, feet hip width and slightly behind the knees; if it's an office chair, lock the swivel and push it back against the desk or a wall first. Lean the chest forward and stand up without using your hands. Sit back down slowly, taking 2–3 s, and only brush the seat before standing again.

**SQT-04 · Goblet squat** — Quad, Glute, Hip · 15 reps · 60 · Diff 2 · Stand (DB/KB) · Load M · Counteracts: lower-body strength loss, stiff hips.

Hold one dumbbell upright by its top end, or the kettlebell by the horns, against your chest with the elbows pointing down. With feet shoulder width, squat as low as is comfortable, elbows tracking inside the knees and chest tall, then stand and squeeze the glutes. Keep the weight touching your chest the whole time.

**SQT-05 · Dumbbell front squat** — Quad, Glute, L-spine/Core · 15 reps · 60 · Diff 2 · Stand (DB) · Load M · Counteracts: quad weakness, slumped trunk.

Rest one end of each dumbbell on the front of your shoulders, elbows high and pointing forward. Squat down with the chest tall and the elbows staying up, then drive up through the whole foot. If the elbows drop the weights tip forward, so think "elbows up" on every rep.

**SQT-06 · Suitcase squat** — Quad, Glute, L-spine/Core · 10/side · 60 · Diff 2 · Stand (DB/KB) · Load M · **Grip** · Counteracts: quad weakness, lateral core weakness.

Hold one dumbbell or the kettlebell at your side like a suitcase, arm long. Squat until the weight nearly touches the floor, staying level, without letting the shoulders tilt toward the weight. Switch hands at the halfway chime.

**SQT-07 · Split squat** — Quad, Glute, Hip · 10/side · 60 · Diff 1 · Stand · Counteracts: hip flexor shortening, single-leg weakness.

Stand in a long stride with the rear heel up and the feet hip width apart side to side, as if on train tracks. Lower straight down until the rear knee hovers just above the floor, torso upright, then push through the front foot to rise. Do all the reps on one side, then switch at the chime. A fingertip on the desk for balance is fine.

**SQT-08 · Loaded split squat** — Quad, Glute, Hip · 10/side · 60 · Diff 2 · Stand (DB/KB) · Load M · **Grip** · Counteracts: single-leg weakness, hip flexor shortening.

Set up as for the split squat, holding a dumbbell in each hand at your sides or the kettlebell at your chest. Lower until the rear knee hovers above the floor, keep the torso tall, and drive up through the front heel. Switch legs at the chime.

**SQT-09 · Reverse lunge** — Glute, Quad · 10/side · 60 · Diff 1 · Stand · Counteracts: glute inhibition.

From standing, step one foot back and lower until both knees are at about 90°, torso tall. Push through the front heel to bring the back foot forward to standing. Do all the reps on one leg, then switch. Set the back foot down softly; no stomping.

**SQT-10 · Loaded reverse lunge** — Glute, Quad · 8/side · 60 · Diff 2 · Stand (DB/KB) · Load M · **Grip** · Counteracts: glute inhibition, single-leg weakness.

Hold a dumbbell in each hand at your sides, or the kettlebell at your chest. Step back into the lunge and lower until the back knee hovers, then drive through the front heel to return to standing. Finish one side, then switch.

**SQT-11 · Lateral lunge** — Adductor, Quad, Glute · 8/side · 60 · Diff 2 · Stand · Counteracts: no side-to-side loading, stiff adductors.

From a wide stance with toes forward, sit back into one hip, bending that knee while the other leg stays straight. Keep the bent-side heel down and the chest up, then push back to centre. Do all the reps to one side, then switch.

**SQT-12 · Goblet lateral lunge** — Adductor, Quad, Glute · 8/side · 60 · Diff 2 · Stand (DB/KB) · Load M · Counteracts: no side-to-side loading, adductor weakness.

Hold a dumbbell or the kettlebell at your chest as for a goblet squat. From a wide stance, sit into one hip with the other leg straight, then push back to centre. Finish one side, then switch. Go only as deep as you can with the bent-side heel flat.

**SQT-13 · Curtsy lunge** — Glute, Quad, Adductor · 10/side · 60 · Diff 2 · Stand · Counteracts: weak side glutes, hip stiffness.

Stand tall, then step one foot diagonally behind and across the other, as if curtsying, and bend both knees. Keep the front knee over the front foot and the hips facing forward, then push through the front heel to return. Finish one side, then switch.

**SQT-14 · Rear-foot-elevated split squat** — Quad, Glute, Hip · 8/side · 60 · Diff 3 · Stand/Chair · Counteracts: single-leg weakness, hip flexor shortening.

Use a fixed chair, or lock an office chair's swivel and push it against a wall or desk so it can't move, then stand about a stride in front of it, facing away. Rest the top of your rear foot on the seat, lower straight down until the front thigh is near parallel with the torso tall, and drive up through the front heel. Switch legs at the chime.

**SQT-15 · Loaded rear-foot-elevated split squat** — Quad, Glute, Hip · 8/side · 60 · Diff 3 · Stand/Chair (DB/KB) · Load M · Counteracts: single-leg weakness.

Same setup as the rear-foot-elevated split squat, holding a dumbbell in each hand at your sides or the kettlebell at your chest. Lower until the front thigh is near parallel, keeping the weight over the front foot, then drive up through the heel. Switch legs at the chime.

**SQT-16 · Wall sit** — Quad · 45–60 s · 60 · Diff 1 · Wall · Counteracts: quad deconditioning.

Lean your back against a wall and walk the feet forward, sliding down until the thighs are roughly parallel to the floor and the knees are over the ankles. Keep the whole back and head against the wall and breathe normally. If it burns too much before the minute is up, slide a little higher rather than stopping.

## 5. HNG — Hinge & bridge (hip-dominant)

**HNG-01 · Glute bridge** — Glute, Ham · 15 reps · 60 · Diff 1 · Floor · Counteracts: glute inhibition.

Lie on your back with knees bent, feet flat and hip width, arms at your sides. Drive through the heels to lift the hips until the body is straight from shoulders to knees, squeeze the glutes for 1 s, then lower slowly. Don't arch the low back to get higher.

**HNG-02 · Single-leg glute bridge** — Glute, Ham · 10/side · 60 · Diff 2 · Floor · Counteracts: glute inhibition, side-to-side imbalance.

Set up as for the glute bridge, then lift one foot off the floor with the knee bent. Push through the planted heel to raise the hips, keeping both hip bones level, then lower. Switch legs at the chime.

**HNG-03 · Loaded glute bridge** — Glute, Ham · 15 reps · 60 · Diff 1 · Floor (DB/KB) · Load H · Counteracts: glute inhibition.

Lie on your back, knees bent, and rest one dumbbell across your hip bones, or the kettlebell on its side with the bell on your lower belly, steadied with both hands. Drive through the heels to lift the hips until the body is straight from shoulders to knees, squeeze for 1 s, and lower under control. Keep the weight still; the hips do the moving.

**HNG-04 · Chair-edge hip thrust** — Glute · 15 reps · 60 · Diff 2 · Floor/Chair · Counteracts: glute inhibition.

Use a fixed chair, or lock an office chair's swivel and tilt and push it against a wall or desk, then sit on the floor with your upper back against the front edge of the seat, knees bent and feet flat. Tuck the chin and drive through the heels until the thighs are level with the torso, squeeze the glutes, then lower under control.

**HNG-05 · Loaded chair-edge hip thrust** — Glute · 15 reps · 60 · Diff 2 · Floor/Chair (DB/KB) · Load H · Counteracts: glute inhibition, posterior chain weakness.

Same setup as the chair-edge hip thrust, with a dumbbell across your hip bones or the kettlebell resting on your lower belly, held steady with both hands. Drive through the heels until the thighs are level with the torso, squeeze for 1 s, and lower slowly.

**HNG-06 · Single-leg chair-edge hip thrust** — Glute, Ham · 8/side · 60 · Diff 3 · Floor/Chair · Counteracts: glute inhibition, side-to-side imbalance.

Set up as for the chair-edge hip thrust, then lift one foot with the knee bent. Drive through the planted heel until the thigh is level with the torso, keeping the hips square, then lower. Switch legs at the chime.

**HNG-07 · Bodyweight good morning** — Ham, Glute, L-spine/Core · 15 reps · 60 · Diff 1 · Stand · Counteracts: posterior chain weakness, lost hip hinge.

Stand with feet hip width, knees soft, fingertips lightly behind your head. Push the hips straight back, letting the torso tip forward with a flat back until you feel the hamstrings load, then drive the hips forward to stand tall and squeeze the glutes. The hips move back and forth; the back never rounds.

**HNG-08 · Romanian deadlift** — Ham, Glute · 15 reps · 60 · Diff 2 · Stand (DB/KB) · Load H · **Grip** · Counteracts: posterior chain weakness.

Stand holding a dumbbell in each hand in front of your thighs, or the kettlebell with both hands. With soft knees, push the hips back and slide the weight down the front of your legs with a flat back until you feel a strong hamstring stretch, around mid-shin. Drive the hips forward to stand and squeeze the glutes. Keep the weight close to the legs the whole way.

**HNG-09 · Sumo deadlift** — Ham, Glute, Adductor · 15 reps · 60 · Diff 1 · Stand (DB/KB) · Load H · **Grip** · Counteracts: posterior chain weakness, adductor weakness.

Stand wide with toes turned out and the kettlebell, or one dumbbell standing on its end, on the floor between your feet. Push the hips back and bend the knees until you can grip it with a flat back, then stand tall by driving the hips forward. Lower it under control and just tap the floor, or stop a few centimetres above it to stay quiet.

**HNG-10 · Kettlebell swing** — Glute, Ham, Full · 20 reps · 60 · Diff 3 · Stand (KB) · Load H · **Grip** · Counteracts: posterior chain weakness, low power.

Set the bell about 30 cm in front of you, hinge, and grip the handle with both hands, tilting it toward you. Hike it back high between the thighs, then snap the hips forward to float the bell to chest height; the arms are ropes and the hips do the work. Let it fall back into the hinge and repeat. To finish, hike it back once more and park it gently on the floor in front of you.

**HNG-11 · One-arm kettlebell swing** — Glute, Ham, L-spine/Core · 10/side · 60 · Diff 3 · Stand (KB) · Load H · **Grip** · Counteracts: posterior chain weakness, trunk rotation control.

Swing as in the two-hand swing, with one hand on the handle and the free arm loose at your side. Keep the shoulders square and don't let the bell pull you into a twist. At the halfway chime, park the bell gently, switch hands, and continue.

**HNG-12 · Single-leg RDL** — Ham, Glute · 8/side · 60 · Diff 2 · Stand · Counteracts: posterior chain weakness, balance loss.

Stand on one leg with a soft knee. Hinge at the hip, sending the free leg straight back and the torso forward together like a see-saw, with a flat back and the hips square. Reach toward the floor, then squeeze the standing-side glute to return. A fingertip on the desk is fine; switch legs at the chime.

**HNG-13 · Loaded single-leg RDL** — Ham, Glute · 8/side · 60 · Diff 3 · Stand (DB/KB) · Load M · Counteracts: posterior chain weakness, balance loss.

Hold a dumbbell or the kettlebell in the hand opposite the standing leg. Hinge as in the single-leg RDL, letting the weight hang straight below the shoulder until the torso is nearly parallel to the floor, then squeeze the glute to stand. Keep the hips square to the floor. Switch legs and hands at the chime.

**HNG-14 · Kickstand RDL** — Ham, Glute · 10/side · 60 · Diff 2 · Stand (DB/KB) · Load M · **Grip** · Counteracts: posterior chain weakness, side-to-side imbalance.

Stand with one foot slightly behind the other, rear heel up and only the ball of that foot touching for balance; most of your weight stays on the front leg. Holding a dumbbell in each hand or the kettlebell in both, hinge over the front leg with a flat back until you feel the hamstring stretch, then drive the hips forward to stand. Switch legs at the chime.

**HNG-15 · Prone back extension** — L-spine/Core, Glute · 15 reps · 60 · Diff 1 · Floor · Counteracts: weak back extensors from a supported seat.

Lie face down with your hands lightly at your temples and legs straight. Squeeze the glutes and lift the chest a few centimetres off the floor using the back muscles, hold 1 s, and lower slowly. Keep the chin tucked and the eyes looking at the floor.

**HNG-16 · Frog pump** — Glute · 20 reps · 60 · Diff 1 · Floor · Counteracts: glute inhibition.

Lie on your back, bring the soles of the feet together, and let the knees fall out wide with the heels close to your hips. Press the outer edges of the feet down and lift the hips in short, quick bridges, squeezing the glutes hard at the top of each. The range is small; the squeeze is everything.

**HNG-17 · Hamstring walkout** — Ham, Glute · 6 reps · 60 · Diff 2 · Floor · Counteracts: weak hamstrings, posterior chain weakness.

Lie on your back with knees bent and lift into a glute bridge. Keeping the hips up, walk the heels away from you in small steps until the legs are nearly straight, then walk them back and lower the hips. That's one rep. Let the hips drop a little as the feet go out if you need to.

**HNG-18 · Suitcase deadlift** — Ham, Glute, L-spine/Core · 8/side · 60 · Diff 2 · Stand (DB/KB) · Load M · **Grip** · Counteracts: posterior chain weakness, lateral core weakness.

Stand with one dumbbell or the kettlebell on the floor beside one foot. Hinge and bend the knees to grip it with a flat back, then stand tall without leaning toward the weight, and lower it slowly back to a quiet tap on the floor. Switch sides at the chime.

## 6. PSH — Push

**PSH-01 · Wall push-up** — Chest, Shoulder · 20 reps · 60 · Diff 1 · Stand/Wall · Counteracts: upper-body deconditioning.

Stand an arm's length from a wall with your hands on it at shoulder height, slightly wider than the shoulders. Keeping the body straight from head to heels, bend the elbows to bring the chest toward the wall, elbows angled about 45° from the body, then push back. Step the feet further back to make it harder.

**PSH-02 · Desk incline push-up** — Chest, Shoulder · 15 reps · 60 · Diff 1 · Stand/Desk · Counteracts: upper-body deconditioning.

Put your hands on the edge of a sturdy desk, slightly wider than the shoulders, and walk the feet back until the body is straight from head to heels. Lower the chest to the desk edge with the elbows about 45° from the body, then press back up. Squeeze the glutes so the hips don't sag.

**PSH-03 · Knee push-up** — Chest, Shoulder · 15 reps · 60 · Diff 1 · Floor · Counteracts: upper-body deconditioning.

Start on hands and knees, then walk the hands forward until the body is straight from head to knees, hands slightly wider than the shoulders. Lower the chest toward the floor with the elbows about 45° from the body, then press back up. Keep the hips in line with the shoulders rather than piked up.

**PSH-04 · Push-up** — Chest, Shoulder, L-spine/Core · 12 reps · 60 · Diff 2 · Floor · Counteracts: upper-body deconditioning.

Hands on the floor slightly wider than the shoulders, body straight from head to heels. Lower the chest until it's a fist's height from the floor, elbows about 45° from the body, then press back up, taking 2 s to lower. If the hips start to sag, finish the reps on your knees.

**PSH-05 · Tempo push-up** — Chest, Shoulder, L-spine/Core · 10 reps · 60 · Diff 3 · Floor · Counteracts: upper-body deconditioning.

Set up as for a push-up. Take 3 s to lower, pause 1 s with the chest just above the floor, then press up in 1 s. Drop to the knees for the remaining reps rather than letting the form slip.

**PSH-06 · Close-grip desk push-up** — Chest, Arm, Shoulder · 15 reps · 60 · Diff 2 · Stand/Desk · Counteracts: weak triceps and pushing strength.

Hands on the edge of a sturdy desk, shoulder width apart, body straight from head to heels. Lower the chest to the desk edge with the elbows brushing your ribs, pointing back rather than out, then press back up. Walk the feet further back to make it harder.

**PSH-07 · Decline push-up** — Chest, Shoulder · 10 reps · 60 · Diff 3 · Floor/Chair · Counteracts: upper-body and overhead weakness.

Brace a fixed chair (or a locked office chair) against a wall, put your feet on the seat, and walk the hands out into a push-up position on the floor, slightly wider than the shoulders. Lower the chest toward the floor with the elbows about 45° from the body, then press up. Keep the body straight; don't let the hips pike.

**PSH-08 · Pike push-up** — Shoulder, Arm · 10 reps · 60 · Diff 3 · Floor · Counteracts: overhead pressing weakness.

From a push-up position, walk the feet toward the hands until the hips are high and the body makes an upside-down V. Bend the elbows to lower the top of your head toward the floor just in front of the hands, then press back up. Shorten the range rather than letting the hips drop.

**PSH-09 · Chair dip** — Arm, Chest, Shoulder · 12 reps · 60 · Diff 2 · Chair · Counteracts: weak triceps and pushing strength.

Use a fixed chair that can't roll or swivel, or the edge of a sturdy desk. Sit on the edge with your hands beside your hips, fingers forward, then slide forward off the seat with the knees bent and feet flat. Bend the elbows straight back to lower until the upper arms are about parallel to the floor, or less, then press up. Keep the shoulders down away from the ears.

**PSH-10 · Push-up plus** — Shoulder · 15 reps · 60 · Diff 1 · Floor · Counteracts: weak serratus, rounded shoulders.

Start in a push-up position, or on your knees, arms straight. Without bending the elbows, let the chest sink between the shoulders so the shoulder blades pinch together, then push the floor away so they spread apart and the upper back rounds slightly. Move slowly; the arms stay locked the whole time.

**PSH-11 · Dumbbell floor press** — Chest, Arm · 15 reps · 60 · Diff 1 · Floor (DB) · Load M · Counteracts: upper-body deconditioning.

Lie on your back with knees bent and a dumbbell in each hand, upper arms resting on the floor at about 45° from the body, forearms vertical. Press both dumbbells straight up over the chest, then lower slowly until the upper arms touch the floor lightly. Pause there for a moment before pressing again.

**PSH-12 · Single-arm floor press** — Chest, Arm, L-spine/Core · 10/side · 60 · Diff 2 · Floor (DB/KB) · Load M · Counteracts: upper-body deconditioning, trunk rotation control.

Lie on your back with knees bent, holding one dumbbell, or the kettlebell with the bell resting on the back of your forearm, upper arm on the floor. Press straight up over the shoulder without letting the body roll toward the weight, then lower until the upper arm touches the floor. Switch arms at the chime.

**PSH-13 · Squeeze press** — Chest, Arm · 15 reps · 60 · Diff 1 · Floor (DB) · Load L · Counteracts: upper-body deconditioning.

Lie on your back with knees bent, holding the dumbbells together over your chest, palms facing each other. Squeeze them hard against each other and keep squeezing as you lower them to the chest and press back up. The inward squeeze is what loads the chest.

**PSH-14 · Standing dumbbell overhead press** — Shoulder, Arm · 12 reps · 60 · Diff 2 · Stand (DB) · Load L · Counteracts: overhead weakness, rounded upper back.

Stand with a dumbbell in each hand at shoulder height, palms facing forward or toward each other. Brace the belly and squeeze the glutes so the ribs stay down, then press straight up until the arms are beside the ears, and lower slowly. Don't lean back to finish the press.

**PSH-15 · Single-arm overhead press** — Shoulder, Arm, L-spine/Core · 8/side · 60 · Diff 2 · Stand (DB/KB) · Load M · Counteracts: overhead weakness, rounded upper back.

Hold one dumbbell at shoulder height, or the kettlebell in the rack position with the bell resting on the outside of the forearm, elbow tucked. Brace, then press straight up until the arm is locked out beside the ear, without leaning away from the weight. Lower slowly and switch arms at the chime.

**PSH-16 · Half-kneeling single-arm press** — Shoulder, Arm, L-spine/Core · 8/side · 60 · Diff 2 · Floor (DB) · Load L · Counteracts: overhead weakness, hip flexor shortening.

Kneel on one knee with the other foot flat in front, and hold one dumbbell at the shoulder on the kneeling side. Squeeze the glute of the down leg so the hip opens, then press straight up and lower slowly. Switch the knee and the arm at the chime.

**PSH-17 · Lateral raise** — Shoulder · 15 reps · 60 · Diff 1 · Stand (DB) · Load L · Counteracts: weak shoulder abductors.

Stand holding the light dumbbells at your sides, elbows slightly bent. Raise the arms out to the sides until they reach shoulder height, leading with the elbows and keeping the shoulders down, then lower over 2 s. If you have to swing or shrug, the weights are too heavy.

**PSH-18 · Overhead triceps extension** — Arm · 15 reps · 60 · Diff 1 · Stand (DB) · Load L · Counteracts: weak triceps.

Hold one dumbbell upright by its top end with both hands, overhead with the arms straight. Keeping the elbows pointing up and close to your head, bend them to lower the weight behind your head, then straighten the arms. Keep the ribs down so the back doesn't arch.

## 7. PUL — Pull & upper back

There's no pull-up bar, and nothing in a cubicle is safe to row against, so bodyweight pulling here is done face down on the floor or bent over standing. That's enough for the mid/lower traps and rear shoulders, which are what a desk weakens most.

**PUL-01 · Prone Y-T-W** — Shoulder, T-spine · 5 of each · 60 · Diff 2 · Floor · Counteracts: weak lower and middle traps.

Lie face down with your forehead resting on the floor and chin tucked. With thumbs up, lift straight arms off the floor in a Y (overhead, wide), lower, then in a T (straight out to the sides), lower, then in a W (elbows bent and pulled toward the hips). Squeeze the shoulder blades together and down on each lift.

**PUL-02 · Reverse snow angel** — Shoulder, T-spine · 10 reps · 60 · Diff 2 · Floor · Counteracts: weak posterior shoulder.

Lie face down with arms at your sides, palms down, forehead on the floor. Lift both arms a few centimetres and sweep them slowly out and up overhead like a snow angel, then back to the hips, without letting them touch the floor. Keep the shoulder blades pulled down.

**PUL-03 · Prone lat pull-down** — Shoulder, T-spine · 15 reps · 60 · Diff 1 · Floor · Counteracts: weak lats and lower traps.

Lie face down with arms reaching overhead, thumbs up, and lift them a few centimetres off the floor. Pull the elbows down toward your ribs as if pulling a bar to your chest, squeeze the shoulder blades together for 1 s, then reach back overhead. The arms stay off the floor for the whole set.

**PUL-04 · Prone cobra hold** — T-spine, Shoulder · 6 × 5 s · 60 · Diff 1 · Floor · Counteracts: rounded upper back, weak mid-back.

Lie face down with your arms by your sides, palms down. Lift the chest slightly, draw the shoulder blades back and down, and rotate the arms so the thumbs point to the ceiling as the hands lift off the floor. Hold for 5 s, rest for 3 s, and repeat. Keep the neck long and the eyes on the floor.

**PUL-05 · Supine elbow press** — T-spine, Shoulder · 10 × 3 s · 60 · Diff 1 · Floor · Counteracts: weak mid-back, rounded shoulders.

Lie on your back with knees bent and elbows bent to 90° beside the ribs, hands pointing up. Press the elbows down into the floor, pinching the shoulder blades together until the upper back lifts slightly, hold for 3 s, then relax. It's a small movement driven entirely by the muscles between the shoulder blades.

**PUL-06 · Reverse tabletop** — Shoulder, Glute, T-spine · 12 reps · 60 · Diff 2 · Floor · Counteracts: rounded shoulders, weak posterior chain.

Sit on the floor with knees bent, feet flat, and hands on the floor behind the hips, fingers pointing toward your feet. Press through the hands and heels to lift the hips until the body is flat like a table from shoulders to knees, pulling the shoulders back and down, then lower. Keep the chest open; don't let the shoulders creep up to the ears.

**PUL-07 · Prone T-raise** — Shoulder, T-spine · 12 reps · 60 · Diff 1 · Floor · Counteracts: weak middle traps, rounded shoulders.

Lie face down with arms straight out to the sides in a T, thumbs pointing up, forehead on the floor. Pinch the shoulder blades together to lift both arms as high as you can, hold for 2 s, then lower slowly. Lead with the shoulder blades, not the hands.

**PUL-08 · Bodyweight bent-over T and Y raise** — Shoulder, T-spine, Ham · 12 reps · 60 · Diff 1 · Stand · Counteracts: weak mid-back, rounded shoulders.

Hinge forward with soft knees and a flat back until the torso is nearly parallel to the floor, arms hanging. Raise the arms out to the sides in a T with thumbs up, squeezing the shoulder blades, then lower; on the next rep raise them forward and wide in a Y. Alternate T and Y, holding the hinge the whole set.

**PUL-09 · Bent-over dumbbell row** — Shoulder, T-spine · 15 reps · 60 · Diff 2 · Stand (DB) · Load M · **Grip** · Counteracts: weak upper back, rounded shoulders.

Hold a dumbbell in each hand and hinge forward with a flat back until the torso is about 45° to the floor, arms hanging. Pull both dumbbells toward the lower ribs, driving the elbows back past the body and squeezing the shoulder blades, then lower under control. Keep the neck long and the back flat.

**PUL-10 · Single-arm supported row** — Shoulder, T-spine · 10/side · 60 · Diff 1 · Stand/Desk (DB/KB) · Load M · **Grip** · Counteracts: weak upper back, rounded shoulders.

Put one hand on the desk and step back into a staggered stance, hinging until the back is flat. Holding one dumbbell or the kettlebell in the free hand, pull it toward your hip, elbow close to the body, then lower until the arm is straight. Don't twist the torso to lift it higher. Switch sides at the chime.

**PUL-11 · Gorilla row** — Shoulder, T-spine, Ham · 20 reps, alternating · 60 · Diff 2 · Stand (DB) · Load M · **Grip** · Counteracts: weak upper back, posterior chain weakness.

Stand wide with a dumbbell on the floor inside each foot. Hinge down with a flat back and grip both, then row one dumbbell to the hip while pushing the other lightly into the floor, lower it, and row the other. Stay in the hinge the whole minute and set the weights down quietly at the end.

**PUL-12 · Bent-over reverse fly** — Shoulder, T-spine · 15 reps · 60 · Diff 1 · Stand (DB) · Load L · Counteracts: rounded shoulders, weak rear shoulders.

Hinge forward with a flat back until the torso is near parallel to the floor, light dumbbells hanging below the shoulders. With slightly bent elbows, raise the arms out to the sides until they form a T, squeezing the shoulder blades together, then lower slowly. Use the lightest weights you have.

**PUL-13 · Bent-over Y raise** — Shoulder, T-spine · 12 reps · 60 · Diff 2 · Stand (DB) · Load L · Counteracts: weak lower traps.

Hinge forward with a flat back until the torso is near parallel to the floor, light dumbbells hanging, thumbs pointing forward. Raise straight arms forward and out in a Y until they're in line with your ears, then lower slowly. If the weights pull the shoulders up toward the ears, they're too heavy.

**PUL-14 · Dumbbell pullover** — Shoulder, Chest, L-spine/Core · 15 reps · 60 · Diff 2 · Floor (DB) · Load L · Counteracts: weak lats, stiff overhead range.

Lie on your back with knees bent, holding one dumbbell by its end over your chest with both hands and slightly bent arms. Keeping the ribs and low back pressed down, lower the weight in an arc behind your head until it nearly touches the floor, then pull it back over the chest. Stop the arc where the ribs start to flare.

**PUL-15 · Side-lying external rotation** — Shoulder · 10/side · 60 · Diff 1 · Floor (DB) · Load L · Counteracts: weak rotator cuff, rounded shoulders.

Lie on your side and hold a very light dumbbell in the top hand, elbow bent to 90° and pinned to your side, forearm across the belly. Rotate the forearm up toward the ceiling, keeping the elbow glued to the ribs, then lower over 2 s. Switch sides at the chime.

**PUL-16 · Renegade row** — Shoulder, L-spine/Core · 16 reps, alternating · 60 · Diff 3 · Floor (DB) · Load L · **Grip** · Counteracts: weak upper back, trunk rotation control.

Start in a push-up position with your hands on two dumbbells, feet wide; flat-sided (hex) dumbbells won't roll, but with round ones put the hands on the floor and row one dumbbell from beside the hand instead. Row one dumbbell toward the hip without letting the hips twist, set it down quietly, and row the other. Drop to the knees if the hips rock side to side.

**PUL-17 · Two-hand kettlebell row** — Shoulder, T-spine · 15 reps · 60 · Diff 2 · Stand (KB) · Load H · **Grip** · Counteracts: weak upper back, rounded shoulders.

Grip the kettlebell handle with both hands and hinge forward with a flat back until the torso is about 45° to the floor, arms hanging. Pull the bell to your lower ribs, elbows driving back and close to the body, squeeze the shoulder blades, then lower under control.

**PUL-18 · Kickstand single-arm row** — Shoulder, T-spine, Ham · 10/side · 60 · Diff 2 · Stand (DB/KB) · Load M · **Grip** · Counteracts: weak upper back, posterior chain weakness.

Take a staggered stance with the rear heel up, hinge over the front leg with a flat back, and hold one dumbbell or the kettlebell in the hand on the rear-leg side. Row it to your hip without twisting, then lower slowly; there's no hand on the desk, so the hinge muscles work too. Switch sides and stance at the chime.

## 8. COR — Core

**COR-01 · Dead bug** — L-spine/Core · 16 reps, alternating · 60 · Diff 1 · Floor · Counteracts: trunk stabilizers switched off by sitting.

Lie on your back with arms pointing at the ceiling and knees bent at 90° over the hips. Press the low back into the floor, then slowly lower one arm overhead and the opposite leg toward the floor without letting the back arch, and return. Alternate sides, breathing out as you reach.

**COR-02 · Weighted dead bug** — L-spine/Core, Shoulder · 16 reps, alternating · 60 · Diff 2 · Floor (DB/KB) · Load L · Counteracts: trunk stabilizers switched off by sitting.

Set up as for the dead bug, holding one dumbbell or the kettlebell over your chest with both arms straight. Keep the weight still and the low back pressed down while you slowly lower one leg toward the floor and back, then the other.

**COR-03 · Front plank** — L-spine/Core · 45–60 s · 60 · Diff 1 · Floor · Counteracts: weak anterior core.

Forearms on the floor under the shoulders, legs straight back, body in a straight line from head to heels. Squeeze the glutes, brace the belly as if about to be poked, and breathe normally. Drop to the knees for the last part rather than letting the hips sag.

**COR-04 · Side plank** — L-spine/Core, Glute · 25 s/side · 60 · Diff 2 · Floor · Counteracts: weak lateral core.

Lie on your side propped on one forearm, elbow under the shoulder, legs straight and stacked. Lift the hips until the body is straight from head to feet, and hold. Switch sides at the chime.

**COR-05 · Bird dog** — L-spine/Core, Glute · 12 reps, alternating, 2 s hold · 60 · Diff 1 · Floor · Counteracts: weak spinal stabilizers.

On hands and knees, wrists under shoulders and knees under hips, back flat. Reach one arm forward and the opposite leg back until both are level with the torso, hold for 2 s without the hips tipping, then return and switch. Move slowly, as if balancing a cup on your low back.

**COR-06 · Plank shoulder taps** — L-spine/Core, Shoulder · 20 reps, alternating · 60 · Diff 2 · Floor · Counteracts: weak anti-rotation core.

Start in a push-up position with feet wide. Lift one hand to tap the opposite shoulder, put it back, then switch, keeping the hips as still as possible. Go slowly; the wider the feet, the easier it is.

**COR-07 · Bear hold** — L-spine/Core, Quad, Shoulder · 4 × 10 s · 60 · Diff 2 · Floor · Counteracts: weak anterior core.

Start on hands and knees with toes tucked under. Brace the belly and lift the knees about 3 cm off the floor, back flat, and hold for 10 s while breathing. Lower the knees for a few seconds, then repeat.

**COR-08 · Hollow body hold** — L-spine/Core · 4 × 10 s · 60 · Diff 3 · Floor · Counteracts: weak anterior core.

Lie on your back, press the low back firmly into the floor, and lift the head, shoulders, and legs a few centimetres, arms reaching toward the feet. Hold for 10 s, keeping the low back down and breathing steadily, then rest briefly and repeat. Bend the knees to make it easier.

**COR-09 · Reverse crunch** — L-spine/Core · 15 reps · 60 · Diff 1 · Floor · Counteracts: weak lower abs.

Lie on your back with knees bent at 90° over the hips and arms on the floor beside you. Curl the hips off the floor, bringing the knees toward the chest, then lower the hips slowly without letting the feet drop. Use the belly, not momentum.

**COR-10 · Seated knee tuck** — L-spine/Core, Hip · 15 reps · 60 · Diff 1 · Chair · Counteracts: weak anterior core and hip flexors.

Sit near the front edge of a chair that can't roll or swivel, hands gripping the sides of the seat, and lean back slightly. Extend the legs out in front with the feet just off the floor, then pull the knees in toward the chest and extend again. Keep the chest lifted rather than collapsing forward.

**COR-11 · Halo** — Shoulder, L-spine/Core · 8 each direction · 60 · Diff 1 · Stand (DB/KB) · Load L · Counteracts: stiff shoulders, weak trunk control.

Hold the kettlebell upside down by the horns, or one dumbbell upright by both ends, at chest height. Circle it slowly around your head, close to the skull, keeping the ribs down and the hips still. Do half the circles one way and half the other.

**COR-12 · Suitcase march** — L-spine/Core, Hip · 25 s/side · 60 · Diff 2 · Stand (DB/KB) · Load H · **Grip** · Counteracts: weak lateral core.

Hold one dumbbell or the kettlebell at your side like a suitcase. March slowly in place, lifting each knee to hip height, standing perfectly tall without leaning toward or away from the weight. Switch hands at the chime.

**COR-13 · Half-kneeling chop** — L-spine/Core, Shoulder · 10/side · 60 · Diff 2 · Floor (DB) · Load L · Counteracts: weak rotational core.

Kneel on one knee and hold one dumbbell by both ends beside the shoulder opposite the down knee. Move it diagonally across and down toward the outside of the down-knee hip, rotating through the upper back, then return. Keep the hips facing forward. Switch the knee and the direction at the chime.

**COR-14 · Windmill** — L-spine/Core, Hip, Shoulder · 5/side · 60 · Diff 3 · Stand (DB/KB) · Load L · Counteracts: weak lateral core, stiff hips.

Press a light dumbbell or the kettlebell overhead and turn both feet about 45° away from that arm. Watching the weight, push the hips toward the weighted side and slide the free hand down the inside of the front leg toward the floor, keeping the top arm vertical. Stand back up by driving the hips. Switch sides at the chime.

**COR-15 · Bodyweight windmill** — L-spine/Core, Hip, Shoulder · 6/side · 60 · Diff 2 · Stand · Counteracts: weak lateral core, stiff hips.

Raise one arm straight overhead and turn both feet about 45° away from it. Watching the raised hand, push the hips toward that side and slide the other hand down the inside of the front leg as far as you can, keeping the top arm vertical, then stand back up. Switch sides at the chime.

**COR-16 · Half Turkish get-up** — Full, Shoulder, L-spine/Core · 3/side · 60 · Diff 3 · Floor (DB/KB) · Load L · Counteracts: weak trunk and shoulder stability.

Lie on your back with one arm pressing a light dumbbell or the kettlebell straight up, that knee bent and foot flat, the other arm and leg out at 45°. Watching the weight, roll up onto the opposite elbow, then the hand, then lift the hips into a bridge. Reverse each step slowly back to the floor. Switch sides at the chime.

**COR-17 · Plank pull-through** — L-spine/Core, Shoulder · 12 reps, alternating · 60 · Diff 3 · Floor (DB/KB) · Load L · Counteracts: weak anti-rotation core.

Start in a push-up position, feet wide, with a dumbbell or the kettlebell on the floor just outside one hand. Reach under your body with the opposite hand and pull it across to the other side, lifting it low rather than dragging it, without the hips twisting. Alternate hands.

**COR-18 · Short side plank** — L-spine/Core, Glute · 25 s/side · 60 · Diff 1 · Floor · Counteracts: weak lateral core.

Lie on your side propped on one forearm, knees bent at 90° behind you. Lift the hips until the body is straight from head to knees, and hold. Switch sides at the chime.

## 9. ACC — Accessory & joint resilience

**ACC-01 · Slow calf raise** — Calf/Ankle · 15 reps · 60 · Diff 1 · Stand · Counteracts: calf deconditioning, venous pooling.

Stand with feet hip width, a hand on the desk for balance. Rise as high as you can onto the balls of the feet, pause for 1 s at the top, then lower over 2 s. Keep the weight over the big and second toes rather than rolling out.

**ACC-02 · Single-leg calf raise** — Calf/Ankle · 8/side · 60 · Diff 2 · Stand · Counteracts: calf deconditioning, ankle weakness.

Stand on one foot with a fingertip on the desk or wall for balance. Rise as high as you can, pause at the top, and lower slowly through the full range. Switch feet at the chime.

**ACC-03 · Loaded calf raise** — Calf/Ankle · 15 reps · 60 · Diff 1 · Stand (DB/KB) · Load H · **Grip** · Counteracts: calf deconditioning.

Hold the kettlebell at your chest, or a dumbbell in each hand at your sides. Rise as high as you can onto the balls of the feet, pause for 1 s, and lower over 2 s. Stand near the desk in case you need a fingertip for balance.

**ACC-04 · Seated soleus raise** — Calf/Ankle · 15 reps · 60 · Diff 1 · Chair (DB/KB) · Load H · Counteracts: soleus deconditioning, venous pooling.

Sit on the chair with feet flat and knees at 90°, and rest the kettlebell or the dumbbells across the tops of your thighs near the knees. Lift the heels as high as you can, pause, and lower slowly. The bent knee shifts the work to the soleus, the deep calf muscle that pumps blood back up from the legs.

**ACC-05 · Tibialis raise** — Foot/Shin · 20 reps · 60 · Diff 1 · Stand/Wall · Counteracts: weak shins.

Lean your back against a wall with the feet about 30 cm in front of it. Keeping the legs straight, pull the toes up toward the shins as high as you can, then lower slowly without letting them slap the floor. Walk the feet further out to make it harder.

**ACC-06 · Side-lying hip abduction** — Glute · 12/side · 60 · Diff 1 · Floor · Counteracts: weak side glutes.

Lie on your side with the bottom knee bent and the top leg straight, in line with the body. Turn the toes of the top leg slightly down and lift the leg toward the ceiling, leading with the heel, then lower slowly. Keep the top hip stacked over the bottom one; don't roll back. Switch sides at the chime.

**ACC-07 · Side-lying adductor raise** — Adductor · 10/side · 60 · Diff 1 · Floor · Counteracts: weak adductors.

Lie on your side, propped on the forearm, and cross the top leg over so its foot is flat on the floor in front of the bottom knee. Keeping the bottom leg straight, lift it a few centimetres off the floor using the inner thigh, hold for 1 s, then lower. Switch sides at the chime.

**ACC-08 · Copenhagen plank (short lever)** — Adductor, L-spine/Core · 20 s/side · 60 · Diff 3 · Floor/Chair · Counteracts: weak adductors.

Lie on your side beside a fixed or braced chair, propped on the forearm. Rest the inside of the top knee and shin on the chair seat, with the bottom leg bent behind you. Press the top knee into the seat to lift the hips until the body is straight from head to knee, and hold. Switch sides at the chime.

**ACC-09 · Standing hip hike** — Glute · 12/side · 60 · Diff 1 · Stand · Counteracts: weak side glutes, hip drop when walking.

Stand on one leg, a fingertip on the desk if you need it, standing knee straight and the other foot just off the floor. Let the free-side hip drop a few centimetres, then lift it back up level and a little higher using the outer hip of the standing leg. Keep the torso upright. Switch sides at the chime.

**ACC-10 · Deep neck flexor head lift** — Neck · 6 × 5 s · 60 · Diff 2 · Floor · Counteracts: weak deep neck flexors, forward head.

Lie on your back with knees bent and no pillow. Tuck the chin gently as if nodding "yes", then lift the head about a centimetre off the floor, keeping the chin tucked. Hold for 5 s without letting the chin poke forward, then rest for a few seconds.

**ACC-11 · Wall-press knee hold** — Glute, Hip · 25 s/side · 60 · Diff 1 · Stand/Wall · Counteracts: weak side glutes.

Stand side-on to a wall, close enough that when you lift the knee nearest the wall to hip height, the outside of that knee touches it. Press that knee firmly into the wall while standing tall on the outside leg, and hold. You'll feel the work in the standing-side outer hip. Switch sides at the chime.

## 10. END — End-range strength & active flexibility (micro pool)

Every END movement is bodyweight only and tagged **Micro**. The floor and the chair are allowed. The common thread is moving actively into the end of a joint's range and working there, rather than resting passively in a stretch. A per-side movement fills a micro-routine on its own (block 60, 30 s a side). A two-sided movement is a 30 s half (block 30) and is paired with another.

**END-01 · Standing knee-lift hold** — Hip, L-spine/Core · 25 s/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: deep hip flexion range never used in a chair.

Stand tall with a fingertip on the desk. Lift one knee as high above hip height as you can without rounding the back or leaning back, and hold it there with the leg muscles alone; every few seconds, try to lift it a centimetre higher. Switch legs at the chime.

**END-02 · Seated knee lift-off** — Hip · 6/side · 60 · Diff 2 · Chair · **Micro** · Counteracts: weak hip flexors at full flexion.

Sit tall on the front of the chair with your hands holding the sides of the seat. Lift one knee as high toward the chest as you can without leaning back, hold for 2 s at the top, and lower slowly. Switch legs at the chime.

**END-03 · Seated straight-leg lift-off** — Hip, Quad, L-spine/Core · 6/side · 60 · Diff 3 · Floor · **Micro** · Counteracts: weak hip flexors in a compressed position.

Sit on the floor with legs straight and hands on the floor beside the knees, sitting as tall as you can. Keeping the knee locked, lift one heel a few centimetres off the floor, hold for 2 s, and lower slowly. If the heel won't lift, put the hands on the floor behind the hips and lean back slightly. Switch legs at the chime.

**END-04 · 90/90 back-leg lift-off** — Hip · 6/side · 60 · Diff 2 · Floor · **Micro** · Counteracts: lost hip internal rotation.

Sit in a 90/90: front leg bent 90° in front of you, back leg bent 90° out to the side, hands on the floor behind you. Lift the back foot and knee off the floor together, rotating from the hip, hold for 2 s, and lower. A small lift is normal. Switch the legs at the chime.

**END-05 · Half-kneeling hip flexor contract-relax** — Hip, Quad · 30 s/side · 60 · Diff 1 · Floor · **Micro** · Counteracts: hip flexor shortening.

Kneel on one knee, other foot flat in front, tuck the pelvis, and squeeze the rear glute to feel the stretch at the front of the rear hip. Hold for 10 s, then press the rear knee into the floor as if dragging it forward at about 30% effort for 10 s. Relax a little deeper, then for the last 10 s squeeze the rear glute harder and hold the new range with no help from the floor push. Switch sides at the chime.

**END-06 · Cossack squat with end-range pause** — Adductor, Hip · 4/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: stiff adductors, no side-to-side range.

Take a wide stance with toes slightly out. Shift to one side and bend that knee deeply while the other leg stays straight with its toes pointing up. Pause for 2 s at your lowest point, trying to sink a little further, then push back to centre. Do all reps on one side, then switch.

**END-07 · Deep squat hold with reach** — Hip, Calf/Ankle, T-spine · 30 s · 30 · Diff 2 · Stand · **Micro** · Counteracts: compressed hips, stiff ankles.

Sink into the deepest squat you can with heels down, feet slightly wider than the hips. Hold the bottom and, every few seconds, reach one arm up to the ceiling, rotating the chest to follow it, then switch arms. Hold the desk with one hand if the heels lift.

**END-08 · Standing hip CARs** — Hip · 2 each direction/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: lost hip rotation.

Stand with a hand on the desk. Lift one knee to hip height, open it out to the side as far as it goes, rotate it behind you so the foot points up, then sweep the knee back down beside the standing leg. Make the biggest, slowest circle you can without the pelvis moving, then reverse. Switch legs at the chime.

**END-09 · Side-lying hip internal rotation lift-off** — Hip · 6/side · 60 · Diff 2 · Floor · **Micro** · Counteracts: lost hip internal rotation.

Lie on your side with hips and knees bent at 90°, knees stacked. Keeping the knees touching, lift the top foot toward the ceiling as high as it will go, hold for 2 s, and lower slowly. The knee stays down; only the foot rises. Switch sides at the chime.

**END-10 · Adductor rock-back** — Adductor, Hip · 6/side · 60 · Diff 1 · Floor · **Micro** · Counteracts: stiff adductors.

Kneel on all fours, then extend one leg straight out to the side with the foot flat on the floor. Rock the hips back toward the heel of the bent leg until you feel the inner thigh of the straight leg; hold 2 s, pressing that foot into the floor, then rock forward. Keep the back flat. Switch sides at the chime.

**END-11 · Prone straight-leg hip extension** — Glute, Hip · 8/side · 60 · Diff 1 · Floor · **Micro** · Counteracts: glutes never working at full hip extension.

Lie face down with your forehead on your stacked hands. Squeeze one glute to lift that straight leg a few centimetres off the floor, hold for 2 s, and lower; the hip bones stay pressed down. Switch legs at the chime.

**END-12 · Standing hip airplane** — Hip, Glute · 4/side · 60 · Diff 3 · Stand · **Micro** · Counteracts: weak hip rotators, balance loss.

Stand on one leg, fingertips on the desk if you need them, and hinge forward until the torso is nearly parallel to the floor, free leg straight behind you. Slowly rotate the pelvis open toward the ceiling as far as you can, then roll it closed toward the floor, all on the standing hip. Switch legs at the chime.

**END-13 · Shin box get-up** — Hip, Glute · 4 reps · 30 · Diff 3 · Floor · **Micro** · Counteracts: lost hip rotation, weak glutes.

Sit in a 90/90 with hands free if you can. Squeeze the front-leg glute to rise up onto the knees into tall kneeling, then lower back to the 90/90 with control. Swap the legs to the other side, rise again, and keep alternating. Use a hand on the floor if needed.

**END-14 · Standing straight-leg front raise** — Ham, Hip · 6/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: hamstring tightness, weak hip flexors at length.

Stand tall with a hand on the desk. Keeping the knee straight and the torso upright, lift one leg in front of you as high as you can, hold for 2 s at the top, and lower slowly. Don't lean back to get the leg higher. Switch legs at the chime.

**END-15 · Supine active straight-leg raise** — Ham, Hip · 6/side · 60 · Diff 1 · Floor · **Micro** · Counteracts: hamstring tightness.

Lie on your back with both legs straight. Pull the toes of one foot toward you and raise that leg as high as you can with no help from the hands, keeping both knees straight; hold for 2 s at the top and lower slowly. The other leg stays pressed to the floor. Switch legs at the chime.

**END-16 · Elephant walk** — Ham, Calf/Ankle · 30 s · 30 · Diff 1 · Stand · **Micro** · Counteracts: hamstring and calf tightness.

Fold forward and put your hands on the floor, bending the knees as much as needed. Straighten one knee and press that heel down while the other knee bends, then switch, walking in place slowly. Pause for a moment each time a leg is straight.

**END-17 · Bodyweight Jefferson curl** — T-spine, L-spine/Core, Ham · 3 slow reps · 30 · Diff 2 · Stand · **Micro** · Counteracts: spine held still all day.

Stand with feet together, knees straight but not locked. Tuck the chin and slowly roll down one vertebra at a time, letting the arms hang, until you reach your lowest point; there, pull yourself a little deeper using the front of the trunk rather than just hanging, then roll up one vertebra at a time. Each rep takes about 10 s.

**END-18 · Quadruped thoracic rotation with hold** — T-spine · 6/side · 60 · Diff 1 · Floor · **Micro** · Counteracts: thoracic rotation loss.

On hands and knees, sit the hips back halfway toward the heels and put one hand behind your head. Rotate that elbow up toward the ceiling as far as it goes, eyes following, hold for 2 s while trying to turn a little further, then rotate down toward the opposite wrist. Switch sides at the chime.

**END-19 · Seated rotation lift-off** — T-spine · 5/side · 60 · Diff 1 · Chair · **Micro** · Counteracts: thoracic rotation loss.

Sit sideways on the chair with the backrest beside you, feet flat and knees together. Rotate toward the backrest as far as you can, using both hands on it to pull into the end of the turn, then let go and hold the position with your trunk muscles alone for 3 s while trying to turn further. Return to centre. At the chime, sit facing the other way and repeat.

**END-20 · Sphinx lift-off** — T-spine, L-spine/Core, Shoulder · 6 reps · 30 · Diff 2 · Floor · **Micro** · Counteracts: spinal extension range lost to slouching.

Lie face down propped on your forearms, elbows under the shoulders, chest up. Keeping the chest where it is, lift both forearms a centimetre off the floor and hold for 2 s using the back muscles, then set them down. Keep the neck long.

**END-21 · Standing side-bend lift-off** — L-spine/Core, T-spine · 5/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: side-bending range never used.

Stand with feet hip width and reach one arm overhead. Bend sideways away from the raised arm as far as you can without twisting, then use the waist muscles on the side you're bending toward to pull a little further and hold for 3 s, and return to upright by lifting from the other side. Switch sides at the chime.

**END-22 · Open book with lift-off** — T-spine, Chest · 5/side · 60 · Diff 1 · Floor · **Micro** · Counteracts: thoracic rotation loss, tight chest.

Lie on your side with knees bent to 90° and stacked, both arms straight out in front. Keeping the knees together, arc the top arm over to the other side, letting the chest follow. At the end of the turn, lift that hand a centimetre off the floor and hold for 2 s, then return. Switch sides at the chime.

**END-23 · Segmental cat-cow** — T-spine, L-spine/Core · 30 s · 30 · Diff 1 · Floor · **Micro** · Counteracts: spinal stiffness.

On hands and knees, start rounding from the tailbone and let it travel up the spine one segment at a time until the head tucks last. Then reverse, starting the arch from the tailbone. At each end, pause for 2 s and actively push a little further.

**END-24 · Shoulder CARs** — Shoulder · 2 each direction/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: stiff shoulders, lost overhead range.

Stand tall, make a loose fist, and brace the trunk so nothing moves but the arm. Raise the straight arm forward and up past the ear, rotate the thumb out as it goes behind you, and sweep it down and back to the hip in the biggest circle you can, then reverse. Go slowly enough to feel every part of the circle. Switch arms at the chime.

**END-25 · Wall-facing overhead lift-off** — Shoulder, T-spine · 8 reps · 30 · Diff 2 · Stand/Wall · **Micro** · Counteracts: lost overhead range, weak lower traps.

Stand facing a wall with toes about 30 cm from it, arms overhead in a Y, thumbs pointing back, palms on the wall. Without arching the low back, lift both hands a centimetre or two off the wall, hold for 2 s, and touch back. Step closer to the wall to make it harder.

**END-26 · Behind-the-back arm lift** — Shoulder, Chest · 8 reps · 30 · Diff 1 · Stand · **Micro** · Counteracts: tight chest, weak shoulder extension.

Stand tall with straight arms by your sides, palms facing behind you. Squeeze the shoulder blades together and lift both arms backward and up as high as you can without leaning forward, hold for 2 s, and lower. Keep the chin tucked.

**END-27 · Prone overhead lift-off** — Shoulder, T-spine · 8 reps · 30 · Diff 2 · Floor · **Micro** · Counteracts: lost overhead range.

Lie face down with arms overhead in a Y, thumbs up, forehead on the floor. Lift both arms a few centimetres off the floor, hold for 2 s, and lower. Keep the low back relaxed; the lift comes from between the shoulder blades.

**END-28 · Prone 90/90 external rotation lift-off** — Shoulder · 6/side · 60 · Diff 2 · Floor · **Micro** · Counteracts: weak rotator cuff at end range.

Lie face down with one upper arm out to the side at shoulder height and the elbow bent 90°, hand pointing toward your head, palm down. Keeping the elbow on the floor, lift the hand and forearm as high as you can by rotating the shoulder, hold for 2 s, and lower. Switch arms at the chime.

**END-29 · Wall slide with lift-off** — Shoulder, T-spine · 6 reps · 30 · Diff 2 · Stand/Wall · **Micro** · Counteracts: weak lower traps.

Face a wall with forearms flat on it, elbows at shoulder height. Slide the arms up until they're nearly straight, then lift the forearms a centimetre off the wall and hold for 2 s. Return to the wall and slide back down, keeping the ribs down.

**END-30 · Hand-behind-back lift-off** — Shoulder · 6/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: lost shoulder internal rotation.

Stand tall and place the back of one hand against your low back, palm facing out, elbow bent. Without arching the back or tipping the shoulder forward, lift the hand a few centimetres away from the body and hold for 2 s, then touch back. Slide the hand higher up the back as this gets easier. Switch arms at the chime.

**END-31 · Chin tuck hold** — Neck · 6 × 4 s · 30 · Diff 1 · Chair · **Micro** · Counteracts: forward head posture.

Sit or stand tall, eyes level. Glide the head straight back, making a double chin, as far as it goes without tilting the head down; hold for 4 s and release halfway. Imagine a string pulling the back of your head up and back.

**END-32 · Neck side-bend isometric** — Neck · 30 s/side · 60 · Diff 1 · Chair · **Micro** · Counteracts: tight upper traps, stiff neck.

Sit tall and tilt one ear toward the shoulder as far as is comfortable. Reach the hand on the side you're tilting toward over the top of your head to the opposite ear, and press the head back toward centre into the hand at about 20% effort for 5 s, then relax and let the hand ease the head a little further. Repeat once more, then take the hand away and hold the tilt on your own for the last few seconds. Switch sides at the chime.

**END-33 · Neck rotation end-range hold** — Neck · 4/side, 3 s hold · 60 · Diff 1 · Chair · **Micro** · Counteracts: lost neck rotation.

Sit tall with the shoulders still. Turn the head as far as you can to one side, leading with the eyes, hold for 3 s while gently trying to turn a little further, then return to centre. Switch sides at the chime.

**END-34 · Half-kneeling ankle rock** — Calf/Ankle · 8/side · 60 · Diff 1 · Floor · **Micro** · Counteracts: stiff ankles.

Kneel on one knee with the other foot flat in front. Keeping that heel down, drive the front knee forward over the toes as far as it will go, hold for 2 s, then rock back. Let the knee track over the second toe. Switch legs at the chime.

**END-35 · Top-range calf raise hold** — Calf/Ankle, Foot/Shin · 20 s/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: weak calves and feet at full tiptoe.

Stand on one foot with a fingertip on the desk. Rise onto the ball of the foot as high as you possibly can and hold the very top, pressing the big toe down. If the heel sinks, push back up to the top. Switch feet at the chime.

**END-36 · Seated ankle CARs** — Calf/Ankle · 3 each direction/side · 60 · Diff 1 · Chair · **Micro** · Counteracts: stiff ankles.

Sit tall and lift one foot just off the floor. Holding the shin still with your hand if needed, draw the biggest, slowest circle you can with the foot, reaching each edge of the range, then reverse. Switch feet at the chime.

**END-37 · Toe yoga and short foot** — Foot/Shin · 30 s · 30 · Diff 1 · Chair · **Micro** · Counteracts: weak feet from shoes and sitting.

Sit with both feet flat and bare or in thin socks if possible. Lift only the big toes while the other toes stay down, then press the big toes down and lift the other four; alternate for about 20 s. Finish by gently pulling the ball of the foot toward the heel to raise the arch, without curling the toes, and hold.

**END-38 · Reverse Nordic (short range)** — Quad, Hip · 6 reps · 30 · Diff 3 · Floor · **Micro** · Counteracts: quads never loaded at length.

Kneel tall with knees hip width and the tops of the feet flat, on carpet if you have it. Squeeze the glutes and lean the whole body back as one straight line from knees to head, only as far as you can control, then return to tall kneeling. Start with a very small lean.

**END-39 · Knee-over-toe split squat hold** — Quad, Hip, Calf/Ankle · 25 s/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: knees and ankles never loaded at full bend.

Take a short stride, a hand on the desk if you need it, and sink down so the front knee travels well past the toes while that heel stays flat, rear knee hovering near the floor. Hold the lowest position you can control and breathe. Switch legs at the chime.

**END-40 · Kneeling wrist rocks with lift-off** — Wrist/Forearm · 30 s · 30 · Diff 1 · Floor · **Micro** · Counteracts: wrists stuck in one keyboard position.

On hands and knees, palms flat and fingers forward, rock gently forward over the hands to the end of the wrist range, then back, for about 15 s. At the end of each forward rock, try to lift the fingertips off the floor for a moment. Then turn the hands over so the backs of the hands are on the floor, fingers pointing toward the knees, and rock gently back to work the opposite direction.

**END-41 · Spiderman lunge with reach** — Hip, T-spine · 3/side · 60 · Diff 2 · Floor · **Micro** · Counteracts: hip flexor shortening, thoracic rotation loss.

From a push-up position, step one foot outside the same-side hand and sink the hips low; hold for 3 s while pressing the hips down. Rotate and reach the inside arm to the ceiling, hold for 3 s, then return the hand and step back. Do all reps on one side, then switch.

## 11. Full strength routines: building rules

1. **Five movements, fixed slot order: SQT → PSH → HNG → PUL → COR or ACC.** Alternating lower and upper body lets each region rest while the next works, so moderate loads stay at RPE 7 without breaks between movements.
2. **Slot 5** draws from COR and ACC together, with COR weighted about 2:1.
3. **Equipment filter.** A movement is eligible when it is bodyweight, or when its equipment list includes something the user selected. If the user selected any equipment, at least two of slots 1–4 should be loaded, so owning weights actually changes the routine. With nothing selected, everything is bodyweight. Two more switches belong with the equipment choice: **solid wall available** (when off, skip movements with Wall in their setting), and the **kettlebell's weight** (when it's heavier than about 12 kg, skip the kettlebell version of Load L and M movements).
4. **Slot 1 is the warm-up.** It is Diff 1–2, never Load H, and never a swing. Swings (HNG-10, HNG-11) appear only in slot 3, after the body is warm.
5. **Floor limit.** At most two movements with Floor in their setting per routine, so the user isn't up and down five times.
6. **Grip budget.** At most two **Grip** movements per routine, never in slot 5, so the forearms are fresh for typing.
7. **No repeats in a day** (DECISIONS 32). If the user mixes modes in a day, treat the "same" overlaps in section 15 as the same movement.
8. **Difficulty ramp.** Default cap Diff 2, plus the user's manual cap. Both swings are Diff 3, so a new user meets them only after unlocking the hinge bucket; samples that use a Diff 3 movement say "Diff 3 unlocked". A Diff 3 movement unlocks per bucket after the user has completed Diff 2 movements in that bucket several times (tracked per movement, as in v4 rule 7).
9. **Region focus** steers by region exactly as in movement mode.
10. **Timer wins.** Reps are a target, not a contract. The UI shows the rep target, runs the 60 s timer (or 30 s per side), and moves on when it ends.

## 12. Micro strength routines: building rules

1. **Pool: the END bucket only.** Bodyweight only; floor and chair allowed.
2. **Shape: the movement-mode micro rule** (DECISIONS 30). One draw over the pool. If it's per-side, it fills the minute alone, 30 s a side. Otherwise a second two-sided END movement is drawn, and each runs 30 s with a 5 s lead-in before the second.
3. **Stay at one level.** If the first movement is on the floor, prefer a floor movement for the second, and likewise for standing and seated, so a 1-minute break doesn't include getting down and up again.
4. **No region twice in consecutive micro-routines**, and no movement twice in a day.
5. **Avoid the next full routine's regions** where possible, so a micro-routine doesn't pre-tire what the next strength routine is about to load.

## 13. Sample full strength routines (each 5 × 60 s)

**SR1 — Bodyweight basics** (no equipment, beginner) — 300 s
SQT-01 Bodyweight squat (60) → PSH-02 Desk incline push-up (60) → HNG-01 Glute bridge (60) → PUL-03 Prone lat pull-down (60) → COR-10 Seated knee tuck (60)

**SR2 — Bodyweight builder** (no equipment, harder) — 300 s
SQT-13 Curtsy lunge (60) → PSH-04 Push-up (60) → HNG-12 Single-leg RDL (60) → PUL-02 Reverse snow angel (60) → ACC-02 Single-leg calf raise (60)

**SR3 — Dumbbells** (pair of dumbbells) — 300 s
SQT-04 Goblet squat (60) → PSH-14 Standing dumbbell overhead press (60) → HNG-08 Romanian deadlift (60) → PUL-09 Bent-over dumbbell row (60) → COR-03 Front plank (60)

**SR4 — Kettlebell** (one kettlebell, Diff 3 unlocked) — 300 s
SQT-04 Goblet squat (60) → PSH-15 Single-arm overhead press (60) → HNG-10 Kettlebell swing (60) → PUL-10 Single-arm supported row (60) → COR-11 Halo (60)

**SR5 — Kettlebell and chair** (one kettlebell) — 300 s
SQT-12 Goblet lateral lunge (60) → PSH-09 Chair dip (60) → HNG-05 Loaded chair-edge hip thrust (60) → PUL-17 Two-hand kettlebell row (60) → COR-02 Weighted dead bug (60)

**SR6 — Full kit** (dumbbells and kettlebell) — 300 s
SQT-05 Dumbbell front squat (60) → PSH-11 Dumbbell floor press (60) → HNG-14 Kickstand RDL (60) → PUL-12 Bent-over reverse fly (60) → COR-11 Halo (60)

**SR7 — Standing only** (no equipment, no floor) — 300 s
SQT-03 Chair sit-to-stand (60) → PSH-02 Desk incline push-up (60) → HNG-07 Bodyweight good morning (60) → PUL-08 Bodyweight bent-over T and Y raise (60) → ACC-01 Slow calf raise (60)

**SR8 — Swing day** (dumbbells and kettlebell, Diff 3 unlocked) — 300 s
SQT-06 Suitcase squat (60) → PSH-12 Single-arm floor press (60) → HNG-11 One-arm kettlebell swing (60) → PUL-15 Side-lying external rotation (60) → COR-15 Bodyweight windmill (60)

## 14. Sample micro strength routines (≈ 60 s)

SM1 — Hip flexors: END-05 Half-kneeling hip flexor contract-relax (60)
SM2 — Overhead reach: END-25 Wall-facing overhead lift-off (30) → END-26 Behind-the-back arm lift (30)
SM3 — Hip rotation: END-09 Side-lying hip internal rotation lift-off (60)
SM4 — Spine on the floor: END-23 Segmental cat-cow (30) → END-20 Sphinx lift-off (30)
SM5 — Knees and ankles: END-39 Knee-over-toe split squat hold (60)
SM6 — At the desk: END-31 Chin tuck hold (30) → END-37 Toe yoga and short foot (30)
SM7 — Hamstrings: END-14 Standing straight-leg front raise (60)
SM8 — Neck: END-32 Neck side-bend isometric (60)
SM9 — Bottom of the squat: END-07 Deep squat hold with reach (30) → END-16 Elephant walk (30)

## 15. Overlap with movement library v4

Some movements here are the same as, or close to, a v4 movement. "Same" means the same exercise, so no-repeat rules should treat the two IDs as one when modes are mixed in a day. "Similar" means a related exercise with a different dose, load, or end-range emphasis; the two can safely share a day.

| Strength v1 | v4 | Kind |
|---|---|---|
| SQT-01 | CIR-16 | similar |
| SQT-02 | STR-04 | same |
| SQT-04 | STR-09 | same |
| SQT-07 | STR-05 | same |
| SQT-09 | STR-06 | same |
| SQT-16 | STR-11 | same |
| HNG-01 | STR-01 | same |
| HNG-02 | STR-02 | same |
| HNG-04 | STR-03 | same |
| HNG-07 | CIR-12 | similar |
| HNG-09 | STR-10 | similar |
| HNG-10 | CIR-18 | similar |
| HNG-12 | STR-08 | same |
| HNG-15 | STR-27 | same |
| PSH-02 | STR-20 | same |
| PSH-04 | STR-21 | same |
| PSH-10 | STR-22 | similar |
| PSH-15 | STR-32 | same |
| PUL-01 | STR-16 | same |
| PUL-02 | STR-28 | same |
| PUL-12 | STR-33 | same |
| COR-01 | STR-13 | same |
| COR-03 | STR-15 | same |
| COR-04 | STR-14 | same |
| COR-05 | STR-12 | same |
| COR-12 | STR-25 | similar |
| ACC-01 | CIR-04 | similar |
| ACC-02 | STR-26 | same |
| ACC-05 | STR-31 | same |
| ACC-08 | STR-29 | same |
| ACC-10 | STR-36 | same |
| END-06 | FLX-09 | similar |
| END-07 | FLX-08 | similar |
| END-08 | FLX-26 | same |
| END-12 | BAL-07 | similar |
| END-17 | FLX-37 | similar |
| END-22 | FLX-12 | similar |
| END-23 | FLX-11 | similar |
| END-24 | FLX-25 | same |
| END-29 | STR-37 | same |
| END-31 | FLX-21 | similar |
| END-34 | FLX-30 | similar |
| END-35 | BAL-13 | similar |
| END-41 | FLX-04 | similar |

## 16. Counts

SQT 16 · HNG 18 · PSH 18 · PUL 18 · COR 18 · ACC 11 · END 41 — **140 movements** in 7 buckets. Full-routine movements: 99. Micro-eligible (END): 41.
