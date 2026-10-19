# Handoff: Movez UI — full-break overlay, panels, menu, settings

## Overview
Movez is a macOS menu-bar app that interrupts long sitting bouts with scheduled movement breaks. This package covers the approved v1 visual design for every user-facing surface listed in Product brief v1 §5–§7: the full-break overlay (four states), the heads-up panel, the micro-break panel (count-in and countdown), the away toast, the menu-bar dropdown (three states), and the Settings window. Scheduler behaviour is specified in `reference/scheduler-research-v1.md`; this document only covers what it looks like.

## About the design files
`movez-ui-designs.dc.html` is a **design reference built in HTML** (open it in a browser; `support.js` must sit beside it). It is a mockup canvas, not production code. The job is to **recreate these designs in the Movez codebase** (SwiftUI / AppKit per the brief) using its own patterns. Do not port the HTML.

The canvas has three turns, newest at top. **Only turn 3 (`#3a`, `#3b`, `#3c`) and option `#2a` in turn 2 are approved.** Turn 1 (`#1a`–`#1e`) is rejected exploration kept for history; ignore it.

Screenshots of the approved options are in `screenshots/`. Full-break screens are rendered at 50% (real size 1440×900); the turn-3 panels are 1:1.

## Fidelity
**High-fidelity.** Colours, type, sizes, radii and copy are final. Match them.

## Design tokens

Colours
- `ink` #08161f — screen dim base, text on seafoam, timer ring
- `panel` rgba(18,42,58,.92) on panels/overlay card; rgba(18,42,58,.94) on small panels; .96 on menu; solid #12283a for the Settings window
- `panel-border` rgba(127,200,183,.28) — 1px on every panel
- `accent` #7fc8b7 (seafoam) — primary buttons, timer disc, eyebrow labels, active sequence rule, links
- `accent-tint` rgba(127,200,183,.14) — pill track, highlighted menu row, streak chip; .12 for segmented-control track; .10 for info badge
- `rule` rgba(127,200,183,.18) — dividers; sequence inactive rule uses .25
- `text` #e6f1ee · `text-2` #a9c3c0 · `text-3` #5a7a86
- `warn` #e2a45f — sitting-badge dot only
- Screen dim behind overlay: rgba(8,22,34,.86) + 24px backdrop blur; end state .78

Type — Manrope (Google Fonts) throughout, Manrope 700 for display
- Eyebrow: 600, letter-spacing .1em, uppercase, accent colour. 18px on overlay, 11px on panels
- Overlay movement name 80px/1 700, letter-spacing −.035em (56px for long /side names); instruction 28px/1.45 400 text-2; helper links 18px 600 accent
- Overlay timer disc numerals 84px 600 letter-spacing −.04em; disc label 16px 700 letter-spacing .12em uppercase
- Panel title 20px/1.15 700 letter-spacing −.015em; body 13px/1.45 400 text-2; disc numerals 17px 700
- Menu rows 13px/1.3 500; header title 14px 700; secondary 12px 400
- Settings rows 13px 500; section labels 11px 600 .1em uppercase accent

Radii: overlay card 36px · panels 20px · toast 16px · menu 12px, rows 7px · Settings window 12px · buttons/pills 999px · select fields 8px
Shadows: overlay card 0 40px 100px rgba(0,0,0,.5) · panels 0 24px 60px rgba(0,0,0,.45) · menu 0 18px 50px rgba(0,0,0,.45) · timer disc 0 30px 60px rgba(0,0,0,.5)

Buttons (one system everywhere)
- Primary: accent fill, ink text, 700. Overlay 20×48px padding 22px; panels 9×18px padding 13px 600
- Secondary: 1.5px border rgba(127,200,183,.35), text-2, 600, same padding
- Overlay Snooze/Done: secondary variant with accent border and accent text
- Link action (Skip everywhere, "I know this one", "Show instruction"): plain text, underline offset 3px, text-3 (Skip) or accent (helpers). Never a button.
- Order left→right: primary · secondary · link. Centered.

## Screens

