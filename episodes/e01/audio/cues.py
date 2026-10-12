"""Партитура серии 1 «Укус молнии»: музыка по сценам, шумы и эффекты на событиях.
Выполняется внутри engine/audio/mix.py — доступны все инструменты движка (groove, melody, chord, hit,
add, whoosh, impact, rain_bed, seg, strikes_thunder…). Время — сюжетное (как в shots.js).
"""
# 0–16.5 Пролог
add('music', pad(38, 16, fc=500), 0.0, 0.12, rev=0.3)
add('music', pad(50, 15, fc=900), 0.4, 0.05, rev=0.5)
for t0 in (0.55, 4.6, 9.2, 13.3):
    add('drums', taiko(1.0, 55), t0, 0.7, rev=0.5)
melody(HERO, 6.0, BEAT, 'pluck', 0.22, oct=0)
melody(HERO, 6.0, BEAT, 'strings', 0.045, oct=-12)
chord('Bb', 10.0, 3.4, 'strings', 0.035)
chord('A', 13.3, 3.2, 'strings', 0.04)
add('fx', riser(3.0, 250, 9000), 13.6, 0.45, rev=0.2)
for k in range(12):
    add('drums', snare(0.3 + 0.7 * k / 11), 15.9 + k * 0.05, 0.35)

# 16.5–21 Заставка
hit(17.08, 1.2)
melody([74, 77, 81, 79, 77, 76, 74, None], 17.15, BEAT / 2, 'brass', 0.16, ln=[1, 1, 1, 1, 1, 1, 4, 1])
melody([74, 77, 81, 79, 77, 76, 74, None], 17.15, BEAT / 2, 'brass', 0.1, oct=-12, ln=[1, 1, 1, 1, 1, 1, 4, 1])
for k, t0 in enumerate((17.08, 17.08 + BEAT * 2, 17.08 + BEAT * 4, 17.08 + BEAT * 5, 17.08 + BEAT * 6)):
    add('drums', taiko(1.0, 70 + 10 * (k % 2)), t0, 0.6, rev=0.3)
add('fx', whoosh(0.8, True), 20.3, 0.4)

# 21–44 Велосипед
groove(21.0, 43.6, intensity=0.85)
melody(HERO, 21.0 + BAR * 2, BEAT, 'pluck', 0.16, oct=12)
melody(HERO, 21.0 + BAR * 6, BEAT, 'brass', 0.07, oct=0)
add('fx', riser(1.2, 400, 5000), 33.5, 0.25)
hit(35.6, 0.6, 'F')
add('bass', tape_stop(0.7), 43.55, 0.5)
add('music', tape_stop(0.7), 43.55, 0.2)

# 44–62 Лаборатория
add('music', pad(38, 18, fc=600), 44.0, 0.09, rev=0.4)
for i in range(30):
    t0 = 48.0 + i * BEAT
    m = [62, 69, 72, 76, 74, 69, 65, 64][i % 8] + (0 if i < 16 else -2)
    add('music', pluck(mtof(m + 12), 0.8, 0.5, 0.996), t0, 0.1, pan=0.5 * np.sin(i), rev=0.6)
for t0 in (48.4, 52.2, 56.0, 59.8):
    add('music', bell(mtof(86), 2.0), t0, 0.05, pan=0.4, rev=0.7)
chord('Dm', 48.0, 7.0, 'pad', 0.03)
chord('Bb', 55.6, 6.4, 'pad', 0.03)

# 62–77.6 Кронов
for i in range(int((74.0 - 62.0) / (BEAT / 2))):
    t0 = 62.0 + i * BEAT / 2
    m = [38, 38, 38, 39, 38, 38, 36, 38][i % 8]
    add('bass', bassnote(m, 0.22, 1.2), t0, 0.4)
    if i % 4 == 0:
        add('drums', taiko(1.0, 60), t0, 0.6, rev=0.3)
    if i % 8 == 6:
        add('drums', taiko(0.8, 85), t0, 0.4, rev=0.3)
for c, t0 in (('Dm', 62.0), ('Eb', 65.8), ('Dm', 69.6)):
    chord(c, t0, 3.8, 'strings', 0.05, oct=0)
chord('Dm', 62.0, 2.0, 'brass', 0.12, oct=-12)
add('fx', riser(1.8, 300, 8000), 72.2, 0.4)
hit(74.0, 1.0, 'Eb')
groove(74.0, 75.9, prog=['Eb', 'Dm'], intensity=0.9, arp=False)
add('music', strings(86, 1.8, att=0.4), 76.0, 0.05, rev=0.6)
add('music', strings(87, 1.8, att=0.4), 76.0, 0.04, rev=0.6)
add('fx', riser(1.6, 600, 9000), 76.1, 0.3)
add('fx', impact(1.0), 77.8, 0.7)

