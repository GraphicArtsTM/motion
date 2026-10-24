"""Push Pals — MAIN MENU mockup (diegetic table scene), 1536x1024."""
import math, sys
from shared import P, scene_defs, table, finish, page, flame, matchstick, corners

W, H = 1536, 1024
INK, CREAM = P['ink'], P['cream']
SC = "font-family:'Alegreya Sans SC'"
SANS = "font-family:'Alegreya Sans'"

def shadow(inner, f='shadow'):
    return f'<g filter="url(#{f})">{inner}</g>'

def label(x, y, text, selected=False, desc=None):
    if selected:
        g = (f'<path d="M{x} {y-8} l6 -6 l6 6 l-6 6z" fill="{P["candle"]}" stroke="{INK}" stroke-width="1"/>'
             f'<text x="{x+22}" y="{y}" style="{SC};font-weight:700;font-size:27px;letter-spacing:2.5px" fill="#F6ECD8">play</text>'
             f'<line x1="{x+22}" y1="{y+11}" x2="{x+92}" y2="{y+11}" stroke="{P["candle"]}" stroke-width="1.4"/>'
             f'<line x1="{x+96}" y1="{y+11}" x2="{x+250}" y2="{y+11}" stroke="{P["candle"]}" stroke-width="1" opacity="0.35"/>')
        if desc:
            g += f'<text x="{x+22}" y="{y+38}" style="{SANS};font-weight:400;font-size:18px" fill="#E3D3B4" opacity="0.92">{desc}</text>'
        return g.replace('>play<', f'>{text}<')
    return (f'<path d="M{x+2} {y-7} l4 -4 l4 4 l-4 4z" fill="none" stroke="{CREAM}" stroke-width="1.1" opacity="0.6"/>'
            f'<text x="{x+20}" y="{y}" style="{SC};font-weight:500;font-size:21px;letter-spacing:2px" fill="{CREAM}" opacity="0.72">{text}</text>')

S = [f'<rect width="{W}" height="{H}" fill="#2a1609"/>', table(W, H)]

# far: blurred candle off the top-left edge + bokeh
far = (f'<ellipse cx="60" cy="230" rx="90" ry="20" fill="url(#brass)"/>'
       f'<rect x="22" y="40" width="76" height="190" fill="#E9DAB8"/>'
       + ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#F2C46B" opacity="{o}"/>' for x, y, r, o in
                 [(420, 40, 18, .25), (700, 24, 12, .2), (1180, 40, 26, .14), (1420, 120, 16, .12)]))
S.append(f'<g filter="url(#blurFar)" opacity="0.4">{far}</g>')
S.append(f'<circle cx="60" cy="10" r="90" fill="#FFB347" opacity="0.5" filter="url(#glow)"/>')

# ---------- LOGO (top-left) ----------
lx, ly, lw, lh = 72, 76, 300, 100
logo = (f'<rect x="{lx}" y="{ly}" width="{lw}" height="{lh}" fill="{CREAM}" filter="url(#paper)"/>'
        f'<rect x="{lx+6}" y="{ly+6}" width="{lw-12}" height="{lh-12}" fill="none" stroke="{INK}" stroke-width="1.3"/>'
        f'<rect x="{lx+11.8}" y="{ly+10.4}" width="{lw-22}" height="{lh-22}" fill="none" stroke="{P["brick"]}" stroke-width="2.6"/>'
        + corners(lx+16, ly+16, lw-32, lh-32, 0, 0.3) +
        f'<text x="{lx+lw/2+12}" y="{ly+56}" text-anchor="middle" style="font-family:\'Playfair Display SC\';font-weight:900;font-size:33px;letter-spacing:1px" fill="{P["brick"]}" opacity="0.9" transform="translate(1.2 -0.8)">Push Pals</text>'
        f'<text x="{lx+lw/2+12}" y="{ly+56}" text-anchor="middle" style="font-family:\'Playfair Display SC\';font-weight:900;font-size:33px;letter-spacing:1px" fill="{INK}">Push Pals</text>'
        f'<text x="{lx+lw/2+12}" y="{ly+76}" text-anchor="middle" style="{SC};font-weight:500;font-size:11px;letter-spacing:3.5px" fill="{P["blue"]}">a cooperative tale</text>'
        + f'<g transform="translate({lx+40} {ly+68}) rotate(-90)">{matchstick(0, 0, 30, 0, 5, P["wood_l"], P["brick"])}</g>')
