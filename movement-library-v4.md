# movez — Movement Library v4.1

Library of movements the app can prescribe at each movement break. v2 expanded every description into brief in-app instructions (enough for someone unfamiliar with the movement to do it imperfectly). v3 added the interval presets and the 1-minute micro-break (section 11) and flagged the movements suitable for it with a **Micro** tag. v4 expands the balance bucket (13 → 29) with yoga-derived balance-and-strength postures, adds a balance-focused sample routine, and separates each header line from its instructions. v4.1 marks what each movement cannot be done without (floor, wall, stairs), so a user without one is never served it, and adds twelve core movements to the strength bucket (STR-39–STR-50).

## 1. Design rules

- A **full break** is ~5 minutes, built from 3–5 **blocks** of 60–90 s. A block is one movement (or one movement done per side).
- A **micro-break** is ~1 minute, taken roughly every 30 minutes of sitting on the longer presets (section 11). It is one 60 s block or two 30 s blocks, drawn only from movements tagged **Micro**.
- Setting: home office. Standing, chair, wall, and floor are all usable. Optional equipment: resistance band / mini-band, kettlebell or dumbbell, foam roller or lacrosse ball. Every movement has a bodyweight version or a listed equipment-free swap.
- Intensity: low-sweat. Strength work is RPE ~5–6, 1–2 sets, moderate reps, slow tempo. Avoid anything that fatigues the grip or forearms right before typing (carries and hangs are light and short).
- Goal of strength items is maintenance and gradual progression, not hypertrophy. Progression comes from tempo, range of motion, single-leg variants, and eventually light load.
- No per-movement cautions; safety lives in the app disclaimer.

## 2. What sitting does, and which buckets answer it

| Effect of prolonged sitting / screen work | Primary counter | Secondary |
|---|---|---|
| Hip flexors held short, anterior pelvic tilt, lumbar stiffness | FLX (hips), STR (glutes) | BAL |
| Glute inhibition ("gluteal amnesia"), weak posterior chain | STR (glutes/hamstrings) | CIR |
| Thoracic kyphosis, rounded shoulders, tight pecs | FLX (T-spine/chest), STR (upper back) | BRE |
| Forward head, tight upper traps / levator, weak deep neck flexors | FLX (neck), STR (chin tucks) | EYE |
| Venous pooling in calves, low metabolic rate, sluggishness | CIR | STR (calves) |
| Stiff ankles and weak feet/shins from no walking | FLX (ankles), STR (calves/tibialis) | BAL |
| Loss of balance and proprioceptive input from static posture | BAL | STR (single-leg) |
| Wrist/forearm load from keyboard and mouse, finger flexor dominance | HWF | CIR |
| Eye strain, reduced blink rate, fixed near focus | EYE | BRE |
| Shallow apical breathing, rib cage immobility | BRE | FLX (T-spine) |

## 3. Metadata schema

Each entry is formatted as:

**ID · Movement name** — Region · Dose · Block seconds · Diff · Setting (optional equipment) · [Requires …] · [**Micro**] · Counteracts: ….

Instructions (2–4 sentences: setup, the movement, the one cue that matters most), always separated from the header line by a blank line. The header ends with a period after the Counteracts text.

- **Region** — Neck, Shoulder, Chest, T-spine, L-spine/Core, Hip, Glute, Ham, Quad, Adductor, Calf/Ankle, Foot/Shin, Wrist/Forearm, Full, Eyes, Breath.
- **Dose** — time or reps. "/side" means do both sides; the block time already includes both.
- **Block** — approximate total block time in seconds.
- **Diff** — 1 easy, 2 moderate, 3 harder or needs more control.
- **Setting** — Stand, Chair, Wall, Desk, Floor, Any. Equipment in parentheses when optional: (Band), (KB) kettlebell or dumbbell, (Roller), (Ball).
- **Requires** — present when the movement cannot be done without a floor to lie or kneel on, a wall, or stairs. Absent when it needs none of them, including when a wall or step only helps with balance or another surface (a chair, the desk) will do.
- **Micro** — present when the movement is eligible for the 1-minute micro-break. Criteria: block ≤ 60 s, done standing or seated (no floor), no equipment required, no warm-up needed, no sweat, and the user can return to typing immediately.

Buckets: **FLX** flexibility & mobility, **CIR** blood flow & circulation, **STR** strength, **BAL** balance & proprioception, **HWF** hands / wrists / forearms, **EYE** eyes, **BRE** breathing.

---

## 4. FLX — Flexibility & mobility (active stretching)

**FLX-01 · Standing hip flexor stretch** — Hip · 30 s/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: hip flexor shortening.

Step one foot back about a metre, both feet pointing forward, rear heel up. Tuck your tailbone under (as if zipping tight jeans), squeeze the rear glute, and reach the same-side arm overhead. You should feel the front of the rear hip, not the low back. Keep the front knee over the ankle.

**FLX-02 · Half-kneeling hip flexor stretch** — Hip · 30 s/side · 60 · Diff 1 · Floor · Requires floor · Counteracts: hip flexor shortening.

Kneel on one knee with the other foot flat in front, both knees at 90°. Tuck the pelvis under and squeeze the glute on the kneeling side, then shift forward an inch or two without arching the back. Stay tall; the stretch is in the front of the kneeling-side hip.

**FLX-03 · Couch stretch** — Hip, Quad · 30 s/side · 60 · Diff 2 · Floor/Wall · Requires floor · Counteracts: hip flexor + rectus femoris tightness.

Kneel facing away from a wall or chair and put one shin up against it, knee on the floor, foot pointing up. Step the other foot forward flat. Squeeze the rear glute, tuck the pelvis, and slowly raise your torso toward upright. Stop where you feel a strong stretch in the front of the thigh and hip.

**FLX-04 · World's greatest stretch** — Full · 3 reps/side · 90 · Diff 2 · Floor · Requires floor · Counteracts: hips, T-spine, hamstrings at once.

From a push-up position, step the right foot outside the right hand. Drop the right elbow toward the instep, then rotate and reach the right arm to the ceiling, eyes following the hand. Bring the hand down, push the hips back and straighten the front leg to feel the hamstring, then return to the lunge. That's one rep.

**FLX-05 · Standing figure-4** — Glute · 30 s/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: glute/piriformis tightness.

Stand on one leg and cross the other ankle over the standing knee. Push the hips back and bend the standing knee as if sitting into a chair, keeping the chest up, until you feel the outer hip and glute of the crossed leg. Hold something for balance if needed.

**FLX-06 · Seated figure-4 lean** — Glute · 30 s/side · 60 · Diff 1 · Chair · **Micro** · Counteracts: glute/piriformis tightness.

Sit tall and place one ankle on the opposite knee, letting the raised knee drop out. Keeping the back straight, hinge forward from the hips until you feel the stretch in the raised-leg glute. Gently press the raised knee down for more.

**FLX-07 · 90/90 hip switches** — Hip · 8 switches · 60 · Diff 2 · Floor · Requires floor · Counteracts: lost hip rotation.

Sit on the floor with the front leg bent 90° in front of you and the back leg bent 90° out to the side, torso tall. Without using your hands, lift both knees and rotate them together to the other side so the leg positions swap. Move slowly; going all the way over is not required.

**FLX-08 · Deep squat hold with elbow pry** — Hip, Calf/Ankle, T-spine · 45–60 s · 60 · Diff 2 · Stand · Counteracts: compressed hips, stiff ankles.

Feet slightly wider than the hips and turned out a little, sink as low as you can with heels down. Bring the palms together at the chest and use the elbows to gently push the knees outward. Keep the chest lifted and breathe. If heels lift, put a book under them.

**FLX-09 · Cossack squat (slow)** — Adductor, Hip · 5 reps/side · 75 · Diff 2 · Stand · Counteracts: adductor and hip stiffness.

Take a wide stance, toes pointed slightly out. Shift your weight to one side and bend that knee deeply while the other leg stays straight, toes pointing up. Keep the bent-side heel down and the chest up, then push back to centre and go the other way. Depth comes with practice.

**FLX-10 · Active hamstring sweep** — Ham · 6 reps/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: hamstring tightness.

Place one heel on the floor a step in front of you, toes up, that leg straight. Hinge at the hips with a flat back and sweep both hands down past the toes and forward, as if scooping the floor, then stand tall. It's a rhythmic movement, not a long hold.

**FLX-11 · Cat-cow** — T-spine, L-spine/Core · 10 reps · 60 · Diff 1 · Floor · Requires floor · Counteracts: spinal stiffness.

On hands and knees, wrists under shoulders and knees under hips. Exhale and round the whole back toward the ceiling, tucking chin and tailbone. Inhale and let the belly drop, lifting the chest and tailbone. Move slowly so every part of the spine takes part.

**FLX-12 · Open book** — T-spine · 6 reps/side · 75 · Diff 1 · Floor · Requires floor · Counteracts: thoracic rotation loss.

Lie on your side with knees bent to 90° and stacked, both arms straight out in front, palms together. Keeping the knees glued together, lift the top arm and arc it over to the other side like opening a book, letting the eyes and chest follow. Pause, then return.

**FLX-13 · Thread the needle** — T-spine, Shoulder · 6 reps/side · 75 · Diff 1 · Floor · Requires floor · Counteracts: thoracic rotation loss.

On hands and knees, slide one arm palm-up under the body until the shoulder and ear come toward the floor. Then unthread and reach the same arm up to the ceiling, opening the chest. Keep the hips still over the knees the whole time.

**FLX-14 · Chair-back thoracic extension** — T-spine · 8 reps · 60 · Diff 1 · Chair · **Micro** · Counteracts: kyphosis.

