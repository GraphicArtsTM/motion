"""Push Pals — STYLE REFERENCE mood board (1536x1024)."""
import math, random, sys
from shared import P, filters, corners, gear_path, flame, matchstick

W, H = 1536, 1024
random.seed(7)

def wood_filter(i, seed):
    return f'''<filter id="wood{i}" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="0.0035 0.09" numOctaves="5" seed="{seed}" result="t"/>
  <feColorMatrix in="t" type="matrix" values="0.27 0 0 0 0.040  0.14 0 0 0 0.012  0.06 0 0 0 0.002  0 0 0 0 1"/>
</filter>'''

defs = [filters()] + [wood_filter(i, s) for i, s in enumerate([11, 23, 37, 51, 64])]
defs.append('''
<filter id="grain" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="1.1" numOctaves="2" seed="5" result="n"/>
  <feColorMatrix type="saturate" values="0"/>
</filter>
<filter id="blurFar"><feGaussianBlur stdDeviation="7"/></filter>
<filter id="blurMid"><feGaussianBlur stdDeviation="3.5"/></filter>
<filter id="blurNear" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="7"/></filter>
<filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="18"/></filter>
<radialGradient id="candleLight" cx="170" cy="120" r="1250" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#F2C46B" stop-opacity="0.75"/>
  <stop offset="0.35" stop-color="#E0A04A" stop-opacity="0.22"/>
  <stop offset="1" stop-color="#E0A04A" stop-opacity="0"/>
</radialGradient>
<radialGradient id="vignette" cx="0.42" cy="0.42" r="0.78">
  <stop offset="0.35" stop-color="#000" stop-opacity="0"/>
  <stop offset="1" stop-color="#070301" stop-opacity="0.88"/>
</radialGradient>
<linearGradient id="dofMask" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#fff"/><stop offset="0.24" stop-color="#fff" stop-opacity="0.6"/><stop offset="0.36" stop-color="#fff" stop-opacity="0"/>
</linearGradient>
<mask id="dof"><rect width="1536" height="1024" fill="url(#dofMask)"/></mask>
<radialGradient id="paperEdge" cx="0.5" cy="0.5" r="0.72">
  <stop offset="0.6" stop-color="#8a5a2a" stop-opacity="0"/><stop offset="1" stop-color="#8a5a2a" stop-opacity="0.28"/>
</radialGradient>
<radialGradient id="brass" cx="0.35" cy="0.3" r="0.8">
  <stop offset="0" stop-color="#F6DC92"/><stop offset="0.45" stop-color="#C99A42"/><stop offset="1" stop-color="#7A5420"/>
</radialGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#F6D98A"/><stop offset="0.55" stop-color="#E0B04E"/><stop offset="1" stop-color="#A8782C"/>
</linearGradient>
<linearGradient id="wax" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#C9B48E"/><stop offset="0.35" stop-color="#F3E6C8"/><stop offset="1" stop-color="#9E8664"/>
</linearGradient>
<pattern id="hatch" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(35)">
  <line x1="0" y1="0" x2="0" y2="5" stroke="#2F5487" stroke-width="0.9" opacity="0.55"/>
</pattern>
''')

def brass_pin(x, y, r=11):
    return f'''<g filter="url(#shadowS)"><circle cx="{x}" cy="{y}" r="{r}" fill="url(#brass)" stroke="{P['ink']}" stroke-width="1.3"/>
<circle cx="{x}" cy="{y}" r="{r*0.55}" fill="none" stroke="#7A5420" stroke-width="0.8" opacity="0.7"/>
<ellipse cx="{x-r*0.32}" cy="{y-r*0.38}" rx="{r*0.32}" ry="{r*0.2}" fill="#FFF4CF" opacity="0.8"/></g>'''

out = []
# ---------- TABLE ----------
planks = [(-20, 230), (210, 250), (460, 240), (700, 230), (930, 120)]
for i, (y, h) in enumerate(planks):
    out.append(f'<rect x="0" y="{y}" width="{W}" height="{h}" filter="url(#wood{i})"/>')
    out.append(f'<rect x="0" y="{y}" width="{W}" height="{h}" fill="{["#000","#1a0d05"][i%2]}" opacity="{0.06*(i%3)}"/>')
    out.append(f'<line x1="0" y1="{y+h-1}" x2="{W}" y2="{y+h-1}" stroke="#120803" stroke-width="3"/>')
    out.append(f'<line x1="0" y1="{y+h+1.5}" x2="{W}" y2="{y+h+1.5}" stroke="#9a6a40" stroke-width="1" opacity="0.35"/>')
