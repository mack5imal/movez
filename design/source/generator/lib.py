# Shared builders for Movez strength-mode artboards (static .dc.html)
ACC="#7fc8b7"; INK="#08161f"; TXT="#e6f1ee"; T2="#a9c3c0"; T3="#5a7a86"; WARN="#e2a45f"
PANEL="rgba(18,42,58,.92)"; BORDER="rgba(127,200,183,.28)"
FONT="font-family: Manrope, system-ui, sans-serif"

def page(title, w, h, body):
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0}}
a{{color:#7fc8b7}}a:hover{{color:#a6dccf}}
</style>
</helmet>
{body}
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{w},"height":{h}}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
'''

GLYPHS = {
 'movement': '<path d="M2 10C4.5 4 7.5 4 10 10S15.5 16 18 10"></path>',
 'strength': '<rect x="3.5" y="5" width="3.5" height="10" rx="1.2"></rect><rect x="13" y="5" width="3.5" height="10" rx="1.2"></rect><line x1="7" y1="10" x2="13" y2="10"></line><line x1="1.5" y1="10" x2="3.5" y2="10"></line><line x1="16.5" y1="10" x2="18.5" y2="10"></line>',
 'hundreds': '<line x1="4.5" y1="4" x2="4.5" y2="16"></line><line x1="8" y1="4" x2="8" y2="16"></line><line x1="11.5" y1="4" x2="11.5" y2="16"></line><line x1="15" y1="4" x2="15" y2="16"></line><line x1="2.5" y1="14" x2="17.5" y2="6"></line>',
 'pt': '<path d="M7.5 4H6.5A2 2 0 0 0 4.5 6V15.5A2 2 0 0 0 6.5 17.5H13.5A2 2 0 0 0 15.5 15.5V6A2 2 0 0 0 13.5 4H12.5"></path><rect x="7.5" y="2.5" width="5" height="3" rx="1"></rect><polyline points="7.5,11 9.5,13 13,9"></polyline>',
}
MODE_NAME = {'movement':'Movement','strength':'Strength','hundreds':'100s','pt':'PT'}

def glyph(mode, size, color=ACC, sw=1.8):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 20 20" fill="none" stroke="{color}" stroke-width="{sw}" '
            f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink: 0">{GLYPHS[mode]}</svg>')

# ---------- overlay ----------
def _caps(text):
    return text.upper().replace('100S', '100s')
def ov_eyebrow(mode, text):
    return (f'<div style="display: flex; align-items: center; gap: 10px; color: {ACC}; font-size: 18px; font-weight: 600; letter-spacing: .1em; line-height: 1">'
            f'{glyph(mode,22)}<span>{_caps(text)}</span></div>')

def ov_right(text):
    return f'<div style="color: {T2}; font-size: 18px; font-weight: 600; letter-spacing: .1em; text-transform: uppercase; line-height: 1; white-space: nowrap">{text}</div>'

def ov_disc(num, label, frac, kind='run', aria='Next'):
    C = 873.4
    if kind == 'lead':
        bg = f'background: rgba(18,42,58,.96); border: 1.5px solid {BORDER}'
        track = 'rgba(127,200,183,.15)'; prog = ACC; col = ACC
    else:
        bg = f'background: {ACC}; border: 0'
        track = 'rgba(8,22,31,.15)'; prog = INK; col = INK
    arc = ''
    if frac > 0:
        arc = (f'<circle cx="150" cy="150" r="139" fill="none" stroke="{prog}" stroke-width="6" stroke-linecap="round" '
               f'stroke-dasharray="{frac*C:.0f} {C:.0f}" transform="rotate(-90 150 150)"></circle>')
    return f'''<button type="button" aria-label="{aria}" style="position: absolute; left: 1070px; top: 50px; width: 300px; height: 300px; box-sizing: border-box; border-radius: 50%; padding: 0; {bg}; box-shadow: 0 30px 60px rgba(0,0,0,.5); cursor: pointer; font-family: inherit; color: {col}">
    <svg width="300" height="300" viewBox="0 0 300 300" style="position: absolute; left: -1px; top: -1px" aria-hidden="true"><circle cx="150" cy="150" r="139" fill="none" stroke="{track}" stroke-width="6"></circle>{arc}</svg>
    <span style="position: absolute; left: 0; right: 0; top: 96px; text-align: center; font-size: 84px; font-weight: 600; letter-spacing: -.04em; line-height: 1">{num}</span>
    <span style="position: absolute; left: 0; right: 0; top: 196px; text-align: center; font-size: 16px; font-weight: 700; letter-spacing: .12em; line-height: 1; text-transform: uppercase">{label}</span>
  </button>'''

def strip(cols):
    out = []
    for top, name, st in cols:
        if st in ('cur','complete'): rule = f'background: {ACC}'
        elif st == 'half': rule = f'background: linear-gradient(to right, {ACC} 50%, rgba(127,200,183,.25) 50%)'
        else: rule = 'background: rgba(127,200,183,.25)'
        col = TXT if st in ('cur','complete','half') else T3
        lt = '; text-decoration: line-through' if st == 'done' else ''
        out.append(f'''      <div style="color: {col}; min-width: 0">
        <div style="height: 3px; {rule}"></div>
        <div style="margin-top: 12px; font-size: 24px; font-weight: 800; line-height: 1.25">{top}</div>
        <div style="margin-top: 6px; font-size: 17px; line-height: 1.3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis{lt}">{name}</div>
      </div>''')
    n = len(cols)
    return (f'<div style="margin-top: 28px; display: grid; grid-template-columns: repeat({n}, minmax(0, 1fr)); gap: 16px">\n'
            + '\n'.join(out) + '\n    </div>')

def btn(label, kind='secondary', size='ov'):
    pad = '9px 18px'; fs = '13px'
    if kind == 'primary': st = f'background: {ACC}; border: 1.5px solid {ACC}; color: {INK}; font-weight: 700'
    elif kind == 'accent': st = f'background: transparent; border: 1.5px solid {ACC}; color: {ACC}; font-weight: 600'
    else: st = f'background: transparent; border: 1.5px solid rgba(127,200,183,.35); color: {T2}; font-weight: 600'
    return f'<button type="button" style="font-family: inherit; font-size: {fs}; padding: {pad}; border-radius: 999px; {st}; cursor: pointer; white-space: nowrap">{label}</button>'

def link(label, color=T3, fs=13, fw=500):
    return f'<a href="#" style="font-size: {fs}px; font-weight: {fw}; color: {color}; text-decoration: underline; text-underline-offset: 3px; white-space: nowrap">{label}</a>'

def ov_actions(first='Pause', snooze=True, skip='Skip · 1 today'):
    parts = [btn(first)]
    if snooze: parts.append(btn('Snooze 5 min','accent'))
    parts.append(link(skip))
    return ('<div style="margin-top: 22px; display: flex; justify-content: center; align-items: center; gap: 12px">'
            + ''.join(parts) + '</div>')

def overlay(eyebrow, right, body, strip_html, actions, disc, header_pad=200, dim='#0f1820'):
    return f'''<div style="width: 1440px; height: 900px; position: relative; overflow: hidden; background: {dim}; {FONT}; color: {TXT}">
  <div style="position: absolute; left: 220px; top: 120px; width: 1000px; height: 660px; box-sizing: border-box; padding: 56px 80px 44px; background: {PANEL}; border: 1px solid {BORDER}; border-radius: 36px; box-shadow: 0 40px 100px rgba(0,0,0,.5); display: flex; flex-direction: column">
    <div style="display: flex; justify-content: space-between; align-items: center; gap: 24px; padding-right: {header_pad}px">
      {eyebrow}
      {right}
    </div>
    {body}
    {strip_html}
    {actions}
  </div>
  {disc}
</div>'''

# body helpers
def kicker(t, color=T2, mt=0):
    return f'<div style="margin-top: {mt}px; font-size: 20px; font-weight: 600; color: {color}; line-height: 1.2">{t}</div>'
def name56(t, mt=8):
    return f'<div style="margin-top: {mt}px; font-size: 56px; font-weight: 700; letter-spacing: -.03em; line-height: 1.05; color: {TXT}; text-wrap: balance">{t}</div>'
def name80(t, mt=8):
    return f'<div style="margin-top: {mt}px; font-size: 80px; font-weight: 700; letter-spacing: -.035em; line-height: 1; color: {TXT}">{t}</div>'
def dose(t, mt=6):
    return f'<div style="margin-top: {mt}px; font-size: 28px; font-weight: 700; letter-spacing: -.015em; line-height: 1.1; color: {TXT}">{t}</div>'
def modifiers(t, mt=6):
    return f'<div style="margin-top: {mt}px; font-size: 20px; font-weight: 600; line-height: 1.2; color: {T2}">{t}</div>'
def instr(t, fs=24, mt=22, align='left'):
    return f'<p style="margin: {mt}px 0 0; font-size: {fs}px; font-weight: 400; line-height: 1.45; color: {T2}; text-wrap: pretty; text-align: {align}">{t}</p>'

def side_toggle(active, mt=18):
    def seg(lbl):
        if lbl == active: return f'<span style="padding: 8px 30px; border-radius: 999px; background: {ACC}; color: {INK}">{lbl}</span>'
        return f'<span style="padding: 8px 30px; border-radius: 999px; color: {T3}">{lbl}</span>'
    return (f'<div style="margin-top: {mt}px; display: inline-flex; padding: 6px; border-radius: 999px; background: rgba(127,200,183,.14); font-size: 30px; font-weight: 700; line-height: 1.2">'
            + seg('Left') + seg('Right') + '</div>')

ICONS = {
 'up': '<polyline points="4,13 14,4 24,13"></polyline>',
 'down': '<polyline points="4,3 14,12 24,3"></polyline>',
 'pause': '<line x1="10" y1="2" x2="10" y2="14"></line><line x1="18" y1="2" x2="18" y2="14"></line>',
 'hold': '<line x1="5" y1="5" x2="23" y2="5"></line><line x1="5" y1="11" x2="23" y2="11"></line>',
 'swap': '<polyline points="18,1 23,5 18,9"></polyline><line x1="5" y1="5" x2="23" y2="5"></line><polyline points="10,7 5,11 10,15"></polyline><line x1="23" y1="11" x2="5" y2="11"></line>',
}
def icon(name, color=INK, sw=3.5):
    return f'<svg width="28" height="16" viewBox="0 0 28 16" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{ICONS[name]}</svg>'

def meter(level, ic, aria):
    if level > 0:
        inner = (f'<div style="position: absolute; left: 0; right: 0; bottom: 0; height: {level}%; min-height: 64px; border-radius: 999px; background: {ACC}; '
                 f'display: flex; justify-content: center; padding-top: 16px; box-sizing: border-box">{icon(ic)}</div>')
    else:
        inner = f'<div style="position: absolute; left: 0; right: 0; top: 124px; display: flex; justify-content: center">{icon(ic, ACC, 3)}</div>'
    return (f'<div role="img" aria-label="{aria}" style="position: relative; width: 64px; height: 264px; border-radius: 999px; background: rgba(127,200,183,.14); overflow: hidden">'
            + inner + '</div>')

def ladder(total, done, aria):
    gap = 4; h = (264 - gap*(total-1)) / total
    segs = []
    for i in range(total):
        if i < done: st = f'background: {ACC}'
        elif i == done: st = f'background: transparent; box-shadow: inset 0 0 0 2px {ACC}'
        else: st = 'background: rgba(127,200,183,.14)'
        segs.append(f'<div style="height: {h:.1f}px; border-radius: 6px; {st}"></div>')
    return (f'<div role="img" aria-label="{aria}" style="width: 64px; height: 264px; display: flex; flex-direction: column-reverse; gap: {gap}px">'
            + ''.join(segs) + '</div>')

def meter_col(meter_html, counter, ccolor=TXT):
    return (f'<div style="width: 180px; display: flex; flex-direction: column; align-items: center; gap: 18px; flex-shrink: 0">{meter_html}'
            f'<div style="font-size: 28px; font-weight: 700; letter-spacing: -.015em; line-height: 1.1; white-space: nowrap; color: {ccolor}">{counter}</div></div>')

def body_two(meter_col_html, text_html):
    return (f'<div style="flex: 1; display: flex; align-items: center; justify-content: center; gap: 56px; min-height: 0">{meter_col_html}'
            f'<div style="width: 604px; display: flex; flex-direction: column; align-items: flex-start; text-align: left">{text_html}</div></div>')

def body_center(text_html):
    return (f'<div style="flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; min-height: 0">'
            f'<div style="max-width: 780px; display: flex; flex-direction: column; align-items: center">{text_html}</div></div>')

def streak(n):
    return (f'<div style="margin-top: 28px; display: inline-flex; align-items: baseline; gap: 12px; padding: 14px 26px; border-radius: 999px; background: rgba(127,200,183,.14); color: {ACC}">'
            f'<span style="font-size: 32px; font-weight: 800; line-height: 1">{n}</span><span style="font-size: 20px; font-weight: 600">breaks in a row today</span></div>')

def back_to_work():
    return (f'<button type="button" style="margin-top: 28px; font-family: inherit; font-size: 22px; font-weight: 700; padding: 20px 48px; border-radius: 999px; background: {ACC}; border: 0; color: {INK}; cursor: pointer">Back to work</button>')

# ---------- panels ----------
def p_disc(num, frac, kind='run'):
    C = 2*3.14159*27.75
    if kind == 'lead':
        bg = f'background: rgba(12,30,42,1); box-shadow: inset 0 0 0 1.5px {BORDER}'; track='rgba(127,200,183,.15)'; prog=ACC; col=ACC
    else:
        bg = f'background: {ACC}'; track='rgba(8,22,31,.15)'; prog=INK; col=INK
    arc = ''
    if frac > 0:
        arc = f'<circle cx="32" cy="32" r="27.75" fill="none" stroke="{prog}" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="{frac*C:.1f} {C:.1f}" transform="rotate(-90 32 32)"></circle>'
    return (f'<div style="position: relative; width: 64px; height: 64px; border-radius: 50%; {bg}; flex-shrink: 0; color: {col}">'
            f'<svg width="64" height="64" viewBox="0 0 64 64" style="position: absolute; left: 0; top: 0" aria-hidden="true"><circle cx="32" cy="32" r="27.75" fill="none" stroke="{track}" stroke-width="2.5"></circle>{arc}</svg>'
            f'<span style="position: absolute; left: 0; right: 0; top: 22px; text-align: center; font-size: 17px; font-weight: 700; letter-spacing: -.02em; line-height: 20px">{num}</span></div>')

def p_eyebrow(mode, text):
    return (f'<div style="display: flex; align-items: center; gap: 6px; color: {ACC}; font-size: 11px; font-weight: 600; letter-spacing: .1em; line-height: 14px; white-space: nowrap">'
            f'{glyph(mode,13)}<span>{_caps(text)}</span></div>')

def p_title(t):
    return f'<div style="font-size: 20px; font-weight: 700; letter-spacing: -.015em; line-height: 1.15; color: {TXT}">{t}</div>'
def p_dose(t):
    return f'<div style="font-size: 20px; font-weight: 700; letter-spacing: -.015em; line-height: 1.15; color: {ACC}">{t}</div>'
def p_body(t):
    return f'<div style="font-size: 13px; line-height: 1.45; color: {T2}; text-wrap: pretty">{t}</div>'

def p_actions(parts):
    return '<div style="display: flex; align-items: center; gap: 10px">' + ''.join(parts) + '</div>'

def info_badge(text, dot=True, fs=12.5):
    d = f'<span style="width: 7px; height: 7px; border-radius: 50%; background: {WARN}; flex-shrink: 0"></span>' if dot else ''
    return (f'<div style="display: flex; align-items: center; gap: 10px; padding: 8px 12px; border-radius: 10px; background: rgba(127,200,183,.10); font-size: {fs}px; color: {T2}; line-height: 1.4">'
            f'{d}<span>{text}</span></div>')

def panel_board(disc, textcol, extra, actions, w=400, H=340):
    left = (600 - w)//2
    return f'''<div style="width: 600px; height: {H}px; position: relative; overflow: hidden; background: #e9e6df; {FONT}; color: {TXT}">
  <div style="position: absolute; left: 40px; top: 60px; width: 520px; height: 400px; border-radius: 12px; background: #f4f1ea"></div>
  <div style="position: absolute; left: {left}px; top: 12px; width: {w}px; box-sizing: border-box; padding: 18px 20px 16px; background: rgba(18,42,58,.94); border: 1px solid {BORDER}; border-radius: 20px; box-shadow: 0 24px 60px rgba(0,0,0,.45); display: flex; flex-direction: column; gap: 14px">
    <div style="display: flex; gap: 16px; align-items: flex-start">
      {disc}
      <div style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 5px">{textcol}</div>
    </div>
    {extra}
    {actions}
  </div>
</div>'''

# ---------- menu ----------
SHAPES = {
 'movement': '<path d="M8 2A6 6 0 1 1 7.99 2Z" pathLength="100"></path>',
 'strength': '<path d="M8 2H11.5A2.5 2.5 0 0 1 14 4.5V11.5A2.5 2.5 0 0 1 11.5 14H4.5A2.5 2.5 0 0 1 2 11.5V4.5A2.5 2.5 0 0 1 4.5 2Z" pathLength="100"></path>',
 'hundreds': '<path d="M8 1.8L14.6 13.6H1.4Z" pathLength="100"></path>',
 'pt': '<path d="M8 1.5L14.5 8L8 14.5L1.5 8Z" pathLength="100"></path>',
}
def shape_paths(mode, state, color, frac=0.42):
    p = SHAPES[mode]
    def withattrs(attrs): return p.replace('pathLength="100"', f'pathLength="100" {attrs}')
    if state == 'sitting':
        return (withattrs(f'stroke="{color}" stroke-opacity=".35"') +
                withattrs(f'stroke="{color}" stroke-dasharray="{frac*100:.0f} 100"'))
    if state == 'paused':
        return withattrs(f'stroke="{color}" stroke-opacity=".75" stroke-dasharray="6 5"')
    if state == 'offhours':
        return withattrs(f'stroke="{color}" stroke-opacity=".55"')
    if state == 'away':
        return withattrs(f'stroke="{color}" stroke-opacity=".6"')
    return withattrs(f'stroke="{color}"')

def mb_icon(mode, state, color, size=14, frac=0.42, sw=2):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 16 16" fill="none" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink: 0">'
            + shape_paths(mode, state, color, frac) + '</svg>')

def mb_label(state, minutes='32m'):
    return {'sitting': minutes, 'paused': '‖ 42m', 'offhours': '', 'away': '—'}[state]

def m_disc(kind, text='32', frac=0.58):
    C = 2*3.14159*17.5
    if kind == 'run':
        return (f'<div style="position: relative; width: 40px; height: 40px; border-radius: 50%; background: {ACC}; flex-shrink: 0">'
                f'<svg width="40" height="40" viewBox="0 0 40 40" style="position: absolute; left: 0; top: 0" aria-hidden="true"><circle cx="20" cy="20" r="17.5" fill="none" stroke="rgba(8,22,31,.15)" stroke-width="2.5"></circle>'
                f'<circle cx="20" cy="20" r="17.5" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="{frac*C:.1f} {C:.1f}" transform="rotate(-90 20 20)"></circle></svg>'
                f'<span style="position: absolute; left: 0; right: 0; top: 11px; text-align: center; font-size: 13px; font-weight: 700; line-height: 18px; color: {INK}">{text}</span></div>')
    if kind == 'paused':
        return (f'<div style="position: relative; width: 40px; height: 40px; flex-shrink: 0"><svg width="40" height="40" viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="18.75" fill="none" stroke="{T3}" stroke-width="2.5" stroke-dasharray="5 4"></circle></svg>'
                f'<span style="position: absolute; left: 0; right: 0; top: 11px; text-align: center; font-size: 13px; font-weight: 700; line-height: 18px; color: {T3}">‖</span></div>')
    lab = '—' if kind == 'away' else ''
    return (f'<div style="position: relative; width: 40px; height: 40px; flex-shrink: 0"><svg width="40" height="40" viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="20" r="18.75" fill="none" stroke="rgba(127,200,183,.25)" stroke-width="2.5"></circle></svg>'
            f'<span style="position: absolute; left: 0; right: 0; top: 11px; text-align: center; font-size: 13px; font-weight: 700; line-height: 18px; color: {T2}">{lab}</span></div>')

def mode_seg_menu(active, modes=('movement','strength')):
    many = len(modes) > 2
    segs = []
    for m in modes:
        on = m == active
        st = f'background: {ACC}; color: {INK}' if on else f'background: transparent; color: {T2}'
        gcol = INK if on else T2
        show_name = on or not many
        flex = 'flex: 1 1 auto' if (on or not many) else 'flex: 0 0 36px'
        label = f'<span>{MODE_NAME[m]}</span>' if show_name else ''
        aria = '' if show_name else f' aria-label="{MODE_NAME[m]}"'
        segs.append(f'<button type="button"{aria} style="{flex}; display: flex; align-items: center; justify-content: center; gap: 6px; padding: 6px 8px; border: 0; border-radius: 999px; {st}; font-family: inherit; font-size: 12px; font-weight: 600; line-height: 16px; cursor: pointer">{glyph(m,14,gcol)}{label}</button>')
    return (f'<div role="radiogroup" aria-label="Break mode" style="display: flex; gap: 2px; padding: 3px; border-radius: 999px; background: rgba(127,200,183,.12)">'
            + ''.join(segs) + '</div>')

def m_row(label, right='', hl=False, color=TXT, chevron=False):
    bg = 'background: rgba(127,200,183,.14); ' if hl else ''
    r = ''
    if right: r += f'<span style="font-size: 12px; color: {T3}; font-weight: 400">{right}</span>'
    if chevron: r += f'<span style="color: {T3}; font-size: 13px; margin-left: 6px">›</span>'
    return (f'<div style="{bg}display: flex; justify-content: space-between; align-items: center; padding: 7px 10px; border-radius: 7px; font-size: 13px; font-weight: 500; line-height: 1.3; color: {color}">'
            f'<span>{label}</span><span style="display: flex; align-items: center">{r}</span></div>')

def m_div():
    return '<div style="height: 1px; background: rgba(127,200,183,.18); margin: 6px 4px"></div>'

def menu_board(mode, icon_state, disc, title, subtitle, rows, stats=('Today · 1 snoozed · 1 skipped','Longest sitting bout 1 h 12 m')):
    sub = f'<div style="font-size: 12px; color: {T2}; line-height: 1.35">{subtitle}</div>' if subtitle else ''
    lab = mb_label(icon_state)
    labhtml = f'<span>{lab}</span>' if lab else ''
    return f'''<div style="width: 560px; height: 460px; position: relative; overflow: hidden; background: #d3cfc7; {FONT}; color: {TXT}">
  <div style="position: absolute; left: 0; top: 0; right: 0; height: 24px; background: #efece6; display: flex; align-items: center; justify-content: flex-end; padding-right: 14px; gap: 5px; color: #1d1d1f; font-size: 13px; font-weight: 500">{mb_icon_v3s(mode, icon_state, '#1d1d1f')}{labhtml}</div>
  <div style="position: absolute; left: 268px; top: 32px; width: 264px; box-sizing: border-box; padding: 6px; background: rgba(18,42,58,.96); border: 1px solid {BORDER}; border-radius: 12px; box-shadow: 0 18px 50px rgba(0,0,0,.45)">
    <div style="display: flex; gap: 12px; align-items: center; padding: 10px 10px 12px; border-bottom: 1px solid rgba(127,200,183,.18); margin-bottom: 6px">
      {disc}
      <div style="display: flex; flex-direction: column; gap: 3px; min-width: 0"><div style="font-size: 14px; font-weight: 700; line-height: 1.3">{title}</div>{sub}</div>
    </div>
    <div style="padding: 2px 4px 4px">{mode_seg_menu(mode)}</div>
    {m_div()}
    {''.join(rows)}
    {m_div()}
    <div style="padding: 6px 10px; display: flex; flex-direction: column; gap: 4px; font-size: 13px; line-height: 1.3"><span style="color: {T2}">{stats[0]}</span><span style="color: {T3}">{stats[1]}</span></div>
    {m_div()}
    {m_row('Settings…', '⌘,')}
    {m_row('Quit Movez', '⌘Q')}
  </div>
</div>'''

# ---------- settings ----------
def seg(options, active, glyphs=None):
    out = []
    for i, o in enumerate(options):
        on = o == active
        st = f'background: {ACC}; color: {INK}' if on else f'background: transparent; color: {T2}'
        g = glyph(glyphs[i], 14, INK if on else T2) if glyphs else ''
        out.append(f'<button type="button" style="display: inline-flex; align-items: center; gap: 6px; padding: 6px 14px; border: 0; border-radius: 999px; {st}; font-family: inherit; font-size: 12px; font-weight: 600; line-height: 16px; cursor: pointer; white-space: nowrap">{g}{o}</button>')
    return f'<div style="display: inline-flex; padding: 3px; border-radius: 999px; background: rgba(127,200,183,.12)">' + ''.join(out) + '</div>'

def toggle(on=True):
    if on:
        return f'<span role="switch" aria-checked="true" style="display: inline-flex; width: 38px; height: 22px; box-sizing: border-box; padding: 3px; border-radius: 999px; background: {ACC}; justify-content: flex-end"><span style="width: 16px; height: 16px; border-radius: 50%; background: {INK}"></span></span>'
    return f'<span role="switch" aria-checked="false" style="display: inline-flex; width: 38px; height: 22px; box-sizing: border-box; padding: 3px; border-radius: 999px; background: rgba(127,200,183,.2); justify-content: flex-start"><span style="width: 16px; height: 16px; border-radius: 50%; background: {T2}"></span></span>'

def chip(label, sel):
    st = f'background: {ACC}; border: 1.5px solid {ACC}; color: {INK}' if sel else f'background: transparent; border: 1.5px solid rgba(127,200,183,.35); color: {T2}'
    return f'<button type="button" style="font-family: inherit; font-size: 13px; font-weight: 500; padding: 5px 13px; border-radius: 999px; {st}; cursor: pointer; white-space: nowrap">{label}</button>'

def chips(labels_sel):
    return '<div style="display: flex; gap: 8px; flex-wrap: wrap; justify-content: flex-end">' + ''.join(chip(l, s) for l, s in labels_sel) + '</div>'

def select(val, minw=160):
    return (f'<div style="display: inline-flex; align-items: center; justify-content: space-between; gap: 12px; min-width: {minw}px; box-sizing: border-box; padding: 6px 10px 6px 14px; border: 1px solid rgba(127,200,183,.35); border-radius: 8px; font-size: 13px; color: {TXT}">'
            f'<span>{val}</span><svg width="8" height="12" viewBox="0 0 8 12" fill="none" stroke="{T2}" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="1.5,4.5 4,2 6.5,4.5"></polyline><polyline points="1.5,7.5 4,10 6.5,7.5"></polyline></svg></div>')

def srow(label, control, sub=None):
    s = f'<div style="margin-top: 3px; font-size: 12px; font-weight: 400; color: {T3}; line-height: 1.4">{sub}</div>' if sub else ''
    return (f'<div style="display: flex; justify-content: space-between; align-items: center; gap: 16px; min-height: 32px">'
            f'<div style="font-size: 13px; font-weight: 500; color: {TXT}; line-height: 1.3"><div>{label}</div>{s}</div>'
            f'<div style="display: flex; align-items: center; gap: 12px; flex-shrink: 0">{control}</div></div>')

def section(label, rows, first=False):
    border = '' if first else 'border-top: 1px solid rgba(127,200,183,.14); padding-top: 22px; margin-top: 22px; '
    return (f'<div style="{border}display: grid; grid-template-columns: 160px minmax(0, 1fr)">'
            f'<div style="padding-top: 9px; font-size: 11px; font-weight: 600; letter-spacing: .1em; text-transform: uppercase; color: {ACC}">{label}</div>'
            f'<div style="display: flex; flex-direction: column; gap: 12px">{"".join(rows)}</div></div>')

def weight_guidance(fs=12.5):
    return (f'<div style="display: flex; gap: 10px; align-items: flex-start; padding: 10px 12px; border-radius: 10px; background: rgba(127,200,183,.10); font-size: {fs}px; line-height: 1.45; color: {T2}">'
            f'<span style="padding-top: 1px">{glyph("strength",16)}</span><span><strong style="color: {TXT}; font-weight: 600">Choosing a weight.</strong> Pick a weight you could lift 3–5 more times when the set ends. If the last reps feel easy, step up a size next time; if they feel hard, step down.</span></div>')

def settings_window(sections_html, H=1040):
    return f'''<div style="width: 760px; height: {H}px; position: relative; overflow: hidden; background: #12283a; border-radius: 12px; {FONT}; color: {TXT}; display: flex; flex-direction: column">
  <div style="height: 52px; flex-shrink: 0; display: flex; align-items: center; justify-content: center; border-bottom: 1px solid rgba(127,200,183,.14); font-size: 15px; font-weight: 700">Movez settings</div>
  <div style="flex: 1; padding: 24px 32px; min-height: 0">{sections_html}</div>
  <div style="flex-shrink: 0; display: flex; justify-content: space-between; align-items: center; padding: 12px 32px; border-top: 1px solid rgba(127,200,183,.14); font-size: 12px; color: {T3}"><span>›&nbsp; Debug · time scale, signal injectors, state inspector</span><span>Movez 0.5.0 (60) · library v4.2 · 174 movements</span></div>
'''

# ---- side pill variants ----
def side_pill(active, fs=18, padv=6, padh=20, trackpad=4):
    def seg(lbl):
        if lbl == active: return f'<span style="padding: {padv}px {padh}px; border-radius: 999px; background: {ACC}; color: {INK}">{lbl}</span>'
        return f'<span style="padding: {padv}px {padh}px; border-radius: 999px; color: {T3}">{lbl}</span>'
    return (f'<div style="display: inline-flex; padding: {trackpad}px; border-radius: 999px; background: rgba(127,200,183,.14); font-size: {fs}px; font-weight: 700; line-height: 1.2; white-space: nowrap">'
            + seg('Left') + seg('Right') + '</div>')

def header_with_pill(eyebrow, right, pill, left_px, center=False):
    pos = f'left: {left_px}px; transform: translateY(-50%)' if not center else f'left: {left_px}px; transform: translate(-50%, -50%)'
    return f'''<div style="position: relative; display: flex; justify-content: space-between; align-items: center; gap: 24px; padding-right: 200px; min-height: 42px">
      {eyebrow}
      <div style="position: absolute; top: 50%; {pos}">{pill}</div>
      {right}
    </div>'''

def overlay_h(header, body, strip_html, actions, disc, dim='#0f1820'):
    return f'''<div style="width: 1440px; height: 900px; position: relative; overflow: hidden; background: {dim}; {FONT}; color: {TXT}">
  <div style="position: absolute; left: 220px; top: 120px; width: 1000px; height: 660px; box-sizing: border-box; padding: 56px 80px 44px; background: {PANEL}; border: 1px solid {BORDER}; border-radius: 36px; box-shadow: 0 40px 100px rgba(0,0,0,.5); display: flex; flex-direction: column">
    {header}
    {body}
    {strip_html}
    {actions}
  </div>
  {disc}
</div>'''

# ---- menu icon v2: glyph inside an 18 pt shape ----
SHAPES18 = {
 'movement': ('<path d="M9 1A8 8 0 1 1 8.99 1Z" pathLength="100"></path>', (9, 9), 10),
 'strength': ('<path d="M9 1H13.5A3.5 3.5 0 0 1 17 4.5V13.5A3.5 3.5 0 0 1 13.5 17H4.5A3.5 3.5 0 0 1 1 13.5V4.5A3.5 3.5 0 0 1 4.5 1Z" pathLength="100"></path>', (9, 9), 10.5),
 'hundreds': ('<path d="M9 1L17.2 16.2H0.8Z" pathLength="100"></path>', (9, 11.3), 7),
 'pt': ('<path d="M9 0.8L17.2 9L9 17.2L0.8 9Z" pathLength="100"></path>', (9, 9), 8),
}
def mb_icon_v2(mode, color, size=18, frac=0.42, sw=1.6):
    p, (cx, cy), g = SHAPES18[mode]
    track = p.replace('pathLength="100"', f'pathLength="100" stroke="{color}" stroke-opacity=".35"')
    prog = p.replace('pathLength="100"', f'pathLength="100" stroke="{color}" stroke-dasharray="{frac*100:.0f} 100"')
    gsw = max(1.1 / (g/20), 2.0)
    inner = (f'<svg x="{cx-g/2:.2f}" y="{cy-g/2:.2f}" width="{g}" height="{g}" viewBox="0 0 20 20" fill="none" stroke="{color}" stroke-width="{gsw:.2f}" '
             f'stroke-linecap="round" stroke-linejoin="round">{GLYPHS[mode]}</svg>')
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 18 18" fill="none" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink: 0; overflow: visible">'
            + track + prog + inner + '</svg>')

def dose_with_pill(text, active):
    return (f'<div style="margin-top: 6px; width: 100%; display: flex; justify-content: space-between; align-items: center; gap: 16px">'
            f'<div style="font-size: 28px; font-weight: 700; letter-spacing: -.015em; line-height: 1.1; color: {TXT}">{text}</div>{side_pill(active, 22, 6, 22)}</div>')

def mb_icon_v3(mode, color, size=18, frac=0.42, sw=1.6, g=10):
    p = '<path d="M9 1A8 8 0 1 1 8.99 1Z" pathLength="100"></path>'
    track = p.replace('pathLength="100"', f'pathLength="100" stroke="{color}" stroke-opacity=".35"')
    prog = p.replace('pathLength="100"', f'pathLength="100" stroke="{color}" stroke-dasharray="{frac*100:.0f} 100"')
    gsw = max(1.1 / (g/20), 2.0)
    inner = (f'<svg x="{9-g/2:.2f}" y="{9-g/2:.2f}" width="{g}" height="{g}" viewBox="0 0 20 20" fill="none" stroke="{color}" stroke-width="{gsw:.2f}" '
             f'stroke-linecap="round" stroke-linejoin="round">{GLYPHS[mode]}</svg>')
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 18 18" fill="none" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink: 0; overflow: visible">'
            + track + prog + inner + '</svg>')

def mb_icon_v3s(mode, state, color, size=18, frac=0.42, sw=1.6, g=10):
    p = '<path d="M9 1A8 8 0 1 1 8.99 1Z" pathLength="100"></path>'
    def a(attrs): return p.replace('pathLength="100"', f'pathLength="100" {attrs}')
    gop = '1'
    if state == 'sitting':
        ring = a(f'stroke="{color}" stroke-opacity=".35"') + a(f'stroke="{color}" stroke-dasharray="{frac*100:.0f} 100"')
    elif state == 'paused':
        ring = a(f'stroke="{color}" stroke-opacity=".75" stroke-dasharray="6 5"')
    elif state == 'offhours':
        ring = a(f'stroke="{color}" stroke-opacity=".55"'); gop = '.55'
    else:  # away
        ring = a(f'stroke="{color}" stroke-opacity=".6"')
    gsw = max(1.1 / (g/20), 2.0)
    inner = (f'<svg x="{9-g/2:.2f}" y="{9-g/2:.2f}" width="{g}" height="{g}" viewBox="0 0 20 20" fill="none" stroke="{color}" stroke-opacity="{gop}" stroke-width="{gsw:.2f}" '
             f'stroke-linecap="round" stroke-linejoin="round">{GLYPHS[mode]}</svg>')
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 18 18" fill="none" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink: 0; overflow: visible">'
            + ring + inner + '</svg>')
