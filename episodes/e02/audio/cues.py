"""Партитура серии 2 «Личная жизнь»: музыка по сценам, шумы и эффекты на событиях.
Выполняется внутри engine/audio/mix.py — доступны все инструменты движка (groove, melody, chord, hit,
add, whoosh, impact, walla, rain_bed, seg, strikes_thunder…). Время — сюжетное (как в shots.js).
Темы серии: «школьная» (фа мажор, лёгкий бит), «Эм-Джей» (нежные струнные на закате),
«ODILMAN» (низкая медь, ре минор с пониженной ступенью, дойра в 6/8).
"""
CH.update({'Am': [45, 48, 52], 'G': [43, 47, 50], 'Gm7': [43, 46, 53], 'Fm': [41, 44, 48], 'Db': [49, 53, 56], 'Abm': [44, 47, 51]})
SCHOOL = ['F', 'C', 'Dm', 'Bb']


def chirp(seed=0):
    """птичка: короткие свистящие трели"""
    g = np.random.default_rng(seed); out = []
    for k in range(g.integers(2, 5)):
        n = int(SR * g.uniform(.05, .11)); t = tt(n)
        f = g.uniform(2600, 4200) * (1 + .25 * np.sin(2 * np.pi * g.uniform(8, 18) * t))
        out.append(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) ** 2)
        out.append(np.zeros(int(SR * g.uniform(.03, .08))))
    return np.concatenate(out)


def birds(t0, t1, gain=.05, seed=1):
    g = np.random.default_rng(seed); t = t0
    while t < t1:
        add('amb', chirp(int(g.integers(1e6))), t, gain * g.uniform(.5, 1), pan=g.uniform(-.8, .8), rev=.3)
        t += g.uniform(.6, 2.2)


def school_bell(len_=2.6):
    """электрический школьный звонок: металл, дребезг 28 Гц"""
    n = int(len_ * SR); t = tt(n)
    x = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((1870, 1), (2410, .6), (3530, .4), (4900, .25)))
    x *= (np.sin(2 * np.pi * 28 * t) > 0) * .8 + .2
    return x * np.minimum(1, t * 30) * np.minimum(1, (len_ - t) * 6) * .4


def doira(t, amp=1.0, slap=False):
    """дойра: глухой «дум» (центр) или звонкий шлепок по краю с бубенцами"""
    if slap:
        add('drums', fft_filter(noise(int(.12 * SR)) * np.exp(-tt(int(.12 * SR)) * 40), lo=1500, hi=9000), t, .35 * amp, pan=.2, rev=.25)
        add('drums', tom(330), t, .18 * amp, pan=.2, rev=.2)
    else:
        add('drums', tom(95), t, .55 * amp, rev=.3)
        add('drums', kick(.6, .25, 60), t, .3 * amp)
    jn = int(.25 * SR)   # бубенцы
    add('drums', fft_filter(noise(jn) * np.exp(-tt(jn) * 14), lo=5000, hi=11000), t + .01, .08 * amp, pan=-.3, rev=.3)


def crumple(len_=.5):
    n = int(len_ * SR); g = np.random.default_rng(5)
    bursts = (g.random(n) > .996).astype(float) * g.uniform(.3, 1, n)
    return fft_filter(np.convolve(bursts, np.exp(-np.arange(400) / 60), 'same') * noise(n), lo=1200, hi=9000) * 3


def room_tone(len_, lo=80, hi=600):
    return fft_filter(noise(int(len_ * SR)), lo=lo, hi=hi) * .3


# ---------------- 0–14 Кухня, утро ----------------
add('amb', room_tone(14, 100, 900), 0, .12)
birds(0.4, 13.5, .035)
for bi, c in enumerate(['F', 'C', 'Bb', 'F']):
    b0 = 0.8 + bi * BAR
    for s, idx in enumerate([0, 2, 1, 2, 0, 2, 1, 2]):
        add('music', pluck(mtof(CH[c][idx] + 12), .9, .45, .996), b0 + s * BEAT / 2, .06, pan=.2 * (-1) ** s, rev=.35)