# 83–108 Пробуждение
add('music', pad(50, 24, fc=900), 83.5, 0.06, rev=0.6)
add('music', pad(57, 20, fc=1400), 86.0, 0.04, rev=0.6)
add('music', pad(64, 14, fc=2000), 90.0, 0.03, rev=0.7)
for i, t0 in enumerate(np.arange(83.2, 96.5, 0.95 + 0.0)):
    add('drums', heartbeat(1.0), t0 + i * 0.03, 0.55)
for t0 in (90.5, 91.9, 93.3):
    rv = whoosh(1.2, True, 200)
    add('fx', rv, t0 - 0.6, 0.35, rev=0.6)
    add('music', bell(mtof(81), 2.5), t0 + 0.6, 0.06, rev=0.8)
add('fx', riser(2.6, 300, 12000), 94.0, 0.45, rev=0.3)
hit(96.65, 0.8, 'Dm')
add('music', bell(mtof(93), 3.0), 96.65, 0.1, rev=0.7)
for i in range(int((102.3 - 97.0) / (BEAT / 2))):     # напряжение на стене
    t0 = 97.0 + i * BEAT / 2
    add('music', pluck(mtof([62, 65, 62, 69, 62, 65, 70, 69][i % 8]), 0.5, 0.6, 0.993), t0, 0.12, pan=0.3 * (-1) ** i, rev=0.4)
    if i % 2 == 0:
        add('bass', sub(38, 0.3), t0, 0.35)
add('fx', riser(4.7, 200, 12000), 102.4, 0.55)
for k in range(24):
    add('drums', snare(0.2 + 0.8 * k / 23), 105.5 + k * 1.6 / 24, 0.4)

# 108.2–117.2 ПОЛЁТ — дроп
hit(108.2, 1.1, 'Dm')
groove(108.2, 116.6, prog=['Dm', 'Bb', 'F', 'C'], intensity=1.05, toms=True)
melody(HERO, 108.2, BEAT, 'brass', 0.2, oct=12)
melody([65, 69, 72, 70, 69, 67, 69, None], 108.2 + BAR * 2, BEAT, 'brass', 0.2, oct=12)
melody(HERO, 108.2, BEAT, 'strings', 0.06, oct=0)
hit(116.6, 0.9, 'F')

# 117.2–133 Мост: тревога
add('music', pad(38, 6, fc=500), 117.4, 0.1, rev=0.4)
chord('Gm', 118.0, 5.0, 'strings', 0.04, oct=0)
for i in range(int((133 - 123) / (BEAT / 2))):
    t0 = 123 + i * BEAT / 2
    add('bass', bassnote([38, 38, 41, 38, 39, 38, 36, 38][i % 8], 0.22), t0, 0.3)
    if i % 4 == 0:
        add('drums', taiko(1.0, 62), t0, 0.5, rev=0.3)
    add('drums', hat(False), t0, 0.08)
chord('Dm', 123.0, 3.8, 'strings', 0.045, oct=0)
chord('Eb', 126.8, 3.8, 'strings', 0.045, oct=0)
add('fx', impact(1.0), 129.3, 0.4)
chord('Bb', 129.3, 3.6, 'brass', 0.08, oct=0)

# 133–141 Сомнение
add('music', pad(50, 8, fc=700), 133.0, 0.06, rev=0.6)
for i, t0 in enumerate(np.arange(133.2, 139.4, 0.85)):
    add('drums', heartbeat(1.0), t0, 0.5)
melody([62, 65, 69, None, 67, 65, 64, None], 133.6, BEAT * 1.4, 'pluck', 0.14)
add('fx', riser(1.8, 300, 10000), 139.4, 0.45)
for k in range(16):
    add('drums', snare(0.2 + 0.8 * k / 15), 140.3 + k * 1.0 / 16, 0.42)

# 141.3–169 Бой
hit(141.3, 1.0, 'Dm')
groove(141.3, 156.6, prog=['Dm', 'Bb', 'Gm', 'A'], intensity=0.95, toms=True)
melody(HERO, 141.3 + BAR * 2, BEAT, 'brass', 0.12, oct=0)
for t0 in (148.4, 151.4, 153.65):
    add('music', brass(50, 0.4), t0, 0.15, rev=0.3)
    add('music', brass(62, 0.4), t0, 0.1, rev=0.3)
