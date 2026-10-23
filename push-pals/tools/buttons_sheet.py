"""Push Pals — BUTTONS sheet (1536x1024, 4x4, transparent, 9-slice friendly)."""
import json, sys
from shared import P, flame

W, H = 1536, 1024
COLS, ROWS, CW, CH, GAP, M = 4, 4, 320, 192, 64, 32   # 4*320+3*64+2*32 = 1536 ; 4*192+3*64+2*32 = 1024
BW, BH = 300, 60                                          # button: height = width / 5
INK = P['ink']

def cell(c, r):
    return M + c*(CW+GAP), M + r*(CH+GAP)

defs = '''
<filter id="edgeGrain" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="3" seed="4" result="n"/>
  <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.17  0 0 0 0 0.10  0 0 0 0 0.06  1.0 0 0 0 -0.40" result="g"/>
  <feComposite in="g" in2="SourceGraphic" operator="in"/>
</filter>
<radialGradient id="brass" cx="0.35" cy="0.3" r="0.8">
  <stop offset="0" stop-color="#F6DC92"/><stop offset="0.45" stop-color="#C99A42"/><stop offset="1" stop-color="#7A5420"/>
</radialGradient>
<linearGradient id="hlFadeX" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="0.15" stop-color="#fff"/>
  <stop offset="0.85" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
</linearGradient>
<linearGradient id="hlFadeY" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#F2C46B" stop-opacity="0"/><stop offset="0.25" stop-color="#F2C46B" stop-opacity="0.42"/>
  <stop offset="0.75" stop-color="#F2C46B" stop-opacity="0.42"/><stop offset="1" stop-color="#F2C46B" stop-opacity="0"/>
</linearGradient>
'''
masks = []

def ring(x, y, w, h, band, rx=3):
    """Even-odd path covering only the border band (texture stays out of the stretchable center)."""
    i = band
    return (f'M{x+rx} {y} H{x+w-rx} Q{x+w} {y} {x+w} {y+rx} V{y+h-rx} Q{x+w} {y+h} {x+w-rx} {y+h} '
            f'H{x+rx} Q{x} {y+h} {x} {y+h-rx} V{y+rx} Q{x} {y} {x+rx} {y}Z '
            f'M{x+i} {y+i} V{y+h-i} H{x+w-i} V{y+i}Z')

def tiny_corners(x, y, w, h, inset, col, dot, L=9):
    g = []
    for (px, sx) in ((x+inset, 1), (x+w-inset, -1)):
        for (py, sy) in ((y+inset, 1), (y+h-inset, -1)):
            g.append(f'<path d="M{px} {py+sy*L} V{py} H{px+sx*L}" fill="none" stroke="{col}" stroke-width="2" stroke-linecap="square"/>')
            g.append(f'<path d="M{px+sx*4} {py+sy*4} m0 -2.2 l2.2 2.2 l-2.2 2.2 l-2.2 -2.2z" fill="{dot}"/>')
    return ''.join(g)

def label_button(c, r, fill, line, orn, dot, outline=INK, grain=0.55, mis=(0.8, -0.6)):
    cx, cy = cell(c, r); x, y = cx+(CW-BW)/2, cy+(CH-BH)/2
    g = [f'<rect x="{x}" y="{y}" width="{BW}" height="{BH}" rx="3" fill="{fill}"/>',
         f'<path d="{ring(x, y, BW, BH, 15)}" fill-rule="evenodd" fill="#000" filter="url(#edgeGrain)" opacity="{grain}"/>',
         f'<rect x="{x+6+mis[0]}" y="{y+6+mis[1]}" width="{BW-12}" height="{BH-12}" rx="1.5" fill="none" stroke="{line}" stroke-width="1.3"/>',
         tiny_corners(x+6+mis[0], y+6+mis[1], BW-12, BH-12, 4, orn, dot),
         f'<rect x="{x+1}" y="{y+1}" width="{BW-2}" height="{BH-2}" rx="2.5" fill="none" stroke="{outline}" stroke-width="2"/>']
    return ''.join(g)

items = []
# Row 1 — primary
items.append(label_button(0, 0, '#B8443A', P['cream'], P['cream'], P['cream']))
items.append(label_button(1, 0, '#C85A40', '#F6EAD2', '#F6EAD2', P['candle']))
items.append(label_button(2, 0, '#97352D', '#D9C9AE', '#D9C9AE', '#D9C9AE', mis=(0.8, 0.4)))
items.append(label_button(3, 0, '#8C7E70', '#C9BEAC', '#C9BEAC', '#C9BEAC', outline='#5A4C40', grain=0.3))
# Row 2 — secondary
items.append(label_button(0, 1, P['cream'], P['brick'], P['brick'], INK))
items.append(label_button(1, 1, '#F6E6C4', '#C24E3C', '#C24E3C', P['brick']))
items.append(label_button(2, 1, '#DDCDAF', '#9C3A31', '#9C3A31', INK, mis=(0.8, 0.4)))
items.append(label_button(3, 1, '#D3CCC0', '#A99D8F', '#A99D8F', '#A99D8F', outline='#7E7062', grain=0.25))