add('fx', bell(mtof(84), .6), 6.05, .03, rev=.4)                  # пиала о блюдце
add('fx', whoosh(.35, True, 600), 10.6, .45, pan=.5)               # Тимур влетает
for k in range(5):
    add('fx', footstep(.8), 10.62 + k * .07, .25, pan=.5 - k * .1)
add('fx', whoosh(.4, False, 500), 13.0, .5, pan=.6)               # и вылетает
add('fx', thud(1.0), 13.3, .7, pan=.7, rev=.3)                     # хлопок двери
add('fx', impact(.4, .4), 13.3, .25, pan=.7)
add('fx', screech(.25), 13.35, .05, pan=-.4)                       # кот мяукнул

# ---------------- 14–18.5 Заставка ----------------
hit(14.1, 1.1, 'F')
melody([65, 69, 72, 70, 69, 67, 65, None], 14.15, BEAT / 2, 'brass', .15, ln=[1, 1, 1, 1, 1, 1, 4, 1])
melody([65, 69, 72, 70, 69, 67, 65, None], 14.15, BEAT / 2, 'brass', .09, oct=-12, ln=[1, 1, 1, 1, 1, 1, 4, 1])
for k, t0 in enumerate((14.1, 14.1 + BEAT * 2, 14.1 + BEAT * 4, 14.1 + BEAT * 5, 14.1 + BEAT * 6)):
    add('drums', taiko(1.0, 70 + 10 * (k % 2)), t0, .55, rev=.3)
add('fx', whoosh(.8, True), 17.8, .35)

# ---------------- 18.5–41 Ворота лицея ----------------
groove(18.6, 33.9, prog=SCHOOL, intensity=.42, half=True, toms=False)
melody([69, 72, 74, 72, 69, 67, 65, 67], 18.6 + BAR * 2, BEAT, 'pluck', .1, oct=12)
melody([69, 72, 74, 77, 76, 74, 72, None], 18.6 + BAR * 6, BEAT, 'pluck', .09, oct=12)
birds(18.5, 40.5, .04, 3)
add('amb', walla(22, .2, 1), 18.6, .12, rev=.2)
for k in range(10):
    add('fx', footstep(1.0), 18.9 + k * .16, .3, pan=-.6 + k * .06)   # бег Тимура
add('fx', school_bell(2.8), 33.95, .5, pan=.1, rev=.5)
add('music', tape_stop(.5), 33.85, .15)
add('amb', walla(5, .7, 2), 34.0, .16, rev=.2)
for k in range(14):
    add('fx', footstep(1.0), 34.7 + k * .14, .25, pan=.1 * (-1) ** k)
add('fx', whoosh(.6, True), 40.4, .3)

# ---------------- 41–66 Класс физики ----------------
add('amb', room_tone(25, 90, 700), 41, .1)
for k in range(9):                                                # мел по доске
    add('fx', fft_filter(noise(int(.07 * SR)) * np.exp(-tt(int(.07 * SR)) * 30), lo=2500, hi=7000), 41.4 + k * .21, .06, pan=.15, rev=.3)
add('amb', walla(1.4, 1.0, 4), 47.3, .12)                          # смех (с голосом c1)
add('fx', crumple(.6), 48.3, .2, pan=-.2)                          # Азим мнёт бумажку
# паучье чутьё: удар сердца, высокий звон, мир замедляется
add('fx', whoosh(.5, False, 300), 49.2, .45, rev=.4)
add('fx', heartbeat(1.0), 49.35, .5); add('fx', heartbeat(1.0), 50.15, .45)
add('fx', tinnitus(1.8), 49.3, .05)
add('music', pad(50, 2.2, fc=500), 49.25, .06, rev=.6)
add('fx', thwip(), 50.55, .25)
add('fx', splat(), 51.0, .35)                                     # хвать!
add('fx', whoosh(.3, True, 800), 51.05, .25)
add('amb', walla(1.2, .4, 5), 51.3, .08)                          # «о-о»
melody([77, 76, 72, None, 74, 72], 52.2, BEAT / 2, 'pluck', .07, oct=12)
for k in range(6):
    add('fx', footstep(.7), 54.3 + k * .5, .18, pan=-.2)