S.append(f'<g transform="rotate(-1.2 {lx+lw/2} {ly+lh/2})">{shadow(logo, "shadowS")}</g>')

# ---------- PLAY: open matchbox (selected) ----------
mx, my = 470, 372
S.append(f'<ellipse cx="{mx+195}" cy="{my+88}" rx="260" ry="150" fill="#F2C46B" opacity="0.42" filter="url(#glowWide)"/>')
mb = []
dx = mx + 112
mb.append(f'<rect x="{dx}" y="{my+12}" width="270" height="148" rx="2" fill="{P["kraft"]}" stroke="{INK}" stroke-width="2"/>')
mb.append(f'<rect x="{dx+9}" y="{my+21}" width="252" height="130" fill="#8E6440" stroke="{INK}" stroke-width="1"/>')
for i in range(8):
    yy = my + 30 + i*15.6
    mb.append(matchstick(dx + 12 + (i % 3)*3, yy, dx + 228 + (i % 2)*4, yy, 8.5, P['wood_l'], P['brick'] if i != 3 else P['red']))
# sleeve with printed label
mb.append(f'<rect x="{mx}" y="{my}" width="268" height="172" rx="2" fill="{P["blue"]}" stroke="{INK}" stroke-width="2"/>')
mb.append(f'<rect x="{mx+1}" y="{my+1}" width="266" height="13" fill="#5E3E27" filter="url(#sand)"/>')
mb.append(f'<rect x="{mx+1}" y="{my+158}" width="266" height="13" fill="#5E3E27" filter="url(#sand)"/>')
mb.append(f'<line x1="{mx}" y1="{my+14}" x2="{mx+268}" y2="{my+14}" stroke="{INK}" stroke-width="1.2"/><line x1="{mx}" y1="{my+158}" x2="{mx+268}" y2="{my+158}" stroke="{INK}" stroke-width="1.2"/>')
ix, iy, iw, ih = mx+14, my+24, 240, 124
mb.append(f'<rect x="{ix}" y="{iy}" width="{iw}" height="{ih}" fill="{CREAM}" filter="url(#paper)"/>')
mb.append(f'<rect x="{ix+5.8}" y="{iy+4.4}" width="{iw-10}" height="{ih-10}" fill="none" stroke="{P["brick"]}" stroke-width="2.4"/>')
mb.append(f'<rect x="{ix+10}" y="{iy+10}" width="{iw-20}" height="{ih-20}" fill="none" stroke="{INK}" stroke-width="0.9"/>')
ocx, ocy = ix+iw/2, iy+ih/2
rays = ''.join(f'<line x1="{ocx}" y1="{ocy}" x2="{ocx+140*math.cos(a*math.pi/18):.1f}" y2="{ocy+140*math.sin(a*math.pi/18):.1f}"/>' for a in range(36))
mb.append(f'<clipPath id="mbClip"><rect x="{ix+11}" y="{iy+11}" width="{iw-22}" height="{ih-22}"/></clipPath>'
          f'<g clip-path="url(#mbClip)" stroke="{P["brick"]}" stroke-width="3" opacity="0.13">{rays}</g>')
mb.append(f'<ellipse cx="{ocx}" cy="{ocy}" rx="34" ry="42" fill="{CREAM}" stroke="{INK}" stroke-width="1.2"/>'
          f'<ellipse cx="{ocx+0.8}" cy="{ocy-0.6}" rx="29" ry="37" fill="none" stroke="{P["brick"]}" stroke-width="1.6"/>')
mb.append(f'<rect x="{ocx-3}" y="{ocy-6}" width="6" height="34" fill="{P["wood_l"]}" stroke="{INK}" stroke-width="1"/>'
          f'<ellipse cx="{ocx}" cy="{ocy-9}" rx="6.5" ry="8" fill="{P["brick"]}" stroke="{INK}" stroke-width="1"/>' + flame(ocx, ocy-14, 26))
S.append(shadow(''.join(mb)))
# matchstick pointer (from buttons sheet), pointing right at the matchbox
px0, py = 290, my + 88
S.append(shadow(f'{flame(px0+124, py-2, 40)}'
                f'<rect x="{px0}" y="{py-6}" width="118" height="12" rx="1.5" fill="{P["wood_l"]}" stroke="{INK}" stroke-width="1.6"/>'
                f'<line x1="{px0+4}" y1="{py-2}" x2="{px0+110}" y2="{py-2}" stroke="#F2DDB8" stroke-width="1.3" opacity="0.8"/>'
                f'<ellipse cx="{px0+124}" cy="{py}" rx="14" ry="11" fill="{P["brick"]}" stroke="{INK}" stroke-width="1.6"/>'
                f'<ellipse cx="{px0+119}" cy="{py-4}" rx="4.5" ry="2.2" fill="#fff" opacity="0.28"/>', 'shadowS'))