# Row 3.1 — selected-menu-item highlight strip
cx, cy = cell(0, 2); x, y, hw, hh = cx+(CW-BW)/2, cy+(CH-BH)/2, BW, BH
masks.append(f'<mask id="hlMask" maskUnits="userSpaceOnUse" x="{x}" y="{y}" width="{hw}" height="{hh}">'
             f'<rect x="{x}" y="{y}" width="{hw}" height="{hh}" fill="url(#hlFadeX)"/></mask>')
items.append(f'<g mask="url(#hlMask)"><rect x="{x}" y="{y}" width="{hw}" height="{hh}" fill="url(#hlFadeY)"/>'
             f'<rect x="{x}" y="{y+hh*0.25}" width="{hw}" height="{hh*0.5}" fill="#EFE4CF" opacity="0.18"/>'
             f'<line x1="{x}" y1="{y+7.5}" x2="{x+hw}" y2="{y+7.5}" stroke="{P["brick"]}" stroke-width="1" opacity="0.55"/>'
             f'<line x1="{x}" y1="{y+hh-7.5}" x2="{x+hw}" y2="{y+hh-7.5}" stroke="{P["brick"]}" stroke-width="1" opacity="0.55"/></g>')

# Row 3.2 — matchstick pointer (points right, lit head, tiny flame)
cx, cy = cell(1, 2); L = 150; px0 = cx + (CW - L - 30)/2; py = cy + CH/2 + 14
hx = px0 + L + 8
items.append(f'<g>{flame(hx+3, py-2, 44)}'
             f'<rect x="{px0}" y="{py-6}" width="{L}" height="12" rx="1.5" fill="{P["wood_l"]}" stroke="{INK}" stroke-width="1.6"/>'
             f'<line x1="{px0+4}" y1="{py-2}" x2="{px0+L-8}" y2="{py-2}" stroke="#F2DDB8" stroke-width="1.3" opacity="0.8"/>'
             f'<line x1="{px0+12}" y1="{py+2.5}" x2="{px0+L-24}" y2="{py+2.5}" stroke="#A87A48" stroke-width="0.8"/>'
             f'<path d="M{px0+L-14} {py-6} H{px0+L-2} M{px0+L-14} {py+6} H{px0+L-2}" stroke="#3A2414" stroke-width="1" opacity="0.5"/>'
             f'<ellipse cx="{hx}" cy="{py}" rx="14" ry="11" fill="{P["brick"]}" stroke="{INK}" stroke-width="1.6"/>'
             f'<path d="M{hx-2} {py-10.5} Q{hx+10} {py-9} {hx+13} {py-1}" fill="none" stroke="{P["flame_y"]}" stroke-width="2" opacity="0.9"/>'
             f'<ellipse cx="{hx-5}" cy="{py-4}" rx="4.5" ry="2.2" fill="#fff" opacity="0.28"/></g>')

# Row 3.3 — gamepad focus frame (four corner brackets, transparent inside)
cx, cy = cell(2, 2); fw, fh = 316, 76; x, y = cx+(CW-fw)/2, cy+(CH-fh)/2
fr = []
for (px, sx) in ((x+3, 1), (x+fw-3, -1)):
    for (py, sy) in ((y+3, 1), (y+fh-3, -1)):
        d = f'M{px} {py+sy*22} V{py} H{px+sx*34}'
        fr.append(f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'
                  f'<path d="{d}" fill="none" stroke="{P["candle"]}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'
                  f'<path d="M{px+sx*42} {py} m-3.5 0 l3.5 -3.5 l3.5 3.5 l-3.5 3.5z" fill="{P["candle"]}" stroke="{INK}" stroke-width="1"/>'
                  f'<path d="M{px} {py+sy*29} m0 -3 l3 3 l-3 3 l-3 -3z" fill="{P["candle"]}" stroke="{INK}" stroke-width="1"/>')
items.append(''.join(fr))

# Row 3.4 — square icon button (dark-wood plaque, two brass pins, blank center)
cx, cy = cell(3, 2); s = 96; x, y = cx+(CW-s)/2, cy+(CH-s)/2
pins = ''.join(f'<circle cx="{px}" cy="{y+11}" r="4.2" fill="url(#brass)" stroke="{INK}" stroke-width="1"/>'
               f'<circle cx="{px-1.3}" cy="{y+9.6}" r="1.2" fill="#FFF4CF" opacity="0.85"/>' for px in (x+11, x+s-11))
items.append(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="4" fill="{P["wood_d"]}"/>'
             f'<path d="{ring(x, y, s, s, 16, 4)}" fill-rule="evenodd" fill="#000" filter="url(#edgeGrain)" opacity="0.7"/>'
             f'<path d="M{x+3} {y+s-6} V{y+5} Q{x+3} {y+3} {x+5} {y+3} H{x+s-6}" fill="none" stroke="#9A6E46" stroke-width="1.2" opacity="0.8"/>'
             f'<rect x="{x+7}" y="{y+19}" width="{s-14}" height="{s-26}" rx="1.5" fill="none" stroke="{P["wood_l"]}" stroke-width="1.1" opacity="0.55"/>'
             f'<rect x="{x+1}" y="{y+1}" width="{s-2}" height="{s-2}" rx="3.5" fill="none" stroke="{INK}" stroke-width="2"/>' + pins)