for k in range(6):
    add('fx', footstep(.7), 62.2 + k * .5, .16, pan=.1)
for i, c in enumerate(['F', 'Am', 'Bb', 'C']):
    chord(c, 62.0 + i * 1.0, 1.2, 'strings', .03)
melody([72, 74, 76, 77, 76, 72], 62.4, BEAT, 'pluck', .07, oct=12)

# ---------------- 66–108 Столовая ----------------
din = walla(42, .45, 7)
add('amb', din, 66.0, .2, rev=.15)
for k in range(30):                                                # ложки, тарелки
    add('fx', bell(mtof(96 + (k * 7) % 9), .25), 66.3 + k * 1.37, .012, pan=np.sin(k), rev=.3)
for bi in range(8):
    c = ['F', 'Dm', 'Bb', 'C'][bi % 4]; b0 = 66.2 + bi * BAR
    for s, idx in enumerate([0, 1, 2, 1, 0, 2, 1, 2]):
        add('music', pluck(mtof(CH[c][idx] + 24), .4, .5, .993), b0 + s * BEAT / 2, .05, pan=.25 * (-1) ** s, rev=.3)
add('fx', impact(.3), 68.4, .2)                                    # поднос на стол
add('fx', clap(), 71.95, .25, pan=.1)                              # кулачки
brassSting = [72, 76, 79, 84]
melody(brassSting, 82.45, BEAT / 3, 'brass', .12, ln=[1, 1, 1, 4])  # «Паук-Новоград™»
add('fx', bell(mtof(96), 1.0), 83.0, .06, rev=.5)
chord('Dm', 89.7, 2.6, 'strings', .03)                             # «папа бы мной гордился»
# «он просто держит обещания» — зал стихает
chord('F', 94.5, 4.0, 'strings', .045); chord('Am', 98.4, 2.0, 'strings', .035); chord('Bb', 100.3, 2.4, 'strings', .035)
melody([72, None, 76, 77, 79, None, 77, 76], 94.7, BEAT, 'pluck', .08, oct=12)
melody(HERO[:4], 102.6, BEAT, 'pluck', .06, oct=24)
add('fx', whoosh(.5, True), 107.6, .25)

# ---------------- 108–152 Коридор: Азим «Флэш» ----------------
add('amb', walla(23, .5, 9), 108.0, .18, rev=.15)
add('amb', room_tone(44, 90, 800), 108, .1)
for k in range(10):
    add('fx', stomp(.5), 107.6 + k * .42, .12, pan=.5 - k * .04)  # тяжёлые шаги Азима
for i in range(int((130.3 - 109.6) / (BEAT / 2))):                 # напряжение: бас-остинато и тайко
    t0 = 109.6 + i * BEAT / 2
    add('bass', bassnote([38, 38, 41, 38, 39, 38, 36, 38][i % 8], .22, .8), t0, .28)
    if i % 8 == 0:
        add('drums', taiko(1.0, 58), t0, .45, rev=.3)
chord('Dm', 109.6, 8.0, 'pad', .025)
add('fx', impact(.8, 1.0), 111.58, .55, pan=-.2)                    # ладонь по шкафчику
add('fx', fft_filter(noise(int(.06 * SR)) * np.exp(-tt(int(.06 * SR)) * 60), lo=800, hi=5000), 115.2, .35)   # лопнул пузырь жвачки
for k in range(2):
    add('fx', fft_filter(noise(int(.4 * SR)) * np.exp(-tt(int(.4 * SR)) * 8), lo=1500, hi=6000), 66.8 + k * 21.3, .04, pan=.6)   # подносы
