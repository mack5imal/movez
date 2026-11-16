# Decisions

Where Movez departs from, or resolves an ambiguity in, the product brief, the scheduler research
and the design handoff. Each entry says what was decided and why, so a future change can be made
knowingly rather than by accident.

Sources of truth, in order: `product-brief-v1.md`, `scheduler-research-v1.md`,
`movement-library-v4.json`, `design_handoff_movez_ui/`.

## Build and shape

1. **Xcode project generated from `project.yml` via XcodeGen.** The generated `movez.xcodeproj`
   is committed so the repo opens in Xcode without the tool installed, but `project.yml` is the
   source of truth. Swift language mode 5 with strict concurrency at `targeted`; everything that
   touches state or UI is `@MainActor`.
2. **The library JSON is loaded from the repository root as a bundle resource.** There is no
   second copy to keep in sync, and no movement is hard-coded anywhere in the app.
3. **The app is an `LSUIElement` agent and is unsandboxed.** It reads the frontmost window's
   bounds, the running process list and the microphone's *is-running* property, none of which the
   sandbox permits. It makes no network calls and writes only to its own Application Support
   directory.

## The break

4. *Superseded by 76: there is no end screen and no streak.* **The end-of-break streak chip stays.** A streak is consecutive completed full breaks today;
   a skip resets it, a snooze does not, and a credited absence of five minutes or more counts as
   completed.
5. **The overlay has Next and no Back.** → and Return advance; Escape deliberately does nothing,
   because snoozing should be easier than skipping and neither should happen by reflex.
6. **The sequence strip has as many columns as the routine has blocks** (three to five), not a
   fixed four. Every routine now has five (28).
7. **Other displays show the dim and a small label**, not a second copy of the card.
8. **A deferred break is never shortened.** It waits, at full length. What it loses is patience:
   a break that has waited more than half an hour gets one snooze instead of two.
8a. **A routine is named for what it actually works.** The rotation slot biases selection but
   does not force it, so naming by slot put "Upper back opener · t-spine and chest" over leg
   swings and squats. The name comes from the slot whose regions the stretch and
   strength-or-balance blocks work for the most seconds, ties going to the planned slot. The
   rotation itself and the chaining rules are unchanged, and the last break of a working day
   keeps its time-of-day name. *Superseded by 33: routines have no names.*

## The micro-break

9. **The thirty-second count-in stays**, with Start now · Snooze 5 min · Skip, then a sixty-second
   countdown with Snooze 5 min · Skip. The countdown is now sixty or sixty-five seconds (30).
10. **One snooze total.** A second snooze request is a skip — the intent is the same and the
    pretence helps nobody.
11. **The handoff's "Shoulder rolls" is placeholder copy.** There is no such movement in the
    library; the fixtures use CIR-06 "Arm circles", which produces the same eyebrow the handoff
    draws, and the substitution is recorded in `SnapshotFixtures`.

## Settings

12. **Equipment chips follow the data, not the handoff.** Band · Kettlebell or dumbbell · Roller ·
    Ball, mapping to `band`, `kettlebell_or_dumbbell`, `foam_roller`, `ball`. The handoff drew
    Kettlebell and Dumbbell as separate chips; the library has one key for both.
13. **The custom preset is a stepper**, 15–120 minutes in fives. The micro-break toggle is hidden
    below 40 minutes, because a bout that short is already under the threshold a micro-break
    exists to break up.
14. **Working hours are one window a day** with a per-day switch, and cannot cross midnight. The
    summary collapses consecutive days that share a window.
15. **The settings sheets are drawn inside the window**, not as system sheets, so every pixel is
    in the app's palette and each one can be rendered offscreen for review.

## The menu bar

16. **"Start a session now" off hours means an ad-hoc session**: a fresh sitting interval, ending
    at "End session", midnight, or a four-hour gap. During one, "End session" replaces "Pause for".
17. **"Take a break now" stays available while paused**, in text-3 rather than removed; clicking
    it ends the pause and starts the break.
18. **The pause glyph rides in the menu-bar text, not in the icon.** The handoff's menu bar reads
    "◌ ‖ 42m"; drawing the glyph in both places stutters.
19. **The dropdown expands rows inline.** A window-style `MenuBarExtra` has no submenus.

## Scheduling

20. **Defer, never reset.** A break that comes due during a call, a screen share or a fullscreen
    app waits; the countdown keeps running underneath it.
20a. **Midnight rolls the counters, not the countdown.** A sitting bout that crosses the day
    boundary keeps its start time, its due time and its state; only the day-scoped counters, the
    routine seed and the streak key start over. Fifteen minutes from a break at 23:45 is fifteen
    minutes from a break at 00:01, and the alternative — handing back a fresh fifty-five minutes —
    is the one thing a break reminder must never do. This matters most to anyone working across
    midnight, for whom the old behaviour cost a break every night.
20b. **Time Movez was not running is moved past, not judged.** The state file records when it was
    written, so a relaunch knows whether it was gone for two minutes or two days. A gap shorter
    than the sitting interval shifts the whole bout forward by its length; a gap at least that
    long is standby (23c) and the interval starts again. It is never credited as a break: a
    running app can tell from the idle clock whether the user was at the keyboard, and an app that
    was not running cannot.
20c. **The streak and "Today" stay on the calendar day, and reset at midnight mid-session.**
    `HistoryStore` buckets every break by its own calendar day and the streak counts consecutive
    completed breaks within one of them, so someone working 22:00–04:00 sees `Today: 0 · streak 0`
    at 00:01 having just done three breaks. Considered and declined, not deferred: the scheduling
    underneath is correct — 20a keeps the countdown intact across the boundary — and this is the
    display disagreeing with it, not the app misbehaving. Aligning it would mean changing the
    on-disk history format, the streak calculation and every surface that reads them, which is a
    great deal of machinery for a number that is only ever glanced at.
19a. **The menu says when the user is away.** The dropdown had four modes and none of them was
    "nobody is here", so an absence kept counting the old interval down, reached zero and stayed
    there — a menu claiming a break was overdue to someone who had been gone an hour, and a "0m"
    in the menu bar to match. It now reads "Away 68 min · Your countdown is on hold", with an em
    dash beside an empty ring. Deliberately not "paused": a pause is something the user asks for
    and the menu can name an end for. The quiet minute after a wake (23b) reads the same way, with
    the number frozen at the length of the absence being judged, because that minute is exactly
    when someone is most likely to open the menu.
21. **Nothing is polled while paused or off hours.** The signal monitors stop outright rather than
    sampling into a void; a thirty-second wake-check notices when the pause runs out.