hit(154.6, 0.8, 'Eb')
# напряжение: держит автобус
for i, m in enumerate([62, 63, 65, 67, 68, 70]):
    add('music', strings(m, 1.2, att=0.3), 157.0 + i * 1.0, 0.07, rev=0.5)
    add('music', strings(m - 12, 1.2, att=0.3), 157.0 + i * 1.0, 0.05, rev=0.5)
groove(157.0, 163.0, prog=['Dm', 'Eb'], intensity=0.7, half=True, arp=False)
groove(163.0, 168.4, prog=['Gm', 'A'], intensity=0.95, toms=True)
melody([67, 70, 74, 73, 70, 69, 67, 69], 163.0, BEAT, 'brass', 0.13, oct=0)
add('fx', riser(1.6, 400, 12000), 166.8, 0.45)
hit(169.0, 1.4, 'Dm')
add('music', strings(74, 2.5, att=0.05), 169.0, 0.08, rev=0.7)

# 171–183 Развязка
chord('F', 171.2, 4.0, 'strings', 0.05, oct=0)
chord('C', 175.0, 4.0, 'strings', 0.05, oct=0)
chord('Dm', 179.0, 4.0, 'strings', 0.05, oct=0)
melody([69, 72, 76, 74, 72, 69], 175.5, BEAT * 1.5, 'pluck', 0.12, oct=0)

# 183–195 Кухня
for bi, c in enumerate(['F', 'Dm', 'Bb', 'C', 'F', 'Bb']):
    b0 = 183.4 + bi * BAR
    for s, idx in enumerate([0, 1, 2, 1, 0, 2, 1, 2]):
        add('music', pluck(mtof(CH[c][idx] + 12), 0.9, 0.45, 0.996), b0 + s * BEAT / 2, 0.09, pan=0.2 * (-1) ** s, rev=0.35)
    add('bass', sub(CH[c][0] - 12, BAR * 0.9), b0, 0.2)
melody([72, 74, 76, None, 77, 76, 74, 72], 189.2, BEAT, 'pluck', 0.08, oct=12)

# 195–207 Финал + логотип
groove(195.0, 203.5, prog=['F', 'C', 'Dm', 'Bb'], intensity=0.7, hats=False)
melody([65, 69, 72, 70, 69, 67, 65, 60], 195.0 + BAR, BEAT, 'brass', 0.13, oct=0)
melody([65, 69, 72, 70, 69, 67, 65, 60], 195.0 + BAR, BEAT, 'strings', 0.06, oct=12)
add('fx', riser(2.0, 300, 10000), 201.5, 0.4)
hit(203.58, 1.2, 'F')
melody([77, 81, 84, 82, 81, 79, 77, None], 203.65, BEAT / 2, 'brass', 0.12, ln=[1, 1, 1, 1, 1, 1, 5, 1])

# 207–216 Тизер
add('music', pad(26, 9, fc=300), 207.0, 0.22, rev=0.5)
add('music', pad(51, 8, fc=800), 207.5, 0.04, rev=0.7)
add('music', strings(87, 4, att=1.0), 208.0, 0.03, rev=0.8)
add('fx', impact(0.8), 208.2, 0.5)
add('fx', bell(mtof(75), 3.0), 208.25, 0.12, rev=0.8)
hit(212.6, 1.0, 'Dm')
add('fx', bell(mtof(74), 3.0), 212.6, 0.12, rev=0.8)

# ---------------- эффекты на событиях ----------------
# молнии и гром
strikes_thunder()




rain = rain_bed()
lvl = np.ones(N)
T = tt(N)
seg(16.5, 21, 0.2); seg(44, 46, 0.6); seg(48, 83, 0.12); seg(90, 96.8, 0.3); seg(183, 195, 0.25); seg(195, 216, 0.0)
add('amb', rain * lvl, 0, 0.35)
rain_r = rain_bed()
add('amb', rain_r * lvl, 0, 0.0, pan=0.6)
add('amb', rain_r * lvl * 0.35, 0.013, 1.0, pan=0.8)

# город и велосипед
add('amb', fft_filter(noise(int(23 * SR)), hi=300) * 0.4, 21, 0.25)
add('fx', ring_tone(1.6), 21.5, 0.3, pan=0.3)
for t0 in np.arange(21.0, 44.0, 0.11):
    add('fx', footstep(0.15), t0, 0.15, pan=0.1)       # стрёкот цепи
for t0, p in ((24.0, -0.7), (27.5, 0.7), (31.2, -0.6), (40.0, 0.6)):
    add('fx', whoosh(1.4, False, 300), t0, 0.35, pan=p)  # проносящиеся машины
