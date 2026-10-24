"""Shared palette, filters and SVG helpers for Push Pals UI art."""
import math

P = dict(
    cream="#EFE4CF", brick="#B8443A", ink="#2B1A10", kraft="#B98A5E",
    wood_l="#D9B380", wood_d="#6E4A2C", blue="#2F5487", candle="#F2C46B",
    red="#D93A2B", green="#2BA864", pblue="#2B6FD9", purple="#7B5BE0",
    flame="#FF8A00", flame_y="#FFD34D",
)

def filters():
    return f'''
<filter id="paper" x="-5%" y="-5%" width="110%" height="110%">
  <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="3" seed="4" result="n"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.17  0 0 0 0 0.10  0 0 0 0 0.06  0.9 0 0 0 -0.36" result="fine"/>
  <feTurbulence type="fractalNoise" baseFrequency="0.012" numOctaves="3" seed="9" result="m"/>
  <feColorMatrix in="m" type="matrix" values="0 0 0 0 0.50  0 0 0 0 0.34  0 0 0 0 0.15  0.9 0 0 0 -0.44" result="stain"/>
  <feMerge result="tex"><feMergeNode in="stain"/><feMergeNode in="fine"/></feMerge>
  <feComposite in="tex" in2="SourceGraphic" operator="in" result="tex2"/>
  <feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="tex2"/></feMerge>
</filter>
<filter id="sand" x="-5%" y="-20%" width="110%" height="140%">
  <feTurbulence type="fractalNoise" baseFrequency="1.6" numOctaves="2" seed="2" result="n"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.10  0 0 0 0 0.06  0 0 0 0 0.03  2.2 0 0 0 -0.95" result="dk"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.80  0 0 0 0 0.62  0 0 0 0 0.45  0 2.4 0 0 -1.25" result="lt"/>
  <feMerge result="t"><feMergeNode in="dk"/><feMergeNode in="lt"/></feMerge>
  <feComposite in="t" in2="SourceGraphic" operator="in" result="t2"/>
  <feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="t2"/></feMerge>
</filter>
<filter id="shadow" x="-30%" y="-30%" width="160%" height="170%">
  <feDropShadow dx="7" dy="10" stdDeviation="7" flood-color="#120804" flood-opacity="0.55"/>
</filter>
<filter id="shadowS" x="-40%" y="-40%" width="180%" height="190%">
  <feDropShadow dx="3" dy="5" stdDeviation="3.5" flood-color="#120804" flood-opacity="0.55"/>
</filter>
'''

def corner(x, y, sx, sy, s=1.0, col=None, accent=None):
    col = col or P['ink']; accent = accent or P['brick']
    return f'''<g transform="translate({x} {y}) scale({sx*s} {sy*s})" fill="none" stroke="{col}" stroke-width="{1.3/s:.2f}" stroke-linecap="round">
  <path d="M0 38 V0 H38"/>
  <path d="M7 26 V7 H26"/>
  <path d="M7 7 C17 7 21 11 21 17 C21 22 16 23 14 20 C12 17 15 15 16.5 16.5"/>
  <circle cx="0" cy="0" r="3.2" fill="{accent}" stroke="none"/>
  <path d="M44 0 l4 -3 l4 3 l-4 3z M0 44 l3 4 l-3 4 l-3 -4z" fill="{col}" stroke="none"/>
</g>'''

def corners(x, y, w, h, inset, s=1.0, col=None, accent=None):
    return ''.join([
        corner(x+inset, y+inset, 1, 1, s, col, accent), corner(x+w-inset, y+inset, -1, 1, s, col, accent),
        corner(x+inset, y+h-inset, 1, -1, s, col, accent), corner(x+w-inset, y+h-inset, -1, -1, s, col, accent)])