S.append(label(mx, my+222, 'Play', True, 'Strike a match and start a new adventure — 1 to 4 pals'))

# ---------- ONLINE: tin-can telephone ----------
def can(x, y, ang):
    w, h = 64, 84
    return (f'<g transform="rotate({ang} {x+w/2} {y+h/2})">'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#tin)" stroke="{INK}" stroke-width="1.6"/>'
            f'<rect x="{x}" y="{y+22}" width="{w}" height="40" fill="{P["brick"]}" stroke="{INK}" stroke-width="1"/>'
            f'<rect x="{x}" y="{y+28}" width="{w}" height="2" fill="{CREAM}" opacity="0.8"/><rect x="{x}" y="{y+54}" width="{w}" height="2" fill="{CREAM}" opacity="0.8"/>'
            + ''.join(f'<line x1="{x}" y1="{y+yy}" x2="{x+w}" y2="{y+yy}" stroke="{INK}" stroke-width="0.8" opacity="0.5"/>' for yy in (6, 12, 72, 78)) +
            f'<ellipse cx="{x+w/2}" cy="{y}" rx="{w/2}" ry="8" fill="#C9C2B4" stroke="{INK}" stroke-width="1.6"/>'
            f'<ellipse cx="{x+w/2}" cy="{y}" rx="{w/2-6}" ry="5" fill="none" stroke="#7d776c" stroke-width="1"/>'
            f'<ellipse cx="{x+w/2}" cy="{y+h}" rx="{w/2}" ry="7" fill="none" stroke="{INK}" stroke-width="1.6" stroke-dasharray="0 {w*0.05} {w*3} 0"/></g>')
tx, ty = 960, 196
S.append(f'<path d="M{tx+60} {ty+40} C {tx+110} {ty+120} {tx+190} {ty+120} {tx+242} {ty+46}" fill="none" stroke="#E8DCC2" stroke-width="2" opacity="0.9"/>')
S.append(shadow(can(tx, ty, -8)))
S.append(shadow(can(tx+232, ty+4, 9)))
S.append(f'<path d="M{tx+60} {ty+40} C {tx+110} {ty+120} {tx+190} {ty+120} {tx+242} {ty+46}" fill="none" stroke="#E8DCC2" stroke-width="2" opacity="0.9"/>')
S.append(label(tx+4, ty+156, 'Online'))

# ---------- WARDROBE: thimble + fabric swatch ----------
hx, hy = 1290, 384
fab = (f'<g transform="rotate(-10 {hx-40} {hy+50})"><path d="M{hx-92} {hy+14} ' +
       ''.join(f'l6 -5 l6 5 ' for _ in range(10)) +
       f'l0 0 ' + ''.join('l5 6 l-5 6 ' for _ in range(6)) + ''.join('l-6 5 l-6 -5 ' for _ in range(10)) + ''.join('l-5 -6 l5 -6 ' for _ in range(6)) +
       f'z" fill="{P["blue"]}" stroke="{INK}" stroke-width="1.2"/>'
       f'<clipPath id="fabC"><rect x="{hx-90}" y="{hy+15}" width="116" height="70"/></clipPath>'
       f'<g clip-path="url(#fabC)" stroke="{CREAM}" stroke-width="2" opacity="0.35">' +
       ''.join(f'<line x1="{hx-90+k*14}" y1="{hy+10}" x2="{hx-90+k*14}" y2="{hy+90}"/><line x1="{hx-95}" y1="{hy+18+k*14}" x2="{hx+30}" y2="{hy+18+k*14}"/>' for k in range(9)) +
       f'</g></g>')
