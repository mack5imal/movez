# Movez — Scheduler research and recommendations v1

Purpose: answer the "spec the scheduler as a state machine" questions from the pre-build checklist, using what the competition does and what their users reward or punish. Section 4 is the part that feeds the product brief and Supergoal intake; sections 2–3 are the evidence.

Research date: 2026-09-11. Apps examined: Time Out (Dejal), LookAway, Stretchly, BreakTimer, Workrave, Intermission, Rest Time, Awareness, Wakeout, Moova. Sources: official docs and release notes, GitHub issue trackers, Mac App Store reviews, Hacker News, Product Hunt, AlternativeTo, and independent blogs. Reddit was not reachable from the research environment.

One correction to the original framing: **Moova is not a Mac app.** It's iOS/watchOS/Android (formerly StretchMinder). Its scheduling is a plain notification timer; its differentiator is content (200+ guided moves, animated 3D figure, generated sessions). It is still the right reference for the *break content* model, but not for the scheduler. For scheduling, the reference points are Time Out (most configurable), LookAway (best interruption-avoidance), and Stretchly/BreakTimer (open source, with public issue trackers that document every failure mode).

---

## 1. Summary of recommendations

| Question | Recommendation | One-line rationale |
|---|---|---|
| Clock basis | Wall-clock timestamps evaluated by a 1 s tick, with idle handled as explicit state (not "active-time only") | This app limits *sitting bouts*; sitting still while reading is still sitting |
| Idle < 3 min | Counts as sitting | Reading, thinking, calls: still seated |
| Idle 3–5 min | Pause countdown; on return, resume with remaining time and treat the absence as a micro-break | A washroom trip is movement, but not a full break |
| Idle ≥ 5 min | Treat as a completed full break; fresh interval starts on return | Matches every competitor's default; the user demonstrably got up |
| Return from idle | Auto-decide, then show a reversible, auto-dismissing toast ("Counted as a break · I was still sitting") | LookAway removed its "were you away?" modal after complaints |
| Sleep / lock | Same rules as idle, measured by wall-clock gap; never fire a break in the first 60 s after wake; dismiss any overlay on sleep/lock | BreakTimer #53 "always a break after lunch"; Stretchly #1807 frozen overlay after wake |
| Meetings / screen share | Detect mic-in-use, screen capture, fullscreen frontmost app; **defer** the break, don't reset; 2-min grace after activity ends | The single most-requested feature across every tracker; Stretchly's "pause = reset" is its top timing complaint |
| Do Not Disturb / Focus | Respect macOS Focus via a Focus Filter the user opts into; also honor a manual "pause for…" menu | OS-level Focus detection without a filter is fragile (Stretchly's broke on Tahoe) |
| Mid-input | Never fire mid-keystroke or mid-drag: wait for a 10 s input pause, max 60 s | Time Out and LookAway both do this; HN users call it the difference between tolerable and uninstalled |
| Warning | Two-phase: heads-up 60 s before (Start now / +5 min), then slow fade-in overlay | The interaction pattern users consistently praise |
| Snooze | +5 min, max 2 per break, doesn't count as a skip | Bounded snooze is Time Out 3.0's "most popular request" |
| Skip | Always available, but the button is disabled for the first 3 s and the daily skip count is shown | Friction on skip, not on snooze; users report clicking skip "subconsciously" |
| Overlay | Dimmed/blurred overlay on all displays, not input-blocking, focus restored afterwards, remaining time visible | Notifications get missed; hard blocks get uninstalled; dimming is the accepted middle |
| Working hours | On by default, Mon–Fri 9–6, editable; fresh interval at start of day | Standard in BreakTimer, Time Out, LookAway |
| Micro / full interplay | A full break (or a credited absence ≥ 5 min) re-anchors the micro schedule; micro within 10 min of a full break is dropped; micro due during suppression is silently skipped | Prevents stacking; micro-breaks are low-cost to drop |
| Day boundary | Reset all state at working-hours start, or after any gap ≥ 4 h | Prevents "sitting for 14 hours" after an overnight |
| Completion | A full break counts as done if the user reaches ≥ 50% of the movements or ≥ 50% of the time | BreakTimer's rule; keeps the day's stats honest without punishing an early exit |
| Debug | Time-scale factor (e.g. 60×) and a state-inspector panel from phase one | Every competitor's sleep/idle bugs were found late because they're slow to reproduce |

---

## 2. What the competition does

### 2.1 Idle detection and "natural breaks"

Every serious app treats sustained idle as a break the user took on their own, and the 5-minute default is near-universal.

- **Stretchly**: `naturalBreaks` on by default, `naturalBreaksInactivityResetTime` = 5 min. Idle > 20 s flags "on natural break"; idle ≥ 5 min clears the scheduler; on return the whole cycle restarts (mini-break counter zeroed, full interval from the moment of return). Idle under 5 min is ignored. Known gap: video playback reads as idle (issue #965).
- **BreakTimer**: "Smart Breaks", `idleResetLengthSeconds` = 300, on by default. Idle ≥ threshold suppresses breaks; return resets to a full interval; optional notification "Break automatically detected." v2.0.0 fixed timing to reflect actual idle start.
- **Time Out**: the most nuanced. Per-break natural-break policy with three options: *Continue Countdown* (ignore idle), *Pause Countdown* (stop counting after 30 s idle), *Count Backwards* (default: pause after ~1 min idle, and after twice that long start crediting the idle time by pushing the due time later). A separate *Reset after natural break* threshold treats long idle/screensaver/sleep as a completed break. Detection via an event monitor (needs Accessibility) with a mouse-only fallback.
- **LookAway**: detects natural breaks and, as of 2.3, auto-decides resume vs restart from "various system signals," showing a non-blocking, auto-dismissing toast with a one-click reversal. This replaced a modal "did you step away?" prompt that users disliked.
- **Rest Time / Awareness**: pure active-time models ("timer begins only when you become active"; Awareness senses a 5-minute break and resets).

User evidence: Stretchly #1560 ("came back from the washroom… Stretchly about to start a mini-break"), #1724 (screen lock/unlock within seconds resets the timer), #1820 (break fires while reading or on a call because no typing), Workrave #369 (video counts as idle). The failure modes are symmetric: too-coarse thresholds miss short real breaks, and input-only detection misreads reading and video.

### 2.2 Sleep, wake, and lock

- **Stretchly**: listens to `powerMonitor` suspend/lock/resume/unlock. Default pauses on suspend/lock and starts a fresh interval on resume. History of crashes/hangs on unlock (#516, #1369) and a frozen full-screen break window after wake requiring a hard power-off (#1807).
- **BreakTimer**: no power events; a 1 s tick measures the gap since the last tick. Gap > interval → drop the pending break (treated as an auto-detected break); gap > idle threshold → treat as idle. This was the fix for #53 ("after resume from sleep, BreakTimer *always* starts a break… especially after lunch").
- **Time Out**: sleep counts toward the natural-break reset; release notes show repeated fixes (2.2.1 "incorrectly adding the sleep duration to the due time"; 2.4 "if a break would be due in the past after rescheduling, it is reset"; 3.0 "improved the reliability of resetting breaks when waking"). A break interrupted by closing the lid resumes if reopened before it would have ended.
- **Workrave**: timer "continues even if hibernation takes hours" (#567).

The lesson is that sleep handling needs both signals (power events for immediate reaction, tick-gap detection as the safety net) and a rule that nothing fires in the first minute after wake.

### 2.3 Meetings, screen sharing, fullscreen, Do Not Disturb

This is the most-requested capability on every open-source tracker (Workrave #255, #640, #339; Stretchly #355, #969, #1120, #1479, #1838; BreakTimer #259; Intermission reviews) and the headline feature of the two best commercial apps.

- **LookAway "Smart Pause"**: microphone activity (moved from camera to mic-only in 1.12 to kill false positives; per-app and per-mic exclusions), screen recording/sharing detection by process (OBS, QuickTime, Zoom share…), fullscreen games, user-picked deep-focus apps (fullscreen/foreground/open), Apple Calendar events, macOS Focus via Focus Filters, and "don't show breaks while I'm typing or dragging." Breaks are *delayed*, with a configurable 1/2/5-minute "break delay after activity ends."
- **Time Out 3.0 "Rules"**: App rules (frontmost or open), Calendar Event rules, Fullscreen Active, and script rules with built-ins for FaceTime, Teams, and Zoom meetings. Actions: *Automatically skip*, *Postpone* (keeps postponing until the rule stops matching), *Ignore natural break* (for video apps), *Treat as natural break* (for games). Plus a checkbox to skip breaks when macOS Do Not Disturb is on.
- **Stretchly**: `monitorDnd` polls a `defaults read` of the Focus menu-bar item (fragile; broke on Tahoe), plus process-name app exclusions. DnD end → *full schedule reset*, which is the exact complaint in #1433 (a 5-minute DnD cost the user a 55-minute countdown). No fullscreen, screen-share, or camera detection; maintainer stance is "help wanted."
- **BreakTimer**: nothing automatic; manual disable for 30 min / 1 h / 2 h / 4 h / rest of day.
- **Intermission**: markets meeting/call/presentation/screen-share detection without Accessibility or Screen Recording permissions (so likely mic/camera/process-based).

### 2.4 Postpone, snooze, skip, and strictness

- **Stretchly**: postpone once (2 min micro / 5 min long) during the first 30% of a break; after that the button becomes Skip. Strict mode removes both. "Break health" indicator grows with each skip. Manual pause presets 30 min / 1 h / 2 h / 5 h / until morning.
- **BreakTimer**: snooze 3 min (limit 1–5 or none), skip off by default, "end break early" on, and "immediately start breaks" as a pseudo-strict mode. Shows how long since the last break when the user has been snoozing.
- **Time Out**: two postpone buttons + skip, each editable; optional Mindfulness delay that disables the buttons for a few seconds; limits per break, per hour, or per day (3.0's "most popular request"); daily done/postponed/skipped counts; "Make Due In" 30 s–1 h; "End break early" replaces postpone/skip once shown.
- **LookAway**: snooze +1/+5/+15 from the heads-up; on the break screen 1 or 5 min "without it being counted as a skip"; three skip difficulties (Casual / Balanced: skip disabled for a few seconds / Hardcore: no skip); per-day and per-session limits; "advance skips" with a daily cap and a score penalty.

User evidence: Stretchly #1629 and #1036 ("I click skip subconsciously… hide it for 2 seconds"), #1492 (escalating friction on repeat postpones), #1841 (hide Skip for the first 30 s but keep Postpone); BreakTimer #259 ("only skip once or twice per day would keep me from cheating but let me skip during meetings"); HN and dev.to threads on Workrave ("the most annoying software imaginable, but saved my career" / "forceful reminders… I end up quitting the reminder entirely").

### 2.5 Break UI

- Heads-up before the break: Stretchly 10 s (mini) / 30 s (long) system notification; BreakTimer a 60 s "start when ready" grace then a 60 s countdown bar; LookAway a 1-minute notification then a 5–10 s countdown that follows the cursor, then a slow fade-in with a soft sound; Time Out fades in and optionally waits for 15 s of idle before starting (max 1 min).
- The break itself: Stretchly a 0.85-screen always-on-top non-focusable window at 0.9 opacity on every display; BreakTimer expands to full screen with a 0.7 backdrop; Time Out full-screen themed overlay with a "Blank" dim theme and per-display options; LookAway full-screen "rest mode" on all displays.
- None hard-block input by default; strictness is implemented by removing exit paths, not capturing the keyboard.
- Complaints: overlay blocks video controls (Intermission), keystrokes leak to background apps (BreakTimer #262), focus not restored afterward (Intermission), multi-monitor gaps (Stretchly #1225, BreakTimer #372), plain notifications get missed (Stand Up!, Wakeout, and Moova's move to AlarmKit full-screen alerts).

### 2.6 Micro vs long breaks, working hours, clock basis

- Micro/long: Stretchly 20 s every 10 min with a 5-min break after every 2 minis; any reset zeroes the mini counter. Time Out: breaks in priority order with *Reset after higher-priority break* and *Skip if higher-priority break due within X*. LookAway: long break every N short ones; planned breaks suppress nearby regular breaks "so two breaks never stack up." BreakTimer: single break type only.
- Working hours: BreakTimer per-day ranges, default Mon–Fri 9–6, fresh interval when hours begin; Time Out per-break availability by time range and weekday; LookAway Office Hours with overnight support. Stretchly has none (only "pause until morning").
- Clock: all four are wall-clock timestamps with a tick. Time Out's *From* option (Last Due / Last Done / Fixed Time) is the only explicit control over whether the cadence anchors to when a break was due or when it finished.

### 2.7 What users reward and punish (ranked from the review synthesis)

1. Auto-suppress during calls and screen share, with a grace period after.
2. Idle-aware timer with sensible thresholds: credit real absences, don't fire right after the user sits back down, don't reset on a 10-second lock.
3. Correct sleep/wake handling; never a frozen overlay.
4. Defer while the user is mid-input; never mid-keystroke.
5. Two-phase warning (heads-up, short countdown, slow fade).
6. Bounded snooze that doesn't count as a skip, plus per-day skip caps.
7. Friction on Skip, not on Postpone.
8. Dimming overlay that still lets you see and act; not a plain notification, not a hard block.
9. Always-visible time to next break, "take break now," and "make due in."
10. Video/reading awareness: passive video is still sitting; reading is lower urgency.

Table stakes: cover every display, don't leak keystrokes, restore focus, low power draw, reliability across macOS updates.

---

## 3. Where Movez differs from the eye-strain apps

Most of these products exist to rest eyes and wrists, so "not typing" is a reasonable proxy for "resting." Movez exists to break up sitting bouts, which changes three things:

1. **Idle at the desk is not a break.** Reading a paper, thinking, or being on a call are all sitting. Only *leaving* counts, so the idle threshold that credits a break should be tied to how long it plausibly takes to have got up, not to how long the eyes have been off the screen. That argues for keeping Time Out's "pause the countdown" behavior out of the default and instead treating short idle as sitting.
2. **A 5-minute break has content.** The break isn't a blank screen; it's a routine the user does away from the keyboard. So the overlay must be glanceable from standing distance, the routine needs a visible per-movement timer and next/previous controls, and "end early" should record which movements were completed.
3. **The metabolic benefit is in interrupting the bout, so deferral must not become cancellation.** When a meeting pushes a break by 40 minutes, the user has now sat for 95 minutes; the app should surface that (a "sitting for 1 h 35 m" badge) rather than quietly pretend the schedule held.

---

## 4. Recommendations, question by question

### 4.1 What the timer counts

Use wall-clock timestamps (`bout_started_at`, `next_full_due_at`, `next_micro_due_at`) evaluated by a 1-second tick, never accumulated counters. Idle, sleep, and suppression are explicit states that shift the due times, not a second clock. This is how all four mature apps work and it is the only model that survives sleep, clock changes, and process suspension without drift.

Anchor the cadence to *when the break finished* (Time Out's "Last Done"), not when it was due: after a 5-minute break at 10:55, the next is due 55 minutes after the break ends, so deferrals and long breaks don't compress the next sitting interval.

### 4.2 Idle: three thresholds, one policy

| Idle duration | Interpretation | Effect |
|---|---|---|
| < 3 min | Still sitting (reading, thinking, call, short video) | Countdown continues unchanged |
| 3–5 min | Probably stepped away briefly | Countdown pauses at 3 min; on return it resumes with remaining time; the absence counts as the micro-break, so the next micro is re-anchored 30 min from return |
| ≥ 5 min | Took a real break | Treated as a completed full break; on return, a fresh full interval starts and the micro schedule re-anchors |

On return, show a 6-second auto-dismissing toast, not a modal: "Away 7 min — counted as your break · *I was sitting*." One click reverses the decision (restores the paused countdown). This is LookAway's 2.3 pattern and directly addresses Stretchly #1560 and #1724.

Rationale for 3 minutes rather than Stretchly's 5 or Time Out's 1: at 1 minute, reading and calls get credited as movement (wrong for this app); at 5 minutes, a 4-minute walk to the kitchen is ignored and the user gets a break prompt on sitting down (Stretchly's top complaint). 3 minutes is long enough that the user almost certainly left the chair.

Detection: use `CGEventSource.secondsSinceLastEventType` for keyboard/mouse (no Accessibility permission needed), sampled every 2 s. Known v1 gap: watching a long video while motionless will read as "away" after 3 minutes; the reversible toast is the mitigation, and a v1.5 refinement is to treat "audio playing from a frontmost video app" as sitting (Time Out's "Ignore natural break" rule, LookAway's video detection).

### 4.3 Sleep, lock, and wake

Treat lock and sleep as idle with the same three thresholds, but measure them by wall-clock gap rather than input idle, because idle time resets on wake. Implementation: subscribe to `NSWorkspace` `willSleep` / `didWake` / `sessionDidResignActive` / `screensDidSleep` notifications *and* have the tick detect gaps > 10 s (BreakTimer's safety net, for the cases where the event never arrives).

Rules:
- On sleep or lock: dismiss any open overlay or heads-up immediately (Stretchly #1807's frozen overlay is unrecoverable for the user).
- On wake: never fire anything for the first 60 s; the user is unlocking, reading notifications, and re-orienting. Then apply the idle table above to the gap.
- If the gap ≥ 4 h, or crosses the working-hours start, reset the day (section 4.9) rather than "crediting a break."
- If the user closes the lid *during* a break and reopens within the break's original end time, resume the break where it was (Time Out 2.3 behavior); otherwise mark it done to the extent completed.

### 4.4 Meetings, screen sharing, and fullscreen (suppression)

Ship this in v1. It is the top item on the reward/punish list and the thing that makes Stretchly and BreakTimer users write "I have to remember to pause it before every call."

Signals, in order of reliability and cost:
1. **Microphone in use** by any process (CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device). This is LookAway's primary signal after they abandoned camera checks for false positives. Covers Zoom, Teams, Meet, FaceTime, Slack huddles, dictation. Allow per-app exclusions later (e.g. a music app that holds the mic).
2. **Screen being captured** (screen sharing, recording). On modern macOS the public path is checking whether a screen-capture session is active via ScreenCaptureKit / the system's "screen is being captured" indicator; fall back to LookAway's approach of a process list (Zoom share helper, OBS, QuickTime Player recording, Loom, Screenflow).
3. **Fullscreen frontmost app** (`NSWorkspace.frontmostApplication` + window bounds via the Accessibility API, or `NSApplication.presentationOptions`). Suppress by default; the user can whitelist (a fullscreen editor shouldn't suppress) — Time Out and LookAway both expose this.
4. **Calendar events** (EventKit, optional, opt-in): v1.5. Useful for calls taken on a phone, which no on-device signal catches.

Behavior while suppressed: **defer, never reset** (the Stretchly #1433 complaint). The due time stays where it was; the state machine sits in `suppressed` and re-checks every 15 s. When the signal clears, wait a 2-minute grace period (LookAway's "break delay after activity ends," default 2 min, options 1/2/5) so the user can write their follow-up notes, then run the normal pre-break sequence. A micro-break that comes due during suppression is dropped, not deferred; the next one re-anchors from the full break. If a deferred full break waits more than 30 minutes, the heads-up says so ("Sitting for 1 h 25 m · break deferred by your call") and the snooze allowance for that break is reduced to one.

### 4.5 Do Not Disturb and Focus

Do not poll for Focus state. Stretchly's `defaults read` hack broke on Tahoe, and Apple provides no supported read API. Instead ship a **Focus Filter** (App Intents `SetFocusFilterIntent`) so the user can add "Movez: pause breaks" to any Focus mode; LookAway does exactly this. Plus a manual **Pause for…** menu with 15 min / 30 min / 1 h / 2 h / rest of day, with the remaining pause shown in the menu bar and a notification when it lifts. A manual pause is a `paused` state, distinct from `suppressed`, and the countdown resumes with remaining time when it ends (again: no reset).

### 4.6 Mid-input deferral

When a break comes due, wait for a 10-second pause in keyboard and mouse input before starting the heads-up, with a hard cap of 60 seconds (Time Out uses 15 s idle / 60 s cap; LookAway uses a 10 s typing window and separately detects drags). This costs almost nothing to implement given the idle sampling already exists and removes the "it popped up mid-sentence" complaint (Intermission reviews, HN).

### 4.7 The pre-break sequence and the overlay

Two phases, both skippable:

1. **Heads-up, T−60 s.** A small non-focusable panel at the top of the active display (BreakTimer / LookAway style), also mirrored in the menu bar: "Movement break in 1:00 — Hip reset · [Start now] [+5 min]". Optional gentle sound. This is where "Start now" lives, which users request constantly.
2. **Fade-in, T−0.** Over ~3 s, dim and blur every display to ~70% and bring up the break overlay. Not input-blocking: the keyboard still reaches the overlay's own controls, and the menu-bar icon remains reachable (Stretchly #1479: strict fullscreen breaks blocked the tray so users couldn't even pause).

Overlay content for Movez: current movement name in large type, the 2–4 sentence instruction, a per-movement countdown ring, a strip showing the routine's blocks with the current one highlighted, [Next] [Previous] [Skip movement], overall time remaining, and at the bottom [Snooze 5 min] and [Skip break]. Readable from 2 m away. After the break, restore focus to the previously frontmost app (Intermission gets dinged for not doing this) and play a soft completion sound.

Micro-break UI is the heads-up panel only, with a 60-second countdown and the single movement's instruction; no dimming.

### 4.8 Snooze and skip

- **Snooze**: +5 minutes, from the heads-up or the overlay, max 2 per break; a snooze is not a skip. After the second snooze, the button disappears and only Skip remains. A snoozed break returns with the heads-up phase, not straight to the overlay.
- **Skip**: always available (no hardcore mode in v1; add a "strictness" setting later if wanted), but the button is disabled for the first 3 seconds of both the heads-up and the overlay (Time Out's Mindfulness delay; LookAway's Balanced mode; Stretchly #1036/#1629) and the daily skip count is shown on it ("Skip (2 today)"). Skipping does *not* reset the bout timer: the next break is due 55 minutes later, but the "sitting for…" badge keeps counting from the last completed break, so the cost is visible.
- **Micro-breaks**: one +5 snooze, then skip (already in the library doc).
- **End early**: from inside the overlay, [Done] appears after ≥ 50% of the routine; before that, ending is a skip. Record which movements were completed either way.
- **Take a break now** and **Make due in… (5 / 10 / 15 / 30 min)** live in the menu-bar menu.

### 4.9 Working hours and day boundaries

On by default, Mon–Fri 09:00–18:00, editable per day with multiple ranges (BreakTimer's model). Outside hours the app is in `off_hours`: menu bar shows "Off hours," nothing fires. At the start of the working day the state is reset and the first full break is due one full interval later (not "immediately because you sat for 14 hours"). Also reset the day after any gap ≥ 4 hours, regardless of the schedule, so a Saturday session still starts clean.

The first micro-break after the user's lunch (detected as an absence ≥ 20 min between 11:00 and 14:00) is prioritized CIR-heavy, per the library's post-lunch rule.

### 4.10 Micro and full break interplay

- A completed full break, or a credited absence ≥ 5 min, re-anchors the micro schedule: next micro at +30 min from the end of the break.
- A credited absence of 3–5 min re-anchors only the micro schedule.
- A micro due within 10 minutes of a full break is dropped.
- A micro due during `suppressed`, `paused`, or `pending_full` is dropped.
- A micro never defers or snoozes more than once; it's cheap, so drop rather than nag.

### 4.11 Completion accounting

A full break counts as completed if the user reached ≥ 50% of its movements or ≥ 50% of its time (BreakTimer's rule). Store per-movement completion so the routine builder's "don't repeat today" and difficulty-ramp rules work on what was actually done. Show a simple daily line in the menu: breaks done / snoozed / skipped, longest sitting bout. No streaks or scores in v1; the review evidence on gamification is mixed and it's cheap to add later.

### 4.12 Overlay hygiene and reliability (table stakes)

Cover every connected display (and handle displays being plugged in mid-break); swallow keystrokes so they don't reach the app behind (BreakTimer #262); restore the previous frontmost app; poll at 2 s, not 1 s, and stop polling entirely while paused or off-hours (Stretchly's M1 power-draw issue #1278); handle macOS updates that change window-level or Spaces behavior (Stretchly 1.22's fullscreen-window-drops-out-of-Space fix).

### 4.13 Test harness

Specify as a phase-one deliverable: a debug menu with a **time-scale factor** (1×, 10×, 60×) applied to all durations, buttons to inject each signal (idle, sleep, wake, mic on/off, screen capture on/off, fullscreen on/off), and a state-inspector panel showing the current state, every due time, and the last 20 transitions. Every competitor's sleep and idle bugs lived in the tracker for months because they take a day to reproduce.

---

## 5. State machine sketch

States: `off_hours`, `paused` (manual or Focus Filter), `sitting` (countdown running), `away` (idle ≥ 3 min, countdown paused), `suppressed` (meeting/share/fullscreen; countdown continues, firing deferred), `pending_full` (break due; waiting for input pause, then heads-up), `snoozed`, `micro_break`, `full_break`, `post_break_grace` (60 s after wake or after suppression clears).

Key transitions:
- `sitting` → `away` on idle ≥ 3 min; `away` → `sitting` on input, applying the 3–5 / ≥ 5 min rule and showing the toast.
- `sitting` → `suppressed` when any suppression signal is true; `suppressed` → `post_break_grace` (2 min) when all signals clear; grace → `pending_full` if a break was deferred, else `sitting`.
- any → `paused` on manual pause or Focus Filter; `paused` → `sitting` with remaining time when it lifts.
- `sitting` → `pending_full` at `next_full_due_at`; `pending_full` waits ≤ 60 s for a 10 s input pause, then heads-up 60 s, then `full_break`; from heads-up, `+5` → `snoozed` (max 2), `Skip` → `sitting` with new due time.
- `full_break` → `sitting` on completion, done, or skip; new due time = end + interval; micro re-anchored.
- `sitting` → `micro_break` at `next_micro_due_at` unless within 10 min of the full due time; `micro_break` → `sitting` after 60 s, snooze, or skip.
- any → dismiss overlays and → `away` on sleep/lock; on wake → `post_break_grace` (60 s), then apply gap rules; gap ≥ 4 h or crossing working-hours start → day reset.
- any → `off_hours` when outside working hours; `off_hours` → `sitting` (fresh) at start of hours.

Persist all due timestamps and the current state to disk on every transition so a crash or relaunch resumes correctly.

---

## 6. Default parameters

| Parameter | Default | Range |
|---|---|---|
| Preset | 55/5 | 25/5, 55/5, 85/5, custom |
| Micro-break | on (except 25/5), every 30 min of sitting, 60 s | off / on |
| Idle → away | 3 min | 2–10 min |
| Away → credited full break | 5 min | 5–15 min |
| Return toast | 6 s, reversible | — |
| Wake quiet period | 60 s | — |
| Day reset gap | 4 h | — |
| Suppression signals | mic, screen capture, fullscreen | each toggleable; app whitelist |
| Post-suppression grace | 2 min | 1 / 2 / 5 min |
| Mid-input wait | 10 s pause, 60 s cap | — |
| Heads-up | 60 s before | 30 / 60 / 120 s |
| Fade-in | 3 s to ~70% dim | — |
| Snooze | +5 min, max 2/break, not a skip | 1–3 |
| Skip button delay | 3 s | 0–10 s |
| Micro within X of full | dropped if < 10 min | — |
| Working hours | Mon–Fri 09:00–18:00 | per-day ranges |
| Completion threshold | 50% movements or time | — |
| Poll interval | 2 s (idle/mic/capture), 0 while paused/off-hours | — |

---

## 7. Open decisions for Kyle

1. **Idle threshold for "away" (3 min proposed).** Test against your own day: how long is a typical kitchen or washroom trip?
2. **Whether skipping should ever be blocked.** v1 proposes no hardcore mode; the evidence says hard blocks drive uninstalls, but you are also the only user for now.
3. **Calendar integration in v1 or v1.5.** It's the only signal that catches phone calls and in-person meetings, but it needs EventKit permission and a settings UI.
4. **Whether a deferred break should shrink** (e.g. serve a 3-minute routine if it was deferred past 30 minutes and the next break is close), or always run the full 5.
5. **Sound.** Heads-up chime on or off by default.

---

## 8. Sources

**Stretchly**: [README](https://github.com/hovancik/stretchly/blob/trunk/README.md) · [default settings](https://github.com/hovancik/stretchly/blob/trunk/app/utils/defaultSettings.js) · [breaksPlanner.js](https://github.com/hovancik/stretchly/blob/trunk/app/breaksPlanner.js) · [naturalBreaksManager.js](https://github.com/hovancik/stretchly/blob/trunk/app/utils/naturalBreaksManager.js) · [dndManager.js](https://github.com/hovancik/stretchly/blob/trunk/app/utils/dndManager.js) · [CHANGELOG](https://github.com/hovancik/stretchly/blob/trunk/CHANGELOG.md) · [1.22 release post](https://hovancik.net/blog/2026/07/17/stretchly-1-22-is-now-available/) · issues [#59](https://github.com/hovancik/stretchly/issues/59), [#259](https://github.com/hovancik/stretchly/issues/259), [#355](https://github.com/hovancik/stretchly/issues/355), [#516](https://github.com/hovancik/stretchly/issues/516), [#543](https://github.com/hovancik/stretchly/issues/543), [#965](https://github.com/hovancik/stretchly/issues/965), [#969](https://github.com/hovancik/stretchly/issues/969), [#1036](https://github.com/hovancik/stretchly/issues/1036), [#1120](https://github.com/hovancik/stretchly/issues/1120), [#1225](https://github.com/hovancik/stretchly/issues/1225), [#1265](https://github.com/hovancik/stretchly/issues/1265), [#1278](https://github.com/hovancik/stretchly/issues/1278), [#1369](https://github.com/hovancik/stretchly/issues/1369), [#1433](https://github.com/hovancik/stretchly/issues/1433), [#1462](https://github.com/hovancik/stretchly/issues/1462), [#1479](https://github.com/hovancik/stretchly/issues/1479), [#1492](https://github.com/hovancik/stretchly/issues/1492), [#1560](https://github.com/hovancik/stretchly/issues/1560), [#1629](https://github.com/hovancik/stretchly/issues/1629), [#1687](https://github.com/hovancik/stretchly/issues/1687), [#1724](https://github.com/hovancik/stretchly/issues/1724), [#1807](https://github.com/hovancik/stretchly/issues/1807), [#1820](https://github.com/hovancik/stretchly/issues/1820), [#1838](https://github.com/hovancik/stretchly/issues/1838), [#1841](https://github.com/hovancik/stretchly/issues/1841) · [Neat Net Tricks review](https://www.neatnettricks.com/stretchly-review/) · [AlternativeTo](https://alternativeto.net/software/stretchly/about/)

**BreakTimer**: [README](https://github.com/tom-james-watson/breaktimer-app) · [settings.ts](https://github.com/tom-james-watson/breaktimer-app/blob/master/app/types/settings.ts) · [breaks.ts](https://github.com/tom-james-watson/breaktimer-app/blob/master/app/main/lib/breaks.ts) · [windows.ts](https://github.com/tom-james-watson/breaktimer-app/blob/master/app/main/lib/windows.ts) · [releases](https://github.com/tom-james-watson/breaktimer-app/releases) · issues [#11](https://github.com/tom-james-watson/breaktimer-app/issues/11), [#53](https://github.com/tom-james-watson/breaktimer-app/issues/53), [#206](https://github.com/tom-james-watson/breaktimer-app/issues/206), [#259](https://github.com/tom-james-watson/breaktimer-app/issues/259), [#262](https://github.com/tom-james-watson/breaktimer-app/issues/262), [#362](https://github.com/tom-james-watson/breaktimer-app/issues/362), [#372](https://github.com/tom-james-watson/breaktimer-app/issues/372), [#384](https://github.com/tom-james-watson/breaktimer-app/issues/384), [#396](https://github.com/tom-james-watson/breaktimer-app/issues/396), [#423](https://github.com/tom-james-watson/breaktimer-app/issues/423), [#463](https://github.com/tom-james-watson/breaktimer-app/issues/463)

**Time Out**: [help: schedule](https://dejal.com/help/timeout/en/schedule.html) · [help: advanced](https://dejal.com/help/timeout/en/advanced.html) · [help: rules](https://dejal.com/help/timeout/en/rules.html) · [help: appearance](https://dejal.com/help/timeout/en/appearance.html) · [help: action](https://dejal.com/help/timeout/en/action.html) · [natural breaks blog](https://dejal.com/blog/time-out-natural-breaks/) · [Accessibility for idle detection](https://dejal.com/blog/adding-time-out-to-accessibility-system-settings-to-enable-idle-detection/) · [postpone times FAQ](https://dejal.com/blog/can-i-adjust-the-postpone-times-in-time-out/) · [camera-in-use script](https://dejal.com/blog/how-can-i-detect-when-the-camera-is-in-use-for-time-out/) · [3.0 release](https://dejal.com/timeout/version/3.0/) · [3.1 Make Due In](https://dejal.com/blog/another-testflight-of-time-out-version-3-1-now-with-option-menu-and-make-due-in-options/) · [release notes 2.0–3.0](https://www.dejal.com/timeout/release/?from=3010&to=2040&mode=normal) · [App Store](https://apps.apple.com/us/app/time-out-break-reminders/id402592703?mt=12) · [App Store reviews](https://apps.apple.com/us/app/time-out-break-reminders/id402592703?mt=12&see-all=reviews&platform=mac) · [AlternativeTo](https://alternativeto.net/software/time-out/about)

**LookAway**: [docs index](https://lookaway.com/docs/introduction/) · [setting up / presets](https://lookaway.com/docs/setting-up) · [high-engagement (Smart Pause)](https://lookaway.com/docs/high-engagement) · [focus filters](https://lookaway.com/docs/focus-filters) · [planned breaks](https://lookaway.com/docs/planned-breaks) · [scheduling](https://lookaway.com/docs/scheduling) · [how I made break reminders less annoying](https://lookaway.com/blog/2025/04/07/how-i-made-break-reminders-less-annoying/) · [2.2 planned breaks](https://lookaway.com/blog/2026/06/22/lookaway-22-introducing-planned-breaks/) · [2.3 quieter, smarter](https://lookaway.com/blog/2026/07/22/lookaway-23-quieter-smarter-and-more-flexible/) · [1.12 notes](https://alternativeto.net/news/2025/4/lookaway-1-12-adds-app-exclusions-from-meeting-detection-smarter-drag-handling-and-more) · [1.13 notes](https://alternativeto.net/news/2025/6/lookaway-1-13-adds-apple-calendar-sync-smarter-break-reminders-and-redesigned-settings) · [best break apps 2026 (LookAway blog)](https://lookaway.com/blog/2026/04/24/best-break-reminder-apps-for-mac-in-2026/) · [App Store](https://apps.apple.com/us/app/lookaway-break-reminder/id6747192301?mt=12) · [Product Hunt reviews](https://www.producthunt.com/products/lookaway/reviews) · [HN thread](https://news.ycombinator.com/item?id=48659483) · [HN thread](https://news.ycombinator.com/item?id=37927174)

**Workrave**: issues [#168](https://github.com/rcaelers/workrave/issues/168), [#255](https://github.com/rcaelers/workrave/issues/255), [#329](https://github.com/rcaelers/workrave/issues/329), [#339](https://github.com/rcaelers/workrave/issues/339), [#369](https://github.com/rcaelers/workrave/issues/369), [#567](https://github.com/rcaelers/workrave/issues/567), [#640](https://github.com/rcaelers/workrave/issues/640), [#722](https://github.com/rcaelers/workrave/issues/722) · HN [4480993](https://news.ycombinator.com/item?id=4480993), [42570799](https://news.ycombinator.com/item?id=42570799), [7145264](https://news.ycombinator.com/item?id=7145264), [22780478](https://news.ycombinator.com/item?id=22780478)

**Intermission / Rest Time / Awareness / Wakeout / Stand Up! / EyeLeo**: [Intermission App Store](https://apps.apple.com/us/app/intermission-breaks-for-eyes/id1439431081?mt=12) · [Intermission reviews](https://apps.apple.com/us/app/intermission-breaks-for-eyes/id1439431081?mt=12&see-all=reviews&platform=mac) · [Intermission FAQ](https://tryintermission.com/faq.html) · [Rest Time](https://www.publicspace.net/RestTime/index.html) · [Awareness](https://iamfutureproof.com/tools/awareness/) · [Awareness Timer App Store](https://apps.apple.com/us/app/awareness-timer/id1497695227?mt=12) · [Wakeout Mac](https://wakeout.app/movement-reminder-app) · [Wakeout reviews](https://justuseapp.com/en/app/1242116567/wakeout-active-breaks/reviews) · [Stand Up! reviews](https://apps.apple.com/us/app/stand-up-the-work-break-timer/id828244687?see-all=reviews) · [EyeLeo AlternativeTo](https://alternativeto.net/software/eyeleo/about) · [Breaks For Eyes / 3 Mac apps (Medium)](https://medium.com/breaks-for-eyes/these-3-simple-mac-apps-will-help-you-take-breaks-and-get-rid-of-eye-strain-7d99e98a8719) · [No break reminder works for me (dev.to)](https://dev.to/allanchain/no-break-reminder-works-for-me-1n8o) · [The best breaktimer app (Medium)](https://dsavir-h.medium.com/the-best-breaktimer-app-74bca81a15cd)

**Moova**: [App Store](https://apps.apple.com/us/app/moova-movement-break-reminder/id1518522560) · [App Store reviews](https://apps.apple.com/us/app/moova-movement-break-reminder/id1518522560?see-all=reviews&platform=ipad) · [getmoova.app](https://getmoova.app/) · [compare](https://getmoova.app/compare) · [FAQ](https://getmoova.app/faq) · [Google Play](https://play.google.com/store/apps/details?id=app.stretchminder.android&hl=en_US) · [Deskletics on StretchMinder](https://deskletics.app/alternatives/stretchminder/) · [Cult of Mac deal](https://www.cultofmac.com/deals/moova-break-timer-app-deal) · [JustUseApp reviews](https://justuseapp.com/en/app/1518522560/moova-movement-break-reminder/reviews)