table = ''.join(out)

scene = [f'<g id="table">{table}</g>']
# depth of field: blurred copy over the far part of the table
scene.append(f'<g mask="url(#dof)"><g filter="url(#blurFar)">{table}</g></g>')

# ---------- FAR BACKGROUND (blurred) ----------
far = []
# candle
far.append(f'<ellipse cx="170" cy="400" rx="105" ry="22" fill="#5c3c18"/>')
far.append(f'<ellipse cx="170" cy="392" rx="100" ry="19" fill="url(#brass)"/>')
far.append(f'<rect x="128" y="160" width="84" height="232" fill="url(#wax)"/>')
far.append(f'<ellipse cx="170" cy="160" rx="42" ry="9" fill="#F7EBD0"/>')
far.append(f'<path d="M150 160 q-6 40 -2 80 q4 -38 10 -78z" fill="#F7EBD0" opacity="0.9"/>')
far.append('<line x1="170" y1="160" x2="170" y2="138" stroke="#1a0d05" stroke-width="3"/>')
# matchbox top-right
far.append(f'<g transform="translate(1235 40) rotate(-8)">'
           f'<rect x="0" y="0" width="360" height="200" fill="{P["kraft"]}"/>'
           f'<rect x="0" y="0" width="360" height="22" fill="#5a3a24" filter="url(#sand)"/>'
           + ''.join(f'<rect x="{30+i*30}" y="40" width="9" height="160" fill="{P["wood_l"]}"/><ellipse cx="{34.5+i*30}" cy="44" rx="13" ry="11" fill="{P["brick"]}"/>' for i in range(10)) +
           '</g>')
# bokeh
for (bx, by, br, op) in [(300, 70, 26, .35), (420, 40, 16, .3), (60, 260, 20, .25), (1050, 60, 30, .18), (900, 30, 14, .22), (560, 80, 12, .2)]:
    far.append(f'<circle cx="{bx}" cy="{by}" r="{br}" fill="#F2C46B" opacity="{op}"/>')
scene.append(f'<g filter="url(#blurFar)">{"".join(far)}</g>')
# candle flame + glow (sharp-ish core, big glow)
scene.append(f'<circle cx="170" cy="112" r="70" fill="#FFB347" opacity="0.55" filter="url(#glow)"/>')
scene.append(f'<g filter="url(#blurMid)">{flame(170, 142, 52, outline=False)}</g>')