def gear_path(cx, cy, r_out, r_in, teeth, r_hole):
    pts = []
    n = teeth * 4
    for i in range(n):
        a = 2*math.pi*i/n - math.pi/2
        r = r_out if (i % 4) in (1, 2) else r_in
        pts.append((cx + r*math.cos(a), cy + r*math.sin(a)))
    d = 'M' + ' L'.join(f'{px:.2f} {py:.2f}' for px, py in pts) + 'Z'
    d += f' M{cx+r_hole} {cy} A{r_hole} {r_hole} 0 1 0 {cx-r_hole} {cy} A{r_hole} {r_hole} 0 1 0 {cx+r_hole} {cy}Z'
    return d

def flame(cx, base_y, h, outline=True):
    w = h*0.62
    t = base_y - h
    outer = (f'M{cx} {t} C{cx+w*0.15} {t+h*0.22} {cx+w*0.62} {t+h*0.40} {cx+w*0.5} {t+h*0.70} '
             f'C{cx+w*0.42} {t+h*0.92} {cx+w*0.18} {base_y} {cx} {base_y} '
             f'C{cx-w*0.22} {base_y} {cx-w*0.48} {t+h*0.90} {cx-w*0.5} {t+h*0.68} '
             f'C{cx-w*0.52} {t+h*0.48} {cx-w*0.22} {t+h*0.36} {cx-w*0.10} {t+h*0.12} '
             f'C{cx-w*0.02} {t+h*0.26} {cx+w*0.02} {t+h*0.30} {cx} {t}Z')
    hi = h*0.55; wi = hi*0.6; ti = base_y - hi
    inner = (f'M{cx+w*0.03} {ti} C{cx+wi*0.45} {ti+hi*0.35} {cx+wi*0.55} {ti+hi*0.65} {cx+wi*0.35} {ti+hi*0.85} '
             f'C{cx+wi*0.2} {base_y-1} {cx-wi*0.2} {base_y-1} {cx-wi*0.38} {ti+hi*0.82} '
             f'C{cx-wi*0.5} {ti+hi*0.6} {cx-wi*0.2} {ti+hi*0.35} {cx+w*0.03} {ti}Z')
    sw = 'stroke="#2B1A10" stroke-width="1.6" stroke-linejoin="round"' if outline else ''
    return f'<path d="{outer}" fill="{P["flame"]}" {sw}/><path d="{inner}" fill="{P["flame_y"]}"/>'

def matchstick(x1, y1, x2, y2, w, stick, head, ink=True, hl=None):
    ang = math.degrees(math.atan2(y2-y1, x2-x1)); L = math.hypot(x2-x1, y2-y1)
    sw = 'stroke="#2B1A10" stroke-width="1.5"' if ink else ''
    hl_el = f'<rect x="2" y="{-w/2+2}" width="{L-w}" height="{w*0.22}" fill="{hl}" opacity="0.7"/>' if hl else ''
    return f'''<g transform="translate({x1} {y1}) rotate({ang:.2f})">
  <rect x="0" y="{-w/2}" width="{L}" height="{w}" rx="1.5" fill="{stick}" {sw}/>{hl_el}
  <ellipse cx="{L+w*0.2}" cy="0" rx="{w*1.05}" ry="{w*0.82}" fill="{head}" {sw}/>
  <ellipse cx="{L}" cy="{-w*0.3}" rx="{w*0.35}" ry="{w*0.18}" fill="#fff" opacity="0.25"/>
</g>'''


