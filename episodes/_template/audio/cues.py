"""Партитура серии «__TITLE__» (заготовка). Выполняется внутри engine/audio/mix.py: доступны все инструменты
движка — groove, melody, chord, hit, pad, pluck, brass, strings, bell, add, whoosh, impact, thwip, splat, zap…
Время — сюжетное (как в shots.js). Примеры приёмов — episodes/e01/audio/cues.py и episodes/e02/audio/cues.py.
"""
# логово: низкий дрон и колокол
add('music', pad(26, 12, fc=300), 0.0, 0.2, rev=0.5)
add('fx', bell(mtof(75), 3.0), 1.0, 0.12, rev=0.8)
# заставка: удар и тема героя на меди
hit(12.1, 1.1)
melody([74, 77, 81, 79, 77, 76, 74, None], 12.2, BEAT / 2, 'brass', 0.15, ln=[1, 1, 1, 1, 1, 1, 4, 1])
# город: бит и тема героя
groove(16.0, 30.0, intensity=0.85)
melody(HERO, 16.0 + BAR, BEAT, 'pluck', 0.14, oct=12)
add('fx', impact(1.0), 16.2, 0.6)
# кухня: тёплый мотив
for bi, c in enumerate(['F', 'Dm', 'Bb', 'C', 'F', 'Bb']):
    b0 = 30.0 + bi * BAR
    for s, idx in enumerate([0, 1, 2, 1, 0, 2, 1, 2]):
        add('music', pluck(mtof(CH[c][idx] + 12), 0.9, 0.45, 0.996), b0 + s * BEAT / 2, 0.075, pan=0.2 * (-1) ** s, rev=0.35)
# логотип
hit(42.1, 1.1, 'F')

# окружение: гром на молниях из timeline.json, дождь (тише в помещениях)
strikes_thunder()
rain = rain_bed()
lvl = np.ones(N)
T = tt(N)
seg(0, 12, 0.0); seg(30, 42, 0.3); seg(42, 48, 0.0)
add('amb', rain * lvl, 0, 0.35)
