import html
import os

from data import T


def h(x):
    """Экранирует текст; значения T(...) подсвечивает жёлтым."""
    s = html.escape(str(x))
    return f'<span class="todo">{s}</span>' if isinstance(x, T) else s


def save(out, name, body, css, title):
    with open(os.path.join(out, name), "w", encoding="utf-8") as f:
        f.write(f"<!doctype html><html><head><meta charset='utf-8'><title>{title}</title>"
                f"<style>{css}</style></head><body>{body}</body></html>")
