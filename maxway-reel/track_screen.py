"""Трекинг превью-окна After Effects (сиреневый прямоугольник) на кадрах монитора.

Для каждого кадра находит 4 угла окна композиции и сохраняет их в JSON.
    python3 track_screen.py <monitor.mp4> <out.json>
"""
import json
import sys

import cv2
import numpy as np


def order_quad(pts):
    """Углы по порядку: верх-лево, верх-право, низ-право, низ-лево."""
    pts = np.asarray(pts, dtype=np.float64)
    s = pts.sum(1)
    d = pts[:, 0] - pts[:, 1]
    return np.array([pts[s.argmin()], pts[d.argmax()], pts[s.argmax()], pts[d.argmin()]])


def find_panel(frame):
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    h, s, v = cv2.split(hsv)
    # сиреневый: оттенок 120..150 (OpenCV 0..180), заметная насыщенность, яркий
    m = ((h > 118) & (h < 150) & (s > 45) & (v > 120)).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((9, 9), np.uint8))
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return None, 0
    c = max(cnts, key=cv2.contourArea)
    area = cv2.contourArea(c)
    hull = cv2.convexHull(c)
    peri = cv2.arcLength(hull, True)
    for eps in (0.02, 0.03, 0.04, 0.05, 0.06):
        ap = cv2.approxPolyDP(hull, eps * peri, True)
        if len(ap) == 4:
            return order_quad(ap[:, 0, :]), area
    x, y, w, hh = cv2.boundingRect(hull)
    return order_quad([[x, y], [x + w, y], [x + w, y + hh], [x, y + hh]]), area


def main(src, out):
    cap = cv2.VideoCapture(src)
    res = []
    i = 0
    while True:
        ok, fr = cap.read()
        if not ok:
            break
        q, area = find_panel(fr)
        res.append({'i': i, 'area': float(area), 'quad': None if q is None else q.round(2).tolist()})
        i += 1
    json.dump(res, open(out, 'w'))
    print(out, len(res), 'кадров')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
