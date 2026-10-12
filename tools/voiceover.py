"""Лист озвучки серии из dialogue.json: python3 tools/voiceover.py e02 → episodes/e02/VOICEOVER.md
Для каждой реплики — номер, время, персонаж, текст, максимальная длина и подсказка (поле "hint")."""
import json
import os
import sys

STUDIO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WHO = {'timur': 'Тимур', 'narrator': 'Рассказчик', 'ded': 'Дед Рустам', 'vera': 'Вера Лис', 'kronov': 'Кронов',
       'shadow': 'Тень', 'crowd': 'Толпа', 'news': 'Новости (ТВ)', 'drone': 'Дрон (голос Тени)', 'sokol': 'Майор Сокол', 'mgla': 'Мгла', 'diyor': 'Диёр', 'marjon': 'Маржон', 'azim': 'Азим «Флэш»', 'teacher': 'Учительница', 'mom': 'Мама Маржон', 'odilman': 'ODILMAN'}
FX = {'phone': 'телефонный фильтр', 'memory': 'эхо воспоминания', 'radio': 'рация/динамик', 'tv': 'звук из телевизора', 'mask': 'голос из-под маски'}


def main():
    ep = sys.argv[1] if len(sys.argv) > 1 else json.load(open(os.path.join(STUDIO, 'episodes', 'index.json')))['default']
    d = os.path.join(STUDIO, 'episodes', ep)
    title = next((e['title'] for e in json.load(open(os.path.join(STUDIO, 'episodes', 'index.json')))['episodes'] if e['id'] == ep), ep)
    lines = sorted(json.load(open(os.path.join(d, 'dialogue.json'), encoding='utf-8'))['lines'], key=lambda l: l['t'])
    out = [f'# Озвучка — «Паук Новограда», {title}', '',
           'Все реплики серии по порядку: номер, время в серии, персонаж, текст, **максимальная длина** (дольше —',
           'не влезет до следующей реплики) и подсказка, как играть.', '',
           '## Как записывать (самый простой способ)', '',
           '1. Запишите **все реплики подряд одной записью** — по порядку этой таблицы, между репликами пауза 1–2 секунды.',
           '   Дубль не получился — просто скажите реплику ещё раз: лишние дубли программа выбросит сама.',
           f'2. Положите файл в `episodes/{ep}/audio/voice_src/` (любой формат: mp3, m4a с телефона, wav…).',
           f'3. Запустите `tools/audio.sh {ep}` — запись нарежется на реплики, получит обработку и липсинк.',
           '   Если какая-то реплика нарезалась неверно — поправьте раскладку в `<запись>.map.json`',
           '   (`{"t5": [12, 13]}` — реплика t5 = участки речи 12–13; номера участков печатает нарезчик).', '',
           f'Можно и по одной реплике: файл с именем номера (`t1.m4a`, `v3.wav`…) в `episodes/{ep}/audio/voice_user/`.',
           'Голос не обрабатывайте — эффекты (телефон, эхо, рация, шлем) наложатся сами. Реплики без записи',
           'останутся синтезированными.', '', '## Реплики', '',
           '| Файл | Время | Кто | Текст | Макс. | Как играть |', '|---|---|---|---|---|---|']
    for i, l in enumerate(lines):
        nxt = lines[i + 1]['t'] if i + 1 < len(lines) else l['t'] + 8
        mx = max(.8, nxt - l['t'] - .15)
        m, s = divmod(l['t'], 60)
        fx = f" ({FX[l['fx']]})" if l.get('fx') in FX else ''
        out.append(f"| `{l['id']}` | {int(m)}:{s:04.1f} | {WHO.get(l['who'], l['who'])} | {l['text']} | {mx:.1f} с | {l.get('hint', '')}{fx} |")
    open(os.path.join(d, 'VOICEOVER.md'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print('готово:', os.path.join(d, 'VOICEOVER.md'))


if __name__ == '__main__':
    main()