S.append(shadow(fab, 'shadowS'))
th = (f'<path d="M{hx-2} {hy+96} L{hx+6} {hy+22} Q{hx+8} {hy} {hx+34} {hy} Q{hx+60} {hy} {hx+62} {hy+22} L{hx+70} {hy+96} Z" fill="url(#brassV)" stroke="{INK}" stroke-width="1.6"/>'
      f'<rect x="{hx-5}" y="{hy+84}" width="78" height="14" rx="3" fill="url(#brassV)" stroke="{INK}" stroke-width="1.6"/>'
      + ''.join(f'<circle cx="{hx+14+c*10+(r%2)*5}" cy="{hy+16+r*10}" r="2.1" fill="#6E4A1C" opacity="0.75"/>'
                for r in range(7) for c in range(5) if not (r == 0 and c in (0, 4)) and hx+14+c*10+(r%2)*5 < hx+60) +
      f'<path d="M{hx+14} {hy+14} Q{hx+12} {hy+50} {hx+10} {hy+80}" stroke="#FFF1C8" stroke-width="2" fill="none" opacity="0.55"/>')
S.append(shadow(th))
S.append(shadow(f'<circle cx="{hx+104}" cy="{hy+82}" r="13" fill="{CREAM}" stroke="{INK}" stroke-width="1.4"/>'
                + ''.join(f'<circle cx="{hx+104+dx2}" cy="{hy+82+dy2}" r="2" fill="{INK}"/>' for dx2, dy2 in ((-4, -4), (4, -4), (-4, 4), (4, 4))), 'shadowS'))
S.append(label(hx-88, hy+146, 'Wardrobe'))

# ---------- COLLECTION: notebook ----------
nx, ny, nw, nh = 990, 540, 152, 196
nb = (f'<rect x="{nx}" y="{ny}" width="{nw}" height="{nh}" rx="3" fill="{P["kraft"]}" stroke="{INK}" stroke-width="1.8" filter="url(#paper)"/>'
      f'<rect x="{nx}" y="{ny}" width="22" height="{nh}" rx="2" fill="{P["wood_d"]}" stroke="{INK}" stroke-width="1.6"/>'
      f'<rect x="{nx+40}" y="{ny+36}" width="88" height="44" fill="{CREAM}" stroke="{INK}" stroke-width="1.2"/>'
      f'<rect x="{nx+44.6}" y="{ny+39.4}" width="80" height="36" fill="none" stroke="{P["brick"]}" stroke-width="1.2"/>'
      f'<line x1="{nx+54}" y1="{ny+52}" x2="{nx+114}" y2="{ny+52}" stroke="{INK}" stroke-width="1" opacity="0.4"/>'
      f'<line x1="{nx+54}" y1="{ny+64}" x2="{nx+100}" y2="{ny+64}" stroke="{INK}" stroke-width="1" opacity="0.4"/>'
      f'<rect x="{nx+nw-30}" y="{ny-1}" width="9" height="{nh+2}" fill="{P["brick"]}" stroke="{INK}" stroke-width="1.2"/>'
      f'<path d="M{nx+nw-26} {ny+nh} l0 34 l-6 -7 l-6 7 l0 -34" fill="{P["blue"]}" stroke="{INK}" stroke-width="1.2" transform="translate(-30 0)"/>')
S.append(f'<g transform="rotate(5 {nx+nw/2} {ny+nh/2})">{shadow(nb)}</g>')
S.append(label(nx+2, ny+nh+80, 'Collection'))

# ---------- SETTINGS: ruler ----------
rx, ry, rl, rw = 150, 712, 400, 46
ticks = ''.join(f'<line x1="{rx+14+k*9.4:.1f}" y1="{ry}" x2="{rx+14+k*9.4:.1f}" y2="{ry+(16 if k%10==0 else 11 if k%5==0 else 7)}" stroke="{INK}" stroke-width="1"/>' for k in range(40))
ru = (f'<rect x="{rx}" y="{ry}" width="{rl}" height="{rw}" rx="2" fill="{P["wood_l"]}" stroke="{INK}" stroke-width="1.8"/>'
      f'<line x1="{rx+3}" y1="{ry+3}" x2="{rx+rl-3}" y2="{ry+3}" stroke="#F4E2BF" stroke-width="1.4" opacity="0.7"/>'
      f'<rect x="{rx}" y="{ry+rw-7}" width="{rl}" height="7" fill="{P["brick"]}" opacity="0.85"/>'
      f'<line x1="{rx}" y1="{ry+rw-7}" x2="{rx+rl}" y2="{ry+rw-7}" stroke="{INK}" stroke-width="1"/>'
      + ticks + f'<circle cx="{rx+rl-16}" cy="{ry+24}" r="5" fill="#3a2414" stroke="{INK}" stroke-width="1"/>'
      f'<circle cx="{rx+rl-16}" cy="{ry+24}" r="7.5" fill="none" stroke="url(#brass)" stroke-width="2.5"/>')
