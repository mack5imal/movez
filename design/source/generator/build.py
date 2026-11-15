import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from lib import *
OUT = '/home/claude/canvas/project'
boards = {}
def emit(fname, title, w, h, body):
    with open(os.path.join(OUT, fname), 'w') as f:
        f.write(page(title, w, h, body))

SE = lambda: ov_eyebrow('strength', 'Strength break')
STRIP2 = [('Warm-up','Bodyweight squat'),('Set 1','Goblet squat'),('Set 2','Push-up'),('Set 3','Goblet squat'),('Cool-down','Standing quad stretch')]
def strip2(states): return strip([(t, n, s) for (t, n), s in zip(STRIP2, states)])
GS_INSTR = 'Hold the weight at your chest. Sit back between your heels, chest up, then stand tall.'

# ---- strength-set states ----
# warmup
b = body_center(kicker('Warm-up') + name80('Bodyweight squat') +
    instr('Feet shoulder-width apart. Sit back a little way, then stand. Easy pace, no counting. Just get warm.', 28, 24, 'center'))
emit('strength-set--warmup.dc.html', 'strength-set--warmup', 1440, 900, overlay(SE(), ov_right('4:18 left'), b,
    strip2(['cur','up','up','up','up']), ov_actions(), ov_disc('0:16', 'Next →', 16/30)))
# leadin
emit('strength-set--leadin.dc.html', 'strength-set--leadin', 1440, 900, overlay(SE(), ov_right('4:36 left'), b,
    strip2(['cur','up','up','up','up']), ov_actions(), ov_disc('−0:04', 'Get ready', 4/5, 'lead', 'Get ready')))
# rest
b = body_center(name80('Rest', 0) +
    f'<div style="margin-top: 18px; font-size: 28px; font-weight: 600; line-height: 1.3; color: {TXT}">Up next: Push-up · 10 reps</div>' +
    kicker('Set 2 of 3', T3, 6) +
    instr('Hands on the desk edge, body in one line from head to heels. Lower your chest to the edge, then press away.', 24, 20, 'center'))
emit('strength-set--rest.dc.html', 'strength-set--rest', 1440, 900, overlay(SE(), ov_right('3:03 left'), b,
    strip2(['done','done','cur','up','up']), ov_actions(), ov_disc('−0:32', 'Rest', 32/45, 'lead', 'Rest, skip to the next set')))
# cooldown
b = body_center(kicker('Cool-down') + name56('Standing quad stretch') + dose('15 s each side') +
    side_toggle('Left') +
    instr('Hold the desk with one hand. Bend the other knee and hold that ankle behind you, knees together, hips forward.', 24, 18, 'center'))
emit('strength-set--cooldown.dc.html', 'strength-set--cooldown', 1440, 900, overlay(SE(), ov_right('0:22 left'), b,
    strip2(['done','done','done','done','half']), ov_actions(), ov_disc('0:07', 'Then right', 7/15)))
# side (switch-sides cue)
STRIP_SS = [('Warm-up','Bodyweight squat','done'),('Set 1','Split squat','cur'),('Set 2','Push-up','up'),('Set 3','Split squat','up'),('Cool-down','Standing quad stretch','up')]
b = body_two(meter_col(meter(0, 'swap', 'Rep meter, paused while you switch sides'), 'Switch sides', ACC),
    kicker('Set 1 of 3') + name56('Split squat') + dose_with_pill('10 each side', 'Right') +
    instr('Step one foot back, weights at your sides. Lower the back knee toward the floor, then stand.', 24, 18))
emit('strength-set--side.dc.html', 'strength-set--side', 1440, 900, overlay(SE(), ov_right('3:24 left'), b,
    strip(STRIP_SS), ov_actions(), ov_disc('0:34', 'Done', 34/68, aria='Done, end this set')))
# hold (first break of the day: X · Y · Core)
STRIP_H = [('Warm-up','Bodyweight squat','done'),('Set 1','Goblet squat','done'),('Set 2','Push-up','done'),('Set 3','Desk plank','cur'),('Cool-down','Forward fold','up')]
b = body_center(kicker('Set 3 of 3') + name80('Desk plank') + dose('30 s hold') +
    instr('Forearms on the desk, feet back until your body is one straight line. Breathe steadily and keep your hips level.', 24, 22, 'center'))