22. **A break counts as done at half the movements or half the time** (research §4.11).
23. *(Superseded by 43.)* **Idle is credited in two tiers**: three to five minutes hands the countdown back with the
    time it had left; five minutes up to a whole sitting interval is a full break. Both are
    reversible while the away toast is up, because Movez cannot tell a walk to the kitchen from a
    long read on paper. Longer than that is standby (23c), and is not credited at all.
23a. **The away toast stays fifteen seconds, chimes, and can be dismissed.** The research (§4.2)
    and the handoff say six seconds. In use the toast nearly always appears the moment a display
    wakes, and six seconds had gone before a hand reached the trackpad. Fifteen seconds is also
    how long "I was sitting" stays valid. A Dismiss link closes the toast and keeps the credit,
    and a single soft A5 note announces it, under the Sounds setting like the other chimes.
23b. **An absence ends only on evidence that the user is back.** The monitors report the input
    age every two seconds whether or not anyone is there, so only an input age lower than the last
    one seen counts as a return. And macOS sends several notifications for one wake, each
    measuring its gap from a poll that has already run, so an absence is measured from when it
    began, and a later, smaller report never shrinks it. Treating every poll as a return credited
    a break every two seconds of every absence — 78,000 records in four days — and letting a later
    notification overwrite the gap put a break prompt in front of someone who had been gone twenty
    hours.
23c. **An absence as long as the sitting interval is standby.** Not a break — a break is
    something the user takes at their desk, and being away from the desk for an hour is not it.
    Standby starts the countdown again from the moment they come back, silently: no toast, no
    chime, nothing written to history, and the day's counters left alone. Crediting these
    absences made the day's "done" figure meaningless: in eight days of real use the record held
    56 credited absences against 5 routines actually done. The threshold follows the preset, so
    it is 55 minutes on 55/5 and 25 on 25/5, and the same rule judges a gap when the app was not
    running (20b). What standby does not do is end the day: only midnight does that (20a), and a
    working day opening while Movez was away, which is what a gap crossing working hours means.
23d. **The menu shows snoozed and skipped, not done.** "Done" counted credited absences beside
    routines, which made it the one number in the menu that could climb on a day with no movement
    in it at all. It stays in the record, where the streak and the history read it. A break turned
    away at the heads-up is now written down too: `hideHeadsUp` is also sent by sleep, idle and a
    pause, so the coordinator could not tell a snooze from a dismissal and the day's snoozes and
    skips were the overlay's alone.
23e. **Movements are drawn at random, weighted, and a three-day memory weighs down what was
    served recently.** Selection used to draw a shortlist and then take whichever movement was
    closest to an ideal length, with ties going to the lowest id. In a library where nearly
    everything runs 45–60 s that meant "the longest one, every time": one circulation movement
    opened 53% of routines, 39 of 124 eligible movements ever appeared in a month, and the closer
    was one of three movements 80% of the time. Length is now only a constraint, held afterwards
    by the repair and trim steps that already enforce the 270–330 s window. A movement served
    yesterday is worth a third of its weight, and is back to full weight on the fourth day. Over a
    simulated month the same two-breaks-a-day pattern now reaches 100 movements, with no movement
    in more than 11% of routines. *The repair and trim steps are gone too: every block is a minute
    (29). The three-day memory stays.*
23f. **The region rotation carries on across days, and there is no wake-up routine.** The
    rotation index was the day's break count, so a user who takes two breaks a day saw the first
    two slots — hips, then upper back — and no others, for ever. It is now a cursor over the
    routines actually done, counted from the completions already in history. The wake-up shape
    went with it: it applied to the first break of every calendar day, which for anyone working
    odd hours is not the start of anything, and it spent half of its blocks on circulation. The
    wind-down shape stays, but only when the working day genuinely closes — always-on working
    hours report an end at midnight, which used to give anyone working late a wind-down routine
    every night. *Superseded by 28: the rotation and the wind-down are both gone.*
23g. **The post-lunch rule is gone, and micro-breaks draw from more buckets.** A return from
    twenty minutes away between 11:00 and 14:00 used to mark the next micro-break as post-lunch,
    however many hours later it came, and that micro-break was a single minute drawn from four
    movements. Every micro-break also contained a circulation movement, so twelve movements
    carried all of them, and the balance and strength movements marked micro-eligible were never
    served at all. Each emphasis now leads with its own buckets and follows with a wider set.
    *Superseded by 30: there is no emphasis, and no bucket is drawn first.*
23h. **The microphone means a call only after a minute, and a micro-break on screen is left
    alone.** `kAudioDevicePropertyDeviceIsRunningSomewhere` cannot say which process is listening,
    and a dictation tool holds the mic for a few seconds at a time. Every one of those bursts used
    to defer breaks for the burst plus the two-minute grace: twenty of them in an hour of real use,
    and one landed 28 seconds into a micro-break's count-in, took it off screen, and re-anchored the
    next one inside the quiet zone before the full break — where research §4.10 says to drop it. So
    the user lost the micro-break altogether and the next signal any surface gave them was the full
    break half an hour later. The mic is now held to sixty seconds of continuous use before it
    counts (`SustainedSignal`, in the aggregator, so the scheduler still sees a plain reading), and
    suppression no longer takes down a micro-break that is already up, exactly as it already left a
    running full break alone. A screen share and a fullscreen app still suppress on the first
    reading: they are steady states that mean what they say. Naming the process that holds the mic
    (macOS 14.2 can) would be more precise and is the next step if a minute proves too blunt.
23i. **A micro-break is written to history only if it ran for half its length.** The coordinator
    used to record its movements whenever the panel came down, and the panel comes down for a
    snooze, a skip, a closed lid and an idle stretch as well as for a minute of movement — so a
    micro-break nobody did was recorded as done, and under 23e those movements then weighed
    themselves down for three days. The scheduler, which is the only thing that knows what just
    happened, now says so with `recordMicroDone`, on the same half rule the full break uses
    (research §4.11). A count-in that never reached the movement records nothing at all.
23j. **The micro-break's count-in chimes.** It is the quietest of the five notes, and it is there
    because the panel takes no focus and opens on whichever display the pointer is on: in silence
    its thirty seconds ran out unnoticed, which reads to the user as a micro-break that fired
    without a count-in, or as one that never fired at all.
24. **Settings apply live.** The scheduler re-plans from the bout that is already running, so
    changing a preset never costs the user the time they have already sat. *Refined by 72: the
    countdown moves by the change, not from the bout start.*

## Known compromises

