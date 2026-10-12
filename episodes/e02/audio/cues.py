"""Партитура серии 2 «Сигнал»: музыка по сценам, шумы и эффекты на событиях.
Выполняется внутри engine/audio/mix.py — доступны все инструменты движка (groove, melody, chord, hit,
add, whoosh, impact, thwip, rain_bed, seg, strikes_thunder…). Время — сюжетное (как в shots.js).
"""

# 0–16 Логово Тени
add('music', pad(26, 16, fc=300), 0.0, 0.2, rev=0.5)
add('music', pad(51, 14, fc=800), 0.8, 0.04, rev=0.7)
add('fx', bell(mtof(75), 3.0), 0.9, 0.12, rev=0.8)
add('fx', bell(mtof(75), 3.0), 6.3, 0.09, rev=0.8)
add('music', strings(87, 5, att=1.2), 6.0, 0.03, rev=0.8)
for i in range(40):                                   # стрёкот лапок дронов
    add('fx', footstep(0.25) * 0.6, 11.6 + i * 0.07 + 0.02 * np.sin(i * 7), 0.12, pan=0.6 * np.sin(i * 1.7))
add('fx', impact(0.8), 14.6, 0.5)
add('fx', riser(1.6, 250, 9000), 14.4, 0.35)

# 16.5–21 Заставка
hit(16.6, 1.1)
melody([74, 77, 81, 79, 77, 76, 74, None], 16.7, BEAT / 2, 'brass', 0.15, ln=[1, 1, 1, 1, 1, 1, 4, 1])
melody([74, 77, 81, 79, 77, 76, 74, None], 16.7, BEAT / 2, 'brass', 0.09, oct=-12, ln=[1, 1, 1, 1, 1, 1, 4, 1])

# 20.5–48 Кухня: тёплый щипковый мотив
for bi, c in enumerate(['F', 'Dm', 'Bb', 'C', 'F', 'Dm', 'Bb', 'C', 'F', 'Bb', 'C', 'F', 'F']):
    b0 = 20.6 + bi * BAR
    if b0 > 47.5:
        break
    for s, idx in enumerate([0, 1, 2, 1, 0, 2, 1, 2]):
        add('music', pluck(mtof(CH[c][idx] + 12), 0.9, 0.45, 0.996), b0 + s * BEAT / 2, 0.075, pan=0.2 * (-1) ** s, rev=0.35)
    add('bass', sub(CH[c][0] - 12, BAR * 0.9), b0, 0.16)
melody([72, 74, 76, None, 77, 76, 74, 72], 41.6, BEAT, 'pluck', 0.08, oct=12)
for t0 in np.arange(23.0, 31.0, 0.6):                 # ложка о тарелку
    add('fx', bell(2600, 0.06) * 0.25, t0 + 0.05 * np.sin(t0 * 9), 0.05, pan=0.2)
for t0 in np.arange(20.5, 48.0, 1.0):
    add('fx', bell(2400, 0.05) * 0.3, t0, 0.04, pan=-0.6)   # часы
add('fx', footstep(0.7), 39.6, 0.3); add('fx', footstep(0.7), 40.1, 0.3)

# 48–64 Полёт над проспектом
groove(48.4, 56.4, intensity=0.8)
melody(HERO, 48.4, BEAT, 'pluck', 0.15, oct=12)
for t0, p in ((48.6, -0.4), (51.0, 0.4), (53.4, -0.3)):
    add('fx', thwip(), t0, 0.45, pan=p); add('fx', whoosh(1.4, True, 300), t0 + 0.2, 0.35, pan=-p)
add('fx', thwip(), 56.4, 0.4)
add('fx', zap(0.4), 56.9, 0.25)                        # нить «чихает»
add('fx', tape_stop(0.7), 57.2, 0.4)
add('music', tape_stop(0.7), 57.2, 0.15)
add('fx', whoosh(1.0, False, 300), 57.6, 0.4)
add('fx', impact(1.0, metal=0.6), 59.4, 0.7); add('fx', scrape(1.2), 59.6, 0.35)
add('music', brass(38, 0.5), 60.3, 0.12)              # «пук» тубы — смешной стоп-кадр
add('fx', thud(0.6), 66.6, 0.15)                       # урчит живот (низкий гул)
add('fx', ring_tone(1.6), 72.2, 0.3, pan=0.3)          # телефон
groove(64.0, 78.0, prog=['Dm', 'Bb'], intensity=0.45, hats=True, arp=False, half=True)

