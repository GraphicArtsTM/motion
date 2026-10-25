import re, sys
PROTECT = {"welcome", "Telegram", "WhatsApp", "Instagram", "QR", "QR-kod", "Fleet", "API", "SQL", "SELECT",
           "REHIRE", "Clawback", "ID", "TG", "AB1234567", "profile_id", "Go", "24/7", "Pro'ga", "reply"}
REPL_PRE = [("Yandex Pro'sini", "Яндекс Про иловасини"), ("Yandex Pro'ga", "Яндекс Про'га"), ("Yandex Pro", "Яндекс Про"),
            ("Yandex Go'dagi", "Яндекс Go'даги"), ("Yandex Go", "Яндекс Go"), ("F.I.Sh.", "Ф.И.Ш."), ("QR-kod", "QR-код"),
            ("Fleet'da", "Fleet'да")]
APOS = "'ʻ‘’`"
def tr_word(w):
    if w in PROTECT or w.rstrip("-") in PROTECT or not re.search(r"[A-Za-z]", w):
        return w
    out = []
    i = 0
    n = len(w)
    def at_start(i):
        return i == 0 or not w[i-1].isalpha()
    while i < n:
        c = w[i]; nx = w[i+1] if i+1 < n else ""
        lc = c.lower(); up = c.isupper()
        def put(s):
            out.append(s.upper() if up and (len(s) == 1 or (nx.isupper() if nx else False)) else (s[0].upper()+s[1:] if up else s))
        if lc == "o" and nx and nx in APOS:
            put("ў"); i += 2; continue
        if lc == "g" and nx and nx in APOS:
            put("ғ"); i += 2; continue
        if lc == "s" and nx.lower() == "h":
            put("ш"); i += 2; continue
        if lc == "c" and nx.lower() == "h":
            put("ч"); i += 2; continue
        if lc == "y" and nx.lower() in "aoue" and nx:
            m = {"a": "я", "o": "ё", "u": "ю", "e": "е"}[nx.lower()]
            if nx.lower() == "o" and i+2 < n and w[i+2] in APOS:
                put("й"); i += 1; continue
            put(m); i += 2; continue
        if lc == "e":
            put("э" if at_start(i) else "е"); i += 1; continue
        if c and c in APOS:
            out.append("ъ" if (i > 0 and w[i-1].isalpha() and nx.isalpha()) else "'"); i += 1; continue
        m = {"a":"а","b":"б","d":"д","f":"ф","g":"г","h":"ҳ","i":"и","j":"ж","k":"к","l":"л","m":"м","n":"н","o":"о",
             "p":"п","q":"қ","r":"р","s":"с","t":"т","u":"у","v":"в","x":"х","y":"й","z":"з","c":"с","w":"в"}.get(lc)
        if m:
            put(m)
        else:
            out.append(c)
        i += 1
    return "".join(out)

TOKEN = re.compile(r"(\{[^}]*\}|<[^>]+>|/[a-z]+|https?://\S+|[A-Za-z][A-Za-z" + APOS + r"0-9_/.\-]*)")
def tr_text(s):
    for a, b in REPL_PRE:
        s = s.replace(a, b)
    parts = TOKEN.split(s)
    res = []
    for p in parts:
        if not p:
            continue
        if p.startswith("{") or p.startswith("<") or p.startswith("/") or p.startswith("http"):
            res.append(p)
        elif re.match(r"[A-Za-z]", p):
            res.append(tr_word(p))
        else:
            res.append(p)
    return "".join(res)

src = open(sys.argv[1], encoding="utf-8").read().splitlines()
out = []
for line in src:
    m = re.match(r"^([a-z0-9_\-]+) = (.*)$", line)
    if line.startswith("##") or not line.strip():
        out.append(line); continue
    if m:
        key, val = m.groups()
        if key.startswith("lang-") or key == "broadcast-raw":
            out.append(line); continue
        out.append(f"{key} = {tr_text(val)}")
    else:
        out.append(tr_text(line))
text = "\n".join(out) + "\n"
text = re.sub(r"([А-ЯЎҚҒҲЁ])ъ([А-ЯЎҚҒҲЁ])", r"\1Ъ\2", text)
for a, b in [("Яндекс Гўдаги", "Яндекс Go'даги"), ("Велсоме", "Welcome"), ("велсоме", "welcome")]:
    text = text.replace(a, b)
open(sys.argv[2], "w", encoding="utf-8").write(text)