25. **Screen-capture detection is a heuristic.** macOS exposes no public API for "my screen is
    being recorded", so Movez watches for the tools people actually use, conservatively: a false
    positive quietly postpones a break, which is better than interrupting a live share. Tools that
    idle in the menu bar all day (Loom, CleanShot X, Kap) are listed but disabled.
26. **Focus is read through a Focus Filter, not the system.** There is no supported way to read
    the current Focus, so Movez ships a `SetFocusFilterIntent` the user adds to their own Focus.
27. **Launch at login needs a permanent home, not a signed build.** `SMAppService` records the
    bundle's path, so an app registered out of `build/DerivedData` stops launching the moment
    `make clean` removes it — install it to `/Applications` before turning the toggle on.
    Registration itself needs no Developer ID: measured on macOS 15.6, an ad-hoc signature with no
    team identifier registers, with and without the `get-task-allow` a Debug build carries, and
    the login item survives a rebuild that changes the code hash. The refusal is still shown under
    the toggle rather than letting it spring back silently, for the systems where macOS says no.

## The October 2026 rules

Several weeks of real history showed the rules above interacting in ways nobody chose: strength was
26% of the library and 4% of what full breaks served, eye and breathing movements were 7% of the
library and about 20% of what was served, "four blocks by default" came out as five 75% of the
time, and "Hip reset" was the name about twice as often as a fair share. The entries below replace
those rules with a much smaller set. The working list, the reasoning and the simulation behind them
are in `docs/rule-changes-2026-10.md` and `scripts/simulate_selection.py`.

28. **Every full break has the same shape: circulation, then balance, flexibility and strength in
    a random order, then a closer.** This departs from the library's chaining rules (one each of
    FLX, CIR and STR plus one of BAL/HWF/EYE/BRE, a region rotation, time-of-day shapes) and from
    the brief's "STR or BAL, balance served daily". Sharing one slot between strength and balance,
    with balance claiming it first every day, is what kept strength to 4%; now each takes a fifth
    of every break. Circulation stays first as the warm-up after sitting. The region rotation and
    the wind-down shape are gone: the rotation only weighted the draw, about half of routines
    ended up working its slot, and keeping it in a simulation moved each region's share by about
    two points. The closer is one draw over every hand, eye and breathing movement together, so
    each is as likely as any other rather than each bucket taking a third whatever its size.
29. **Every movement runs a minute, thirty seconds a side, after a five-second lead-in.** Length
    is no longer a selection rule. The library's `block_seconds` runs from 20 to 90 s, and fitting
    it into five minutes took a repair pass that swapped short movements for longer ones and so
    quietly drew against the eye and hand movements. Each movement, the first included, now
    appears on a hollow disc counting down from −0:05 so it can be read before its minute starts;
    Next still goes to the next movement. A break is 5:25, and `breakSeconds` follows it, so the
    half-time rule (22) is now 162 s. The transition chime still plays as a movement appears.
30. *(Lengths amended by 39.)* **A micro-break is drawn straight from the micro-eligible pool, and runs its own length.** A
    per-side movement fills the minute alone, thirty seconds a side; otherwise two one-sided
    movements run thirty seconds each, with a five-second lead-in before the second, for 65 s. No
    bucket is drawn first and there is no emphasis rotation: giving the eight eye and breathing
    movements the odds of sixteen stretches is what made them the most-served movements in the
    app. The panel shows each movement in turn — it used to show only the first, for the whole
    minute, while history recorded both — and ends the micro-break itself, as the overlay ends a
    full break. The scheduler's `microSeconds` is 65, the longest a micro-break runs: its backstop,
    and what the half rule (23i) measures. Only the movements the user got halfway through are
    written to history.
31. **A micro-break chimes at its transitions and closes on the completion chime.** The transition
    chime plays as the second movement appears and at a per-side movement's halfway point, as in
    a full break. A micro-break that runs to its end closes on the chime a full break ends on;
    skipping, snoozing and a count-in that never started stay quiet.
32. **Nothing is served twice in a day, in either kind of break.** The library lets walk lap
    (CIR-01), distance gaze (EYE-01) and diaphragmatic breathing (BRE-01) recur freely; they were
    among the most-served movements because of it, and at any realistic number of breaks a day the
    pools never run short without them. Micro-breaks used to avoid only the last micro-break and
    the next full break, so a movement from the morning's break could come back in the afternoon.
33. **Routines have no names.** They are drawn at random, so a name could only describe whichever
    region the draw landed on. The heads-up reads "Movement break in a minute", the overlay's
    eyebrow "MOVEMENT BREAK", the completion screen "Break done" (*removed by 76*), and history
    records "Movement break" (the field keeps its name so older history still decodes). The menu no longer has a
    line under the countdown.
34. **Focus is a body region, not a kind of movement.** "More balance" is gone: balance is in every
    break. "More hands and eyes" stays, as the wrist/forearm and eye regions. A stored
    `moreBalance` reads as no focus.

## October 2026 changes

35. **The app version is set once and the build number counts itself.** `MARKETING_VERSION` in
    `project.yml` feeds `Info.plist`, and `make version V=x.y.z` is the one way to change it. A
    build phase stamps `CFBundleVersion` with the commit count before signing, so every commit has a
    higher build number without anyone remembering to bump it. Versions stay below 1.0 — a minor
    bump for a release with features, a patch bump for one with only fixes — and this build is
    0.5.0: in daily use and roughly whole for its first scope. The library carries its own version
    (41), and the Settings footer reads all three from what is installed.
36. **The break screen always shows the instructions.** "I know this one" collapsed a movement's
    instruction for good, and nobody needs it: the instruction is the reason the break has a
    screen. The per-movement memory of collapsed instructions went with it — removing only the link
    would have hidden those instructions permanently — and the stored field stays in the history
    file, unread, so the file still decodes.
37. **The break's time left is worked out from the plan.** It used to be the wall clock since the
    break began, while each movement started on whichever one-second tick noticed the last one
    end, so the two counters drifted apart by up to a second a movement and the break could run
    out with the movement still on four seconds. Now each movement starts at the previous one's
    planned end, and the header is the current movement's remainder plus the planned movements
    after it, rounded the same way. Pressing Next takes the skipped time off the header.