# 78–96 Лаборатория: радар
add('music', pad(38, 18, fc=600), 78.0, 0.08, rev=0.4)
for i in range(32):
    t0 = 78.4 + i * BEAT / 2
    m = [62, 69, 72, 76, 74, 69, 65, 64][i % 8]
    add('music', pluck(mtof(m + 12), 0.7, 0.5, 0.996), t0, 0.08, pan=0.5 * np.sin(i), rev=0.6)
for t0 in np.arange(78.6, 95.0, 1.2):
    add('fx', bell(1760, 0.12) * 0.4, t0, 0.06, pan=0.3)   # «пинг» радара
chord('Eb', 85.0, 6.0, 'strings', 0.045, oct=0)
add('fx', riser(2.0, 300, 9000), 94.0, 0.35)

# 96–150 Крыша: чутьё, дроны, бой
hit(96.5, 0.7, 'Dm')
for i, t0 in enumerate(np.arange(97.2, 103.8, 0.8)):
    add('drums', heartbeat(1.0), t0, 0.5)
add('fx', tinnitus(2.5), 98.4, 0.04)
for i in range(30):                                    # дроны лезут через край
    add('fx', footstep(0.25) * 0.6, 102.6 + i * 0.08, 0.14, pan=-0.4 + 0.03 * i)
add('fx', servo(0.6, 900, 300), 104.8, 0.2)
hit(108.0, 0.9, 'Gm')
groove(108.0, 135.0, prog=['Dm', 'Bb', 'Gm', 'A'], intensity=0.95, toms=True)
melody(HERO, 108.0 + BAR * 2, BEAT, 'brass', 0.11, oct=0)
add('fx', whoosh(0.8, True), 110.4, 0.4)              # прыжок дрона
add('fx', thwip(), 111.6, 0.55); add('fx', splat(), 111.8, 0.45)
add('fx', impact(0.8, metal=1.0), 112.0, 0.5)
add('fx', thwip(), 116.4, 0.5); add('fx', thwip(), 116.5, 0.5)
add('fx', whoosh(0.6, False, 300), 117.4, 0.4)
add('fx', impact(1.0, metal=1.5), 118.2, 0.8); add('fx', glass(0.5, 1.0), 118.25, 0.3)   # «БДЫЩ!»
add('fx', zap(1.2), 118.4, 0.3)
add('fx', servo(0.4, 400, 1300), 124.5, 0.2)
add('fx', whoosh(0.5, True, 400), 129.0, 0.35)
add('fx', impact(1.0), 130.0, 0.6)
add('music', pad(26, 10, fc=300), 135.0, 0.14, rev=0.5)
add('fx', bell(mtof(75), 3.0), 136.3, 0.1, rev=0.8)
add('fx', whoosh(0.5, True, 300), 143.6, 0.35)
add('fx', impact(1.0, metal=1.2), 144.1, 0.75); add('fx', zap(1.0), 144.2, 0.3)
add('fx', whoosh(1.4, False, 200), 144.4, 0.3)
add('fx', thwip(), 147.2, 0.5); add('fx', whoosh(1.5, True, 250), 147.4, 0.45)

# 150–186 Лаборатория: напарница
add('fx', glass(0.3, 1.2), 150.6, 0.3)
add('fx', footstep(0.5), 151.4, 0.25); add('fx', footstep(0.5), 151.9, 0.25)
add('music', pad(50, 14, fc=900), 152.0, 0.06, rev=0.6)
for c, t0 in (('Dm', 152.0), ('Bb', 158.0), ('F', 164.0), ('C', 170.0)):
    chord(c, t0, 6.0, 'strings', 0.035, oct=0)