add('fx', screech(0.9), 33.9, 0.3, pan=-0.3)
add('fx', horn(0.25), 34.25, 0.45, pan=-0.2)
add('fx', horn(0.45), 34.6, 0.45, pan=-0.2)
add('fx', whoosh(1.0, True, 300), 34.4, 0.5)
add('fx', thud(0.8), 35.6, 0.5)
add('fx', screech(0.8), 45.0, 0.3, pan=0.4)               # тормоз у башни
for t0 in np.arange(46.0, 48.0, 0.32):
    add('fx', footstep(0.6), t0, 0.3)

# лаборатория
add('fx', bell(mtof(88), 1.2), 47.9, 0.12, rev=0.5)       # «динь» лифта
add('fx', whoosh(0.8, True, 200), 48.0, 0.3)
add('amb', np.sin(2 * np.pi * 60 * tt(int(34 * SR))) * 0.15 + fft_filter(noise(int(34 * SR)), lo=2000, hi=5000) * 0.02, 48.0, 0.4)
for t0 in np.arange(48.6, 51.5, 0.55):
    add('fx', footstep(0.5), t0, 0.25)
add('fx', servo(0.6, 500, 1200), 57.2, 0.2, pan=0.2)
add('fx', impact(1.0, metal=1.0), 62.0, 0.8, rev=0.4)
add('fx', glass(0.4, 1.0), 62.05, 0.4)
for t0 in np.arange(62.6, 66.1, 0.72):
    add('fx', stomp(), t0, 0.55, rev=0.2)
    add('fx', servo(0.35, 250, 500), t0 + 0.1, 0.12)
add('fx', siren(18, 500, 600, 1.0), 62.4, 0.06, pan=0.5)
add('fx', impact(1.0, metal=1.2), 73.35, 0.7, rev=0.3)
add('fx', zap(1.2), 73.5, 0.3)
add('fx', zap(2.0), 74.05, 0.4)
add('fx', glass(1.0, 2.0), 74.3, 0.7, rev=0.4)
add('fx', servo(0.4, 1500, 3000), 75.6, 0.15)
add('fx', zap(0.6), 77.8, 0.45)
add('fx', splat(), 77.8, 0.4)
add('fx', tinnitus(4.0), 79.2, 0.06)
add('fx', glass(0.8, 1.5), 81.8, 0.5)
add('fx', whoosh(1.0, False), 81.9, 0.35)

# пробуждение и полёт
add('fx', whoosh(2.0, True, 150), 96.0, 0.3)
for t0 in (98.0, 99.2, 100.6):
    add('fx', splat() * 0.3, t0, 0.2)
add('fx', scrape(0.5), 102.2, 0.3)
add('fx', riser(4.5, 300, 4000), 102.5, 0.4)       # ветер падения
add('fx', thwip(), 107.15, 0.75, rev=0.2)
add('fx', splat(), 107.42, 0.3)
for t0, p in ((108.4, -0.5), (109.6, 0.5), (110.8, -0.3), (113.0, 0.4), (114.4, -0.4)):
    add('fx', whoosh(0.9, True, 300), t0, 0.45, pan=p)
add('fx', thwip(), 112.35, 0.6)
add('fx', thud(1.0), 116.6, 0.55)

# мост


add('amb', walla(6.0, 0.9, 1), 122.2, 0.06, pan=-0.3, rev=0.3)                    # люди бегут, кричат
add('amb', walla(14.0, 0.3, 2), 128.0, 0.025, pan=0.4, rev=0.5)                     # зеваки вдалеке
add('fx', screech(1.1), 165.4, 0.12, pan=-0.5, rev=0.2)                              # полиция тормозит на мосту
for t0, p in ((166.55, -0.5), (166.85, -0.3), (166.75, -0.6)):
    add('fx', thud(0.5), t0, 0.12, pan=p, rev=0.3)                                   # хлопают двери
cheer = walla(4.5, 1.4, 3)
for k in range(46):
    i = int((0.1 + rs.random() * 3.6) * SR); c = clap()[:len(cheer) - i]; cheer[i:i + len(c)] += c * (0.6 + rs.random() * 0.6)
add('amb', cheer, 174.2, 0.07, pan=0.2, rev=0.4)                                     # толпа ликует: автобус спасён
add('amb', siren(52, 600, 900, 0.3) * 0.5 + siren(52, 700, 1000, 0.42) * 0.4, 121.0, 0.07, pan=-0.4, rev=0.4)
for t0 in (124.5, 131.5, 146.0, 158.5, 161.5, 172.0):
    add('fx', metal_groan(2.2, 60 + 20 * rs.random()), t0, 0.25, rev=0.3)
