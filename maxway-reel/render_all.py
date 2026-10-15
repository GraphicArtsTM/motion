"""Полная сборка трёх версий рилса одной командой (Windows / macOS / Linux).

    python render_all.py                    # всё: исходники → монтаж → 3 видео в out/
    python render_all.py --titles uz         # только одна версия
    python render_all.py --workers 8        # число потоков рендера (по умолчанию — все ядра)

Если исходников нет в src/, они скачиваются с Google Drive (ссылки из задания).
Нужен ffmpeg с фильтром zscale (RENDER.bat скачивает подходящий сам).
"""
import argparse
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / 'src'
WORK = HERE / 'work' / 'sdr'
OUT = HERE / 'out'
PY = sys.executable

TITLES = {
    'posmotrite': 'MAXWAY, ПОСМОТРИТЕ, ЧТО Я СДЕЛАЛ!',
    'uz': 'MAXWAY, SIZ BUNI KO\u2018RDINGIZMI?',
}

# исходники: имя в src/ -> (id файла на Google Drive, это zip-архив с дублями?)
DRIVE = {
    'IMG_6290.MOV': ('1dqGroMdk8TW-8HyY4l5cGlP-nnC-hDhV', True),   # кадр 1, реакция
    'IMG_6298.MOV': ('1uMmMASe5nfEDkZS7TFG7geIDQeSJupra', True),   # кадр 2, монитор
    'k3.mp4': ('1SyRxwdrPpYabal3UGD55XqeGir9tD3hP', False),        # кадр 3, ролик Maxway
}

# HLG (HDR iPhone) -> SDR BT.709, тонмаппинг Hable — цветокоррекция версии 1
TONEMAP = ('zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,'
           'zscale=t=bt709:m=bt709:r=tv,format=yuv420p')


def say(msg):
    print(f'\n=== {msg}', flush=True)


def run(cmd, **kw):
    print('  >', ' '.join(str(c) for c in cmd)[:160], flush=True)
    subprocess.run([str(c) for c in cmd], check=True, **kw)


def check_ffmpeg():
    if not shutil.which('ffmpeg'):
        sys.exit('ffmpeg не найден. Запусти RENDER.bat — он скачает ffmpeg сам.')
    out = subprocess.run(['ffmpeg', '-hide_banner', '-filters'], capture_output=True, text=True).stdout
    if 'zscale' not in out:
        sys.exit('В этом ffmpeg нет фильтра zscale (нужен для HDR iPhone). '
                 'Возьми сборку с https://github.com/BtbN/FFmpeg-Builds (win64-gpl) или запусти RENDER.bat.')


def download(file_id, dest):
    url = f'https://drive.usercontent.google.com/download?id={file_id}&export=download&confirm=t'
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=60) as r:
        if 'text/html' in (r.headers.get('Content-Type') or ''):
            raise RuntimeError('Google Drive вернул страницу вместо файла')
        total = int(r.headers.get('Content-Length') or 0)
        got = 0
        t0 = time.time()
        with open(dest, 'wb') as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                got += len(chunk)
                if total:
                    print(f'\r  {got / 2**20:6.1f} / {total / 2**20:.1f} МБ  ({got / 2**20 / max(time.time() - t0, 0.1):.1f} МБ/с)',
                          end='', flush=True)
        print()


def ensure_sources():
    SRC.mkdir(exist_ok=True)
    for name, (fid, is_zip) in DRIVE.items():
        target = SRC / name
        if target.exists() and target.stat().st_size > 1_000_000:
            continue
        say(f'Скачиваю исходник {name} с Google Drive')
        tmp = SRC / f'_{name}.download'
        try:
            download(fid, tmp)
        except Exception as e:
            sys.exit(f'Не получилось скачать {name}: {e}\n'
                     f'Скачай вручную https://drive.google.com/file/d/{fid}/view и положи {name} в папку {SRC}')
        if is_zip:
            with zipfile.ZipFile(tmp) as z:
                member = next((m for m in z.namelist() if m.endswith(name)), None)
                if member is None:
                    sys.exit(f'В архиве нет файла {name}')
                with z.open(member) as fi, open(target, 'wb') as fo:
                    shutil.copyfileobj(fi, fo)
            tmp.unlink()
        else:
            tmp.replace(target)