# ---------- scene helpers (backgrounds / mockups) ----------
def scene_defs(light_x=170, light_y=120, light_r=1250):
    wood = ''.join(f'''<filter id="wood{i}" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="0.0035 0.09" numOctaves="5" seed="{s}"/>
  <feColorMatrix type="matrix" values="0.27 0 0 0 0.040  0.14 0 0 0 0.012  0.06 0 0 0 0.002  0 0 0 0 1"/>
</filter>''' for i, s in enumerate([11, 23, 37, 51, 64]))
    return filters() + wood + f'''
<filter id="grain" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="1.1" numOctaves="2" seed="5"/><feColorMatrix type="saturate" values="0"/>
</filter>
<filter id="blurFar"><feGaussianBlur stdDeviation="7"/></filter>
<filter id="blurMid"><feGaussianBlur stdDeviation="3.5"/></filter>
<filter id="glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="18"/></filter>
<filter id="glowWide" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="34"/></filter>
<radialGradient id="candleLight" cx="{light_x}" cy="{light_y}" r="{light_r}" gradientUnits="userSpaceOnUse">
  <stop offset="0" stop-color="#F2C46B" stop-opacity="0.75"/>
  <stop offset="0.35" stop-color="#E0A04A" stop-opacity="0.22"/>
  <stop offset="1" stop-color="#E0A04A" stop-opacity="0"/>
</radialGradient>
<radialGradient id="vignette" cx="0.45" cy="0.45" r="0.8">
  <stop offset="0.35" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#070301" stop-opacity="0.88"/>
</radialGradient>
<radialGradient id="brass" cx="0.35" cy="0.3" r="0.8">
  <stop offset="0" stop-color="#F6DC92"/><stop offset="0.45" stop-color="#C99A42"/><stop offset="1" stop-color="#7A5420"/>
</radialGradient>
<linearGradient id="brassV" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#8A6226"/><stop offset="0.3" stop-color="#E9C979"/><stop offset="0.55" stop-color="#C99A42"/><stop offset="1" stop-color="#6E4A1C"/>
</linearGradient>
<linearGradient id="tin" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#6F6A62"/><stop offset="0.28" stop-color="#D8D2C4"/><stop offset="0.5" stop-color="#A9A296"/><stop offset="1" stop-color="#57524B"/>
</linearGradient>
<pattern id="hatch" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(35)">
  <line x1="0" y1="0" x2="0" y2="5" stroke="#2F5487" stroke-width="0.9" opacity="0.55"/>
</pattern>'''

def table(W, H, planks=((-20, 230), (210, 250), (460, 240), (700, 230), (930, 140))):
    out = []
    for i, (y, h) in enumerate(planks):
        out.append(f'<rect x="0" y="{y}" width="{W}" height="{h}" filter="url(#wood{i % 5})"/>')
        out.append(f'<rect x="0" y="{y}" width="{W}" height="{h}" fill="#000" opacity="{0.06*(i%3)}"/>')
        out.append(f'<line x1="0" y1="{y+h-1}" x2="{W}" y2="{y+h-1}" stroke="#120803" stroke-width="3"/>')
        out.append(f'<line x1="0" y1="{y+h+1.5}" x2="{W}" y2="{y+h+1.5}" stroke="#9a6a40" stroke-width="1" opacity="0.35"/>')
    return ''.join(out)

def finish(W, H):
    """Candle light, vignette and film grain over the whole scene."""
    return (f'<rect width="{W}" height="{H}" fill="url(#candleLight)" opacity="0.6" style="mix-blend-mode:soft-light"/>'
            f'<rect width="{W}" height="{H}" fill="url(#candleLight)" opacity="0.28" style="mix-blend-mode:screen"/>'
            f'<rect width="{W}" height="{H}" fill="url(#vignette)"/>'
            f'<rect width="{W}" height="{H}" filter="url(#grain)" opacity="0.10" style="mix-blend-mode:overlay"/>')

def page(svg, bg='transparent', fonts=True):
    import base64, os, re
    d = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts')
    css = open(os.path.join(d, 'fonts.css')).read() if fonts else ''
    css = re.sub(r"url\('fonts/([^']+)'\)", lambda m: "url(data:font/woff2;base64,%s)" % base64.b64encode(open(os.path.join(d, m.group(1)), 'rb').read()).decode(), css)
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}html,body{{margin:0;background:{bg}}}svg{{display:block}}</style></head>'
            f'<body>{svg}</body></html>')