Sit so the top edge of the chair back is at mid-back level, just below the shoulder blades. Interlace fingers behind the head, keep the ribs and belly relaxed, and lean back over the edge of the chair, looking up. Return to upright and repeat. If your chair is too tall, roll a towel and place it behind the mid-back.

**FLX-15 · Foam roller thoracic extension** — T-spine · 8 reps · 75 · Diff 1 · Floor (Roller) · Requires floor · Counteracts: kyphosis.

Lie back with the roller across your mid-back, knees bent, hands supporting the head. Keeping the hips on the floor, extend the upper back over the roller and return. Do a few reps, move the roller up a couple of inches, and repeat at two or three spots between the shoulder blades and the base of the neck.

**FLX-16 · Wall angels** — Shoulder, T-spine · 10 reps · 60 · Diff 2 · Wall · Requires wall · Counteracts: rounded shoulders, weak lower traps.

Stand with heels a few inches from the wall, back and head touching it. Put the backs of the hands and forearms against the wall with elbows at shoulder height. Slide the arms slowly up the wall and back down, keeping wrists, elbows, and low back in contact as much as you can. Reduce range rather than let the ribs flare.

**FLX-17 · Doorway pec stretch** — Chest · 20 s × 3 heights · 60 · Diff 1 · Wall · Requires wall · Counteracts: tight pecs.

Stand in a doorway with forearms on each side of the frame, elbows at shoulder height. Step one foot through and lean gently until the chest stretches. Then repeat with elbows below shoulder height, then above. Keep the ribs down and chin tucked; don't push the head forward.

**FLX-18 · Standing chest opener** — Chest, Shoulder · 3 × 15 s · 60 · Diff 1 · Stand · **Micro** · Counteracts: tight pecs, protracted shoulders.

Interlace the fingers behind your back, palms toward each other. Straighten the arms, pull the shoulder blades down and together, and lift the hands away from the body a few inches. Keep the chin tucked and ribs down; the chest opens, the back doesn't arch.

**FLX-19 · Desk lat stretch** — Shoulder, T-spine · 3 × 15 s · 60 · Diff 1 · Desk · **Micro** · Counteracts: overhead stiffness, lat tightness.

Place both hands on the desk edge, shoulder width, and step back until the arms are straight and the torso is parallel to the floor. Push the hips back and let the chest sink toward the floor between the arms. Keep the knees soft and the neck in line with the spine.

**FLX-20 · Standing side-bend reach** — L-spine/Core, Shoulder · 20 s/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: QL/lat tightness, rib immobility.

Reach one arm straight overhead and place the other hand on the hip. Lean sideways away from the raised arm, keeping both feet planted and hips square. Breathe into the ribs on the open side. Come back through centre before switching.

**FLX-21 · Chin tucks** — Neck · 10 × 3 s · 45 · Diff 1 · Chair/Stand · **Micro** · Counteracts: forward head.

Sit or stand tall and look straight ahead. Glide the chin straight backward, making a double chin, without tipping the head up or down. Hold for 3 s, feeling the muscles at the front of the neck and a stretch at the base of the skull, then relax.

**FLX-22 · Active neck range** — Neck · 5 each way · 60 · Diff 1 · Chair/Stand · **Micro** · Counteracts: upper trap / levator tightness.

Sit tall with shoulders relaxed. Slowly tilt one ear toward the shoulder and back, then the other side. Then turn the chin toward each armpit. Then rotate left and right. Move only as far as feels easy; no hands, no pushing.

**FLX-23 · Levator scapulae stretch** — Neck · 20 s/side · 45 · Diff 1 · Chair/Stand · **Micro** · Counteracts: levator tightness.

Turn your head 45° to the left, then nod the nose down toward the left armpit. Place the left hand on the back of the head and let its weight add gentle pressure. Put the right hand behind your back or hold the chair seat to keep the right shoulder down. Switch sides.

**FLX-24 · Neck CARs** — Neck · 3 each way · 60 · Diff 1 · Stand · **Micro** · Counteracts: cervical stiffness.

Start with a chin tuck. Slowly drop the chin to the chest, roll one ear toward the shoulder, tip the head back to look up, roll the other ear toward its shoulder, and return to the chin at chest. Take about 10 s per circle, keeping the shoulders still. Reverse direction.

**FLX-25 · Shoulder CARs** — Shoulder · 3 each way/side · 90 · Diff 2 · Stand · Counteracts: shoulder capsule stiffness.

Stand tall with one arm straight at your side, thumb forward. Slowly raise the arm forward and overhead, rotate the palm outward as it reaches the top, bring it down behind you in a big circle, and return. Take 10 s per circle and keep the torso still; the arm moves, the ribs and head don't. Reverse direction, then switch arms.

**FLX-26 · Hip CARs (standing)** — Hip · 3 each way/side · 90 · Diff 2 · Stand/Wall · Counteracts: hip capsule stiffness.

Hold a wall or desk with one hand. Lift the opposite knee to hip height in front, swing it out to the side, rotate the knee down and back so the heel points up behind you, then return. Keep the torso upright and still throughout. Reverse the circle, then switch legs.

**FLX-27 · Standing thoracic rotation** — T-spine · 8/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: thoracic rotation loss.

Stand with feet hip width, knees soft, hands crossed on the chest. Rotate the ribcage as far as you can to one side without moving the hips, pause, and return. Keep the head moving with the chest. Alternate sides.

**FLX-28 · Downward dog with pedals** — Ham, Calf/Ankle, Shoulder · 45 s · 60 · Diff 2 · Floor · Requires floor · Counteracts: posterior chain tightness.

From hands and knees, tuck the toes and lift the hips up and back so the body makes an inverted V, arms straight, heels reaching toward the floor. Alternately bend one knee while pressing the other heel down, pedalling slowly. Keep the spine long; a bent knee is fine.

**FLX-29 · Wall calf stretch** — Calf/Ankle · 20 s × 2/side · 80 · Diff 1 · Wall · Requires wall · Counteracts: gastroc/soleus stiffness.

Hands on a wall, step one foot back with the heel down and knee straight, and lean in until the upper calf stretches. Then bend the rear knee while keeping the heel down to stretch the lower calf. Both feet point straight at the wall.

**FLX-30 · Ankle rocks (knee over toe)** — Calf/Ankle · 10 reps/side · 60 · Diff 1 · Floor/Stand · Counteracts: dorsiflexion loss.

Half-kneel with one foot flat in front, or stand with one foot on a low step. Drive that knee forward over the toes as far as it goes while the heel stays glued down, then rock back. Aim the knee slightly outward, over the small toes.

**FLX-31 · Standing quad stretch (active)** — Quad, Hip · 30 s/side · 60 · Diff 1 · Stand/Wall · **Micro** · Counteracts: rectus femoris tightness.

Stand on one leg, holding a wall if needed, and grab the other ankle behind you. Tuck the pelvis under and squeeze that glute, keeping the knees close together. Don't pull the heel to the glute; the pelvic tuck is what makes the stretch.

**FLX-32 · Prone press-up** — L-spine/Core · 10 reps · 60 · Diff 1 · Floor · Requires floor · Counteracts: lumbar flexion posture.

Lie face down with hands under the shoulders. Press through the hands to lift the chest while the hips and legs stay relaxed on the floor, letting the low back arch. Go only as high as is comfortable, hold 2 s, and lower.

**FLX-33 · Child's pose with side reach** — L-spine/Core, Shoulder · 20 s centre + 20 s/side · 60 · Diff 1 · Floor · Requires floor · Counteracts: lumbar and lat stiffness.

Kneel and sit back toward the heels, arms stretched forward on the floor, forehead down. Breathe into the low back. Then walk both hands to one side, keeping the hips centred, to stretch the side of the torso. Repeat on the other side.

**FLX-34 · Squat-to-stand** — Hip, Ham, T-spine · 8 reps · 60 · Diff 2 · Stand · Counteracts: whole posterior chain and hips.

Stand with feet shoulder width, bend down and grab your toes, legs as straight as they'll go. Keeping the grip, pull the hips down into a deep squat and lift the chest. Then push the hips up and straighten the legs again, still holding the toes. Release and stand.

**FLX-35 · Elevated pigeon on desk** — Glute, Hip · 30 s/side · 60 · Diff 2 · Desk · Counteracts: glute/external rotator tightness.

Place one shin on the desk with the knee out to the side and the foot toward the opposite hand, standing on the other leg. Square the hips toward the desk and keep the back straight, then hinge forward slightly. Use a lower surface, like a bed or bench, if the desk is too high.

**FLX-36 · Standing pelvic tilts** — L-spine/Core, Hip · 12 reps · 45 · Diff 1 · Stand · **Micro** · Counteracts: lost lumbopelvic control.

Stand with knees soft, hands on the hips. Tip the pelvis forward to arch the low back, then tuck the tailbone under to flatten it. Move slowly between the two extremes; the ribs and shoulders stay still.

**FLX-37 · Segmental roll-down** — Full spine · 4 reps · 60 · Diff 1 · Stand · **Micro** · Counteracts: global spinal stiffness.

Stand tall, tuck the chin, and roll forward one vertebra at a time, letting the arms hang, until you're folded as far as comfortable with soft knees. Pause, then rebuild from the tailbone up, stacking each segment, the head arriving last. Take at least 10 s each way.

**FLX-38 · Foot roll** — Foot/Shin · 30 s/side · 60 · Diff 1 · Stand/Chair (Ball) · Counteracts: plantar stiffness.

Standing or sitting, place a lacrosse or tennis ball under the arch of one foot. Roll slowly from heel to toes, pausing a few breaths anywhere that feels tight. Use body weight to control pressure. No ball: roll on a water bottle.

