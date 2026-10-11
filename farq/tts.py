"""Озвучка ролика и таймлайн.

Читает script.json, синтезирует каждую реплику, раскладывает их по сетке 120 BPM
(начала сцен — на долях) и пишет:
  out/voice.wav   — дорожка голоса 48 кГц, моно, обработанная
  timeline.js     — window.TL: тексты, время сцен и каждого слова (для motion.js и music.py)
  out/timeline.json — то же для music.py

Движки:
  edge   — нейроголос Microsoft uz-UZ-SardorNeural (нужен доступ к speech.platform.bing.com)
  mbrola — офлайн: espeak-ng + MBROLA tr1; узбекская латиница переводится в турецкую
           орфографию, у которой близкое произношение (sh→ş, ch→ç, j→c, q→k, x→h …)
По умолчанию пробуется edge, при ошибке — mbrola.

    python3 tts.py [--engine edge|mbrola]
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 48000
BEAT = 0.5
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
TMP = tempfile.mkdtemp(prefix='farq-tts-')
EDGE_VOICE = 'uz-UZ-SardorNeural'
RATE = '160'


def arg(k, d=None):
    return sys.argv[sys.argv.index('--' + k) + 1] if '--' + k in sys.argv else d


# ---------- текст ----------
APOS = '‘’ʻʼ\'`'


def words_of(text):
    """Слова для караоке: как написаны на экране (тире выбрасываем)."""
    return [w for w in text.replace('—', ' ').split() if re.search(r'\w', w)]


def norm(w):
    return re.sub(r"[^\w‘’ʻʼ']", '', w.lower()).replace('’', '‘')


def find_keys(words, keys):
    """Индексы слов каждой ключевой фразы в определении: [[i, j, ...], ...]."""
    nw = [norm(w) for w in words]
    out = []
    for k in keys:
        kw = [norm(x) for x in k.split()]
        hit = next((i for i in range(len(nw) - len(kw) + 1) if nw[i:i + len(kw)] == kw), None)
        if hit is None:
            raise SystemExit(f'ключ «{k}» не найден в определении')
        out.append(list(range(hit, hit + len(kw))))
    return out


def uz_to_tr(text):
    """Узбекская латиница → турецкая орфография для MBROLA tr1."""
    s = text.replace('—', ',').lower()
    s = re.sub('([og])[' + APOS + ']', r'\1', s)        # o‘ → o, g‘ → g
    s = re.sub('[' + APOS + ']', '', s)                 # тутуқ белгиси
    for a, b in (('sh', 'ş'), ('ch', 'ç'), ('ng', 'ng'), ('j', 'c'), ('q', 'k'), ('x', 'h'), ('w', 'v')):
        s = s.replace(a, b)
    return s


# ---------- синтез ----------
def read_wav(path):
    with wave.open(path) as w:
        sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
        x = np.frombuffer(w.readframes(n), '<i2').astype(np.float64) / 32768
    if ch > 1:
        x = x.reshape(-1, ch).mean(1)
    return x, sr


def to48k(src, dst, af=None):
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-ac', '1', '-ar', str(SR)]
    if af:
        cmd += ['-af', af]
    subprocess.run(cmd + [dst], check=True)
    return read_wav(dst)[0]


def synth_mbrola(text, name):
    """espeak-ng строит фонемы и интонацию, MBROLA tr1 звучит.

    В базе дифонов tr1 нет «тёмного» и сдвоенного L (L/, l/, L) — MBROLA заменил бы их
    тишиной, поэтому все варианты сводим к обычному l."""
    pho = subprocess.run(['espeak-ng', '-v', 'mb-tr1', '-q', '--pho', '-s', RATE, '-p', '46', uz_to_tr(text)],
                         check=True, capture_output=True, text=True).stdout
    pho = re.sub(r'^(L/|l/|L)(?=\t)', 'l', pho, flags=re.M)
    pf = os.path.join(TMP, name + '.pho')
    open(pf, 'w').write(pho)
    raw = os.path.join(TMP, name + '.raw.wav')
    subprocess.run(['mbrola', '-e', '/usr/share/mbrola/tr1/tr1', pf, raw], check=True, capture_output=True)
    return to48k(raw, os.path.join(TMP, name + '.wav'))


def synth_edge(text, name):
    mp3 = os.path.join(TMP, name + '.mp3')
    subprocess.run(['edge-tts', '--voice', EDGE_VOICE, '--rate', '+6%', '--text', text, '--write-media', mp3],
                   check=True, capture_output=True, timeout=60)
    return to48k(mp3, os.path.join(TMP, name + '.wav'))


def trim(x, thr=0.012):
    """Срезает тишину по краям, оставляя 20 мс воздуха."""
    idx = np.nonzero(np.abs(x) > thr)[0]
    if not len(idx):
        return x
    a, b = max(0, idx[0] - int(0.02 * SR)), min(len(x), idx[-1] + int(0.06 * SR))
    return x[a:b]


def word_times(x, words, synth, name, text):
    """Время слов внутри реплики.

    Делим реплику по паузам (запятые, тире) на фразы, внутри фразы распределяем время
    пропорционально длине слов, синтезированных по отдельности."""
    weights = []
    for i, w in enumerate(words):
        if ENGINE == 'mbrola':
            weights.append(len(trim(synth(w, f'{name}_w{i}'))) / SR)
        else:
            weights.append(0.06 * len(re.sub(r'\W', '', w)) + 0.08)
    # паузы в сигнале: огибающая 20 мс, тишина длиннее 110 мс
    hop = int(0.01 * SR)
    env = np.array([np.sqrt(np.mean(x[i:i + 2 * hop] ** 2)) for i in range(0, len(x) - 2 * hop, hop)])
    quiet = env < max(0.01, env.max() * 0.06)
    gaps, i = [], 0
    while i < len(quiet):
        if quiet[i]:
            j = i
            while j < len(quiet) and quiet[j]:
                j += 1
            if (j - i) * 0.01 >= 0.11 and i > 0 and j < len(quiet):
                gaps.append(((i + 1) * 0.01, (j + 1) * 0.01))
            i = j
        else:
            i += 1
    # фразы по пунктуации: конец фразы — слово с запятой или слово перед тире
    toks = text.split()
    ends = set()
    k = -1
    for tk in toks:
        if tk == '—':
            ends.add(k)
            continue
        if re.search(r'\w', tk):
            k += 1
            if re.search(r'[,;:]$', tk):
                ends.add(k)
    groups, cur = [], []
    for k in range(len(words)):
        cur.append(k)
        if k in ends and k < len(words) - 1:
            groups.append(cur)
            cur = []
    groups.append(cur)
    dur = len(x) / SR
    # каждому стыку фраз — ближайшая к ожидаемому месту пауза
    tot = sum(weights)
    spans, a, ok = [], 0.0, True
    acc = 0.0
    free = list(gaps)
    for g in groups[:-1]:
        acc += sum(weights[k] for k in g)
        want = dur * acc / tot
        cand = [p for p in free if p[0] > a]
        if not cand:
            ok = False
            break
        p = min(cand, key=lambda p: abs((p[0] + p[1]) / 2 - want))
        if abs((p[0] + p[1]) / 2 - want) > 0.9:
            ok = False
            break
        free = [q for q in free if q[0] > p[1]]
        spans.append((a, p[0]))
        a = p[1]
    spans.append((a, dur))
    if not ok:
        groups, spans = [list(range(len(words)))], [(0.0, dur)]
    out = [None] * len(words)
    for g, (a, b) in zip(groups, spans):
        tot = sum(weights[k] for k in g)
        t = a
        for k in g:
            d = (b - a) * weights[k] / tot
            out[k] = [round(t, 3), round(t + d, 3)]
            t += d
    return out


ENGINE = arg('engine')


def pick_engine():
    global ENGINE
    if ENGINE:
        return
    try:
        synth_edge('Salom', 'probe')
        ENGINE = 'edge'
    except Exception:
        ENGINE = 'mbrola'


def snap(t):
    return np.ceil(t / BEAT - 1e-6) * BEAT


def main():
    pick_engine()
    synth = synth_edge if ENGINE == 'edge' else synth_mbrola
    print('движок:', ENGINE)
    S = json.load(open(os.path.join(HERE, 'script.json'), encoding='utf-8'))
    clips = []          # (t0, signal)
    n = [0]

    def say(text, t0):
        n[0] += 1
        name = f'l{n[0]:02d}'
        x = trim(synth(text, name))
        ws = words_of(text)
        wt = word_times(x, ws, synth, name, text)
        clips.append((t0, x))
        d = len(x) / SR
        return {'text': text, 't0': round(t0, 3), 't1': round(t0 + d, 3),
                'words': [{'w': w, 't0': round(t0 + a, 3), 't1': round(t0 + b, 3)} for w, (a, b) in zip(ws, wt)]}

    tl = {'engine': ENGINE, 'title': S['title'], 'scenes': []}
    # — интро: удар на 0, голос с 0,9 с —
    t = 0.9
    lines = []
    for s in S['intro']:
        ln = say(s, t)
        lines.append(ln)
        t = ln['t1'] + 0.3
    end = snap(lines[-1]['t1'] + 0.7)
    tl['scenes'].append({'type': 'intro', 't0': 0.0, 't1': end, 'lines': lines})
    t = end
    # — пары —
    for pi, p in enumerate(S['pairs']):
        sc = {'type': 'pair', 'i': pi, 't0': t, 'colors': p['colors']}
        sc['q'] = say(p['q'], t + 0.75)                    # слова сталкиваются на доле, голос — следом
        ta = snap(sc['q']['t1'] + 0.55)
        for key in ('a', 'b'):
            c = p[key]
            tv = ta + 0.45                                  # карточка влетает, потом звучит голос
            ln = say(c['term'] + ' — ' + c['def'], tv)
            ki = find_keys(words_of(c['def']), c['keys'])
            dw = ln['words'][1:]                            # первое слово реплики — сам термин
            sc[key] = {'t0': ta, 'term': c['term'], 'icon': c['icon'], 'def': c['def'],
                       'keys': ki, 'kt': [dw[k[0]]['t0'] for k in ki], 'chips': c['chips'], 'line': ln}
            ta = snap(ln['t1'] + 0.6)
        sc['sum'] = ta                                      # итоговое сравнение, без голоса
        sc['t1'] = ta + 3.5
        tl['scenes'].append(sc)
        t = sc['t1']
    # — финал —
    lines = []
    tt = t + 0.6
    for s in S['outro']:
        ln = say(s, tt)
        lines.append(ln)
        tt = ln['t1'] + 0.35
    tl['scenes'].append({'type': 'outro', 't0': t, 't1': snap(lines[-1]['t1'] + 2.2), 'lines': lines})
    tl['duration'] = tl['scenes'][-1]['t1']

    # — сведение голоса —
    N = int((tl['duration'] + 1) * SR)
    v = np.zeros(N)
    for t0, x in clips:
        i = int(round(t0 * SR))
        v[i:i + len(x)] += x[:N - i]
    os.makedirs(OUT, exist_ok=True)
    dry = os.path.join(TMP, 'voice_dry.wav')
    with wave.open(dry, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(v / (np.abs(v).max() + 1e-9) * 0.9, -1, 1) * 32767).astype('<i2').tobytes())
    if ENGINE == 'mbrola':
        # MBROLA звучит на 16 кГц: убираем гул, добавляем присутствие и «воздух», компрессия, маленькая комната
        af = ('highpass=f=85,equalizer=f=180:t=q:w=1:g=2,equalizer=f=420:t=q:w=1.4:g=-3,'
              'equalizer=f=2600:t=q:w=1.2:g=4,aexciter=amount=2.5:drive=6:blend=0:freq=5200:ceil=16000,'
              'deesser=i=0.4,acompressor=threshold=-22dB:ratio=3.5:attack=4:release=90:makeup=5,'
              'aecho=0.9:0.6:23|41:0.10|0.06')
    else:
        af = 'highpass=f=70,acompressor=threshold=-20dB:ratio=2.5:attack=5:release=100:makeup=3'
    to48k(dry, os.path.join(OUT, 'voice.wav'), af)

    js = json.dumps(tl, ensure_ascii=False, indent=1)
    open(os.path.join(HERE, 'timeline.js'), 'w', encoding='utf-8').write('window.TL = ' + js + ';\n')
    open(os.path.join(OUT, 'timeline.json'), 'w', encoding='utf-8').write(js)
    print(f'длительность: {tl["duration"]:.1f} с → out/voice.wav, timeline.js')


if __name__ == '__main__':
    main()