add('fx', metal_groan(.8, 120), 111.6, .1)
chord('F', 118.3, 2.4, 'strings', .05, oct=0)                      # «Не давай ему»
add('fx', thud(.6), 128.35, .45)                                   # толчок — Тимур не сдвинулся
add('fx', riser(1.1, 300, 6000), 129.3, .3)
# ---- драка: шесть приёмов (время — как F в shots.js) ----
def crowd_vowel(len_, f0=170, formant=420, seed=0, rise=.25, fall=.6, slide=0.0):
    """толпа тянет гласную («у-у-у», «о-о-о»): дюжина голосов с вибрато, пропущенных через форманту"""
    g = np.random.default_rng(seed); n = int(len_ * SR); t = tt(n); out = np.zeros(n)
    for v in range(12):
        f = f0 * g.uniform(.75, 1.6) * (1 + slide * t / len_)
        ph = 2 * np.pi * np.cumsum(f * (1 + .012 * np.sin(2 * np.pi * g.uniform(4.5, 6.5) * t + g.random() * 6))) / SR
        out += sum(np.sin(k * ph) / k for k in range(1, 9)) * g.uniform(.5, 1)
    out = fft_filter(out, lo=formant * .55, hi=formant * 1.8) + fft_filter(g.standard_normal(n), lo=600, hi=3000) * .08
    env = np.minimum(1, t / rise) * np.clip((len_ - t) / fall, 0, 1)
    return out * env / 6


def crowd_gasp(seed=0, n_voices=10):
    """общий вздох «ах!»: короткие вдохи разных людей вразнобой"""
    g = np.random.default_rng(seed); L = int(.9 * SR); out = np.zeros(L)
    for v in range(n_voices):
        d = int(g.uniform(0, .12) * SR); m = int(g.uniform(.22, .4) * SR); tm = tt(m)
        x = fft_filter(g.standard_normal(m), lo=g.uniform(700, 1100), hi=g.uniform(2500, 4200)) * (tm / tm[-1]) ** 1.5 * np.exp(-np.maximum(0, tm - tm[-1] * .8) * 30)
        out[d:d + m] += x[:L - d] * g.uniform(.6, 1)
    return out / 3


def crowd_laugh(len_=1.6, seed=0):
    """смешки в толпе: гул, прерывистый «ха-ха»"""
    t = tt(int(len_ * SR)); w = walla(len_, 1.4, seed)
    return w * (.45 + .55 * (np.sin(2 * np.pi * 5.3 * t) > -.2)) * np.exp(-t * .6)


add('music', tape_stop(.4), 130.25, .25)
add('fx', heartbeat(1.0), 130.35, .45)
add('fx', whoosh(.7, True, 200), 130.5, .55, rev=.4)
add('fx', impact(1.3, 1.0), 130.85, .9, rev=.3)                    # 1) кулак в шкафчик — БДЫНЬ
add('fx', metal_groan(1.4, 90), 130.9, .25)
add('fx', crash(1.4), 130.85, .2)
add('amb', crowd_vowel(1.0, 200, 520, 41, .1, .5), 130.95, .12, rev=.3)   # «о!»
# боевой бит: тайко, малый, тема героя на меди
groove(131.15, 134.95, prog=['Dm', 'Bb', 'C', 'Dm'], intensity=.8, toms=True, arp=False)
melody([62, 65, 69, 67, 65, 69, 74, None], 131.2, BEAT / 2, 'brass', .1)
for j in (131.25, 131.5, 131.75):                                   # 2) три джеба — свист мимо уха
    add('fx', whoosh(.25, True, 700), j, .4, pan=(.3 if j == 131.5 else -.3))
add('fx', whoosh(.5, True, 250), 131.95, .45)                       # 3) бросок
add('fx', whoosh(.35, False, 500), 132.1, .3, pan=.4)               #    Тимур выкручивается
add('fx', impact(1.1, 1.0), 132.3, .8)                              #    БАМ лицом в шкафчик
add('fx', metal_groan(1.0, 110), 132.32, .2)
add('amb', crowd_laugh(1.8, 43), 132.4, .2, rev=.2)                 #    смех в коридоре
for k in range(5):                                                  # 4) разгон: топот
    add('fx', stomp(.8), 132.85 + k * .07, .3)