## 5. CIR — Blood flow & circulation

**CIR-01 · Walk lap** — Full · 60–120 s · 90 · Diff 1 · Stand · **Micro** · Counteracts: low metabolic rate, venous pooling.

Get up and walk briskly around the room, down a hallway, or outside. Swing the arms, take full steps, and land heel to toe. If space is tight, walk a loop repeatedly.

**CIR-02 · March in place** — Full · 60 s · 60 · Diff 1 · Stand · **Micro** · Counteracts: venous pooling.

March on the spot lifting each knee to about hip height, swinging the opposite arm as the knee rises. Land softly on the ball of the foot and keep a steady, slightly quicker-than-walking rhythm.

**CIR-03 · Stair climb** — Full · 60–90 s · 90 · Diff 2 · Stand · Requires stairs · Counteracts: sluggish circulation.

Climb one or two flights of stairs at a steady pace, pushing through the whole foot and standing tall at the top of each step. Walk down at an easy pace. Repeat if time allows.

**CIR-04 · Calf pumps** — Calf/Ankle · 30 reps · 45 · Diff 1 · Stand/Desk · **Micro** · Counteracts: venous pooling in calves.

Stand with fingertips on the desk for balance. Rise onto the balls of both feet and drop back down at a quick, bouncy pace, about one per second. Range doesn't need to be full; rhythm matters more.

**CIR-05 · Ankle pumps and circles** — Calf/Ankle · 20 pumps + 10 circles each way · 60 · Diff 1 · Chair/Stand · **Micro** · Counteracts: venous pooling.

Seated or standing on one leg, point the toes away then pull them up toward the shin, 20 times. Then draw big slow circles with the foot in each direction. Do both feet.

**CIR-06 · Arm circles** — Shoulder · 30 s each way · 60 · Diff 1 · Stand · **Micro** · Counteracts: shoulder stiffness, upper-body circulation.

Arms straight out to the sides, make small circles forward and gradually enlarge them until they're as big as your shoulders allow. Reverse direction and repeat. Keep the ribs down and the neck relaxed.

**CIR-07 · Step-out jacks** — Full · 45 s · 45 · Diff 1 · Stand · **Micro** · Counteracts: heart rate too low.

Like a jumping jack without the jump: step one foot out to the side as both arms swing overhead, step it back in as arms come down, then the other foot. Keep a brisk, even rhythm.

**CIR-08 · Inchworm** — Full, Ham · 5 reps · 60 · Diff 2 · Floor · Requires floor · Counteracts: posterior chain stiffness, low HR.

From standing, fold forward and place hands on the floor, bending the knees as needed. Walk the hands forward until you're in a straight-arm plank. Then walk the feet toward the hands in small steps, keeping the legs as straight as you can, and stand up.

**CIR-09 · Shadow boxing** — Full, Shoulder · 45 s · 45 · Diff 1 · Stand · Counteracts: low HR, shoulder stiffness.

Stand in a staggered stance with fists up by the chin. Throw light, loose punches into the air — jab, cross, hook — rotating the torso and shifting weight with each punch, and shuffle the feet between combos. Speed and relaxation over power.

**CIR-10 · Leg swings** — Hip · 10 each direction/side · 75 · Diff 1 · Stand/Wall · Counteracts: hip stiffness, lower-body circulation.

Hold a wall with one hand and swing the outside leg forward and back like a pendulum, letting it swing progressively higher while the torso stays upright. Then face the wall with both hands on it and swing the leg side to side across the body. Switch legs.

**CIR-11 · Standing hip circles** — Hip, L-spine/Core · 10 each way · 45 · Diff 1 · Stand · **Micro** · Counteracts: lumbopelvic stiffness.

Feet hip width, hands on hips, knees soft. Make big slow circles with the hips as if using a hula hoop, pushing them as far forward, sideways, and back as you can while the head stays roughly over the feet. Reverse direction.

**CIR-12 · Brisk good mornings** — Ham, Glute · 15 reps · 45 · Diff 1 · Stand · **Micro** · Counteracts: glute inhibition, low HR.

Stand with feet hip width, hands behind the head, knees slightly bent. Push the hips straight back and hinge the torso forward with a flat back until you feel the hamstrings, then squeeze the glutes to stand up. Move at a brisk pace, about 2 s per rep.

**CIR-13 · Standing knee-to-elbow** — L-spine/Core, Hip · 20 reps · 45 · Diff 1 · Stand · **Micro** · Counteracts: trunk stiffness, low HR.

Stand tall with hands behind the head. Lift one knee while rotating the torso to bring the opposite elbow toward it, then return and switch sides. Keep a steady rhythm and stay tall between reps.

**CIR-14 · Heel walks and toe walks** — Foot/Shin, Calf/Ankle · 2 lengths each · 60 · Diff 1 · Stand · Counteracts: weak shins, foot circulation.

Walk across the room on your heels with the toes pulled up as high as possible, then walk back on the balls of the feet with the heels high. Take short steps and keep the torso tall. Repeat once.

**CIR-15 · Whole-body shake-out** — Full · 30 s · 30 · Diff 1 · Stand · **Micro** · Counteracts: static tension.

Stand loosely and shake the hands, then the arms from the shoulders, then bounce lightly on the balls of the feet and shake out each leg. Let the jaw and shoulders go slack. Nothing here needs to look tidy.

**CIR-16 · Air squats (brisk)** — Quad, Glute · 20 reps · 45 · Diff 1 · Stand · **Micro** · Counteracts: low HR, glute inhibition.

Feet shoulder width, sit the hips back and down to about a quarter or half squat, arms reaching forward for balance, then stand and squeeze the glutes. Keep the heels down and move at about one rep per 2 s.

**CIR-17 · Step-ups** — Glute, Quad · 45 s · 45 · Diff 1 · Stand · Requires stairs · Counteracts: low HR, glute inhibition.

Use the bottom stair or a sturdy step. Step fully onto it with one foot, bring the other up, then step down leading with the same foot. Alternate the leading leg every few reps. Keep the torso upright and the pace moderate.

**CIR-18 · Light kettlebell swings** — Glute, Ham · 15 reps · 45 · Diff 2 · Stand (KB) · Counteracts: glute inhibition, low HR.

Stand with feet slightly wider than hips, bell on the floor a foot in front. Hinge at the hips with a flat back, hike the bell back between the legs, then snap the hips forward to float it to chest height with straight arms. Let it swing back and repeat. The hips do the work; the arms just guide. Use a light bell.

**CIR-19 · Reverse lunge with overhead reach** — Hip, Full · 6/side · 60 · Diff 1 · Stand · Counteracts: hip flexor shortening, low HR.

Step one foot back into a lunge, lowering the rear knee toward the floor while the front knee stays over the ankle. At the bottom, reach both arms straight overhead and squeeze the rear glute. Drive through the front heel to return. Alternate sides.

**CIR-20 · Speed skaters (no jump)** — Glute, Adductor · 30 s · 30 · Diff 1 · Stand · **Micro** · Counteracts: lateral hip weakness, low HR.

Take a wide step to one side, bending that knee and letting the other leg trail behind as the opposite hand reaches toward the planted foot. Push off and step to the other side. Stay low and keep the movement smooth, no hop needed.

## 6. STR — Strength (bodyweight-first, low-sweat)

**STR-01 · Glute bridge** — Glute · 12 reps, 2 s hold · 60 · Diff 1 · Floor · Requires floor · Counteracts: glute inhibition.

Lie on your back, knees bent, feet flat and hip width, arms at the sides. Drive through the heels to lift the hips until the body is straight from shoulders to knees. Squeeze the glutes hard at the top for 2 s, then lower slowly. Don't arch the low back to get higher.

**STR-02 · Single-leg glute bridge** — Glute · 8/side · 75 · Diff 2 · Floor · Requires floor · Counteracts: glute inhibition, asymmetry.

Same setup as the glute bridge, but lift one foot off the floor with the knee bent. Push through the planted heel to lift the hips, keeping both hip bones level, hold, and lower. Swap sides after the set.

**STR-03 · Chair-edge hip thrust** — Glute · 12 reps · 60 · Diff 2 · Chair · Requires floor · Counteracts: glute inhibition.

Sit on the floor with your upper back against the front edge of a chair seat, knees bent, feet flat. Tuck the chin and drive through the heels to lift the hips until the thighs are level with the torso, then squeeze the glutes. Lower under control. Brace the chair against a wall so it can't slide.

**STR-04 · Tempo squat** — Quad, Glute · 10 reps · 60 · Diff 1 · Stand · Counteracts: lower-body deconditioning.

Feet shoulder width, toes slightly out. Take 3 s to sit the hips back and down as low as comfortable with heels down and chest up, pause 1 s at the bottom, then stand in 1 s and squeeze the glutes. Arms out in front for balance.

**STR-05 · Split squat** — Quad, Glute, Hip · 8/side · 75 · Diff 2 · Stand · Counteracts: hip flexor shortening, single-leg weakness.

Stand in a long stride stance, rear heel up. Lower straight down until the rear knee nearly touches the floor, keeping the torso upright and the front knee over the ankle. Push through the front heel to stand. Finish all reps on one side before switching.

**STR-06 · Reverse lunge** — Glute, Quad · 8/side · 75 · Diff 1 · Stand · Counteracts: glute inhibition.

From standing, step one foot back and lower until both knees are around 90°, torso tall. Push through the front heel to return to standing. Alternate legs or finish one side first. Hold a wall or desk if balance is an issue.

**STR-07 · Step-up (slow)** — Glute, Quad · 8/side · 75 · Diff 1 · Stand · Requires stairs · Counteracts: glute inhibition.