### 2a · Full-break overlay (1440×900 display, any size — layout is centred)
Screen dim covers all displays; overlay card only on the active one. Card 1000×660, centred (left 220 / top 130 on 1440×900), padding 56 80 44, column flex, centre-aligned text.
- Header row (full width, padding-right 200 to clear the disc): eyebrow "HIP RESET · HIPS AND GLUTES" left, time left in break right in text-2 ("4:12 LEFT").
- Timer disc: 300px circle, accent fill, positioned overlapping the card's top-right corner (left 1070 / top 60 on the screen, i.e. its centre sits on the card's corner). Ring: 6px stroke, track rgba(8,22,34,.15), progress ink, round caps, starts at 12 o'clock, drains clockwise per block. Numerals m:ss. Label under numerals: "NEXT →" — the disc IS the Next button (whole disc clickable). In /side blocks the label reads "THEN RIGHT" for the first half; ring shows only the half's share.
- Body (flex 1, centred, max-width 780): movement name, instruction paragraph (text-wrap pretty), helper link.
- Sequence strip (full card width, 4 equal columns, 16px gap, 28px below): each column has a 3px top rule, then number (24px 800), then name (17px). Current block: accent rule, text colour; done: rule .25, text-3, line-through; upcoming: rule .25, text-3. For a /side block in progress the rule is half accent / half .25 (left half fills for left side). Names: "March in place", "Hip flexor /side", "Wall sit", "Box breathing".
- Action row (centred, 12px gap): Snooze 5 min (accent-outline) · Skip · N today (link). From block ≥50% Snooze is replaced by Done. Skip disabled for the first 3 s of the overlay (render at 40% opacity).

States
1. Full instruction — as above.
2. Collapsed instruction — user tapped "I know this one": body shows only the movement name and "Show instruction" link (text-3); nothing else moves. Persisted per movement.
3. /side block — name at 56px, then a pill toggle: track accent-tint, 6px padding, two segments 16×44px padding 30px 700; active side accent fill / ink text, inactive text-3. Instruction below at 24px. Side switches at the halfway chime.
4. End of break — header "HIP RESET · COMPLETE" / "NEXT BREAK 12:05"; disc gone; body: "Hips reset" 84px, one line "Four movements done. Next break at 12:05." 28px text-2, streak chip (accent-tint pill, 14×26 padding: "4" 32px + "breaks in a row today" 20px 600 accent), primary button "Back to work" 22px. Sequence strip all accent, no line-through, no action row. Dim eases to .78.

Transitions: card scales 0.96→1 and fades in over 240ms ease-out; block change crossfades body 160ms; disc ring animates continuously (1 s linear per tick). Dim fades out 300ms after Back to work.

### 3a · Heads-up panel (T−60 s)
400px wide, top-centre of active display, 12px below the menu bar, non-activating. Padding 18 20 16, gap 14.
- Row: 64px disc (accent, ring ink 2.5px, full at T−60 draining to empty, numerals "1:00" 17px) + text column (gap 5): eyebrow "MOVEMENT BREAK · HIPS AND GLUTES", title "Hip reset in a minute", body "Five minutes, four movements."
- Actions: Start now (primary) · Snooze 5 min (secondary) · Skip · 1 today (link).
- Deferred variant (break waited >30 min for a call): panel widens to 420; an info badge sits between text and actions — accent-tint .10, radius 10, padding 8 12, 7px warn dot, 12.5px text-2: "Sitting for 1 h 35 m · break waited for your call". If no snoozes remain, the Snooze button is omitted (no disabled state).

### 3a · Micro-break panel
Same shell as heads-up (400px). No screen dim.
- Count-in (30 s): disc numerals "−0:21" (minus sign, m:ss), ring drains over 30 s; eyebrow "MICRO-BREAK · SHOULDERS"; title "Shoulder rolls in a moment"; body "One minute, standing. Starts in 21 seconds." (live). Actions: Start now · Snooze 5 min · Skip.
- Countdown (60 s): disc "0:44" drains over 60 s; title "Shoulder rolls"; body = instruction text. Actions: Snooze 5 min (secondary) · Skip (link). Auto-dismisses at 0:00.

