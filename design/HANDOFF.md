# Handoff: Movez strength mode

This package adds a second break mode, **Strength**, to the Movez macOS menu-bar app. It also adds a mode badge and a mode-specific menu-bar icon to every surface: the full-break overlay, the heads-up and micro-break panels, the menu-bar dropdown and Settings. It covers every new Strength screen and state, plus the five existing Movement screens that change (`overlay`, `micro-panel`, `headsup`, `menu`, `settings`). Badges and menu-bar icons are defined for all four modes (Movement, Strength, 100s, PT), but only Movement and Strength have full screens. Everything not described here stays exactly as it is in the current app. **All screenshots are rendered at 2× (Retina).** Overlay screenshots are 2880×1800 for a 1440×900 pt display. Panels are 1200×680 for a 600×340 pt crop with the panel at its real 400 pt width. Dropdowns are 1120×920 for 560×460 pt. Settings are 1520×2080 for the full 760 pt-wide window, drawn unscrolled; the real window is 700 pt tall and scrolls. The light desktop and menu-bar backdrops in the panel and dropdown screenshots are context only, not part of the design.

## Approved screens

| id | name | files |
|---|---|---|
| `strength-set` | Strength break: a working set | `strength-set.png`, `strength-set--warmup.png`, `strength-set--leadin.png`, `strength-set--rest.png`, `strength-set--cooldown.png`, `strength-set--side.png`, `strength-set--hold.png`, `strength-set--paused.png`, `strength-set--reduced-motion.png`, `strength-set--long-dose.png` |
| `endrange-break` | End-range break | `endrange-break.png`, `endrange-break--leadin.png`, `endrange-break--side.png`, `endrange-break--paused.png` |
| `strength-headsup` | Heads-up panel (Strength) | `strength-headsup.png`, `strength-headsup--endrange.png`, `strength-headsup--deferred.png` |
| `strength-micro` | Micro-break panel (Strength) | `strength-micro.png`, `strength-micro--running.png`, `strength-micro--countin.png`, `strength-micro--leadin.png`, `strength-micro--side.png`, `strength-micro--second.png` |
| `menu-strength` | Menu-bar dropdown in Strength mode | `menu-strength.png`, `menu-strength--paused.png`, `menu-strength--offhours.png`, `menu-strength--away.png` |
| `menu-icons` | Menu-bar icon per mode | `menu-icons.png`, `menu-icons--paused.png`, `menu-icons--offhours.png` |
| `mode-badges` | The mode badge, all four modes | `mode-badges.png` |
| `settings-strength` | Settings with Strength selected | `settings-strength.png`, `settings-strength--library.png`, `settings-strength--first-switch.png` |
| `overlay` | Movement break (changed: badge) | `overlay.png` |
| `micro-panel` | Movement micro-break (changed: badge, eyebrow) | `micro-panel.png` |
| `headsup` | Movement heads-up (changed: badge) | `headsup.png` |
| `menu` | Movement dropdown (changed: mode row, icon) | `menu.png` |
| `settings` | Movement Settings (changed: mode control) | `settings.png` |

The brief's `strength-end`, `endrange-break--end`, `strength-set--collapsed` and `strength-set--other-display` were dropped on purpose; see Deviations.

## Design tokens

### Colour (all existing unless marked new)

| name | value | usage |
|---|---|---|
| `ink` | `#08161f` | text on seafoam, timer ring progress, rep-meter chevron |
| `accent` | `#7fc8b7` | seafoam: primary buttons, TimerDisc, eyebrows, badge glyphs, active strip rule, links, rep-meter fill, "Switch sides" counter, panel dose line |
| `text` | `#e6f1ee` | movement name, dose line, rep counter, primary copy |
| `text-2` | `#a9c3c0` | instruction, set kicker ("Set 1 of 3"), dose modifiers, time left, panel body |
| `text-3` | `#5a7a86` | Skip link, inactive strip, inactive SideToggle segment, sub-labels |
| `warn` | `#e2a45f` | deferred-badge dot only |
| `panel` | `rgba(18,42,58,.92)` overlay card · `.94` small panels · `.96` menu and lead-in disc · solid `#12283a` Settings | surfaces |
| `dim` | `rgba(8,22,34,.86)` + 24 px backdrop blur | screen dim behind the overlay, on every display |
| `panel-border` | accent at `.28` | 1 px border on card, panels, menu, sheets; 1.5 px on the lead-in disc |
| `accent-tint` | accent at `.14` (segmented `.12`, info badge `.10`) | SideToggle track, highlighted menu row, rep-meter track, unfilled ladder segment; info badge / weight guidance background |
| `secondary-border` | accent at `.35` | secondary buttons, unselected chips, select fields, search field |
| `rule` | accent at `.18` (inactive strip `.25`, Settings `.14`) | dividers |
| `empty-ring` | accent at `.25` | off-hours / away header disc in the dropdown |
| `ring-track` | ink at `.15` | TimerDisc track on seafoam |
| `leadin-ring-track` | accent at `.15` | TimerDisc track in lead-in and rest (existing lead-in look) |
| `icon-track` (new) | template colour at `.35` | menu-bar icon ring, unelapsed part |
| `icon-paused` (new) | template colour at `.75` | menu-bar icon dashed ring when paused |
| `icon-offhours` (new) | template colour at `.55` | menu-bar icon ring **and** glyph in off hours |
| `icon-away` (new) | template colour at `.60` | menu-bar icon ring while away |

