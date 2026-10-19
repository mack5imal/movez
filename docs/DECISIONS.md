# Decisions

Where movez departs from, or resolves an ambiguity in, the product brief, the scheduler research
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

4. **The end-of-break streak chip stays.** A streak is consecutive completed full breaks today;
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
20b. **Time movez was not running is moved past, not judged.** The state file records when it was
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
    reversible while the away toast is up, because movez cannot tell a walk to the kitchen from a
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
    working day opening while movez was away, which is what a gap crossing working hours means.
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
    changing a preset never costs the user the time they have already sat.

## Known compromises

25. **Screen-capture detection is a heuristic.** macOS exposes no public API for "my screen is
    being recorded", so movez watches for the tools people actually use, conservatively: a false
    positive quietly postpones a break, which is better than interrupting a live share. Tools that
    idle in the menu bar all day (Loom, CleanShot X, Kap) are listed but disabled.
26. **Focus is read through a Focus Filter, not the system.** There is no supported way to read
    the current Focus, so movez ships a `SetFocusFilterIntent` the user adds to their own Focus.
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
    eyebrow "MOVEMENT BREAK", the completion screen "Break done", and history records "Movement
    break" (the field keeps its name so older history still decodes). The menu no longer has a
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
    that has a filter, and each time a Focus ends. With the default on, a reboot paused movez with
    no Focus running, and a Focus that ended could never resume the breaks it had paused. Off by
    default, both now leave breaks running, and a pause the user set is still never undone by a
    Focus. Attaching movez to a Focus means switching "Pause breaks" on in that Focus's filter.