Stand facing a stair or sturdy step. Place one whole foot on it and, without pushing off the back foot, drive through the front heel to stand fully on the step. Lower the back foot to the floor slowly, taking about 3 s. Do all reps on one leg, then switch.

**STR-08 · Single-leg RDL** — Ham, Glute · 8/side · 75 · Diff 2 · Stand (KB) · Counteracts: posterior chain weakness, balance.

Stand on one leg with a soft knee. Hinge at the hip, sending the free leg straight back and the torso forward together, like a see-saw, with a flat back and the hips square. Reach toward the floor, then squeeze the glute to return. A light bell in the opposite hand is optional; a fingertip on the desk is fine for balance.

**STR-09 · Goblet squat** — Quad, Glute, Hip · 10 reps · 60 · Diff 2 · Stand (KB) · Counteracts: lower-body strength, hip mobility.

Hold a kettlebell or dumbbell against the chest with both hands, elbows pointing down. Feet shoulder width, toes slightly out, squat down as low as comfortable with elbows tracking inside the knees and chest tall. Stand and squeeze the glutes. No weight: hold a full water bottle or just clasp hands at the chest.

**STR-10 · Kettlebell deadlift** — Ham, Glute · 10 reps · 60 · Diff 2 · Stand (KB) · Counteracts: posterior chain weakness.

Stand with the bell between the feet. Push the hips back and bend the knees a little until you can grip the handle with a flat back and the chest up. Stand by driving the hips forward, then hinge back down under control, keeping the bell close to the legs.

**STR-11 · Wall sit** — Quad · 30–45 s · 45 · Diff 1 · Wall · Requires wall · **Micro** · Counteracts: quad deconditioning.

Lean your back against a wall and walk the feet forward, sliding down until the thighs are roughly parallel to the floor and the knees are over the ankles. Keep the whole back and head against the wall and breathe normally.

**STR-12 · Bird dog** — L-spine/Core, Glute · 6/side, 3 s hold · 75 · Diff 1 · Floor · Requires floor · Counteracts: weak spinal stabilizers.

On hands and knees, brace the belly as if about to be poked. Extend the right arm forward and the left leg back until both are level with the torso, without letting the hips or shoulders tilt. Hold 3 s, return, and switch. Keep the neck neutral, eyes on the floor.

**STR-13 · Dead bug** — L-spine/Core · 8/side · 75 · Diff 1 · Floor · Requires floor · Counteracts: weak anterior core, rib flare.

Lie on your back, arms pointing at the ceiling, hips and knees bent to 90°. Press the low back gently into the floor and keep it there. Slowly lower the right arm overhead and the left leg toward the floor together, exhale, then return and switch. Stop the range wherever the low back starts to lift.

**STR-14 · Side plank** — L-spine/Core · 20–30 s/side · 60 · Diff 2 · Floor · Requires floor · Counteracts: lateral core weakness.

Lie on one side propped on the forearm, elbow under the shoulder. Lift the hips so the body forms a straight line from head to feet (or head to knees, with knees bent, for an easier version). Squeeze the glutes and don't let the hips sag or roll. Switch sides.

**STR-15 · Front plank** — L-spine/Core · 30–45 s · 45 · Diff 1 · Floor · Requires floor · Counteracts: core deconditioning.

Forearms on the floor, elbows under shoulders, toes tucked. Lift the body into a straight line from head to heels. Squeeze the glutes and quads, push the floor away with the forearms, and keep the neck long with eyes on the floor. Breathe.

**STR-16 · Prone Y-T-W** — Shoulder, T-spine · 8 each · 75 · Diff 2 · Floor · Requires floor · Counteracts: weak lower/mid traps.

Lie face down, forehead resting on a folded towel. With thumbs up, lift straight arms off the floor in a Y shape (overhead, wide), lower, then in a T (straight out to the sides), lower, then in a W (elbows bent and pulled toward the hips). Squeeze the shoulder blades on each lift; the head stays down.

**STR-17 · Band pull-apart** — Shoulder · 15 reps · 45 · Diff 1 · Stand (Band) · Counteracts: rounded shoulders.

Hold a band in both hands at shoulder height, arms straight out in front, hands about shoulder width. Pull the hands apart until the band touches the chest, squeezing the shoulder blades together, then return slowly. Keep the shoulders down away from the ears.

**STR-18 · Band face pull** — Shoulder · 12 reps · 45 · Diff 1 · Stand (Band) · Counteracts: rounded shoulders, weak external rotators.

Anchor a band at about face height (a door handle or hook). Hold both ends with palms facing each other and pull toward the face, letting the elbows flare wide and high, finishing with the hands beside the ears. Squeeze the back of the shoulders, then return slowly.

**STR-19 · Band row** — Shoulder, T-spine · 12 reps · 60 · Diff 1 · Stand (Band) · Counteracts: weak upper back.

Anchor a band at waist height, or loop it around your feet while seated on the floor. Hold both ends with arms straight, then pull the elbows back past the ribs, squeezing the shoulder blades together, and pause. Return slowly. Stay tall; don't lean back to help.

**STR-20 · Desk incline push-up** — Chest, Shoulder · 12 reps · 45 · Diff 1 · Desk · **Micro** · Counteracts: upper-body deconditioning.

Hands on the desk edge slightly wider than shoulders, body in a straight line from head to heels, feet back. Bend the elbows to lower the chest to the desk, elbows angled about 45° from the body, then push back up. Squeeze the glutes so the hips don't sag.

**STR-21 · Push-up** — Chest, Shoulder, Core · 8–12 reps · 60 · Diff 2 · Floor · Requires floor · Counteracts: upper-body deconditioning.

Hands on the floor slightly wider than shoulders, body straight from head to heels. Lower the chest until it's a fist's height from the floor, elbows about 45° from the body, then press back up. Take 2 s to lower. Drop to the knees if the hips sag.

**STR-22 · Scapular push-up** — Shoulder · 12 reps · 45 · Diff 1 · Floor · Requires floor · Counteracts: weak serratus, winged scapula.

Hold a straight-arm plank. Without bending the elbows, let the chest sink between the shoulders so the shoulder blades pinch together, then push the floor away so the upper back rounds slightly and the blades spread apart. Small, slow movement.

**STR-23 · Lateral band walk** — Glute · 10 steps each way · 60 · Diff 1 · Stand (Band) · Counteracts: weak glute medius.

Loop a mini-band just above the knees. Sink into a quarter squat with feet hip width and toes forward. Step sideways, leading with the outside foot and keeping tension on the band, then follow with the other foot without letting the feet touch. Go one way, then back.

**STR-24 · Clamshell** — Glute · 15/side · 75 · Diff 1 · Floor (Band) · Requires floor · Counteracts: weak glute medius / hip external rotators.

Lie on one side with hips and knees bent about 45°, feet together, head on the lower arm. Keeping the feet touching and the pelvis still, lift the top knee as high as it goes, pause, and lower slowly. Add a mini-band above the knees to make it harder. Switch sides.

**STR-25 · Light suitcase carry** — L-spine/Core · 20 s/side · 60 · Diff 2 · Stand (KB) · Counteracts: lateral core weakness.

Hold a light kettlebell or dumbbell in one hand at your side like a suitcase. Walk slowly around the room, standing perfectly tall and not letting the torso lean toward or away from the weight. Switch hands. Keep the weight light enough that the grip never fatigues.

**STR-26 · Single-leg calf raise** — Calf/Ankle · 12/side · 60 · Diff 2 · Stand/Wall · Counteracts: calf weakness, venous pooling.

Stand on one foot with a fingertip on the wall for balance. Rise as high as you can onto the ball of the foot, pause, then lower over 3 s until the heel touches. Keep the ankle from rolling outward. Switch legs.

**STR-27 · Prone back extension** — L-spine/Core, Glute · 10 reps · 45 · Diff 1 · Floor · Requires floor · Counteracts: weak spinal extensors.

Lie face down with hands at the temples, elbows out, legs straight. Squeeze the glutes and lift the chest a few inches off the floor, keeping the neck in line with the spine and eyes down. Hold 2 s and lower slowly. Height is not the goal.

**STR-28 · Reverse snow angel** — Shoulder, T-spine · 10 reps · 60 · Diff 2 · Floor · Requires floor · Counteracts: weak posterior shoulder.

Lie face down with arms at your sides, palms down, forehead on a towel. Lift both arms an inch off the floor and sweep them slowly out and up overhead like a snow angel, then back to the hips, without letting them touch the floor. Keep the shoulder blades pulled down.

**STR-29 · Copenhagen plank (short lever)** — Adductor, Core · 15–20 s/side · 60 · Diff 3 · Floor/Chair · Requires floor · Counteracts: adductor weakness.

Lie on one side beside a chair, propped on the forearm. Bend the top leg and rest the inside of that knee and shin on the chair seat; the bottom leg is bent behind you, foot off the floor. Lift the hips so the body is straight from head to top knee, pressing the top knee into the chair. Hold, then switch.

**STR-30 · Banded good morning** — Ham, Glute · 12 reps · 45 · Diff 1 · Stand (Band) · Counteracts: posterior chain weakness.

Stand on the middle of a band and loop the top behind the neck across the upper traps. With soft knees, push the hips back and hinge forward with a flat back until you feel the hamstrings, then squeeze the glutes to stand against the band. Keep the chin tucked.

**STR-31 · Tibialis raise** — Foot/Shin · 15 reps · 45 · Diff 1 · Wall · Requires wall · **Micro** · Counteracts: weak shins, ankle stiffness.

