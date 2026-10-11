"""Контрольные листы: кадр из середины каждого плана (или заданные моменты), сетка 3×3 → out/contact/sheetN.png
    python3 tools/contact.py            # все планы
    python3 tools/contact.py 40,41.5    # выбранные моменты
"""
import os, re, subprocess, sys, glob, shutil
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
if len(sys.argv) > 1:
    ts = sys.argv[1]
else:
    src = open('shots.js', encoding='utf-8').read()
    ts = ','.join(f'{(float(a) + float(b)) / 2:.2f}' for a, b in re.findall(r'shot\(([\d.]+), ([\d.]+),', src))
shutil.rmtree('out/stills', ignore_errors=True)
shutil.rmtree('out/contact', ignore_errors=True)
os.makedirs('out/contact')
subprocess.run(['node', 'render.mjs', '--stills', ts], check=True, stdout=subprocess.DEVNULL)
files = sorted(glob.glob('out/stills/*.png'))
for n in range(0, len(files), 9):
    b = files[n:n + 9]
    b += [b[0]] * (9 - len(b))
    args = []
    for f in b:
        args += ['-i', f]
    fc = ''.join(f'[{k}]scale=640:360[v{k}];' for k in range(9)) + ''.join(f'[v{k}]' for k in range(9)) + \
        'xstack=inputs=9:layout=0_0|w0_0|w0+w1_0|0_h0|w0_h0|w0+w1_h0|0_h0+h1|w0_h0+h1|w0+w1_h0+h1'
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error'] + args + ['-filter_complex', fc, f'out/contact/sheet{n // 9}.png'], check=True)
print('\n'.join(sorted(glob.glob('out/contact/*.png'))))