emit('strength-set--hold.dc.html', 'strength-set--hold', 1440, 900, overlay(SE(), ov_right('0:48 left'), b,
    strip(STRIP_H), ov_actions(), ov_disc('0:18', 'Done', 18/30, aria='Done, end this set')))
# paused
def set_text(): return kicker('Set 1 of 3') + name56('Goblet squat') + dose('12 reps') + instr(GS_INSTR, 24, 22)
b = body_two(meter_col(meter(56, 'pause', 'Rep meter, paused'), 'Rep 7 of 12'), set_text())
emit('strength-set--paused.dc.html', 'strength-set--paused', 1440, 900, overlay(SE(), ov_right('Paused · ends in 4:48'), b,
    strip2(['done','cur','up','up','up']), ov_actions('Resume'), ov_disc('0:22', 'Paused', 22/41, aria='Paused')))
# reduced motion
b = body_two(meter_col(ladder(12, 6, 'Rep meter, rep 7 of 12'), 'Rep 7 of 12'), set_text())
emit('strength-set--reduced-motion.dc.html', 'strength-set--reduced-motion', 1440, 900, overlay(SE(), ov_right('3:58 left'), b,
    strip2(['done','cur','up','up','up']), ov_actions(), ov_disc('0:22', 'Done', 22/41, aria='Done, end this set')))
# long dose
STRIP_L = [('Warm-up','Bodyweight squat','done'),('Set 1','Goblet squat','done'),('Set 2','Loaded rear-foot-elevated split squat','cur'),('Set 3','Goblet squat','up'),('Cool-down','Standing quad stretch','up')]
b = body_two(meter_col(meter(100, 'hold', 'Rep meter, holding at the top'), 'Rep 5 of 12'),
    kicker('Set 2 of 3') + name56('Loaded rear-foot-elevated split squat') + dose('12 reps') + modifiers('Alternating · 2 s hold') +
    instr('Back foot on the chair seat, weights at your sides. Lower slowly, pause at the bottom, then stand.', 24, 18))
emit('strength-set--long-dose.dc.html', 'strength-set--long-dose', 1440, 900, overlay(SE(), ov_right('2:41 left'), b,
    strip(STRIP_L), ov_actions(), ov_disc('0:42', 'Done', 42/65, aria='Done, end this set')))
# ---- endrange-break ----
ER = ov_eyebrow('strength', 'Strength break')
ERS = [('1','Deep squat sit'),('2','Kneeling hip flexor /side'),('3','Wall slides'),('4','Doorway chest opener /side')]
def er_strip(states): return strip([(t, n, s) for (t, n), s in zip(ERS, states)])
b1 = body_center(name80('Deep squat sit', 0) + dose('6 × 5 s', 10) +
    instr('Hold the desk and sink into a deep squat, heels down. Hold 5 s, rise halfway, then sink again.', 28, 22, 'center'))
emit('endrange-break.dc.html', 'endrange-break', 1440, 900, overlay(ER, ov_right('3:19 left'), b1, er_strip(['cur','up','up','up']),
    ov_actions(), ov_disc('0:41', 'Next →', 41/60)))
emit('endrange-break--leadin.dc.html', 'endrange-break--leadin', 1440, 900, overlay(ER, ov_right('4:03 left'), b1, er_strip(['cur','up','up','up']),
    ov_actions(), ov_disc('−0:03', 'Get ready', 3/5, 'lead', 'Get ready')))
b = body_center(name56('Kneeling hip flexor', 0) + dose('25 s each side') + side_toggle('Left') +
    instr('Kneel on your left knee, right foot in front. Tuck the tailbone and squeeze the back glute until the front of the hip opens.', 24, 18, 'center'))
emit('endrange-break--side.dc.html', 'endrange-break--side', 1440, 900, overlay(ER, ov_right('2:41 left'), b, er_strip(['done','half','up','up']),
    ov_actions(), ov_disc('0:12', 'Then right', 12/25)))
b = body_center(name80('Wall slides', 0) + dose('8 slow reps', 10) +
    instr('Back and arms flat on the wall, elbows bent. Slide your arms up as far as they stay on the wall, then slowly back down.', 28, 22, 'center'))