### 3a · Away toast
380px, bottom-right, 20px inset, radius 16, padding 14 16 12, auto-dismiss 6 s. Row: 10px accent dot · title 14px 700 "Away 7 min · counted as your break" + 12px text-2 "Next break at 14:02" · secondary button "I was sitting" (13px). Bottom edge: 2px progress hairline (track rule .18, fill accent) shrinking left→right over the 6 s; tapping the button reverses the credit.

### 3b · Menu-bar dropdown
264px, padding 6, radius 12, custom MenuBarExtra view. Header block (padding 10 10 12, bottom rule, margin-bottom 6): 40px disc + title 14px 700 + subtitle 12px. Rows 7×10 padding, radius 7; the recommended action row has accent-tint .14 background. Dividers 1px rule with 6px 4px margin. Stats block two lines 400 weight (text-2, then text-3). Footer rows Settings… ⌘, and Quit Movez ⌘Q with shortcuts in text-3.
- Sitting: disc accent with ring at remaining fraction, "32" inside; "Next break in 32 min" / "Hip reset · hips and glutes"; rows Take a break now (highlighted), Make due in ▸ (5 · 10 · 15 · 30 min), Pause for ▸.
- Paused: disc = 40px dashed circle 2.5px text-3 with "‖"; "Paused · 42 min left" / "Countdown resumes at 15:00 with 23 min left"; rows Resume now (highlighted), Extend pause ▸, Take a break now (text-3).
- Off-hours: disc = 2.5px ring rgba(127,200,183,.25), empty; "Off hours" / "Breaks resume Monday at 9:00"; rows Start a session now (highlighted), Take a break now. Stats show the last working day.
Menu-bar icon: 12px ring, filled arc = fraction elapsed, followed by minutes remaining ("32m"); dashed ring + "‖" when paused; ring only at 55% opacity off-hours.

### 3c · Settings window
760×700 single scrolling window, background #12283a, 52px title bar with centred "Movez settings". Content padding 24 32, sections separated by 1px rule .14 with 22px gaps. Each section is a 160px label column (section label style) + rows (gap 12, label left / control right).
- Schedule: Preset segmented control (track accent-tint .12, 3px padding, segments 6×14 12px 600, active accent/ink): 25/5 · 55/5 · 85/5 · Custom. Toggle "Micro-break every 30 min · 60 s" (toggle 38×22, on = accent track with ink knob, off = .2 track with text-2 knob). Working hours "Mon–Fri · 9:00–18:00" + accent "Edit" link.
- Movements: Equipment chips (selected = accent fill, unselected = secondary outline) Band · Kettlebell · Dumbbell · Roller / ball. Difficulty cap segmented Beginner · Moderate · Advanced. Excluded movements "3 excluded" + "Browse library…" link. Focus select (outlined 8px field, 160 min-width) "More upper back".
- Stay out of the way: three toggles (microphone, screen share/record, fullscreen app + "2 exceptions" link), "Count me away after" select "3 min".
- General: Sounds toggle, Launch at login toggle.
- Footer bar (12 32 padding, top rule): "▸ Debug · time scale, signal injectors, state inspector" disclosure left; version string right, 12px text-3.

## State
Overlay: `block index`, `blockRemaining`, `breakRemaining`, `side (left|right|none)`, `instructionCollapsed[movementId]`, `skipEnabledAt`, `phase (running|complete)`. Panels: `phase (headsUp|microCountIn|microRunning|toast)`, `remaining`, `snoozesLeft`, `skipsToday`, `deferredReason`. Menu: `scheduler state (sitting|paused|offHours)`, `nextBreakAt`, `pauseUntil`, `todayStats`. All timers tick once per second; ring progress interpolates between ticks.

## Assets
No images. Font: Manrope (bundle the variable TTF; weights 400–800 used). Timer ring and menu-bar icon are drawn shapes.

## Files
- `movez-ui-designs.dc.html` + `support.js` — the design canvas (open in a browser). Approved: `#2a`, `#3a`, `#3b`, `#3c`.
- `screenshots/` — PNGs of the approved options.
- `reference/product-brief-v1.md`, `reference/scheduler-research-v1.md` — product and behaviour spec.