# Row 4 — toggles
def toggle(c, on):
    cx, cy = cell(c, 3); tw, th = 150, 36; x, y = cx+(CW-tw)/2, cy+(CH-th)/2
    kw, kh = 44, 50; kx = x+tw-kw-3 if on else x+3; ky = y+(th-kh)/2
    groove = P['brick'] if on else '#5E4330'
    kraft = P['kraft'] if on else '#A8906F'
    kn = P['wood_l'] if on else '#C9B08C'
    g = [f'<rect x="{x}" y="{y}" width="{tw}" height="{th}" rx="5" fill="{kraft}"/>',
         f'<path d="{ring(x, y, tw, th, 6, 5)}" fill-rule="evenodd" fill="#000" filter="url(#edgeGrain)" opacity="0.6"/>',
         f'<rect x="{x+8}" y="{y+th/2-5}" width="{tw-16}" height="10" rx="2" fill="{groove}" stroke="{INK}" stroke-width="1.2"/>',
         f'<line x1="{x+9}" y1="{y+th/2-3}" x2="{x+tw-9}" y2="{y+th/2-3}" stroke="#000" stroke-width="1.5" opacity="0.25"/>',
         f'<rect x="{x+1}" y="{y+1}" width="{tw-2}" height="{th-2}" rx="4" fill="none" stroke="{INK}" stroke-width="2"/>',
         f'<rect x="{kx}" y="{ky}" width="{kw}" height="{kh}" rx="4" fill="{kn}" stroke="{INK}" stroke-width="2"/>',
         f'<path d="M{kx+3} {ky+kh-5} V{ky+4} Q{kx+3} {ky+3} {kx+5} {ky+3} H{kx+kw-5}" fill="none" stroke="#FFF1D6" stroke-width="1.2" opacity="0.6"/>']
    for i, gx in enumerate((kx+12, kx+20, kx+28)):
        g.append(f'<line x1="{gx}" y1="{ky+9}" x2="{gx}" y2="{ky+kh-9}" stroke="{INK}" stroke-width="1.2" opacity="{0.55 if i==1 else 0.35}"/>')
    if on:
        g.append(f'<circle cx="{kx+kw/2}" cy="{ky+kh/2}" r="4.5" fill="{P["brick"]}" stroke="{INK}" stroke-width="1"/>')
    return ''.join(g)
items.append(toggle(0, False))
items.append(toggle(1, True))

# Row 4 — checkboxes
def checkbox(c, checked):
    cx, cy = cell(c, 3); s = 64; x, y = cx+(CW-s)/2, cy+(CH-s)/2
    g = [f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="2" fill="{P["cream"]}"/>',
         f'<path d="{ring(x, y, s, s, 12, 2)}" fill-rule="evenodd" fill="#000" filter="url(#edgeGrain)" opacity="0.55"/>',
         f'<rect x="{x+6.8}" y="{y+5.4}" width="{s-12}" height="{s-12}" fill="none" stroke="{P["brick"]}" stroke-width="1.2"/>',
         f'<rect x="{x+1}" y="{y+1}" width="{s-2}" height="{s-2}" rx="1.5" fill="none" stroke="{INK}" stroke-width="2"/>']
    for (px, py) in ((x+6.8, y+5.4), (x+s-5.2, y+5.4), (x+6.8, y+s-6.6), (x+s-5.2, y+s-6.6)):
        g.append(f'<circle cx="{px}" cy="{py}" r="1.8" fill="{INK}"/>')
    if checked:
        # brush-like hand-inked tick: variable width, slight overshoot past the top-right corner
        t = (f'M{x+12} {y+30} C{x+15} {y+29} {x+19} {y+33} {x+24} {y+40} '
             f'C{x+33} {y+24} {x+45} {y+8} {x+66} {y-6} '
             f'C{x+68} {y-5} {x+67} {y-3} {x+65} {y-1} '
             f'C{x+48} {y+14} {x+36} {y+32} {x+26} {y+50} '
             f'C{x+25} {y+52} {x+22} {y+52} {x+21} {y+50} '
             f'C{x+18} {y+42} {x+15} {y+36} {x+11} {y+33} C{x+9} {y+32} {x+10} {y+30} {x+12} {y+30}Z')
        k = s/56
        g.append(f'<g transform="translate({x} {y}) scale({k}) translate({-x} {-y})"><path d="{t}" fill="{P["brick"]}" transform="translate(0.9 -0.6)" opacity="0.35"/><path d="{t}" fill="{P["brick"]}"/></g>')
    return ''.join(g)
items.append(checkbox(2, False))
items.append(checkbox(3, True))

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
       f'<defs>{defs}{"".join(masks)}</defs>{"".join(items)}</svg>')
open(sys.argv[1], 'w').write('<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent}svg{display:block}</style></head><body>'
                             + svg + '</body></html>')