emit('endrange-break--paused.dc.html', 'endrange-break--paused', 1440, 900, overlay(ER, ov_right('Paused · ends in 4:48'), b, er_strip(['done','done','cur','up']),
    ov_actions('Resume'), ov_disc('0:35', 'Paused', 35/60, aria='Paused')))
# ---- overlay (Movement, changed: badge) ----
b = body_center(name80('March in place', 0) +
    instr('Lift each knee to hip height, swinging the opposite arm. Land softly through the whole foot. Keep a pace you could hold a conversation at.', 28, 24, 'center'))
MS = [('1','March in place','cur'),('2','Single-leg stand','up'),('3','Hip flexor /side','up'),('4','Wall sit','up'),('5','Box breathing','up')]
emit('overlay.dc.html', 'overlay', 1440, 900, overlay(ov_eyebrow('movement','Movement break'), ov_right('4:12 left'), b, strip(MS),
    ov_actions(), ov_disc('0:42', 'Next →', 0.35)))

# ---- panels ----
def hs(mode, eyebrow, title, body, deferred=False, fname='', ttl=''):
    tc = p_eyebrow(mode, eyebrow) + p_title(title) + p_body(body)
    extra = info_badge('Sitting for 1 h 35 m · break waited for your call') if deferred else ''
    acts = [btn('Start now','primary')] + ([] if deferred else [btn('Snooze 5 min')]) + [link('Skip · 1 today')]
    emit(fname, ttl, 600, 340, panel_board(p_disc('−1:00', 1.0), tc, extra, p_actions(acts), w=420 if deferred else 400))
hs('strength','Strength break','Strength break in a minute','About 5 minutes, three sets. Have your weights nearby.', fname='strength-headsup.dc.html', ttl='strength-headsup')
hs('strength','Strength break','End-range break in a minute','Four minutes, four stretches. No weights needed.', fname='strength-headsup--endrange.dc.html', ttl='strength-headsup--endrange')
hs('strength','Strength break','Strength break in a minute','About 5 minutes, three sets. Have your weights nearby.', True, 'strength-headsup--deferred.dc.html', 'strength-headsup--deferred')
hs('movement','Movement break','Movement break in a minute','Five minutes, five movements.', fname='headsup.dc.html', ttl='headsup')

M1 = ('Seated spinal twist', '6 slow reps', 'Sit tall at the front of your chair, feet flat. Turn your chest to one side, one hand on the backrest, then slowly turn to the other side.')
M2 = ('Standing hip flexor stretch', '12 s each side', 'Step one foot back into a short lunge, back knee soft. Tuck the tailbone and squeeze the back glute until the front of the hip opens. Switch at the chime.')
def micro(fname, ttl, disc, eyebrow, title, d, body, acts):
    tc = p_eyebrow('strength', eyebrow) + p_title(title) + (p_dose(d) if d else '') + p_body(body)
    emit(fname, ttl, 600, 340, panel_board(disc, tc, '', p_actions(acts)))
run_acts = [btn('Snooze 5 min'), link('Skip')]
micro('strength-micro.dc.html', 'strength-micro', p_disc('0:14', 14/30), 'Strength micro-break', M1[0], M1[1], M1[2], run_acts)
micro('strength-micro--running.dc.html', 'strength-micro--running', p_disc('0:14', 14/30), 'Strength micro-break', M1[0], M1[1], M1[2], run_acts)
micro('strength-micro--countin.dc.html', 'strength-micro--countin', p_disc('−0:21', 21/30), 'Strength micro-break', 'Seated spinal twist in a moment', '', 'One minute, sitting then standing. Starts in 21 seconds.',
      [btn('Start now','primary'), btn('Snooze 5 min'), link('Skip')])
micro('strength-micro--leadin.dc.html', 'strength-micro--leadin', p_disc('−0:03', 3/5, 'lead'), 'Strength micro-break', M1[0], M1[1], M1[2], run_acts)
micro('strength-micro--side.dc.html', 'strength-micro--side', p_disc('0:08', 8/12), 'Strength micro-break', M2[0], M2[1], M2[2], run_acts)
micro('strength-micro--second.dc.html', 'strength-micro--second', p_disc('−0:03', 3/5, 'lead'), 'Strength micro-break', M2[0], M2[1], M2[2], run_acts)
# micro-panel (Movement, changed)
tc = p_eyebrow('movement', 'Movement micro-break') + p_title('Arm circles') + p_body("Arms straight out to the sides, make small circles forward and gradually enlarge them until they're as big as your shoulders allow. Reverse direction and repeat. Keep the ribs down and the neck relaxed.")
emit('micro-panel.dc.html', 'micro-panel', 600, 340, panel_board(p_disc('0:14', 14/60), tc, '', p_actions(run_acts)))