38. **A full break can be paused so a movement can be read.** Pause, or Space, stops both
    countdowns and every chime; the disc says PAUSED and the header says how long the pause may
    last, and nothing covers the movement or its instruction. Snooze, Skip and Done still work and
    Next does not, so a stray Return cannot move on from a movement being read. Five minutes in one
    pause ends the break — as done if it already counts, otherwise as snoozed even with no snoozes
    left, because a break left paused is coming back, not being skipped. Paused time does not count
    toward the completion rule (22). A lid closed during a pause still ends the break as an
    interrupted one (20), judged by the wall clock; that is not worth the scheduler knowing about
    pauses it otherwise never sees. The micro-break panel has no pause.
39. **A micro-break's first movement gets a lead-in too.** The count-in names the movement but
    never showed its instructions, and the movement started the moment the count-in ended. Every
    movement in a micro-break now opens with the five-second lead-in a full break has, with the
    transition chime as it appears, so a micro-break runs 65 s with one movement and 70 s with two.
    `microSeconds` is 70, amending 30.
40. **Rings fill as a movement runs and drain as a start approaches, everywhere.** The full break's
    ring always filled; the micro-break panel's drained, which looked like it was running
    backwards next to it. A movement's ring now fills in both, per side for a per-side movement,
    and only count-ins and lead-ins drain.
41. **The library says what a movement cannot be done without, and settings say what the user
    lacks.** Movement library 4.1 adds `requires` — floor, wall, stairs — to every movement, set
    by hand from the instructions and only where there is no alternative: the couch stretch needs
    the floor but a wall *or* a chair will do, and a fingertip on the wall for balance is not a
    wall requirement. The existing `settings` field could not be used, because it mixes "can be
    done at" with "needs" (`["Stand","Wall"]` is optional support, `["Floor","Wall"]` needs both).
    Three switches under Movements — a wall, floor space, stairs nearby — default on, and a
    movement needing something switched off is never served in either kind of break. The builder
    never relaxes that rule, since no shortage of options makes stairs appear; with all three off,
    no equipment and the default difficulty cap, the strength slot still has ten movements to draw
    from, three of them new. The loader now checks the
    counts the JSON declares for itself, so a library revision needs no code change.
42. **Twelve core movements, and a More core focus.** The library had five core movements, all on
    the floor and all competing with thirty-three others for the one strength slot, so they almost
    never came up. Nine floor movements (crunch, sit-up, lying leg raise, scissor kicks, bicycle
    crunch, reverse crunch, hollow body hold, alternating heel taps, V-up) and three that need no
    floor (standing oblique crunch, desk plank, seated knee tucks) join the strength bucket as
    STR-39 to STR-50, so core work reaches someone who will not get down on the floor at the
    office. They share the strength slot rather than getting one of their own; "More core" weights
    the core region up for anyone who wants more of it.
43. **An absence resets or pauses the countdowns, and is never a break.** This replaces the two
    credit tiers (23). Any absence past "Count me away after" either starts both countdowns again
    or pauses them — the user's choice under "When I'm away", reset by default — so the hidden
    five-minute line between a micro-break credit and a full one is gone. It adds nothing to the
    day's count and neither builds nor breaks the streak; it is written to history as an away entry
    (`awayReset` or `awayPaused`) that counts for nothing, and "I was sitting" takes the entry back
    out with the rest. Records written as `credited` before keep counting, so days already recorded
    keep their numbers. The toast says what happened — "Away 7 min · break timer reset", or
    "paused" — and Dismiss lets it stand (amending 23a). Standby (23c) is unchanged in either
    behaviour, silent and restarting, but it is now logged as a reset too; a launch gap is still not
    (20b), because nothing was observed. Pausing moves the bout forward with the due times, as the
    launch shift does, so a later settings change cannot make the countdown jump. An older build
    that reads a history file with an away entry in it cannot decode it and starts fresh; that only
    matters on a downgrade.
44. **The away toast sits in the top-right corner**, twelve points under the menu bar like the
    panels and twenty in from the edge, rather than bottom-right as the handoff draws it. The
    panels sit top-centre, so the two never meet.

## Library v4.2

45. **Near-duplicates are grouped into families, and a family counts as one movement.** The
    builders only ever stopped the same id repeating, so a single-leg calf raise hold (balance) and
    a single-leg calf raise (strength) ran back to back in one break, and a standing, a
    half-kneeling and a crescent-lunge hip-flexor stretch all came up in one day. Movement library
    4.2 declares 28 families covering 73 movements; the test for membership is whether the two,
    done back to back, would feel like the same exercise twice. Neither builder serves two members
    of a family in one break or one day, the micro-break's last-micro and next-full-break rules
    compare families too, and recency is summed across a family, so yesterday's FLX-01 weights
    down FLX-02 today. A movement outside every family is a family of one, which keeps the old
    per-movement rules exactly. Avoiding a body region within a break was considered and rejected:
    regions such as Hip and Full cover too many unrelated movements, and it would not have touched
    the hip-flexor case, which spanned several breaks. Because a family can now use up a bucket on
    a long day — strength with no floor or wall shares its standing movements' families with
    circulation and balance — a position that runs out takes a movement already served today
    rather than leaving the break one short.
46. **A movement is split into sides only when its instructions do one side and then the other.**
    Thumb CARs and forearm pronation/supination are done with both hands at once for the whole
    minute. Nine movements whose instructions alternate rep by rep (Cossack squat, standing
    thoracic rotation, reverse lunge and its overhead-reach and paused variants, bird dog, dead
    bug, marching hold, chair-to-single-leg stand) and child's pose with side reach, which runs
    centre then each side, lose their sides, so the break no longer chimes halfway or says "THEN
    RIGHT" over instructions that say to alternate. Shoulder CARs and the median nerve glide stay
    per side: both arms at once lets the low back arch, and the nerve glide's head tilt can only
    go one way.
47. **Fifteen movements fill the library's gaps, with the first for the arms.** Six stretches
    (seated spinal twist, cross-body shoulder, overhead triceps, biceps wall stretch, upper-trap,
    seated butterfly), eight strength movements (isometric biceps curl under the desk, isometric
    triceps press-down on it, 4-way neck isometrics, doorframe row, seated shoulder-blade squeeze,
    standing side leg raise, arch doming, lateral lunge) and toe yoga, as FLX-39–44, STR-51–58 and
    BAL-30, with a new Arm region. Most can be done in a chair, so twelve are micro-eligible. The
    doorframe row is tagged as needing a wall, the closest switch settings offer to a door frame.
    Rejected: chair dips, since most desk chairs roll; a pec-minor wall stretch, which the doorway
    pec stretch already covers at its high elbow position; and a held side-lunge stretch, which is
    the Cossack squat held still. The lateral lunge joins the Cossack squat's family instead.

## Minor changes, October 2026