# ---------- LABEL PANEL ----------
lx, ly, lw, lh = 230, 250, 640, 430
cx, cy = lx + lw/2, ly + lh/2 - 6
lab = []
lab.append(f'<rect x="{lx}" y="{ly}" width="{lw}" height="{lh}" fill="{P["cream"]}" filter="url(#paper)"/>')
lab.append(f'<rect x="{lx}" y="{ly}" width="{lw}" height="{lh}" fill="url(#paperEdge)"/>')
# sunburst (printed in red, clipped to inner frame)
lab.append(f'<clipPath id="inner"><rect x="{lx+40}" y="{ly+40}" width="{lw-80}" height="{lh-80}"/></clipPath>')
rays = ''.join(f'<line x1="{cx}" y1="{cy}" x2="{cx+600*math.cos(a*math.pi/36):.1f}" y2="{cy+600*math.sin(a*math.pi/36):.1f}"/>' for a in range(72))
lab.append(f'<g clip-path="url(#inner)" stroke="{P["brick"]}" stroke-width="5" opacity="0.10">{rays}</g>')
# frames: ink outer, red band (misregistered), ink inner
lab.append(f'<rect x="{lx+14}" y="{ly+14}" width="{lw-28}" height="{lh-28}" fill="none" stroke="{P["ink"]}" stroke-width="1.6"/>')
lab.append(f'<rect x="{lx+24+1.4}" y="{ly+24-0.9}" width="{lw-48}" height="{lh-48}" fill="none" stroke="{P["brick"]}" stroke-width="5" opacity="0.92"/>')
lab.append(f'<rect x="{lx+34}" y="{ly+34}" width="{lw-68}" height="{lh-68}" fill="none" stroke="{P["ink"]}" stroke-width="1.1"/>')
lab.append(corners(lx+34, ly+34, lw-68, lh-68, 8, 1.0))
# central oval cartouche
orx, ory = 112, 132
lab.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{orx+14}" ry="{ory+14}" fill="{P["cream"]}" stroke="{P["ink"]}" stroke-width="1.4"/>')
lab.append(f'<ellipse cx="{cx+1.2}" cy="{cy-0.8}" rx="{orx+7}" ry="{ory+7}" fill="none" stroke="{P["brick"]}" stroke-width="3"/>')
lab.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{orx}" ry="{ory}" fill="{P["cream"]}" stroke="{P["ink"]}" stroke-width="1.2"/>')
lab.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{orx-4}" ry="{ory-4}" fill="url(#hatch)" opacity="0.35"/>')
# beads around oval
for k in range(40):
    a = 2*math.pi*k/40
    lab.append(f'<circle cx="{cx+(orx+24)*math.cos(a):.1f}" cy="{cy+(ory+24)*math.sin(a):.1f}" r="1.8" fill="{P["ink"]}"/>')
# emblem: upright matchstick + flame (offset red for misregistration feel)
lab.append(f'<rect x="{cx-7}" y="{cy-30}" width="14" height="118" fill="{P["wood_l"]}" stroke="{P["ink"]}" stroke-width="1.5"/>')
for k in range(5):
    lab.append(f'<line x1="{cx-3+k*1.5}" y1="{cy-20+k*6}" x2="{cx-3+k*1.5}" y2="{cy+60+k*4}" stroke="#a87a48" stroke-width="0.8"/>')
lab.append(f'<ellipse cx="{cx+1}" cy="{cy-40}" rx="15" ry="19" fill="{P["brick"]}" stroke="{P["ink"]}" stroke-width="1.5"/>')
lab.append(flame(cx+1, cy-50, 70))
# blank ribbon banner across lower oval
by = cy + 98
bw = 360
lab.append(f'<path d="M{cx-bw/2-6} {by-12} h-46 l18 22 l-18 22 h56z" fill="#24406a" stroke="{P["ink"]}" stroke-width="1.3"/>')
lab.append(f'<path d="M{cx+bw/2+6} {by-12} h46 l-18 22 l18 22 h-56z" fill="#24406a" stroke="{P["ink"]}" stroke-width="1.3"/>')
lab.append(f'<rect x="{cx-bw/2}" y="{by-20}" width="{bw}" height="44" fill="{P["blue"]}" stroke="{P["ink"]}" stroke-width="1.4"/>')
lab.append(f'<rect x="{cx-bw/2+6}" y="{by-14}" width="{bw-12}" height="32" fill="none" stroke="{P["cream"]}" stroke-width="1" opacity="0.85"/>')
lab.append(f'<path d="M{cx-bw/2+18} {by+2} l5 -4 l5 4 l-5 4z M{cx+bw/2-28} {by+2} l5 -4 l5 4 l-5 4z" fill="{P["cream"]}"/>')
# small side ornaments on label
for sx in (lx+90, lx+lw-90):
    lab.append(f'<g fill="none" stroke="{P["ink"]}" stroke-width="1.2"><circle cx="{sx}" cy="{cy}" r="16"/><circle cx="{sx}" cy="{cy}" r="10" stroke="{P["brick"]}" stroke-width="2.4"/></g>')
    lab.append(f'<path d="M{sx} {cy-34} V{cy-22} M{sx} {cy+22} V{cy+34}" stroke="{P["ink"]}" stroke-width="1.2"/>')
label = f'<g transform="rotate(-1.6 {cx} {cy})"><g filter="url(#shadow)">{"".join(lab)}</g>'
# paper tape on top-right corner + brass pin top-left
label += (f'<g transform="translate({lx+lw-18} {ly+10}) rotate(38)" opacity="0.78">'
          f'<path d="M-60 -17 L60 -17 l-3 5 l4 5 l-3 6 l3 6 l-4 5 l3 7 L-60 17 l3 -5 l-4 -6 l3 -6 l-3 -5 l4 -6z" fill="#E6D6B4"/>'
          f'<path d="M-60 -17 L60 -17" stroke="#fff" stroke-width="1" opacity="0.5"/></g>')
label += brass_pin(lx+30, ly+30, 10) + '</g>'
scene.append(label)

# ---------- BUTTONS ----------
def button(x, y, w, h, fill, line, deco, ang):
    g = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="{fill}" stroke="{P["ink"]}" stroke-width="2" filter="url(#paper)"/>',
         f'<rect x="{x+6+0.8}" y="{y+6-0.6}" width="{w-12}" height="{h-12}" rx="1.5" fill="none" stroke="{line}" stroke-width="1.2"/>']
    for (px, sx) in ((x+6, 1), (x+w-6, -1)):
        for (py, sy) in ((y+6, 1), (y+h-6, -1)):
            g.append(f'<path d="M{px} {py+sy*12} V{py} H{px+sx*12}" fill="none" stroke="{line}" stroke-width="2.2"/>')
    for px in (x+24, x+w-24):
        g.append(f'<path d="M{px-6} {y+h/2} l6 -5 l6 5 l-6 5z" fill="{deco}"/>')
    g.append(f'<path d="M{x+40} {y+h/2} H{x+64} M{x+w-40} {y+h/2} H{x+w-64}" stroke="{deco}" stroke-width="1.1"/>')
    return f'<g transform="rotate({ang} {x+w/2} {y+h/2})" filter="url(#shadow)">{"".join(g)}</g>'