# ---- menus ----
def std_rows(): return [m_row('Take a break now', hl=True), m_row('Make due in', '5 · 10 · 15 · 30 min', chevron=True), m_row('Pause for', chevron=True)]
emit('menu-strength.dc.html', 'menu-strength', 560, 460, menu_board('strength','sitting', m_disc('run'), 'Next break in 32 min', 'Strength · A day · break 2 of 3', std_rows()))
emit('menu-strength--paused.dc.html', 'menu-strength--paused', 560, 460, menu_board('strength','paused', m_disc('paused'), 'Paused · 42 min left', 'Countdown resumes at 15:00 with 23 min left',
    [m_row('Resume now', hl=True), m_row('Extend pause', chevron=True), m_row('Take a break now', color=T3)]))
emit('menu-strength--offhours.dc.html', 'menu-strength--offhours', 560, 460, menu_board('strength','offhours', m_disc('off'), 'Off hours', 'Breaks resume Monday at 9:00',
    [m_row('Start a session now', hl=True), m_row('Take a break now')], ('Friday · 0 snoozed · 1 skipped', 'Longest sitting bout 58 m')))
emit('menu-strength--away.dc.html', 'menu-strength--away', 560, 460, menu_board('strength','away', m_disc('away'), 'Away · 7 min', 'Timer restarts when you’re back. Strength break 2 of 3 is still next.', std_rows()))
emit('menu.dc.html', 'menu', 560, 460, menu_board('movement','sitting', m_disc('run'), 'Next break in 32 min', '', std_rows()))

# ---- mode badges ----
MODES = ['movement','strength','hundreds','pt']
def code(t): return f'<code style="display: block; font-family: ui-monospace, Menlo, monospace; font-size: 10.5px; line-height: 1.5; color: {T3}; white-space: pre-wrap; word-break: break-all">{t}</code>'
SPEC = {
 'movement': 'path M2 10 C4.5 4 7.5 4 10 10 S15.5 16 18 10',
 'strength': 'rect 3.5,5 3.5×10 r1.2 · rect 13,5 3.5×10 r1.2\nline 7,10→13,10 · line 1.5,10→3.5,10 · line 16.5,10→18.5,10',
 'hundreds': 'lines x=4.5, 8, 11.5, 15 from y4→16\nline 2.5,14→17.5,6',
 'pt': 'path M7.5 4 H6.5 A2 2 0 0 0 4.5 6 V15.5 A2 2 0 0 0 6.5 17.5\nH13.5 A2 2 0 0 0 15.5 15.5 V6 A2 2 0 0 0 13.5 4 H12.5\nrect 7.5,2.5 5×3 r1 · polyline 7.5,11 9.5,13 13,9',
}
gridbg = 'background-image: linear-gradient(rgba(127,200,183,.10) 1px, transparent 1px), linear-gradient(90deg, rgba(127,200,183,.10) 1px, transparent 1px); background-size: 5px 5px'
rows = []
for m in MODES:
    nm = MODE_NAME[m]
    rows.append(f'''<div style="display: grid; grid-template-columns: 300px 220px 220px 200px minmax(0, 1fr); gap: 24px; align-items: center; padding: 18px 0; border-top: 1px solid rgba(127,200,183,.14)">
    <div style="display: flex; gap: 14px; align-items: center"><div style="width: 100px; height: 100px; flex-shrink: 0; border-radius: 8px; {gridbg}; display: flex; align-items: center; justify-content: center">{glyph(m,100,ACC,1.8)}</div>{code(SPEC[m])}</div>
    <div>{ov_eyebrow(m, nm + ' break')}</div>
    <div>{p_eyebrow(m, nm + ' micro-break')}</div>
    <div style="width: 200px">{mode_seg_menu(m, ('movement', m) if m != 'movement' else ('movement','strength'))}</div>
    <div>{seg([nm], nm, [m])}</div>
  </div>''')
