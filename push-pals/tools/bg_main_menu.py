"""Push Pals — MAIN MENU BACKGROUND: side view of a kitchen table at night, candle on the right (1536x1024, no text/UI)."""
import math, random, sys
from shared import P, scene_defs, finish, page, flame

W, H = 1536, 1024
random.seed(3)
HORIZON, K = 420, 660            # y = HORIZON + K / z  (simple pinhole perspective)
Z_BACK, PLANK = 4.0, 0.45
BACK_Y = HORIZON + K / Z_BACK   # back edge of the table (585)
CX, CY = 1296, 652              # candle base on the table

def py(z): return HORIZON + K / z

defs = [scene_defs(CX, 470, 1350)]
# ---- table planks with per-plank perspective-correct grain ----
planks, z = [], Z_BACK
while py(z) < H:
    y0, y1 = py(z), min(py(z - PLANK) if z - PLANK > 0.3 else H + 50, H + 50)
    planks.append((y0, y1)); z -= PLANK
for i, (y0, y1) in enumerate(planks):
    h = y1 - y0
    defs.append(f'''<filter id="pw{i}" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="{0.0028 + 0.0006*(len(planks)-i):.4f} {min(9/h, 0.5):.4f}" numOctaves="5" seed="{17+i*13}"/>
  <feColorMatrix type="matrix" values="0.30 0 0 0 0.045  0.165 0 0 0 0.016  0.07 0 0 0 0.004  0 0 0 0 1"/>
</filter>''')
defs.append(f'''
<linearGradient id="wall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#120a05"/><stop offset="1" stop-color="#2a180c"/></linearGradient>
<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0c1426"/><stop offset="0.7" stop-color="#1d2e4f"/><stop offset="1" stop-color="#2b3f63"/></linearGradient>
<radialGradient id="moon" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#E9EEF5" stop-opacity="0.9"/><stop offset="0.25" stop-color="#C8D3E6" stop-opacity="0.5"/><stop offset="1" stop-color="#8FA3C6" stop-opacity="0"/></radialGradient>
<radialGradient id="pool" cx="{CX}" cy="{CY+10}" r="760" gradientUnits="userSpaceOnUse" gradientTransform="translate({CX} {CY+10}) scale(1 0.42) translate({-CX} {-(CY+10)})">
  <stop offset="0" stop-color="#FFC768" stop-opacity="0.7"/><stop offset="0.4" stop-color="#E89A45" stop-opacity="0.28"/><stop offset="1" stop-color="#E89A45" stop-opacity="0"/>
</radialGradient>
<linearGradient id="waxL" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#7d6a50"/><stop offset="0.55" stop-color="#E6D5B2"/><stop offset="0.85" stop-color="#F7EBD0"/><stop offset="1" stop-color="#cdb791"/></linearGradient>
<linearGradient id="moonSpill" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#6F8DC0" stop-opacity="0.22"/><stop offset="0.45" stop-color="#6F8DC0" stop-opacity="0"/></linearGradient>
<linearGradient id="dofT" x1="0" y1="{BACK_Y}" x2="0" y2="{BACK_Y+180}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
<mask id="dofMask"><rect width="{W}" height="{H}" fill="url(#dofT)"/></mask>
<linearGradient id="spoon" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#E8E2D6"/><stop offset="0.5" stop-color="#9C968C"/><stop offset="1" stop-color="#4c4842"/></linearGradient>
<filter id="bgBlur" x="-5%" y="-5%" width="110%" height="110%"><feGaussianBlur stdDeviation="9"/></filter>
<filter id="softBlur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="1.2"/></filter>
<filter id="nearBlur" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3.2"/></filter>
<filter id="castBlur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="10"/></filter>
<filter id="plaster" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="0.02" numOctaves="4" seed="8"/>
  <feColorMatrix type="matrix" values="0 0 0 0 0.1  0 0 0 0 0.06  0 0 0 0 0.03  0.9 0 0 0 -0.35"/>
</filter>''')