Lean your back against a wall with feet about a foot in front of it, legs straight. Keeping the heels down, lift the toes and the front of both feet as high as possible, pause, and lower slowly. The further the feet are from the wall, the harder it gets.

**STR-32 · Light overhead press** — Shoulder · 8/side · 75 · Diff 2 · Stand (KB) · Counteracts: overhead weakness, kyphosis.

Hold a light bell or dumbbell at shoulder height, elbow in front of the body. Brace the belly and squeeze the glutes so the ribs stay down, then press straight up until the arm is locked out beside the ear. Lower slowly. Do all reps on one side, then switch.

**STR-33 · Bent-over reverse fly** — Shoulder, T-spine · 12 reps · 45 · Diff 1 · Stand (KB/Band) · Counteracts: rounded shoulders.

Hinge forward at the hips with a flat back until the torso is near parallel to the floor, light weights or band ends hanging below the shoulders. With slightly bent elbows, raise the arms out to the sides until they form a T, squeezing the shoulder blades together, then lower slowly. No weight: use full water bottles.

**STR-34 · Bottom squat hold** — Hip, Quad · 30–40 s · 45 · Diff 2 · Stand · **Micro** · Counteracts: hip compression, quad deconditioning.

Squat as deep as you can with heels down, feet slightly turned out, and hold there. Keep the chest lifted, push the knees outward, and keep the weight over the middle of the feet. Hands can clasp in front for balance.

**STR-35 · Standing glute squeezes** — Glute · 10 × 5 s · 60 · Diff 1 · Stand · **Micro** · Counteracts: glute inhibition.

Stand tall with feet hip width. Squeeze both glutes as hard as you can, as if pinching a coin between them, without tucking the pelvis much or leaning back. Hold 5 s, relax fully, and repeat.

**STR-36 · Deep neck flexor hold** — Neck · 5 × 10 s · 60 · Diff 2 · Floor · Requires floor · Counteracts: weak deep neck flexors, forward head.

Lie on your back with knees bent, no pillow. Tuck the chin gently as if nodding "yes", then lift the head about a centimetre off the floor, keeping the chin tucked. Hold 10 s without letting the chin poke forward, then rest.

**STR-37 · Wall slide with lift-off** — Shoulder, T-spine · 8 reps · 60 · Diff 2 · Wall · Requires wall · Counteracts: weak lower traps.

Face a wall with forearms and hands flat on it, elbows at shoulder height. Slide the arms up the wall until they're nearly straight, then press the forearms lightly into the wall and lift them a centimetre off it, holding 2 s. Return to the wall and slide back down. Keep the ribs down.

**STR-38 · Hip hinge with band abduction** — Glute, Ham · 12 reps · 45 · Diff 1 · Stand (Band) · Counteracts: glute inhibition, valgus tendency.

Loop a mini-band just above the knees, feet hip width. Push the hips back into a hinge with a flat back while driving the knees outward against the band, then squeeze the glutes to stand tall, keeping the knees pushed out throughout.

**STR-39 · Crunch** — L-spine/Core · 15 reps · 60 · Diff 1 · Floor · Requires floor · Counteracts: weak anterior core.

Lie on your back with knees bent, feet flat, and fingertips lightly behind the ears. Exhale and curl the head and shoulder blades off the floor by drawing the ribs toward the hips, pause, then lower slowly. Keep the low back on the floor and the elbows wide; never pull on the head.

**STR-40 · Sit-up** — L-spine/Core, Hip · 10 reps · 60 · Diff 2 · Floor · Requires floor · Counteracts: weak anterior core.

Lie on your back with knees bent and feet flat, hooked under a desk edge if they lift. Cross the arms on the chest and curl up one segment at a time, head, shoulders, then mid-back, until you're sitting tall, then roll back down the same way. Lower slowly; that's where the work is, and the arms never swing to help.

**STR-41 · Lying leg raise** — L-spine/Core, Hip · 10 reps · 60 · Diff 2 · Floor · Requires floor · Counteracts: weak lower abdominals.

Lie on your back, legs straight, hands flat beside the hips. Keeping the legs together and straight, lift them until they point at the ceiling, then lower them slowly until the heels hover just above the floor. Stop lowering wherever the low back starts to arch; bend the knees a little to make it easier.

**STR-42 · Scissor kicks** — L-spine/Core, Hip · 30–40 s · 60 · Diff 2 · Floor · Requires floor · Counteracts: weak lower abdominals.

Lie on your back with the hands under the hips, press the low back into the floor, and lift both straight legs a hand's width off it. Cross one leg over the other, then switch, in a steady scissoring rhythm, keeping the movement small. Raise the legs higher if the low back starts to lift.

**STR-43 · Bicycle crunch** — L-spine/Core · 20 reps · 60 · Diff 2 · Floor · Requires floor · Counteracts: weak obliques, trunk stiffness.

Lie on your back with fingertips behind the ears and both knees lifted to 90°. Curl the shoulders up, then turn the right elbow toward the left knee as the right leg straightens out, and switch sides in a slow pedalling rhythm. Rotate from the ribs, not the neck, and keep the low back pressed down.

**STR-44 · Reverse crunch** — L-spine/Core · 12 reps · 60 · Diff 2 · Floor · Requires floor · Counteracts: weak lower abdominals.

Lie on your back, arms by your sides, knees bent to 90° and lifted over the hips. Exhale and curl the hips off the floor, drawing the knees toward the chest, then lower the hips slowly until the tailbone just touches down. Lift with the lower abdominals rather than swinging the legs.

**STR-45 · Hollow body hold** — L-spine/Core · 20–30 s · 60 · Diff 2 · Floor · Requires floor · Counteracts: core deconditioning.

Lie on your back with arms reaching overhead and legs straight. Press the low back firmly into the floor, then lift the arms, shoulders and legs a few inches so the body forms a shallow curve, and hold while breathing. Bend the knees or bring the arms to the sides if the low back lifts; rest and repeat.

**STR-46 · Alternating heel taps** — L-spine/Core · 20 reps · 60 · Diff 1 · Floor · Requires floor · Counteracts: weak obliques.

Lie on your back with knees bent and feet flat, a little wider than the hips. Lift the head and shoulders slightly and reach the right hand toward the right heel by bending sideways at the waist, then the left hand to the left heel. Keep the shoulders off the floor throughout and the movement small and steady.

**STR-47 · V-up** — L-spine/Core, Hip · 8 reps · 60 · Diff 3 · Floor · Requires floor · Counteracts: core deconditioning.

Lie flat with arms overhead and legs straight. In one motion, lift the arms and legs together and reach the hands toward the shins, balancing briefly on the seat in a V, then lower both back down slowly. Tuck the knees if the legs can't stay straight, and control the way down rather than dropping.

**STR-48 · Standing oblique crunch** — L-spine/Core · 12/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: trunk stiffness, weak obliques.

Stand tall with feet hip width and the right hand behind the head. Lift the right knee out to the side as you bend sideways to bring the right elbow down to meet it, then return to standing. Do all reps on one side, then switch; squeeze the side of the waist rather than rounding forward.

**STR-49 · Desk plank** — L-spine/Core, Shoulder · 30–45 s · 60 · Diff 1 · Desk · Counteracts: core deconditioning.

Place the forearms on the edge of a sturdy desk, elbows under the shoulders, and walk the feet back until the body is a straight line from head to heels. Squeeze the glutes, draw the belly in gently, and hold while breathing steadily. Walk the feet further back to make it harder; don't let the hips sag or pike.

**STR-50 · Seated knee tucks** — L-spine/Core, Hip · 12 reps · 60 · Diff 1 · Chair · **Micro** · Counteracts: weak lower abdominals.

Sit near the front edge of a chair that won't roll and hold its sides, leaning back slightly with a long spine. Lift both feet and draw the knees toward the chest, then extend the legs out at a slight angle without touching the floor, and repeat. Keep the chest lifted and move slowly; touch the toes down between reps if needed.

## 7. BAL — Balance & proprioception

Balance declines with age faster than strength does and responds quickly to practice, so BAL items are meant to be served daily, not just when they fit the rotation. Progression for any single-leg item: fingertip on the wall → hands free → arms moving → head turning → eyes closed → soft surface. The app should hold a user at one rung until they complete it without a toe-touch, then advance. The yoga-derived postures (BAL-14 through BAL-20, BAL-28) double as strength work for the hips and trunk and count toward the STR slot in a break when needed.

**BAL-01 · Single-leg stand** — Full · 30 s/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: lost proprioception.

Stand on one foot with a soft knee, the other foot lifted just off the floor. Keep the hips level, stand tall, and fix your eyes on a point ahead. If you wobble, touch the toe down and resume. Switch legs.

**BAL-02 · Single-leg stand, eyes closed** — Full · 20 s/side · 45 · Diff 2 · Stand/Wall · Counteracts: dependence on vision for balance.

Stand on one leg near a wall, then close your eyes. Keep the standing knee soft and feel the foot making small corrections. Open the eyes or touch the wall if needed, then close them again. Switch legs.

**BAL-03 · Single-leg stand with head turns** — Full, Neck · 20 s/side · 45 · Diff 2 · Stand · Counteracts: neck stiffness plus balance.

Balance on one leg, then slowly turn the head left and right, then nod up and down, while staying balanced. Keep the movement slow and the standing knee soft. Switch legs.

**BAL-04 · Tandem stance** — Full · 20 s each · 45 · Diff 1 · Stand · **Micro** · Counteracts: narrow-base instability.

Stand with one foot directly in front of the other, heel touching toe, as if on a tightrope, arms at the sides. Hold, then swap which foot is in front. Look ahead, not down.

**BAL-05 · Heel-to-toe line walk** — Full · 10 steps each way · 60 · Diff 1 · Stand · Counteracts: gait control loss.