add('fx', impact(1.0, metal=1.0), 125.7, 0.6)
add('fx', whoosh(0.8, True), 129.3, 0.4)
add('fx', whoosh(1.0, True, 250), 140.2, 0.5)
add('fx', impact(1.0), 141.3, 0.7)
for t0 in np.arange(141.6, 145.6, 0.9):
    add('fx', stomp(), t0, 0.45); add('fx', servo(0.35, 250, 500), t0 + .1, 0.1)
add('fx', thwip(), 148.3, 0.6); add('fx', splat(), 148.5, 0.5)
add('fx', scrape(0.35), 150.3, 0.35); add('fx', splat(), 150.32, 0.3)               # Кронов срывает паутину с визора
add('fx', servo(0.3, 300, 120), 151.05, 0.2)                                          # замах
add('fx', whoosh(0.5, True, 250), 151.3, 0.5)
add('fx', whoosh(1.2, False, 200), 151.5, 0.3)                                        # кулак в слоу-мо над головой
add('fx', whoosh(0.8, True), 152.4, 0.4)
add('fx', whoosh(0.35, True, 500), 153.2, 0.35)                                       # прыжок
add('fx', impact(1.0), 153.65, 0.8); add('fx', boom(1.2, 0.8), 153.65, 0.35)          # удар двумя ногами в ядро
add('fx', bell(1568, 1.2) + bell(2093, 1.2) * .5, 153.72, 0.18, pan=0.3)              # «ДЗЫНЬ!» — ядро вылетает
add('fx', scrape(0.9), 153.75, 0.4, pan=0.2)                                          # ступни Кронова скребут асфальт
add('fx', whoosh(0.5, False, 300), 153.7, 0.3)                                        # сальто Тимура
add('fx', impact(1.0, metal=1.5), 154.6, 0.85); add('fx', glass(0.8), 154.65, 0.35)  # Кронов врезается в автобус
add('fx', scrape(2.0), 154.7, 0.5)
add('fx', thwip(), 155.35, 0.55); add('fx', whoosh(1.0, True, 220), 155.5, 0.45)     # рывок на нити к автобусу
for t0 in np.arange(163.55, 164.4, 0.28):
    add('fx', stomp(0.8), t0, 0.4)                                                    # Кронов бросается на Тимура
add('fx', thwip(), 157.1, 0.6); add('fx', thwip(), 157.2, 0.5)
add('fx', metal_groan(5.5, 90), 157.4, 0.25)
for t0 in (160.5, 160.7, 164.5, 165.8, 165.95, 166.1, 166.25, 166.4, 166.55):
    add('fx', thwip(), t0, 0.4, pan=rs.uniform(-.4, .4))
add('fx', whoosh(1.0, True, 200), 164.6, 0.5)
add('fx', impact(1.0, metal=1.5), 165.6, 0.7)
add('fx', zap(2.2), 169.05, 0.6)
add('fx', servo(1.2, 900, 60), 170.3, 0.3)
add('fx', scrape(3.0), 171.0, 0.35)
add('fx', thud(1.2), 174.05, 0.7)
add('fx', whoosh(0.6, False, 300), 175.3, 0.2)
add('fx', servo(0.5, 200, 120), 175.3, 0.12)   # пневматика двери
for t0 in np.arange(175.5, 176.7, 0.45):
    add('fx', footstep(0.6), t0, 0.3)
add('fx', thwip(), 181.45, 0.5)
add('fx', whoosh(0.9, True), 181.5, 0.4)

# кухня
add('fx', footstep(1.0), 183.1, 0.5)
for t0 in np.arange(183.3, 185.6, 0.5):
    add('fx', footstep(0.7), t0, 0.3)
add('fx', scrape(0.4), 186.6, 0.15)
add('fx', scrape(0.6) * 0.5, 189.8, 0.15)
for t0 in np.arange(183.0, 195.0, 1.0):
    add('fx', bell(2400, 0.05) * 0.3, t0, 0.05, pan=-0.6)   # часы
add('amb', fft_filter(noise(int(12 * SR)), lo=300, hi=1200) * 0.05, 183.0, 0.5)    # кипит чайник

# финал: ветер на шпиле
add('amb', tv_band(noise(int(8 * SR)), lambda s: 400 + 300 * np.sin(s * 0.9), bw=0.8) * 0.6, 195.0, 0.35)
add('amb', fft_filter(noise(int(9 * SR)), hi=120) * 0.3, 207.0, 0.4)      # гул логова