S = []
# ================= FAR BACKGROUND (blurred, dark) =================
bg = [f'<rect width="{W}" height="{BACK_Y+20}" fill="url(#wall)"/>',
      f'<rect width="{W}" height="{BACK_Y+20}" filter="url(#plaster)"/>']
# window with night sky
wx, wy, ww, wh = 200, 70, 420, 400
bg.append(f'<rect x="{wx}" y="{wy}" width="{ww}" height="{wh}" fill="url(#sky)"/>')
bg.append(f'<circle cx="{wx+300}" cy="{wy+105}" r="120" fill="url(#moon)"/>')
for _ in range(26):
    bg.append(f'<circle cx="{wx+random.uniform(10, ww-10):.0f}" cy="{wy+random.uniform(10, wh*0.6):.0f}" r="{random.uniform(1.2, 2.6):.1f}" fill="#DDE6F5" opacity="{random.uniform(.4, .9):.2f}"/>')
# distant rooftops / trees silhouettes
bg.append(f'<path d="M{wx} {wy+wh} V{wy+300} l60 -40 l50 30 h40 v-60 h30 v50 l70 -50 l80 60 l40 -20 l50 30 V{wy+wh}Z" fill="#0a1020"/>')
bg.append(f'<circle cx="{wx+120}" cy="{wy+318}" r="4" fill="#F2C46B" opacity="0.8"/><circle cx="{wx+300}" cy="{wy+340}" r="3" fill="#F2C46B" opacity="0.6"/>')
# window frame + mullions + sill
fc = '#1e1208'
bg.append(f'<rect x="{wx-18}" y="{wy-18}" width="{ww+36}" height="{wh+36}" fill="none" stroke="{fc}" stroke-width="36"/>')
bg.append(f'<rect x="{wx+ww/2-7}" y="{wy}" width="14" height="{wh}" fill="{fc}"/><rect x="{wx}" y="{wy+wh/2-7}" width="{ww}" height="14" fill="{fc}"/>')
bg.append(f'<rect x="{wx-40}" y="{wy+wh+14}" width="{ww+80}" height="18" fill="#2b1a0e"/>')
# a pot plant on the sill, a small jug
bg.append(f'<path d="M{wx+40} {wy+wh+14} l8 -46 h44 l8 46z" fill="#5a2e1c"/><ellipse cx="{wx+70}" cy="{wy+wh-48}" rx="54" ry="40" fill="#14200f"/>')
bg.append(f'<path d="M{wx+330} {wy+wh+14} q-6 -50 14 -64 h26 q20 14 14 64z" fill="#3c4a5c"/>')
# moonlight falling through the window onto the wall below
bg.append(f'<path d="M{wx} {wy+wh+32} L{wx+ww} {wy+wh+32} L{wx+ww+150} {BACK_Y+20} L{wx-70} {BACK_Y+20}Z" fill="#6F8DC0" opacity="0.07"/>')
# shelves on the right wall with jars, plates, a teapot
for sy in (150, 330):
    bg.append(f'<rect x="780" y="{sy}" width="520" height="16" fill="#3a2414"/><rect x="780" y="{sy+16}" width="520" height="6" fill="#120a05"/>')
    bg.append(f'<path d="M800 {sy+22} l0 30 l26 -30z M1270 {sy+22} l0 30 l-26 -30z" fill="#2a190d"/>')
jars = [(800, 150, 50, 74, '#6a4a2a'), (862, 150, 44, 96, '#4e5a3a'), (918, 150, 58, 62, '#7a5a3a'),
        (1090, 150, 40, 82, '#5a3a2a'), (1144, 150, 52, 70, '#4a4a5a'), (1210, 150, 46, 92, '#6b4a2a'),
        (812, 330, 60, 76, '#5a4630'), (890, 330, 44, 60, '#3e4a5a'), (1180, 330, 54, 88, '#6a4028')]