hdr = ''.join(f'<div style="font-size: 11px; font-weight: 600; letter-spacing: .1em; text-transform: uppercase; color: {T3}">{h}</div>' for h in
              ['Glyph · 20 × 20 grid, 1.8 stroke', 'Overlay eyebrow · 22 / 18 px', 'Panel eyebrow · 13 / 11 px', 'Dropdown mode row · 14 / 12 px', 'Settings mode control · 14 / 12 px'])
four = f'''<div style="margin-top: 22px; padding-top: 22px; border-top: 1px solid rgba(127,200,183,.14); display: grid; grid-template-columns: 300px 1fr; gap: 40px; align-items: start">
    <div><div style="font-size: 11px; font-weight: 600; letter-spacing: .1em; text-transform: uppercase; color: {T3}">With 3 or 4 modes</div>
    <div style="margin-top: 8px; font-size: 12.5px; line-height: 1.5; color: {T2}">Dropdown (252 pt inside): the active segment shows glyph + name; the others shrink to 36 pt glyph-only buttons with the name as their accessibility label and tooltip. Settings always shows every name.</div></div>
    <div style="display: flex; flex-direction: column; gap: 14px">
      <div style="width: 252px">{mode_seg_menu('strength', MODES)}</div>
      <div>{seg([MODE_NAME[m] for m in MODES], 'Strength', MODES)}</div>
    </div>
  </div>'''
mb = f'''<div style="width: 1280px; height: 1000px; box-sizing: border-box; padding: 48px 56px; background: #0f1d28; {FONT}; color: {TXT}">
  <div style="font-size: 20px; font-weight: 700; letter-spacing: -.015em">Mode badge · glyph + mode name</div>
  <div style="margin-top: 6px; font-size: 13px; color: {T2}">Always accent glyph with the existing text colour of its context. No colour changes between modes. 100s and PT are badge-only for now.</div>
  <div style="margin-top: 28px; display: grid; grid-template-columns: 300px 220px 220px 200px minmax(0, 1fr); gap: 24px; padding-bottom: 10px">{hdr}</div>
  {''.join(rows)}
  {four}
</div>'''
emit('mode-badges.dc.html', 'mode-badges', 1280, 1000, mb)

# ---- settings ----
def mode_section(active):
    return section('Mode', [srow('Break mode', seg(['Movement','Strength'], active, ['movement','strength']), 'Switch any day. Your schedule and today’s stats carry over.')], first=True)
def schedule():
    return section('Schedule', [srow('Preset', seg(['25 / 5','55 / 5','85 / 5','Custom'], '55 / 5')),
        srow(f'Micro-break every 30 min <span style="color: {T3}; font-weight: 400">&nbsp;· 1 min</span>', toggle(True)),
        srow('Working hours', f'<span style="font-size: 13px; color: {T2}">Mon–Fri · 9:00–18:00</span>' + link('Edit', ACC, 13, 500))])
def strength_section():
    return section('Strength', [
        srow('Equipment on hand', chips([('Dumbbells', True), ('Kettlebell', False)])),
        srow('Solid wall nearby', toggle(True)),
        srow('Strength breaks a day', seg(['1','2','3','4'], '3'), 'Later breaks that day are end-range breaks.'),
        srow('Difficulty cap', seg(['Beginner','Moderate','Advanced'], 'Moderate')),
        srow('Focus', select('None', 200)),
        srow('Excluded moves', f'<span style="font-size: 13px; color: {T2}">2 excluded</span>' + link('Browse library…', ACC, 13, 500)),
        weight_guidance()])
def movement_section():
    return section('Movements', [
        srow('Equipment on hand', chips([('Band', True), ('Kettlebell or dumbbell', True), ('Roller', False), ('Ball', False)])),
        srow('A wall I can lean on', toggle(True)),
        srow('Floor space I’m willing to use', toggle(True)),
        srow('Stairs nearby', toggle(True)),
        srow('Difficulty cap', seg(['Beginner','Moderate','Advanced'], 'Moderate')),
        srow('Excluded movements', f'<span style="font-size: 13px; color: {T2}">3 excluded</span>' + link('Browse library…', ACC, 13, 500)),
        srow('Focus', select('More upper back'))])