scene.append(button(990, 292, 390, 78, P['brick'], P['cream'], P['cream'], 1.2))
scene.append(button(990, 400, 390, 78, P['cream'], P['brick'], P['ink'], -0.8))

# ---------- ICON BADGES ----------
def badge(x, y, inner, ang):
    r = 54
    g = [f'<circle cx="{x}" cy="{y}" r="{r}" fill="{P["cream"]}" stroke="{P["ink"]}" stroke-width="1.8" filter="url(#paper)"/>',
         f'<circle cx="{x+0.9}" cy="{y-0.6}" r="{r-7}" fill="none" stroke="{P["brick"]}" stroke-width="2.4"/>',
         f'<circle cx="{x}" cy="{y}" r="{r-11}" fill="none" stroke="{P["ink"]}" stroke-width="0.9"/>']
    for k in range(24):
        a = 2*math.pi*k/24
        g.append(f'<circle cx="{x+(r-3.5)*math.cos(a):.1f}" cy="{y+(r-3.5)*math.sin(a):.1f}" r="1.1" fill="{P["ink"]}"/>')
    return f'<g transform="rotate({ang} {x} {y})" filter="url(#shadow)">{"".join(g)}{inner}</g>'

bx = [1050, 1185, 1320]; byy = 600
scene.append(badge(bx[0], byy, flame(bx[0], byy+30, 64), -4))
gear = (f'<path d="{gear_path(bx[1], byy, 31, 24, 9, 9)}" fill="{P["wood_d"]}" stroke="{P["ink"]}" stroke-width="1.5" fill-rule="evenodd"/>'
        f'<circle cx="{bx[1]}" cy="{byy}" r="17" fill="none" stroke="{P["ink"]}" stroke-width="1"/>'
        f'<path d="{gear_path(bx[1], byy, 31, 24, 9, 9)}" fill="none" stroke="#C49A6C" stroke-width="1" transform="translate(-0.8 -0.8)" opacity="0.6"/>')
scene.append(badge(bx[1], byy, gear, 3))
gm = matchstick(bx[2]-26, byy+28, bx[2]+16, byy-16, 9, 'url(#gold)', 'url(#gold)', hl='#FFF2C2')
scene.append(badge(bx[2], byy, gm + f'<path d="M{bx[2]+30} {byy-34} l2 6 l6 2 l-6 2 l-2 6 l-2 -6 l-6 -2 l6 -2z" fill="{P["candle"]}" stroke="{P["ink"]}" stroke-width="0.8"/>', -2))