No colour changes between modes. Seafoam is the only accent in every mode, the badge included.

### Type (Manrope, bundled)

| name | value | usage |
|---|---|---|
| `eyebrow-overlay` | 18 px 600, letter-spacing .1em, uppercase, accent | overlay eyebrow, time left (text-2) |
| `eyebrow-panel` | 11 px 600, .1em, uppercase, accent, line-height 14 | panel eyebrow |
| `movement-name` | 80 px 700, −.035em, lh 1 (56 px 700, −.03em, lh 1.05 for long names) | overlay name, "Rest" headline |
| `set-name` (new use of 56 px) | 56 px 700, −.03em, lh 1.05, `text-wrap: balance`, wraps to 2 lines | movement name on rep-based sets |
| `set-kicker` (new) | 20 px 600, lh 1.2, text-2 | "Set 1 of 3", "Warm-up", "Cool-down" |
| `dose` (new) | 28 px 700, −.015em, lh 1.1, text | the rep target / dose line on the overlay |
| `dose-modifier` (new) | 20 px 600, lh 1.2, text-2 | "Alternating · 2 s hold" |
| `rep-counter` (new) | 28 px 700, −.015em, lh 1.1, text (accent for "Switch sides") | under the rep meter |
| `up-next` (new) | 28 px 600, lh 1.3, text | "Up next: …" on rest |
| `instruction` | 28 px / 1.45 400 text-2 (24 px on sets and whenever a SideToggle shows) | overlay instruction |
| `disc-numerals` / `disc-label` | 84 px 600 −.04em / 16 px 700 .12em uppercase | TimerDisc 300 |
| `strip-top` / `strip-name` | 24 px 800 / 17 px 400 | SequenceStrip |
| `panel-title` / `panel-body` | 20 px 700 −.015em lh 1.15 / 13 px lh 1.45 text-2 | panels |
| `panel-dose` (new) | 20 px 700 −.015em lh 1.15, **accent** | dose line in micro panels |
| `side-pill` (new size) | 22 px 700 lh 1.2 | compact SideToggle on the dose line |
| `menu-row` / `menu-title` / `menu-sub` | 13 px 500 / 14 px 700 / 12 px text-2 | dropdown |
| `segment` | 12 px 600 lh 16 | SegmentedControl, mode controls |
| `settings-row` / `section-label` | 13 px 500 / 11 px 600 .1em uppercase accent | Settings |
| `settings-sub` (new) | 12 px 400 text-3 lh 1.4 | sub-label under a Settings row label |
| `menubar` | 13 px 500 (system) | "32m" beside the menu-bar icon |

### Size, space and radius

| name | value | usage |
|---|---|---|
| `overlay-card` | 1000×660, padding 56 80 44, radius 36, left 220 / top 120 on 1440×900 | overlay |
| `disc-overlay` | 300, left 1070 / top 50; ring r 139, 6 px, round caps, from 12 o'clock | TimerDisc |
| `disc-panel` / `disc-menu` | 64 (ring r 27.75, 2.5) / 40 (ring r 17.5, 2.5) | TimerDisc |
| `rep-meter` (new) | 64×264, radius 999; fill min-height 64 | RepMeter |
| `meter-column` (new) | 180 wide, meter + 18 gap + counter | two-column set body |
| `set-text-column` (new) | 604 wide | two-column set body; column gap 56 (180 + 56 + 604 = card content width 840) |
| `ladder-gap` (new) | 4 px between segments, segment radius 6 | stepped RepMeter |
| `menubar-icon` (changed) | 18×18 pt circle r 8, stroke 1.6 pt; glyph 10×10 pt, stroke 1.1 pt | menu-bar icon (was 12 pt) |
| `badge-glyph` (new) | 22 (overlay) · 13 (panel) · 14 (dropdown, Settings) · 16 (weight guidance) | ModeBadge |
| radii | card 36 · panels 20 · menu 12, rows 7 · Settings window and sheets 12 · info badge 10 · select / search 8 · pills 999 | existing |
| shadows | card 0 40 100 rgba(0,0,0,.5) · panels and sheets 0 24 60 rgba(0,0,0,.45) · menu 0 18 50 rgba(0,0,0,.45) · disc 0 30 60 rgba(0,0,0,.5) | existing |

## Components

Existing, used as-is unless noted:

- `TimerDisc`: 300 / 64 / 40 pt disc. Overlay disc is a button. Modes:
  - **run**: accent fill, ink ring;
  - **lead-in**: `panel .96` fill, `panel-border` 1.5 px, accent ring on `leadin-ring-track`, accent numerals with a minus sign;
  - **paused**: run look with label "PAUSED".

  New labels: **DONE** on sets and **REST** on rests. Rest uses the lead-in look (negative time).
