# movez — Product brief v1

Owner: Kyle Mack · Date: 2026-09-11 · Status: ready for design mockups
Companion docs: `movement-library-v4.md` / `.json` (content and rules), `scheduler-research-v1.md` (scheduler behavior and rationale)

## 1. What it is

movez is a macOS menu-bar app that limits how long you sit at the computer. You choose how long you're allowed to sit (default 55 minutes); when the time is up, the screen dims and the app walks you through a 5-minute movement routine built from a library of 147 movements chosen to counteract the effects of sitting and screen work: hip flexor shortening, glute inhibition, thoracic kyphosis, forward head, venous pooling, stiff ankles, eroding balance, and wrist, eye, and breathing strain. On the longer presets, a 1-minute micro-break every 30 minutes keeps sitting bouts under the threshold the research associates with harm.

The tone is light and encouraging, never nagging. The app gets out of the way when you're on a call or sharing your screen, credits you when you get up on your own, and makes skipping possible but visible.

## 2. Why

The strongest evidence on sedentary work (Dunstan 2012, Diaz 2017, Duran 2023) says two things: interrupt sitting at least every 30 minutes, and a 5-minute movement bout does measurably more than a 1-minute one for glucose, blood pressure, mood, and fatigue. Existing break apps are built for eyes and wrists, treat "not typing" as resting, and either interrupt at the worst moments or are so easy to dismiss they get ignored. None prescribes a progressive movement routine. movez combines an interruption-aware scheduler with a real movement library.

## 3. Who it's for, and v1 scope

v1 is a personal tool for one user (Kyle), working at a home office with a Mac and, optionally, a resistance band, kettlebell or dumbbell, and foam roller or ball. It is built and run locally: no App Store, no accounts, no sync. It should still be built as if it might be shared later, so defaults are sensible and permissions are requested with explanation, but onboarding polish is not a v1 goal.

**Explicitly out of v1:** illustrations or video for movements (text only); iCloud sync, cloud, or accounts; Apple Watch, HealthKit, or step data; gamification (streaks, scores, badges); calendar-based suppression (v1.5); a routine editor (v1.5); illustrations of any kind.

## 4. Goals and success criteria

Goals: (1) the user actually takes the breaks: at least 80% of scheduled full breaks completed over a typical week; (2) the app never fires during a call or screen share, and never immediately after the user sits back down; (3) routines cover the six body-region groups across a day without repeating a movement; (4) the app is invisible when it isn't needed: no Dock icon, under 1% CPU idle, no polling while paused or off-hours.

Non-goals: building muscle, replacing exercise, tracking health metrics.

## 5. Core experience

**Sitting.** The menu-bar icon shows time to the next break. The menu offers Take a break now, Make due in (5/10/15/30 min), Pause for (15 m / 30 m / 1 h / 2 h / rest of day), today's line (breaks done / snoozed / skipped, longest sitting bout), and Settings.

**Micro-break (55/5 and 85/5 presets).** At minute 30 (and 60), a small non-blocking panel appears at the top of the active display with one micro-eligible movement, its instruction, and a 60-second countdown. Snooze 5 min once; a second snooze skips it. No dimming.

**Heads-up.** Sixty seconds before a full break, a panel shows the routine's name and focus ("Hip reset · hips and glutes"), with Start now and +5 min. The app waits for a 10-second pause in typing or dragging (max 60 s) before showing it.

**Full break.** All displays dim to ~70%; the routine card appears on the display with the cursor, other displays show a small "movement break" label. The card is readable from two metres: movement name in large type, the 2–4 sentence instruction (collapsible per movement via "I know this one"), a countdown ring for the current block, a strip of the routine's 4–5 blocks with the current one highlighted, Next / Back, and, in the footer, Snooze 5 min (max 2 per break) and Skip (button enabled after 3 s, showing today's skip count). Blocks auto-advance with a soft chime at each transition; a "/side" block chimes at the halfway point. Done appears once half the routine is complete. At the end, a completion chime, the overlay fades, and focus returns to the previous app.

**Away.** If the user is idle 3–5 minutes, that counts as the micro-break; 5 minutes or more counts as the full break and a fresh interval starts on return. A 6-second toast on return says what was credited, with one-click "I was sitting" to reverse it. Sleep and screen lock are treated the same way, and nothing fires in the first minute after wake.

**Suppressed.** While the microphone is in use, the screen is being captured, or a fullscreen app is frontmost (whitelistable), full breaks are deferred, never reset; micro-breaks are dropped. Two minutes after the signal clears, the deferred break runs through the normal heads-up. If it waited more than 30 minutes, the heads-up says so and shows the sitting time.

## 6. Routine generation

Each full break is assembled from the library using the chaining rules in the library doc: four blocks by default (CIR → FLX → STR or BAL → HWF/EYE/BRE), regions rotating through the day (hip → T-spine/chest → neck/shoulder → posterior chain → core → ankle/foot), no movement repeated in a day, first break CIR-heavy, last break FLX + BRE, post-lunch break CIR + BAL, and balance served daily. The user steers lightly: equipment on hand, a per-movement exclude list, and an optional focus ("more balance", "more upper back"). Difficulty defaults to 1–2; a Diff 3 movement unlocks in a region after its Diff 2 counterpart is completed five times, and Settings also has a manual cap (Beginner / Moderate / Advanced). Equipment movements are substituted with their bodyweight peers when the equipment isn't set.

## 7. Settings (single window)

Preset (25/5, 55/5, 85/5, custom) and micro-break on/off · Working hours per day, default Mon–Fri 9–6 · Equipment on hand · Difficulty cap · Excluded movements (searchable library list) · Focus · Suppression signals (mic, screen capture, fullscreen) with a fullscreen whitelist · Sounds on/off · Away threshold (default 3 min) · Launch at login · A debug section with a time-scale factor (1×/10×/60×), signal injectors, and a state inspector.

## 8. Constraints and technical notes

Native Swift/SwiftUI, macOS 14+, menu-bar app (`MenuBarExtra`), no Dock icon. Scheduler is a persisted state machine over wall-clock timestamps evaluated by a tick (see scheduler research §5 and §6 for states, transitions, and defaults). OS signals: idle via `CGEventSource.secondsSinceLastEventType` (no Accessibility permission); sleep/wake/lock via `NSWorkspace` notifications plus tick-gap detection; microphone via CoreAudio "device is running somewhere"; screen capture via ScreenCaptureKit or a process list fallback; fullscreen via `NSWorkspace.frontmostApplication` and window bounds; Focus via a shippable Focus Filter (no polling for DND). The library ships as `movement-library-v4.json`, regenerated from the markdown by `md_to_json.py`; the app must not hard-code movements. Overlay windows cover every display at a level above fullscreen apps, swallow keystrokes, and restore focus afterwards. Poll at 2 s, not at all while paused or off-hours.

## 9. What design needs to produce

Four screens, in priority order: (1) the full-break overlay, including its collapsed-instruction and "/side" states, and the end-of-break state; (2) the heads-up and micro-break panels (same component family) and the away toast; (3) the menu-bar dropdown, including paused and off-hours states; (4) the Settings window. Design principles: readable from standing distance; calm, dimmed, never alarming; one primary action per state; snooze easier than skip; time remaining always visible; the light, encouraging voice ("Time to move — hips today") without exclamation marks.

## 10. Open items

Sound design for the three chimes (heads-up, transition, completion). Whether the away toast should offer "I was sitting" for the ≥5 min case as well as the 3–5 min case (proposed: yes). Exact copy for suppression and deferral messages.
