# Selection-rule changes, October 2026

Agreed on 2026-10-09 after reviewing several weeks of real history. The selection rules had grown
to about eighteen for a full break and nine for a micro-break, and they interacted in ways nobody
intended: strength was 26% of the library but 4% of full-break movements, eye and breathing
movements were 7% of the library but about 20% of what was served, "four blocks by default" came
out as five 75% of the time, and "Hip reset" won the naming about twice as often as a fair share.
These changes replace them with a much smaller set.

**Status: implemented** on the `feat/simpler-break-rules` branch, and recorded in `DECISIONS.md` as
entries 28–34 (shape and rotation 28, timing and lead-ins 29, micro-breaks 30, micro-break chimes 31,
no repeats 32, no names 33, focus 34).

## Agreed changes

**Full breaks**

- **C1. No time-of-day breaks.** No day-open, wind-down or post-lunch shape; every break has the
  same one. (Day-open and post-lunch were already gone, 23f and 23g; only the wind-down remained.)
- **C2. Five movements, always.** Circulation first, then balance, flexibility and strength in
  random order, then a closer. The closer is one draw over every eye, breathing and hands movement
  together, not a category draw first.
- **C3. Every movement is 60 s**, 30 s a side for a per-side movement. Length is never a selection
  rule, so the length repair and trimming steps go.
- **C5. "Not the same body part twice in a row" applies to the strength movement only.**
- **C7. No routine names.** The heads-up title, overlay eyebrow, menu subtitle, completion title and
  history record name get plain wording instead.
- **C8. A 5 s lead-in before every movement**, including the first, shown with a minus sign and in
  a different colour from the countdown. A full break becomes 5:25.
  - Also before the second movement of a two-movement micro-break, which becomes 65 s.
  - No lead-in at a per-side switch; the halfway chime covers it.
  - Next during a lead-in goes to the next movement, as it does now.
- **C9. No target-area rotation**, and no ×3 weight for it. Which areas get worked follows the
  library's own mix, steered only by the user's region focus.

**Micro-breaks**

- **C4. One draw over every micro-eligible movement**, with no category draw and no emphasis
  rotation. If the first movement drawn is per-side it fills the minute alone, 30 s each side;
  otherwise a second, one-sided movement is drawn and each gets 30 s.
- **C13. A micro-break that runs to the end plays the completion chime**, the one a full break
  ends with. Not on a skip or a snooze.
- **C14. The transition chime plays inside a micro-break** at the switch to the second movement
  and at the side switch of a per-side movement, as in full breaks.

**Both**

- **C6. "More balance" focus is removed.** Focus is about body regions, not movement type.
- **C10. No movement is exempt from the no-repeat rule.** Walk lap (CIR-01), Distance gaze (EYE-01)
  and Diaphragmatic breathing (BRE-01) lose their exemption.
- **C11. One no-repeat rule for both kinds of break:** no movement twice in a day, whichever break
  it is in. Micro-breaks still avoid the next full break's movements.
- **C12. "More hands and eyes" focus stays**, redefined by region (wrist/forearm and eyes).

## Bug found along the way

- **B1. The micro-break panel only ever shows its first movement.** `PanelViewModel` reads the
  name, instructions and posture from `micro.blocks.first` and runs it for the whole minute, yet
  both movements are written to history as done. The unseen one then counts as used today and is
  weighed down for three days. Present since the panels were built (`fa6c5a0`).

## Settled during planning

- The lead-in disc is hollow: dark, with a teal outline and teal numerals, filling teal when the
  movement starts.
- The transition chime plays as a movement appears, at the start of its lead-in, not when it starts.
- Names are replaced by "Movement break in a minute" (heads-up), "MOVEMENT BREAK" (eyebrow), "Break
  done" (completion screen) and "Movement break" (history). The menu drops its subtitle line.
- On a micro-break, a per-side movement says which side in the eyebrow:
  "MICRO-BREAK · HANDS · RIGHT SIDE".

## What the simulation showed

`scripts/simulate_selection.py` models both rule sets in Python against
`movement-library-v4.json`, with the user's settings (no equipment, difficulty cap 3, nothing
excluded, no focus), 400 runs per scenario, treating every break as completed. The current-rules
model matches the real history closely (strength 5% of full-break movements against 4% observed;
five-movement breaks 82% against 75%).

Two scenarios: the user's actual last 14 days, day by day (15 full breaks and 17 micro-breaks over
7 active days, including one day of 7 and 5), and three times that volume (about 45 and 51 over 10
working days).

| | Current rate, now | Current rate, proposed | 3×, now | 3×, proposed |
|---|---|---|---|---|
| Distinct movements shown on screen | 69 | 81 | 109 | 118 |
| Most-served movement (times in 2 weeks) | 2.6, all eye/breath | 1.3, mixed | 7.6, all eye/breath | 3.6, mixed |
| Served again within 3 days | 13% | 11% | 35% | 32% |
| Strength share of full-break movements | 7% | 20% | 8% | 20% |

Appearances per available movement in two weeks, by category:

| | CIR | FLX | STR | BAL | HWF | EYE | BRE |
|---|---|---|---|---|---|---|---|
| Current rate, now | 1.1 | 0.9 | 0.35 | 0.5 | 1.0 | 1.9 | 1.9 |
| Current rate, proposed | 1.1 | 0.6 | 0.7 | 0.7 | 1.1 | 1.2 | 1.1 |
| 3×, now | 3.3 | 2.8 | 1.2 | 1.5 | 2.8 | 5.4 | 5.9 |
| 3×, proposed | 3.2 | 1.9 | 2.1 | 2.1 | 3.3 | 3.6 | 3.2 |

- The spread between the most and least repeated category drops from over 5× to about 2×.
- No pool runs short. The fewest options any draw had, on the busiest real day, were 7
  circulation movements, 9 closers, 5 strength movements after the region rule, and 35 for a
  micro-break. What matters is breaks per day, not total volume.
- About a third of micro-breaks are a single per-side movement; the rest have two.

**Accepted trade-offs**

- Flexibility becomes the least repeated per movement: 36 stretches share one slot instead of
  about 1.5.
- Circulation becomes the most repeated: it is in every break and only 19 movements fill it.
- Movements touching the upper back fall from about 25% of full-break movements to 18%. Keeping
  the rotation would recover only about 2 points (`--keep-rotation`); the drop comes from having
  one stretch per break. The "More upper back" focus is there for anyone who wants more.