def ensure_intermediates():
    WORK.mkdir(parents=True, exist_ok=True)
    for n in ('IMG_6290', 'IMG_6298'):
        dst = WORK / f'{n}.mp4'
        if not dst.exists():
            say(f'HDR → SDR: {n}')
            run(['ffmpeg', '-y', '-loglevel', 'error', '-i', SRC / f'{n}.MOV', '-vf', f'{TONEMAP},fps=60',
                 '-c:v', 'libx264', '-crf', '12', '-preset', 'veryfast', '-g', '30', '-an', dst])
    dst = WORK / 'k3.mp4'
    if not dst.exists():
        run(['ffmpeg', '-y', '-loglevel', 'error', '-i', SRC / 'k3.mp4', '-c:v', 'copy', '-an', dst])
    if not (HERE / 'track_6298.json').exists():
        say('Трекинг окна After Effects')
        run([PY, HERE / 'track_screen.py', WORK / 'IMG_6298.mp4', HERE / 'track_6298.json'])


def mux(title, video_list):
    """Склейка вступления и хвоста + звук: музыка до 5,92 с, дальше оригинал ролика Maxway."""
    out = OUT / f'MAXWAY_{title}.mp4'
    af = ('[1:a]afade=t=out:st=5.92:d=0.12,aresample=48000[a0];'
          '[2:a]atrim=start=0.92,asetpts=PTS-STARTPTS,adelay=5920|5920,afade=t=in:st=5.92:d=0.1,aresample=48000[a1];'
          '[a0][a1]amix=inputs=2:normalize=0:duration=longest,atrim=end=35,loudnorm=I=-14:TP=-1.0:LRA=9[a]')
    run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', video_list,
         '-i', OUT / 'music.wav', '-i', SRC / 'k3.mp4', '-filter_complex', af,
         '-map', '0:v', '-map', '[a]', '-c:v', 'libx264', '-preset', 'slow', '-crf', '17',
         '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '4.2',
         '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
         '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-t', '35', '-movflags', '+faststart', out])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--titles', default=','.join(TITLES), help='через запятую: ' + ', '.join(TITLES))
    ap.add_argument('--workers', type=int, default=os.cpu_count() or 4)
    a = ap.parse_args()
    titles = [t.strip() for t in a.titles.split(',') if t.strip()]
    os.chdir(HERE)
    OUT.mkdir(exist_ok=True)
    t0 = time.time()

    check_ffmpeg()
    ensure_sources()
    ensure_intermediates()

    say('Музыка для вступления')
    run([PY, HERE / 'music.py', OUT / 'music.wav'])

    track = HERE / 'track_6298.json'
    say(f'Рендер ролика Maxway на весь экран (6–35 с), потоков: {a.workers}')
    run([PY, HERE / 'edit.py', '--src', WORK, '--track', track, '--range', '6:35',
         '--out', OUT / 'tail.mp4', '--workers', a.workers])

    done = []
    for t in titles:
        say(f'Вступление с заголовком «{TITLES.get(t, t)}»')
        intro = OUT / f'intro_{t}.mp4'
        run([PY, HERE / 'edit.py', '--src', WORK, '--track', track, '--title', t, '--range', '0:6',
             '--out', intro, '--workers', a.workers])
        lst = OUT / f'concat_{t}.txt'
        lst.write_text(f"file '{intro.as_posix()}'\nfile '{(OUT / 'tail.mp4').as_posix()}'\n", encoding='utf-8')
        say(f'Сведение звука и финальный файл: {t}')
        done.append(mux(t, lst))

    print(f'\nГотово за {(time.time() - t0) / 60:.1f} мин:')
    for f in done:
        print(f'  {f}  ({f.stat().st_size / 2**20:.0f} МБ)')


if __name__ == '__main__':
    main()