for (x, sy, w, h, c) in jars:
    bg.append(f'<rect x="{x}" y="{sy-h}" width="{w}" height="{h}" rx="7" fill="{c}"/><rect x="{x+4}" y="{sy-h-10}" width="{w-8}" height="12" rx="3" fill="#2a1a0e"/>')
    bg.append(f'<rect x="{x+w-10}" y="{sy-h+8}" width="5" height="{h-18}" rx="2" fill="#F2C46B" opacity="0.28"/>')
    bg.append(f'<rect x="{x+6}" y="{sy-h*0.6}" width="{w-12}" height="{h*0.3:.0f}" fill="#EFE4CF" opacity="0.18"/>')
for k in range(4):  # standing plates
    bg.append(f'<ellipse cx="{1000+k*22}" cy="{150-58}" rx="12" ry="58" fill="#cfc4ad" opacity="{0.55-k*0.08:.2f}"/>')
bg.append(f'<path d="M960 330 q0 -70 60 -70 q60 0 60 70z" fill="#5a2e24"/><path d="M1078 300 q40 -10 46 -40" stroke="#5a2e24" stroke-width="10" fill="none"/>'
          f'<path d="M962 300 q-30 0 -30 -26 q0 -20 22 -16" stroke="#5a2e24" stroke-width="8" fill="none"/><ellipse cx="1020" cy="258" rx="16" ry="7" fill="#4a241c"/>')
bg.append(f'<rect x="1020" y="300" width="70" height="30" rx="4" fill="#B98A5E" opacity="0.7"/>')  # a matchbox on the shelf
# hanging utensils near the right edge
for k, (hx, L) in enumerate([(1380, 150), (1424, 190), (1466, 130)]):
    bg.append(f'<line x1="{hx}" y1="40" x2="{hx}" y2="{40+L}" stroke="#6a5a48" stroke-width="5"/><ellipse cx="{hx}" cy="{40+L+18}" rx="{14+k*3}" ry="22" fill="#6a5a48"/>')
bg.append(f'<rect x="1340" y="30" width="170" height="10" fill="#3a2414"/>')
# warm light washing the right wall from the candle
bg.append(f'<ellipse cx="{CX}" cy="{CY-260}" rx="520" ry="380" fill="#F2A84A" opacity="0.16"/>')
S.append(f'<g filter="url(#bgBlur)">{"".join(bg)}</g>')

# ================= TABLE =================
tab = []
for i, (y0, y1) in enumerate(planks):
    tab.append(f'<rect x="-10" y="{y0:.1f}" width="{W+20}" height="{y1-y0+1:.1f}" filter="url(#pw{i})"/>')
    tab.append(f'<rect x="-10" y="{y0:.1f}" width="{W+20}" height="{y1-y0+1:.1f}" fill="#000" opacity="{[0, .07, .03, .1][i % 4]}"/>')
    sw = max(1.0, (y1-y0)/40)
    tab.append(f'<line x1="0" y1="{y0:.1f}" x2="{W}" y2="{y0:.1f}" stroke="#0e0602" stroke-width="{sw:.1f}"/>')
    tab.append(f'<line x1="0" y1="{y0+sw:.1f}" x2="{W}" y2="{y0+sw:.1f}" stroke="#a87444" stroke-width="{sw*0.5:.1f}" opacity="0.25"/>')
table_svg = ''.join(tab)
S.append(table_svg)
# back edge: thin top lip of the table catching light
S.append(f'<rect x="0" y="{BACK_Y-6}" width="{W}" height="7" fill="#5a381f"/><line x1="0" y1="{BACK_Y-6}" x2="{W}" y2="{BACK_Y-6}" stroke="#C48A52" stroke-width="1.2" opacity="0.5"/>')
# depth of field on the far part of the table
S.append(f'<g mask="url(#dofMask)"><g filter="url(#bgBlur)">{table_svg}</g></g>')
# cool moon spill on the back-left, warm pool from the candle
S.append(f'<rect x="0" y="{BACK_Y}" width="{W}" height="{H-BACK_Y}" fill="url(#moonSpill)" style="mix-blend-mode:screen"/>')
S.append(f'<rect x="0" y="{BACK_Y}" width="{W}" height="{H-BACK_Y}" fill="url(#pool)" style="mix-blend-mode:screen"/>')