add('fx', whoosh(.4, True, 400), 133.13, .4)                        #    подножка
add('fx', thud(1.0), 133.4, .7, pan=.5)                             #    БУХ — в дружка
add('fx', thud(.6), 133.6, .4, pan=.6)
add('amb', crowd_laugh(2.0, 47), 133.45, .26, rev=.2)
add('fx', fft_filter(noise(int(.6 * SR)) * np.exp(-tt(int(.6 * SR)) * 4), lo=90, hi=500), 133.75, .5)   # 5) рык
add('fx', whoosh(.5, True, 200), 134.2, .5)                         #    размах
add('fx', splat(), 134.45, .55); add('fx', impact(.9), 134.45, .6)  #    ХВАТЬ — кулак в ладони
add('amb', crowd_vowel(1.5, 160, 380, 53, .15, .7, -.15), 134.5, .2, rev=.3)   # «у-у-у!»
add('bass', tape_stop(.35), 134.95, .3); add('music', tape_stop(.35), 134.95, .2)
add('fx', impact(1.5), 135.0, .9); add('fx', boom(1.4, 1.0), 135.0, .55)       # 6) толчок ладонью
add('fx', whoosh(.5, False, 500), 135.05, .45, pan=.4)
add('fx', impact(.35, .6), 135.22, .3, pan=.5)                       #    табличка
add('fx', thud(1.5), 135.42, .95, pan=.5, rev=.3)                    #    ТЫДЫЩ в шкафчики
add('fx', impact(1.2, 1.0), 135.43, .7, pan=.5)
add('fx', crash(1.2), 135.43, .25, pan=.5)
add('fx', metal_groan(1.2, 80), 135.45, .25, pan=.5)
add('fx', impact(.4, .9), 135.5, .3, pan=.6)                         #    распахнулась дверца
for k in range(3):                                                   #    учебники
    add('fx', thud(.35), 135.75 + k * .09, .25, pan=.6)
add('fx', scrape(.6), 135.5, .2, pan=.5)                             #    сползает вниз
add('amb', crowd_gasp(59, 12), 135.55, .55, rev=.3)                  # общий вздох «ах!»
add('amb', crowd_vowel(1.2, 190, 600, 61, .05, .5, .1), 135.62, .14, rev=.3)
add('amb', walla(1.4, .3, 63) * np.linspace(0, 1, int(1.4 * SR)), 135.95, .12)   # шёпот нарастает
for k in range(6):                                                   # «звёздочки» в голове
    add('fx', bell(mtof(91 + (k % 3) * 4), .6), 136.0 + k * .9, .025, pan=.5, rev=.6)
add('amb', crowd_vowel(2.2, 175, 450, 67, .2, 1.2), 136.3, .2, rev=.3)   # «о-о-о!» вместе с репликой
add('amb', walla(15, 1.0, 11), 136.4, .22, rev=.2)                 # «Ого-о-о!», телефоны
add('fx', bell(mtof(100), .1), 137.0, .03); add('fx', bell(mtof(100), .1), 137.4, .03)
melody([65, None, 64, None, 62], 140.0, BEAT / 2, 'pluck', .07, oct=12)   # «пол мокрый»
groove(143.6, 151.5, prog=SCHOOL, intensity=.5, half=True)
melody(HERO, 143.6 + BAR, BEAT / 2, 'pluck', .1, oct=12)
add('fx', whoosh(.8, True), 151.2, .3)

