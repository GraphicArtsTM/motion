"""Нарезка одной длинной записи озвучки на реплики.

Запись читается по порядку сценария (VOICEOVER.md). Скрипт:
  1) находит участки речи (VAD по энергии),
  2) сравнивает их с эталонными синтезированными версиями тех же реплик (MFCC + DTW),
  3) динамическим программированием выбирает, какие участки составляют каждую реплику
     (учитывает похожесть, длительность и паузы; лишние дубли и оговорки пропускает),
  4) сохраняет реплики в audio/voice_user/<id>.wav с мягкими краями.

    python3 audio/align_voice.py путь/к/записи.mp3
"""
import json
import os
import subprocess
import sys

import numpy as np
from numba import njit

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 16000
HOP = 160          # 10 мс
WIN = 400


def load(path, sr=SR):
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', path, '-ac', '1', '-ar', str(sr), '-f', 'f32le', '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


def mel_fb(n_mels=40, n_fft=512):
    def hz2mel(f): return 2595 * np.log10(1 + f / 700)
    def mel2hz(m): return 700 * (10 ** (m / 2595) - 1)
    pts = mel2hz(np.linspace(hz2mel(80), hz2mel(7600), n_mels + 2))
    bins = np.floor((n_fft + 1) * pts / SR).astype(int)
    fb = np.zeros((n_mels, n_fft // 2 + 1))
    for i in range(n_mels):
        a, b, c = bins[i], bins[i + 1], bins[i + 2]
        fb[i, a:b] = (np.arange(a, b) - a) / max(b - a, 1)
        fb[i, b:c] = (c - np.arange(b, c)) / max(c - b, 1)
    return fb


FB = mel_fb()
DCT = np.cos(np.pi / 40 * (np.arange(40)[None, :] + .5) * np.arange(1, 14)[:, None])


def frames(x):
    n = 1 + max(0, (len(x) - WIN) // HOP)
    idx = np.arange(WIN)[None, :] + HOP * np.arange(n)[:, None]
    return x[idx] * np.hanning(WIN)


def mfcc(x):
    if len(x) < WIN:
        x = np.pad(x, (0, WIN - len(x)))
    p = np.abs(np.fft.rfft(frames(x), 512)) ** 2
    lm = np.log(p @ FB.T + 1e-8)
    c = lm @ DCT.T
    d = np.gradient(c, axis=0)
    f = np.hstack([c, d * 2])
    return (f - f.mean(0)) / (f.std(0) + 1e-6)          # CMVN: сглаживает разницу голосов


@njit(cache=True)
def dtw(a, b):
    n, m = a.shape[0], b.shape[0]
    D = np.full((n + 1, m + 1), np.inf)
    L = np.zeros((n + 1, m + 1))
    D[0, 0] = 0.0
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            s = 0.0
            for k in range(a.shape[1]):
                t = a[i - 1, k] - b[j - 1, k]
                s += t * t
            c = np.sqrt(s)
            best, bl = D[i - 1, j - 1], L[i - 1, j - 1]
            if D[i - 1, j] < best:
                best, bl = D[i - 1, j], L[i - 1, j]
            if D[i, j - 1] < best:
                best, bl = D[i, j - 1], L[i, j - 1]
            D[i, j] = best + c
            L[i, j] = bl + 1
    return D[n, m] / L[n, m]


def vad(x):
    f = frames(x)
    e = 10 * np.log10((f ** 2).mean(1) + 1e-10)
    floor = np.percentile(e, 10)
    thr = max(floor + 14, e.max() - 45)
    sp = e > thr
    regs, i = [], 0
    while i < len(sp):
        if sp[i]:
            j = i
            while j < len(sp) and sp[j]:
                j += 1
            regs.append([i, j]); i = j
        else:
            i += 1
    merged = []
    for r in regs:                       # склеиваем дыры короче 0,18 с (паузы внутри слова)
        if merged and r[0] - merged[-1][1] < 18:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    return [(a * HOP / SR, b * HOP / SR) for a, b in merged if b - a >= 10]


def main():
    src = sys.argv[1]
    lines = sorted(json.load(open(os.path.join(HERE, 'dialogue.json'), encoding='utf-8'))['lines'], key=lambda l: l['t'])
    refdir = os.path.join(HERE, 'voice_tts')
    sys.path.insert(0, HERE)
    import voices
    os.makedirs(refdir, exist_ok=True)
    refs = []
    for ln in lines:                     # эталоны: синтез тех же фраз
        p = os.path.join(refdir, ln['id'] + '.wav')
        if not os.path.exists(p):
            voices.synth(ln['who'], ln.get('say', ln['text']), p); voices.trim(p)
        r = load(p)
        refs.append((mfcc(r), len(r) / SR))

    x = load(src)
    chunks = vad(x)
    print(f'запись {len(x) / SR:.1f} с, участков речи: {len(chunks)}, реплик: {len(lines)}')
    for q, (a, b) in enumerate(chunks):
        print(f'  участок {q:2d}: {a:7.2f}–{b:7.2f}')
    feats = mfcc(x)
    fr = lambda t: int(t * SR / HOP)
    ratio = sum(b - a for a, b in chunks) / sum(r[1] for r in refs)
    print(f'темп записи относительно эталона: ×{ratio:.2f}')

    NL, NC, G = len(lines), len(chunks), 5
    cache = {}
    def cost(i, j, k):                   # реплика i = участки j..k-1
        key = (i, j, k)
        if key not in cache:
            a, b = chunks[j][0], chunks[k - 1][1]
            gaps = [chunks[q + 1][0] - chunks[q][1] for q in range(j, k - 1)]
            uf = feats[fr(a):fr(b)]
            # внутри реплики выкидываем длинные паузы, чтобы DTW сравнивал только речь
            if gaps:
                uf = np.vstack([feats[fr(chunks[q][0]):fr(chunks[q][1])] for q in range(j, k)])
            d = dtw(np.ascontiguousarray(refs[i][0]), np.ascontiguousarray(uf))
            dur = sum(chunks[q][1] - chunks[q][0] for q in range(j, k))
            dpen = np.log(dur / (refs[i][1] * ratio)) ** 2
            gpen = sum(max(0, g - 0.9) for g in gaps)       # длинная пауза внутри реплики — подозрительно
            cache[key] = d + 1.5 * dpen + 0.8 * gpen
        return cache[key]

    SKIP = 2.4                           # штраф за выброшенный участок (оговорка, дубль, шум)
    INF = 1e18
    best = np.full((NL + 1, NC + 1), INF)
    back = {}
    best[0, 0] = 0
    for j in range(1, NC + 1):
        best[0, j] = best[0, j - 1] + SKIP; back[(0, j)] = ('skip', j - 1)
    for i in range(1, NL + 1):
        for k in range(1, NC + 1):
            v = best[i, k - 1] + SKIP; bk = ('skip', k - 1)
            for j in range(max(0, k - G), k):
                if best[i - 1, j] >= INF:
                    continue
                c = best[i - 1, j] + cost(i - 1, j, k)
                if c < v:
                    v, bk = c, ('take', j)
            best[i, k] = v; back[(i, k)] = bk
    # восстановление
    i, k, assign = NL, NC, {}
    while i > 0 or k > 0:
        kind, j = back[(i, k)]
        if kind == 'skip':
            k = j
        else:
            assign[i - 1] = (j, k); i -= 1; k = j
    # ручные правки раскладки: <запись>.map.json — {"id": [первый_участок, последний_участок]}
    mp = os.path.splitext(src)[0] + '.map.json'
    if os.path.exists(mp):
        fix = json.load(open(mp, encoding='utf-8'))
        for i, ln in enumerate(lines):
            if ln['id'] in fix:
                a, b = fix[ln['id']]; assign[i] = (a, b + 1)
        print('применены правки из', os.path.basename(mp))

    out = os.path.join(HERE, 'voice_user')
    os.makedirs(out, exist_ok=True)
    full = load(src, 48000)
    report = []
    used = set()
    for i, ln in enumerate(lines):
        j, k = assign[i]
        used.update(range(j, k))
        a, b = chunks[j][0] - 0.06, chunks[k - 1][1] + 0.12
        seg = full[max(0, int(a * 48000)):int(b * 48000)]
        n = len(seg); fade = int(0.015 * 48000)
        seg[:fade] *= np.linspace(0, 1, fade); seg[-fade:] *= np.linspace(1, 0, fade)
        p = os.path.join(out, ln['id'] + '.wav')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'f64le', '-ar', '48000', '-ac', '1', '-i', '-', p],
                       input=seg.astype(np.float64).tobytes(), check=True)
        c = cost(i, j, k)
        report.append({'id': ln['id'], 'who': ln['who'], 'from': round(a, 2), 'to': round(b, 2), 'chunks': k - j, 'cost': round(float(c), 2), 'text': ln['text']})
        flag = '  ← проверить' if c > 2.2 else ''
        print(f"{ln['id']:>4} {a:7.2f}–{b:7.2f}  {b - a:4.1f}s  участков {k - j}  цена {c:4.2f}  {ln['text']}{flag}")
    skipped = [(round(chunks[q][0], 2), round(chunks[q][1], 2)) for q in range(NC) if q not in used]
    if skipped:
        print('пропущено (дубли/оговорки):', skipped)
    json.dump({'source': os.path.basename(src), 'lines': report, 'skipped': skipped},
              open(os.path.join(out, 'alignment.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