# ================= CANDLE (right, in focus) =================
cw, ch = 58, 250
c = []
# cast shadow of the holder, falling away from the flame (toward the viewer-left)
c.append(f'<ellipse cx="{CX-40}" cy="{CY+20}" rx="110" ry="16" fill="#0a0402" opacity="0.6" filter="url(#castBlur)"/>')
# brass holder: dish + finger loop
c.append(f'<path d="M{CX+70} {CY-6} q38 -6 40 14 q-2 18 -38 12" fill="none" stroke="#7A5420" stroke-width="7"/>')
c.append(f'<ellipse cx="{CX}" cy="{CY+4}" rx="86" ry="18" fill="#4a3014"/>')
c.append(f'<ellipse cx="{CX}" cy="{CY-2}" rx="86" ry="18" fill="url(#brassV)"/>')
c.append(f'<ellipse cx="{CX}" cy="{CY-5}" rx="64" ry="12" fill="#8A6226"/>')
c.append(f'<ellipse cx="{CX}" cy="{CY-8}" rx="30" ry="7" fill="url(#brassV)"/>')
c.append(f'<path d="M{CX-58} {CY-10} q30 -9 70 -8" stroke="#FFE7A8" stroke-width="2" fill="none" opacity="0.55"/>')
# wax body with drips
top = CY - 8 - ch
c.append(f'<rect x="{CX-cw/2}" y="{top}" width="{cw}" height="{ch}" fill="url(#waxL)"/>')
c.append(f'<path d="M{CX-cw/2} {top+4} q6 26 2 54 q-2 10 4 12 q6 -2 4 -14 q-2 -28 6 -50z" fill="#F4E6C8" opacity="0.85"/>')
c.append(f'<path d="M{CX+8} {top+4} q4 40 0 70 q2 8 6 0 q-1 -40 4 -70z" fill="#F9EFD8" opacity="0.9"/>')
c.append(f'<ellipse cx="{CX}" cy="{top+2}" rx="{cw/2}" ry="7" fill="#F8EDD3"/>')
c.append(f'<ellipse cx="{CX}" cy="{top+3}" rx="{cw/2-6}" ry="4" fill="#FFD98A" opacity="0.8"/>')
c.append(f'<path d="M{CX} {top+2} q-1 -8 1 -14" stroke="#1a0d05" stroke-width="2.5" fill="none"/>')
S.append(f'<g filter="url(#softBlur)">{"".join(c)}</g>')
# flame and glow
S.append(f'<circle cx="{CX}" cy="{top-40}" r="140" fill="#FFB347" opacity="0.35" filter="url(#glowWide)"/>')
S.append(f'<circle cx="{CX}" cy="{top-36}" r="46" fill="#FFD27A" opacity="0.6" filter="url(#glow)"/>')
S.append(f'<g filter="url(#softBlur)">{flame(CX+1, top-4, 58, outline=False)}</g>')
S.append(f'<ellipse cx="{CX+1}" cy="{top-18}" rx="5" ry="10" fill="#FFF6DA" opacity="0.9" filter="url(#softBlur)"/>')

# ================= EDGE DETAILS =================
def flat_match(x, y, L, ang, w, head, burnt=False, sq=0.62):
    """Matchstick lying on the table, squashed vertically for perspective."""
    hc = '#1c1410' if burnt else head
    stick_end = f'<rect x="{L-18}" y="{-w/2}" width="18" height="{w}" fill="#3a2414"/>' if burnt else ''
    return (f'<g transform="translate({x} {y}) scale(1 {sq}) rotate({ang})">'
            f'<rect x="4" y="{-w/2+5}" width="{L}" height="{w}" fill="#0a0402" opacity="0.45" filter="url(#softBlur)"/>'
            f'<rect x="0" y="{-w/2}" width="{L}" height="{w}" rx="1.5" fill="{P["wood_l"]}"/>{stick_end}'
            f'<rect x="0" y="{-w/2}" width="{L}" height="{w*0.3}" fill="#F6E3BE" opacity="0.6"/>'
            f'<ellipse cx="{L+w*0.25}" cy="0" rx="{w*1.05}" ry="{w*0.85}" fill="{hc}"/>'
            f'<ellipse cx="{L+w*0.1}" cy="{-w*0.35}" rx="{w*0.4}" ry="{w*0.2}" fill="#fff" opacity="0.22"/></g>')