def rest_sections():
    return (section('Stay out of the way', [srow('Wait while the microphone is in use', toggle(True)),
            srow('Wait while the screen is shared or recorded', toggle(True)),
            srow(f'Wait while a fullscreen app is in front&nbsp;&nbsp;{link("2 exceptions", ACC, 13, 500)}', toggle(True)),
            srow('Count me away after', select('3 min', 90))]) +
            section('General', [srow('Sounds', toggle(True)), srow('Launch at login', toggle(True))]))
S_STR = mode_section('Strength') + schedule() + strength_section() + rest_sections()
S_MOV = mode_section('Movement') + schedule() + movement_section() + rest_sections()
emit('settings-strength.dc.html', 'settings-strength', 760, 1040, settings_window(S_STR) + '</div>')
emit('settings.dc.html', 'settings', 760, 1040, settings_window(S_MOV) + '</div>')

def modal(title, inner, footer, top=90, w=560):
    return f'''<div style="position: absolute; inset: 0; background: rgba(8,22,34,.62)"></div>
  <div role="dialog" aria-label="{title}" style="position: absolute; left: {(760-w)//2}px; top: {top}px; width: {w}px; background: #10233a; border: 1px solid {BORDER}; border-radius: 12px; box-shadow: 0 24px 60px rgba(0,0,0,.45); display: flex; flex-direction: column; overflow: hidden">
    <div style="padding: 18px 20px; border-bottom: 1px solid rgba(127,200,183,.14); font-size: 15px; font-weight: 700">{title}</div>
    {inner}
    <div style="padding: 14px 20px; border-top: 1px solid rgba(127,200,183,.14); display: flex; align-items: center; gap: 10px">{footer}</div>
  </div>'''
# library
def lib_row(code_, name, meta, on):
    return (f'<div style="display: grid; grid-template-columns: 68px minmax(0, 1fr) auto; gap: 12px; align-items: center; padding: 12px 0; border-bottom: 1px solid rgba(127,200,183,.14)">'
            f'<span style="font-size: 12.5px; color: {T3}">{code_}</span><div><div style="font-size: 14px; font-weight: 600; color: {TXT}">{name}</div><div style="margin-top: 3px; font-size: 12.5px; color: {T3}">{meta}</div></div>{toggle(on)}</div>')
lib_inner = f'''<div style="padding: 16px 20px 0">
      <div style="display: flex; align-items: center; gap: 8px; padding: 8px 12px; border: 1.5px solid rgba(127,200,183,.35); border-radius: 8px; font-size: 14px; color: {TXT}"><svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="{T2}" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><circle cx="6" cy="6" r="4.5"></circle><line x1="9.5" y1="9.5" x2="13" y2="13"></line></svg><span>squat</span></div>
      <div style="margin-top: 12px; display: flex; gap: 6px; flex-wrap: wrap">{''.join(chip(c, c=='All') for c in ['All','WRM','LEG','HNG','PSH','PUL','COR','END'])}</div>
      <div style="margin-top: 12px; display: flex; justify-content: space-between; font-size: 13px"><span style="font-weight: 500">2 excluded</span><span style="color: {T3}">5 shown</span></div>
    </div>
    <div style="padding: 4px 20px 0; height: 320px; overflow: hidden">
      {lib_row('WRM-02','Bodyweight squat','Warm-up · Diff 1', True)}
      {lib_row('LEG-01','Goblet squat','Squat &amp; lunge · Diff 1 · dumbbell or kettlebell', True)}
      {lib_row('LEG-04','Split squat','Squat &amp; lunge · Diff 2 · dumbbells · /side', True)}
      {lib_row('LEG-09','Loaded rear-foot-elevated split squat','Squat &amp; lunge · Diff 3 · dumbbells · chair', False)}
      {lib_row('END-04','Deep squat sit','End-range · Diff 1 · micro', True)}
    </div>'''
emit('settings-strength--library.dc.html', 'settings-strength--library', 760, 1040,
     settings_window(S_STR) + modal('Strength library', lib_inner, '<span style="flex: 1"></span>' + btn('Done','primary')) + '</div>')