# ---------- STRIKER SLIDER ----------
sx0, sx1, sy, sh = 300, 940, 822, 26
hx = sx0 + (sx1-sx0)*0.62
sl = [f'<rect x="{sx0}" y="{sy-sh/2}" width="{sx1-sx0}" height="{sh}" rx="4" fill="#5E3E27" stroke="{P["ink"]}" stroke-width="1.8" filter="url(#sand)"/>',
      f'<rect x="{sx0+8}" y="{sy-3}" width="{hx-sx0-8}" height="6" rx="1" fill="{P["brick"]}" opacity="0.9"/>',
      f'<rect x="{sx0+8}" y="{sy-3}" width="{hx-sx0-8}" height="6" rx="1" fill="none" stroke="{P["ink"]}" stroke-width="0.8" opacity="0.7"/>']
for t in range(1, 10):
    tx = sx0 + (sx1-sx0)*t/10
    sl.append(f'<line x1="{tx}" y1="{sy+sh/2+6}" x2="{tx}" y2="{sy+sh/2+(12 if t==5 else 9)}" stroke="{P["cream"]}" stroke-width="1.2" opacity="0.55"/>')
scene.append(f'<g filter="url(#shadow)">{"".join(sl)}</g>')
scene.append(brass_pin(sx0-22, sy, 9) + brass_pin(sx1+22, sy, 9))
# handle: an upright matchstick
scene.append(f'<g filter="url(#shadow)"><rect x="{hx-7}" y="{sy-18}" width="14" height="62" rx="1.5" fill="{P["wood_l"]}" stroke="{P["ink"]}" stroke-width="1.6"/>'
             f'<line x1="{hx-2}" y1="{sy-12}" x2="{hx-2}" y2="{sy+38}" stroke="#a87a48" stroke-width="0.9"/>'
             f'<ellipse cx="{hx}" cy="{sy-26}" rx="15" ry="18" fill="{P["red"]}" stroke="{P["ink"]}" stroke-width="1.6"/>'
             f'<ellipse cx="{hx-5}" cy="{sy-33}" rx="5" ry="3" fill="#fff" opacity="0.3"/></g>')

# ---------- LOOSE BRASS PIN ----------
scene.append(f'<g filter="url(#shadowS)"><line x1="1205" y1="828" x2="1244" y2="842" stroke="#8C8C8C" stroke-width="2.2" stroke-linecap="round"/></g>')
scene.append(brass_pin(1196, 824, 15))

# a crisp matchstick resting on the table (mid ground)
scene.append(f'<g filter="url(#shadow)">{matchstick(1010, 930, 1300, 885, 11, P["wood_l"], P["brick"])}</g>')

# ---------- LIGHT, VIGNETTE, GRAIN ----------
scene.append(f'<rect width="{W}" height="{H}" fill="url(#candleLight)" opacity="0.6" style="mix-blend-mode:soft-light"/>')
scene.append(f'<rect width="{W}" height="{H}" fill="url(#candleLight)" opacity="0.28" style="mix-blend-mode:screen"/>')
scene.append(f'<rect width="{W}" height="{H}" fill="url(#vignette)"/>')
# ---------- FOREGROUND MATCHSTICKS (out of focus) ----------
fg = matchstick(1200, 1060, 1450, 960, 24, P['wood_l'], P['brick'], ink=False) + \
     matchstick(-60, 1010, 230, 930, 20, P['wood_l'], P['brick'], ink=False)
scene.append(f'<g style="filter:brightness(0.55)"><g filter="url(#blurNear)" opacity="0.85">{fg}</g></g>')
scene.append(f'<rect width="{W}" height="{H}" filter="url(#grain)" opacity="0.10" style="mix-blend-mode:overlay"/>')

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><defs>{"".join(defs)}</defs>
<rect width="{W}" height="{H}" fill="#2a1609"/>{"".join(scene)}</svg>'''
html = f'<!doctype html><html><head><meta charset="utf-8"><style>html,body{{margin:0;background:#2a1609}}svg{{display:block}}</style></head><body>{svg}</body></html>'
open(sys.argv[1], 'w').write(html)