48. **"Sitting for" counts the current sitting bout, not the time since the last break.** The
    deferred badge on the heads-up measured from the last completed break, which was the same thing
    while an absence counted as a break. Since 43 an absence no longer moves the last break, so a
    morning after a night away read "Sitting for 17 h" although standby had restarted everything.
    It now measures from the bout start, which a completed break, a reset absence and standby all
    move to their end and a paused absence shifts forward by its length, so it counts desk time only.
49. **The whole break shows on every display.** The handoff put the card only on the display with
    the cursor and gave the others the dim with "MOVEMENT BREAK · 4:12 left", which left someone
    facing the other screen with nothing to follow. Every display now gets the full card. All of
    them run off the one break, so the timer, the buttons, the side toggle and a collapsed
    instruction stay in step whichever screen is used, and each chime plays once. The display with
    the cursor still holds keyboard focus, and the arrow, Return and Space keys work from anywhere.
50. **The JSON is the library.** Each library had a Markdown version, a JSON version and a script
    meant to turn the first into the second. Nobody edits the Markdown by hand, the JSON had been
    edited alongside it since v4.1, and the movement library's converter no longer ran. The
    Markdown files and both converters are gone, and changes are made to the JSON directly. What
    only the Markdown held moved into the JSON first: the movement library's version history into
    its `notes`, and the strength library's design rules and its overlap table with the movement
    library as `design_notes` and `overlap_with_movement_library`. `source` is dropped and
    `generated` becomes `updated`, the date of the last edit.
51. **The Focus filter's "Pause breaks" is off by default** (amending 26). macOS performs a Focus
    filter with its default values whenever no Focus is on: once after every boot, for every app
    that has a filter, and each time a Focus ends. With the default on, a reboot paused Movez with
    no Focus running, and a Focus that ended could never resume the breaks it had paused. Off by
    default, both now leave breaks running, and a pause the user set is still never undone by a
    Focus. Attaching Movez to a Focus means switching "Pause breaks" on in that Focus's filter.
52. **The app is called Movez.** Every name a person reads (the Settings window title, "Quit Movez",
    the version line, the start-up and error messages, the Focus filter's name, and the bundle's
    display name) and the documentation's prose now say Movez. Everything that is a name on disk
    or on the web stays lowercase: the repository, `movez.app`, the executable, the bundle
    identifier `com.kylemack.movez`, the Xcode project and source folders, and the data folder in
    Application Support, so builds, links, Launch at Login and saved state are untouched.
53. **Nothing runs until the health and safety notice is accepted.** On launch Movez reads
    `HEALTH_AND_SAFETY.md`, bundled from the repository root like the movement library, so the
    app and the repository can never show two different texts. If its version has not been
    accepted, the notice opens in a window of its own, and the coordinator is not built: nothing
    is scheduled, polled or written. "I understand and agree" stays unavailable until the end of
    the notice has scrolled into view, and Quit, or closing the window, quits. Accepting records
    the version and the time. The "Notice version" line in the file is what asks again: raising
    it re-asks everyone, and an edit that keeps it does not. Settings → General → "Health, safety
    and terms" shows when it was accepted and reopens it read-only. While it waits, the menu says
    so and offers "Show notice" and Quit. A notice that is missing or has no version is fatal at
    launch, like a missing library.

## Strength mode, November 2026

Movez gained a second mode, Strength, beside the existing break mix, which is now called
Movement. Strength breaks are for keeping office workers strong through long desk days:
maintenance, not muscle building, and never gym-heavy. The brief and the scheduler research say
nothing about strength work, so the rules below rest on three pieces of research done for this
change. Where a finding came from training knowledge rather than a study, or a number was derived
rather than measured, the entry says it is judgment. The studies are cited by author as the
research cited them: Spiering et al. (J Strength Cond Res 2021) on the maintenance dose, the
ACSM position stands (2009 and March 2026), Nuzzo et al.'s overview of minimal-dose training and
exercise snacks (Sports Med 2024), Ralston et al. (Sports Med Open 2018) on frequency, Robinson,
Refalo, Zourdos et al. (2024) on proximity to failure, Pelland et al. (Sports Med 2026) on
counting sets, Bickel, Cross and Bamman (MSSE 2011) on older adults, de França et al. (2015) and
Gentil et al. (2013) on arm isolation, and Martuscello et al. (J Strength Cond Res 2013) on the
core. Movement mode's library, routine rules, timings and chimes are unchanged; a golden record
of its picks, taken before any of this was built, is replayed by a test to prove it.

54. **A mode is a row in a table.** Two more modes are planned, a "100s" rep mode and a physical
    therapy mode, so the mode is not a flag but an enum backed by one `ModeDefinition` per mode
    in `Sources/movez/Modes/`: its name, the word in its eyebrows, its badge and menu-bar glyphs,
    its library, its break builders and its settings group. The Settings mode control, the
    dropdown's mode row, every badge, the menu-bar icon and the coordinator's one build path all
    read the definition rather than branching on Movement or Strength, and a test that adds a
    fake third mode in the test target shows each of them serving it with no production change.
    Any code that must tell the modes apart lives in `Modes/`, which a test enforces by grepping
    the rest of `Sources/`. The mode is persisted under its own key, absent meaning Movement, so
    an existing install upgrades to exactly what it had.
55. **The mode is shown by a badge and the menu-bar glyph, never by color.** The first plan
    recolored the whole app orange in Strength mode. That was dropped before it was built:
    orange is too close to `warn`, which already means "waiting" and "paused"; four modes would
    need four accents; and the menu bar is monochrome anyway. Instead every surface that names a
    break or the app's state (heads-up, overlay, micro-break panel, dropdown, Settings) carries
    the mode badge, the mode's glyph beside its name, as in "STRENGTH BREAK" with a dumbbell, in
    fixed places, and seafoam stays the only accent in every mode. The menu-bar icon became the
    design's 18 pt circle with the mode's glyph inside, Movement's wave included, so the two
    modes differ by glyph alone and Movement's icon changed too. Movement's panels gained its
    badge, and the micro-break eyebrow now reads `MOVEMENT MICRO-BREAK` without the body area.
    Glyphs for 100s and PT are drawn already, so those modes add a row and not a theme.
56. **Strength has its own settings, and the first switch opens them.** Equipment (a pair of
    dumbbells, one kettlebell), "Solid wall nearby", strength breaks a day, the difficulty cap,
    focus and excluded moves are all separate keys from Movement's, so changing one mode's setup
    never touches the other's; working hours, break timing and away handling stay shared. The
    first switch to Strength, from Settings or the dropdown, leaves the mode on Movement and opens
    Settings at a strength setup, because a strength break built for equipment the user does not
    own is worse than none. "Switch to Strength" confirms it, and may be pressed with nothing
    ticked, which means bodyweight only. The cap starts at Beginner. Every later switch is
    instant. A switch never changes what is on screen: a heads-up, break or micro-break finishes
    in the mode it started in, and the next one uses the new mode, also after a relaunch.