# first switch
fs_inner = f'''<div style="padding: 18px 20px; display: flex; flex-direction: column; gap: 14px">
      <div style="font-size: 13px; line-height: 1.5; color: {T2}">Short strength breaks keep you strong through long desk days. Each takes about 5 minutes: a warm-up, three sets with your own weights, and a cool-down. Any later breaks that day are end-range stretches with no weights.</div>
      {srow('Equipment on hand', chips([('Dumbbells', True), ('Kettlebell', False)]), 'Choose at least one.')}
      {srow('Solid wall nearby', toggle(True))}
      {srow('Strength breaks a day', seg(['1','2','3','4'], '3'))}
      {srow('Difficulty cap', seg(['Beginner','Moderate','Advanced'], 'Beginner'))}
      {weight_guidance()}
    </div>'''
fs_footer = f'<span style="flex: 1; font-size: 12px; color: {T3}">Movement stays on until you switch.</span>' + btn('Switch to Strength','primary') + btn('Not now')
emit('settings-strength--first-switch.dc.html', 'settings-strength--first-switch', 760, 1040,
     settings_window(S_MOV) + modal('Set up Strength', fs_inner, fs_footer, top=110) + '</div>')

# ---- menu icons (v3: circle with the mode glyph inside) ----
def real_bar(bg, fg, icons_html):
    return (f'<div style="display: flex; align-items: center; justify-content: flex-end; gap: 18px; height: 24px; padding: 0 14px; background: {bg}; color: {fg}; font-size: 13px; font-weight: 500; letter-spacing: -.005em">'
            f'{icons_html}<span style="opacity: .9">Sun 15 Nov&nbsp;&nbsp;9:41</span></div>')
def icon_sheet3(state, fname, heading, desc):
    lab = mb_label(state)
    def item(m, fg):
        l = f'<span>{lab}</span>' if lab else ''
        return f'<span style="display: inline-flex; align-items: center; gap: 5px">{mb_icon_v3s(m, state, fg)}{l}</span>'
    cols = ''.join(f"""<div style="display: flex; flex-direction: column; gap: 12px">
      <div style="display: flex; align-items: center; gap: 8px; color: {ACC}; font-size: 13px; font-weight: 600; letter-spacing: .1em; text-transform: uppercase">{glyph(m,16)}<span>{MODE_NAME[m]}</span></div>
      <div style="height: 220px; border-radius: 12px; background: rgba(127,200,183,.06); border: 1px solid rgba(127,200,183,.14); display: flex; align-items: center; justify-content: center">{mb_icon_v3s(m, state, TXT, 180)}</div>
    </div>""" for m in MODES)
    cap = lambda t: f'<div style="margin-top: 22px; margin-bottom: 8px; font-size: 12px; color: {T3}">{t}</div>'
    body = (f'<div style="width: 1280px; height: 760px; box-sizing: border-box; padding: 48px 56px; background: #0f1d28; {FONT}; color: {TXT}">'
      f'<div style="font-size: 20px; font-weight: 700; letter-spacing: -.015em">{heading}</div>'
      f'<div style="margin-top: 6px; font-size: 13px; color: {T2}">{desc}</div>'
      f'<div style="margin-top: 24px; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 32px">{cols}</div>'
      f'<div style="margin-top: 28px; font-size: 13px; font-weight: 600; color: {TXT}">Actual size · view the canvas at 100% (1 px = 1 pt)</div>'
      + cap('All four side by side, for comparison only. The app shows one icon at a time.') +
      f'<div style="border-radius: 8px; overflow: hidden; display: flex; flex-direction: column; gap: 1px">{real_bar("#efece6", "#1d1d1f", "".join(item(m, "#1d1d1f") for m in MODES))}{real_bar("#1e1e20", "#f2f2f2", "".join(item(m, "#f2f2f2") for m in MODES))}</div>'
      + cap('As it will appear · Strength mode, light and dark menu bar') +
      f'<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px"><div style="border-radius: 8px; overflow: hidden">{real_bar("#efece6", "#1d1d1f", item("strength", "#1d1d1f"))}</div><div style="border-radius: 8px; overflow: hidden">{real_bar("#1e1e20", "#f2f2f2", item("strength", "#f2f2f2"))}</div></div>'
      '</div>')
    emit(fname, fname[:-8], 1280, 760, body)
BASE = 'Template image, 18 × 18 pt circle (r 8, 1.6 pt stroke), the full status-item height. Glyph 10 × 10 pt centred, stroke 1.1 pt. Modes differ by the glyph only; macOS tints the image.'
icon_sheet3('sitting', 'menu-icons.dc.html', 'Sitting · 42% of the bout elapsed · 32 min left',
    BASE + ' The ring is the progress track at 35% opacity; the elapsed part is drawn at full opacity, clockwise from 12 o’clock.')
