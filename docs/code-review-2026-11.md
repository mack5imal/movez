# Code review: movez, November 2026

Reviewed at `3f69dd2` on `relay/add-a-strength-mode-to-movez-alongside-t-DWCNKz`, 2026-11-16.
Scope: everything in `Sources/movez/`, `Tests/movezTests/`, `scripts/`, `project.yml` and the
`Makefile`. Out of scope: `build/`, `.relay/`, `design/` and the generated `movez.xcodeproj`.

**How it was done.** Eleven reviewers each read one area in full, together with `CLAUDE.md` and
`docs/DECISIONS.md`. The areas were Scheduler; App and its neighbours; Signals; Library, Routine
and Modes; Strength; three UI slices; two test slices; and scripts plus build. A separate verifier
then went over each area's findings and tried to refute every one against the code and the decision
log. Of 126 raw findings:
- 3 were refuted and dropped.
- The rest were confirmed, or confirmed with a corrected line, mechanism or severity.
- Problems found by more than one area were merged.

That leaves **100 distinct findings: 6 high, 24 medium, 70 low**. Behaviour that matches a
DECISIONS entry was treated as intended. Findings are filed by the file they live in, not by the
reviewer who found them. No code was changed.

Severity:
- **High:** wrong behaviour a user will hit in normal use, or data loss.
- **Medium:** a real bug on a less common path, or a risky gap.
- **Low:** dead code, duplication, needless complexity, weak tests, or a minor bug.

## How the code is put together

**One pure decider, one impure applier.** `Scheduler` (`Sources/movez/Scheduler/`) is a value
type made of a `SchedulerSnapshot` and a `SchedulerConfig`. Its whole job is
`handle(_ event:, now:) -> [SchedulerEffect]`:
- It never reads the clock, never sets a timer and never does I/O. Time arrives as `now`, and
  everything it wants done goes out as an effect.
- The event handlers are split across `Scheduler+Actions/+Idle/+Sleep/+Pause/+Hours/+Suppression`.
- The snapshot is the whole persisted state. It holds the `SchedulerState` enum (sitting, heads-up,
  pending, full break, micro, paused, suppressed, away, grace, off hours…). It also holds side
  fields: `boutStartedAt`, the next full and micro due times, the "drawers" that keep a countdown
  through a pause or an absence, a deferral, and an interrupted break.

That purity is why the test harness can replay a whole working day in milliseconds on a
`ManualClock`.

**`AppCoordinator`** (`App/`, `@MainActor`) is the only thing that talks to the scheduler. It:
- sends `.tick` every 2 s;
- turns each `SignalAggregator` poll into `.input`, `.idle` and `.signals`;
- forwards `PowerMonitor`'s sleep, wake, lock and unlock;
- routes every user intent from the menu, overlay, panels and Settings in as an event.

`deliver()` applies each returned effect twice. First the coordinator applies it to its own state:
it builds the break (through `ModeBuilderTable`), keeps a `BreakSession`, writes `BreakRecord`s
and `MovementCompletion`s to `HistoryStore`, and persists `state.json`. Then it hands the effect to
the `EffectSink`s (overlay, panels, menu bar, chimes), which own all the AppKit. Settings live in
`SettingsStore` (UserDefaults). Each edit sends the whole config back in as `.settingsChanged`.

**Signals** (`Signals/`) are small protocol-backed adapters:
- idle: `CGEventSource`;
- microphone: CoreAudio "is running somewhere";
- screen capture: bundle ids and process names against `capture-signatures.json`;
- fullscreen: CGWindowList bounds against `NSScreen` frames;
- power: NSWorkspace notifications.

`SignalAggregator` polls them only while `Scheduler.pollingRequired`, holds the mic to 60 s of
sustained use, and synthesises a `.gapDetected` wake when polls are more than 10 s apart.

**Content** comes in two modes, which meet only in `Modes/`.
- *Movement mode:* `LibraryLoader` validates `movement-library-v4.json`. `RoutineBuilder` draws a
  five-block routine (and `MicroBreakBuilder` a micro-break) from a seeded SplitMix64. The draw is
  weighted by a three-day recency memory and filtered by `RoutineContext`.
- *Strength mode:* `StrengthDayPlanner` replays the day's history to decide the next slot (A/B day,
  pattern, core or arm sets, or end-range once the quota is met). `StrengthBreakBuilder`,
  `EndRangeBreakBuilder` and `StrengthMicroBuilder` then draw through a ladder that relaxes rules
  one rung at a time and takes them back where the pool allows.
- Both modes produce a `PlannedBreak` or `PlannedMicro`, so the coordinator and UI read parts and
  seconds without branching on the mode.

**UI** (`UI/`):
- `OverlayEffectSink` puts one borderless non-activating panel on every screen. They are bound to
  `OverlayViewModel` (Movement) or `StrengthOverlayViewModel` (a `StrengthSessionTimeline`).
- The overlay view models own block progression on a 1 Hz tick and report back through closures
  that call coordinator intents.
- Panels (heads-up, micro, toast), the `MenuBarExtra` and the Settings window are thin view models
  over the coordinator.
- `UI/Debug/SnapshotRenderer` renders every surface offscreen from `SnapshotFixtures`. That is how
  UI changes are reviewed.

**Where it is weakest.** The architecture is sound and well tested. Most of the serious bugs share
one shape: **the same fact is stored in two places and the copies drift apart.**
- `apply()` re-plans the due time from `boutStartedAt`, but skip, pause-resume and wake set the
  due time directly without moving the bout (SCH-1).
- A deferral lives both in `.suppressed(deferredFullDue:)` and in `snapshot.deferredFullDueAt`
  (SCH-2).
- The scheduler settles a slept-through break, but the coordinator owns history and is never told
  (SCH-3).
- The overlay rebuilt after a wake doesn't receive the block index the session kept (UI-1).

The second theme is **display sleep during a break**. The user is meant to step away from the
keyboard, nothing holds the display awake, and display sleep is treated like closing the lid
(UI-2, SIG-3).

Use the `SCH-n`, `APP-n`, `SIG-n`, `LIB-n`, `UI-n` and `TST-n` ids below to refer to findings.

## 1. Scheduler

### SCH-1 · high · A settings change re-plans from the bout start, which re-serves a skipped or paused break and fires a second micro-break

**Where:** `Sources/movez/Scheduler/Scheduler.swift:257` · **Category:** correctness · **DECISIONS checked:** 24, 48 (skip keeps the bout), memory: defer-never-reset

*Found independently by the App + History + Notice + Settings + FocusFilter + Audio, UI: MenuBar + Settings reviews as well.*

**What goes wrong.** `apply(_:now:)` handles every `.settingsChanged`. That covers almost every toggle in Settings, via `SettingsViewModel.changed()`, plus the dropdown's mode switch. It recomputes `nextFullDueAt = boutStartedAt + sitSeconds` and `nextMicroDueAt = microDue(anchoredAt: microAnchorAt ?? boutStartedAt)`. That only works if `boutStartedAt` is where the current countdown was planned from, and three paths deliberately break that link:

(1) **Skip.** `skip()` / `rescheduleAfterSkip` (Scheduler+Actions.swift:163) sets `nextFullDueAt = now + sit` but leaves `boutStartedAt` alone on purpose (line 114 comment; DECISIONS 48). Example: bout 09:00, skip at 09:56, so the next break is due 10:51. At 10:00 the user excludes a movement or switches mode. `apply` sets the due time to 09:55, the next tick sees it is past, and the heads-up comes straight back. `setBreakLength`'s own comment (line 269) admits that `apply` "would undo a skip's fresh interval".

(2) **Manual pause.** `endPauseBookkeeping` (Scheduler+Pause.swift:74) sets `nextFullDueAt = now + remaining` and never moves `boutStartedAt`. Any setting changed after a one-hour pause therefore brings the break due an hour early, often at once.

(3) **Micro-breaks.** `closeMicroCycle` sets `microAnchorAt = nil` (Scheduler+Actions.swift:261), so `apply` falls back to the bout start. On the default 55/5 the 09:30 micro-break closes, and a settings change at 09:35 gives `microDue(09:00) = 09:30`. That is 25 minutes before the full break, so it passes the quiet-zone check, and a second micro-break count-in starts at 09:35. The same applies after a micro skip, and after a micro snooze it cuts the snooze short.

The settle-as-skip branch of `resumeInterruptedBreak` (Scheduler+Sleep.swift:138) also breaks the link in the same way. The away-pause and launch-shift paths move `boutStartedAt` specifically to keep `apply` honest (Scheduler+Idle.swift:134, Scheduler+Sleep.swift:189), but these three paths do not. SettingsLiveUpdateTests only checks `boutStartedAt` and a mid-bout preset change; nothing changes a setting after a skip, a pause or a micro-break.

**Suggested fix.** Re-plan by the change in the setting instead of from a different anchor. Before assigning `config = updated`, set `nextFullDueAt += updated.sitSeconds - config.sitSeconds`, and re-plan the micro-break only if `microEnabled`/`microEverySeconds` actually changed. Alternatively, persist an explicit `intervalStartedAt` that skip, pause-resume and settle update, and re-plan from that. Add tests that change a setting after a skip, after a manual pause and after a micro-break, and assert that neither due time moves earlier.

<details><summary>Verification (confirmed)</summary>

Traced: apply() sets nextFullDueAt = boutStartedAt + sitSeconds whenever countdownRuns. skip()/rescheduleAfterSkip (Actions:163-172) set nextFullDueAt = now+sit and never touch boutStartedAt; endPauseBookkeeping (Pause:73-80) sets nextFullDueAt = now+remaining without moving boutStartedAt; closeMicroCycle sets microAnchorAt=nil so apply falls back to boutStartedAt (55/5: microDue(09:00)=09:30, full 09:55, 25 min gap passes the 600 s quiet check, tickSitting fires a count-in). settingsChanged is sent by SettingsViewModel.changed() via AppDelegate onChange, by MenuBarViewModel.selectMode and by DebugViewModel.setTimeScale. setBreakLength's own comment (Scheduler.swift:269-270) and AppCoordinator.swift:401 acknowledge that apply undoes a skip. SchedulerInterruptionTests:103 only covers the away-pause path (which moves boutStartedAt), not a manual pause, a skip or a closed micro cycle. DECISIONS 24 intends re-planning from the bout so that time already sat is kept, not so that a skip is undone; DECISIONS 48 keeps the bout on a skip, which is exactly what makes the anchor wrong.

</details>

### SCH-2 · high · An absence after a deferred break leaves `deferredFullDueAt` behind: the next break is mislabelled and a later call triggers an early break

**Where:** `Sources/movez/Scheduler/Scheduler+Idle.swift:127` · **Category:** correctness · **DECISIONS checked:** 8, 20, 43

**What goes wrong.** `deferredFullDueAt` is the snapshot's note that a break came due during a call. Only `enterFullBreak`, `rescheduleAfterSkip` and `startFreshSession` clear it. The reset path of a returning absence (`returnFromAway`, then `resetCountdowns`, then `startFreshInterval`) clears neither it nor `deferredReason`.

A common sequence: a break comes due during a call (deferred at 09:55). The call ends, and the user walks off before the break starts: idle in `.pendingFull` or `.headsUp`, or the lid closes during the 2-minute grace. They return at 10:30, and the countdown resets to 11:25 as DECISIONS 43 says. But the stale 09:55 deferral is still there, and it does two things:
(1) At 11:25 `enterHeadsUp` reads `deferredSince ?? snapshot.deferredFullDueAt` (Scheduler+Actions.swift:15). Ninety minutes is more than 30, so the brand-new break gets the "waited for your call" badge and `snoozeAllowanceThisBreak = 1`.
(2) Any call before 11:25 copies the stale value forward (`deferred ?? snapshot.deferredFullDueAt`, Scheduler+Suppression.swift:33). When that call ends, `resumeAfterSuppression` (line 47) sees a non-nil value and goes to `pendingFull`, so a break fires 30 minutes early.

The root cause is the duplicated fact: `.suppressed(deferredFullDue:)` holds the truth for this call, but `resumeAfterSuppression` reads the snapshot copy instead.

**Suggested fix.** Clear `deferredFullDueAt` and `deferredReason` in `startFreshInterval` (any fresh interval owes nothing), or at least in `resetCountdowns`. Have `resumeAfterSuppression` use the deferral carried by the state it is leaving, or require `nextFullDueAt <= now`. Add a test: a call defers the break, the user goes idle, returns, then has a short call; assert no early `pendingFull` and no deferred badge.

<details><summary>Verification (confirmed)</summary>

Traced. tickSuppressed sets snapshot.deferredFullDueAt. Only enterFullBreak, rescheduleAfterSkip and startFreshSession clear it; resetCountdowns→startFreshInterval (Scheduler.swift:215-224) clears neither it nor deferredReason. A realistic path: the call ends, the 2-minute grace runs (not idle-interruptible), resumeAfterSuppression goes to pendingFull, and the next poll's .input (age ≥10) raises the heads-up. The same poll's .idle (≥180 s from talking without typing) then sends headsUp to away. A lid close during the grace (handleSleepOrLock default branch) also reaches away. A 3–54 minute return takes the reset path. Afterwards enterHeadsUp (Actions:15) uses the stale deferral (badge plus snoozeAllowance=1 once more than 30 min old). beginSuppression from .sitting keeps it (`deferred ?? snapshot.deferredFullDueAt`, Suppression:33), and resumeAfterSuppression (Suppression:47) checks only the snapshot copy, so it enters pendingFull although nextFullDueAt is in the future. No DECISIONS entry sanctions an early break.

</details>

### SCH-3 · high · A break the lid or display sleep interrupted is settled without telling the coordinator, so it never reaches history

**Where:** `Sources/movez/Scheduler/Scheduler+Sleep.swift:141` · **Category:** persistence · **DECISIONS checked:** 20, 22, 23c, 38, 59

*Found independently by the App + History + Notice + Settings + FocusFilter + Audio, Strength reviews as well.*

**What goes wrong.** When a lid close or display sleep interrupts a full break and the user returns after its planned end, resumeInterruptedBreak settles it by the completion rule. It only bumps doneToday or skipsToday and emits no .endFullBreak or record effect. The coordinator holds the BreakSession in interruptedSession and drops it in deliver() once interruptedBreak is nil, so neither a done nor a skipped BreakRecord reaches history. Today, the streak and StrengthDayPlanner never see the break, and the next strength break repeats the slot. In the same path, the skip branch does not reset the per-break snooze allowance (two snoozes, then an interrupted break that ends as a skip, leaves the next break with 0 snoozes). The resume-or-settle comparison also uses `now`, which differs between the input-first and wake-first return paths. The standby discard of an interrupted break is deliberate (startFreshSession comment, testStandbyDiscardsABreakTheLidClosedOn), though whether a break that already counted should be lost there is worth deciding explicitly.

**Suggested fix.** Emit a settle effect, either .endFullBreak(.completed/.skipped) or a dedicated .settleInterruptedBreak(outcome), that the coordinator records from interruptedSession before it is dropped. Route the skip branch through rescheduleAfterSkip. Compare returnedAt rather than now against plannedEnd. Add a CoordinatorHarness test asserting a .done BreakRecord after a slept-through break. Optionally decide (and record in DECISIONS) whether standby should still credit an interrupted break that already met the completion rule.

<details><summary>Verification (confirmed with corrections)</summary>

Core claim holds. The settle branch of resumeInterruptedBreak returns only [.persist, .menuRefresh]. The coordinator's .interrupted case only stashes interruptedSession (AppCoordinator+Effects.swift:160-164), and deliver() drops it once interruptedBreak is nil (AppCoordinator.swift:353), so no BreakRecord is ever written. HistoryStore streak and StrengthDayPlanner:229 read countsAsCompleted from history. No IOPMAssertion exists in Sources. StrengthCoordinatorTests:139 checks only that the session is dropped, not that history is written. (b) holds: lines 137-139 do not reset snoozesUsedThisBreak, snoozeAllowanceThisBreak or microAnchorAt, unlike rescheduleAfterSkip. (c) holds: input-first calls endAbsence(now: returnedAt), while wake-first calls it at the end of the grace minute, and input during the grace is ignored. Sub-claim (a) is deliberate: startFreshSession's comment says interrupted breaks are moot once the session ends, and AwayReturnTests.testStandbyDiscardsABreakTheLidClosedOn asserts it. Discarding a break that already met the completion rule is a design question, not a defect.

</details>

### SCH-4 · medium · Ad-hoc sessions: midnight takes down a running break without recording it, and the four-hour-gap end in DECISIONS 16 is missing

**Where:** `Sources/movez/Scheduler/Scheduler+Hours.swift:10` · **Category:** correctness · **DECISIONS checked:** 16, 20a

**What goes wrong.** Two problems with ad-hoc sessions. (1) At midnight, endAdHocSessionIfStale runs before the exemption that lets a running break finish, so a break on screen at 23:59 in an ad-hoc session is taken down via .endFullBreak(.interrupted) with no InterruptedBreak stored, and the coordinator drops it without writing history. (2) DECISIONS 16's four-hour-gap ending is not implemented: standby, resetDay and the launch gap never clear adHocSession, so a weekend session survives a long lid-closed gap and keeps serving breaks. The session continuing through the normal working-hours close is consistent with DECISIONS 16 and is not a defect.

**Suggested fix.** Let a running .fullBreak (and arguably .paused) finish before ending a stale ad-hoc session at midnight. End the ad-hoc session in enterStandby/applyLaunchGap when the gap is at least 4 h, or amend DECISIONS 16 if that clause is no longer wanted. Add tests for both.

<details><summary>Verification (confirmed with corrections)</summary>