Walk forward in a straight line placing the heel of each step directly against the toes of the other foot. Then walk backward the same way, toe to heel. Keep the eyes forward and the arms loose.

**BAL-06 · Single-leg reach (Y-balance)** — Hip, Glute · 3 rounds/side · 90 · Diff 2 · Stand · Counteracts: hip control, ankle stability.

Stand on one leg with a slight knee bend. Reach the free foot as far as you can straight forward and tap the floor lightly, return to centre, then reach diagonally back to one side, return, then diagonally back to the other side. Keep the standing heel down and hips level. Switch legs.

**BAL-07 · Airplane / single-leg hinge hold** — Ham, Glute · 20 s/side · 60 · Diff 2 · Stand · Counteracts: posterior chain control.

Stand on one leg and hinge forward at the hip, extending the free leg behind you and the arms out to the sides, until the torso and leg are near parallel to the floor. Keep the hips square to the floor and the back flat. Hold, then rise and switch.

**BAL-08 · Towel or cushion single-leg stand** — Foot/Shin, Calf/Ankle · 20 s/side · 45 · Diff 2 · Stand · Counteracts: ankle stabilizer weakness.

Fold a towel a few times or use a firm cushion and stand on it on one foot. The soft surface makes the ankle work harder; keep the knee soft and the hips level. Switch feet.

**BAL-09 · Clock toe taps** — Hip, Glute · 2 rounds/side · 75 · Diff 2 · Stand · Counteracts: hip control.

Imagine standing at the centre of a clock face on one leg. With the free foot, tap lightly to 12 o'clock, then 3, 6, and 9 (going behind or across the body as needed), returning to centre between taps. Keep the standing knee soft and the torso upright. Switch legs.

**BAL-10 · Single-leg mini-squat** — Quad, Glute · 8/side · 75 · Diff 2 · Stand · Counteracts: knee and hip control.

Stand on one leg and bend that knee to lower a few inches, like a quarter squat, keeping the knee pointed over the middle toes and the hips level. Stand back up. Use a fingertip on the desk for balance if needed. Switch legs.

**BAL-11 · Marching hold** — Hip, Core · 5 × 5 s/side · 60 · Diff 1 · Stand · **Micro** · Counteracts: hip flexor strength, balance.

Stand tall and lift one knee to hip height, thigh parallel to the floor, foot relaxed. Hold 5 s without leaning back or letting the hips tilt, then lower slowly and switch. Hands on hips.

**BAL-12 · Step-back lunge with pause** — Glute, Quad · 5/side · 75 · Diff 2 · Stand · Counteracts: single-leg control.

Step one foot back into a lunge and lower until the rear knee hovers just above the floor. Hold that bottom position for 3 s, keeping the torso tall and still, then drive through the front heel to stand. Alternate sides.

**BAL-13 · Single-leg calf raise hold** — Calf/Ankle · 3 × 10 s/side · 60 · Diff 2 · Stand/Wall · Counteracts: ankle stability, venous pooling.

Stand on one foot with a fingertip on the wall. Rise as high as possible onto the ball of the foot and hold there for 10 s, keeping the ankle straight (not rolling outward). Lower, rest a moment, and repeat. Switch legs.

**BAL-14 · Tree pose** — Hip, Glute, Full · 30 s/side · 60 · Diff 2 · Stand/Wall · **Micro** · Counteracts: lost single-leg stability, hip rotator weakness.

Stand tall and place the sole of one foot on the inside of the opposite calf or inner thigh (not on the knee), knee pointing out to the side. Press the foot and the standing leg into each other, bring the palms together at the chest or reach them overhead, and fix your eyes on one point. Fingertips on a wall are fine at first. Switch sides.

**BAL-15 · Warrior III** — Ham, Glute, Core · 20 s/side · 60 · Diff 3 · Stand · Counteracts: posterior chain control, hip stability.

Stand on one leg and hinge forward at the hip while the other leg extends straight back, until the torso and the raised leg are close to parallel with the floor and the body forms a T. Arms can reach forward, out to the sides, or stay at the hips. Keep the hips level (toes of the raised foot pointing down), the standing knee soft, and the neck long. Switch sides.

**BAL-16 · Half moon (supported)** — Hip, Glute, Core · 20 s/side · 60 · Diff 3 · Desk/Wall · Counteracts: lateral hip weakness, rotational balance.

Stand sideways to the desk. Place the near hand on the desk and shift weight onto the near leg, then lift the far leg out to the side until it's roughly level with the hip, foot flexed. Open the chest and top arm toward the ceiling, stacking the shoulders and hips. Look forward or down to start; up when steady. Switch sides.

**BAL-17 · Eagle pose** — Hip, Shoulder, Full · 20 s/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: narrow-base instability, shoulder and hip stiffness.

Bend the knees slightly and cross one thigh over the other, hooking the foot behind the calf if it reaches (toes on the floor beside the standing foot is fine). Cross the arms in front of the chest with the opposite arm on top, wrap the forearms so the palms or backs of the hands touch, and lift the elbows to shoulder height. Sit a little lower into the standing leg and hold. Switch sides.

**BAL-18 · Crescent lunge hold** — Hip, Quad, Glute · 20 s/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: hip flexor shortening, single-leg control.

Step one foot back into a long lunge with the rear heel lifted and the rear leg straight, front knee over the ankle. Reach both arms overhead, tuck the tailbone slightly, and squeeze the rear glute. Hold, staying tall and steady on the ball of the rear foot. Switch sides.

**BAL-19 · Dancer prep** — Hip, Quad, Full · 20 s/side · 60 · Diff 3 · Stand/Wall · Counteracts: hip flexor tightness, single-leg control under a moving load.

Stand on one leg and hold the other ankle behind you with the same-side hand, knees close together. Reach the free arm forward and, keeping the chest lifted, press the held foot gently back into the hand so the torso tips forward a few inches. Hold, then return upright. A hand on the wall for the free arm is fine to start. Switch sides.

**BAL-20 · Hand-to-knee hold** — Hip, Core · 20 s/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: hip flexor strength through range, standing stability.

Stand on one leg and hold the other knee with the same-side hand, thigh at hip height. Once steady, open the knee out to the side, keeping the hips square and the standing leg straight. Hold, bring the knee back to centre, and lower. Switch sides.

**BAL-21 · Chair-to-single-leg stand** — Glute, Quad, Full · 5/side · 75 · Diff 2 · Chair · Counteracts: weak sit-to-stand, single-leg control.

Sit near the front of the chair, feet flat, arms crossed on the chest. Lean forward and stand up without using the hands, and as you reach the top, lift one foot off the floor and balance for 3 s. Place the foot down and sit back down slowly. Alternate which leg you finish on.

**BAL-22 · Heel-toe rock** — Calf/Ankle, Foot/Shin · 30 s + 30 s eyes closed · 60 · Diff 1 · Stand · **Micro** · Counteracts: reduced ankle strategy for balance.

Stand with feet hip width and rock slowly forward onto the balls of the feet, then back onto the heels with toes lifted, without bending at the hips. After 30 s, close the eyes and continue, keeping the rocking smooth. Stand near a wall the first few times.

**BAL-23 · Single-leg stand with arm reaches** — Full, Shoulder · 30 s/side · 60 · Diff 2 · Stand · **Micro** · Counteracts: balance while the upper body moves.

Balance on one leg, then slowly reach both arms overhead, then across the body to one side and the other, then behind you, keeping the standing knee soft and the hips level. The point is staying steady while the arms shift your weight. Switch sides.

**BAL-24 · Backward walking** — Full · 60 s · 60 · Diff 1 · Stand · **Micro** · Counteracts: gait control, reduced awareness of the body in space.

Walk slowly backward across the room, reaching each foot back and landing toe first, then rolling to the heel. Keep the torso tall and the eyes forward, not over the shoulder. Turn and repeat. Clear the path first.

**BAL-25 · Quick side-steps** — Glute, Full · 30 s · 30 · Diff 1 · Stand · **Micro** · Counteracts: slow stepping reactions.

Stand with knees soft. Take two or three quick small steps to the right, pause and settle, then two or three to the left. Speed up gradually so each stop requires a small catch. The goal is fast feet and a quiet upper body.

**BAL-26 · Tandem stance, eyes closed** — Full · 15 s each · 45 · Diff 2 · Stand/Wall · **Micro** · Counteracts: dependence on vision for balance.

Stand heel to toe as in the tandem stance, near a wall, and close the eyes. Feel the ankles and hips making small corrections. Open the eyes or touch the wall whenever needed, then continue. Swap the front foot.

**BAL-27 · Single-leg RDL to knee drive** — Ham, Glute, Hip · 6/side · 75 · Diff 3 · Stand · Counteracts: posterior chain control, dynamic balance.

Stand on one leg and hinge forward into a single-leg RDL, free leg extending behind. Then, without setting the foot down, rise and drive that knee up in front to hip height and pause. Lower back into the next hinge. Keep the standing knee soft and the hips square. Switch sides.

**BAL-28 · Chair pose to toe raise** — Quad, Calf/Ankle, Core · 3 × 10 s · 60 · Diff 2 · Stand · **Micro** · Counteracts: quad and calf control, ankle stability.

Feet together or hip width, sit the hips back and down into a half squat with the arms reaching overhead, weight in the heels. Hold, then rise onto the balls of both feet while staying in the squat, and hold there for 10 s. Lower the heels and stand. Repeat.

**BAL-29 · Slow 360° turns** — Full · 3 each way · 45 · Diff 1 · Stand · **Micro** · Counteracts: turning-related instability, vestibular under-use.