add('fx', servo(0.3, 2000, 3500), 178.2, 0.15)       # щелчок глушилки
add('fx', zap(0.6), 178.5, 0.25)
add('fx', riser(1.5, 400, 10000), 177.2, 0.3)
add('music', bell(mtof(86), 2.5), 178.6, 0.12, rev=0.7)
melody([65, 69, 72, 70, 69, 67, 65, 60], 179.0, BEAT, 'strings', 0.07, oct=12)
melody([65, 69, 72, 70, 69, 67, 65, 60], 179.0, BEAT, 'pluck', 0.1, oct=0)

# 186–206 Дроны в лаборатории
add('fx', glass(1.0, 1.6), 186.4, 0.6, rev=0.3)
add('fx', siren(10, 500, 600, 1.0), 186.6, 0.05, pan=0.5)
hit(187.6, 0.8, 'Dm')
groove(188.0, 204.0, prog=['Dm', 'Eb'], intensity=0.85, toms=True, arp=False)
add('fx', thwip(), 191.6, 0.5); add('fx', thwip(), 191.75, 0.5)
add('fx', impact(0.8, metal=1.0), 192.4, 0.5); add('fx', impact(0.8, metal=1.0), 192.6, 0.45)
add('fx', whoosh(0.5, True, 400), 195.6, 0.35)
add('fx', impact(1.0, metal=1.3), 196.2, 0.75); add('fx', zap(1.4), 196.3, 0.35)
add('fx', servo(1.2, 900, 60), 197.0, 0.25)            # дрон «гаснет»
hit(204.0, 0.6, 'F')

# 206–222 Дом
for bi, c in enumerate(['F', 'Dm', 'Bb', 'C']):
    b0 = 206.4 + bi * BAR
    for s, idx in enumerate([0, 1, 2, 1, 0, 2, 1, 2]):
        add('music', pluck(mtof(CH[c][idx] + 12), 0.9, 0.45, 0.996), b0 + s * BEAT / 2, 0.075, pan=0.2 * (-1) ** s, rev=0.35)
    add('bass', sub(CH[c][0] - 12, BAR * 0.9), b0, 0.14)
melody([65, 69, 72, 70, 69, 67, 65, None], 214.0, BEAT, 'pluck', 0.08, oct=12)
for t0 in np.arange(206.0, 222.0, 1.0):
    add('fx', bell(2400, 0.05) * 0.3, t0, 0.04, pan=-0.6)

# 222–236 Логотип и тизер
hit(222.3, 1.1, 'F')
melody([77, 81, 84, 82, 81, 79, 77, None], 222.4, BEAT / 2, 'brass', 0.11, ln=[1, 1, 1, 1, 1, 1, 5, 1])
add('music', pad(26, 10, fc=300), 226.0, 0.22, rev=0.5)
add('music', strings(87, 4, att=1.0), 226.6, 0.03, rev=0.8)
add('fx', impact(0.8), 227.0, 0.5)
add('fx', bell(mtof(75), 3.0), 227.05, 0.12, rev=0.8)
hit(232.4, 1.0, 'Dm')
add('fx', bell(mtof(74), 3.0), 232.4, 0.12, rev=0.8)

# ---------------- эффекты окружения ----------------
strikes_thunder()
rain = rain_bed()
lvl = np.ones(N)
T = tt(N)
seg(0, 16.5, 0.0); seg(16.5, 20.5, 0.2); seg(20.5, 48, 0.3); seg(78, 96, 0.12); seg(150, 206, 0.15)
seg(206, 222, 0.3); seg(222, 236, 0.0)
add('amb', rain * lvl, 0, 0.35)
rain_r = rain_bed()
add('amb', rain_r * lvl * 0.35, 0.013, 1.0, pan=0.8)
add('amb', fft_filter(noise(int(16 * SR)), hi=120) * 0.3, 0.0, 0.4)          # гул логова
add('amb', fft_filter(noise(int(30 * SR)), hi=300) * 0.4, 48.0, 0.2)         # город
add('amb', np.sin(2 * np.pi * 60 * tt(int(18 * SR))) * 0.12, 78.0, 0.35)     # гул приборов в лаборатории
add('amb', np.sin(2 * np.pi * 60 * tt(int(56 * SR))) * 0.1, 150.0, 0.3)
add('amb', fft_filter(noise(int(10 * SR)), hi=120) * 0.3, 226.0, 0.4)