# ---------------- 152–205 Двор Старого Затона, закат ----------------
birds(152, 205, .03, 21)
add('amb', room_tone(53, 60, 400), 152, .08)
bus = fft_filter(noise(int(5 * SR)), lo=40, hi=260) * np.exp(-tt(int(5 * SR)) * .5)
add('amb', bus, 152.2, .35, pan=.4)
add('fx', fft_filter(noise(int(.6 * SR)) * np.exp(-tt(int(.6 * SR)) * 5), lo=200, hi=3000), 152.25, .2, pan=.5)   # двери автобуса
# тема «Эм-Джей»: тёплые струнные и гитара-щипок
EMJ = [['F', 'Am', 'Bb', 'C'], ['Dm', 'Am', 'Bb', 'C'], ['F', 'C', 'Bb', 'F']]
b = 0
for row in EMJ * 2:
    for c in row:
        t0 = 152.6 + b * BAR
        if t0 < 159.6 or 162.3 < t0 < 202.5:
            chord(c, t0, BAR * 1.05, 'strings', .028)
            for s, idx in enumerate([0, 1, 2, 1]):
                add('music', pluck(mtof(CH[c][idx] + 24), 1.2, .4, .997), t0 + s * BEAT, .045, pan=.3 * (-1) ** s, rev=.45)
        b += 1
melody([72, 74, 76, None, 77, 76, 74, 72], 156.0, BEAT, 'pluck', .07, oct=12)
# апельсины: дно пакета рвётся (159.8), чутьё — замедление, рывок, ловля «корзиной», два — на лету
add('fx', fft_filter(noise(int(.3 * SR)) * np.exp(-tt(int(.3 * SR)) * 10), lo=800, hi=6000), 159.8, .4)   # треск бумаги
add('fx', whoosh(.8, False, 260), 159.85, .4, rev=.5)                # мир замедляется
add('fx', heartbeat(1.0), 159.95, .4); add('fx', heartbeat(1.0), 160.75, .35)
add('fx', tinnitus(1.6), 159.9, .04)
add('fx', whoosh(.35, True, 500), 159.95, .5, pan=.4)               # рывок
for k, tk in enumerate((160.62, 160.67, 160.72, 160.77, 160.82)):    # мягкие шлепки в ладони
    add('fx', thud(.3), tk, .22, pan=.1 * (k - 2))
add('fx', whoosh(.25, True, 800), 161.1, .3, pan=-.4); add('fx', splat(), 161.3, .2, pan=-.4)   # выхватил левой
add('fx', whoosh(.25, True, 800), 161.15, .3, pan=.4); add('fx', splat(), 161.35, .2, pan=.4)    # и правой
add('fx', whoosh(.6, True, 300), 161.8, .3)                         # мир снова в обычном темпе
add('fx', splat(), 161.85, .2)
add('music', pluck(mtof(84), .6, .6, .995), 161.9, .08)
# «Эм-Джей» — мотив на колокольчиках
melody([81, 77, None, 81, 84], 182.4, BEAT, 'pluck', .08, oct=0)
for k, m in enumerate([84, 88]):
    add('fx', bell(mtof(m), 1.2), 187.45 + k * 1.2, .05, rev=.6)
chord('F', 191.3, 3.6, 'strings', .04)
add('fx', servo(.4, 200, 260), 194.6, .06, pan=.6)                 # окно скрипнуло
add('fx', thud(.5), 201.9, .3, pan=-.3, rev=.3)                    # дверь подъезда
add('fx', splat(), 202.8, .25)                                     # ладонь прилипла
add('fx', fft_filter(np.sin(2 * np.pi * np.cumsum(np.linspace(900, 260, int(.12 * SR))) / SR) * np.exp(-tt(int(.12 * SR)) * 25), lo=150), 203.85, .5)   # ЧПОК
melody([77, 81, 84], 204.0, BEAT / 3, 'pluck', .08)

# двор живёт: скрип качелей, мяч, смех детей, голуби вспорхнули, бабушки шепчутся
for k in range(16):
    tk = 152.5 + k * 3.3
    add('amb', fft_filter(np.sin(2 * np.pi * np.cumsum(np.linspace(700, 520, int(.35 * SR))) / SR) * np.exp(-tt(int(.35 * SR)) * 6), lo=300, hi=3000), tk, .025, pan=-.7, rev=.3)
for k in range(30):
    add('amb', thud(.25), 152.7 + k * .6 + (k % 3) * .05, .05, pan=-.6, rev=.2)