57. **Strength days alternate an A day and a B day, with core once a day.** An A day works
    squat/lunge and push, a B day hinge and pull. The next strength day is the other letter from
    the last day that had a completed strength break, whatever mode the days between were in, and
    the first ever is A. The first plan had a leg move and a rotating upper-body move in every
    break, which the research showed would give the legs about twice the weekly volume of chest
    or back (Pelland's counting, below); pairing non-competing patterns and resting each pattern
    a day is the usual coaching answer, so it is judgment rather than a trial result (the ACSM
    2009 recovery window of 24–48 h is the evidence it leans on). The day's first strength break
    replaces its third set with one core set, since the core needs only a few direct sets a week
    once loaded moves are in the pool (Martuscello 2013).
58. **A strength break is a warm-up, three sets X · Y · X and a cool-down, with no end screen.**
    The research found the draft of five moves in every break to be 10–90 times the evidenced
    maintenance dose of about one hard set per exercise a week (Spiering 2021), and exercise-snack
    trials used one set of a few exercises (Nuzzo 2024). So a break is a 30 s warm-up (one
    bodyweight, difficulty-1, two-sided move from the first set's pattern, off the floor, with no
    rep target), three working sets of the day's two patterns, the pattern done twice using the
    same move both times, then a 30 s cool-down (one END stretch for a region the sets worked,
    15 s a side for a per-side move). The next break leads with whichever pattern has had fewer
    sets today, a tie going to the one that led less recently. Between sets is 45 s of rest that
    shows what comes next and whose last 5 s are the next set's lead-in. A set's timer is the reps
    × 3 s plus 5 s of grace, with 3 s more on a per-side set to switch and (3 + hold) s a rep for
    a dose with a hold; when it runs out the rest starts with a chime, and Done (the disc or
    Space) ends a set early. The rest of 45 s, shorter than the 2–3 min strength coaching uses
    between sets of one muscle, works because the sets alternate patterns; that is coaching
    practice, not a finding. A break runs about 4½–5½ min and closes itself after the cool-down:
    the design dropped the end screen because there is nothing to review. A break has at most
    one per-side, one floor and one grip working move, never a wall move with the wall off, and
    only moves that are bodyweight or use what the user owns. When the pool runs short, the draw
    lets rules go one at a time and then takes back every rule it can, so a break is never empty
    and never relaxed further than it has to be.
59. **The first three strength breaks of a day are strength, and the rest are end-range.**
    "Strength breaks a day" is 1, 2, 3 or 4, default 3. The first that many full breaks completed
    in Strength mode are strength breaks; a skipped or snoozed one does not count, so the next is a
    strength break again with the same shape. Every later full break that day is an end-range
    break: four END stretches of 60 s (30 s a side) after a 5 s lead-in each, 260 s in all,
    recency-weighted, never repeating a move that day and avoiding the regions the day's strength
    breaks worked where it can. The research suggested 2 a day; the owner chose 3, which puts the
    bigger muscles slightly above the derived maintenance target (entry 69) and was accepted
    because the loads are light and real weeks miss breaks. One a day still meets the floor for
    every body part, which is why 1 is allowed. Switching from Movement mid-day counts only that
    day's strength breaks.
60. **Doses are 10–15 reps, 16–20 alternating and 8–10 a side, at a weight you could lift 3–5
    more times.** In the working buckets (SQT, HNG, PSH, PUL, COR, ACC) the strength library's
    two-sided rep doses are 10–15, alternating doses 16–20 in total and per-side doses 8–10 a
    side, so five 20-rep doses became 15 and two became 10 a side. Six slow multi-part moves keep
    their doses, because a rep of each is several movements and the count is already the right
    effort: PUL-01 ("5 of each"), HNG-17 (6 reps), COR-11 (8 each direction), COR-14 (5/side),
    COR-15 (6/side) and COR-16 (3/side). COR-05, the bird dog, keeps 12 alternating as a named
    exception too: each rep holds 2 s at full reach, so 12 is already the effort of 16–20, and
    COR-17, the plank pull-through, went from 12 to 16 alternating to sit in the range (*amended
    in the November 2026 review, TST-24*). Doses in seconds and every END dose are unchanged. The
    load guidance asks for a weight that leaves 3–5 reps in reserve, about RPE 7: stopping short
    of failure costs little strength (Robinson et al. 2024), people training unsupervised rarely
    go near maximal loads (Nuzzo 2024), and a break must not leave anyone winded or sweaty in
    work clothes. The guidance appears in Strength settings and the first-switch setup only, never
    during a set, and no copy asks for "max reps" or "as many as you can". The rep range itself is
    judgment: the research's evidence is for about 12 reps per snack.
61. **The kettlebell is the heavy bell, and moves it is too heavy for are dumbbell-only.** The
    equipment is one kettlebell of about 20–23 kg (45–50 lb) and one pair of dumbbells, with chair,
    desk and floor always there and a wall only when the setting says so. A fixed heavy bell
    suits squats, hinges, rows and the heavy-tier moves, so SQT-04, SQT-06, SQT-08, SQT-10,
    SQT-12, SQT-15, HNG-14, HNG-18, PUL-10, PUL-18 and every heavy-tier move keep it. Eight moves
    that listed either but cannot be done well with one heavy bell (PSH-12, PSH-15, HNG-13,
    COR-02, COR-11, COR-14, COR-16, COR-17) became dumbbell-only, in their equipment and
    instructions, and
    the kettlebell is only ever offered for a move that lists it. A kettlebell-weight setting was
    decided against: a goblet move that feels too heavy can be done with a dumbbell held
    goblet-style, which the copy says.
62. **Five curls join PUL, and "Arm" means biceps and triceps.** The library had triceps work and
    nothing for the biceps. PUL gained a dumbbell curl, a hammer curl, an under-desk isometric curl
    (bodyweight), a seated concentration curl (one arm at a time, per side) and a reverse curl
    (grip), each in the library's style with a dose in range, which makes 145 movements and 23 in
    PUL; the Arm region is documented as biceps and triceps. They sit in PUL rather than ACC
    because push and pull already give the arms enough indirect work to maintain them (de França
    2015 and Gentil 2013 found isolation added nothing measurable), so arm work is something a
    pull set may draw, not a guaranteed slot. ACC is not drawn by any strength break.
63. **Focus weights every draw of a strength break ×3.** The strength focus is None, More legs and glutes,
    More back and shoulders, More core or More arms. Within a pattern every draw is weighted by
    recency, and a move in a focused region (legs and glutes: quads, glutes, hamstrings and
    adductors; back and shoulders: thoracic and shoulder; core: lumbar and core; arms: arm and
    wrist and forearm) weighs three times as much. Focus never changes which patterns a day
    works, so it tilts a week without unbalancing it. Three is judgment, kept as one constant.
    The warm-up and the cool-down are draws of the break too, so More legs and glutes, More back
    and shoulders and More core also tilt which warm-up opens a break and which END stretch closes
    it. *Title corrected in the November 2026 review: it said "a working set's draw" (LIB-13).*
64. **A move served in either mode is not served again that day in either mode.** A strength move
    whose `v4_overlap.kind` is `same` (28 of them) is the same exercise as its movement-library id,
    and that id counts together with its family (entry 45), so a glute bridge (STR-01) in a
    Movement break in the morning keeps the strength glute bridge (HNG-01) out of the afternoon,
    and the reverse. A
    `similar` overlap is different enough to share a day. When no strength move was served,
    Movement's picks are exactly what they were.
65. **Difficulty 3 unlocks per strength bucket.** Movement unlocks difficulty 3 per movement. In
    Strength a bucket's difficulty-3 moves become eligible once difficulty-2 moves from that
    bucket have been completed 5 times in all, using the same threshold. Counting by bucket fits a
    library where a bucket is one movement pattern and its harder moves are progressions of the
    easier ones, so the practice that earns the unlock is the pattern's, not one move's. The
    threshold is judgment, shared with Movement so there is one figure to tune.
66. **A rep meter paces every rep at 3 s, from one constant.** During a rep-based set a meter rises
    for 1.5 s and falls for 1.5 s once a rep, beside "Rep n of N", and stops at N for the 5 s of
    grace. A per-side set counts N, shows "Switch sides" for 3 s, then counts N again; a dose with
    a hold rises, holds full for the hold, then falls; alternating reps each count toward the
    total. It is silent, freezes when paused, and steps once a rep instead of moving with Reduce
    Motion on. Timed holds, doses in seconds and the six slow moves of entry 60 show no meter and
    use the library's `block_seconds` as the set length. The 3 s pace is the one figure the set
    timer and the meter share, `StrengthBreak.repPaceSeconds`; a pace per movement was considered
    and deferred, since one even pace is enough to keep reps controlled. The meter takes a rep
    count and a pace rather than a strength break, so the 100s mode can reuse it. The rep target
    is a target only: reps and weights are not logged.
67. **Strength micro-breaks are END stretches, never on the floor.** After the 30 s count-in a
    strength micro-break is either one per-side END move for 60 s (30 s a side) or two two-sided
    END moves of 30 s, each after a 5 s lead-in; the design's "always two moves of 25 s" was
    turned down to keep that shape. A micro-break is taken at the desk in work clothes, so there
    is no floor move, which overrides an earlier answer that allowed one, and the second move
    keeps the first one's posture, standing or seated, so nobody is up and down inside a minute.
    A micro-break shares no region with the previous one, avoids the next full break's regions
    when it can, and repeats no move that day while the pool allows.
68. **Away works the same in both modes.** For a while Strength mode was to ignore absences and
    keep its countdown running. That was reversed: an absence past "Count me away after" resets
    or pauses both countdowns according to the shared "When I'm away" setting, is logged as an
    away entry that counts for nothing, and shows the same toast with "I was sitting", exactly as
    entry 43 has it for Movement. The scheduler has no strength branch at all.
69. **The simulation proves the rules and reports weekly hard sets per body part.**
    `scripts/simulate_strength.py` mirrors the Swift draws exactly, checks every break against
    `scripts/strength-rules.json` and writes `docs/strength-simulation.md`: at least 5,000
    strength, end-range and micro-breaks for every combination of dumbbells, kettlebell and wall
    at caps 2 and 3, plus the app defaults, with zero violations and no eligible move never
    served; a Swift test cross-checks 200 seeds against it. Weekly sets count a direct set as 1
    and a helper set as ½, the fractional counting that fit best in Pelland 2026: squat/lunge
    gives quads 1 and glutes ½, hinge hamstrings 1 and glutes 1, push chest 1 and triceps ½, pull
    back 1 and biceps ½, core 1. At the default (3 strength breaks a day, every break taken,
    5 days) the targets are 8–12 sets a week for quads, chest, back and hamstrings, 12–18 for
    glutes, 4–7 for biceps and triceps and 4–6 of direct core. These are judgment: no trial tests
    maintenance volume per muscle or a desk strength break, and the research's derived target of
    4–8 per muscle (higher for people over about 50, per Bickel 2011) sits a little below them for
    the reasons in entry 59. The ½ helper mapping and the claim that loaded moves cover most core
    work are training knowledge, not findings. Re-run the script after any change to a strength
    builder or the strength library.
70. **Biceps and Triceps are their own categories, trained in an arm break.** Counted directly,
    the curls in PUL and the overhead extension in PSH took sets that back and chest need: the
    default week has only 8 pull sets, so a curl drawn there left back short. BIC (six moves) and
    TRI (six) became their own buckets, with new ids for the moved moves (PUL-19–23 to BIC-01–05,
    PSH-18, PSH-06 and PSH-09 to TRI-01–03) and four new arm moves; with two new loaded lunges
    (entry 71) the library has 151 movements.
    An arm break is a warm-up, three sets and a cool-down like any strength break: two sets of one
    arm move and a third of a different one from the same bucket (A · A · B, no core set),
    triceps on an A day and biceps on a B day, so the arm lands on the day whose pattern already
    uses it as a helper. Its warm-up is the usual warm-up of the day's push (A) or pull (B), and
    since no END move stretches the arm, its cool-down only has to stretch the shoulder, chest,
    arm or wrist and forearm. The arm break is the fourth strength break of a day, or the third
    with More arms (where a fourth is then an ordinary push-pull break), and only when the day
    has more strength breaks than its position, so 1 or 2 a day never get one. The pattern breaks
    step over it: its sets count toward neither pattern and it leads with neither, so a day's
    pattern breaks are exactly the ones it would have had without it. History records it as an
    ordinary `strengthA`/`strengthB` break, so when the planner replays earlier days for the last
    lead it puts the arm break at today's position, whatever that day's setting was; only a
    change of focus or kit since can misplace it, which moves at most one tie. A kit with a
    kettlebell but no dumbbells has no vigorous arm move (the arm buckets have no kettlebell
    moves, entry 71), so its arm break stays an ordinary push-pull break. This supersedes, for
    arms only, entry 62's "arm work is not a guaranteed slot" and entry 63's "focus never
    changes which patterns a day works": More arms moves the arm break earlier. A biceps or
    triceps set counts 1 toward its muscle in the simulation's weekly sets; at 4 a day an arm
    break adds 9 direct sets a week to one arm and 6 to the other, and with More arms at 3 a day
    it takes the third break from the patterns. Arm targets are not set yet, so those tables are
    reported, not checked.
71. **With kit selected, a working set must be vigorous.** Every strength move has a `vigorous`
    flag: whether it is hard enough to be a working set beside a loaded move. Every equipment
    move is (the loader refuses a file where one is not). Of the bodyweight moves, the push-up,
    tempo, decline and pike push-ups (PSH-04, 05, 07, 08), the single-leg glute bridge and the
    single-leg chair-edge hip thrust (HNG-02, HNG-06), all eleven bodyweight core moves and the
    chair dip (TRI-03) are; every other one is not. No squat or lunge is, because each now has a
    weighted counterpart (SQT-17 and SQT-18 were added for the curtsy and forward lunges), and
    the single-leg RDL is not, because its loaded version is difficulty 3 and the kickstand RDL
    is its difficulty-2 step. Core is all vigorous because that is simpler than leaving core out
    of the rule, and the loaded core moves are there for anyone who wants them. With any kit
    selected, a working set (core and arm sets included) draws only vigorous moves, so the light
    bodyweight moves are warm-ups only; bodyweight-only users have no such rule. The rule is a
    rung in the working ladder after "served today", so repeating a vigorous move beats serving a
    light one, and it goes before the exclusions and the difficulty cap. In the simulation it has
    never had to let go: every pattern a kit can reach has a vigorous move, and a kettlebell
    alone at cap 2, with the push-up as its only vigorous push, repeats the push-up instead.

## The November 2026 review

Entries from fixing the findings in `docs/code-review-2026-11.md`.

72. **A settings change moves the countdown by the change, not from the bout start.** A longer
    or shorter sitting interval moves the next break by the difference, and every other setting
    leaves the due time alone. The micro-break keeps its own cycle: it is re-planned only when the
    sitting interval or a micro-break setting changed, from its due time less the old interval,
    and from now when micro-breaks are turned on. For a bout nobody has touched this is the same
    as entry 24. The difference is after a skip, a resumed pause or a finished micro-break, which
    restart a countdown without moving the bout: re-planning from the bout start brought back the
    break the user had just skipped, cut a pause's hour off the countdown, and served a second
    micro-break minutes after the first (SCH-1).
73. **A break the lid closed on is settled into history, and standby still credits one that
    counted.** Back after the break was due to end, the break is judged by the completion rule as
    before, and the verdict now reaches history as a done or skipped record written from the
    session kept at the interruption. The scheduler judges it by the user's return, not by when
    the quiet minute confirmed it. Away for a whole sitting interval, the break is still not
    resumed, but one that had already met the completion rule is credited as done; one that had
    not is let go with no skip recorded, because the user left rather than turned it down (SCH-3).
74. **Working hours follow the Mac's current time zone.** "9 to 6" means local time wherever the
    Mac is. The scheduler, the history's calendar days, the strength planner and the transition
    log all use the auto-updating calendar, so a Mac that flies from London to New York with Movez
    running starts judging hours, midnight and the day's counters in New York time at once, rather
    than on the next launch or settings change (SCH-9).
75. **A full break holds the display awake.** While the overlay is up it holds an idle
    display-sleep assertion, released the moment the break leaves the screen. The user is meant to
    step back from the keyboard, so without it the display slept a minute or two into a break on a
    laptop on battery, which the scheduler takes for a closed lid. Panels hold nothing: a heads-up
    or a micro-break that the display sleeps through is no loss. A closed lid or a lock by hand
    still interrupts a break (UI-2).
76. **A movement break has no end screen, and there is no streak.** When the last block ends, or
    Done is pressed, the break leaves the screen with the completion chime, as a strength break
    already did (58). The "Break done" card was only ever on screen for the 0.3 s fade, its Back to
    work button could not close it, and its numbers were captured as the break began. The streak
    was shown nowhere else, so it is gone with the card: the chip, its text styles, the end dim,
    the coordinator's published count and the history's calculation. This supersedes entry 4 and
    the end-screen part of 33 (UI-7).
77. **The microphone signal asks which processes are recording, not whether the default input
    device is running.** Reading `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default
    input missed a call on any other microphone (Zoom on a USB headset while the default is the
    built-in mic, or AirPods connecting mid-call), and it read music through a headset as a call,
    because that property is device-wide and says nothing about direction. On macOS 14.2 and later
    the signal is now any process other than Movez with `kAudioProcessPropertyIsRunningInput` set,
    from `kAudioHardwarePropertyProcessObjectList`: per direction, on every device. Before 14.2 it
    falls back to every device that has input streams and is running, which no longer misses a
    non-default mic but still cannot tell direction on a duplex device. This is the next step 23h
    named. The minute's sustain stays, since a dictation burst is still a process recording
    (SIG-2).
79. **A Movement break's seed comes from the day's recorded breaks, as a strength break's does.**
    The full break is built from a seed of the day and an index, and the index was the breaks
    this run of the app had put on screen. A relaunch set it back to 0, so a break skipped before
    any block was done, which leaves no completion in history, was built again from exactly the
    same context and came back as the five movements the user had just turned down, against
    entry 32. The index is now the breaks recorded today, absences aside, the count Strength mode
    already used, so a relaunch carries on where it was. Two things follow. A break snoozed or
    skipped at the heads-up writes a record, so the break offered after it is a fresh draw rather
    than the one announced, as in Strength mode. And a break put on screen but not done still
    counts as served only until the app quits; storing its movements in history was left out,
    since a new seed already makes the same break again unlikely, though not impossible (LIB-8).
80. **A bodyweight strength break's heads-up does not ask for weights.** The design's heads-up
    reads "About 5 minutes, three sets. Have your weights nearby." for every strength break, but
    a setup confirmed with nothing ticked is bodyweight only (56), and that user read the request
    before every break. A break with no loaded set now reads "About 5 minutes, three sets.", and
    one with any loaded set keeps the design's sentence (LIB-6).