S.append(f'<g transform="rotate(-5 {rx+rl/2} {ry+rw/2})">{shadow(ru)}</g>')
S.append(label(rx+6, ry+108, 'Settings'))

# ---------- EXIT: small door ----------
dx0, dy0, dw, dh = 1300, 616, 104, 168
door = (f'<path d="M{dx0} {dy0+dh} V{dy0+40} Q{dx0} {dy0} {dx0+dw/2} {dy0} Q{dx0+dw} {dy0} {dx0+dw} {dy0+40} V{dy0+dh}Z" fill="{P["wood_d"]}" stroke="{INK}" stroke-width="1.8"/>'
        f'<path d="M{dx0+10} {dy0+dh-8} V{dy0+44} Q{dx0+10} {dy0+10} {dx0+dw/2} {dy0+10} Q{dx0+dw-10} {dy0+10} {dx0+dw-10} {dy0+44} V{dy0+dh-8}Z" fill="#8A5E38" stroke="{INK}" stroke-width="1.2"/>'
        f'<path d="M{dx0+20} {dy0+90} V{dy0+52} Q{dx0+20} {dy0+24} {dx0+dw/2} {dy0+24} Q{dx0+dw-20} {dy0+24} {dx0+dw-20} {dy0+52} V{dy0+90}Z" fill="none" stroke="{INK}" stroke-width="1" opacity="0.6"/>'
        f'<rect x="{dx0+20}" y="{dy0+104}" width="{dw-40}" height="46" fill="none" stroke="{INK}" stroke-width="1" opacity="0.6"/>'
        f'<circle cx="{dx0+dw-24}" cy="{dy0+96}" r="5.5" fill="url(#brass)" stroke="{INK}" stroke-width="1"/>'
        f'<rect x="{dx0-6}" y="{dy0+dh-4}" width="{dw+12}" height="8" rx="1" fill="{P["wood_d"]}" stroke="{INK}" stroke-width="1.4"/>')
S.append(shadow(door))
S.append(label(dx0+6, dy0+dh+46, 'Exit'))

# ---------- input hints & build tag (inside 16:9 safe area) ----------
def keycap(x, y, t, w):
    return (f'<rect x="{x}" y="{y-17}" width="{w}" height="24" rx="4" fill="none" stroke="{CREAM}" stroke-width="1.2" opacity="0.75"/>'
            f'<text x="{x+w/2}" y="{y}" text-anchor="middle" style="{SANS};font-weight:500;font-size:14px" fill="{CREAM}" opacity="0.85">{t}</text>')
def face(x, y, which):
    pos = {'s': (0, 7), 'e': (7, 0), 'n': (0, -7), 'w': (-7, 0)}
    return ''.join(f'<circle cx="{x+dx2}" cy="{y-5+dy2}" r="3.6" fill="{CREAM if k == which else "none"}" stroke="{CREAM}" stroke-width="1" opacity="0.8"/>' for k, (dx2, dy2) in pos.items())
hy2 = 912
hint = (face(1076, hy2, 's') + keycap(1092, hy2, 'Enter', 52) + f'<text x="1154" y="{hy2}" style="{SANS};font-size:17px" fill="{CREAM}" opacity="0.8">Select</text>'
        + face(1240, hy2, 'e') + keycap(1256, hy2, 'Esc', 40) + f'<text x="1306" y="{hy2}" style="{SANS};font-size:17px" fill="{CREAM}" opacity="0.8">Back</text>'
        + f'<path d="M1384 {hy2-19} h12 a6 6 0 0 1 6 6 v16 a12 12 0 0 1 -24 0 v-16 a6 6 0 0 1 6 -6z M1390 {hy2-19} v10" fill="none" stroke="{CREAM}" stroke-width="1.2" opacity="0.75"/>'
        + f'<text x="1410" y="{hy2}" style="{SANS};font-size:17px" fill="{CREAM}" opacity="0.8">Pick up</text>')
S.append(f'<line x1="1070" y1="{hy2-36}" x2="1470" y2="{hy2-36}" stroke="{CREAM}" stroke-width="0.8" opacity="0.18"/>')
S.append(hint)
S.append(f'<text x="72" y="{hy2}" style="{SANS};font-size:15px;letter-spacing:1px" fill="{CREAM}" opacity="0.55">Prototype build 0.1</text>')

S.append(finish(W, H))
svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><defs>{scene_defs(60, 40, 1400)}</defs>{"".join(S)}</svg>'
open(sys.argv[1], 'w').write(page(svg, '#2a1609'))
