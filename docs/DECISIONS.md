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
   fixed four.
7. **Other displays show the dim and a small label**, not a second copy of the card.
8. **A deferred break is never shortened.** It waits, at full length. What it loses is patience:
   a break that has waited more than half an hour gets one snooze instead of two.
8a. **A routine is named for what it actually works.** The rotation slot biases selection but
   does not force it, so naming by slot put "Upper back opener · t-spine and chest" over leg
   swings and squats. The name comes from the slot whose regions the stretch and
   strength-or-balance blocks work for the most seconds, ties going to the planned slot. The
   rotation itself and the chaining rules are unchanged, and the last break of a working day
   keeps its time-of-day name.

## The micro-break

9. **The thirty-second count-in stays**, with Start now · Snooze 5 min · Skip, then a sixty-second
   countdown with Snooze 5 min · Skip.
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
23. **Idle is credited in two tiers**: three to five minutes hands the countdown back with the
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
    in more than 11% of routines.
23f. **The region rotation carries on across days, and there is no wake-up routine.** The
    rotation index was the day's break count, so a user who takes two breaks a day saw the first
    two slots — hips, then upper back — and no others, for ever. It is now a cursor over the
    routines actually done, counted from the completions already in history. The wake-up shape
    went with it: it applied to the first break of every calendar day, which for anyone working
    odd hours is not the start of anything, and it spent half of its blocks on circulation. The
    wind-down shape stays, but only when the working day genuinely closes — always-on working
    hours report an end at midnight, which used to give anyone working late a wind-down routine
    every night.
23g. **The post-lunch rule is gone, and micro-breaks draw from more buckets.** A return from
    twenty minutes away between 11:00 and 14:00 used to mark the next micro-break as post-lunch,
    however many hours later it came, and that micro-break was a single minute drawn from four
    movements. Every micro-break also contained a circulation movement, so twelve movements
    carried all of them, and the balance and strength movements marked micro-eligible were never
    served at all. Each emphasis now leads with its own buckets and follows with a wider set.
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