add('amb', walla(52, 1.3, 31), 152.4, .035, pan=-.6, rev=.3)
for k in range(9):                                                   # хлопанье крыльев
    n = int(.5 * SR); flap = (np.sin(2 * np.pi * (14 + k) * tt(n)) > .3) * fft_filter(noise(n), lo=600, hi=5000) * np.exp(-tt(n) * 3)
    add('fx', flap, 158.7 + k * .06, .12, pan=-.3 + k * .05, rev=.3)
add('amb', walla(30, .1, 33) * .5, 164.0, .02, pan=-.8, rev=.4)

# ---------------- 205–221 Кухня вечером, сумерки ----------------
add('amb', room_tone(16, 100, 900), 205, .1)
for bi, c in enumerate(['F', 'Am', 'Bb', 'F', 'Dm', 'Bb', 'C', 'F']):
    b0 = 205.2 + bi * BAR
    for s, idx in enumerate([0, 2, 1, 2, 0, 2, 1, 2]):
        add('music', pluck(mtof(CH[c][idx] + 12), .9, .45, .996), b0 + s * BEAT / 2, .055, pan=.2 * (-1) ** s, rev=.35)
add('fx', bell(mtof(84), .6), 205.6, .025, rev=.4)
chord('Dm', 213.4, 3.0, 'strings', .035); chord('Bb', 216.4, 2.4, 'strings', .035); chord('C', 218.8, 2.4, 'strings', .04)
melody(HERO, 213.6, BEAT, 'strings', .035, oct=0)

# ---------------- 221–225.5 Логотип ----------------
hit(221.1, 1.1, 'F')
melody([74, 77, 81, 79, 77, 76, 74, None], 221.15, BEAT / 2, 'brass', .15, ln=[1, 1, 1, 1, 1, 1, 4, 1])
melody([74, 77, 81, 79, 77, 76, 74, None], 221.15, BEAT / 2, 'brass', .09, oct=-12, ln=[1, 1, 1, 1, 1, 1, 4, 1])

# ---------------- 225.5–241 Тизер: ODILMAN ----------------
add('music', pad(26, 15.5, fc=260), 225.5, .22, rev=.5)
add('music', sub(26, 15.5), 225.5, .25)
add('fx', riser(1.0, 120, 2500), 225.4, .2)
# дойра в 6/8: ДУМ . тек ДУМ тек тек
U6 = BEAT * 2 / 3
for bar in range(int((240.0 - 227.0) / (U6 * 6))):
    b0 = 227.0 + bar * U6 * 6
    for k, (pos, sl) in enumerate(((0, False), (2, True), (3, False), (4, True), (5, True))):
        doira(b0 + pos * U6, (.9 if not sl else .7) * (1 + .15 * (bar % 2)), sl)
# тема ODILMAN: низкая медь, D F Ab G
melody([38, 41, 44, 43, None, 38], 227.6, BEAT, 'brass', .2, ln=[1, 1, 1, 2, 1, 2])
melody([50, 53, 56, 55, None, 50], 227.6, BEAT, 'brass', .08, ln=[1, 1, 1, 2, 1, 2])
chord('Fm', 229.6, 2.0, 'strings', .05, oct=0)
add('fx', crumple(.55), 230.15, .5)
add('fx', whoosh(.6, False, 250), 230.8, .3, pan=.3)
melody([38, 41, 44, 45, 50], 231.3, BEAT / 2, 'brass', .16, ln=[1, 1, 1, 1, 6])
add('fx', zap(1.0, 1.0), 233.05, .35)                              # глаза вспыхивают
add('fx', boom(2.0, 1.0), 233.05, .6)
hit(235.25, 1.3, 'Abm')
add('fx', riser(.6, 400, 6000), 234.6, .25)
chord('Dm', 237.6, 3.4, 'strings', .05, oct=-12)
add('fx', boom(3.0, 1.0), 237.7, .35)

# окружение: дождь и гром только в тизере
strikes_thunder()
rain = rain_bed()
lvl = np.zeros(N)
T = tt(N)
seg(225.5, 241.0, 1.0, .6)
add('amb', rain * lvl, 0, .4)
