"""Упаковка студии в один zip (для новой сессии или для рендера на своём компьютере).

    python3 tools/pack.py                  → out/PAUK_NOVOGRADA_STUDIO.zip (весь проект: движок, все серии, звук)
    python3 tools/pack.py --no-voice-src   → без исходных длинных записей озвучки (меньше размер)

Внутри zip всё готово к запуску: RENDER_WINDOWS.bat (CRLF), render_mac_linux.sh (с правом запуска).
"""
import os
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {'node_modules', 'out', '__pycache__', '.git', 'video'}
SKIP_PARTS = ('/audio/voice/', '/audio/voice_tts/', 'soundtrack.wav', '/audio/voice_user/alignment.json')


def files():
    try:
        out = subprocess.run(['git', 'ls-files'], cwd=ROOT, check=True, capture_output=True, text=True).stdout.split('\n')
        fs = [f for f in out if f and not f.startswith('video/')]
    except Exception:
        fs = []
        for r, ds, names in os.walk(ROOT):
            ds[:] = [d for d in ds if d not in SKIP_DIRS]
            fs += [os.path.relpath(os.path.join(r, n), ROOT) for n in names]
    fs = [f for f in fs if not any(p in '/' + f.replace(os.sep, '/') for p in SKIP_PARTS)]
    if '--no-voice-src' in sys.argv:
        fs = [f for f in fs if '/voice_src/' not in f.replace(os.sep, '/') or f.endswith('.json')]
    return sorted(set(fs))


def main():
    os.makedirs(os.path.join(ROOT, 'out'), exist_ok=True)
    dst = os.path.join(ROOT, 'out', 'PAUK_NOVOGRADA_STUDIO.zip')
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in files():
            p = os.path.join(ROOT, f)
            if not os.path.isfile(p):
                continue
            data = open(p, 'rb').read()
            if f.endswith('.bat'):
                data = data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
            info = zipfile.ZipInfo.from_file(p, 'PAUK_NOVOGRADA/' + f.replace(os.sep, '/'))
            if f.endswith('.sh'):
                info.external_attr = 0o755 << 16
            z.writestr(info, data, zipfile.ZIP_DEFLATED)
    print(f'готово: {dst}  ({os.path.getsize(dst) / 1e6:.1f} МБ)')


if __name__ == '__main__':
    main()