From standing, turn a full circle in place using small, deliberate steps, taking about 5 s per turn. Pause and let your balance settle before turning the other way. Once easy, keep the eyes fixed on one point for as long as possible during the turn, then snap them to the next point.

## 8. HWF — Hands, wrists & forearms

**HWF-01 · Wrist flexor stretch** — Wrist/Forearm · 20 s/side · 45 · Diff 1 · Stand/Chair · **Micro** · Counteracts: keyboard flexor tension.

Extend one arm straight in front, palm up. With the other hand, gently pull the fingers back and down toward the floor until you feel a stretch along the inside of the forearm. Keep the elbow straight. Switch arms.

**HWF-02 · Wrist extensor stretch** — Wrist/Forearm · 20 s/side · 45 · Diff 1 · Stand/Chair · **Micro** · Counteracts: mouse extensor tension.

Extend one arm straight in front, palm down, and let the hand hang. With the other hand, gently press the back of the hand toward the body until you feel the top of the forearm stretch. Keep the elbow straight. Switch arms.

**HWF-03 · Prayer and reverse prayer** — Wrist/Forearm · 20 s each · 45 · Diff 1 · Stand/Chair · **Micro** · Counteracts: wrist stiffness.

Press the palms together in front of the chest, fingers pointing up, and lower the hands toward the waist while keeping the palms together until the wrists stretch. Then turn the hands so the backs are pressed together, fingers pointing down, and raise them toward the chest.

**HWF-04 · Wrist circles and figure-8s** — Wrist/Forearm · 30 s · 30 · Diff 1 · Stand/Chair · **Micro** · Counteracts: wrist stiffness.

Interlace the fingers and make slow circles with the wrists in one direction, then the other. Then trace a sideways figure-8 in the air with the clasped hands, letting the wrists lead.

**HWF-05 · Finger spreads** — Wrist/Forearm · 15 reps · 30 · Diff 1 · Stand/Chair · **Micro** · Counteracts: finger flexor dominance.

Hold the hands in front of you and spread the fingers as wide apart as they'll go, straightening them fully, hold 2 s, then relax into a loose fist. A rubber band around the fingertips adds resistance to the spread.

**HWF-06 · Tendon glides** — Wrist/Forearm · 8 cycles · 45 · Diff 1 · Stand/Chair · **Micro** · Counteracts: tendon gliding restriction.

Start with the fingers straight. Bend only the top two joints into a hook, keeping the knuckles straight; then close into a full fist; then bend only at the knuckles so the fingers form a flat tabletop; then straighten again. Move slowly through each shape, both hands together.

**HWF-07 · Forearm pronation/supination** — Wrist/Forearm · 15 reps/side · 45 · Diff 1 · Stand/Chair · **Micro** · Counteracts: forearm rotation stiffness.

Tuck the elbow against your side, bent to 90°, hand in front like holding a tray. Turn the palm fully up, then fully down, rotating the forearm as far as it goes each way while the elbow stays pinned. Switch arms.

**HWF-08 · Thumb CARs and stretch** — Wrist/Forearm · 30 s/side · 60 · Diff 1 · Stand/Chair · **Micro** · Counteracts: trackpad/thumb overuse.

Make slow big circles with the thumb in both directions, keeping the rest of the hand still. Then tuck the thumb inside a loose fist and gently tilt the wrist toward the little-finger side until the base of the thumb stretches; hold 10 s. Switch hands.

**HWF-09 · Forearm roll on ball** — Wrist/Forearm · 30 s/side · 60 · Diff 1 · Desk (Ball) · Counteracts: forearm soft-tissue tension.

Rest one forearm on the desk, palm down, with a lacrosse or tennis ball under the fleshy upper part of the forearm. Press down with the other hand and roll slowly toward the wrist and back, pausing on tender spots. Flip the arm palm-up and repeat on the underside. Switch arms.

**HWF-10 · Median nerve glide** — Wrist/Forearm, Neck · 10/side · 60 · Diff 2 · Stand/Chair · **Micro** · Counteracts: nerve tension from fixed elbow and wrist posture.

Extend one arm out to the side at shoulder height, palm up, elbow straight. Bend the wrist so the fingers point down toward the floor while tilting the head away from that arm; then release the wrist and tilt the head toward the arm. Rock gently between the two positions; it should feel like a mild pull, never sharp. Switch arms.

**HWF-11 · Hand shake-out** — Wrist/Forearm · 20 s · 20 · Diff 1 · Stand/Chair · **Micro** · Counteracts: static grip tension.

Let the arms hang and shake the hands loosely and quickly from the wrists, as if flicking off water, letting the shaking travel up into the forearms. Keep the shoulders relaxed.

## 9. EYE — Eyes

**EYE-01 · Distance gaze (20-20-20)** — Eyes · 30 s · 30 · Diff 1 · Any · **Micro** · Counteracts: fixed near focus.

Look away from the screen at something at least 20 feet (6 m) away, ideally out a window, and let the eyes rest on it. Blink normally and let the face relax.

**EYE-02 · Near-far focus shifts** — Eyes · 15 shifts · 45 · Diff 1 · Any · **Micro** · Counteracts: ciliary muscle fatigue.

Hold a thumb up at arm's length and focus on it until it's sharp. Then shift focus to an object far across the room or out the window until that's sharp. Alternate slowly, giving each target 2–3 s to come into focus.

**EYE-03 · Eye tracking** — Eyes · 30 s · 30 · Diff 1 · Any · **Micro** · Counteracts: ocular muscle stiffness.

Keeping the head perfectly still, move the eyes slowly in a big circle, then reverse. Then trace a wide sideways figure-8, as far to the edges as you can see. Move slowly enough that it doesn't feel jerky.

**EYE-04 · Palming** — Eyes · 30–45 s · 45 · Diff 1 · Chair · **Micro** · Counteracts: eye strain, light overload.

Rub the palms together until warm, then cup them over the closed eyes without pressing on the eyeballs, fingers overlapping on the forehead, blocking out all light. Rest the elbows on the desk and breathe slowly.

**EYE-05 · Blink sets** — Eyes · 20 s · 20 · Diff 1 · Any · **Micro** · Counteracts: reduced blink rate, dry eye.

Close the eyes slowly and fully, hold for a second, and open — 10 times. Then blink quickly and lightly 10 times. The slow blinks spread tear film; the fast ones wake the lids up.

## 10. BRE — Breathing

**BRE-01 · Diaphragmatic breathing** — Breath · 6–8 breaths · 60 · Diff 1 · Chair/Stand · **Micro** · Counteracts: shallow apical breathing.

Place one hand on the belly and one on the chest. Breathe in slowly through the nose so the belly hand rises first and the chest hand barely moves; let the lower ribs widen too. Exhale slowly through the mouth, letting the belly fall. Keep the shoulders down.

**BRE-02 · Box breathing** — Breath · 4 rounds · 60 · Diff 1 · Chair/Stand · **Micro** · Counteracts: stress breathing pattern.

Inhale through the nose for a count of 4, hold for 4, exhale for 4, hold empty for 4. Keep the counts even and the breath quiet. Shorten to 3 counts if 4 feels strained.

**BRE-03 · Extended-exhale breathing** — Breath · 6 breaths · 60 · Diff 1 · Chair/Stand · **Micro** · Counteracts: sympathetic overdrive.

Inhale through the nose for 4 counts, then exhale through pursed lips (as if blowing through a straw) for 6 to 8 counts, longer than the inhale. Let the shoulders drop on each exhale. Don't force air out; just lengthen it.

**BRE-04 · Crocodile breathing** — Breath, L-spine/Core · 8 breaths · 75 · Diff 1 · Floor · Requires floor · Counteracts: rib cage immobility.

Lie face down, forehead resting on stacked hands, legs relaxed. Breathe in through the nose so the belly presses into the floor and the low back and sides expand, then exhale slowly. The floor gives feedback that the breath is going low rather than into the chest.

**BRE-05 · 90/90 breathing** — Breath, L-spine/Core · 8 breaths · 75 · Diff 1 · Floor/Chair · Requires floor · Counteracts: rib flare, anterior tilt.

Lie on your back with the calves resting on a chair seat, hips and knees at 90°. Flatten the low back gently toward the floor and keep it there. Inhale through the nose into the belly and sides, then exhale fully and slowly through the mouth until the ribs drop down, pausing briefly before the next breath.

**BRE-06 · Banded lateral rib breathing** — Breath, T-spine · 8 breaths · 60 · Diff 1 · Chair/Stand (Band) · Counteracts: lateral rib immobility.

Wrap a band snugly around the lower ribs and hold the ends in front. Inhale through the nose and try to push the ribs sideways and backward into the band, then exhale slowly. No band: use your own hands on the sides of the lower ribs.

---

## 11. Interval presets and micro-breaks

### Presets

The user sets how long they may sit before a full 5-minute break. Three presets are offered; each cycle (sitting + break) lands on a 30-minute boundary so the day's schedule stays predictable.

| Preset | Sit | Full break | Cycle | Micro-breaks per cycle | Label |
|---|---|---|---|---|---|
| 25/5 | 25 min | 5 min | 30 min | none | Evidence-optimal: matches the ~30-minute sitting-bout threshold in the research |
| 55/5 | 55 min | 5 min | 60 min | 1, at minute 30 | Default: full dose every hour, micro-break keeps bouts under 30 min |
| 85/5 | 85 min | 5 min | 90 min | 2, at minutes 30 and 60 | Deep work: long focus blocks, micro-breaks on by default |

A custom sit length is also allowed; the app places a micro-break every 30 minutes of sitting, dropping any that would fall within 10 minutes of the full break.

### Micro-break rules

