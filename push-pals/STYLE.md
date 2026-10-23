# Push Pals — UI style & sheet rules

## Style
Premium PC indie UI (Untitled Goose Game, Human Fall Flat, Overcooked, It Takes Two) — never mobile-casual.
Vintage matchbox labels / old printed paper: subtle grain, slight print misregistration, fine engraved ornaments.

| Role | Hex |
|---|---|
| Aged cream paper | #EFE4CF |
| Muted brick red | #B8443A |
| Dark ink brown (outlines) | #2B1A10 |
| Kraft cardboard | #B98A5E |
| Light wood / dark wood | #D9B380 / #6E4A2C |
| Matchbox blue | #2F5487 |
| Candle light | #F2C46B |
| Player accents (only) | #D93A2B, #2BA864, #2B6FD9, #7B5BE0 |
| Fire (only) | #FF8A00, #FFD34D |

- Thin, consistent #2B1A10 outlines; buttons low and wide (h ≈ w/5); fine borders, small corner ornaments.
- No chunky/puffy/glossy/candy/plastic, heavy bevels, 3D extrusions, strong gradients, neon.
- Materials: printed paper, corrugated cardboard, wood, striker strip, brass pins, paper tape.
- Never: coins, gems, currency, prices, shop banners, energy bars, rating popups, 3-star ratings, platform logos.

## Sheet rules
- Transparent PNG (fallback: flat #FF00FF).
- Equal grid cells, ≥ 64 px gaps, nothing touching, every item inside its cell.
- No text/numbers/labels unless requested. No shadows outside an item.
- Front-on flat view, soft light from top-left. Exact item count and order (left→right, top→bottom).

## Tooling
Assets are authored as SVG in Python (`tools/*.py`, shared palette/filters in `tools/shared.py`)
and rasterised with headless Chromium:

    python3 tools/style_reference.py out/x.html
    node tools/render.js out/x.html out/x.png 1536 1024 [1=transparent]