icon_sheet3('paused', 'menu-icons--paused.dc.html', 'Paused · dashed ring, ‖ and the minutes left in the pause',
    BASE + ' Paused: the ring is dashed (6 / 5 on a 100-unit path) at 75% opacity, no progress arc; the glyph stays at full opacity.')
icon_sheet3('offhours', 'menu-icons--offhours.dc.html', 'Off hours · ring and glyph at 55% opacity, no label',
    BASE + ' Off hours: a solid ring and the glyph, both at 55% opacity, and no minutes label.')

# ---- canvas.json ----
rows_layout = [
 (0, 1440, 900, 'Strength break · strength-set', ['Main.dc.html','strength-set--warmup.dc.html','strength-set--leadin.dc.html','strength-set--rest.dc.html','strength-set--cooldown.dc.html']),
 (1, 1440, 900, 'strength-set · more states', ['strength-set--side.dc.html','strength-set--hold.dc.html','strength-set--paused.dc.html','strength-set--reduced-motion.dc.html','strength-set--long-dose.dc.html']),
 (2, 1440, 900, 'End-range break · and the changed Movement overlay', ['endrange-break.dc.html','endrange-break--leadin.dc.html','endrange-break--side.dc.html','endrange-break--paused.dc.html','overlay.dc.html']),
 (3, 600, 340, 'Heads-up and micro-break panels', ['strength-headsup.dc.html','strength-headsup--endrange.dc.html','strength-headsup--deferred.dc.html','headsup.dc.html','strength-micro.dc.html','strength-micro--running.dc.html','strength-micro--countin.dc.html','strength-micro--leadin.dc.html','strength-micro--side.dc.html','strength-micro--second.dc.html','micro-panel.dc.html']),
 (4, 560, 460, 'Menu-bar dropdown', ['menu-strength.dc.html','menu-strength--paused.dc.html','menu-strength--offhours.dc.html','menu-strength--away.dc.html','menu.dc.html']),
 (5, 1280, 860, 'Menu-bar icons and mode badges', ['menu-icons.dc.html','menu-icons--paused.dc.html','menu-icons--offhours.dc.html','mode-badges.dc.html']),
 (6, 760, 1040, 'Settings', ['settings-strength.dc.html','settings-strength--library.dc.html','settings-strength--first-switch.dc.html','settings.dc.html']),
]
canvas = json.load(open('/home/claude/canvas/project/canvas.json'))
heights = {'mode-badges.dc.html':1000, 'menu-icons.dc.html':760, 'menu-icons--paused.dc.html':760, 'menu-icons--offhours.dc.html':760}
y = 0; order = []; notes = {}; boards = {}
for idx, w, h, title, files in rows_layout:
    x = 0; rowh = 0
    for f in files:
        hh = heights.get(f, h)
        t = 'strength-set' if f == 'Main.dc.html' else f[:-8]
        ww = w
        boards[f] = {'x': x, 'y': y, 'w': ww, 'h': hh, 'title': t}
        order.append(f); x += w + 80; rowh = max(rowh, hh)
    notes[f'row{idx}'] = {'x': 0, 'y': y - 260, 'text': title, 'kind': 'title1', 'maxW': x - 80, 'w': 240}
    if idx == 1:
        notes['dose-rule'] = {'x': x, 'y': y, 'text': 'Dose display rule (long-dose): library dose shown verbatim except "/side" reads "each side" and "/direction/side" reads "each direction, each side" (e.g. "2 each direction/side" → "2 each direction, each side"). Text after the first comma moves to a 20 px modifier line: "12 reps, alternating, 2 s hold" → "12 reps" + "Alternating · 2 s hold". Strip names stay one line with an ellipsis.', 'w': 420, 'color': 'teal'}
    y += rowh + 120 + 300
canvas['boards'] = boards; canvas['order'] = order; canvas['notes'] = notes
canvas['noteOrder'] = [f'row{i}' for i in range(7)] + ['dose-rule']
canvas.setdefault('attachments', {})
json.dump(canvas, open('/home/claude/canvas/project/canvas.json', 'w'))
print(len(order), 'boards')