1. **Optional but on by default** for 55/5 and 85/5. Not offered on 25/5, which needs none.
2. **Duration:** ~60 s. One 60 s block, or two 30 s blocks. The sitting timer keeps running; the micro-break does not reset it.
3. **Eligibility:** only movements tagged **Micro** (list below). No floor, no equipment, no warm-up, nothing that leaves the user flushed or with tired forearms.
4. **Priority:** the point of the micro-break is to interrupt the sitting bout, so it should be at least partly upright. Prefer a CIR item first (stand up, get blood moving), and use HWF, EYE, and BRE items as the second half-block or as the whole break when the user is mid-call and can't stand.
5. **Rotation across the day:** alternate the emphasis — circulation → eyes/hands → posture (neck, T-spine, hips) → circulation — so the same micro-break isn't served twice in a row. Don't repeat a movement across consecutive micro-breaks.
6. **Coordination with full breaks:** a micro-break should not use a movement that the next scheduled full break already contains.
7. **Post-lunch:** the first micro-break after lunch is CIR-heavy (walk lap, march, calf pumps), since post-meal glucose is where breaking up sitting shows the largest metabolic benefit.
8. **Snooze:** a micro-break can be deferred 5 minutes once; a second deferral skips it.

### Micro-eligible movements (67)

Circulation (12): CIR-01 Walk lap (60 s version) · CIR-02 March in place · CIR-04 Calf pumps · CIR-05 Ankle pumps and circles · CIR-06 Arm circles · CIR-07 Step-out jacks · CIR-11 Standing hip circles · CIR-12 Brisk good mornings · CIR-13 Standing knee-to-elbow · CIR-15 Whole-body shake-out · CIR-16 Air squats · CIR-20 Speed skaters

Flexibility (16): FLX-01 Standing hip flexor stretch · FLX-05 Standing figure-4 · FLX-06 Seated figure-4 lean · FLX-10 Active hamstring sweep · FLX-14 Chair-back thoracic extension · FLX-18 Standing chest opener · FLX-19 Desk lat stretch · FLX-20 Standing side-bend reach · FLX-21 Chin tucks · FLX-22 Active neck range · FLX-23 Levator scapulae stretch · FLX-24 Neck CARs · FLX-27 Standing thoracic rotation · FLX-31 Standing quad stretch · FLX-36 Standing pelvic tilts · FLX-37 Segmental roll-down

Strength (7): STR-11 Wall sit · STR-20 Desk incline push-up · STR-31 Tibialis raise · STR-34 Bottom squat hold · STR-35 Standing glute squeezes · STR-48 Standing oblique crunch · STR-50 Seated knee tucks

Balance (14): BAL-01 Single-leg stand · BAL-04 Tandem stance · BAL-11 Marching hold · BAL-14 Tree pose · BAL-17 Eagle pose · BAL-18 Crescent lunge hold · BAL-20 Hand-to-knee hold · BAL-22 Heel-toe rock · BAL-23 Single-leg stand with arm reaches · BAL-24 Backward walking · BAL-25 Quick side-steps · BAL-26 Tandem stance, eyes closed · BAL-28 Chair pose to toe raise · BAL-29 Slow 360° turns

Hands / wrists (10): HWF-01 Wrist flexor stretch · HWF-02 Wrist extensor stretch · HWF-03 Prayer and reverse prayer · HWF-04 Wrist circles and figure-8s · HWF-05 Finger spreads · HWF-06 Tendon glides · HWF-07 Forearm pronation/supination · HWF-08 Thumb CARs and stretch · HWF-10 Median nerve glide · HWF-11 Hand shake-out

Eyes (5): EYE-01 Distance gaze · EYE-02 Near-far focus shifts · EYE-03 Eye tracking · EYE-04 Palming · EYE-05 Blink sets

Breathing (3): BRE-01 Diaphragmatic breathing · BRE-02 Box breathing · BRE-03 Extended-exhale breathing

Not eligible, and why: anything on the floor (bridges, planks, cat-cow, open book, dead bug, crocodile breathing), anything needing equipment (bands, bells, roller, ball), blocks over 60 s (world's greatest stretch, CARs done per side, Y-balance, stairs, chair-to-single-leg stand, RDL to knee drive), the Diff 3 yoga balances (Warrior III, half moon, dancer prep), and items that raise heart rate enough to leave the user flushed (inchworm, shadow boxing, kettlebell swings, step-ups).

### Sample micro-breaks (≈ 60 s)

M1 — Stand and pump: CIR-04 Calf pumps (30) → EYE-01 Distance gaze (30)
M2 — Neck and eyes: FLX-21 Chin tucks (30) → EYE-02 Near-far focus (30)
M3 — Hips: FLX-01 Standing hip flexor stretch (60)
M4 — Hands: HWF-06 Tendon glides (30) → HWF-11 Hand shake-out (20) + HWF-05 Finger spreads (10)
M5 — Upper back: FLX-27 Standing thoracic rotation (30) → FLX-18 Standing chest opener (30)
M6 — On a call, seated: FLX-22 Active neck range (30) → BRE-03 Extended-exhale breathing (30)
M7 — Post-lunch: CIR-02 March in place (60)
M8 — Legs awake: CIR-16 Air squats (30) → STR-35 Standing glute squeezes (30)

## 12. Chaining rules for full breaks (for the app's routine builder)

1. **Break = 4 blocks by default** (range 3–5), target 270–330 s including ~5 s transitions.
2. **Block mix per break:** 1 FLX + 1 CIR + 1 STR + 1 from {BAL, HWF, EYE, BRE}. A 5th block, when used, is a second FLX or a BRE closer.
3. **Order within a break:** CIR first (warm up), then FLX, then STR or BAL, then HWF/EYE/BRE last so the user returns to the desk calm.
4. **Region rotation across the day:** cycle the FLX and STR regions through Hip → T-spine/Chest → Neck/Shoulder → Posterior chain → Core → Ankle/Foot before repeating. Don't hit the same STR region in consecutive breaks.
5. **Time-of-day weighting:** first break of the day skews CIR-heavy; last break of the day skews FLX + BRE; mid-afternoon (post-lunch) break skews CIR + BAL.
6. **Equipment filter:** if equipment is unavailable, substitute the bodyweight peer with the same Counteracts value (e.g. STR-17 → FLX-18 + STR-16; STR-09 → STR-04; CIR-18 → CIR-12).
7. **Difficulty ramp:** default to Diff 1–2. Introduce Diff 3 items only after the user has completed the Diff 2 item in the same region several times (tracked per movement).
8. **Variety:** avoid repeating any movement within the same day except CIR-01, EYE-01, and BRE-01, which can recur freely.

## 13. Sample full-break routines (each ≈ 5 minutes)

**R1 — Hip reset** (hip flexors, glutes) — 300 s
CIR-19 Reverse lunge reach (60) → FLX-01 Standing hip flexor stretch (60) → FLX-05 Standing figure-4 (60) → STR-01 Glute bridge (60) → BRE-05 90/90 breathing (75, trim to 60)

**R2 — Upper back & neck** (kyphosis, forward head) — 300 s
CIR-06 Arm circles (60) → FLX-14 Chair-back thoracic extension (60) → FLX-17 Doorway pec stretch (60) → STR-17 Band pull-apart (45) → FLX-21 Chin tucks (45) → EYE-01 Distance gaze (30)

**R3 — Full-body wake-up** (first break of the day) — 300 s
CIR-01 Walk lap (90) → FLX-04 World's greatest stretch (90) → CIR-16 Air squats (45) → STR-15 Front plank (45) → CIR-15 Shake-out (30)

**R4 — Posterior chain** (glute inhibition, hamstrings) — 300 s
CIR-12 Brisk good mornings (45) → FLX-10 Active hamstring sweep (60) → STR-08 Single-leg RDL (75) → STR-03 Chair-edge hip thrust (60) → FLX-33 Child's pose with side reach (60)

**R5 — Deep-focus day** (hands, eyes, breath; low arousal) — 285 s
CIR-02 March in place (60) → HWF-06 Tendon glides (45) → HWF-01 + HWF-02 Wrist flexor/extensor stretches (90) → EYE-02 Near-far focus (45) → BRE-03 Extended-exhale breathing (45)

**R6 — Balance & ankles** (post-lunch) — 300 s
CIR-14 Heel and toe walks (60) → FLX-30 Ankle rocks (60) → BAL-06 Y-balance reach (90) → STR-26 Single-leg calf raise (60) → EYE-03 Eye tracking (30)

**R7 — Spine & rotation** (thoracic stiffness) — 300 s
CIR-11 Standing hip circles (45) → FLX-11 Cat-cow (60) → FLX-12 Open book (75) → STR-12 Bird dog (75) → FLX-37 Segmental roll-down (45)

**R8 — Wind-down** (last break of the day) — 285 s
CIR-01 Walk lap (60) → FLX-03 Couch stretch (60) → FLX-19 Desk lat stretch (60) → FLX-22 Active neck range (60) → BRE-01 Diaphragmatic breathing (45)

**R9 — Balance builder** (single-leg stability, yoga postures) — 300 s
CIR-10 Leg swings (75) → FLX-26 Hip CARs, one direction only (45) → BAL-14 Tree pose (60) → BAL-15 Warrior III (60) → BAL-22 Heel-toe rock (60)

## 14. Counts

FLX 38 · CIR 20 · STR 50 · BAL 29 · HWF 11 · EYE 5 · BRE 6 — **159 movements** in 7 buckets. Equipment-tagged items: 18 (all with bodyweight substitutes per chaining rule 6). Micro-eligible items: 67. Requiring the floor: 38; a wall: 6; stairs: 3.