# loose matchsticks bottom-left (closer than the focus plane: slightly blurred)
near = (flat_match(40, 930, 230, -12, 15, P['brick']) + flat_match(150, 985, 240, 8, 15, P['brick']) +
        flat_match(330, 905, 200, -38, 14, P['brick'], burnt=True))
S.append(f'<g filter="url(#nearBlur)">{near}</g>')
# two small matchsticks further back on the left (in focus)
S.append(flat_match(150, 690, 92, 14, 6, P['brick'], sq=0.45) + flat_match(240, 700, 86, -6, 6, P['brick'], burnt=True, sq=0.45))
# spoon at the right front edge
sp = (f'<g transform="translate(1290 965) scale(1 0.6) rotate(-24)">'
      f'<ellipse cx="6" cy="12" rx="62" ry="40" fill="#0a0402" opacity="0.45" filter="url(#softBlur)"/>'
      f'<rect x="40" y="3" width="320" height="15" rx="7" fill="#0a0402" opacity="0.4" filter="url(#softBlur)"/>'
      f'<ellipse cx="0" cy="0" rx="60" ry="38" fill="url(#spoon)"/>'
      f'<ellipse cx="4" cy="4" rx="48" ry="28" fill="#6c665d"/>'
      f'<ellipse cx="-10" cy="-8" rx="22" ry="9" fill="#FFF3D6" opacity="0.7"/>'
      f'<path d="M56 -6 C90 -10 120 -6 360 -10 l2 14 C120 10 90 12 56 8z" fill="url(#spoon)"/>'
      f'<path d="M120 -6 L350 -9" stroke="#FFF3D6" stroke-width="2" opacity="0.6"/></g>')
S.append(f'<g filter="url(#nearBlur)">{sp}</g>')
# crumbs — only near the edges and around the candle
crumbs = []
for (x0, x1, y0, y1, n, s) in [(30, 420, 760, 1000, 22, 1.0), (1080, 1500, 700, 840, 14, 0.8), (1150, 1510, 880, 1010, 10, 1.2), (60, 300, 640, 700, 8, 0.6)]:
    for _ in range(n):
        x, y = random.uniform(x0, x1), random.uniform(y0, y1)
        r = random.uniform(1.4, 3.6) * s * (0.6 + 0.6*(y-BACK_Y)/(H-BACK_Y))
        col = random.choice(['#C99A62', '#B07E48', '#E0BC86', '#8E6236'])
        crumbs.append(f'<ellipse cx="{x:.0f}" cy="{y+r*0.4:.0f}" rx="{r*1.1:.1f}" ry="{r*0.5:.1f}" fill="#0a0402" opacity="0.5"/>'
                      f'<ellipse cx="{x:.0f}" cy="{y:.0f}" rx="{r:.1f}" ry="{r*0.7:.1f}" fill="{col}"/>')
S.append(''.join(crumbs))

# ================= LIGHT, VIGNETTE, GRAIN =================
S.append(f'<rect width="{W}" height="{H}" fill="#0b0503" opacity="0.18" style="mix-blend-mode:multiply"/>')
S.append(finish(W, H).replace('url(#vignette)', 'url(#vigR)'))
defs.append('<radialGradient id="vigR" cx="0.6" cy="0.55" r="0.82"><stop offset="0.3" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#050201" stop-opacity="0.9"/></radialGradient>')

svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><defs>{"".join(defs)}</defs><rect width="{W}" height="{H}" fill="#120a05"/>{"".join(S)}</svg>'
open(sys.argv[1], 'w').write(page(svg, '#120a05', fonts=False))
