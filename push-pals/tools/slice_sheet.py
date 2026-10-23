"""Validate a grid sheet and cut each cell into a trimmed sprite.
Usage: python3 slice_sheet.py sheet.png out_dir cols rows cell_w cell_h gap margin name1,name2,..."""
import sys, os
from PIL import Image
sheet, out, cols, rows, cw, ch, gap, m, names = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:9]), sys.argv[9].split(',')
im = Image.open(sheet).convert('RGBA'); a = im.getchannel('A')
os.makedirs(out, exist_ok=True)
mask = Image.new('L', im.size, 255)
boxes = []
for r in range(rows):
    for c in range(cols):
        x, y = m + c*(cw+gap), m + r*(ch+gap)
        mask.paste(0, (x, y, x+cw, y+ch))
        bb = a.crop((x, y, x+cw, y+ch)).getbbox()
        assert bb, f'empty cell {r},{c}'
        assert bb[0] > 0 and bb[1] > 0 and bb[2] < cw and bb[3] < ch, f'item touches cell edge {r},{c}: {bb}'
        boxes.append((x+bb[0], y+bb[1], x+bb[2], y+bb[3]))
        n = names[r*cols+c]
        im.crop(boxes[-1]).save(f'{out}/{r*cols+c+1:02d}_{n}.png')
outside = Image.composite(a, Image.new('L', im.size, 0), mask).getbbox()
assert outside is None, f'pixels outside cells: {outside}'
# min gap between neighbouring items
mg = min([boxes[i+1][0]-boxes[i][2] for i in range(len(boxes)) if (i+1) % cols] +
         [boxes[i+cols][1]-boxes[i][3] for i in range(len(boxes)-cols)])
print(f'OK: {len(boxes)} items, transparent bg, nothing outside cells, min gap between items {mg}px')
for n, b in zip(names, boxes): print(f'  {n:24s} {b[2]-b[0]}x{b[3]-b[1]}')