- `SequenceStrip`: one column per block, 3 px top rule, top line 24/800, name 17 px. Current: accent rule, text colour. Done: `.25` rule, text-3, name struck through. Upcoming: `.25` rule, text-3. Half-done per-side block: rule half accent, half `.25`. Strength strips have 5 columns: `Warm-up`, `Set 1`, `Set 2`, `Set 3`, `Cool-down`. End-range strips have 4 columns: `1`–`4`. Names stay on one line and truncate with an ellipsis (new rule).
- `SideToggle`: Left/Right pill. Track `accent-tint`, 6 px padding, segments 8×30 padding, 30 px 700, active accent / ink, inactive text-3. **New compact size:** 22 px 700, segments 6×22, track padding 4. It sits at the right end of the dose line on views that show the rep meter (see `strength-set--side`).
- `PrimaryButton` / `SecondaryButton` / accent-outline `SecondaryButton` (Snooze) / `LinkAction` (Skip, Edit, Browse library…). 13 px, 9×18 padding.
- `PanelShell`: 400 pt (420 deferred), padding 18 20 16, gap 14, radius 20.
- `InfoBadge`: accent-tint `.10`, radius 10, padding 8 12, 12.5 px text-2, optional 7 px `warn` dot (deferred badge).
- `Chip`, `SegmentedControl`, `Toggle` (38×22), `SelectField`, menu `Row` (inline expansion, no submenus), `LibrarySheet` (Settings library browser), Settings section (160 pt label column + rows, gap 12).

New:

- `ModeBadge` (new): mode glyph plus mode name. The glyph is drawn in accent and the name in the surrounding eyebrow or control's text style. It's defined in `mode-badges`, and the glyph vectors are under the `mode-badges` screen.
- `RepMeter` (new): vertical pill meter with a rep counter. It has two looks, **smooth** (default) and **stepped** (Reduce Motion), and is not strength-specific (it's reused by 100s).
- `ModeSegmentedControl` (new): a `SegmentedControl` whose segments are glyph + name. In the dropdown, with more than 2 modes, inactive segments collapse to 36 pt glyph-only buttons.
- `WeightGuidance` (new): `InfoBadge` variant with no dot, a 16 pt Strength glyph, a bold lead "Choosing a weight." in `text` 600, and the rest in text-2. Padding 10 12, line-height 1.45.
- `StrengthSetupSheet` (new): first-switch sheet built on the `LibrarySheet` shell (560 pt wide, radius 12, header 15 px 700 with bottom rule, footer with top rule).
- `MenuBarIcon` (changed): an 18 pt circle with the mode glyph inside. It replaces today's 12 pt ring for every mode.

## Screens

### strength-set — Strength break: a working set

**Frame.** Today's overlay: dim on every display, card, disc overlapping the card's top-right corner, strip, action row. The break window appears on **every display**, with no secondary-display label.

- Header row: `ModeBadge` eyebrow `[glyph] STRENGTH BREAK` on the left, time left in the break on the right (text-2, `eyebrow-overlay`). Padding-right 200 to clear the disc.
- Action row: centred, gap 12, margin-top 22. `Pause` (secondary) · `Snooze 5 min` (accent outline) · `Skip · {n} today` (link). Pause becomes `Resume` while paused. Snooze is **never** swapped for a Done button, because the disc is Done. Skip is disabled for the first 3 s (40% opacity), as today.
- Strip: margin-top 28, 5 columns, gap 16.

**Body: rep-based set (default, `--paused`, `--reduced-motion`, `--long-dose`, `--side`).** A centred row with gap 56:

1. Meter column, 180 wide, centred: `RepMeter` 64×264, an 18 gap, then the counter `Rep {n} of {total}` (`rep-counter`).
2. Text column, 604 wide, left-aligned:
   - `set-kicker` `Set {n} of 3`;
   - 8 px, then the movement name (`set-name`, 56 px; it wraps to 2 lines rather than shrinking);
   - 4–6 px, then the **dose line** (`dose`, 28 px) — the rep target;
   - optionally 6 px and the `dose-modifier` line;
   - 22 px (18 px after a modifier line or pill), then the instruction at 24 px.

   The instruction is always shown; there is no collapse toggle.
- TimerDisc: run look, set countdown, label `DONE`. Clicking the disc or pressing **Space** ends the set early and starts the rest. Nothing *requires* a click.

**RepMeter, smooth.**
- Track: `accent-tint`, radius 999. The fill is accent from the bottom, radius 999, with height `64 + 200 × p`.
- Each rep, `p` rises 0→1 over 1.5 s, then falls 1→0 over 1.5 s (ease-in-out sine). The rhythm is even and silent.
- A 28×16 ink chevron sits 16 pt below the fill's top edge (stroke 3.5, round). It points **up** while rising and **down** while falling, so direction never depends on colour.
- The counter increments when a rep starts rising. Rep 1 starts when the set starts. The set clock is 3 s × reps + 5 s, so the reps finish as the clock runs out; when it hits 0 a chime starts the rest.
- **Doses with a hold** ("2 s hold"): the fill rises 1.5 s, holds full for the hold, then falls 1.5 s. While holding, the chevron becomes `=` (two 18 pt bars). The set clock is (3 + hold) s × reps + 5 s. See `--long-dose`.
- **Paused**: the fill freezes and the chevron becomes `‖`. See `--paused`.

**RepMeter, stepped (macOS Reduce Motion), `--reduced-motion`.**
- The track becomes a ladder of N segments, N = reps (per side for per-side sets), gap 4, radius 6, filling from the bottom.
- Completed reps are accent, the current rep has a 2 px accent inset outline, and later reps are `accent-tint`.
- One segment fills per rep, every 3 s (or 3 + hold), with no animation.
- There is no chevron. The counter is unchanged.

**Per-side rep sets (`--side`, e.g. "10 each side").**
- A compact `SideToggle` sits right-aligned on the dose line (`justify-content: space-between`) and shows the current side.
- After N reps on side 1, there is a **3 s switch cue**: the meter empties, an accent ⇄ glyph (28×16, stroke 3) is centred in the track, and the counter reads `Switch sides` in accent. The SideToggle flips to `Right` and the existing side-switch chime plays (if Sounds is on).
- Counting then restarts at `Rep 1 of {N}`.
- Set clock: 3 s × 2N + 5 s + 3 s. The strip rule shows half accent / half `.25` during side 1.
- **Pill placement rule:** on views with the rep meter the pill goes on the dose line, at the right. On views without the meter it is the full-size SideToggle, centred under the dose (see `--cooldown`, `endrange-break--side`).

**Body: no meter (centred).** This applies to `--warmup`, `--leadin`, `--hold`, `--cooldown`, `--rest` and all of `endrange-break`.
- The column is centred, max-width 780, and the text is centred.
- Order: `set-kicker`, then the movement name at 80 px (56 px when the name is longer than 16 characters), then 6 px and the dose line (28 px, if any), then an optional full-size SideToggle (margin-top 18), then the instruction.
- The instruction is 28 px on warm-up and end-range moves, and 24 px on sets and whenever a SideToggle shows. Its margin-top is 22–24 (18 under a SideToggle).
- **Warm-up** (30 s, no rep target, no meter): kicker `Warm-up` with the name and instruction. Disc run, label `NEXT →`.
- **Hold set** (`--hold`, e.g. "30 s hold"): kicker `Set {n} of 3`, name, dose. Disc counts the hold (hold + 5 s), label `DONE`.
- **Cool-down** (30 s, one stretch or hold): kicker `Cool-down`, name, dose, and the full-size SideToggle if per-side. The disc shows the half's share with label `THEN RIGHT` during side 1, then `NEXT →`.
- **Rest** (`--rest`, 45 s): the headline `Rest` (80 px), then 18 px and `Up next: {movement} · {dose}` (`up-next`), then 6 px and `Set {n} of 3` (`set-kicker` in text-3), then the next move's instruction at 24 px. The **disc uses the lead-in look**: negative time (`−0:32`) and label `REST`. Clicking it skips the rest. There is no separate lead-in after a rest; the rest's last 5 s are the lead-in. In the strip, the next set's column is "current".

**Lead-ins (`--leadin`).** These are 5 s, with the disc in the lead-in look counting `−0:05`→`−0:00`, label `GET READY`.
- The lead-in before the warm-up shows the warm-up body.
- The lead-in before set 1 shows set 1's two-column body with the meter empty, an up chevron, and the counter `Rep 1 of {N}`. The meter starts moving at 0:00.

**Flow and timing.**

1. Lead-in, 5 s.
2. Warm-up, 30 s.
3. Lead-in, 5 s.
4. Set 1.
5. Rest, 45 s.
6. Set 2.
7. Rest, 45 s.
8. Set 3.
9. Cool-down, 30 s.

The pattern is X · Y · X, and the day's first break is X · Y · Core. **When the cool-down ends, the overlay closes on its own:** the card fades out over 240 ms and the dim over 300 ms, as today after "Back to work". There is no end screen and nothing to click. Block changes crossfade the body over 160 ms (existing).

**Paused (`--paused`).** The header right reads `PAUSED · ENDS IN {m:ss}` (existing). The disc keeps its numerals with label `PAUSED`, the meter freezes with `‖`, and the action row shows `Resume`.

**Long names and doses (`--long-dose`).** See the dose display rule below. The name wraps to 2 lines at 56 px, and strip names truncate with an ellipsis.

**Dose display rule (all screens).** The dose is shown from the library string:
- `/side` reads ` each side` (`10/side` → `10 each side`, `25 s/side` → `25 s each side`).
- `each direction/side` reads `each direction, each side`.
- Everything after the first comma moves to the `dose-modifier` line. Commas there become ` · ` and the first letter is capitalised: `12 reps, alternating, 2 s hold` → `12 reps` + `Alternating · 2 s hold`.
- Everything else is verbatim (`6 × 5 s`, `8 slow reps`, `30 s hold`). Weights in kg/lb never appear.

### endrange-break — End-range break

This is the day's breaks after the strength breaks: four 60 s active stretches or holds, with no weights.
- Same frame as `strength-set`. The eyebrow is `[glyph] STRENGTH BREAK` (no "end-range" label).
- Centred body: name at 80 px (56 px if longer than 16 characters), then the dose line, then the instruction (28 px; 24 px with a SideToggle).
- Strip of 4 columns numbered `1`–`4`. Disc run, label `NEXT →`. Total 5 s lead-in + 4 × 60 s.
- `--leadin`: lead-in disc `−0:03` / `GET READY` on block 1.
- `--side`: full-size SideToggle centred under the dose. Disc shows the half's share and `THEN RIGHT`. Sides switch at the halfway chime, as in Movement.
- `--paused`: as in `strength-set`.
- No end state: the overlay closes when the last block ends.
- Moves that use the rep meter never appear here. Slow reps ("8 slow reps") show no meter.

### strength-headsup — Heads-up panel (Strength)

Today's heads-up, with the badge.
- 64 pt disc counting `−1:00`, full ring.
- Eyebrow `[glyph] STRENGTH BREAK` (13 pt glyph, 6 pt gap).
- Title `Strength break in a minute`, body `About 5 minutes, three sets. Have your weights nearby.`
- Actions: `Start now` · `Snooze 5 min` · `Skip · {n} today`.
- `--endrange`: same eyebrow; title `End-range break in a minute`, body `Four minutes, four stretches. No weights needed.`
- `--deferred`: panel widens to 420 and the existing deferred `InfoBadge` sits between the text and the actions. The Snooze button is omitted when no snoozes remain.

### strength-micro — Micro-break panel (Strength)

One minute of end-range work. Micro-breaks are **always sitting or standing, never on the floor**.
- Timing: count-in 30 s, then two moves. Each move has a 5 s lead-in, and the 2 × (5 + 25) s make the minute.
- Eyebrow on every state: `[glyph] STRENGTH MICRO-BREAK`, with no body area or side.
- Text column (gap 5): eyebrow, then the movement name (`panel-title`), then the **dose line** (`panel-dose`, 20 px 700 accent), then the instruction (`panel-body`).
- Default / `--running`: run disc counting the move (e.g. `0:14`). Actions: `Snooze 5 min` · `Skip`.
- `--countin` (30 s): run disc with negative time (`−0:21`) draining over 30 s. Title `{movement} in a moment`, body `One minute, {sitting | standing | sitting then standing}. Starts in {n} seconds.` (live). Actions: `Start now` · `Snooze 5 min` · `Skip`.
- `--leadin` (before move 1) and `--second` (before move 2): 64 pt disc in the lead-in look, `−0:03`, with the next move's name, dose and instruction.
- `--side`: run disc showing the half's share. Sides switch at the halfway chime; the instruction ends "Switch at the chime."
- The panel auto-dismisses at the end, as today.

### menu-strength — Menu-bar dropdown in Strength mode

Today's 264 pt dropdown with a mode row added.
- **Header**: 40 pt disc, title `Next break in {n} min`, and the subtitle (new for Strength) naming the next break:
  - `Strength · {A|B} day · break {n} of {N}` for a strength break;
  - `Strength · end-range break` for an end-range break.

  The Movement header has no subtitle (unchanged).
- **Mode row** (new): directly under the header, in a block with padding 2 4 4, followed by a divider. It's a `ModeSegmentedControl`: track accent `.12`, radius 999, padding 3, gap 2; segments 6×8 padding, 14 pt glyph, 12 px 600 name, active accent/ink, inactive text-2.
  - **One click switches mode.** The switch applies from the next break; a break in progress finishes in its mode.
  - The first time Strength is chosen, the dropdown closes and Settings opens with the first-switch sheet; the mode stays Movement until it's confirmed.
  - With 3–4 modes, the active segment keeps glyph + name and the others collapse to 36 pt glyph-only buttons, with the name as accessibility label and tooltip.
- **Rows** are unchanged: `Take a break now` (highlighted), `Make due in` with `5 · 10 · 15 · 30 min`, `Pause for`, the stats block, `Settings…` ⌘, and `Quit Movez` ⌘Q.
- Menu-bar icon: see `menu-icons`.
- `--paused`: dashed 40 pt disc with `‖`; `Paused · {n} min left` / `Countdown resumes at {time} with {n} min left`; rows `Resume now` (highlighted), `Extend pause`, `Take a break now` (text-3).
- `--offhours`: empty ring disc (`empty-ring`); `Off hours` / `Breaks resume {day} at {time}`; rows `Start a session now` (highlighted), `Take a break now`. The stats show the last working day.
- `--away`: `empty-ring` disc with `—`; title `Away · {n} min`. Away time is handled by the user's existing setting, either **resetting** or **pausing** the sitting timer. It never counts as a strength break and is not described as rest.
  - Reset subtitle: `Timer restarts when you’re back. Strength break {n} of {N} is still next.`
  - Pause subtitle: `Countdown paused with {n} min left. Strength break {n} of {N} is still next.`

  Rows as in the default state.

### menu-icons — Menu-bar icon per mode

- A monochrome template image, **18×18 pt** (the full status-item height; today's icon is 12 pt).
- Shape: a circle of r 8 pt with a 1.6 pt stroke and round caps, plus the **mode glyph inside** at 10×10 pt, centred, 1.1 pt stroke.
- Every mode uses the same circle and **differs by glyph only**; macOS tints it. The `32m` label follows at 13 pt with a 5 pt gap.
- Sitting (default): ring at `icon-track` (.35), with the elapsed fraction of the bout drawn at full opacity clockwise from 12 o'clock. The glyph is at full opacity. The label is `{m}m`.
- `--paused`: ring dashed (6 / 5 on a 100-unit path) at `icon-paused` (.75), no progress, glyph at full opacity. Label `‖ {m}m` (minutes left in the pause).
- `--offhours`: solid ring and glyph both at `icon-offhours` (.55). No label.
- Away (dropdown only): solid ring at `icon-away` (.60), glyph full, label `—`.
- Glyph vectors are the `ModeBadge` glyphs, under `mode-badges`.

### mode-badges — The mode badge, all four modes

Glyph + mode name. Glyphs are drawn on a 20×20 grid with a 1.8 stroke (scaled with size), round caps and joins, no fill, in `accent`:

- **Movement**: `path M2 10 C4.5 4 7.5 4 10 10 S15.5 16 18 10`
- **Strength**: `rect x3.5 y5 w3.5 h10 rx1.2` · `rect x13 y5 w3.5 h10 rx1.2` · `line 7,10→13,10` · `line 1.5,10→3.5,10` · `line 16.5,10→18.5,10`
- **100s**: lines at x = 4.5, 8, 11.5, 15 from y 4→16 · `line 2.5,14→17.5,6`
- **PT**: `path M7.5 4 H6.5 A2 2 0 0 0 4.5 6 V15.5 A2 2 0 0 0 6.5 17.5 H13.5 A2 2 0 0 0 15.5 15.5 V6 A2 2 0 0 0 13.5 4 H12.5` · `rect x7.5 y2.5 w5 h3 rx1` · `polyline 7.5,11 9.5,13 13,9`

Sizes:

- Overlay eyebrow: glyph 22, gap 10, 18 px text: `{MODE} BREAK`.
- Panel eyebrow: glyph 13, gap 6, 11 px text: `{MODE} BREAK` on heads-up, `{MODE} MICRO-BREAK` on micro panels.
- Dropdown mode row: glyph 14 + 12 px name.
- Settings mode control: glyph 14 + 12 px name.
- Weight guidance: glyph 16.

Eyebrows never carry a break kind, body area, side or "complete". The mode name `100s` keeps its lowercase "s" when the eyebrow is uppercased (`100s BREAK`).

### settings-strength — Settings with Strength selected

- New first section, **MODE**: row `Break mode` with the sub-label `Switch any day. Your schedule and today’s stats carry over.` (`settings-sub`), and a `ModeSegmentedControl` (glyph + name, all names always shown) on the right.
- **SCHEDULE**: unchanged.
- **STRENGTH** replaces MOVEMENTS when Strength is selected. Rows:
  - `Equipment on hand`: chips `Dumbbells` · `Kettlebell`.
  - `Solid wall nearby`: toggle.
  - `Strength breaks a day`: segmented `1` · `2` · `3` · `4`, with sub-label `Later breaks that day are end-range breaks.`
  - `Difficulty cap`: `Beginner` · `Moderate` · `Advanced`.
  - `Focus`: SelectField, 200 min-width, options `None` · `More legs and glutes` · `More back and shoulders` · `More core` · `More arms`.
  - `Excluded moves`: `{n} excluded` and `Browse library…`.
  - Then `WeightGuidance` spanning the rows column.
  - The Movement-only rows are hidden. There is no floor row; micro-breaks never use the floor.
- **STAY OUT OF THE WAY**, **WHEN I'M AWAY** and **GENERAL**: unchanged and shared by both modes. *When I'm away* is not drawn in the mockups; keep it exactly as it is today, in its current position.
- `--library`: `LibrarySheet` titled `Strength library` over the dimmed window (`dim` at .62).
  - Search field, category chips `All` · `WRM` · `LEG` · `HNG` · `PSH` · `PUL` · `COR` · `END`, and the counts row `{n} excluded` / `{n} shown`.
  - Rows: code (12.5 px text-3, 68 pt column), then name 14 px 600 and meta 12.5 px text-3 (`{Category} · Diff {n}{ · equipment}{ · /side}{ · micro}`), then a Toggle. Off means excluded.
  - Categories: Warm-up, Squat & lunge, Hinge, Push, Pull, Core, End-range. The `Done` primary button closes the sheet.
- `--first-switch`: `StrengthSetupSheet` titled `Set up Strength`, at top 110, over **Movement** Settings. The mode control still shows Movement.
  - Content: an intro paragraph (13 px text-2), then rows `Equipment on hand` (sub-label `Choose at least one.`), `Solid wall nearby`, `Strength breaks a day` (default 3), `Difficulty cap` (default Beginner), then `WeightGuidance`.
  - Footer: the note `Movement stays on until you switch.` (12 px text-3) on the left, and `Switch to Strength` (primary) · `Not now` (secondary) on the right.
  - `Switch to Strength` is disabled (40% opacity) until at least one equipment chip is selected. It saves the choices, sets the mode to Strength and closes the sheet. `Not now` closes it with the mode unchanged.
  - Shown only the first time Strength is chosen, from Settings or from the dropdown.

### overlay — Movement break (changed: badge)

Unchanged except that the eyebrow gains the Movement glyph: `[glyph] MOVEMENT BREAK`.

### micro-panel — Movement micro-break (changed: badge, eyebrow)

The eyebrow becomes `[glyph] MOVEMENT MICRO-BREAK` on every micro-panel state; the body area and side are no longer shown there. Everything else is unchanged.

### headsup — Movement heads-up (changed: badge)

The eyebrow gains the Movement glyph: `[glyph] MOVEMENT BREAK`. Otherwise unchanged.

### menu — Movement dropdown (changed: mode row, icon)

The mode row is added under the header, with Movement active. The menu-bar icon is the new 18 pt circle with the Movement glyph. Otherwise unchanged; there is still no header subtitle.

### settings — Movement Settings (changed: mode control)

The MODE section is added at the top with Movement selected. MOVEMENTS and every other section are unchanged; *When I'm away* is not drawn but stays as is.

## Deviations from the brief

All approved by Kyle during design review.

- The rep target must be "at least as large as the movement name" (80 pt) → the dose line is **28 px**, under a 56 px (sets) or 80 px (no meter) name. Kyle chose this deliberately.
- Movement name 80 px on the overlay → **56 px on rep-based sets**, to fit the two-column meter layout.
- Overlay body is a centred stack → rep-based sets use a **two-column body**: meter on the left, left-aligned text on the right.
- "Decide whether the disc is the Done button" → the **disc is Done** during sets (Space too). Snooze is never swapped for a Done button.
- Instruction collapsible ("I know this one" / "Show instruction") → **always shown**; `strength-set--collapsed` dropped. The toggle was already removed from the app.
- Load hint on the set screen → **no load hint during sets**. Weight guidance appears only in the Strength settings section and the first-switch setup.
- Set timer 3 s a rep + 5 s → **per-side sets add a 3 s switch-sides cue** (3 s × 2N + 5 s + 3 s). Doses with a hold use (3 + hold) s per rep.
- `strength-end` and `endrange-break--end` → **dropped**. The break closes on its own when the cool-down (or last block) ends; there is no "Back to work". Movement has no end screen either.
- `strength-set--other-display` → **dropped**. The break screen already shows on every display.
- Eyebrows such as "STRENGTH · END-RANGE BREAK", "· COMPLETE", "· HIPS", "· RIGHT SIDE" → eyebrows read only `{MODE} BREAK`, or `{MODE} MICRO-BREAK` on micro panels. This also changes the Movement micro panel (`MICRO-BREAK · SHOULDERS` → `MOVEMENT MICRO-BREAK`).
- Rest countdown → uses the **lead-in disc style** (negative time) with the label `REST`.
- Strength micro-breaks "some on the floor" → micro-breaks are **never on the floor**, only sitting or standing. There is no floor row in Strength settings.
- SideToggle placement: on views with the rep meter it is **compact and right-aligned on the dose line**; on views without the meter it stays full-size and centred under the dose.
- Settings "When I'm away" stays shared → it is **intentionally left out of the mockups**. It's unchanged and must be kept as it is today.
- Menu-bar icons "differ by shape only", with "today's Movement icon (unchanged)" → **every mode uses the same circle, 18 pt, with the mode glyph inside**; modes differ by glyph. This changes the Movement icon too (12 pt ring → 18 pt circle with glyph).
- Away → never counts as a strength break and is not called rest. The dropdown copy follows the user's existing reset-or-pause away setting.
- Strength micro panel → shows a **dose line in accent** (20 px) under the movement name.

## Copy

### strength-set
- `STRENGTH BREAK`
- `{m:ss} LEFT` (e.g. `3:58 LEFT`)
- `PAUSED · ENDS IN {m:ss}` (e.g. `4:48`)
- `Set {n} of 3`
- `Warm-up`
- `Cool-down`
- `{movement name}` (e.g. `Goblet squat`, `Loaded rear-foot-elevated split squat`)
- `{dose}` (e.g. `12 reps`, `10 each side`, `30 s hold`, `15 s each side`)
- `{dose modifiers}` (e.g. `Alternating · 2 s hold`)
- `Rep {n} of {total}` (e.g. `Rep 7 of 12`)
- `Switch sides`
- `Left`
- `Right`
- `Rest`
- `Up next: {movement name} · {dose}` (e.g. `Up next: Push-up · 10 reps`)
- `{instruction}` (from the library; e.g. `Hold the weight at your chest. Sit back between your heels, chest up, then stand tall.`)
- `{m:ss}` (e.g. `0:22`)
- `−{m:ss}` (e.g. `−0:04`, `−0:32`)
- `DONE`
- `NEXT →`
- `GET READY`
- `REST`
- `PAUSED`
- `THEN RIGHT`
- `Set 1`
- `Set 2`
- `Set 3`
- `Pause`
- `Resume`
- `Snooze 5 min`
- `Skip · {n} today` (e.g. `1`)

### endrange-break
- `STRENGTH BREAK`
- `{m:ss} LEFT`
- `PAUSED · ENDS IN {m:ss}`
- `{movement name}` (e.g. `Deep squat sit`, `Kneeling hip flexor`, `Wall slides`)
- `{dose}` (e.g. `6 × 5 s`, `25 s each side`, `8 slow reps`)
- `{instruction}`
- `Left`
- `Right`
- `1`
- `2`
- `3`
- `4`
- `{strip name}` (e.g. `Kneeling hip flexor /side`)
- `{m:ss}`
- `−{m:ss}`
- `NEXT →`
- `GET READY`
- `THEN RIGHT`
- `PAUSED`
- `Pause`
- `Resume`
- `Snooze 5 min`
- `Skip · {n} today`

### strength-headsup
- `STRENGTH BREAK`
- `−1:00`
- `Strength break in a minute`
- `About 5 minutes, three sets. Have your weights nearby.`
- `End-range break in a minute`
- `Four minutes, four stretches. No weights needed.`
- `Sitting for {h} h {m} m · break waited for your call` (e.g. `1 h 35 m`)
- `Start now`
- `Snooze 5 min`
- `Skip · {n} today`

### strength-micro
- `STRENGTH MICRO-BREAK`
- `{movement name} in a moment` (e.g. `Seated spinal twist in a moment`)
- `One minute, {posture}. Starts in {n} seconds.` (e.g. `sitting then standing`, `21`), where posture is `sitting`, `standing` or `sitting then standing`
- `{movement name}` (e.g. `Seated spinal twist`, `Standing hip flexor stretch`)
- `{dose}` (e.g. `6 slow reps`, `12 s each side`)
- `{instruction}`
- `{m:ss}` (e.g. `0:14`)
- `−{m:ss}` (e.g. `−0:21`, `−0:03`)
- `Start now`
- `Snooze 5 min`
- `Skip`

### menu-strength
- `{m}m` (e.g. `32m`)
- `‖ {m}m` (e.g. `‖ 42m`)
- `—`
- `{n}` (e.g. `32`)
- `‖`
- `Next break in {n} min`
- `Strength · {A|B} day · break {n} of {N}` (e.g. `Strength · A day · break 2 of 3`)
- `Strength · end-range break`
- `Movement`
- `Strength`
- `Take a break now`
- `Make due in`
- `5 · 10 · 15 · 30 min`
- `Pause for`
- `Today · {n} snoozed · {n} skipped`
- `{weekday} · {n} snoozed · {n} skipped` (e.g. `Friday`)
- `Longest sitting bout {h} h {m} m` (e.g. `1 h 12 m`, `58 m`)
- `Settings…`
- `⌘,`
- `Quit Movez`
- `⌘Q`
- `Paused · {n} min left`
- `Countdown resumes at {time} with {n} min left` (e.g. `15:00`, `23`)
- `Resume now`
- `Extend pause`
- `Off hours`
- `Breaks resume {day} at {time}` (e.g. `Monday`, `9:00`)
- `Start a session now`
- `Away · {n} min` (e.g. `7`)
- `Timer restarts when you’re back. Strength break {n} of {N} is still next.`
- `Countdown paused with {n} min left. Strength break {n} of {N} is still next.`

### menu-icons
- `{m}m` (e.g. `32m`)
- `‖ {m}m` (e.g. `‖ 42m`)
- `—`

### mode-badges
- `MOVEMENT BREAK`
- `STRENGTH BREAK`
- `100s BREAK`
- `PT BREAK`
- `MOVEMENT MICRO-BREAK`
- `STRENGTH MICRO-BREAK`
- `100s MICRO-BREAK`
- `PT MICRO-BREAK`
- `Movement`
- `Strength`
- `100s`
- `PT`

### settings-strength
- `Movez settings`
- `MODE`
- `Break mode`
- `Switch any day. Your schedule and today’s stats carry over.`
- `Movement`
- `Strength`
- `STRENGTH`
- `Equipment on hand`
- `Dumbbells`
- `Kettlebell`
- `Solid wall nearby`
- `Strength breaks a day`
- `1`
- `2`
- `3`
- `4`
- `Later breaks that day are end-range breaks.`
- `Difficulty cap`
- `Beginner`
- `Moderate`
- `Advanced`
- `Focus`
- `None`
- `More legs and glutes`
- `More back and shoulders`
- `More core`
- `More arms`
- `Excluded moves`
- `{n} excluded` (e.g. `2`)
- `Browse library…`
- `Choosing a weight.`
- `Pick a weight you could lift 3–5 more times when the set ends. If the last reps feel easy, step up a size next time; if they feel hard, step down.`
- `Strength library`
- `All`
- `WRM`
- `LEG`
- `HNG`
- `PSH`
- `PUL`
- `COR`
- `END`
- `{n} shown` (e.g. `5`)
- `{code}` (e.g. `LEG-01`)
- `{category} · Diff {n}{ · details}` (e.g. `Squat & lunge · Diff 1 · dumbbell or kettlebell`)
- `Warm-up`
- `Squat & lunge`
- `Hinge`
- `Push`
- `Pull`
- `Core`
- `End-range`
- `Done`
- `Set up Strength`
- `Short strength breaks keep you strong through long desk days. Each takes about 5 minutes: a warm-up, three sets with your own weights, and a cool-down. Any later breaks that day are end-range stretches with no weights.`
- `Choose at least one.`
- `Movement stays on until you switch.`
- `Switch to Strength`
- `Not now`
- All Schedule, Stay out of the way, When I'm away, General and footer strings: unchanged.

### overlay
- `MOVEMENT BREAK` (unchanged text; now preceded by the Movement glyph)

### micro-panel
- `MOVEMENT MICRO-BREAK` (replaces `MICRO-BREAK · {AREA}` and `MICRO-BREAK · {AREA} · {SIDE} SIDE`)

### headsup
- `MOVEMENT BREAK` (unchanged text; now preceded by the Movement glyph)

### menu
- `Movement`
- `Strength`

### settings
- `MODE`
- `Break mode`
- `Switch any day. Your schedule and today’s stats carry over.`
- `Movement`
- `Strength`
