# 01 — Buttons sheet

Sheet: `../01_buttons_sheet.png` (1536×1024, transparent, 4×4 cells of 320×192, 64 px gutters).
Trimmed sprites in this folder, numbered in sheet order.

Suggested Unity 9-slice borders (Sprite Editor → Border, in px: L / B / R / T):

| Sprite | Size | Border L/B/R/T |
|---|---|---|
| primary_* / secondary_* | 300×60 | 20 / 20 / 20 / 20 |
| menu_highlight | 300×60 | 46 / 15 / 46 / 15 |
| focus_frame | 316×78 | 48 / 36 / 48 / 36 |
| icon_button_square | 96×96 | 20 / 20 / 20 / 20 |
| checkbox_* | 64×64 / 78×72 | not sliced (fixed size) |
| toggle_* / matchstick_pointer | — | not sliced (fixed size) |

Button centers are flat colour (no grain) so they stretch cleanly; grain, misregistered inner line and
corner ornaments live inside the border band.