Midnight: with adHocSession set, applyWorkingHours returns endAdHocSessionIfStale before the .paused/.fullBreak exemption. enterOffHours then calls dismissSurfaces and emits .endFullBreak(.interrupted) without storing an InterruptedBreak, and the coordinator stashes the session and then drops it in deliver() (AppCoordinator.swift:353), so nothing is recorded. Four-hour gap: a grep finds no such logic (FakeSignals' simulateFourHourGap is only a debug injector). enterStandby, resetDay and applyLaunchGap never clear adHocSession, contrary to DECISIONS 16. However, the sub-claim that a session started at 07:30 'ignores the 18:00 close' is not a bug: DECISIONS 16 lists only End session, midnight and the four-hour gap as the ways an ad-hoc session ends.

</details>

### SCH-5 · medium · A Focus pause that starts off hours, or runs past the start of a working day, resumes with yesterday's bout and countdown

**Where:** `Sources/movez/Scheduler/Scheduler+Pause.swift:74` · **Category:** correctness · **DECISIONS checked:** 23c, 26, 51

**What goes wrong.** `pause()` refuses only during a full break, so `.focusFilter(paused: true)` turns `.offHours` into `.paused(until: nil)`. It also stores `remainingAtPauseSeconds` worked out from the stale due time `enterOffHours` left behind, usually 0. While paused, `applyWorkingHours` returns early (Scheduler+Hours.swift:17), so `openWorkingDay` never gives the day its fresh session.

Example: a Sleep or Personal Focus with "Pause breaks" on runs 22:00 to 09:30, with working hours 9–18. At 09:30 the Focus ends, and `resumeFromPause` sets `nextFullDueAt = now + 0` with `boutStartedAt` still at yesterday afternoon. The heads-up appears the moment the Focus ends. Its `sittingSeconds` and the next `recordBout` (written to history as the day's longest bout) measure about 16 hours. The same happens for any Focus pause left on overnight.

A resume that lands off hours recovers on the next tick, but one that lands in working hours does not. DECISIONS 23c says the opening of a working day starts things over, and this path skips that.

**Suggested fix.** In `resumeFromPause`/`endPauseBookkeeping`:
- If the pause began off hours, or `crossedWorkingDayOpening` holds for the pause's length, start a fresh session (as `openWorkingDay` does) instead of handing back `remainingAtPauseSeconds`.
- When resuming outside working hours, go straight to `.offHours`.
- Also move `boutStartedAt` forward by the pause length on resume, as `pauseCountdowns` does; that also closes part of the previous finding.

Add a test that turns a Focus on off hours and off inside working hours.

<details><summary>Verification (confirmed)</summary>

pause() refuses only .fullBreak, so .focusFilter(paused:true) from .offHours stores remainingAtPauseSeconds from the stale due time (enterOffHours leaves nextFullDueAt alone), usually 0. applyWorkingHours returns [] for .paused (Hours:17-19), so openWorkingDay never runs. resumeFromPause→endPauseBookkeeping sets nextFullDueAt = now + 0, does not move boutStartedAt, and goes to .sitting. The next tick inside hours rolls the day counters but leaves the bout, then fires pendingFull. The Focus intent calls AppCoordinator.focusFilter directly (MovezFocusFilterIntent.swift:37) whatever the state. It is reachable once a user enables 'Pause breaks' on a Focus (DECISIONS 51 keeps it off by default).

</details>

### SCH-6 · medium · A wake or tick gap with nothing away skips the sleep path's bookkeeping, and at the 60× debug scale the scheduler never leaves the quiet minute

**Where:** `Sources/movez/Scheduler/Scheduler+Sleep.swift:77` · **Category:** macos-edge · **DECISIONS checked:** 19a, 23b, 43

**What goes wrong.** `handleWake` has three branches.

**Default branch (79-84).** When nothing was away, a gap over 10 s goes straight into the wake quiet minute. Unlike `handleSleepOrLock` (lines 39-45), it never calls `dismissSurfaces` or `captureCountdowns`:
- In `.fullBreak`, `.headsUp` or a micro state, the surface stays on screen while the scheduler moves to grace and then sitting. `finishBreak`/`skip` guard on `.fullBreak`, so an orphaned overlay at shielding level refuses Done and Skip.
- In pause-away mode, a gap past the threshold reaches `pauseCountdowns` with `remainingAtAwaySeconds == nil`. `boutStartedAt` moves forward but `nextFullDueAt` does not, and the micro-break is dropped. If `pause()` was entered from `.away`, it reads stale markers instead, because `pause()` never calls `clearAwayMarkers`.

**Grace branch (77-78).** It ignores `fromTickGap`, so every App Nap gap pushes the quiet minute further out.

**Concrete trigger: the 60× option in `DebugState.timeScales`.** The aggregator polls every 0.25 s real time, which is 15 s on the scaled clock, more than the 10 s `tickGapThresholdSeconds`. So every poll dispatches `.gapDetected(15)`. The first one puts a sitting scheduler into grace, and every later one extends it. The menu reads "Away" for good (19a), no break ever fires, and "Take a break now" leaves an orphaned overlay on the next poll. This breaks the debug clock the DebugViewModel describes as the way to reproduce sleep bugs in a minute.

**Suggested fix.** - Honour `fromTickGap` in the grace branch, and decide explicitly what a tick gap means outside `.away`; ignoring it is probably right.
- In the default branch, run the same prelude as `handleSleepOrLock`: `dismissSurfaces`, then `captureCountdowns(at: reportedStart)`, then `awayInputAge = nil`.
- Call `clearAwayMarkers()` in `pause()`.
- In SignalAggregator, measure tick gaps in real (unscaled) time.
- Add scheduler tests for `.gapDetected` from `.sitting` and `.fullBreak`.

<details><summary>Verification (confirmed)</summary>

The default branch (79-84) calls enterAbsenceGrace without dismissSurfaces or captureCountdowns, and the grace branch (77-78) ignores fromTickGap. At 60×, pollInterval = max(0.25, 2/60) = 0.25 s real, which is 15 s on the scaled SystemClock. detectTickGap uses that clock, gap 15 > 10, and the coalesce window (5 s) has passed, so every poll dispatches .gapDetected(15). The first moves sitting into grace; each later one re-enters grace with until = now+60, so the grace never ends. DebugState.timeScales includes 60, and the debug panel is not #if DEBUG gated. pause() never calls clearAwayMarkers (Pause:10-27). Nothing opts out of App Nap (no beginActivity), so real tick gaps outside .away are possible as well.

</details>

### SCH-7 · medium · A call, share or fullscreen app that comes back during the 2-minute post-call grace is ignored, so the heads-up chimes in the call

**Where:** `Sources/movez/Scheduler/Scheduler+Suppression.swift:25` · **Category:** correctness · **DECISIONS checked:** 20, 23h

**What goes wrong.** `beginSuppression` acts only from `.sitting`, `.pendingFull`, `.snoozed` and `.headsUp`. `.postBreakGrace(_, .afterSuppression)` falls into `default` and returns []. So a signal that returns inside the grace is dropped: a back-to-back meeting, a call rejoined, or the presenter leaving Keynote fullscreen for a moment and going back.

When the grace ends with a deferral owed, `resumeAfterSuppression` enters `.pendingFull` although the call is live. The aggregator dispatches `.input` before `.signals` in each poll (SignalAggregator.swift:107-109). On the next poll, if the user has not typed for 10 s (normal when talking or presenting), `handleInput` raises the heads-up with `.chime(.headsUp)`, and only then does `.signals` take it down again. If they have also been hands-off for the away threshold, the same poll's `.idle` turns the call into an absence (`.headsUp` can be interrupted by idle, and away ignores signals). That reset then leaves the stale deferral from the previous finding.

The first minute of a call is unsuppressed by design (23h), but this is an already-recognised call being dropped.

**Suggested fix.** Add `case .postBreakGrace(_, .afterSuppression): deferred = snapshot.deferredFullDueAt` (or keep the grace's own deferral) so the scheduler goes straight back to `.suppressed`. In the aggregator, dispatch `.signals` before `.input`/`.idle`, so that one poll cannot raise a heads-up that its own signal reading would have suppressed. Add a test where the signal returns at grace + 60 s with a deferred break.

<details><summary>Verification (confirmed)</summary>

beginSuppression's switch covers only .sitting, .pendingFull/.snoozed and .headsUp, and .postBreakGrace(_, .afterSuppression) falls into default and returns []. The grace runs 120 s (postSuppressionGraceSeconds), and a screen share or fullscreen app suppresses from its first reading, so it can return inside the grace. At the end of the grace, resumeAfterSuppression enters pendingFull while the signal is live. SignalAggregator.poll dispatches .input, then .idle, then .signals (lines 107-109), so handleInput raises the heads-up with a chime before the same poll's .signals suppresses it. DECISIONS 23h covers only the mic's first minute, not an already-recognised signal.

</details>

### SCH-8 · medium · A snoozed micro-break's anchor survives a pause or a call, so a later micro-break fires again two seconds after it closes

**Where:** `Sources/movez/Scheduler/Scheduler+Suppression.swift:67` · **Category:** correctness · **DECISIONS checked:** 9, 10, 30

**What goes wrong.** `microAnchorAt` and `microSnoozeUsed` are meant to live for one micro cycle: count-in, snooze, return. The micro handlers clear them in `closeMicroCycle`, and `dismissSurfaces` does too. But two other paths re-plan a snoozed micro-break without clearing them: `tickSuppressed` ("a micro-break during a call is simply not worth having", line 67) and `endPauseBookkeeping` (Scheduler+Pause.swift:76).

`enterMicroCountIn` then keeps the old anchor (`if microAnchorAt == nil`, Scheduler+Actions.swift:177). The next micro-break's Snooze is treated as a second snooze, so it skips. Whichever way that micro-break closes, `closeMicroCycle` plans the next one from the old anchor. `microDue` (Scheduler.swift:228-234) never checks that its candidate is in the future.

Example on 85/5: bout 09:00, full break due 10:25. The 09:30 micro-break is snoozed, and a call from 09:34 to 09:50 re-plans it to 10:05. It runs at 10:05 and ends at 10:06:40. `closeMicroCycle` then computes `microDue(09:30) = 10:00`, and the next tick starts another count-in at 10:06:42. This needs a sit interval of about 85 minutes or more: the 85/5 preset or a long custom one.

**Suggested fix.** Wherever `nextMicroDueAt` is re-planned outside the micro handlers, also clear `microAnchorAt` and `microSnoozeUsed`; a small `abandonMicroCycle(now:)` helper would do it. Make `microDue` step a past candidate forward (or anchor to `now`), so it can never return a time already behind the clock. Add an 85/5 test: snooze, then a call, then the next micro ends, and assert no immediate count-in.

<details><summary>Verification (confirmed)</summary>

Traced the 85/5 example. snoozeMicro keeps microAnchorAt (09:30) and sets microSnoozeUsed. tickSuppressed re-plans nextMicroDueAt = microDue(now) without clearing either, and endPauseBookkeeping does the same. enterMicroCountIn keeps the existing anchor (Actions:177). closeMicroCycle computes microDue(09:30) = 10:00, which is 25 min before 10:25 and so passes the quiet zone. microDue never checks candidate > now, so the next tick at 10:06:42 starts another count-in. The second micro-break's Snooze also turns into a skip. On 55/5 the re-planned micro falls into the quiet zone and is dropped, so this needs about an 85-minute interval.

</details>

### SCH-9 · medium · The scheduler's calendar is fixed when the config is built, so a time-zone change shifts working hours and midnight

**Where:** `Sources/movez/Scheduler/SchedulerConfig.swift:45` · **Category:** macos-edge · **DECISIONS checked:** 14, 20a, 20c

**What goes wrong.** `SchedulerConfig.calendar` defaults to `.current`, and so does `from(preset:)` at line 61. That value captures the time zone at the moment it is created, and it is only rebuilt at launch or in `settingsChanged()`. Nothing observes `NSSystemTimeZoneDidChange` (a grep of Sources finds no observer).

The calendar drives `WorkingHours.isWithin` and `nextStart`, `DayKey`, `endOfToday` and the ad-hoc midnight check. A laptop that flies from London to New York with movez running keeps judging 9–18 in London time. Breaks stop at 13:00 local, or start at 04:00 on the way back. Midnight rolls the counters at the wrong hour too, which disagrees with HistoryStore (DECISIONS 20c keeps the streak on the calendar day). DST itself is fine, because the TimeZone is a region.

**Suggested fix.** Use `Calendar.autoupdatingCurrent` in `SchedulerConfig` and `from(preset:)`, or observe `.NSSystemTimeZoneDidChange` in the coordinator and call `settingsChanged()`. HistoryStore and `TransitionLog.timeFormatter` have the same pattern. Add a test that changes the calendar's time zone and checks that `isWithin` follows.

<details><summary>Verification (confirmed)</summary>

SchedulerConfig.calendar and from(preset:) default to Calendar.current, a snapshot that does not track time-zone changes. SettingsStore.schedulerConfig builds a fresh config on each access, but the scheduler's copy changes only at launch and on .settingsChanged (setBreakLength touches only breakSeconds). A grep finds no NSSystemTimeZoneDidChange observer and no autoupdatingCurrent anywhere. The coordinator's previewKey and day-key code read settings.schedulerConfig.calendar (fresh), so after a time-zone change the two can disagree. HistoryStore, StrengthDayPlanner and TransitionLog also take .current.

</details>

### SCH-10 · low · A short lock or display sleep during a snooze cuts the snooze short

**Where:** `Sources/movez/Scheduler/Scheduler+Idle.swift:100` · **Category:** correctness · **DECISIONS checked:** 20, 43

**What goes wrong.** `handleSleepOrLock` puts `.snoozed(until:)` into `.away` after `captureCountdowns(at: now)`, which records the original due time (already in the past) as `dueAtAway`. On a return shorter than the away threshold, `returnFromAway` restores that due time and goes to `.sitting`, losing `until`.

Example: snooze at 10:00 until 10:05, a 30-second lock at 10:01. After the quiet minute (10:02:30) the next tick finds the due time past, and the heads-up is back at about 10:02:40 instead of 10:05. In pause-away mode a longer absence does the same, because `remainingAtAwaySeconds` is measured to the original due time, not to the snooze end.

**Suggested fix.** When going away from `.snoozed(until)`, capture `until` as the due time to restore (for example `dueAtAway = max(nextFullDueAt, until)`), or restore `.snoozed` on a short return. Add a lock-during-snooze test.

<details><summary>Verification (confirmed)</summary>

handleSleepOrLock from .snoozed reaches captureCountdowns(at: now), and dueAtAway = nextFullDueAt (the original due time, already past). On a return shorter than the away threshold, returnFromAway restores that due time and goes to .sitting, so the snooze's `until` is lost and the next tick enters pendingFull. .snoozed is not idle-interruptible, so only a lock or sleep triggers it. snoozesUsedThisBreak is kept, so the user loses only the remaining minutes, not the allowance.

</details>

### SCH-11 · low · Two handlers change state without checking it, which breaks `handle`'s promise to be total

**Where:** `Sources/movez/Scheduler/Scheduler+Idle.swift:165` · **Category:** correctness · **DECISIONS checked:** 16, 43

**What goes wrong.** `Scheduler` documents that every unhandled combination of state and event "returns no effects and changes nothing". Two handlers break that.

`reverseCredit` transitions to `.sitting` from whatever state it finds, as long as `creditRestore` has not expired, and nothing clears `creditRestore` when the state moves on. In pause-away mode with a break owed, the return sets `nextFullDueAt = returnedAt`, and the heads-up can appear while the 15-second toast is still up. Tapping "I was sitting" then moves to `.sitting` without `.hideHeadsUp`. The panel stays up with Start/Snooze/Skip all refused until the next heads-up replaces it.

`.userStartSession` (Scheduler.swift:75) calls `beginAdHocSession` from any state. Today only the dropdown gates it to off hours, but from `.fullBreak` it would move to sitting without `.endFullBreak`.

**Suggested fix.** Guard `reverseCredit` on `case .sitting = state`, and clear `creditRestore` on any transition out of sitting. Guard `.userStartSession` to `.offHours`, as the menu already assumes.

<details><summary>Verification (confirmed)</summary>

reverseCredit guards only on creditRestore and its 15 s expiry, then transitions to .sitting from any state and emits only .hideToast. In pause-away mode with 0 remaining, returnFromAway sets nextFullDueAt = returnedAt, so pendingFull and then the heads-up (input pause of 10 s) can appear while the toast is still up. Reversing then leaves an orphaned heads-up panel until the next showHeadsUp replaces it. .userStartSession calls beginAdHocSession unguarded, but the only sender is the off-hours dropdown row, so that half is latent.

</details>

### SCH-12 · low · A relaunch within 10 s of the last save leaves the scheduler in `.fullBreak` with nothing on screen

**Where:** `Sources/movez/Scheduler/Scheduler+Sleep.swift:157` · **Category:** lifecycle · **DECISIONS checked:** 20b

**What goes wrong.** applyLaunchGap's short-gap early return (≤10 s since the last persist) skips the isBreakSurfaceVisible reset, so a .fullBreak restored from a file written seconds before the process died stays in .fullBreak with no overlay until the next sleep or lock. This needs a crash and a relaunch within 10 s of the last write, which nothing in the app does automatically, so it is an unlikely edge rather than a common path.

**Suggested fix.** Run the isBreakSurfaceVisible check (at least for .fullBreak) before the short-gap early return, and add a 5 s case to testABreakRestoredWithNothingOnScreenIsResolvedAtLaunch.

<details><summary>Verification (confirmed with corrections)</summary>

The mechanism is real: a gap ≤10 s returns rollDayIfStale before the isBreakSurfaceVisible check, and nothing times out .fullBreak (tickBreakStates has no case; idle, pause and takeBreakNow refuse it). The trigger is much narrower than claimed. The gap is measured from savedAt (the last persist; the heartbeat is every 30 s and applicationWillTerminate does not persist), so the process must die and relaunch within 10 s of the last write. Nothing relaunches movez automatically (no KeepAlive), and a rebuild plus `make run` takes longer than that. It recovers on the next sleep or lock, which moves fullBreak to away and resumes the break. LaunchStateTests:152 tests only the 20-minute gap.

</details>

### SCH-13 · low · After a relaunch, a snooze or pending break keeps its wall-clock deadline while the countdown is moved on

**Where:** `Sources/movez/Scheduler/Scheduler+Sleep.swift:207` · **Category:** correctness · **DECISIONS checked:** 20b

**What goes wrong.** When the app relaunches after a gap of more than 10 s but less than one sitting interval, shiftInterval moves boutStartedAt, both due times, the micro anchor and an absence's `since` forward by the gap, then re-enters the same state. Only `.away` has the date inside its state shifted. `.snoozed(until:)`, `.pendingFull(since:)` and `.postBreakGrace(until:)` keep their original deadlines. Example: the user snoozes at 10:00 (until 10:05), quits at 10:01 and relaunches at 10:21. The snooze had four minutes left, but the first tick sees now ≥ until and puts the heads-up up the moment the app starts. Decision 20b says time Movez was not running is moved past; the countdown follows that, the snooze does not. LaunchStateTests only seed .sitting and .fullBreak, so these states are not covered.

**Suggested fix.** In shiftInterval, shift the dates carried by the state (the snooze's until, pendingFull's since, the grace's until, suppressed's since) the same way .away is shifted. Add launch tests seeded in .snoozed and .pendingFull that tick once and assert no showHeadsUp.

<details><summary>Verification (confirmed)</summary>

Confirmed. shiftInterval (192-211) shifts boutStartedAt, both due times, microAnchorAt and dueAtAway, but changes the state's own date only for .away. isBreakSurfaceVisible (SchedulerState.swift:57-61) does not include snoozed or pendingFull, so those states reach shiftInterval unchanged. On the first tick, tickBreakStates (Scheduler.swift:160-162) sees now >= until on the old snooze deadline and calls enterHeadsUp at once. pendingFull(since:) likewise hits the input-wait cap at once. This is inconsistent with 20b ('shifts the whole bout forward'). The scheduler-level applyLaunchGap tests in AwayReturnTests and the LaunchStateTests cover only sitting, away and fullBreak.

</details>

### SCH-14 · low · Dead state and dead branches in the scheduler

**Where:** `Sources/movez/Scheduler/SchedulerSnapshot.swift:59` · **Category:** dead-code

*Found independently by the Tests: scheduler, coordinator, signals, persistence, settings review as well.*

**What goes wrong.** Several fields and branches do nothing, and some of their comments describe behaviour that does not exist:
- `configHash` is written in three places (Scheduler.swift:15, 254, 274) but never read outside one test. Its `stableHash` comment promises that "a resumed session can tell whether the settings changed while it was gone", and nothing does that.
- `pendingInputWaitStartedAt` (line 46) is written in four places and never read; `.pendingFull(since:)` carries the same date.
- `SignalSnapshot.screenLocked` and `displaySleeping` (SignalSnapshot.swift:12-13) are never set or read.
- `GraceResume.sitting` and `.pendingFull` (SchedulerState.swift:5-6) are never constructed. Unlike `.applyGap`, nothing marks them as kept only so old files decode.
- `enterHeadsUp`'s `deferredSince:` parameter is never passed.
- `apply()`'s `wasPolling != pollingRequired` check (Scheduler.swift:262) can never be true, because `apply` does not change the state.

Each one invites a reader to believe a behaviour exists.

**Suggested fix.** Remove the never-read fields and the unused parameter. Optional fields decode fine when absent, and a removed key is ignored on decode. Mark the `GraceResume` cases as decode-only, as `.applyGap` is. Either implement the `configHash` check at launch or drop the field and fix the comment.

<details><summary>Verification (confirmed)</summary>

Verified each item by grep. snapshot.configHash is written at Scheduler.swift:15, 254 and 274 and read only in SettingsLiveUpdateTests:174 (the previewKey uses settings.schedulerConfig.stableHash, not the snapshot field), and the stableHash comment's promise is unimplemented. pendingInputWaitStartedAt is written in four places and never read. SignalSnapshot.screenLocked and displaySleeping are never set or read. GraceResume.sitting and .pendingFull are never constructed (the only postBreakGrace constructions are at Suppression:42 and Sleep:96). enterHeadsUp's deferredSince: is never passed. pollingRequired depends only on state, which apply() does not change, so the check at line 262 is always false.

</details>

### SCH-15 · low · Dead SignalSnapshot fields and an unused report path

**Where:** `Sources/movez/Scheduler/SignalSnapshot.swift:12` · **Category:** dead-code

**What goes wrong.** `screenLocked` and `displaySleeping` (lines 12-13) are never written or read; lock and display sleep reach the scheduler as their own PowerMonitor events.

`frontmostBundleId` (line 15) is written by the aggregator and read by nothing, because the fullscreen exceptions are applied inside FullscreenMonitor. Yet when the fullscreen setting is off, `read()` still makes an NSWorkspace call on every poll just to fill it (SignalAggregator.swift:119-121, 150-152), and the comment at lines 116-117 says the snapshot 'needs' it.

The Codable conformance is unused as well, since nothing persists a SignalSnapshot. Finally, `AppCoordinator.report(signals:)` (AppCoordinator.swift:286-291) is never called, and it sends events in a different order from `poll()`: a second, divergent copy of the dispatch logic.

**Suggested fix.** Delete the two dead fields and drop Codable. Either remove `frontmostBundleId` and the per-poll frontmost lookup, or make it the one place the exceptions are applied. Delete `report(signals:)`.

<details><summary>Verification (confirmed)</summary>

Neither screenLocked nor displaySleeping is referenced anywhere in Sources or Tests. frontmostBundleId is written by SignalAggregator.read (121, 127) and read only by SignalAggregatorTests:79. SignalProbe prints reading.bundleId directly, and the exceptions are applied inside FullscreenMonitor. Even with the fullscreen setting off, the frontmostBundleId() NSWorkspace call runs on every poll (121, 150-152). SignalSnapshot is Codable, but SchedulerEvent is only Equatable and nothing persists a snapshot. AppCoordinator.report(signals:) (286-291) has no callers in Sources or Tests (only report(inputAgeSeconds:) is called, from tests), and it dispatches in a different order from poll(), with .idle only when idle > 0.

</details>


## 2. App, History, Notice, Settings, FocusFilter, Audio

### APP-1 · medium · The Focus filter is applied as a one-shot event, and the event can be lost

**Where:** `Sources/movez/FocusFilter/MovezFocusFilterIntent.swift:37` · **Category:** lifecycle · **DECISIONS checked:** 26, 51

**What goes wrong.** perform() forwards pauseBreaks to `AppCoordinator.shared`, a static weak reference that is set only in start() (AppCoordinator.swift:215). The value is acted on once, as an event, and never stored or read back. It is lost in three ways:

(a) It arrives while no coordinator exists: before the health notice is accepted (AppDelegate.swift:84-100 never builds one), or when macOS performs its boot-time default before the login item has started the app. The optional chain drops it silently.

(b) A Focus turns on while a full break is on screen. pause() returns [] in `.fullBreak` (Scheduler+Pause.swift:11), so after the break, breaks keep running for the whole Focus.

(c) Movez quits or crashes during a Focus pause, and the Focus ends before it relaunches. The snapshot restores `.paused(until: nil)`, which outlasts the launch gap (Scheduler+Sleep.swift:162-164), working hours (Scheduler+Hours.swift:17-19) and midnight. Nothing ever asks macOS for the current Focus, so breaks stay paused across days until the user presses Resume.

Nothing in Sources reads `MovezFocusFilterIntent.current`.

**Suggested fix.** Keep the last requested Focus state as state, on the coordinator or in SettingsStore. In start(), read `try await MovezFocusFilterIntent.current` and reconcile. Re-apply a pending pause when a full break ends. If perform arrives before the coordinator exists, record the value and apply it in start().

<details><summary>Verification (confirmed)</summary>

perform() calls AppCoordinator.shared?.focusFilter, a static weak reference set only in start() (AppCoordinator.swift:77, 215). Before the notice is accepted, launch() never builds a coordinator (AppDelegate.swift:84-100), so the call is dropped. In .fullBreak, pause() returns [] (Scheduler+Pause.swift:11), so a Focus that turns on during a break is lost, and nothing re-applies it afterwards. A focus pause is paused(until: nil): tickPaused never ends it (Pause.swift:82-85), applyWorkingHours leaves it alone (Hours.swift:17-19), and applyLaunchGap keeps it (Sleep.swift:157-160). Nothing reads MovezFocusFilterIntent.current (grep). DECISIONS 51 says macOS re-sends the default at every boot, which recovers case (c) after a reboot but not after a quit and relaunch without one. Case (b) alone is a concrete, reachable failure.

</details>

### APP-2 · low · A relaunch with an interrupted break still in state.json serves a different, backdated break

**Where:** `Sources/movez/App/AppCoordinator+Effects.swift:111` · **Category:** lifecycle · **DECISIONS checked:** 20b

**What goes wrong.** InterruptedBreak is saved in the snapshot, but the session it belongs to (interruptedSession) lives only in memory. applyLaunchGap clears it only for standby (Scheduler+Sleep.swift:175-181). A short gap while away keeps it, through shiftInterval or the ≤10 s early return.

If the user then returns before the absolute plannedEnd, the scheduler sends `.startFullBreak(resumed: true)` with startedAt backdated by the elapsed time. beginBreak finds no kept session and falls through to a newly built break, but keeps the backdated plan.startedAt. The new overlay then treats the opening blocks of a routine the user never saw as already run, and records them: recordOverlayPart's guard passes because completedBlocks is 0. It needs a crash or relaunch during an interruption plus a quick return, so it is rare.

**Suggested fix.** In beginBreak, when plan.resumed is set but nothing was kept, start the fresh break at clock.now. Alternatively, have applyLaunchGap drop interruptedBreak: as its own comment says for a visible break, whatever was on screen died with the process.

<details><summary>Verification (confirmed)</summary>

interruptedSession is in-memory only. interruptedBreak is in the snapshot with an absolute plannedEnd. Relaunching in .away (not isBreakSurfaceVisible) with a short gap goes through shiftInterval (Sleep.swift:170-199) or the ≤threshold early return, and neither clears interruptedBreak. On return, endAbsence calls resumeInterruptedBreak, which emits startFullBreak(resumed: true) with a backdated start when now < plannedEnd. beginBreak finds no kept session and falls through to a fresh break, but keeps plan.startedAt (Effects.swift:111-121). The new overlay then replays the 'elapsed' blocks. recordOverlayBlock has no guard, and recordOverlayPart's guard passes because completedBlocks is 0. Rare, so low.

</details>

### APP-3 · low · Persistence failures are silent, and a failed store setup runs a whole session with nothing saved

**Where:** `Sources/movez/App/AppDelegate.swift:115` · **Category:** persistence · **DECISIONS checked:** 3

**What goes wrong.** startCoordinator builds both file stores with `try?`. If Application Support/movez can't be created (for example a plain file named `movez` is in the way, or permissions are wrong), it falls back to an in-memory HistoryStore and no snapshot store (lines 115-121). The app looks normal, loses the whole session at quit, and logs nothing.

persistSnapshot (AppCoordinator+Effects.swift:63) and HistoryStore.save (line 281) also swallow every write error with `try?`, and lastPersistAt is updated as if the write succeeded. When setAttributes or replaceItemAt throws, the `.state.json.<UUID>` or `.history.json.<UUID>` temp file stays in the directory: one leftover per failed save (StatePersistence.swift:59-66, HistoryPersistence.swift:31-38).

**Suggested fix.** Log every failure through MovezLog.store. Show a failed store setup to the user (an alert or a menu line). Delete the temp file in a catch block or `defer`.

<details><summary>Verification (confirmed)</summary>

AppDelegate.swift:115-121 builds both stores with try? and falls back to HistoryStore() in memory and a nil snapshotStore, with no log. persistSnapshot sets lastPersistAt and then calls try? save (Effects.swift:60-64). HistoryStore.save is try? (line 280-282). FileSnapshotStore.save (StatePersistence.swift:57-71) and FileHistoryStore.save (HistoryPersistence.swift:29-44) write a dot-temp file and never remove it if setAttributes or replaceItemAt throws. The trigger is unusual, so low is right.

</details>

### APP-4 · low · An unreadable history file is overwritten by the next save, so the record cannot be recovered

**Where:** `Sources/movez/History/HistoryStore.swift:118` · **Category:** persistence · **DECISIONS checked:** 43

**What goes wrong.** A history file that fails to decode is replaced by an empty record, and the next save overwrites it. DECISIONS 43 accepts starting fresh on a downgrade, but because the original file is overwritten rather than set aside, upgrading back (or recovering from a one-off read error) cannot bring the record back.

**Suggested fix.** On a decode failure, rename the file aside (history.json.unreadable-<date>) and log the path before starting fresh. Leave the DECISIONS 43 behaviour otherwise unchanged.

<details><summary>Verification (confirmed with corrections)</summary>

The mechanism is confirmed. restore() returns an empty HistoryData on any decode error (lines 118-125). save() runs on every mutation and replaces the file via replaceItemAt (HistoryPersistence.swift:29-44). HistoryData and BreakRecord use synthesized Codable, so an unknown raw value fails the whole file. However, DECISIONS 43 explicitly accepts that an older build "cannot decode it and starts fresh; that only matters on a downgrade". LaunchStateTests.testACorruptHistoryFileCostsTheRecordAndNothingElse asserts that loss on purpose. Severity is lowered to low: the decided trade-off stands, and what remains is cheap hardening (keep the unreadable bytes aside) for a downgrade or corruption case.

</details>

### APP-5 · low · "Longest sitting bout" ignores bouts that only skips touched; recordLongestBout is never called

**Where:** `Sources/movez/History/HistoryStore.swift:159` · **Category:** dead-code

**What goes wrong.** The menu line reads DailyStats.longestBoutSeconds. That field is written only when a completed break or an absence record passes in the scheduler's longestBoutSeconds (AppCoordinator+Effects.swift:139, 243). The scheduler measures a bout only when the bout ends (recordBout, Scheduler.swift:236), and a skip deliberately doesn't end it. So someone who sits from 09:00 to 12:00 skipping every break sees "Longest sitting bout 0 m", on exactly the day the number matters most. HistoryStore.recordLongestBout looks as if it was meant for this, but nothing calls it.

**Suggested fix.** Call recordLongestBout(now - boutStartedAt) on the heartbeat and on each skip, or include the running bout when the menu line is built. Otherwise delete the method.

<details><summary>Verification (confirmed)</summary>

recordLongestBout is called only from HistoryStoreTests (grep). DailyStats.longestBoutSeconds is written only when a completed break (Effects.swift:139) or an absence (line 243) passes in the scheduler's longestBoutSeconds. Skip and snooze records pass nothing. The scheduler updates longestBoutSeconds only in recordBout, which runs when a break completes, at standby, or on an away reset (Scheduler.swift:236-239, Idle.swift:92,128). Skips keep the bout running. MenuBarViewModel.applyStats always shows the line (line 239), so a day of skips with no absence reads "Longest sitting bout 0 m".

</details>

### APP-6 · low · History grows without limit, is re-encoded on the main thread on every change, and is scanned in full on every delivery

**Where:** `Sources/movez/History/HistoryStore.swift:280` · **Category:** complexity · **DECISIONS checked:** 20c

**What goes wrong.** Nothing prunes history, and every mutation (each completed movement or set) re-encodes and rewrites the whole file on the main thread, so each write costs more as the history grows. Routine builds also scan every completion (recency, the difficulty unlocks, the day's used ids). The per-delivery strength planner scan covers only break records and is cheap, and the dayProgress doc comment is accurate.

**Suggested fix.** Prune completions older than the recency window and keep per-movement counts for the unlocks, or switch to an append-only log. Optionally cache today's completion set in HistoryStore.

<details><summary>Verification (confirmed with corrections)</summary>

Confirmed: save() re-encodes and atomically rewrites the whole HistoryData on every completion and record, on the main actor, and nothing prunes completions. Corrected: the dayProgress doc ('refreshed with the preview rather than on every tick') is accurate. refreshPublished runs per deliver (about 30 s heartbeat or effects), while tick() only rebuilds menuState (AppCoordinator.swift:269-279). The planner scans breakRecords, which are about 10 a day, not completions. usedMovementIds' full completion scan runs only when the preview key changes, not on every delivery. The real cost is the growing full rewrite on each mutation, plus the recency and unlock scans at each rebuild. This is a scaling concern, not a present bug.

</details>


## 3. Signals

### SIG-1 · high · Fullscreen detection never fires for native fullscreen apps on a notched MacBook display

**Where:** `Sources/movez/Signals/FullscreenMonitor.swift:35` · **Category:** macos-edge · **DECISIONS checked:** none (20 and 23h say fullscreen suppresses; README's known limitation covers maximised editors, not this)

**What goes wrong.** `reading(exceptions:)` asks the window server (CGWindowListCopyWindowInfo, line 59) for the frontmost app's on-screen, layer-0 windows. It then calls `isFullscreen`, which only says yes when a window's origin and size are within 1 pt of a whole `NSScreen.frame`. `screenFrames()` (lines 46-57) flips each frame into the top-left-origin coordinates the window list uses.

On a MacBook with a camera housing, `NSScreen.frame` includes the strip beside the notch. macOS, however, places a native fullscreen window inside the screen's safe area, below that strip. Measured on this Mac: the built-in display's frame is 1728x1117 with `safeAreaInsets.top` = 32. A fullscreen Keynote, Zoom or Safari-video window therefore comes back at roughly y = 32 and height 1085. That is 32 pt off on two edges, against a 1 pt tolerance, so `isFullscreen` returns false.

Trigger: any native fullscreen app on the built-in panel of a notched MacBook (2021+ Pro, M2+ Air), including the owner's 16-inch. The external display (safe area 0) still works. On the laptop panel the 'suppress during fullscreen' setting silently does nothing, and breaks fire over presentations and fullscreen calls. FullscreenMonitorTests only uses un-notched frames.

To confirm, run `movez --probe-signals` with a Safari video fullscreen on the laptop panel; expect `fullscreen=false`.

Sources: [Apple: NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets.md) (native fullscreen content is placed inside the safe area); [cocoa-dev: How to check for full-screen apps, robustly?](https://lists.apple.com/archives/cocoa-dev/2023/Aug/msg00016.html) (QuickTime and Safari fullscreen windows come out smaller than the screen frame on notched Macs).

**Suggested fix.** For each screen with `safeAreaInsets.top > 0` (macOS 12+), have `screenFrames()` return the safe-area rect (the frame with the top inset removed) alongside the full frame, and accept a match on either. Add a notched 1728x1117 / inset-32 case to FullscreenMonitorTests.

The trade-off: on a notched panel with the Dock hidden, a zoomed window has the same bounds. That is the maximised-editor compromise the README already names, and the per-app exceptions list covers it.

<details><summary>Verification (confirmed)</summary>

isFullscreen (35-42) requires all four edges to be within tolerance = 1 pt of a whole NSScreen.frame, and screenFrames (46-57) returns only the full frames. Measured on this Mac: the built-in display's frame is 1728x1117 with safeAreaInsets.top = 32 (the menu-bar strip is 37-38 pt; visibleFrame height is 1079). By default macOS puts native fullscreen content below the camera housing, so a fullscreen window there comes back about 32 pt short and can never match. The external LEN display has an inset of 0 and still works. No fullscreen window was open, so I could not capture live bounds; the OS placement rests on Apple's documented behaviour, which is well established. FullscreenMonitorTests uses only 1440x900 and 2560x1440 frames with no inset, and no DECISIONS entry covers this. Small correction to the fix's stated trade-off: a zoomed window on the notched panel starts under the menu bar (about y = 38, height 1079 or less), not at y = 32, so the safe-area rect would not actually match it within 1 pt. The trade-off is smaller than claimed.

</details>

### SIG-2 · medium · The mic signal reads only the default input device, and that property can't tell input from output

**Where:** `Sources/movez/Signals/MicrophoneMonitor.swift:10` · **Category:** macos-edge · **DECISIONS checked:** 23h

**What goes wrong.** `isInUse()` looks up `kAudioHardwarePropertyDefaultInputDevice` and reads `kAudioDevicePropertyDeviceIsRunningSomewhere` on that one device (lines 9-19). This goes wrong in two ways.

(a) Missed calls. A call app set to a specific microphone (for example Zoom on a USB headset while the system default input is the MacBook mic) runs a device Movez never looks at. The reading stays false and a break lands in the middle of the call. The same happens when the default input changes mid-call (AirPods connect): the reading drops to false, suppression ends, and after the 2-minute grace the deferred break comes up during the call.

(b) False calls. The property is device-wide: it says the device's IO is running, not which direction. So when the default input is a device that also plays sound (a USB or Bluetooth headset, an audio interface), playing music or a video through it keeps the device 'running'. After the 60 s hold, that reads as a call, and every full break is deferred 'for your call' for as long as audio plays.

DECISIONS 23h covers not knowing which process holds the mic (dictation bursts). It does not cover direction or the device choice.

Sources: CoreAudio list threads noting the property 'doesn't seem to distinguish between input and output activity' ([2006](https://lists.apple.com/archives/coreaudio-api/2006/Apr/msg00169.html)) and only says whether the *device* is in use, not which stream ([2015](https://lists.apple.com/archives/coreaudio-api/2015/May/msg00021.html)).

**Suggested fix.** Use the process-level API that 23h already names as the next step. On macOS 14.2+, enumerate `kAudioHardwarePropertyProcessObjectList` and treat the mic as in use when any process other than Movez reports `kAudioProcessPropertyIsRunningInput`. That is per-direction and covers every device, and it can also name the process. The deployment target is 14.0 (project.yml:6), so put this behind `if #available(macOS 14.2, *)`. The fallback should check every device that has input streams (`kAudioDevicePropertyStreams` with input scope), not only the default one.

Keep the device and process selection in a pure function so it can be unit-tested with fake device lists.

<details><summary>Verification (confirmed)</summary>

isInUse reads kAudioDevicePropertyDeviceIsRunningSomewhere with global scope on the device returned by kAudioHardwarePropertyDefaultInputDevice, and on nothing else (lines 9-40). (a) A call on a non-default mic is never seen, and the default changing mid-call drops the reading to false. SustainedSignal then resets and endSuppression opens the 2-minute grace. (b) The property is device-wide, global scope, so a duplex default input (a USB headset or an audio interface) that is only playing output still reads as running. After the 60 s sustain that becomes a call. 23h accepts only the process ambiguity (dictation); it says nothing about direction or device choice. Medium is right: the built-in MacBook mic and speakers are separate devices, so the default setup is unaffected, but headset users will hit it.

</details>

### SIG-3 · medium · A display that sleeps from inactivity dates the absence from the sleep, not from the last input

**Where:** `Sources/movez/Signals/PowerMonitor.swift:30` · **Category:** correctness · **DECISIONS checked:** 23b (an absence is measured from when it began), 43

**What goes wrong.** PowerMonitor turns `NSWorkspace.screensDidSleepNotification` into the same `.sleep` event a closed lid sends. `Scheduler.handleSleepOrLock` has no input age to go on, so it starts the absence at the notification: `captureCountdowns(at: now)` and `.away(since: now)` (Scheduler+Sleep.swift:45-48).

But the display sleeps *because* nobody has touched anything for N minutes. The idle path (Scheduler+Idle.swift:26-35) dates an absence from `now - idleSeconds`, and the aggregator knows that age (`lastSnapshot.idleSeconds`), but nothing passes it along. Whenever display sleep comes before 'Count me away after', every absence is measured short by the display-sleep delay. Any absence shorter than threshold + delay is ignored entirely: `returnFromAway` takes the 'under the threshold' branch, restores the countdown, and shows no toast and writes no record.

Replayed with the real Scheduler sources: a 4-minute walk, default 3-minute threshold (SettingsStore.swift:127), display off after 2 minutes. It ends with 'back after 120 s', no reset, no toast and no away entry. The same walk with the display on gives 'away 4 min, countdowns reset' plus a toast.

A screensaver that locks the screen before the threshold (`com.apple.screenIsLocked`, line 37) behaves the same way. This Mac uses 10 and 30 minutes of display sleep, so it won't show here. A 2-minute display sleep on battery is a common laptop setting, and the threshold can be raised to 10 minutes (SettingsStore.swift:47), which equals the usual AC display sleep.

**Suggested fix.** Send the input age with the event. In the coordinator's PowerMonitor callback (AppCoordinator.swift:247-252), attach `aggregator.lastSnapshot.idleSeconds`, or read the idle source directly, to `.sleep` and `.lock` (e.g. `.sleep(inputAgeSeconds:)`). In handleSleepOrLock, date `away(since:)` and `captureCountdowns` from `now - inputAge`, floored by `lastCompletedBreakAt` and `lastAbsenceEndedAt` as handleIdle does.

A lid close or a Ctrl-Cmd-Q lock has an age near zero, so those behave exactly as today. Add a scheduler test that climbs the idle age for two minutes and then sends `.sleep`.

<details><summary>Verification (confirmed)</summary>

Line 30 maps screensDidSleepNotification to .sleep. handleSleepOrLock (Scheduler+Sleep.swift:45-48) calls captureCountdowns(at: now) and transitions to .away(since: now). handleIdle, by contrast, dates the absence from now - seconds (Scheduler+Idle.swift:26-35). Once away, .away is not interruptible by idle, so later polls never re-date it. handleWake keeps min(since, reportedStart), and reportedStart is about 2 s back. endAbsence measures from the sleep moment, and returnFromAway (Idle.swift:99-103) takes the 'under the threshold' branch when absence < awayThresholdSeconds: it restores dueAtAway with no toast and no recordAbsence. So when display sleep comes before the away threshold, the absence is shortened by the display-sleep delay, and a 4-minute walk with a 2-minute display sleep against the 3-minute threshold is ignored. The same applies to the screenIsLocked path (line 37). 23b says an absence is measured from when it began, which supports the finding.

</details>

### SIG-4 · medium · Input before signals in each poll plays a heads-up chime in back-to-back calls

**Where:** `Sources/movez/Signals/SignalAggregator.swift:107` · **Category:** correctness · **DECISIONS checked:** 20 (defer, never reset), 23h

**What goes wrong.** `poll()` sends three events in order: `.input(age)`, then `.idle`, then `.signals` (lines 107-109). Within one poll, the scheduler can therefore act on input before it learns that a call or share is live.

Two scheduler rules then combine. `beginSuppression` ignores a new signal while the scheduler is in the 2-minute post-suppression grace: `.postBreakGrace` falls into the `default: return []` branch (Scheduler+Suppression.swift:25-30). When that grace ends with a break deferred, `resumeAfterSuppression` goes straight to `.pendingFull` (lines 46-51). The next poll's `.input` (an age of 10 s or more, which is normal while listening in a call) calls `enterHeadsUp`. That puts the panel up and plays `chime(.headsUp)`, and the same poll's `.signals` then hides the panel again.

Reproduced with the real Scheduler sources plus a copy of the poll order and SustainedSignal. Call 1 runs 10:00-60:00 with a break deferred at 55:00, and call 2 starts 30 s after call 1 ends. At 62:00, 90 s into call 2, the poll emits showHeadsUp, then chime(headsUp), then hideHeadsUp. A single mic dropout during one call does the same: SustainedSignal resets on one false reading, and the renewed reading arrives during a grace that ignores it.

With `.signals` sent first, the same run produced no heads-up at all. AwayReturnTests' poll helper mirrors the order but never sends `.signals`, so nothing covers this.

**Suggested fix.** Send `.signals` before `.input` and `.idle` in `poll()`. While away, signals are already ignored, so return detection is unchanged. In `.sitting`, the suppressed state is not interruptible by idle, so no absence starts by mistake.

Also (scheduler area): let `beginSuppression` move `.postBreakGrace(_, .afterSuppression)` back to `.suppressed`, keeping `deferredFullDueAt`.

Add an aggregator-level back-to-back-call test that asserts no `.showHeadsUp` and no `.chime` while the mic is held.

<details><summary>Verification (confirmed)</summary>

poll() sends .input, then .idle, then .signals (107-109). beginSuppression returns [] for .postBreakGrace through its default branch (Suppression.swift:25-30), so a sustained mic reading that arrives during the 2-minute grace is dropped. When the grace ends with deferredFullDueAt set, resumeAfterSuppression calls enterPendingFull, which emits no surface. On the next poll, handleInput (Scheduler.swift:199) sees age >= inputPauseSeconds (10) in .pendingFull and calls enterHeadsUp, which returns [.showHeadsUp, .chime(.headsUp), ...] (Actions.swift:22). The same poll's .signals then hits the .headsUp case and appends .hideHeadsUp. The chime plays audibly in a call. With .signals first, .pendingFull goes straight to .suppressed. SignalAggregatorTests never combines grace with a renewed mic hold, and the AwayReturnTests poll helper never sends .signals. Back-to-back calls within two minutes, or a single mic dropout, trigger it.

</details>

### SIG-5 · medium · At the 60x debug scale every poll is a synthesised wake, and no break ever fires

**Where:** `Sources/movez/Signals/SignalAggregator.swift:159` · **Category:** correctness · **DECISIONS checked:** none (21 and 23b set the quiet minute; the time scale is not in DECISIONS)

*Found independently by the Tests: scheduler, coordinator, signals, persistence, settings, UI: MenuBar + Settings reviews as well.*

**What goes wrong.** The debug time scale (DebugState.timeScales = [1, 10, 60]) makes SystemClock run fast. `pollInterval` floors the real timer at `minimumPollSeconds` = 0.25 s (lines 59-61), so at 60x two polls are 0.25 x 60 = 15 scaled seconds apart. `detectTickGap` compares that scaled gap with `tickGapThresholdSeconds` = 10 (line 159). The 5 s `wakeCoalesceSeconds` check doesn't absorb a 15 s gap, so every poll sends `.gapDetected(15)`.

In `.sitting`, `Scheduler.handleWake`'s default branch accepts any gap over 10 s and enters the wake-quiet minute. Every later gap, now in `.postBreakGrace(.returnFromAbsence)`, re-enters it with a fresh `until = now + 60` (Scheduler+Sleep.swift:77-78, 94). The minute therefore never ends.

Replayed with the real Scheduler sources: 480 polls over two scaled hours gave 480 synthesised wakes, post_break_grace after every poll, and no break. At 10x (2.5 scaled seconds between polls) the same loop ran normal micro and full breaks. The menu shows 'Away' (19a) the whole time.

So the 60x mode, which DebugViewModel says reproduces a day's sleep and idle bugs in a minute, cannot reproduce anything once the real aggregator is attached. DebugViewModelTests.swift:25-48 asserts the 0.25 s floor but never polls at it.

**Suggested fix.** Judge the gap against the interval the timer was asked for, e.g. `guard gap > max(Self.tickGapThresholdSeconds, 4 * pollInterval * max(1, settings.debugTimeScale))`. A real sleep still passes the scheduler's own > 10 s check. Alternatively, lower the floor so the scaled interval stays under 10 s.

Add a test that sets the scale to 60, advances a ManualClock 15 s per `poll()` and asserts there are no 'tick gap' transitions.

<details><summary>Verification (confirmed)</summary>

pollInterval = max(0.25, 2/60) = 0.25 s real (59-61), while SystemClock.now scales elapsed real time by 60 (Clock.swift:32-34). The scaled gap between polls is therefore 15 s, which exceeds tickGapThresholdSeconds = 10. The coalesce check is 5 s and the last synthesised wake was 15 s ago, so every poll dispatches .gapDetected(15). In .sitting, handleWake's default branch accepts a gap over 10 and calls enterAbsenceGrace. In .postBreakGrace(.returnFromAbsence), case 77-78 does not check fromTickGap and re-enters with until = now + 60 scaled, which is 1 real second, while polls arrive every 0.25 s. The grace never expires and no break fires. The tick timer is floored at 0.25 s too (AppCoordinator.swift:143, 322). DebugViewModelTests:25-48 only asserts the interval value. This is developer-only (the Debug section sits behind settings.debugExpanded), which is why it is medium and not high, but it makes 60x useless for its stated purpose.

</details>

### SIG-6 · low · Test-only fake sources ship in the app target, and the header comment says otherwise

**Where:** `Sources/movez/Signals/FakeSignals.swift:5` · **Category:** dead-code

**What goes wrong.** The four Fake*Source classes (lines 5-30) are used only by six test files, yet they sit in Sources/movez/Signals and are compiled into the shipped app.

The header comment (lines 3-4) says the debug injectors in the settings window use them. They don't: the injectors go through SignalOverrides and the Overriding* wrappers (AppCoordinator.swift:233-237). A reader following that comment looks in the wrong place for how a debug hold reaches a poll.

**Suggested fix.** Move the fakes to Tests/movezTests, beside CoordinatorTestSupport. Keep SignalInjector and SignalHold, which the debug UI does use, in a file named for them, and fix the comment.

<details><summary>Verification (confirmed)</summary>

A grep of Sources/movez finds no use of FakeIdleSource, FakeMicSource, FakeCaptureSource or FakeFullscreenSource outside FakeSignals.swift. They are used by six test files (SignalAggregatorTests, SettingsLiveUpdateTests, DebugViewModelTests, EdgeCaseTests, FullscreenMonitorTests, FakeSignalsTests). The debug injectors go through SignalOverrides and the Overriding* wrappers (AppCoordinator.swift:233-237), so the header comment at lines 3-4 is wrong. This is dead code in the shipped app plus a misleading comment.

</details>

### SIG-7 · low · The debug 'Mic on' hold is undone by the 60 s sustain, and 'off' clears every held signal

**Where:** `Sources/movez/Signals/FakeSignals.swift:125` · **Category:** test-gap · **DECISIONS checked:** 23h

**What goes wrong.** SignalOverrides' doc (SignalOverrides.swift:5-8) promises that a held 'Mic on' behaves exactly like a real call through every poll. Since 23h, `poll()` runs the mic through SustainedSignal, which reports false until the raw reading has been true for 60 s.

What pressing Mic on actually does:
1. The injector's own one-shot event, `.signals(SignalSnapshot(microphoneActive: true))` (line 125), suppresses at once.
2. The next poll reads the held raw `true`, starts the 60 s clock, reports false, and ends the suppression into a 2-minute grace.
3. The sustained `true` at 60 s is ignored during that grace.

The tool shows suppressed, then grace, then suppressed, which no real call produces.

Separately, Mic off, Capture off and Fullscreen off all send `.signals(.quiet)` (line 128). That clears every signal, including another one still held, and opens the grace although capture is still 'on'.

The test that should catch this, `testAHeldSignalSurvivesThePollThatFollowsIt` (Tests/movezTests/DebugViewModelTests.swift:121-138), calls `aggregator.read(now:)`. That method skips `sustained()`, so the test passes while the real poll path undoes the hold.

**Suggested fix.** Let the aggregator know about a hold: pass it SignalOverrides and skip the sustain while `micInUse` is held. Then drop the one-shot suppression events, or build their snapshot from all current holds instead of `.quiet`.

Change the test to call `poll()` and assert the scheduler state two polls later.

<details><summary>Verification (confirmed)</summary>

fire(.micOn) applies the hold and then injects .signals(SignalSnapshot(microphoneActive: true)), which suppresses at once. The next real poll reads the held raw true, but sustained() reports false for 60 s, so handleSignals calls endSuppression, which opens the grace. The sustained true about 60 s later is dropped by beginSuppression's default branch during the 120 s grace. So the tool shows suppressed, then grace, then sitting or pendingFull, then suppressed, which contradicts the SignalOverrides doc (lines 5-8). Line 128 sends .quiet for every 'off', which can end a suppression another held signal should keep. testAHeldSignalSurvivesThePollThatFollowsIt (DebugViewModelTests:121-138) calls read(now:), which skips sustained(), so it cannot catch this. Debug-only, so low.

</details>

### SIG-8 · low · Capture-matcher comments contradict the code, and the QuickTime row is redundant

**Where:** `Sources/movez/Signals/ScreenCaptureMonitor.swift:62` · **Category:** dead-code · **DECISIONS checked:** 25

**What goes wrong.** Three places in the capture matcher say something the code doesn't do.

1. `CaptureSignatures.lowercased` (lines 60-69) is documented as 'computed once rather than on every poll'. It is a computed property, so `firstMatch` rebuilds every signature's lowercased copy on every 2 s poll.
2. `runningProcessNames`' comment (lines 121-124) says `proc_name` truncates names to sixteen characters. Measured on this Mac with the same calls, names reach 31 characters (e.g. 'Brave Browser Helper (Renderer)'), because `proc_name` copies `pbi_name` (2 x MAXCOMLEN). That is what `nameLimit` = 31 assumes. A maintainer who 'fixed' it to 16 would break the Teams helper match, which is a 30-character name. With the shipped JSON no candidate is longer than 31, so the truncated-prefix path is currently never reached.
3. The 'QuickTime Player screen recording' row (capture-signatures.json:18-24) can never change `isCaptured()`. The 'macOS screen recording' row (lines 39-45) matches the same `screencapture` process with no bundle requirement, and the matched signature's name is only read by tests.

**Suggested fix.** Make the lowercased signatures a `let` computed in init. Correct the comment to 31 characters and say where the limit comes from. Remove the QuickTime row, or fold its name into the generic one.

<details><summary>Verification (confirmed)</summary>

(1) `lowercased` is a computed `private var` (62-69), so firstMatch (81) rebuilds it on every call, which contradicts the 'computed once' comment. (2) Measured on this Mac with the same proc_listpids and proc_name calls: the longest names are 31 characters (for example 'Brave Browser Helper (Renderer)'), which matches nameLimit = 31. The 'sixteen characters' comment (123-124) is therefore wrong; 'Microsoft Teams (Screen Share)' is 30 characters and fits. (3) The QuickTime row requires com.apple.QuickTimePlayerX plus the screencapture process, while the later 'macOS screen recording' row matches screencapture with no bundle requirement, so the QuickTime row can never change isCaptured(). matchedSignature().name is read only by tests. These are comment and maintenance issues, so low.

</details>

### SIG-9 · low · A malformed capture-signatures.json silently turns off screen-share detection

**Where:** `Sources/movez/Signals/ScreenCaptureMonitor.swift:74` · **Category:** persistence · **DECISIONS checked:** 25

**What goes wrong.** CaptureSignature declares `var enabled: Bool = true` (line 14), and the comment beside it reads as if the field were optional. Swift's synthesized Decodable ignores property defaults, so an entry without "enabled" (or without "requireProcessName") throws keyNotFound for the whole file.

`bundled()` swallows that error with `try?` (lines 72-74), and `ScreenCaptureMonitor.init` falls back to zero signatures (line 102), with no log line. A one-line JSON edit can therefore disable capture detection entirely while every call site keeps working.

Only CaptureSignaturesTests would notice (lines 5-8), and its failure message says the file is 'missing from the bundle'. The movement library, by contrast, is fatal when malformed.

**Suggested fix.** Give CaptureSignature a custom `init(from:)` that uses `decodeIfPresent(...) ?? true` for `enabled` (and a sensible default for `requireProcessName`). Replace the `try?` with do/catch and log the error through MovezLog, as AppCoordinator.restore does.

<details><summary>Verification (confirmed)</summary>

Swift's synthesized Decodable decodes non-optional properties with decode, not decodeIfPresent, whatever the default value. So `var enabled: Bool = true` (line 14) and `requireProcessName` are both required keys. bundled() swallows the error twice with try? (72-74), and init falls back to an empty signature list (102) without logging. Today every JSON entry has both keys, so nothing is broken now; the risk is a future edit. CaptureSignaturesTests would fail, but with the misleading 'missing from the bundle' message. Low is right.

</details>


## 4. Library, Routine, Modes, Strength

### LIB-1 · medium · Movement micro-breaks ignore the difficulty cap

**Where:** `Sources/movez/Routine/MicroBreakBuilder.swift:57` · **Category:** correctness · **DECISIONS checked:** none (product brief §Settings difficulty cap; 41 refers to the default cap)

**What goes wrong.** The Difficulty cap setting (Beginner 1 / Moderate 2 / Advanced 3, SettingsViewModel.swift:104-106) is enforced for full breaks in RoutineBuilder.usable (RoutineBuilder.swift:109-110: `difficulty > cap` and the difficulty-3 unlock) and for Strength micro-breaks (StrengthMicroBuilder.swift:87). Movement micro-breaks never apply it. MicroContext (RoutineContext.swift:60-72) has no cap field, MovementModeBuilder.microBreak (MovementModeBuilder.swift:15-28) never passes one, and MicroBreakBuilder.candidates filters only on equipment, floor, requirements, exclusions and families. The shipped library tags 10 difficulty-2 movements as micro-eligible: FLX-05, STR-34, BAL-14 Tree pose, BAL-17 Eagle pose, BAL-18, BAL-20, BAL-23, BAL-26 Tandem stance with eyes closed, BAL-28 and HWF-10. Trigger: set the cap to Beginner. Then about one micro-break in six contains a difficulty-2 movement, usually one of the harder balance poses: 10 of the 79-movement pool can be the first pick, and more can be the second. A future difficulty-3 micro tag would also be served without its unlock.

**Suggested fix.** Add `difficultyCap` (default 2) and `unlockedDiff3` to MicroContext. Apply the same two checks as RoutineBuilder.usable inside `candidates`. Fill them in MovementModeBuilder.microBreak from settings.difficultyCap and history.unlockedDiff3. No golden micro context sets a cap and no micro movement is difficulty 3, so with the default of 2 the pool is unchanged and MovementPicksGoldenTests still passes. Add a MicroBreakBuilderTests case: with cap 1, no block has difficulty above 1. If ignoring the cap was intended, record that in DECISIONS.

<details><summary>Verification (confirmed)</summary>

MicroBreakBuilder.candidates (57-70) filters only on needsEquipment, requiresFloor, unavailable, excluded and family; MicroContext (RoutineContext.swift:61-72) has no cap or unlock field; MovementModeBuilder.microBreak (Routine/MovementModeBuilder.swift:15-28) never reads settings.difficultyCap. RoutineBuilder.usable:109-110 and StrengthMicroBuilder:87 do apply caps. I checked the JSON myself: 79 micro_eligible movements, and exactly the 10 listed are difficulty 2. None needs the floor, equipment or a requirement, so all 10 stay in a Beginner user's micro pool. No DECISIONS entry exempts micro-breaks from the cap, and the brief's cap is a general setting. Medium fits: a user's explicit setting is ignored, but the cost is a moderate balance pose, not harm.

</details>

### LIB-2 · medium · With kit at the default Beginner cap, every squat/lunge set (and every push set for a kettlebell-only user) is a light bodyweight move

**Where:** `Sources/movez/Strength/StrengthBreakBuilder.swift:27` · **Category:** correctness · **DECISIONS checked:** 71, 56, 69

**What goes wrong.** With any kit at the default Beginner cap (1), the vigorous rung is always let go for squat/lunge sets, and for push sets with a kettlebell only, because the library has no difficulty-1 vigorous move there. Those sets are light bodyweight moves. The ladder order matches DECISIONS 71, but 71's statements that light moves are warm-ups only with kit, and that the rule never has to let go, do not hold at cap 1. The simulation report's per-configuration relaxation table and the Swift vigorous test only cover caps 2 and 3, so nothing shows it.

**Suggested fix.** Decide which way it should go. Either reclassify a loaded squat and a loaded kettlebell push as difficulty 1, let the vigorous rule widen the cap for kit users, or amend DECISIONS 71 to say that at Beginner the cap wins. Then add the dbl configurations to per_config_relaxations, add a Swift test with kit at strengthDifficultyDefault, and add a cap-1 kit configuration to StrengthSimulationCrossCheckTests.

<details><summary>Verification (confirmed with corrections)</summary>

Mechanism confirmed. I dumped strength-library-v1.json: every vigorous SQT move is difficulty 2 or higher (SQT-04/05/06/08/10/12/17/18), so at cap 1 there is no difficulty-1 vigorous squat. No PSH move lists a kettlebell, and PSH-04 is the only vigorous bodyweight push, at difficulty 2. StrengthDraw.pick (StrengthContext.swift:110-138) lets breakLimits, then servedToday, then vigorous go until the pool has something in it. It takes back only the rungs before the last one, so vigorous stays let go and the draw serves SQT-01/03/07/09/16. strengthDifficultyDefault is 1 (SettingsStore.swift:53). per_config_relaxations renders only the 20 cap-2/3 configurations (docs/strength-simulation.md lines 138-159 have no dbl rows). testWithKitEveryWorkingSetIsVigorous uses everythingContext, which is cap 3. Severity lowered because the ladder order is exactly what DECISIONS 71 prescribes ('it goes before the exclusions and the difficulty cap'). Respecting the Beginner cap is a defensible outcome. The real defect is that 71's other claims ('light bodyweight moves are warm-ups only', 'never had to let go') are false at the default cap, and neither the report nor the tests show it. That is a product or decision gap, not broken behaviour.

</details>

### LIB-3 · low · The loader is strict about data the app never reads and does not check a stale list

**Where:** `Sources/movez/Library/LibraryLoader.swift:30` · **Category:** dead-code · **DECISIONS checked:** 41, 50

**What goes wrong.** The loader demands exact counts (9 routines, 8 micro routines, 3 presets) for collections no production code reads. So any edit to those worked examples in the JSON fails LibraryTests, and would fail launch if shipped untested. The presets duplicate SchedulerConfig.from(preset:), so editing them in the JSON has no effect. micro_break.eligible_ids is never decoded and is stale: it is missing 14 movements tagged micro_eligible. The JSON contradicts itself and nothing checks it.

**Suggested fix.** Drop the hard counts for routines, micro routines and presets, keeping the dangling-id checks. Either read the presets from the library or add a test that SchedulerConfig agrees with the JSON. Decode `eligible_ids` and require it to equal the tagged set, then fix the JSON; or delete the list from the JSON.

<details><summary>Verification (confirmed with corrections)</summary>

The facts check out. Expected 9/8/3 is checked at :133-148. Nothing outside the loader reads routines, microRoutines or presets in Sources, though tests do (LibraryTests:40 uses library.resolve). SchedulerConfig.from(preset:) hard-codes 25/55/85 (SchedulerConfig.swift:56-80). micro_break.eligible_ids is not decoded and lacks the 14 listed ids; I verified 65 vs 79 and the exact set. However, 'a library revision stops the app from starting' overstates it. The JSON is the developer's own file, bundled from the repo root (DECISIONS 50), and LibraryTests loads it, so a trimmed collection fails `make test` long before it ships. The real issues are strictness about unused data and the self-contradicting eligible_ids list.

</details>

### LIB-4 · low · The strength loader's structural checks are untested, and the meter-dose test skips the arm buckets

**Where:** `Sources/movez/Library/StrengthLibrary.swift:93` · **Category:** test-gap · **DECISIONS checked:** 41, 70

**What goes wrong.** How it works: StrengthLibraryLoader.validate refuses a file with the wrong mode, a total other than 151, a bucket declared twice or with a wrong count, an id whose prefix does not match its bucket, a micro-eligible move outside END, or a micro pool other than 41 (lines 79-145). These are what stop a bad JSON edit from mis-filing a move into the wrong pattern's no-repeat rules. StrengthLibraryTests covers only truncation, duplicate ids, an unknown overlap, a non-vigorous equipment move and a missing file. A refactor that dropped, say, the prefix check would pass. Separately, StrengthBreakBuilderTests.testEveryOtherRepDoseHasAMeter lists only [.sqt, .hng, .psh, .pul, .cor] (line 417), so the BIC/TRI doses added for the arm break (DECISIONS 70) are never checked for meter parsing. I checked them by hand and they all parse today.

**Suggested fix.** Add mutatedCopy tests for the mode, total, bucket-count, misfiled-prefix and micro-pool branches. Add .bic and .tri to the `working` set in testEveryOtherRepDoseHasAMeter.

<details><summary>Verification (confirmed)</summary>

validate and validateMovements check mode, the total of 151, buckets declared once with their counts, the vigorous rule, the id-prefix match (bucket is decoded from its own field, StrengthMovement.swift:52/73, so the prefix check is meaningful) and the micro pool. StrengthLibraryTests covers truncation (a decoding error, not the count check), duplicate ids, an unknown overlap, a non-vigorous equipment move and a missing file only, so the mode, count, bucket, prefix and micro-pool branches are untested. StrengthBreakBuilderTests:417 lists working = [.sqt, .hng, .psh, .pul, .cor] without .bic and .tri.

</details>

### LIB-5 · low · The micro-break timeline is written four times with two lead-in constants

**Where:** `Sources/movez/Modes/ModeBuilder.swift:96` · **Category:** duplication · **DECISIONS checked:** 30, 39, 67

**What goes wrong.** The rule is: a block appears after the earlier blocks' lead-ins and seconds, and starts moving 5 s later. That rule is written out in four places. (1) MicroBreak.totalSeconds/appearsAt/startsAt/blocksRun (Routine.swift:62-85). (2) Again by hand in PlannedMicro.partsRun's strength branch (ModeBuilder.swift:96-106), using StrengthTiming.leadInSeconds. (3) StrengthMicroBreak.totalSeconds (StrengthBreak.swift:224). (4) The panel's MicroPanelBreak (MicroPanelBreak.swift:36-48), which uses Routine.leadInSeconds even for strength moves. Both constants are 5 today. But StrengthTiming says its values live 'in one place so that they can be tuned together'. If StrengthTiming.leadInSeconds became 8, the panel would run a two-move strength micro for 70 s while StrengthMicroBreak and partsRun count 76 s. History would then credit the moves against a timeline the user never saw. The strength branch of partsRun also has no test: CoordinatorSimulatedDayTests.swift:298-309 runs in Movement mode and compares the recorded completions with partsRun itself.

**Suggested fix.** Extract one `MicroTimeline(blockSeconds:leadIn:)` value with appearsAt, startsAt, total and indicesRun(seconds:). Both micro types and MicroPanelBreak should build it, with MicroPanelBreak carrying the source's lead-in. Add a Strength-mode test that skips a two-move micro at 40 s and expects only the first move recorded.

<details><summary>Verification (confirmed)</summary>

The timeline appears in Routine.swift:62-85, ModeBuilder.swift:96-106 (StrengthTiming.leadInSeconds), StrengthBreak.swift:223-225, and MicroPanelBreak.swift:36-48 (Routine.leadInSeconds even for strength moves). Both constants are 5 (Routine.swift:32, StrengthBreak.swift:21), so nothing is wrong today. The risk is divergence if one constant changes. The test gap holds: the only partsRun test, CoordinatorSimulatedDayTests:298-309, runs the default Movement harness and checks completions against partsRun itself. StrengthEdgeTests:96-123 runs a strength micro but checks only the mode, not what was recorded. This is maintainability, low.

</details>

### LIB-6 · low · Strength heads-up tells bodyweight-only users to have their weights nearby

**Where:** `Sources/movez/Modes/PlannedBreak.swift:70` · **Category:** correctness · **DECISIONS checked:** 56

**What goes wrong.** HeadsUpAnnouncement.fixedBody returns the design's fixed sentence, 'About 5 minutes, three sets. Have your weights nearby.', for every strength break. DECISIONS 56 makes confirming the setup with nothing ticked a valid choice that means bodyweight only, and the strength builder then draws only bodyweight moves. So that user reads 'Have your weights nearby' before every strength break of every day. `init(_ planned:)` already has the StrengthBreak in hand and could tell the two cases apart.

**Suggested fix.** Make the case `.strength(loaded: Bool)` with `loaded = sets.contains { !$0.movement.isBodyweight }`, and give the unloaded case a bodyweight sentence. That needs a copy decision from the design, for example 'About 5 minutes, three sets.' Update StrengthPanelTests and the snapshot fixture.

<details><summary>Verification (confirmed)</summary>

fixedBody returns the same sentence for every strength break. It is the design's copy (design/HANDOFF.md:218), which was written without the bodyweight-only case that DECISIONS 56 later allowed ('may be pressed with nothing ticked, which means bodyweight only'). init(_ planned:) has the StrengthBreak, and StrengthMovement.isBodyweight exists (StrengthMovement.swift:83). This is a copy gap needing a design decision, not a logic bug, so low.

</details>

### LIB-7 · low · MicroBreakBuilder can return a micro-break with no movements

**Where:** `Sources/movez/Routine/MicroBreakBuilder.swift:38` · **Category:** correctness · **DECISIONS checked:** 32, 45

**What goes wrong.** When the pool is empty, the builder relaxes only `usedMovementIdsToday` (lines 31-36). The last micro, the next full break, the exclusions and the requirements all stay. If those still cover every micro-eligible movement, `choose` returns nil and the builder returns `MicroBreak(blocks: [])`. The coordinator shows it anyway, because beginMicro runs on `.showMicroCountIn`. The count-in title becomes ' in a moment', since movementName is empty. Then beginMicroRunning sets totalSeconds to 0, the next tick calls microEnded, and the scheduler's endMicro from `.microRunning` plays the completion chime. So the user hears two chimes around an empty panel. Trigger: the user excludes all but a few micro-eligible movements in Browse library, and those few are in the last micro-break or the next full break. RoutineBuilder has a last-resort ladder for the same situation (relaxedCandidates, and LaunchStateTests covers excluding everything), but the micro builder has none.

**Suggested fix.** Extend the ladder. Drop usedToday first (as now), then lastMicroMovementIds and nextFullRoutineIds, then either the exclusions (matching RoutineBuilder rung 2) or have the coordinator skip a micro-break that has no blocks. Add a test where all but two micro movements are excluded and both are in lastMicroMovementIds.

<details><summary>Verification (confirmed)</summary>

Only usedMovementIdsToday is relaxed (31-36). If choose() returns nil, the builder returns MicroBreak(blocks: []). beginMicro (AppCoordinator+Effects.swift:200-204) stores it without checking for emptiness. MicroPanelBreak.totalSeconds becomes 0, so after the count-in PanelViewModel.beginMicroRunning sets totalSeconds 0 and the next tick sends microEnded. If the scheduler is in microRunning by then, endMicro adds .chime(.completion) (Scheduler+Actions.swift:209). No MicroBreakBuilderTests case covers an exhausted pool. The trigger needs the user to exclude nearly all 79 micro movements, so it is rare but reachable through Browse library, and low is right. I did not fully trace the exact chime sequence; the empty panel is certain.

</details>

### LIB-8 · low · After a relaunch, Movement mode forgets skipped breaks and can rebuild the identical routine

**Where:** `Sources/movez/Routine/MovementModeBuilder.swift:11` · **Category:** persistence · **DECISIONS checked:** 32

**What goes wrong.** The full-break seed is `seed(dayKey, breakIndexToday)`, and breakIndexToday is `breaksToday.count`. `breaksToday` (AppCoordinator.swift:114-116) is an in-memory array. Only rememberBreak appends to it, and nothing restores it at launch. Two other inputs depend on it too. idsServedToday (AppCoordinator+Effects.swift:317-320) uses it to remember breaks that were put on screen but not completed, and routineContext reads usedStrRegionsLastBreak from its last element. After any relaunch (an update, a crash, a login), the index starts again at 0, a skipped break's movements no longer count as served, and the consecutive-strength-region rule loses its memory. Concrete case: on the 25/5 preset (no micro-breaks), the 10:00 break is skipped at its first movement, so history has no completions. The app is relaunched at 10:10. The 10:30 break is then built from exactly the 10:00 context (same dayKey, index 0, same history, same recency), so it is the identical five movements the user just skipped. That breaks DECISIONS 32. SeededRandom.swift:5-7 claims 'a relaunch mid-day regenerates exactly the same routine', but that holds only for the first break of the day. StrengthModeBuilder.seedIndex (StrengthModeBuilder.swift:101-106) reads its index from history specifically to avoid this.

**Suggested fix.** Derive Movement's index from `history.breaks(on: now)` (absences excluded), as Strength does. If turned-away breaks must stay 'served', store the served movement ids on BreakRecord or persist breaksToday's ids with the snapshot. This changes real-world Movement picks, though not the golden fixture, which builds contexts directly, so add a DECISIONS entry. At minimum, correct the SeededRandom doc comment.

<details><summary>Verification (confirmed)</summary>

breakIndexToday (AppCoordinator+Effects.swift:333-336) returns breaksToday.count. breaksToday (AppCoordinator.swift:116) is in-memory only: it is appended only in rememberBreak (:338, called from beginBreak :113), cleared in rollDayIfNeeded, and never restored. idsServedToday (:317-320) unions breaksToday's ids, and usedStrRegionsLastBreak (:302) reads breaksToday.last. history.usedMovementIds reads only completions, and Recency.weight returns 0 for daysAgo 0, so a break skipped before any part completes leaves no trace in history. After a relaunch the seed (day, 0) and the context match the first build, so the same routine comes back. StrengthModeBuilder.seedIndex (:101-106) reads history explicitly 'so that it is the same after a relaunch'. The SeededRandom comment at :5-7 overstates the guarantee. This conflicts with DECISIONS 32 for skipped breaks.

</details>

### LIB-9 · low · Production code that only tests reach

**Where:** `Sources/movez/Routine/Routine.swift:88` · **Category:** dead-code · **DECISIONS checked:** 54, 55

*Found independently by the Tests: library, routine, strength, modes, UI review as well.*

**What goes wrong.** MicroBreak.eyebrow(for:), both regionWord(for:) and plainRegionWords (Routine.swift:87-121) built the old 'MICRO-BREAK · SHOULDERS' eyebrow, which DECISIONS 55 replaced with the mode badge. Only MicroBreakBuilderTests.swift:152-166 and LibraryTests.swift:306 call them. MovementLibrary.byRegion and byBucket (MovementLibrary.swift:56-68) have no callers at all, and defaultPreset, preset(id:) and resolve(_:) are called only from tests. DesignRules.minBlockSeconds and maxBlockSeconds (LibraryMetadata.swift:29-30) are unused. RoutineContext.date (RoutineContext.swift:41) is set by the coordinator but no builder reads it. MicroContext.equipment (RoutineContext.swift:66) is set but ignored, because MicroBreakBuilder rejects every equipment movement. ModeDefinition.libraryKind (ModeDefinition.swift:41) is never read: AppDelegate loads both libraries by their loaders and ModeBuilderTable.standard wires them to builders, so the 'its library' of DECISIONS 54 lives in the table, not in the definition. RoutineValidator is used only by tests but is compiled into the app.

**Suggested fix.** Delete these, together with the tests that only exercise them. Removing RoutineContext.date means editing GoldenContexts.fullContexts, which sets it, but not the fixture file. For libraryKind, either delete it or have Launch load each mode's library through its definition. Consider moving RoutineValidator into the test target.

<details><summary>Verification (confirmed with corrections)</summary>

Mostly confirmed. eyebrow/regionWord/plainRegionWords (Routine.swift:88-121), byRegion and byBucket (MovementLibrary.swift:56-68), defaultPreset, preset(id:) and resolve(_:) (:70-83), DesignRules.minBlockSeconds and maxBlockSeconds (LibraryMetadata.swift:29-30), RoutineContext.date (set at AppCoordinator+Effects.swift:300, never read) and MicroContext.equipment (set, never read by MicroBreakBuilder) have no production readers, and RoutineValidator is referenced only from tests. DECISIONS 55 replaced the region eyebrow. One correction: ModeDefinition.libraryKind is not entirely unread. It takes part in ModeDefinition's == (ModeDefinition.swift:80) and is set in SnapshotFixtures:533 and :544. No behaviour reads it, though, so the point stands. The eyebrow function begins at line 88; line 87 is its doc comment.

</details>

### LIB-10 · low · Substitutions only reorders the candidate pool; it never changes what can be drawn

**Where:** `Sources/movez/Routine/RoutineBuilder.swift:76` · **Category:** complexity · **DECISIONS checked:** 23e, 28

*Found independently by the Tests: library, routine, strength, modes, UI review as well.*

**What goes wrong.** `candidates` swaps each equipment movement the user does not own for its bodyweight peer (`Substitutions.resolve`). But every peer is itself a bodyweight movement in `library.movements`. Each peer therefore reaches the pool on its own iteration with the same `usable` verdict, and the `seen` set drops the duplicate. The pool's members are the same with or without Substitutions. The only effect is that a peer can be inserted at the earlier position of the equipment movement it replaces. I mirrored the code for all 16 combinations of owned equipment: the set was identical every time and the order differed in 12. Because the draw is weighted over the pool, order changes which movement a given seed lands on but not the odds. Substitutions.swift (74 lines) and SubstitutionsTests implement the brief's 'equipment movements are substituted with their bodyweight peers', which has had no effect since template slots gave way to pooled draws (23e, 28). The comments at RoutineBuilder.swift:68-70 and Substitutions.swift:3-13 describe a swap that never happens: the equipment movement is simply left out.

**Suggested fix.** Smallest change: rewrite the comments to say that an unowned equipment movement is dropped and the resolve call is kept only so seeded picks stay as recorded. Cleaner: remove the resolve call and Substitutions. That reshuffles seeded picks, MovementPicksGoldenTests will fail, and the fixture is never re-recorded, so it needs a deliberate DECISIONS entry.

<details><summary>Verification (confirmed)</summary>

Substitutions.resolve returns the original movement, or a peer from bodyweightPeers, which always comes from library.movements with !needsEquipment. usable() for that peer does not depend on which iteration produced it, so the peer also enters on its own iteration with the same verdict, and `seen` dedupes by id. An unresolved unowned movement fails usable's equipment check. So the pool's members are identical with or without substitution; only order changes. pick() weights each option independently of position, so the odds are unchanged too. The comments at RoutineBuilder.swift:68-70 and Substitutions.swift:3-13 describe a swap that has no effect. No DECISIONS entry covers it (28 only replaces the slot shape).

</details>

### LIB-11 · low · relaxedCandidates' last rung can never run, and it tightens the pool

**Where:** `Sources/movez/Routine/RoutineBuilder.swift:100` · **Category:** dead-code

**What goes wrong.** Rung 3 runs only if rung 2 (exclusions cleared, today forgotten) is still empty. At that point the only filters left are owned equipment, floor/wall/stairs and difficulty. 75 movements pass even the strictest combination (cap 1, all three requirements off, no equipment), so with the shipped library rung 3 is unreachable. The golden context `used-all-excluded-all` returns at rung 2. If rung 3 ever did run, `relaxed.equipment = []` would remove the user's owned-equipment movements instead of adding any. That is the opposite of the 'Everything off' its comment promises.

**Suggested fix.** Delete rung 3. If it is kept for test libraries, set `relaxed.equipment = Set(Equipment.allCases)` and say so in the comment. No golden context reaches it, so the fixture is unaffected.

<details><summary>Verification (confirmed)</summary>

I checked the JSON: 75 movements have no equipment, no requires, and difficulty 1. Rung 2 (exclusions cleared, today forgotten) never comes back empty for any settings, so rung 3 (:96-101) is unreachable with the shipped library. No test reaches it: there is no relaxedCandidates call and no custom library in RoutineBuilder tests. If it did run, `relaxed.equipment = []` would drop owned-equipment movements that the raised cap had just admitted, the opposite of what its comment says. It is dead and latently inverted, so low.

</details>

### LIB-12 · low · The warm-up shape is let go as one block, so a floor warm-up is served even when a standing one is left

**Where:** `Sources/movez/Strength/StrengthBreakBuilder.swift:71` · **Category:** correctness · **DECISIONS checked:** 58

**What goes wrong.** When the warm-up shape rung is let go, every bodyweight move in the pattern becomes equally eligible, however many of the shape's four parts it breaks. A move that breaks three parts (HNG-02: floor, difficulty 2, per-side) is drawn as readily as one that breaks only the floor rule (HNG-01). This is milder than 'never relaxed further than it has to be' suggests.

**Suggested fix.** When .warmUpShape is let go, narrow the pool part by part with StrengthDraw.preferring, as the break limits do, in an order you choose and record in DECISIONS 58 (for example difficulty 1, then two-sided, then off the floor). Mirror it in simulate_strength.py.

<details><summary>Verification (confirmed with corrections)</summary>

Mechanism confirmed. Once .warmUpShape is let go, the slot rule is just isBodyweight (line 71). No narrow step keeps parts of the shape, unlike the break limits (lines 89-96). HNG-07 is indeed the only shaped hinge move. Lowered and reframed because the 'standing one left' framing assumes off-the-floor outranks difficulty-1 and two-sided, and DECISIONS 58 does not rank them. HNG-12, the standing alternative, breaks two parts (difficulty 2 and per-side). HNG-01/15/16 break only one (floor). A 'keep as many parts as possible' narrowing would therefore still pick floor moves. At the default cap 1 there is no standing alternative at all. The genuine issue is smaller: the pool is uniform over moves that break one to three parts. HNG-02, which is floor, difficulty 2 and per-side, is as likely as HNG-01.

</details>

### LIB-13 · low · The strength focus ×3 weights the warm-up and cool-down too, though DECISIONS 63 and the code comment say working sets only

**Where:** `Sources/movez/Strength/StrengthBreakBuilder.swift:192` · **Category:** correctness · **DECISIONS checked:** 63

**What goes wrong.** The focus ×3 weight applies to the warm-up and the END cool-down as well as the working sets. That matches the builder's header comment and the body of DECISIONS 63, but contradicts that entry's title and the StrengthContext.boostedRegions comment ('in a working set's draw'). In practice the legs, back-and-shoulders and core foci tilt which END stretch closes a break. More arms barely does, since only one END move is Wrist/Forearm.

**Suggested fix.** Decide which is intended. If 'working set only', pass focus × recency only for `.set` slots and change the Python to match. Otherwise fix DECISIONS 63's title and the StrengthContext comment to say every draw of a strength break.

<details><summary>Verification (confirmed with corrections)</summary>

Confirmed that the single weight closure (188-194) feeds the warm-up, set and cool-down draws, and that the Python matches (simulate_strength.py:428-431). The sources disagree with one another, though. The builder's own header (lines 16-17) and the body of DECISIONS 63 ('every draw is weighted by recency, and a move in a focused region weighs three times as much') describe every draw. Only DECISIONS 63's title and the StrengthContext.swift:38 comment say 'working set'. The More arms example is weak: of 41 END moves only one is Wrist/Forearm, and none is Arm. The tilt is real for More legs and glutes, More back and shoulders and More core, whose regions (Quad, Ham, Glute, Adductor, T-spine, Shoulder, L-spine/Core) many END cool-downs carry.

</details>

### LIB-14 · low · A strength break that crosses midnight is filed under the next day, which then repeats the previous day's letter and has no core set

**Where:** `Sources/movez/Strength/StrengthDayPlanner.swift:231` · **Category:** correctness · **DECISIONS checked:** 57, 20a, 20c

**What goes wrong.** A strength break planned before midnight and finished after it is recorded on the next calendar day. The planner then fixes that day's letter to the previous day's and counts it as that day's first break, so the patterns repeat and that day's core-carrying first break is skipped. This only happens with working hours that run past midnight; the default 9 to 6 never triggers it.

**Suggested fix.** Store the day a break was planned for, or its start time, on `BreakRecord`. For example, add an optional `planDay` that falls back to `at`'s day for older records, and key `strengthDays(in:)` by it.

Add a `StrengthDayPlannerTests` case with an A record at 00:04 that belongs to the previous day.

<details><summary>Verification (confirmed with corrections)</summary>

Mechanism confirmed. strengthDays keys each record by DayKey.key(for: record.at). letter(for:) (line 237) takes the day's first record. finishBreak writes BreakRecord(at: clock.now) when the break ends (AppCoordinator+Effects.swift:130-131), while the plan was fixed at the heads-up (attachingBreak). A record finished after midnight therefore lands on the next day, fixes that day's letter to the previous day's, and makes completedToday 1. Severity lowered because the default working hours are .standard, 9 to 6 on weekdays (WorkingHours.swift:47, SettingsStore.swift:115). The trigger needs custom hours that span midnight and a break running across it. The effect is one repeated letter and one missed core set, then it self-corrects.

</details>

### LIB-15 · low · After a mode switch, a strength micro-break ignores the previous micro-break's regions

**Where:** `Sources/movez/Strength/StrengthMicroBuilder.swift:103` · **Category:** correctness · **DECISIONS checked:** 67

**What goes wrong.** `regions(of:)` resolves ids only through the strength library (`library.movement(id:)`). The coordinator's `lastMicroIds` holds whatever the last micro-break served, in either library (AppCoordinator+Effects.swift:208), and is passed straight in (StrengthModeBuilder.swift:55).

**Concrete trigger.** A Movement micro-break works the shoulders (FLX ids). The user switches to Strength, and the next strength micro-break is built with `previousRegions` empty, so it can serve a shoulder END move right after. DECISIONS 67 says a micro-break shares no region with the previous one.

Both libraries share the `Region` enum, so the information is available. The Movement micro builder has the same blind spot the other way round.

**Suggested fix.** Put regions rather than ids into the micro contexts (for example `lastMicroRegions`), computed in the coordinator from whichever library knows each id.

<details><summary>Verification (confirmed)</summary>

regions(of:) resolves ids only through library.movement(id:) (line 103-105). coordinator.lastMicroIds is set from whatever micro-break ran last (AppCoordinator+Effects.swift:208) and is passed straight in (StrengthModeBuilder.swift:55). Movement-library ids such as FLX-xx resolve to nil, so previousRegions is empty on the first strength micro-break after a switch. That breaks DECISIONS 67's 'shares no region with the previous one' once per switch. The impact is minimal and one-off.

</details>

### LIB-16 · low · Cool-down, end-range and lone micro-break blocks show a dose that contradicts their timer

**Where:** `Sources/movez/Strength/StrengthSessionTimeline.swift:112` · **Category:** correctness · **DECISIONS checked:** 58, 59

*Found independently by the Tests: library, routine, strength, modes, UI review as well.*

**What goes wrong.** **How the dose gets on screen.** The cool-down segment carries `dose: coolDown.movement.dose` (line 112), and end-range blocks carry `block.movement.dose` (line 125). The view model prints it via `DoseText`.

**Where the timer differs.** These blocks are timed by the builder, not by the library dose:
- the cool-down runs 30 s, so 15 s a side
- an end-range block runs 60 s
- a micro-break move with no partner runs the whole minute

**Concrete examples.**
- END-01 or END-39 ('25 s/side') or END-32 ('30 s/side') as a cool-down reads '25 s each side' or '30 s each side'. The disc switches sides after 15 s.
- END-07, END-16 or END-37 ('30 s') in an end-range break read '30 s' over a 60-second countdown.

The user sees two different instructions on one card.

**Suggested fix.** For blocks the builder times (cool-down, end-range, micro), derive the shown dose from the block's seconds when the library dose is a time ('15 s each side', '60 s'), or omit timed doses. Rep doses such as '6/side' can stay.

<details><summary>Verification (confirmed)</summary>

The cool-down segment uses dose: coolDown.movement.dose (line 112) and end-range blocks use block.movement.dose (line 125). StrengthOverlayViewModel.fillBody renders DoseText(shown.dose) (line 247). coolDownSeconds is 30 and endRangeBlockSeconds is 60 (StrengthBreak.swift:19, 23). The library has END-01/39 at '25 s/side', END-32 at '30 s/side', and END-07/16/37 at '30 s' with block_seconds 30. So a cool-down card can read '25 s each side' while the disc switches sides at 15 s, and an end-range card can read '30 s' over a 60 s countdown.

</details>

### LIB-17 · low · Strength APIs that only tests use, or nothing uses

**Where:** `Sources/movez/Strength/StrengthUnlock.swift:28` · **Category:** dead-code

**What goes wrong.** Several pieces of the Strength code have no production caller:
- `StrengthUnlock.unlockedDiff3` is called only by StrengthUnlockTests. The builders filter by `unlockedBuckets`.
- `StrengthSessionTimeline.isLeadIn(at:)` (StrengthSessionTimeline.swift:201) is test-only. The view model shows 'REST' for the whole rest and never asks it.
- `StrengthDose.perSide` and `StrengthDose.hasMeter` (StrengthBreak.swift:43, 67) are never read. `StrengthSet` takes `movement.perSide` instead, so a library row whose `per_side` disagreed with a '/side' dose would go unnoticed.
- `StrengthBreak.workedRegions` (StrengthBreak.swift:192) is used only by tests. The builder recomputes the same set inline at StrengthBreakBuilder.swift:106.

Each one is a second definition that can drift from the real one.

**Suggested fix.** Delete `unlockedDiff3` and `isLeadIn(at:)`, or move them into the test target. Either use `StrengthDose.perSide` in the loader to check it against `per_side`, or remove it along with `hasMeter`. Have the builder use `workedRegions`.

<details><summary>Verification (confirmed)</summary>

Grep confirms each one. StrengthUnlock.unlockedDiff3 is called only from StrengthUnlockTests; production uses unlockedBuckets (StrengthModeBuilder.swift:109). StrengthSessionTimeline.isLeadIn(at:) (line 201) is called only from StrengthTimelineTests. StrengthDose.perSide and StrengthDose.hasMeter (StrengthBreak.swift:43, 67) are never read: StrengthSet takes movement.perSide (line 108), tests use StrengthSet.hasMeter, and RepPacerTests reads only reps and holdSeconds. StrengthBreak.workedRegions (line 192) is used only in tests, and the builder recomputes the same set inline at StrengthBreakBuilder.swift:106. This is real dead or duplicate code, which the user asked about.

</details>


## 5. UI

### UI-1 · high · A resumed Movement break replays its finished blocks and writes them to history a second time

**Where:** `Sources/movez/UI/Overlay/OverlayEffectSink.swift:87` · **Category:** correctness

*Found independently by the App + History + Notice + Settings + FocusFilter + Audio review as well.*

**What goes wrong.** When a break the lid closed on resumes, `beginBreak` rebuilds `currentBreak` with the old `blockIndex` and `completedBlocks` and a start backdated by the time already run (AppCoordinator+Effects.swift:98-108, Scheduler+Sleep.swift:144). `presentRoutine` never passes `blockIndex` to the new `OverlayViewModel` (lines 74-86). The view model starts at block 0 with `blockStartedAt` set to the backdated start. On its first tick the catch-up loop (OverlayViewModel.swift:182-185) walks through every block whose planned end has passed. Each step calls `onBlockCompleted` and plays a transition chime. The sink throws the index away (`{ block, _ in coordinator?.recordOverlayBlock(block) }`). Unlike `recordOverlayPart(index:)`, which the strength path uses, `recordOverlayBlock` has no guard against an index already recorded (AppCoordinator+Intents.swift:81-87 vs 97-105). Concrete case: blocks 1-2 finish on their clocks, the lid closes at 140 s, the break resumes at 230 s. The first tick plays two chimes together and writes two more `MovementCompletion` rows for the same routine id, and `completedBlocks` goes 2 → 4. Running on to the end makes it 7 for a 5-block break. A Skip after resuming records 'skipped, 4 of 5 done' (`max(completed, current.completedBlocks)`, AppCoordinator+Effects.swift:147). The duplicate rows are summed into `recencyScores` (HistoryStore.swift:210-216), which weights those movements down twice from tomorrow. They also count toward the difficulty-3 unlock (HistoryStore.swift:263-265). A second problem comes from replaying by time rather than by where the user was: someone who pressed Next twice early is put back onto blocks they already did. The strength path does this too: its records are deduplicated, but sets ended early with Done are shown again. The existing resume test (ReviewFixTests.swift:158-178) advances with `coordinator.nextBlock()`, which production never calls, so it never exercises the overlay view model.

**Suggested fix.** Pass the block index through: `viewModel.onBlockCompleted = { _, index in coordinator?.recordOverlayPart(index: index) }`. A movement routine's `planned.parts` are its blocks, so the existing guard (`index >= current.completedBlocks`) drops replays. Better still, start a resumed view model at `session.blockIndex`: add an init parameter that sets `blockIndex`, `completedBlocks` and `blockStartedAt`, so there is nothing to replay and no burst of chimes. Do the same for the strength timeline. Add a coordinator test that builds a real `OverlayViewModel` for the resumed session, like `testAResumedStrengthBreakRecordsEachPartOnceInOrder` does for strength.

<details><summary>Verification (confirmed)</summary>

beginBreak rebuilds the resumed session with the old blockIndex and completedBlocks, and with plan.startedAt set to now - elapsed (AppCoordinator+Effects.swift:98-108, Scheduler+Sleep.swift:144-147). presentRoutine passes only startedAt to OverlayViewModel, which starts at blockIndex 0 with blockStartedAt = startedAt (OverlayViewModel.swift:33, 87). The tick's while loop (182-185) calls advance(recordCompletion: true) for every block whose planned end has passed. Each step fires onBlockCompleted and plays .transition (265, 278). The sink drops the index and calls recordOverlayBlock, which has no dedupe: it always appends a MovementCompletion and does completedBlocks += 1 (Intents.swift:81-87). recordOverlayPart has the index guard (97-105). HistoryStore.record(completion:) appends without a check (139-142). recencyScores sums every row (207-217) and unlockedDiff3 counts every row (263-265). The skip record uses max(completed, current.completedBlocks) (Effects.swift:147). ReviewFixTests.swift:158-178 drives coordinator.nextBlock() and never builds an OverlayViewModel. The strength test (StrengthCoordinatorTests.swift:470) does, which is why only the strength path is covered.

</details>

### UI-2 · high · Idle display sleep takes the overlay down mid-break, because nothing keeps the display awake during a break

**Where:** `Sources/movez/UI/Overlay/OverlayWindowController.swift:52` · **Category:** macos-edge · **DECISIONS checked:** 38 (lid close and lock interrupting a break is intended; idle display sleep during a break is not covered by any entry)

*Found independently by the App + History + Notice + Settings + FocusFilter + Audio review as well.*

**What goes wrong.** During a full break the user is meant to step back and move, so nobody touches the keyboard or trackpad for minutes. `present(_:)` (lines 52-62) creates the windows, key monitor, screen observer and tick timer. It takes no power assertion: there is no `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep…)` or `ProcessInfo.beginActivity(.idleDisplaySleepDisabled)` anywhere in Sources. So the system's display-sleep timer keeps counting. When it fires, `PowerMonitor` maps `screensDidSleepNotification` to `.sleep` (Signals/PowerMonitor.swift:30). `Scheduler.handleSleepOrLock` stores an `InterruptedBreak` and `dismissSurfaces` emits `.endFullBreak(.interrupted)` (Scheduler+Idle.swift:206-207). `OverlayEffectSink` then removes the overlay at once (OverlayEffectSink.swift:19-21). Concrete trigger: a MacBook on battery, whose default 'turn display off when inactive' is 2 minutes, with the user idle since the heads-up. The display sleeps 1-2 minutes into a 5:25 Movement break or a ~5 min strength break. With 'require password' on, the screen also locks. The user wakes the display to read the next movement and finds the desktop. The overlay comes back only after the 60 s wake-quiet minute, and only if that is still before the break's planned end (Scheduler+Sleep.swift:124, 144-147). Otherwise the break is judged with the hard-coded `completedBlocks: 0, totalBlocks: 0` (Scheduler+Sleep.swift:34-35). An elapsed time under 162 s counts it as a skip (skipsToday +1) and writes no break record. Every such resume also hits the replay bug in the next finding.

**Suggested fix.** Take a display-sleep power assertion in `OverlayWindowController.present`. One way is `ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Movement break on screen")`, stored next to `tickTimer`. Release it in `dismiss` and `finishDismiss`. A real lid close or a manual lock still interrupts the break, as entry 38 intends. Only idle display sleep stops being one. Record the choice in DECISIONS.

<details><summary>Verification (confirmed)</summary>

grep for IOPMAssertion/beginActivity/idleDisplaySleep in Sources finds nothing. PowerMonitor.swift:30 maps screensDidSleepNotification to .sleep. Scheduler.swift:54 sends that to handleSleepOrLock, which stores an InterruptedBreak with completedBlocks: 0, totalBlocks: 0 (Scheduler+Sleep.swift:30-36), and dismissSurfaces returns .endFullBreak(.interrupted) for .fullBreak (Scheduler+Idle.swift:206-207). OverlayEffectSink.isGraceful(.interrupted) is false, so the overlay is dismissed at once. The scheduler deliberately does not treat idle during a full break as an absence (interruptibleByIdle), which shows that a user standing still during a break is expected. Display sleep is the one thing that still ends the break. Resume goes through endAbsence (Scheduler+Idle.swift:74-78), then resumeInterruptedBreak, which only resumes before plannedEnd and otherwise judges the break with 0/0 blocks (Sleep.swift:124-140). Entries 20 and 38 cover a closed lid or a lock, not idle display sleep. On battery, macOS turns the display off after a short idle (2 min by default), so this hits most breaks the user does not touch.

</details>

### UI-3 · medium · VoiceOver reads every Settings switch as just "On" or "Off", with no name

**Where:** `Sources/movez/UI/DesignSystem/Controls.swift:23` · **Category:** correctness

**What goes wrong.** MovezToggle is a Button drawn to look like a switch. Its only accessibility is `.accessibilityLabel(isOn ? "On" : "Off")` plus `.isButton`. The label is what VoiceOver uses as the control's name, so it says "On, button", and nothing says which setting it is. SettingsRow (SettingsView.swift:303-333) puts the row's text in a separate element and does not combine it with the control. None of the call sites adds a label either: SettingsView.swift:149, 178-184, 216-219 and the rest, including the library browser's per-move switches. The switch also has no toggle meaning for VoiceOver: there is no .isToggle trait and no accessibilityValue, so flipping it sounds like a button being renamed. SelectField already solves the same problem with `accessibilityName` (Controls.swift:91, 121). AccessibilityTests.testEveryDesignSystemControlSaysWhatItIs only checks that the word "accessibility" appears in the declaration, which this control passes.

**Suggested fix.** Give MovezToggle a `label: String` and pass it the SettingsRow's label. Then set `.accessibilityLabel(label)`, `.accessibilityValue(isOn ? "On" : "Off")` and `.accessibilityAddTraits(.isToggle)`, which is available from macOS 14. Alternatively, rebuild it as a real `Toggle(label, isOn:)` with a custom ToggleStyle, which gets the name, value and trait for free. Tighten the test so it fails when the label is only a state word.

<details><summary>Verification (confirmed)</summary>

MovezToggle (Controls.swift:4-26) is a plain Button with .accessibilityLabel(isOn ? "On" : "Off") and .isButton. It has no value and no .isToggle trait. Every call site passes only isOn: SettingsView.swift:149,178,181,184,216,219,225,249,252, WorkingHoursPopover:88, LibraryBrowserSheet:90, StrengthSetupSheet:32 and StrengthSettingsSection:18,125. SettingsRow (SettingsView.swift:303-333) and LibraryRow use no accessibilityElement(children: .combine), and grep finds no label added at any toggle call site. SelectField, by contrast, takes an accessibilityName (Controls.swift:91,121). AccessibilityTests.testEveryDesignSystemControlSaysWhatItIs only checks that accessibility modifiers are present, so this passes it.

</details>

### UI-4 · medium · The dropdown shows "Take a break now" and "Make due in" in states where the scheduler ignores them

**Where:** `Sources/movez/UI/MenuBar/MenuBarView.swift:104` · **Category:** correctness · **DECISIONS checked:** 17

**What goes wrong.** The dropdown picks its rows from four menu modes. Every scheduler state except paused, off hours and away maps to sitting (MenuBarViewModel.swift:244-251), and away reuses the sitting rows (MenuBarView.swift:96). So two rows are shown in states where the scheduler drops the request and returns no effects:
- **Make due in** works only in `.sitting` (Scheduler+Actions.swift:79). Clicking 5, 10, 15 or 30 does nothing during a snooze, a pending or deferred break, a call, the grace period after a call, a heads-up, a micro-break, or while away.
- **Take a break now** returns no effects for `.microCountIn` and `.microRunning` (Scheduler+Actions.swift:67-68). With a micro-break count-in on screen (label "micro"), the highlighted row does nothing, which is exactly when someone might prefer the full break.

Neither case gives any feedback.

**Suggested fix.** Decide per state. Either let the scheduler accept the request (take-a-break-now from a micro-break: `dismissSurfaces`, then `enterFullBreak`; make-due from snoozed or pendingFull: back to sitting with the new due time), or carry per-row availability flags in MenuBarState and dim or hide the rows. Add a test for each row in each mode that shows it.

<details><summary>Verification (confirmed)</summary>

MenuBarViewModel.mode maps .sitting and .breaking to the sitting menu, and makeMenuState maps snoozed, pendingFull, suppressed and grace to .sitting. rows shows sittingRows for .sitting and .away (MenuBarView.swift:94-99). makeDue guards `case .sitting` (Scheduler+Actions.swift:79), so it is a silent no-op while snoozed, pendingFull, suppressed, in grace, during a heads-up, during a micro-break or while away. takeBreakNow's switch falls to `default: return []` for microCountIn and microRunning (Scheduler+Actions.swift:59-68), and the coordinator intent passes the request straight through (AppCoordinator+Intents.swift:8). DECISIONS 17 covers only the paused case.

</details>

### UI-5 · medium · An indefinite Focus pause shows "‖ 0m", and "Extend pause" turns it into a 15-minute pause

**Where:** `Sources/movez/UI/MenuBar/MenuBarView.swift:120` · **Category:** correctness · **DECISIONS checked:** 26, 51

**What goes wrong.** A pause set by a Focus filter has `until == nil` (Scheduler+Pause.swift:30). The view model knows this: it passes `indefinite: until == nil` to the title (MenuBarViewModel.swift:217). But it does not keep the flag in the state, so `pauseLeft` and `minutesRemaining` become 0 (lines 210 and 213). `labelText` then shows "‖ 0m" in the menu bar for as long as the Focus lasts (MenuBarState.swift:86), which reads as "about to resume".

Worse, the paused rows always offer "Extend pause". The scheduler's `extendPause` computes `(until ?? now) + seconds` (Scheduler+Pause.swift:56), so choosing "15 m" changes "until the Focus ends" into "in 15 minutes". `tickPaused` then resumes breaks 15 minutes later while the Focus is still on. When the Focus ends later, nothing happens, because the scheduler is no longer paused.

Trigger: attach Movez to a Focus with "Pause breaks" on (DECISIONS 51), turn the Focus on, open the dropdown, and choose Extend pause → 15 m.

**Suggested fix.** Add `pauseIndefinite` to MenuBarState. Show "‖" with no number in the label, and hide or relabel "Extend pause" when `until == nil`. Also guard the scheduler's `extendPause` so it does nothing to an indefinite pause. Add a test for each.

<details><summary>Verification (confirmed)</summary>

A Focus pause is pause(seconds: nil, focusInitiated: true) (Scheduler.swift:71-74), and pauseEnd returns nil for it (Scheduler+Pause.swift:30). applyPaused sets pauseLeft = 0 when until is nil, so minutesRemaining is 0 (MenuBarViewModel.swift:208-213). labelText's .paused case renders '‖ 0m' (MenuBarState.swift:86), and only the title knows about indefinite. pausedRows always offers Extend pause (MenuBarView.swift:120-123). extendPause computes (until ?? now) + seconds (Scheduler+Pause.swift:54-58), which turns the pause into a timed one. tickPaused then resumes with focusInitiated false, which its guard allows. The later Focus-off event hits resumeFromPause while not paused and returns []. No test covers extendPause on an indefinite pause.

</details>

### UI-6 · medium · During a snooze the menu says "Next break in 0 min" and the menu bar shows "0m"

**Where:** `Sources/movez/UI/MenuBar/MenuBarViewModel.swift:175` · **Category:** correctness · **DECISIONS checked:** 19a, 20

*Found independently by the App + History + Notice + Settings + FocusFilter + Audio review as well.*

**What goes wrong.** The menu's sitting header reads `secondsUntilFullBreak`, which is `nextFullDueAt − now`. A snooze (Scheduler+Actions.swift:109-110) moves the scheduler to `.snoozed(until:)` but leaves `nextFullDueAt` at the original due time, which has already passed. The break actually comes back when `until` passes (Scheduler.swift:162-164).

`makeMenuState` maps `.snoozed` to `.sitting` (AppCoordinator+Effects.swift:370-371), and `isBreakSurfaceVisible` is false for it. So for the whole 5-minute snooze:
- the header reads "Next break in 0 min"
- the menu-bar label reads "0m"
- the icon ring is fully spent

This happens after every snooze, from the heads-up or the overlay.

The same zero shows in `.pendingFull`, and in `.suppressed` once a deferred break is waiting, which can last a whole call. That is the same kind of stale countdown DECISIONS 19a fixed for absences.

**Suggested fix.** Carry the snooze end in MenuState (for example `snoozedUntil`) and, in that state, compute `minutesRemaining` and `elapsedFraction` from `until − now`. Give pendingFull, and suppressed with a deferred break, their own title (for example "Break waiting · on a call"), the way 19a did for away. Add a MenuBarViewModel test that snoozes the heads-up and checks the title and the label.

<details><summary>Verification (confirmed)</summary>

snooze (Scheduler+Actions.swift:103-110) transitions to .snoozed(until:) and leaves nextFullDueAt at the original due time, which has already passed. makeMenuState (AppCoordinator+Effects.swift:353-376) falls through to .sitting for .snoozed, and isBreakSurfaceVisible is false for it (SchedulerState.swift:57-61). applySitting reads secondsUntilFullBreak, which is max(0, ...) = 0 (SchedulerSnapshot.swift:68-70), so the title reads 'Next break in 0 min' (MenuBarState.swift:120), labelText reads '0m' and elapsedFraction is 1. The break really returns when `until` passes (Scheduler.swift:162-164). pendingFull and suppressed also map to sitting with a due time already passed. No MenuBarViewModel test covers the snoozed state. DECISIONS 19a fixed the same kind of stale zero for away only.

</details>

### UI-7 · medium · The Movement end screen is visible only during the 0.3 s fade, and its Back to work button does nothing

**Where:** `Sources/movez/UI/Overlay/OverlayViewModel.swift:286` · **Category:** correctness · **DECISIONS checked:** 4, 33, 58

**What goes wrong.** `finish()` sets `phase = .complete` and calls `onFinished` straight away. The coordinator injects `.breakEnded`, and the scheduler answers in the same call with `[.chime(.completion), .endFullBreak(.completed…)]` (Scheduler+Actions.swift:154). `OverlayEffectSink` then fades the overlay out over `dismissFade` (0.3 s). So the 'Break done' card, its streak chip, the 'Next break at …' line and the end dim (`Tokens.dimEnd`) appear only while the window is fading. The handoff draws this screen staying up until 'Back to work', and entries 4 and 33 keep it. `StrengthOverlayView.swift:213-214` even says a movement break 'leaves after Back to work'. The button is wired to `viewModel.done` (OverlayWindowController.swift:335), and `done()` returns at once unless `phase == .running` (OverlayViewModel.swift:222-223), so it could never close the screen anyway. Even if the screen were shown, its numbers are stale. `streak` is `coordinator.streak` captured when the break began, so it leaves out this break. `nextBreakAt` is `scheduler.snapshot.nextFullDueAt` at that moment (OverlayEffectSink.swift:82-83), which is the due time of the break now running. Example: a break due at 10:55 that starts at 10:56 would say 'Next break at 10:55' instead of 11:51.

**Suggested fix.** First decide which behaviour you want. To keep the end screen, the overlay could still report the finish but stay up after `.endFullBreak(.completed)`: change `isGraceful` so the sink only marks the session complete. Give Back to work its own action that calls `controller.dismiss()`. Read `streak` and `nextFullDueAt` after the scheduler has handled `.breakEnded`, for example by setting them on the view model in the sink's `.endFullBreak(.completed)` case. To drop the end screen, as strength mode did (entry 58), record that in DECISIONS. Then delete `OverlayEndView`, `OverlayActions.backToWork`, the streak and nextBreakAt plumbing and `dimEnd`.

<details><summary>Verification (confirmed)</summary>

finish() sets .complete and calls onFinished in the same pass. That reaches finishOverlayBreak, then inject(.breakEnded), then finishBreak(userInitiated: false), which returns [.chime(.completion), .endFullBreak(.completed...)] (Scheduler+Actions.swift:154). OverlayEffectSink dismisses with the 0.3 s animation, so the end view shows only while the window fades. OverlayScreen wires backToWork to viewModel.done (OverlayWindowController.swift:335), and done() needs phase == .running (222-223), so the button does nothing. streak and nextBreakAt are captured in presentRoutine (OverlayEffectSink.swift:82-83) before the break ends. Entries 4 and 33 describe an end screen for movement breaks, and entry 58 drops it only for strength. StrengthOverlayView.swift:214 assumes a movement break 'leaves after Back to work'.

</details>

### UI-8 · medium · A strength break whose pause runs out is always recorded as snoozed, even when it already counts as done

**Where:** `Sources/movez/UI/Overlay/StrengthOverlayViewModel.swift:183` · **Category:** correctness · **DECISIONS checked:** 38, 59

*Found independently by the Strength, Tests: library, routine, strength, modes, UI reviews as well.*

**What goes wrong.** Entry 38 says: 'Five minutes in one pause ends the break — as done if it already counts, otherwise as snoozed'. `OverlayViewModel.pauseExpired` does this: when `doneAvailable` it calls `finish()`, and otherwise `onPauseExpired` (OverlayViewModel.swift:242-251). `StrengthOverlayViewModel.pauseExpired` always calls `onPauseExpired` (lines 183-189). That reaches `.overlayPauseExpired` → `Scheduler.snooze(beyondAllowance: true)` → `.endFullBreak(.snoozed)`. Concrete case: the user finishes the warm-up and sets 1 and 2 (3 of 5 parts, which meets ceil(5 × 0.5) = 3), presses Pause in the rest before set 3 and is pulled away. Five minutes later the break is written as snoozed. Under entry 59 a snoozed break does not count among the day's strength breaks, so the same position comes back as a full strength break five minutes later. The same Movement break would have been recorded as done. No test covers strength pause expiry; OverlayTimingTests.swift:150-189 cover only the Movement model.

**Suggested fix.** Give `StrengthOverlayViewModel` the scheduler config, as `OverlayViewModel` has. In `pauseExpired`, if `Scheduler.meetsCompletionRule(completed: timeline.completedWork, total: timeline.totalWork, elapsed: elapsedSeconds, config:)` holds, call `onFinished` (and play the completion chime) instead of `onPauseExpired`. Add a test mirroring `testFiveMinutesPausedEndsABreakThatAlreadyCountsAsDone`.

<details><summary>Verification (confirmed)</summary>

pauseExpired (183-189) always calls onPauseExpired. The sink wires that to coordinator.pauseExpired(), which injects .overlayPauseExpired, which calls snooze(now:, beyondAllowance: true) (Scheduler.swift:97), which returns .endFullBreak(.snoozed) (Actions.swift:103). OverlayViewModel.pauseExpired checks doneAvailable first (242-251), as entry 38 requires. No strength entry (54-71) exempts strength from entry 38. meetsCompletionRule is ceil(total × fraction) completed, or the elapsed time (Scheduler.swift:279-287), so 3 of 5 parts counts. Entry 59 does not count a snoozed break as a strength break. No test drives strength pause expiry: grep finds onPauseExpired tests only in OverlayTimingTests for the Movement model.

</details>

### UI-9 · medium · activeScreen() crashes when no display is attached, and a break shown with no windows is never rebuilt

**Where:** `Sources/movez/UI/Panels/PanelWindowController.swift:97` · **Category:** macos-edge

**What goes wrong.** `activeScreen()` falls back to `NSScreen.main ?? NSScreen.screens[0]`. With no screen attached, `main` is nil and `screens` is empty, so the subscript traps. It is called every time a panel or toast is presented (lines 43, 58). It is also called on every overlay build (OverlayWindowController.swift:73), including `rebuildForScreenChange`, which runs on `didChangeScreenParametersNotification`, the notification posted when a display goes away. Trigger: a Mac mini or Mac Studio, or a closed-lid MacBook, whose only monitor is switched off or unplugged while awake (many DisplayPort and USB-C monitors drop off the bus when powered down), either during a break or as a heads-up comes due. Result: the app crashes. On relaunch `applyLaunchGap` throws away the break that was on screen ('relaunched with a break on screen'). A related bug: if `build()` ever creates zero windows, `isPresenting` is false. `rebuildForScreenChange`'s `guard isPresenting` (line 182) then never rebuilds when a screen returns, and the scheduler sits in `.fullBreak` with nothing visible.

**Suggested fix.** Make `activeScreen()` return `NSScreen?` and handle nil: skip the panel, or keep the overlay session and show nothing. Have `rebuildForScreenChange` check `session != nil` rather than `isPresenting`, so windows are built as soon as a screen appears.

<details><summary>Verification (confirmed)</summary>

activeScreen() falls back to NSScreen.screens[0], which traps on an empty array. build() calls it unconditionally (OverlayWindowController.swift:73), and that includes rebuildForScreenChange from didChangeScreenParametersNotification (170-185). present(panel:) and present(toast:) call it too (43, 58). On a headless Mac, NSScreen.screens is empty and NSScreen.main is nil. The trigger, the only display going away while awake during a break, is rare, but the result is a crash that leaves the agent dead until it is relaunched, and applyLaunchGap then discards the break (Scheduler+Sleep.swift:169-172). The zero-windows / isPresenting point is real but follows from the crash fix: once activeScreen stops trapping, build() can produce zero windows, and the guard isPresenting at line 182 never rebuilds.

</details>

### UI-10 · medium · The debug time scale is saved across relaunches, and while it runs it writes future timestamps into the real history and state files

**Where:** `Sources/movez/UI/Settings/DebugViewModel.swift:35` · **Category:** persistence

*Found independently by the App + History + Notice + Settings + FocusFilter + Audio, UI: DesignSystem + Debug reviews as well.*

**What goes wrong.** `setTimeScale` stores the scale in SettingsStore, which saves it to UserDefaults and reads it back at launch (SettingsStore.swift:80 and 131; the relaunch test asserts this). The Debug section ships in every build: nothing is behind `#if DEBUG`.

The fast SystemClock is the coordinator's only clock. So everything written while it runs carries scaled time: history records and completions (AppCoordinator+Effects.swift:130-196 use `clock.now`), and the state file's `savedAt`, bout start and due times. Switching back to 1× re-bases the clock without giving the offset back (Clock.swift:38-41), so the app stays ahead of the wall clock until it quits.

Trigger: at 10:00, run at 60× for three real minutes, so the scaled clock reads about 13:00. Go back to 1×, quit at 10:05 and relaunch.
- The restored `nextFullDueAt` is after 13:00.
- The launch gap is `max(0, negative) = 0` (AppCoordinator.swift:179), so nothing corrects it, and the next break is three or more hours away.
- "Today" counts breaks stamped this afternoon, and recency and the strength planner read them too.

Quitting with 60× still on relaunches straight into the stuck state described in the previous finding.

**Suggested fix.** Keep the time scale in memory only, starting at 1 on every launch. While it is above 1, point the coordinator at scratch history and state stores, or don't write to them at all. Consider compiling the Debug section into Debug builds only.

<details><summary>Verification (confirmed)</summary>

setTimeScale writes settings.debugTimeScale. SettingsStore persists it (SettingsStore.swift:80) and reloads it (line 131), and SettingsStoreTests asserts the reload. AppCoordinator.start calls applyTimeScale (AppCoordinator.swift:216), so a relaunch comes back at the saved scale. Nothing in Sources is behind #if DEBUG, and the Debug disclosure is always present (SettingsView.swift:82-86). History writes use clock.now (AppCoordinator+Effects.swift:130-196), and the persisted savedAt is clock.now (Effects:61). SystemClock.rebase (Clock.swift:38-41) keeps the accumulated scaled offset when the scale drops back to 1. At launch, launchGapSeconds = max(0, now - savedAt) (AppCoordinator.swift:179), which is 0 when savedAt is in the future, so nothing corrects the restored due times.

</details>

### UI-11 · low · The gallery's strip and disc samples no longer match the app

**Where:** `Sources/movez/UI/Debug/Gallery.swift:131` · **Category:** correctness · **DECISIONS checked:** 28, 6

**What goes wrong.** SnapshotFixtures.stripNames grew to five names when every break moved to the five-block shape (entry 28), but the gallery still builds its rows as if there were four:
- "4 columns · current is a /side block" (:127-129) now draws five columns and puts the half-filled rule on Single-leg stand, which is not a per-side block (the /side one is index 2).
- "5 columns" (:130-134) adds a hand-made item numbered 5 to a strip that already ends at 5. It draws six columns, and two items share id 5. StripItem.id is its number (SequenceStrip.swift:23) and SequenceStrip uses ForEach(items) (:37), so the duplicate ids make SwiftUI's diffing undefined.
- The "panel 64" disc sample (:112) uses TimerDisc's default numeral style, which scales 84/300 x 64 = 17.92 and rounds to 18 pt (TimerDisc.swift:153-160). The real heads-up passes MovezType.panelDisc at 17 pt (HeadsUpView.swift:52). TimerDisc's own comment (:40-42) claims the scaling lands on 17, and only the gallery ever reaches that small-size branch.

The gallery is meant to be the reference page, so these rows show strips and a disc that no real surface draws.

**Suggested fix.** Build the gallery strips from explicit lengths: 3, 4 and all 5, with sideIndex set on the /side item. Remove the extra StripItem. Pass numeralStyle: MovezType.panelDisc and MovezType.menuDisc to the 64 and 40 pt sample discs, or delete the small-size branch of defaultNumeralStyle, and correct the comment.

<details><summary>Verification (confirmed)</summary>

SnapshotFixtures.stripNames has 5 entries (SnapshotFixtures.swift:23), and 'Hip flexor /side' is index 2. The Gallery row labelled '4 columns · current is a /side block' (:127-129) draws 5 columns with current = index 1 ('Single-leg stand'). The '5 columns' row (:130-134) adds StripItem(number: 5) to the 5 items already there, so it draws 6 columns with two id 5s. StripItem.id is number (SequenceStrip.swift:23), and the strip uses ForEach(items) (:37). TimerDisc.defaultNumeralStyle for size 64 is round(64*84/300 = 17.92) = 18 pt (TimerDisc.swift:153-161). The real heads-up passes MovezType.panelDisc at 17 pt (HeadsUpView.swift:52), and the menu passes menuDisc (MenuBarView.swift:55). So only the gallery reaches that branch, and the comment at :40-42 claiming it lands on 17 is wrong. This only affects the debug reference page.

</details>

### UI-12 · low · Snapshot fixtures fail silently, and nothing checks them

**Where:** `Sources/movez/UI/Debug/SnapshotRenderer.swift:327` · **Category:** test-gap · **DECISIONS checked:** 70

**What goes wrong.** There are three ways a snapshot can quietly show the wrong thing:
- view(for:) (:143-147) tries seven optional lookups in turn, and the last one, overlayView(for:), ends in `default: overlayRunning()`. A new SnapshotSurface case that isn't added to any table renders the Movement overlay under its own file name instead of failing to compile.
- strengthState, endRangeState and strengthMicro return an empty StrengthOverlayState() or a nil MicroPanelBreak when a pinned id is missing (StrengthSnapshotFixtures.swift:183-188 and 215-219, StrengthPanelFixtures.swift:78-82). Entry 70's renumbering of PSH/PUL moves into BIC/TRI is exactly the kind of edit that could cause this.
- run(_:until:) gives up after 1,000 ticks and returns whatever segment it reached (StrengthSnapshotFixtures.swift:255-259).

Nothing would catch any of these. `make snapshots` only checks that each PNG exists. compare_snapshots.py counts every strength image as "new" against the pre-strength baseline, and a new image never fails. The only test that touches surfaces (FontsTests.swift:63-69) checks their sizes. I verified that every current case is mapped and every pinned id resolves, so this is a risk for the next library or surface change, not a current bug.

**Suggested fix.** Turn view(for:) into one exhaustive `switch surface` with no default, so the compiler flags a new case. Add a unit test that builds every fixture and checks it is filled in and at the intended moment: a non-empty movementName, a segment equal to the kind passed to run, and a non-nil micro on each panel. Make run(until:) fail loudly (assertionFailure) when it hits the tick cap.

<details><summary>Verification (confirmed)</summary>

view(for:) (:143-147) chains optional lookups that end in overlayView, which has `default: AnyView(OverlaySnapshot(state: SnapshotFixtures.overlayRunning()))` at :327-328. strengthState and endRangeState return an empty StrengthOverlayState() when an id is missing (StrengthSnapshotFixtures.swift:183-188, 215-219). run(_:until:) stops at 1,000 ticks without any signal (:250-260). The Makefile snapshots target only checks that each PNG exists. compare_snapshots.py says a new image never fails (:10-11, :122). The tests only touch SnapshotFixtures.strip and sheetModes, and neither checks strength fixture contents. This is a real latent risk, not a current bug, which the finding itself says. Low is right.

</details>

### UI-13 · low · The strength micro-break long-text snapshot draws the wrong instruction

**Where:** `Sources/movez/UI/Debug/StrengthPanelFixtures.swift:65` · **Category:** correctness · **DECISIONS checked:** 67

**What goes wrong.** strengthMicroLong() is meant to show the longest standing END name over the longest END instruction: the name from END-06 and the instruction from END-32. I checked the library: END-32's 433 characters is the longest END instruction. But it calls `renamed(texted, after: named)`, and renamed (StrengthSnapshotFixtures.swift:231-240) takes the name *and the instructions* from `named` (line 237). Only the dose and timing fields come from the first argument. That is right for the long-dose overlay fixture, where it is also used, but wrong here. So micro-strength-long-text.png shows END-06's 281-character Cossack-squat instruction plus the appended "Switch at the chime" (about 300 characters), not the 433-character neck isometric. The tallest micro panel the app can actually show is never rendered. Also, the doc comment at :43-44 says "first side", but microSideElapsed = 43 s puts a 60 s per-side move on its second side.

**Suggested fix.** Build the long-text move explicitly, taking each field from where the comment says, for example a `renamed(_:name:instructions:)` that takes the name and instruction separately. Fix the "first side" comment, or pick an elapsed time that is on the first side. A unit test asserting that this fixture's instruction is the longest micro-eligible END instruction would keep it right after library edits.

<details><summary>Verification (confirmed)</summary>

renamed(_:after:) (StrengthSnapshotFixtures.swift:231-240) takes name, equipment, vigorous, load and instructions from `named`. strengthMicroLong calls renamed(texted /*END-32*/, after: named /*END-06*/), so the instruction is END-06's, not END-32's. I checked strength-library-v1.json: END-32 'Neck side-bend isometric' has the longest END instruction (433 chars, per_side, micro_eligible). END-06's is 281 chars. microSideElapsed = 43 (SnapshotFixtures.swift:160), which that file's own doc describes as the per-side move 'on its right side with 0:22 left', the second half of a 60 s block. So the 'first side' comment at :44 is wrong too. Only the snapshot fixture is affected.

</details>

### UI-14 · low · Line heights tighter than Manrope's natural 1.37 are silently ignored (10 of 44 styles)

**Where:** `Sources/movez/UI/DesignSystem/TextStyles.swift:23` · **Category:** correctness

**What goes wrong.** Text styles that ask for a line height below Manrope's natural 1.366 silently get lineSpacing 0, so they set at 1.366. This affects 10 styles. It only shows when the text wraps, for example a two-line strength set name or up-next line, which sets about 18 pt looser than the handoff's 1.05 at 56 pt.

**Suggested fix.** Either record in DECISIONS that line heights below the font's natural ratio are not honoured and set those styles to 1, or draw the wrapping tight styles (setName, upNext, panelTitle) with something that can tighten line spacing, such as an NSAttributedString with maximumLineHeight. Add a test that every style's lineHeight is 1 or at least the font's natural ratio.

<details><summary>Verification (confirmed with corrections)</summary>

I measured the bundled Manrope[wght].ttf with a small swiftc program: ascender - descender + leading = 1.366 x size at 13, 20, 28 and 56 pt. So max(0, size*lineHeight - natural) is 0 for every style below 1.366: setName 1.05, dose/repCounter 1.1, panelTitle/panelDose 1.15, setKicker/doseModifier/sidePillCompact 1.2, upNext/menuRow 1.3. setName uses lineLimit 2 (StrengthOverlayView.swift:88) and upNext uses lineLimit 2 (:149). FontsTests only checks instruction and overlayName. No DECISIONS entry covers line height. The mechanism is correct. What I changed: the severity. The effect is only visual and only shows when one of these styles wraps to a second line. There is no wrong behaviour and no data loss, so low, not medium.

</details>

### UI-15 · low · Two unused tokens, and three components that re-implement a neighbouring one

**Where:** `Sources/movez/UI/DesignSystem/Tokens.swift:109` · **Category:** duplication

**What goes wrong.** Two tokens are dead code: leadinRingTrack is never read, because TimerDisc draws the lead-in track with accentTint, and overlayRingStroke is never read, because TimerDisc derives the ring width from ringRatio. OverlaySnapshot.desktop also writes two raw colour literals, although Tokens.Backdrop exists so that colour values are written nowhere else.

**Suggested fix.** Delete overlayRingStroke. Either use leadinRingTrack in TimerDisc (an agreed 1% alpha snapshot change) or delete it. Move the two gradient colours into Tokens.Backdrop. Leave ModeSegmentedControl and WeightGuidance as they are.

<details><summary>Verification (confirmed with corrections)</summary>

Confirmed by grep: leadinRingTrack (Tokens.swift:109) and overlayRingStroke (:179) are never read in Sources or Tests. TimerDisc uses accentTint for the lead-in track (TimerDisc.swift:107). OverlaySnapshot.desktop writes two Color literals (OverlaySnapshot.swift:23-26), which contradicts the Tokens.Backdrop doc comment ('so that no colour value is written anywhere else', Tokens.swift:126-128). What I dropped: the component-duplication claims. ModeSegmentedControl differs from SegmentedControl in real ways: variant-dependent spacing, collapsed glyph-only segments with a fixed width, full-width dropdown segments, help tooltips and per-segment accessibility labels. Making SegmentedControl generic to cover all that adds complexity for little gain. WeightGuidance shares only a 3-line background with InfoBadge, and its padding and content differ. Those are style nits.

</details>

### UI-16 · low · The menu-bar item redraws every 2 s because the elapsed fraction changes every tick

**Where:** `Sources/movez/UI/MenuBar/MenuBarViewModel.swift:177` · **Category:** complexity

**What goes wrong.** The `next != state` guard is meant to stop the menu-bar item redrawing on every two-second coordinator publish (the comment at lines 167-168). But `elapsedFraction` (line 177) is computed from the remaining seconds, which change on every tick. So while sitting, the comparison is never equal: the state is republished every 2 s, MenuBarLabel re-renders, and `MenuBarIcon.image` builds a new NSImage each time. That runs all day in an app that is otherwise careful about idle cost.

**Suggested fix.** Round what the icon draws before comparing, for example by deriving `elapsedFraction` from `minutesRemaining` or rounding it to 1/100 (the 18 pt arc cannot show finer). The guard then holds between minute changes.

<details><summary>Verification (confirmed)</summary>

The coordinator republishes menuState on every tick (AppCoordinator.swift:278), and MenuBarViewModel refreshes on each objectWillChange (lines 27-30). applySitting computes elapsedFraction from remaining seconds, which change every 2 s tick, so the `next != state` guard (line 169) never holds while sitting, contrary to its comment ('the menu bar only changes once a minute'). Each publish rebuilds iconImage via MenuBarIcon.image(for:), which reads elapsedFraction (MenuBarIcon.swift:25). The cost is real but small.

</details>

### UI-17 · low · Fixed-size break card and notice window do not fit small displays

**Where:** `Sources/movez/UI/Overlay/OverlayView.swift:124` · **Category:** macos-edge · **DECISIONS checked:** 49, 53

**What goes wrong.** `OverlayCard` is a fixed 1000×660 pt. The 300 pt disc is centred on the card's right edge and 80 pt below its top, so it overhangs 150 pt to the right and 70 pt above (lines 120-139). The card is centred in a window that leaves out the menu bar, so the whole break needs at least about 1300×800 pt of dim. Entry 49 puts the full card on every display. On a smaller one (an iPad over Sidecar at 1194×834, a 1280×800 'larger text' scaling, a 1024×768 projector), the disc, which is the Next/Done control, and the card edges are clipped. The notice is a fixed, non-resizable 720×760 window (NoticeView.swift:8, 25; NoticeWindowController.swift:48-52). On a display with less than about 784 pt of visible height (1024×640 or 1280×720 scaling), AppKit keeps the title bar below the menu bar and pushes the footer with Quit and 'I understand and agree' off the bottom. That happens at the one moment the app does nothing else until the notice is accepted.

**Suggested fix.** Scale the card to the window, for example with `GeometryReader` and `scaleEffect(min(1, available / needed))` in `OverlayScreen`/`StrengthOverlayScreen`. Make the notice height `min(760, screen.visibleFrame.height - margin)` and let the `ScrollView` absorb the difference.

<details><summary>Verification (confirmed)</summary>

Tokens.Metric.overlayCard is 1000×660 and overlayDisc is 300 (Tokens.swift:167-168). OverlayCard offsets the disc to x = card.width - 150 and y = 80 - 150 (OverlayView.swift:138-140), so it overhangs 150 pt to the right and 70 pt above. There is no scaling to fit. NoticeScreen is a fixed 720×760 frame (NoticeView.swift:8, 25), and NoticeWindowController creates a non-resizable titled window of that content size (Controller.swift:48-52). This only affects small or scaled displays, so low.

</details>

### UI-18 · low · The skip delay is stated three times, and the panel layout code is duplicated

**Where:** `Sources/movez/UI/Overlay/OverlayViewModel.swift:15` · **Category:** duplication

**What goes wrong.** `OverlayViewModel.skipDelaySeconds` (line 15), `PanelViewModel.skipDelaySeconds` (PanelViewModel.swift:38) and `SchedulerConfig.skipDelaySeconds` (SchedulerConfig.swift:36, checked at Scheduler+Actions.swift:120, 123) are three copies of one rule. `doneAvailable` deliberately asks the scheduler's rule 'rather than restating it'; Skip restates it. If the config value changes, the Skip button would light up while the scheduler still ignores the tap. Separately, `layoutPanel` and `layoutToast` (PanelWindowController.swift:139-161) are line-for-line the same except for `panelFrame` vs `toastFrame`.

**Suggested fix.** Read the delay from the `SchedulerConfig` the view models are given (the panels can take it from `coordinator.settings.schedulerConfig` in `PanelEffectSink`). Fold the two layout functions into one `layout(_ window:, on screen:, frame: (CGSize, NSRect) -> NSRect)`.

<details><summary>Verification (confirmed)</summary>

The delay is defined in OverlayViewModel.skipDelaySeconds (15), PanelViewModel.skipDelaySeconds (PanelViewModel.swift:38) and SchedulerConfig.skipDelaySeconds (SchedulerConfig.swift:36, checked at Actions.swift:120, 123). StrengthOverlayViewModel reuses OverlayViewModel's (107). All three are 3 today, so nothing breaks now. This is a maintenance risk that fits the user's duplication criterion. layoutPanel and layoutToast (139-161) differ only in panelFrame vs toastFrame and the stored window and screen.

</details>

### UI-19 · low · The menu bar is left uncovered so the icon stays reachable, but its dropdown opens underneath the shielding-level overlay

**Where:** `Sources/movez/UI/Overlay/OverlayWindowController.swift:138` · **Category:** macos-edge

**What goes wrong.** `dimFrame` stops the overlay window below the menu bar 'so the movez icon stays reachable during a break' (lines 136-142). The overlay windows sit at `CGShieldingWindowLevel()` (line 117), which is far above the levels AppKit uses for status-item and pop-up windows. The `MenuBarExtra` dropdown hangs below the menu bar, inside the dimmed area. So clicking the icon during a break opens the menu underneath the overlay, where it is blurred and can't be clicked. Pause, Quit and the rest of the menu are unreachable during a break, and the carve-out does not do what its comment says. The user is not trapped, because Skip works after 3 s. Clicking the icon also takes key away from the overlay window. This comes from reasoning about window levels, so confirm it once by hand during a break.

**Suggested fix.** Confirm by hand. Then either lower the overlay while the dropdown is open (or open the menu at a higher level), or drop the carve-out claim and record in DECISIONS that the overlay's own buttons are the way out.

<details><summary>Verification (confirmed)</summary>

The overlay is at CGShieldingWindowLevel (117), which is above every standard AppKit level. Nothing in Sources changes the MenuBarExtra window's level (grep for .level finds only the overlay at 117 and the panels at .statusBar). The app uses .menuBarExtraStyle(.window) (movezApp.swift:13), whose dropdown opens below the menu bar, inside the dimmed area that dimFrame covers. The window-level reasoning holds, but it has not been run, so a quick manual check is still worth doing.

</details>

### UI-20 · low · Movement overlay keys act from the first instant, with no repeat filter or press guard, so stray typing pauses or advances the break

**Where:** `Sources/movez/UI/Overlay/OverlayWindowController.swift:150` · **Category:** correctness · **DECISIONS checked:** 5, 29

*Found independently by the Tests: library, routine, strength, modes, UI review as well.*

**What goes wrong.** The movement overlay acts on every keyDown, auto-repeats included, and on every disc click, with no press guard. Holding Return or the right arrow, or double-clicking the disc, advances through several blocks and records each one as completed. A Space or Return typed just as the overlay appears pauses the break or skips movement 1. The strength timeline's 1 s press guard prevents the double-press case. Its lead-in exemption covers working sets only, not end-range blocks.

**Suggested fix.** In the key monitor, swallow events where event.isARepeat is true. Give OverlayViewModel.next() a press guard like StrengthSessionTimeline.pressGuardSeconds. Optionally ignore next() and togglePause() for the first skipDelaySeconds. Add tests for a press at t=0 and for two presses 100 ms apart.

<details><summary>Verification (confirmed with corrections)</summary>

Confirmed mechanically. The local monitor never checks event.isARepeat (150-165). OverlayViewModel.next() has no lead-in or press guard, and it records a completion (207-210, 262-266). The heads-up to full-break transition does not wait for typing to stop (Scheduler.swift:158-160). The input pause applies only to pendingFull to headsUp (198-200). The disc calls actions.next (OverlayView.swift:26). Severity is lowered because entry 5 makes Return and the arrow advance by design, a stray Space only pauses (visible and reversible), and the stray-key cases follow a one-minute heads-up warning. One correction: StrengthSessionTimeline ignores lead-in presses only in the workingSets flow. In the endRange flow, a lead-in press skips the block (StrengthSessionTimeline.swift:246-252). Only the 1 s pressGuardSeconds applies to both flows.

</details>

### UI-21 · low · The strength overlay redraws the whole card every display frame during a set

**Where:** `Sources/movez/UI/Overlay/StrengthOverlayView.swift:238` · **Category:** complexity · **DECISIONS checked:** 66

**What goes wrong.** During every rep-counted set (Reduce Motion off, not paused), `StrengthOverlayScreen.card` wraps the entire `StrengthOverlayView` in `TimelineView(.animation)` (lines 235-243). On every frame (60-120 Hz on ProMotion), on every attached display, SwiftUI re-evaluates the header, body text, strip, action row and disc, and calls `viewModel.livePacer()`, for the 30-60 s of each set. Only `RepMeter`'s fill needs per-frame updates. Everything else changes once a second with the tick.

**Suggested fix.** Put the `TimelineView` inside the meter. Pass `RepMeter` a `() -> RepPacerState` provider (or the view model) and keep the card on the 1 Hz `state`.

<details><summary>Verification (confirmed)</summary>

Lines 235-243 wrap the entire StrengthOverlayView in TimelineView(.animation) whenever showsMeter, !reduceMotion and !isPaused hold. Every frame rebuilds the full card and calls livePacer() (StrengthOverlayViewModel.swift:114-120) on every display's window. This is a performance cost only, so low.

</details>

### UI-22 · low · Panels and the toast stay pinned to the screen they opened on, even after that display is gone

**Where:** `Sources/movez/UI/Panels/PanelWindowController.swift:147` · **Category:** macos-edge

**What goes wrong.** `present(panel:)` and `present(toast:)` store `Self.activeScreen()` once (lines 43-44, 58-59). Then `layoutPanel` and `layoutToast` place the window on that `NSScreen`'s `visibleFrame` ten times a second (lines 139-161). Nothing observes display changes. `PanelWindow` also overrides `constrainFrameRect` to return the frame unchanged (lines 255-258), so AppKit cannot pull the window back onto a remaining display. Unplug or sleep-detach the display a heads-up or micro-break is on, during its 60-100 s, and the panel keeps being placed at the old display's coordinates, where nobody can see it. The micro-break still ends itself after its minute (`microEnded`) and is recorded as done (`recordMicroDone`), although nobody saw it. The overlay handles the same event by rebuilding (OverlayWindowController.swift:170-185).

**Suggested fix.** In `layoutPanel` and `layoutToast`, re-resolve the screen when the stored one is no longer in `NSScreen.screens`, or observe `didChangeScreenParametersNotification` as the overlay does and re-pick the pointer's screen.

<details><summary>Verification (confirmed)</summary>

panelScreen and toastScreen are set once (43-44, 58-59). layoutPanel and layoutToast re-place the window on that stored screen's visibleFrame on every 0.1 s tick (139-161, 174-180). There is no screen-change observer in this class, and PanelWindow.constrainFrameRect returns the frame unchanged (255-258). Even if AppKit moved the window, the next tick would put it back on the stale frame. The effect lasts as long as the panel's minute or so.

</details>

### UI-23 · low · Dead accessors and stale comments in the window controllers

**Where:** `Sources/movez/UI/Panels/PanelWindowController.swift:207` · **Category:** dead-code · **DECISIONS checked:** 49

**What goes wrong.** Several members have no callers in Sources or Tests: `PanelWindowController.hideAll` (lines 207-210), `isShowingPanel` and `isShowingToast` (32-33), `OverlayWindowController.viewModel` (OverlayWindowController.swift:31-34) and `NoticeWindowController.isOpen` (NoticeWindowController.swift:13). `OverlayScreen`'s doc comment says each screen gets 'the card if this is the screen the user is on' (OverlayWindowController.swift:311), which entry 49 replaced. Every display gets the card. `OverlayActions.backToWork` is wired to a no-op (see the end-screen finding). Next door in App/, `AppCoordinator.nextBlock()`, `done()`, `endBreak()`, `canFinishBreak` and `elapsedInBreak` are used only by tests, since the overlay owns progression. That is how the Movement resume test ended up exercising a path production never takes.

**Suggested fix.** Delete the unused members and fix the `OverlayScreen` comment. Either delete the coordinator's test-only intents or move the tests that use them onto the overlay view models.

<details><summary>Verification (confirmed)</summary>

A grep across Sources and Tests finds no callers for hideAll, isShowingPanel, isShowingToast, OverlayWindowController.viewModel or NoticeWindowController.isOpen. The OverlayScreen doc comment at OverlayWindowController.swift:311 contradicts entry 49. One small correction: AppCoordinator.endBreak() and canFinishBreak have no callers at all, not even in tests. done() is reached only through nextBlock(), and nextBlock() is used only by tests (CoordinatorTestSupport.swift:96, ReviewFixTests.swift:165 and others).

</details>

### UI-24 · low · After Settings has been opened once, the debug inspector republishes the whole Settings view model every poll until quit

**Where:** `Sources/movez/UI/Settings/SettingsWindow.swift:44` · **Category:** lifecycle

*Found independently by the UI: DesignSystem + Debug review as well.*

**What goes wrong.** DebugViewModel is built on the first open; the comment at lines 14-15 says a window nobody has opened should not rebuild on every publish. But once built it lives for the rest of the run:
- It refreshes on every coordinator publish (DebugViewModel.swift:18-21).
- Its rows include the aggregator's poll count (line 72), which changes on every poll, so its state changes about every 2 s.
- `attach` (SettingsViewModel.swift:369-376) copies that state into a @Published property, so SettingsViewModel republishes and SettingsScreen is re-evaluated every 2 s.

This carries on with the window closed and the Debug disclosure collapsed. With the fullscreen exceptions sheet open, each pass also lists the running apps and does two Launch Services lookups per row (FullscreenExceptionsSheet.swift:53 and 75-81).

**Suggested fix.** Subscribe the debug view model only while the window is visible and the section is expanded: start in `show()`, and cancel in `windowWillClose` and on collapse. Alternatively, keep `debug` out of SettingsViewModel's published state and have DebugSection observe DebugViewModel directly.

<details><summary>Verification (confirmed)</summary>

show() builds the DebugViewModel once and attaches it (lines 44-48), and nothing ever detaches it. DebugViewModel refreshes on every coordinator objectWillChange (DebugViewModel.swift:18-21). Its rows include now and pollCount, so its state changes at least every tick. attach sinks $state into SettingsViewModel's `@Published var debug` (SettingsViewModel.swift:52 and 369-376), so SettingsViewModel publishes every ~2 s for the rest of the run, including with the window ordered out (it is kept, isReleasedWhenClosed = false) and the section collapsed. This is an efficiency issue only.

</details>

### UI-25 · low · Closing the Settings window leaves an open sheet and its draft for next time

**Where:** `Sources/movez/UI/Settings/SettingsWindow.swift:63` · **Category:** lifecycle · **DECISIONS checked:** 15, 56

**What goes wrong.** Sheets are overlays inside the window, driven by `viewModel.openSheet` (SettingsView.swift:27-30). Nothing resets it when the window closes: the controller sets no window delegate, and `close()` only calls `orderOut`.

Trigger: pick Strength in the dropdown for the first time. Settings opens on "Set up Strength". Close the window with the red button instead of pressing "Not now". The mode correctly stays Movement, but the next Settings… (⌘,) opens straight onto the setup sheet again. A half-edited Working hours draft, with its error message, comes back the same way.

**Suggested fix.** Give the window a delegate. In `windowWillClose`, call `declineStrengthSetup()` or set `openSheet = nil`, and reset `hoursDraft` and `hoursError`.

<details><summary>Verification (confirmed)</summary>

The window has no delegate, and close() only calls orderOut. The red close button closes a window kept with isReleasedWhenClosed = false. Nothing resets openSheet, which is set to nil only in applyHours, confirmStrengthSetup, declineStrengthSetup and similar sheet actions (SettingsViewModel.swift:198, 441 and 446). show() does not touch it, so reopening shows the same sheet overlay (SettingsView.swift:27-30). This is a minor UX issue: the mode does not change, because the setup was never confirmed.

</details>


## 6. Tests, scripts and build

### TST-1 · medium · Nothing checks that simulate_strength.py draws what the Swift builders draw, so its proofs and weekly-volume targets are unchecked against the app

**Where:** `Tests/movezTests/StrengthSimulationCrossCheckTests.swift:30` · **Category:** test-gap · **DECISIONS checked:** 69

*Found independently by the Strength, scripts/ + project.yml + Makefile reviews as well.*

**What goes wrong.** How it works: simulate_strength.py reimplements the planner, the three builders, SplitMix64 and the relaxation ladders in Python. Its docstring (lines 6-11) says the same context draws the same moves as the app. From that mirror it proves zero rule violations over 5,000 breaks per configuration, that no eligible move is never served, and that the default week meets the S10 weekly hard-set targets, and it writes docs/strength-simulation.md. The Swift 'cross-check' never compares against the Python output. It runs the Swift builders on its own seeds (`1 + seed % 4` breaks a day versus Python's per_day_cycle) and judges them with StrengthRuleChecker. The only link to Python is that both rule-id lists equal strength-rules.json (testTheRuleListMatchesTheSimulation). No Makefile target runs the script, and no Swift test checks weekly volume or never-served moves. Trigger: change the Swift workingLadder order, the focus weight of 3, or armBreakPosition without touching the Python. `make test` stays green, because the Swift checker still sees no violation, while docs/strength-simulation.md and its S10 table describe code that no longer exists. The next finding shows the two have already drifted.

**Suggested fix.** Have simulate_strength.py also write a small fixture (configuration, seed, context, ids drawn) for a few hundred breaks across every configuration. Add a Swift test that rebuilds the same contexts and asserts identical ids. Add a `make simulate` target, run it in the same gate as `make test`, and fail when the regenerated docs/strength-simulation.md differs from the committed one.

<details><summary>Verification (confirmed)</summary>

The test file reads only scripts/strength-rules.json (testTheRuleListMatchesTheSimulation) and otherwise runs the Swift planner and builders on its own seeds and day cycle, judging them with StrengthRuleChecker. It never reads any Python output or fixture. The Makefile has no 'simulate' target (grep found none). DECISIONS 69 says the script 'mirrors the Swift draws exactly' and that 'a Swift test cross-checks 200 seeds against it'. What that test actually checks is the rules, not the draws, so drift between the script and the Swift goes undetected. Finding 4 is a concrete case of such drift. The user asked directly whether the scripts mirror the Swift.

</details>

### TST-2 · medium · In the app a move done for two sets carries twice the recency; both simulations count it once

**Where:** `scripts/simulate_strength.py:936` · **Category:** correctness · **DECISIONS checked:** 23e, 65, 69

**What goes wrong.** How it works: in the app every set is a part (PlannedBreak.parts, ModeBuilder.swift:27). Each finished part writes its own MovementCompletion (recordOverlayPart). HistoryStore.recencyScores (HistoryStore.swift:210-215) adds Recency.weight once per completion. So the lead move of an X · Y · X break, and the A move of an arm break's A · A · B, gets a score of 2 for yesterday: multiplier 1/(1+2·2) = 0.20. The unlock count also gets +2. StrengthCoordinatorTests:207-210 confirms one completion per set. The Python serve() dedups with `dict.fromkeys` (line 936) and adds 1 per distinct move, giving multiplier 0.33. The Swift cross-check does the same through `serve(strengthBreak.movementIds)` (StrengthSimulationCrossCheckTests.swift:213, 239-242), because movementIds is deduplicated. Concrete effect: at the default of 3 breaks a day, two lead moves a day are weighted down about 40% more in the app than in the simulation. The share tables, the 'above three times their even share' list and the never-served check in docs/strength-simulation.md therefore describe a different distribution from the one users get.

**Suggested fix.** Decide whether a move counts as served once per break or once per set. If once per break, have recencyScores (and StrengthUnlock, if wanted) count distinct (routineId, movementId) pairs. If per set, make serve() in the script and the Swift cross-check add one per set. Then re-run the simulation.

<details><summary>Verification (confirmed)</summary>

In Swift, recordOverlayPart writes one MovementCompletion per part (AppCoordinator+Intents.swift:97-105 and AppCoordinator+Effects.swift:189-195). StrengthCoordinatorTests:207-210 asserts 5 × 3 completions for three strength breaks, so the X move of X · Y · X is recorded twice. HistoryStore.recencyScores (lines 207-217) adds the weight once per completion, and StrengthModeBuilder.swift:60/87 feeds that into the strength context. In Python, serve() at line 936 deduplicates the sets with dict.fromkeys and adds today[m.id] += 1 per distinct move, and recency (line ~844) is built from those counts. The Swift cross-check serves strengthBreak.movementIds, which is deduplicated (StrengthBreak.swift:184-188). The app and both simulations therefore weight a lead move's next-day recency differently (score 2 against 1). The user-facing effect is mild: the lead move is weighted down a little more. The real problem is that docs/strength-simulation.md describes a different distribution from the one the app produces.

</details>

### TST-3 · medium · The simulation never reports the app defaults' relaxations, which hides that every Beginner bodyweight triceps arm break serves a difficulty-2 move

**Where:** `scripts/simulate_strength.py:1205` · **Category:** test-gap · **DECISIONS checked:** 56, 58, 65, 69, 70

**What goes wrong.** main() runs only the 20 configurations from configurations() (lines 1040-1052, all at cap 2 or 3 with everything unlocked) through the 5,000-break loop with the 1-4 cycle and skips. The app defaults (bodyweight, wall, cap 1 Beginner, nothing unlocked) get only the 10-day week runs at lines 1094-1105: 200-800 strength breaks per row, with skip=False. Three report sections sum over `tallies` (the 20 configurations) and nothing else: the Relaxations table (lines 1203-1212), the per-configuration relaxations (line 1304) and 'Eligible moves never served' (lines 1224-1232). So no relaxation at the defaults is ever printed, and DECISIONS 69's '5,000 ... plus the app defaults ... no eligible move never served' is not what the script does. What this hides: TRI has one bodyweight difficulty-1 move (TRI-05). An arm break is arm · arm · alternate, and the alternate must be a different TRI move (hard rule s6-arm-alternate). So the working ladder (StrengthBreakBuilder.swift:27-29) has to let `.difficulty` go and serve TRI-02 or TRI-03 (difficulty 2). I confirmed this with the real Swift builder on a fresh day with nothing served: 20 of 20 A-day arm breaks came out `TRI-05 · TRI-05 · TRI-02/03` with `set3:difficulty`. The Python week runs show the same thing: def4 and def4a each have 100 `arm break:difficulty` relaxations, one per A-day arm break, and def3a also has 100. When it happens: a default user who raises strength breaks a day to 4, or picks More arms at 3. Every A-day arm break then puts a move above the Beginner cap in front of them. No DECISIONS entry records this, and the 'never relaxed further than it has to be' rule in entry 58 cannot avoid it.

**Suggested fix.** Add DEFAULT (and the dumbbell defaults) to configurations() so they get the 5,000-break cycle-and-skip run, or include the week tallies in the Relaxations, per-config and never-served tables. Then decide the product question and record it in DECISIONS: add a difficulty-1 bodyweight triceps move, or let a one-move arm bucket repeat its main move for the third set before it lets the cap go.

<details><summary>Verification (confirmed)</summary>

Read main() (1086-1125) and report() (1131-1240). The Relaxations table (1203-1212), per_config_relaxations (1294-1315) and 'Eligible moves never served' (1224-1232) iterate only `tallies` (the 20 configurations()), never week_tallies. Only violations by rule cover the week runs. DEFAULT and DUMBBELLS appear only in WEEK_CONFIGS, run with days=10 and skip=False. Library: the only bodyweight difficulty-1 TRI move is TRI-05; TRI-02 and TRI-03 are difficulty 2. The strength difficulty default is 1 (SettingsStore.swift:53). In StrengthBreakBuilder.build, the armAlternate slot's `taken` set includes TRI-05, so for a bodyweight user at cap 1 the working ladder [.breakLimits, .servedToday, .vigorous, .excluded, .difficulty] has to reach .difficulty. I re-ran the week simulation by importing the module: def/none/4 a day and def/moreArms/3 and /4 each give 100 ('arm break','difficulty') relaxations out of 200 arm breaks, one per A-day triceps break. They also give 100-132 warmUpShape relaxations, which are not reported either. DECISIONS 69 says the 5,000-break runs cover the app defaults, but they do not. No DECISIONS entry records a Beginner being served a difficulty-2 move. DECISIONS 58's ladder lets this happen, but it does not record it as accepted.

</details>

### TST-4 · low · `make test` hides compiler warnings, and nothing fails on a new concurrency warning

**Where:** `Makefile:33` · **Category:** test-gap · **DECISIONS checked:** 1

**What goes wrong.** `make test` filters compiler warnings out of its output, and with SWIFT_TREAT_WARNINGS_AS_ERRORS: NO nothing fails on a new Sendable or actor-isolation warning. Such a warning is visible only on a fresh `make build` (-quiet still prints warnings) or in build/test.log. The tree builds with zero warnings today, so a strict gate would be cheap to keep.

**Suggested fix.** Add `warning:` to the test grep, or print a warning count from build/test.log. Optionally add a strict target that builds with SWIFT_TREAT_WARNINGS_AS_ERRORS=YES before a release.

<details><summary>Verification (confirmed with corrections)</summary>

Confirmed that `make test` greps for 'Test Suite|Executed|error:|failed|** TEST', so warnings go only to build/test.log, and that SWIFT_TREAT_WARNINGS_AS_ERRORS is NO (project.yml:20). The claim that the warning 'never appears in the output a developer reads' is overstated. `make build` uses `xcodebuild -quiet`, which still prints warnings and errors. The current build/test.log has 0 'warning:' lines, so a new warning would stand out wherever it is shown. What holds: `make test` alone hides warnings, and nothing fails on them.

</details>

### TST-5 · low · NSMicrophoneUsageDescription is never shown, and its text says 'movez'

**Where:** `Sources/movez/Resources/Info.plist:32` · **Category:** dead-code · **DECISIONS checked:** 52

**What goes wrong.** The microphone usage string says 'movez' in lowercase, against DECISIONS 52. The prompt is not expected to appear today, because the property read needs no consent.

**Suggested fix.** Keep the key as a safety net, since a missing usage string crashes the app if a TCC check is ever triggered, and capitalise it to 'Movez checks whether…'.

<details><summary>Verification (confirmed with corrections)</summary>

Confirmed that nothing in Sources calls AVCaptureDevice or requestAccess, and that MicrophoneMonitor only reads kAudioDevicePropertyDeviceIsRunningSomewhere. So the prompt is not expected to show. The string does begin with lowercase 'movez', and DECISIONS 52 says every name a person reads says Movez. CFBundleName and CFBundleDisplayName are already 'Movez'. The suggestion to remove the key is the riskier fix. If any API ever triggers a microphone TCC check, a missing usage string makes macOS terminate the app, so the key is a cheap safety net.

</details>

### TST-6 · low · 'Transitions are identical whatever the scale' compares one run with itself

**Where:** `Tests/movezTests/ClockTests.swift:52` · **Category:** test-gap

**What goes wrong.** `XCTAssertEqual(transitions(tickSeconds: 2), transitions(tickSeconds: 2))` runs the same deterministic simulation twice, so it cannot fail and says nothing about scale. Line 21 is likewise arithmetic on constants. EdgeCaseTests.swift:129-150 read SystemClock and flip the scale with no time passing between the reads. The known rebase bug (re-anchoring with the new scale instead of the old one) would only shift time by microseconds there, less than the time between the reads, so both tests would still pass. ClockTests.testChangingScaleDoesNotJumpTime does catch that bug, but only because it sleeps 0.1 s at 60× first. This is how the 60× poll-gap bug above went unnoticed.

**Suggested fix.** Replace the tautology with a real comparison: 2-second spacing against the 15-second scaled spacing that 60× produces at the 0.25 s floor, driven through SignalAggregator.poll() so gap detection is part of the test. Delete the two EdgeCaseTests scale tests or merge them into ClockTests.

<details><summary>Verification (confirmed)</summary>

Confirmed. Line 52 compares transitions(tickSeconds: 2) with itself, and line 21 is arithmetic on constants. The EdgeCaseTests scale tests (129-150) change the scale with no time passing between the reads, so a rebase that used the new scale would shift time by only microseconds. testChangingScaleDoesNotJumpTime (24-32) does catch that bug, because it sleeps 0.1 s at 60x. The claim that this is how the poll-gap bug was missed is a guess, but the tautology is real.

</details>

### TST-7 · low · Coordinator tests finish breaks through intents production never calls

**Where:** `Tests/movezTests/CoordinatorTestSupport.swift:92` · **Category:** test-gap · **DECISIONS checked:** 38

**What goes wrong.** The coordinator test harness completes breaks through coordinator intents (nextBlock/done) that production never calls. Production progression goes through the overlay's recordOverlayBlock or recordOverlayPart and finishOverlayBreak, so coordinator tests exercise a different recording and completion path, which is how the Movement resume double-recording went unnoticed. Also dead: CompositeEffectSink.add, and SchedulerSnapshot.configHash, which is written but never read (it has no doc comment, so it promises nothing).

**Suggested fix.** Make completeBreak drive a real OverlayViewModel or StrengthOverlayViewModel, wired the way OverlayEffectSink wires it (the strength resume test already does this). Then delete the test-only intents, `.userNextBlock`, `.userDone`, configHash and CompositeEffectSink.add.

<details><summary>Verification (confirmed with corrections)</summary>

Confirmed: the coordinator's nextBlock(), done(), endBreak(), canFinishBreak and elapsedInBreak have no callers in Sources. Scheduler.swift:99 is the scheduler's own nextBlock, not the coordinator's. completeBreak() drives coordinator.nextBlock() (lines 92-99) and is used 12 times across 4 files, while production uses recordOverlayBlock/recordOverlayPart plus finishOverlayBreak(.breakEnded). CompositeEffectSink.add has no callers. configHash is written in three places (Scheduler.swift:15, 254, 274) and never read. Corrected: the configHash declaration (SchedulerSnapshot.swift:59) has no doc comment promising a resume check, so that part of the claim is wrong.

</details>

### TST-8 · low · FullscreenMonitorTests tests the fake's exception list, not the monitor's

**Where:** `Tests/movezTests/FullscreenMonitorTests.swift:33` · **Category:** duplication

**What goes wrong.** testAnExcludedAppNeverSuppresses builds a FakeFullscreenSource and checks the fake's own exception logic. That duplicates FakeSignalsTests.testFakeSourcesHonourTheExceptionList. The real monitor's early return for the user's exceptions and for Movez itself (FullscreenMonitor.swift:24) is untested, and testTheRealMonitorRunsWithoutCrashing only asserts anything when Movez happens to be the frontmost app.

**Suggested fix.** Move the frontmost-app decision into a pure static function (for example `reading(bundleId:exceptions:own:windows:screens:)`) and test that, then delete the duplicate test.

<details><summary>Verification (confirmed)</summary>

Confirmed. Lines 33-39 test FakeFullscreenSource, duplicating FakeSignalsTests.swift:46-51. The real monitor's early return for its own bundle id and the user's exceptions (FullscreenMonitor.swift:24) is checked only by testTheRealMonitorRunsWithoutCrashing, which asserts only when movez happens to be frontmost. The untested logic is one line, so low.

</details>

### TST-9 · low · The 'does not fire a break at launch' checks cannot fail, because the relaunch helper never ticks

**Where:** `Tests/movezTests/LaunchStateTests.swift:140` · **Category:** test-gap · **DECISIONS checked:** 20b

**What goes wrong.** The sink assertions in LaunchStateTests cannot fail, because relaunch() never ticks and applyLaunchGap never emits a break surface. Only testAStateFileWithNoSavedTimeStillDoesNotFireABreakAtLaunch is left with no meaningful assertion, so a regression in the savedAt fallback at AppCoordinator.swift:177 would go unnoticed.

**Suggested fix.** Tick once after applyLaunchGap() in relaunch() (start() runs in that order), and assert nextFullDueAt > now in the no-savedAt test.

<details><summary>Verification (confirmed with corrections)</summary>

The mechanism is correct. relaunch() (lines 22-41) only calls applyLaunchGap(). Its paths (rollDayIfStale, startFreshSession at Sleep.swift:268-276, shiftInterval) return only .persist and .menuRefresh, so every sink check for showHeadsUp, startFullBreak or showToast passes no matter what. In testAStateFileWithNoSavedTime..., if the fallback became `?? clock.now` the gap would be 0, rollDayIfStale would change nothing on the same day, the state would stay sitting with the 06:55 due time, and the test would still pass. Severity lowered: this is a test that cannot fail, not a production bug. The other tests in the file still check nextFullDueAt, which does the real work.

</details>

### TST-10 · low · The font fallback check passes a non-optional value to XCTAssertNotNil

**Where:** `Tests/movezTests/LaunchStateTests.swift:290` · **Category:** test-gap

**What goes wrong.** MovezFont.nsFont returns a non-optional NSFont. Passing it to XCTAssertNotNil wraps it in an Optional, so the assertion always passes. The test registers the font first, so the `?? .systemFont` fallback at Fonts.swift:82, which is what "would still run without it" refers to, never runs. Lines 309-317 are similar: they grep OverlayWindowController.swift for two strings, which a comment would also satisfy.

**Suggested fix.** Test the fallback directly: ask for a family that doesn't exist and assert you get the system font. Drop the grep test, or replace it with a check of the actual notification observer.

<details><summary>Verification (confirmed)</summary>

Confirmed. MovezFont.nsFont returns a non-optional NSFont (Fonts.swift:70), so XCTAssertNotNil always passes. register() runs first, so the `?? .systemFont` fallback at Fonts.swift:82 is not exercised. Lines 309-317 grep the source text for two strings, which a comment would also satisfy (both strings appear at OverlayWindowController.swift:172/176/181).

</details>

### TST-11 · low · The mode-branching test misses `case let .strength(`, and a switch already lives in UI/Panels

**Where:** `Tests/movezTests/ModeExtensibilityTests.swift:90` · **Category:** test-gap · **DECISIONS checked:** 54

*Found independently by the Tests: library, routine, strength, modes, UI review as well.*

**What goes wrong.** DECISIONS 54 says code that tells the modes apart lives only in Modes/, and that this test enforces it by grepping Sources. The regex is `case \.strength|== \.strength|\.movement \?`, which matches only those exact spellings. `case let .strength(x)`, `case .movement:` inside a switch, `!= .strength` and `if let x = planned.strengthBreak` all pass. MicroPanelBreak.swift:95-100 (UI/Panels) switches on PlannedMicro's `.movement`/`.strength` cases and is not flagged. OverlayEffectSink.swift:48-54 picks a view model through `.strengthBreak`/`.endRangeBreak`. The compiler would still catch a third PlannedMicro case in that switch, because it has no default. But the test does not check what the decision says it checks, so the next mode-specific branch outside Modes/ can land unnoticed.

**Suggested fix.** Move `MicroPanelBreak.init(_ planned: PlannedMicro)` into an extension under Modes/, as ModeMenuCopy does for the menu. Widen the pattern to something like `case (let )?\.(strength|movement)\b|[!=]= \.(strength|movement)\b`, with an explicit allow-list for NextFullBreak's `.strength` in Strength/StrengthModeBuilder.swift.

<details><summary>Verification (confirmed)</summary>

The regex at :90 is `case \.strength|== \.strength|\.movement \?`. MicroPanelBreak.swift:95-100 (UI/Panels) has `case let .movement(micro)` and `case let .strength(micro)` and is not flagged. That conflicts with DECISIONS 54 ('Any code that must tell the modes apart lives in Modes/, which a test enforces'). A widened pattern would also hit StrengthModeBuilder.swift:43 and :68 (`if case let .strength(` on the day-plan type), so the suggested allow-list is needed. The exhaustive switch limits the practical risk. Low.

</details>

### TST-12 · low · The Movement golden fixture overwrites itself and passes whenever the record flag is set; its only guard is an audit outside the repo

**Where:** `Tests/movezTests/MovementPicksGoldenTests.swift:47` · **Category:** test-gap · **DECISIONS checked:** Strength mode preamble, 64

**What goes wrong.** A recording run passes rather than failing, and the comment claims an external audit guards the fixture when no check in the repo does. The guard that does exist is the committed fixture's git diff.

**Suggested fix.** Have the record branch end with XCTFail("fixture recorded; rerun without the flag"), and fix the comment so it says the git diff, not an audit, is the guard. Pinning a SHA-256 is optional.

<details><summary>Verification (confirmed with corrections)</summary>

Confirmed. The record branch (lines 47-56) writes the fixture and returns, so the run passes. The doc comment (lines 8-12) cites an 'audit' that does not exist in the repo: the only reference to movement-picks-golden.json outside this file is none. The risk is small, though. Recording requires deliberately setting TEST_RUNNER_MOVEZ_RECORD_GOLDEN=1, and the fixture is committed, so a re-record shows up as a git diff in review. This is test-hygiene hardening, not a medium risk. The point about library-derived contexts is true but expected: a library edit is supposed to change Movement picks.

</details>

### TST-13 · low · testDoneIsNeverOfferedBeforeTheSchedulerWouldAcceptIt compares a function with itself and misses that the overlay reads the wrong config

**Where:** `Tests/movezTests/OverlayViewModelTests.swift:287` · **Category:** test-gap · **DECISIONS checked:** 22, 29

**What goes wrong.** How it works: OverlayViewModel.doneAvailable is literally Scheduler.meetsCompletionRule(completed, total, elapsed, config). The test calls that same function with the same arguments and the same default SchedulerConfig(), and completedBlocks stays 0, so it cannot fail. The risk its comment describes, the overlay and the scheduler disagreeing, does exist one level up. OverlayEffectSink builds the view model with `config: coordinator.settings.schedulerConfig` (OverlayEffectSink.swift:78), whose breakSeconds is always the default 325. The scheduler and AppCoordinator.canFinishBreak (AppCoordinator+Intents.swift:43-52) use `scheduler.config`, whose breakSeconds is set to the break on screen through `.breakLength`. For a 4-block routine (a bucket wholly excluded, 260 s) the overlay's time rule is 162 s and the scheduler's is 130 s. In Movement mode the block half usually hides the gap, so the user-visible effect is small. The test would never notice it.

**Suggested fix.** Pass `coordinator.scheduler.config` in OverlayEffectSink. Rewrite the test to build the view model with a config whose breakSeconds differs from the default, and compare doneAvailable with the scheduler actually handling `.userDone` (via SchedulerHarness).

<details><summary>Verification (confirmed)</summary>

doneAvailable (OverlayViewModel.swift:148-155) is Scheduler.meetsCompletionRule with the view model's config. The test calls the same function with the same default SchedulerConfig(), so it cannot fail. OverlayEffectSink.swift:78 passes settings.schedulerConfig (the default breakSeconds), whereas canFinishBreak and the scheduler use scheduler.config, which .breakLength keeps at the planned length (AppCoordinator.swift:406, Scheduler.swift:272). On a shorter routine the overlay's time threshold is therefore higher than the scheduler's. That makes the overlay stricter, so Done is still never offered before the scheduler would accept it. The only visible effect is that the Done/Snooze swap, and pause expiry ending as done, come later than they should. That is low, as the finding says.

</details>

### TST-14 · low · testNoChimesWhenSoundsAreOff only tests the fake player's own switch

**Where:** `Tests/movezTests/OverlayViewModelTests.swift:352` · **Category:** test-gap · **DECISIONS checked:** 23a

**What goes wrong.** How it works: it sets `chimes.enabled = false` on RecordingChimePlayer and asserts nothing was recorded. RecordingChimePlayer.play starts with `guard enabled else { return }` (Sources/movez/Audio/Chimes.swift:66-70). The test therefore proves the fake drops sounds when told to, whatever the overlay does. The app's real Sounds gate is GatedChimePlayer, tested in SettingsWindowTests and AwayReturnTests. This test adds nothing, and RecordingChimePlayer.enabled exists only to serve it.

**Suggested fix.** Delete the test and RecordingChimePlayer.enabled, or rewrite it to wrap the recorder in GatedChimePlayer with isEnabled false.

<details><summary>Verification (confirmed)</summary>

The test sets chimes.enabled = false, and RecordingChimePlayer.play begins with `guard enabled else { return }` (Chimes.swift:66-70). This is the only place enabled is set to false in Tests (grep). The assertion therefore checks only the fake. The real gate is GatedChimePlayer (Chimes.swift ~55-58).

</details>

### TST-15 · low · Old state files are only tested by removing one key from a freshly encoded snapshot

**Where:** `Tests/movezTests/PersistenceTests.swift:24` · **Category:** persistence

**What goes wrong.** Swift's synthesized Decodable requires every non-optional key even when the property has a default value, and AppCoordinator.restore quietly starts fresh when decoding fails. So an incompatible change to SchedulerSnapshot silently throws away the user's countdown and the day's counters, with nothing but a log line. The only compatibility test takes a snapshot encoded by the current build and deletes `savedAt`. Nothing decodes a file written by an earlier build. In particular, the `GraceResume.applyGap` case that SchedulerState.swift:12-14 says "still decoded", and the later optional fields (awayInputAge, remainingMicroAtAwaySeconds, lastAbsenceEndedAt, CreditRestore.microAnchorAt), have no decode test.

**Suggested fix.** Commit a real state.json from an older build as a fixture (like Fixtures/movement-picks-golden.json), including one saved mid-grace with `applyGap`, and assert that it decodes and that applyGrace handles it.

<details><summary>Verification (confirmed)</summary>

Confirmed. SchedulerSnapshot has no custom init(from:), and its own comment at line 57 says the synthesized decoder needs every non-optional key. AppCoordinator.restore (around 196-203) catches the failure, logs it and starts fresh. The only compatibility test removes savedAt from a snapshot the current build just encoded. Nothing in Tests decodes GraceResume.applyGap: grep finds none. Fixtures/ holds only movement-picks-golden.json. This is a real missing test for a path that loses data, so low is right.

</details>

### TST-16 · low · testInMemoryStoreRecordsEverySave only tests its own loop

**Where:** `Tests/movezTests/PersistenceTests.swift:70` · **Category:** test-gap

**What goes wrong.** The test calls store.save() once for each .persist effect, then asserts that saveCount equals the number of .persist effects. It is counting its own loop, on a test-only store. Production code never runs in it. The real claim (the coordinator writes the state file once per persist) is already tested in CoordinatorSimulatedDayTests.testStateAndHistoryAreWrittenOnEveryChange.

**Suggested fix.** Delete the test.

<details><summary>Verification (confirmed)</summary>

Confirmed. Lines 66-77 save once per .persist effect and then assert saveCount equals the number of .persist effects, on InMemorySnapshotStore, a test-only store. It runs no production code. CoordinatorSimulatedDayTests.swift:177 testStateAndHistoryAreWrittenOnEveryChange covers the real claim. testEveryTransitionEmitsPersist (79-90) already covers the persist count.

</details>

### TST-17 · low · testApplicationSupportDirectoryIsCreated creates a folder in the real ~/Library/Application Support

**Where:** `Tests/movezTests/PersistenceTests.swift:132` · **Category:** test-gap

**What goes wrong.** The test calls the production FileSnapshotStore.applicationSupportDirectory(). That function runs createDirectory on ~/Library/Application Support/movez, so on any machine without Movez installed (a fresh Mac, CI) the test suite creates the app's real data folder. CLAUDE.md says tests must never read or write the user's real Application Support. Today the only harm is an empty folder, but the test exercises the one code path that leads to the real state.json and history.json, so a later change there would make it touch real data.

**Suggested fix.** Give applicationSupportDirectory a `base: URL` parameter that defaults to the system location, and test it against a temporary folder, as the other persistence tests already do.

<details><summary>Verification (confirmed)</summary>

Confirmed. The test calls the production FileSnapshotStore.applicationSupportDirectory() (StatePersistence.swift:41-51), which runs createDirectory on the user-domain Application Support/movez folder. The app is unsandboxed (movez.entitlements), so this is the real folder, which goes against CLAUDE.md's rule that tests never touch the user's real Application Support. Today it only creates an empty folder.

</details>

### TST-18 · low · The "split shift" test uses the wrong weekdays and passes for another reason, so the working-day-opening reset is untested

**Where:** `Tests/movezTests/SchedulerDayBoundaryTests.swift:202` · **Category:** test-gap · **DECISIONS checked:** 14, 23c

*Found independently by the Tests: scheduler, coordinator, signals, persistence, settings review as well.*

**What goes wrong.** `testAGapAcrossAWorkingDayThatClosedAndReopenedStartsItFresh` sets `days[2]` and `days[3]`, with comments saying Monday and Tuesday. `WorkingHours.days` is indexed weekday − 1, so index 0 is Sunday and those are Tuesday and Wednesday; Monday is off. On the first tick of the grace, `applyWorkingHours` sends the scheduler to `.offHours`, and the next tick's midnight roll zeroes `skipsToday`. The 110-minute gap would be standby in any case. So `crossedWorkingDayOpening` → `resetDay` (Scheduler+Idle.swift:68-69) is never exercised by any test, and in practice it is reachable only from an ad-hoc session.

Similarly, `testStandbyRollsTheCountersOnlyWhenTheAbsenceCrossedMidnight` passes because of the tick's midnight roll, not standby's. `testALongGapEndsAnInterruptedBreakByTheCompletionRule` uses a `run(until:)` predicate (`!= .away(since: harness.now)`) that is satisfied immediately. Outside this area's tests, `PersistenceTests.testApplicationSupportDirectoryIsCreated` (line 136) creates the real `~/Library/Application Support/movez`, which CLAUDE.md forbids.

**Suggested fix.** - Fix the indices (Monday = `days[1]`), and assert the state and that the reset reason appears in the transition log.
- Add a direct test of `endAbsence` crossing an opening from an ad-hoc session, or delete the branch if it is not wanted.
- Make the interrupted-break test's predicate meaningful.
- Point the Application Support test at a temporary directory.

<details><summary>Verification (confirmed)</summary>

WorkingHours.days is indexed weekday-1 (WorkingHours.swift:35,74), so days[2] and days[3] are Tuesday and Wednesday, and the harness date defaults to Monday 7 Sep. After the wake the first tick sends the grace state to .offHours (Tuesday 00:45 is outside the 20:00-23:00 window), and rollDayIfStale zeroes skipsToday. The 110-minute absence is also ≥ sitSeconds, so standby (checked first in endAbsence) would win anyway. A grep finds no test reaching crossedWorkingDayOpening→resetDay, which is reachable only from an ad-hoc session or a split shift with an absence shorter than the interval. The other claims hold too: AwayReturnTests' poll() sends .tick, so the midnight roll happens during the away loop; the interruption test's run(until:) predicate is satisfied at once by postBreakGrace; and PersistenceTests:131 calls applicationSupportDirectory(), which creates the real ~/Library/Application Support/movez.

</details>

### TST-19 · low · The check that the micro-break is not lost cannot fail

**Where:** `Tests/movezTests/SchedulerMicroTests.swift:116` · **Category:** test-gap · **DECISIONS checked:** 23h

**What goes wrong.** `XCTAssertNotNil(nextMicroDueAt ?? nextFullDueAt)` can never fail in the sitting state, because nextFullDueAt is always set there. With 55/5 the micro-break's re-anchor falls inside the quiet zone, so nextMicroDueAt is nil whatever happens, and the line checks nothing. Decision 23h is about the micro-break that is on screen being allowed to finish, which the earlier state checks already cover. This line adds no protection.

**Suggested fix.** Assert the outcome 23h promises: the micro-break ended through endMicro (a .recordMicroDone or .chime(.completion) effect). Or use an 85/5 config, where the next micro-break should be scheduled, and assert nextMicroDueAt itself.

<details><summary>Verification (confirmed)</summary>

Confirmed. In sitting after a micro-break, nextFullDueAt is always set, so `nextMicroDueAt ?? nextFullDueAt` is never nil and the assertion cannot fail. The run(until: isSitting) and the suppressed check that follow already cover what 23h promises.

</details>

### TST-20 · low · The 'never talks to the network' entitlement check proves nothing for an unsandboxed app

**Where:** `Tests/movezTests/SecurityAndCopyTests.swift:18` · **Category:** test-gap · **DECISIONS checked:** 3

**What goes wrong.** The source scan behind testTheAppCodeCannotReachTheNetworkOrRunAProcess (lines 16-34) bans only URLSession, NSURLConnection, Process(), NSTask, system( and popen(. Remote Data(contentsOf:) or String(contentsOf:), NWConnection and posix_spawn would get through, so the test does not prove what its name claims. The entitlements test is accurate entitlement hygiene; only its failure message overstates it.

**Suggested fix.** Widen the banned list (`import Network`, NWConnection, posix_spawn, a contentsOf: with a URL(string: argument), or check the built binary with otool -L for networking frameworks. Reword the entitlements test's failure message rather than removing the test.

<details><summary>Verification (confirmed with corrections)</summary>

Partly refuted. testTheEntitlementsClaimNothingBeyondWhatIsUsed (55-61) does what its name says: it keeps the entitlements file free of extra claims. That is meaningful hygiene even with app-sandbox false (decision 3); only its failure message overstates it. The real gap is the source scan. testTheAppCodeCannotReachTheNetworkOrRunAProcess bans URLSession, NSURLConnection, Process(), NSTask, system( and popen(. It would not catch Data(contentsOf:) or String(contentsOf:) with a remote URL, Network.framework (NWConnection), or posix_spawn, so its name claims more than the scan proves.

</details>

### TST-21 · low · The signal-polling tests count their own loop, so the pollCount assertions cannot fail

**Where:** `Tests/movezTests/SignalAggregatorTests.swift:37` · **Category:** test-gap · **DECISIONS checked:** 21

**What goes wrong.** The poll(_:harness:seconds:) helper skips aggregator.poll() whenever the scheduler says polling isn't needed. The aggregator is also never attached to the coordinator, so nothing in the app could stop it. Both `pollCount == 0` assertions in testNoPollsWhilePausedOrOffHours are therefore guaranteed by the helper's own guard. testPollsEveryTwoSecondsWhileSitting counts the helper's 30 loop iterations, not the 2 s timer. EdgeCaseTests.swift:175-177 has the same shape: its real DispatchSourceTimer cannot fire during a synchronous ManualClock loop, so pollCount can't change. What actually matters is the coordinator calling aggregator.setPolling(false) when the scheduler goes paused or off hours. That is covered for pause (the EdgeCaseTests isRunning checks) but not for off hours.

**Suggested fix.** Attach the aggregator (`harness.coordinator.aggregator = aggregator; aggregator.setPolling(true)`). Assert aggregator.isRunning goes false when the working day closes at 18:00 and true again at 09:00. Check the cadence with `pollInterval == 2` rather than a loop count. Remove the guard from the helper and the pollCount assertion from EdgeCaseTests.

<details><summary>Verification (confirmed)</summary>

Confirmed. The helper at lines 32-40 skips poll() when !pollingRequired, and the aggregator is never attached to the coordinator, so both pollCount == 0 checks (55, 62) come from the helper's own guard. The pollCount == 30 check counts the loop's iterations. The EdgeCaseTests.swift:175-177 pollCount check cannot move during a synchronous loop. Coordinator-driven setPolling is tested for pause (EdgeCaseTests isRunning) but not for off hours. The scheduler does emit pollingChanged for off hours (SchedulerInterruptionTests 344-369), and the coordinator path is the same generic one, so the risk is small.

</details>

### TST-22 · low · StrengthRuleChecker borrows the builders' own predicates for several rules, and its s6-dose check cannot fail

**Where:** `Tests/movezTests/StrengthRuleChecker.swift:140` · **Category:** test-gap · **DECISIONS checked:** 69

**What goes wrong.** How it works: the checker says it is 'written against the rules, not the builders'. Yet s6-warm-up-shape uses StrengthBreakBuilder.isWarmUpShaped (line 140). Every difficulty rule uses StrengthEligibility.isWithinDifficulty (lines 64, 233). s7-same-posture uses StrengthPosture (line 201). The micro opener and partner checks use StrengthMicroBuilder.isPartner (lines 214, 220, 248). A bug in any of these, such as isPartner ignoring posture, changes the builder and the checker the same way, so the cross-check stays at zero violations. Separately, s6-dose (line 104) compares each set's dose with the library's, but StrengthSet.init always copies movement.dose (StrengthBreak.swift:107), so the check can never fail. The Python checker has the same blind spot through `(m, m.dose)`. Mitigation: StrengthBreakBuilderTests checks warm-up shape and difficulty independently. Posture and partner have no independent oracle.

**Suggested fix.** Write the four predicates out inside the checker from the rule text, as simulate_strength.py does with warm_up_shaped and within_difficulty. Drop s6-dose, or turn it into a check on what the dose drives (StrengthSet.plannedSeconds and reps against an independent parse).

<details><summary>Verification (confirmed)</summary>

The checker reuses StrengthBreakBuilder.isWarmUpShaped (line 140), StrengthEligibility.isWithinDifficulty (lines 64, 233), StrengthPosture (line 201) and StrengthMicroBuilder.isPartner (lines 214, 220, 248). isPartner is defined as id != first.id && !perSide && same StrengthPosture (StrengthMicroBuilder.swift:95-97), which is the same predicate the builder uses. The s6-dose check (lines 104-106) compares set.dose with library.dose, and StrengthSet.init assigns dose = movement.dose (StrengthBreak.swift ~107), so it can never fail. StrengthMicroBuilderTests:57-66 checks equal posture, but only through the same StrengthPosture, so posture itself has no independent oracle.

</details>

### TST-23 · low · testTheSheetCarriesNoAtLeastOneGate checks whole-string equality, so it can never find the phrase

**Where:** `Tests/movezTests/StrengthSettingsWindowTests.swift:218` · **Category:** test-gap · **DECISIONS checked:** 56

**What goes wrong.** How it works: `[StrengthSetupSheet.intro, StrengthSettingsSection.breaksSub].contains("Choose at least one.")` is Array.contains, which asks whether an element equals that exact string. Both copy strings are long sentences (StrengthSetupSheet.swift:18, StrengthSettingsSection.swift:53), so the assertion passes even if "Choose at least one." were added to either. It also never looks at the sheet's view, where such a note would actually be drawn.

**Suggested fix.** Use `copy.allSatisfy { !$0.contains("Choose at least one") }`, and check the strings the sheet renders, for example by grepping StrengthSetupSheet.swift as other source-reading tests do.

<details><summary>Verification (confirmed)</summary>

`[intro, breaksSub].contains("Choose at least one.")` is Array element equality, and both strings are full sentences (StrengthSetupSheet.swift:18, StrengthSettingsSection.swift:53), so the assertion is vacuous. The second assertion, strengthSetupCanConfirm, carries the test's real value, which limits the impact.

</details>

### TST-24 · low · check_strength_library.py allows doses that DECISIONS 60 rules out, with no decision recorded

**Where:** `scripts/check_strength_library.py:48` · **Category:** correctness · **DECISIONS checked:** 60, 70

**What goes wrong.** Two COR doses, COR-05 (12 alternating with a 2 s hold) and COR-17 (12 alternating), sit outside DECISIONS 60's 16-20 alternating range. The checker reports them on every run as left for the owner, but no DECISIONS entry settles them. The 8-12 per-side arm range is not covered by DECISIONS 60, which predates the arm buckets, but it matches the library's design_rules.

**Suggested fix.** Decide COR-05 and COR-17: bring them to 16-20, or add them to DECISIONS 60's named exceptions (and SLOW_EXCEPTIONS). Optionally note the arm buckets' 8-12 per-side range in DECISIONS 70.

<details><summary>Verification (confirmed with corrections)</summary>

COR-05 '12 reps, alternating, 2 s hold' and COR-17 '12 reps, alternating' really are outside DECISIONS 60's 16-20 alternating range, and no DECISIONS entry records them. Two corrections. First, they are not known only from the comments. Running the script prints 'finding: COR-05 … left for the owner' and the same for COR-17 every time (lines 246-247). Second, TRI-04's 12/side is not a contradiction. DECISIONS 60 lists its working buckets as SQT, HNG, PSH, PUL, COR, ACC, and BIC and TRI arrived later in DECISIONS 70. The 8-12 per-side arm range matches the library's own design_rules.rep_targets.per_side [8, 12]. The regex point is moot, because RECORDED_FINDINGS pins the exact dose string.

</details>

### TST-25 · low · diff_strength_library.py and the snapshot-baseline tools only work until this branch merges

**Where:** `scripts/diff_strength_library.py:26` · **Category:** dead-code · **DECISIONS checked:** 50, 62, 70, 71

**What goes wrong.** diff_strength_library.py, compare_snapshots.py's default baseline and snapshot-agreed-changes.txt are tied to one migration, the strength-mode edits. They work only against the pre-strength baseline, and no doc or script names that commit. After the merge, the obvious choice, `--base main`, would report every agreed edit as missing.

**Suggested fix.** Record the pre-strength baseline sha in each tool's docstring or default. Or, after the merge, mark them as one-off migration tools (or delete them) and keep check_strength_library.py as the standing invariant guard.

<details><summary>Verification (confirmed with corrections)</summary>

diff_strength_library.py hard-codes one migration (lines 26-35) and requires every expected change to be present. But `--base` is a required, free git ref (line 259), and no doc or Makefile target tells anyone to use `main`. Given the pre-strength commit as its base, it keeps working after the merge and still catches drift outside the agreed edits. So it does not turn into a script that always fails. The real gap is that the correct base ref is recorded nowhere, and `main` stops meaning 'before the edits' once this branch merges. compare_snapshots.py likewise takes --base-ref, and its 'before the strength-mode work' baseline is tied to the same one-time review.

</details>

### TST-26 · low · fetch_font.sh deletes the committed Manrope font when both downloads fail, and fetches an unpinned upstream

**Where:** `scripts/fetch_font.sh:35` · **Category:** correctness

**What goes wrong.** download() has curl write straight to the final path, Sources/movez/Resources/Fonts/Manrope[wght].ttf, which is committed. When both the primary and the mirror fail, it runs `rm -f "$out"`. So `make assets` offline, or when GitHub rate-limits, removes the bundled font from the working tree, and the next build draws in the system face (MovezFont.register only asserts in Debug). Separately, both URLs (lines 9-12) point at google/fonts `main` with no checksum. A re-fetch after an upstream Manrope update silently replaces the committed font, which shifts every snapshot.

**Suggested fix.** Download into a `mktemp` file and `mv` it into place only after the size check passes, leaving the existing file alone on failure. Pin a google/fonts commit in the URLs and check a SHA-256 before moving the file.

<details><summary>Verification (confirmed)</summary>

download() has curl write directly to the final path, `--output "$out"`. When both fetches fail it runs `rm -f "$out"` (line 35), which deletes the existing, git-tracked Sources/movez/Resources/Fonts/Manrope[wght].ttf (and OFL.txt). Its only caller is `make assets`. A timeout partway through a transfer can also leave a truncated file at the final path before the size check. The URLs (9-12) use google/fonts `main` with no checksum. The impact is limited because git checkout restores the file.

</details>

### TST-27 · low · simulate_selection.py claims to be 'the model to re-run' but no longer models RoutineBuilder or MicroBreakBuilder

**Where:** `scripts/simulate_selection.py:62` · **Category:** correctness · **DECISIONS checked:** 28, 32, 41, 45

**What goes wrong.** The docstring (lines 6-9, 13-14) says the 'proposed' rules are 'what the app now ships ... so it is the model to re-run' and asks to be re-run whenever the library changes. Since then the builders gained families (DECISIONS 45), and the Python has none: full_pool (lines 62-73), the taken check (line 204), proposed_micro (lines 218-228) and recency_weight (lines 40-46) all key on the id, whereas RoutineBuilder uses familyKey and FamilyIndex.scores. Run against today's library, the Python serves two members of one family in 2.7% of full breaks and on 91.7% of 5-full/6-micro days. RoutineBuilder can never do either. It also ignores `requires` (DECISIONS 41). Its micro floor filter `m["settings"] != ["floor"]` (line 77) can never match, because the library writes `Floor` and the requirement lives in `requires`. It has no forgettingToday fallback (RoutineBuilder.swift:46-51), so where Swift repeats a movement, the Python serves a short break. And proposed_micro crashes on an empty pool (`first["per_side"]` on None) or returns `[first, None]`, where MicroBreakBuilder relaxes or runs one movement for the full minute.

**Suggested fix.** Either relabel it as the October 2026 analysis tool ('models the rules as of <sha>; not the shipped builder') and remove the 're-run whenever the library changes' advice, or port it: family keys for used, taken and recency, `"floor" in m["requires"]` plus the unavailable set, the forgettingToday fallback and MicroBreakBuilder's fallbacks.

<details><summary>Verification (confirmed)</summary>

The docstring (6-14) calls 'proposed' what the app ships and the model to re-run whenever the library changes. The script never references `family` or `requires`, though the library has 73 family-tagged movements and 50 non-empty requires. The keying is by id in full_pool (62-73) and recency_weight (40-46). micro_pool's `m["settings"] != ["floor"]` (77) can never match, because the library writes 'Floor'. It is harmless today, since no micro-eligible move requires the floor. proposed_micro (218-228) dereferences `first["per_side"]` without a None check. The last commit touching the script is c539e73 (Oct 2026 docs). I did not re-verify the 2.7% and 91.7% figures, but the missing family handling is plain from the code.

</details>

### TST-28 · low · The simulated day keeps its records differently from the coordinator, so the report understates the servedToday relaxations about threefold

**Where:** `scripts/simulate_strength.py:879` · **Category:** correctness · **DECISIONS checked:** 59, 64, 67, 69

**What goes wrong.** The builders are mirrored exactly, but the day the simulation feeds them is not the day AppCoordinator builds. (1) A skipped strength break hits `continue` at line 881 before serve(), so its moves stay unserved. In the app, beginBreak calls rememberBreak (AppCoordinator+Effects.swift:113), and idsServedToday unions breaksToday (lines 317-320). So a break skipped from the overlay keeps its five moves 'served today', and the re-offered break must avoid them. (2) serve() (lines 934-943) counts each distinct move once. The app records one completion per part (ModeBuilder.swift:21-29), so the X of X · Y · X (and an arm break's main move) counts twice in recencyScores. (3) last_micro resets every day (line 846), while lastMicroIds survives midnight (rollDayIfNeeded at AppCoordinator+Effects.swift:343-348 does not clear it). (4) `worked` takes only the sets' regions (line 894), but StrengthModeBuilder.workedRegionsToday (lines 116-123) also counts warm-ups. I re-ran the loop with (1) and (2) modelled the app's way. Violations stayed at 0, but strength `servedToday` relaxations went from 43 to 124 per 1,000 for `--W2` and from 241 to 427 at the defaults. The weekly-set tables are not affected, because the plan depends only on the letters. The Swift cross-check harness (StrengthSimulationCrossCheckTests.swift:203-214, 239-242) makes the same simplifications.

**Suggested fix.** In simulate(), add a skipped break's ids_of(brk) to `served` (or model both a heads-up skip and an overlay skip), add one history count per set, keep last_micro across days, and include the warm-up's regions in `worked`. Make the same changes in StrengthSimulationRun so both harnesses model the coordinator.

<details><summary>Verification (confirmed)</summary>

Traced each point. (1) The skip at 879-881 `continue`s before serve(). In the app, beginBreak calls rememberBreak (AppCoordinator+Effects.swift:113), and idsServedToday unions breaksToday (317-320), so an overlay skip keeps the moves served today. The Python models only a heads-up skip. (2) serve() (934-943) dedups the sets with dict.fromkeys, while PlannedBreak.parts (ModeBuilder.swift:21-29) records one completion per set, and HistoryStore.recencyScores (207-218) sums per completion. (3) last_micro is reset per day (846), but lastMicroIds is not cleared in rollDayIfNeeded (343-348). (4) `worked` takes the sets' regions only (894), while StrengthModeBuilder.workedRegionsToday (116-123) counts every non-END completion, warm-ups included. The Swift harness makes the same choices: complete() returns early on skip, and serve() and recency are per distinct id. I did not re-run to check the quoted 43→124 per-1,000 figures. This affects only the reported relaxation rates.

</details>

## The five things to fix first

1. **SCH-1: settings changes re-plan from the bout start** (`Scheduler.swift:257`). This is the
   most likely bug to be hit. Almost every Settings click and every mode switch sends
   `.settingsChanged`, and `apply()` then sets the next break to `boutStartedAt + sit`. After a
   skip, a manual pause or a finished micro-break, the bout start is no longer where the countdown
   was planned from. So the break (or a second micro-break) comes straight back. The fix is to
   re-plan by the *change* in the interval: shift `nextFullDueAt` by the difference in
   `sitSeconds`, and leave the micro-break alone unless its own settings changed. Then add tests
   that change a setting after a skip, a pause and a micro-break.
2. **UI-2 + SCH-3: display sleep during a break, and settling it without history.** Nothing holds
   a display-sleep assertion during a full break. On a laptop on battery the display sleeps one to
   two minutes into the break. That counts as an interruption, and if the break is settled after its
   planned end, no `BreakRecord` is written. The menu, the streak and the strength planner (which
   replays history) then disagree with the scheduler. Fix in two parts:
   - take `kIOPMAssertionTypePreventUserIdleDisplaySleep` (or
     `ProcessInfo.beginActivity(.idleDisplaySleepDisabled)`) while the overlay is up;
   - have `resumeInterruptedBreak` emit `.endFullBreak(.completed/.skipped)`, so the coordinator
     records the outcome from the session it kept. Share the skip branch with `rescheduleAfterSkip`.
3. **UI-1: a resumed Movement break replays its blocks and writes them to history again**
   (`OverlayEffectSink.swift:87`, `AppCoordinator+Intents.swift:81`). Pass the session's
   `blockIndex` and completed count into the rebuilt `OverlayViewModel`. Then make
   `recordOverlayBlock` take the index and ignore one already recorded, the way
   `recordOverlayPart(index:)` already does for strength. The duplicate rows skew recency and the
   difficulty-3 unlock for days, so this is a data-quality fix as well as a UI one.
4. **SIG-1: fullscreen suppression never fires on a notched MacBook's built-in display**
   (`FullscreenMonitor.swift:35`). Native fullscreen windows sit below the camera housing, so they
   never match `NSScreen.frame` within 1 pt. Also accept a match against the frame minus
   `safeAreaInsets.top`, and add a test with a notched frame. Until then, the "suppress during
   fullscreen" setting does nothing on the laptop panel.
5. **SCH-2: a stale deferral after an absence** (`Scheduler+Idle.swift:127`). Clear
   `deferredFullDueAt` and `deferredReason` in `startFreshInterval`. Have `resumeAfterSuppression`
   read the deferral carried in `.suppressed(deferredFullDue:)` rather than the snapshot copy.
   Otherwise a later call ends in a break 30 minutes early, and a fresh break is shown as "waited
   for your call" with one snooze.

Two cheap fixes worth doing at the same time:
- **UI-8.** `StrengthOverlayViewModel.pauseExpired` needs the same `doneAvailable` branch as the
  Movement model (DECISIONS 38).
- **UI-9.** `activeScreen()`'s `NSScreen.screens[0]` fallback traps when the only display goes
  away.
