"""Генерирует HTML для резюме (RU/EN/UZ) и Europass CV (EN/RU)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from data import *  # noqa: E402,F403
from common import h, save as _save  # noqa: E402

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)


def save(*a):
    _save(OUT, *a)


PHOTO = "file://" + os.path.abspath(os.path.join(os.path.dirname(__file__), "photo_3x4.jpg"))


# ============================================================================ РЕЗЮМЕ
RESUME_CSS = """
@page { size: A4; margin: 13mm 15mm 12mm; }
* { box-sizing: border-box; }
body { font-family: Arial, 'Liberation Sans', sans-serif; font-size: 11pt; line-height: 1.32;
       color: #1d1d1f; margin: 0; }
.todo { background: #fff3a0; }
header { display: flex; gap: 14px; align-items: flex-start; border-bottom: 2px solid #1f4e79;
         padding-bottom: 8px; }
header img { width: 25mm; height: 33mm; object-fit: cover; border-radius: 2px; }
header .who { flex: 1; }
h1 { font-size: 19pt; margin: 0 0 1px; letter-spacing: .3px; color: #1f4e79; }
.role { font-size: 12pt; font-weight: bold; margin: 0 0 5px; }
.contacts { font-size: 10.5pt; line-height: 1.45; color: #333; }
.contacts b { color: #1d1d1f; }
h2 { font-size: 12pt; font-weight: bold; text-transform: uppercase; color: #1f4e79;
     margin: 9px 0 3px; padding-bottom: 1px; border-bottom: 1px solid #c9d6e3; letter-spacing: .4px; }
p { margin: 0 0 2px; }
.row { display: flex; justify-content: space-between; gap: 10px; margin-top: 4px; }
.row .t { font-weight: bold; }
.row .d { white-space: nowrap; color: #444; font-size: 10.5pt; }
.sub { color: #444; font-size: 10.5pt; }
ul { margin: 2px 0 0; padding-left: 16px; }
li { margin: 0 0 1px; }
.skills p { margin-bottom: 1px; }
"""


def resume(lang, L):
    exp = "".join(
        f"<div class='row'><span class='t'>{e['t']}</span><span class='d'>{e['d']}</span></div>"
        + (f"<div class='sub'>{e['sub']}</div>" if e.get("sub") else "")
        + "<ul>" + "".join(f"<li>{b}</li>" for b in e["b"]) + "</ul>"
        for e in L["exp"])
    body = f"""
<header><img src="{PHOTO}" alt="">
 <div class="who"><h1>{L['name']}</h1><p class="role">{L['role']}</p>
 <div class="contacts">{L['city']} · <b>{L['phone_l']}:</b> {h(PHONE)} · <b>Email:</b> {EMAIL}<br>
 <b>LinkedIn:</b> {LINKEDIN}<br>
 <b>Telegram:</b> {TELEGRAM} · <b>{L['born_l']}:</b> {L['born']}</div></div></header>
<h2>{L['h_goal']}</h2><p>{L['goal']}</p>
<h2>{L['h_edu']}</h2>
<div class='row'><span class='t'>{L['uni']}</span><span class='d'>{L['uni_d']}</span></div>
<div class='sub'>{L['uni_sub']}</div>
<h2>{L['h_exp']}</h2>{exp}
<h2>{L['h_skills']}</h2><div class="skills">{''.join(f'<p><b>{k}:</b> {v}</p>' for k, v in L['skills'])}</div>
<h2>{L['h_lang']}</h2><p>{L['langs']}</p>
<h2>{L['h_ach']}</h2><ul>{''.join(f'<li>{a}</li>' for a in L['ach'])}</ul>
"""
    save(f"resume_{lang}.html", body, RESUME_CSS, L["name"])


RU = dict(
    name="Рузибоев Мухаммад", role="Видеомонтажёр · моушн-дизайнер", city=CITY_RU,
    phone_l="Тел.", born_l="Дата рождения", born="19.09.2003",
    h_goal="Цель", goal="Занять позицию видеомонтажёра / моушн-дизайнера в digital-команде и делать "
    "рекламные ролики для соцсетей, которые удерживают внимание с первых секунд и приводят к целевому действию.",
    h_edu="Образование", uni="Ташкентский государственный экономический университет",
    uni_d="09.2023 — 06.2027 (ожид.)",
    uni_sub="Бакалавриат, направление «Искусственный интеллект», 4-й курс. "
    "Python, обработка данных, машинное обучение.",
    h_exp="Опыт и проекты",
    exp=[
        dict(t="GraphicArts — видеомонтаж и моушн-дизайн (фриланс)", d=f"{h(FREELANCE_FROM)} — н. в.",
             sub="Ташкент, удалённо · Telegram " + TELEGRAM,
             b=["Монтирую ролики для соцсетей (Reels, Shorts, TikTok): нарезка, цветокоррекция, титры, "
                "звук — в форматах 9:16, 4:5 и 16:9.",
                "Веду проект от брифа и раскадровки до финального рендера и правок заказчика."]),
        dict(t="Промо-ролик для платёжного сервиса Muhr", d="10.2026",
             b=["Сделал рекламный ролик 32 с, 1080×1350, 60 к/с: 8 сцен на ритмической сетке 120 BPM — "
                "от «хука» в первые 4 секунды до призыва «Начать сделку».",
                "Анимацию собрал кодом (HTML/CSS/JavaScript + Playwright) с AI-ассистентом, музыку "
                "синтезировал на Python без сэмплов; звуки привязаны к событиям в кадре, громкость −14 LUFS.",
                "Автоматизировал сборку: любая правка пересобирает финальный MP4 одной командой (ffmpeg)."]),
    ],
    h_skills="Навыки",
    skills=[("Монтаж и графика", "Adobe Premiere Pro, After Effects, DaVinci Resolve, CapCut, Photoshop"),
            ("Моушн-дизайн кодом", "HTML/CSS, JavaScript, Playwright, ffmpeg, Python (numpy)"),
            ("Звук", "синтез и сведение, синхронизация с кадром, нормализация громкости (LUFS)"),
            ("Дополнительно", "Unity (C#) — базовый уровень, тестирование игр, работа с AI-инструментами"),
            ("Личные качества", "внимание к деталям, соблюдение сроков, умение принимать правки")],
    h_lang="Языки", langs="Узбекский — родной · Русский — свободно (C1) · Английский — средний (B1)",
    h_ach="Достижения",
    ach=["Ролик Muhr сделан без стоковых шаблонов и чужой музыки: все 8 сцен и саундтрек — собственная работа.",
         "Совмещаю 4-й курс по направлению «Искусственный интеллект» с практическими заказами по видео."],
)

EN = dict(
    name="Muhammad Ruziboev", role="Video Editor · Motion Designer", city=CITY_EN,
    phone_l="Phone", born_l="Date of birth", born="19 September 2003",
    h_goal="Objective", goal="To join a digital team as a video editor / motion designer and create social-media "
    "ads that hold attention from the first seconds and drive viewers to act.",
    h_edu="Education", uni="Tashkent State University of Economics",
    uni_d="09/2023 — 06/2027 (expected)",
    uni_sub="Bachelor’s degree in Artificial Intelligence, 4th year. "
    "Python, data processing, machine learning.",
    h_exp="Experience and projects",
    exp=[
        dict(t="GraphicArts — video editing and motion design (freelance)", d=f"{h(FREELANCE_FROM_EN)} — present",
             sub="Tashkent, remote · Telegram " + TELEGRAM,
             b=["Edit social-media videos (Reels, Shorts, TikTok): cutting, colour correction, titles and "
                "sound in 9:16, 4:5 and 16:9 formats.",
                "Run each project from brief and storyboard to final render and client revisions."]),
        dict(t="Promo video for the Muhr payment service", d="10/2026",
             b=["Produced a 32-second ad, 1080×1350 at 60 fps: 8 scenes on a 120 BPM rhythm grid — from a "
                "4-second hook to the “Start a deal” call to action.",
                "Built the animation in code (HTML/CSS/JavaScript + Playwright) with an AI assistant and "
                "synthesised the music in Python with no samples; sounds are synced to on-screen events, "
                "loudness −14 LUFS.",
                "Automated the pipeline: any change rebuilds the final MP4 with one command (ffmpeg)."]),
    ],
    h_skills="Skills",
    skills=[("Editing and graphics", "Adobe Premiere Pro, After Effects, DaVinci Resolve, CapCut, Photoshop"),
            ("Motion design in code", "HTML/CSS, JavaScript, Playwright, ffmpeg, Python (numpy)"),
            ("Audio", "synthesis and mixing, sync to picture, loudness normalisation (LUFS)"),
            ("Additional", "Unity (C#) — basic, game testing, AI tools"),
            ("Personal", "attention to detail, meeting deadlines, taking feedback well")],
    h_lang="Languages", langs="Uzbek — native · Russian — fluent (C1) · English — intermediate (B1)",
    h_ach="Achievements",
    ach=["Made the Muhr video with no stock templates or third-party music: all 8 scenes and the soundtrack are my own work.",
         "Combine the 4th year of an Artificial Intelligence degree with paid video work."],
)

UZ = dict(
    name="Ro‘ziboyev Muxammad", role="Videomontajchi · motion-dizayner", city=CITY_UZ,
    phone_l="Tel.", born_l="Tug‘ilgan sana", born="19.09.2003",
    h_goal="Maqsad", goal="Raqamli jamoada videomontajchi / motion-dizayner sifatida ishlash va ijtimoiy "
    "tarmoqlar uchun birinchi soniyalardanoq e’tiborni ushlab, maqsadli harakatga undaydigan reklama roliklarini yaratish.",
    h_edu="Ta’lim", uni="Toshkent davlat iqtisodiyot universiteti",
    uni_d="09.2023 — 06.2027 (kutilmoqda)",
    uni_sub="Bakalavriat, «Sun’iy intellekt» yo‘nalishi, 4-kurs. "
    "Python, ma’lumotlarga ishlov berish, mashinali o‘qitish.",
    h_exp="Tajriba va loyihalar",
    exp=[
        dict(t="GraphicArts — videomontaj va motion-dizayn (frilans)", d=f"{h(FREELANCE_FROM)} — h. v.",
             sub="Toshkent, masofaviy · Telegram " + TELEGRAM,
             b=["Ijtimoiy tarmoqlar uchun roliklarni montaj qilaman (Reels, Shorts, TikTok): kesish, rang "
                "korreksiyasi, titrlar, ovoz — 9:16, 4:5 va 16:9 formatlarida.",
                "Loyihani brif va raskadrovkadan yakuniy render va buyurtmachi tuzatishlarigacha olib boraman."]),
        dict(t="Muhr to‘lov xizmati uchun promo-rolik", d="10.2026",
             b=["32 soniyalik reklama roligini tayyorladim (1080×1350, 60 kadr/s): 120 BPM ritmik to‘rdagi "
                "8 sahna — dastlabki 4 soniyadagi «xuk»dan «Bitimni boshlash» chaqirig‘igacha.",
                "Animatsiyani AI-yordamchi bilan kod orqali yig‘dim (HTML/CSS/JavaScript + Playwright), musiqani "
                "Python’da semplsiz sintez qildim; tovushlar kadrdagi voqealarga bog‘langan, ovoz balandligi −14 LUFS.",
                "Yig‘ishni avtomatlashtirdim: har qanday tuzatish yakuniy MP4 ni bitta buyruq bilan qayta yig‘adi (ffmpeg)."]),
    ],
    h_skills="Ko‘nikmalar",
    skills=[("Montaj va grafika", "Adobe Premiere Pro, After Effects, DaVinci Resolve, CapCut, Photoshop"),
            ("Kod orqali motion-dizayn", "HTML/CSS, JavaScript, Playwright, ffmpeg, Python (numpy)"),
            ("Ovoz", "sintez va mikslash, kadr bilan sinxronlash, ovoz balandligini normallashtirish (LUFS)"),
            ("Qo‘shimcha", "Unity (C#) — boshlang‘ich daraja, o‘yinlarni testlash, AI-vositalar bilan ishlash"),
            ("Shaxsiy sifatlar", "detallarga e’tibor, muddatlarga rioya qilish, tuzatishlarni qabul qila olish")],
    h_lang="Tillar", langs="O‘zbek — ona tili · Rus — erkin (C1) · Ingliz — o‘rta (B1)",
    h_ach="Yutuqlar",
    ach=["Muhr roligi tayyor shablon va begona musiqasiz yaratilgan: barcha 8 sahna va saundtrek — o‘z ishim.",
         "«Sun’iy intellekt» yo‘nalishidagi 4-kursni video bo‘yicha amaliy buyurtmalar bilan birga olib boraman."],
)

for lang, L in (("RU", RU), ("EN", EN), ("UZ", UZ)):
    resume(lang, L)

# ============================================================================ EUROPASS
EP_CSS = """
@page { size: A4; margin: 12mm 13mm 12mm; }
* { box-sizing: border-box; }
body { font-family: Arial, 'Liberation Sans', sans-serif; font-size: 9.6pt; line-height: 1.34; color: #222; margin: 0; }
.todo { background: #fff3a0; }
.top { display: flex; justify-content: space-between; align-items: center; color: #15428b;
       font-size: 8.5pt; letter-spacing: 1.5px; border-bottom: 2px solid #15428b; padding-bottom: 4px; }
.top b { font-size: 13pt; letter-spacing: .5px; }
.grid { display: grid; grid-template-columns: 46mm 1fr; column-gap: 6mm; }
.l { text-align: right; color: #15428b; font-size: 8.8pt; padding-top: 1px; }
.sec { margin-top: 9px; break-inside: avoid; }
.sec > .l { font-weight: bold; text-transform: uppercase; letter-spacing: .4px; font-size: 8.8pt; }
.sec > .r { border-bottom: 1px solid #15428b; margin-bottom: 4px; }
.item { margin-top: 5px; break-inside: avoid; }
h3 { font-size: 10.5pt; margin: 0; color: #15428b; }
.org { margin: 1px 0 2px; }
ul { margin: 1px 0 0; padding-left: 15px; } li { margin-bottom: 1px; }
.pi { display: flex; gap: 14px; } .pi img { width: 26mm; height: 34mm; object-fit: cover; }
.pi .n { font-size: 15pt; font-weight: bold; color: #15428b; margin-bottom: 3px; }
table { border-collapse: collapse; width: 100%; font-size: 8.8pt; }
td, th { border: 1px solid #b7c5dd; padding: 2px 4px; text-align: center; }
th { background: #e7edf7; color: #15428b; font-weight: bold; }
td.ln { text-align: left; font-weight: bold; }
.note { font-size: 8pt; color: #555; margin-top: 2px; }
.muted { color: #555; }
"""


def ep_item(left, title, org, bullets=(), extra=""):
    ul = ("<ul>" + "".join(f"<li>{b}</li>" for b in bullets) + "</ul>") if bullets else ""
    return (f"<div class='grid item'><div class='l'>{left}</div><div><h3>{title}</h3>"
            f"<div class='org'>{org}</div>{ul}{extra}</div></div>")


def ep_sec(title):
    return f"<div class='grid sec'><div class='l'>{title}</div><div class='r'></div></div>"


def ep_row(left, content):
    return f"<div class='grid item'><div class='l'>{left}</div><div>{content}</div></div>"


def europass(lang, E):
    langs = "".join(f"<tr><td class='ln'>{n}</td>" + "".join(f"<td>{x}</td>" for x in lv) + "</tr>"
                    for n, lv in E["langs"])
    dig = "".join(f"<td>{x}</td>" for x in E["dig_lv"])
    body = f"""
<div class="top"><span>{E['cv']}</span><b>europass</b></div>
{ep_sec(E['h_pi'])}
<div class='grid item'><div class='l'></div><div class='pi'><img src="{PHOTO}" alt=""><div>
 <div class='n'>{E['name']}</div>
 {E['addr_l']}: {E['city']}<br>{E['phone_l']}: {h(PHONE)}<br>Email: {EMAIL}<br>
 LinkedIn: {LINKEDIN}<br>Telegram: {TELEGRAM} · GitHub: {GITHUB}<br>
 {E['sex']} | {E['dob_l']}: {BIRTH_EU} | {E['nat']}</div></div></div>
{ep_row(E['job_l'], f"<h3>{E['job']}</h3>")}
{ep_sec(E['h_work'])}
{''.join(ep_item(*w) for w in E['work'])}
{ep_sec(E['h_edu'])}
{''.join(ep_item(*e) for e in E['edu'])}
{ep_sec(E['h_ps'])}
{ep_row(E['mt_l'], E['mt'])}
{ep_row(E['ol_l'], f'''<table><tr><th rowspan=2></th><th colspan=2>{E['und']}</th><th colspan=2>{E['spk']}</th>
 <th rowspan=2>{E['wri']}</th></tr><tr><th>{E['lis']}</th><th>{E['rea']}</th><th>{E['si']}</th><th>{E['sp']}</th></tr>
 {langs}</table><div class='note'>{E['cefr']}</div>''')}
{''.join(ep_row(k, v) for k, v in E['soft'])}
{ep_row(E['dig_l'], f'''<table><tr><th colspan=5>{E['dig_h']}</th></tr>
 <tr>{''.join(f'<th>{x}</th>' for x in E['dig_cols'])}</tr><tr>{dig}</tr></table>
 <div class='note'>{E['dig_note']}</div><div style='margin-top:3px'>{E['dig_tools']}</div>''')}
{ep_sec(E['h_add'])}
{''.join(ep_row(k, v) for k, v in E['add'])}
"""
    save(f"europass_{lang}.html", body, EP_CSS, E["name"])


EP_EN = dict(
    cv="CURRICULUM VITAE", name="Muhammad Ruziboev", h_pi="Personal information",
    addr_l="Address", city=CITY_EN, phone_l="Phone", sex="Sex: Male", dob_l="Date of birth",
    nat="Nationality: Uzbek", job_l="Job applied for", job="Video Editor / Motion Designer",
    h_work="Work experience",
    work=[(f"{h(FREELANCE_FROM_EN)} – Present", "Video editor and motion designer (freelance)",
           "GraphicArts — Tashkent, Uzbekistan (remote)",
           ["Editing social-media videos (Reels, Shorts, TikTok): cutting, colour correction, titles, sound "
            "in 9:16, 4:5 and 16:9 formats.",
            "Running projects from brief and storyboard to final render and client revisions.",
            "<b>10/2026 — promo video for the Muhr payment service:</b> 32 s, 1080×1350, 60 fps, 8 scenes on "
            "a 120 BPM grid; animation built in code (HTML/CSS/JavaScript, Playwright) with an AI assistant; "
            "original music synthesised in Python, loudness −14 LUFS; one-command build to MP4 (ffmpeg)."],
           "<div class='muted'>Business or sector: Digital media and advertising</div>")],
    h_edu="Education and training",
    edu=[("09/2023 – 06/2027 (expected)", "Bachelor’s degree — Artificial Intelligence",
          "Tashkent State University of Economics — Tashkent, Uzbekistan · EQF level 6",
          ["4th-year student. Main subjects: programming in Python, data processing, machine learning, "
           "digital economy."]),
         (f"{h(SCHOOL_YEARS[0]).replace('.', '/')} – {h(SCHOOL_YEARS[1]).replace('.', '/')}",
          "General secondary education", f"{h(SCHOOL_EN)}, Uzbekistan · EQF level 4")],
    h_ps="Personal skills", mt_l="Mother tongue", mt="Uzbek", ol_l="Other languages",
    und="UNDERSTANDING", spk="SPEAKING", wri="WRITING", lis="Listening", rea="Reading",
    si="Spoken interaction", sp="Spoken production",
    langs=[("Russian", ["C1"] * 5), ("English", ["B1"] * 5)],
    cefr="Levels: A1/A2 — basic user · B1/B2 — independent user · C1/C2 — proficient user. "
         "Common European Framework of Reference for Languages.",
    soft=[("Communication skills", "Clear communication with clients: agreeing on a brief, presenting drafts and "
           "taking revisions; experience of remote work through Telegram."),
          ("Organisational / managerial skills", "Planning a project into scenes and deadlines; combining full-time "
           "university study with freelance orders."),
          ("Job-related skills", "Editing to the beat, storytelling for short-form ads (hook → product → call to "
           "action), sound design and sync to picture, preparing videos for different platforms.")],
    dig_l="Digital skills", dig_h="SELF-ASSESSMENT",
    dig_cols=["Information processing", "Communication", "Content creation", "Safety", "Problem solving"],
    dig_lv=["Independent user", "Proficient user", "Proficient user", "Independent user", "Independent user"],
    dig_note="Digital competences — self-assessment grid.",
    dig_tools="Adobe Premiere Pro, After Effects, DaVinci Resolve, CapCut, Photoshop · HTML/CSS, JavaScript, "
              "Playwright, ffmpeg · Python (numpy) · Unity (C#, basic) · AI tools",
    h_add="Additional information",
    add=[("Projects", "Muhr promo video (10/2026) — fintech advertising, vertical 4:5 format for social feeds."),
         ("Online profiles", f"LinkedIn: {LINKEDIN} · hh.uz: resume “Video editor” · vacancy.argos.uz"),
         ("Interests", "Game industry and game testing (Unity), motion graphics, AI tools for content creation."),
         ("References", "Available on request.")],
)

EP_RU = dict(
    cv="РЕЗЮМЕ · ФОРМАТ EUROPASS", name="Рузибоев Мухаммад", h_pi="Личная информация",
    addr_l="Адрес", city=CITY_RU, phone_l="Телефон", sex="Пол: мужской", dob_l="Дата рождения",
    nat="Гражданство: Узбекистан", job_l="Желаемая должность", job="Видеомонтажёр / моушн-дизайнер",
    h_work="Опыт работы",
    work=[(f"{h(FREELANCE_FROM)} – по наст. время", "Видеомонтажёр и моушн-дизайнер (фриланс)",
           "GraphicArts — Ташкент, Узбекистан (удалённо)",
           ["Монтаж роликов для соцсетей (Reels, Shorts, TikTok): нарезка, цветокоррекция, титры, звук "
            "в форматах 9:16, 4:5 и 16:9.",
            "Ведение проекта от брифа и раскадровки до финального рендера и правок заказчика.",
            "<b>10.2026 — промо-ролик для платёжного сервиса Muhr:</b> 32 с, 1080×1350, 60 к/с, 8 сцен "
            "на сетке 120 BPM; анимация собрана кодом (HTML/CSS/JavaScript, Playwright) с AI-ассистентом; "
            "собственная музыка, синтезированная на Python, громкость −14 LUFS; сборка в MP4 одной командой (ffmpeg)."],
           "<div class='muted'>Сфера деятельности: цифровые медиа и реклама</div>")],
    h_edu="Образование и обучение",
    edu=[("09.2023 – 06.2027 (ожид.)", "Бакалавриат — Искусственный интеллект",
          "Ташкентский государственный экономический университет — Ташкент, Узбекистан · уровень EQF 6",
          ["Студент 4-го курса. Основные дисциплины: программирование на Python, обработка данных, "
           "машинное обучение, цифровая экономика."]),
         (f"{h(SCHOOL_YEARS[0])} – {h(SCHOOL_YEARS[1])}", "Общее среднее образование",
          f"{h(SCHOOL_RU)}, Узбекистан · уровень EQF 4")],
    h_ps="Личные навыки", mt_l="Родной язык", mt="Узбекский", ol_l="Иностранные языки",
    und="ПОНИМАНИЕ", spk="РАЗГОВОР", wri="ПИСЬМО", lis="Аудирование", rea="Чтение",
    si="Диалог", sp="Монолог",
    langs=[("Русский", ["C1"] * 5), ("Английский", ["B1"] * 5)],
    cefr="Уровни: A1/A2 — базовый · B1/B2 — самостоятельный · C1/C2 — свободный. "
         "Общеевропейская шкала владения языками (CEFR).",
    soft=[("Коммуникативные навыки", "Чёткое общение с заказчиками: согласование брифа, показ черновиков, "
           "работа с правками; опыт удалённой работы через Telegram."),
          ("Организационные навыки", "Планирую проект по сценам и срокам; совмещаю очную учёбу в университете "
           "с заказами на фрилансе."),
          ("Профессиональные навыки", "Монтаж в ритм музыки, сторителлинг для коротких рекламных роликов "
           "(хук → продукт → призыв к действию), саунд-дизайн и синхронизация с кадром, подготовка видео под разные площадки.")],
    dig_l="Цифровые навыки", dig_h="САМООЦЕНКА",
    dig_cols=["Обработка информации", "Коммуникация", "Создание контента", "Безопасность", "Решение проблем"],
    dig_lv=["Самостоятельный", "Опытный", "Опытный", "Самостоятельный", "Самостоятельный"],
    dig_note="Цифровые компетенции — шкала самооценки.",
    dig_tools="Adobe Premiere Pro, After Effects, DaVinci Resolve, CapCut, Photoshop · HTML/CSS, JavaScript, "
              "Playwright, ffmpeg · Python (numpy) · Unity (C#, базовый) · AI-инструменты",
    h_add="Дополнительная информация",
    add=[("Проекты", "Промо-ролик Muhr (10.2026) — реклама финтех-сервиса, вертикальный формат 4:5 для лент соцсетей."),
         ("Профили", f"LinkedIn: {LINKEDIN} · hh.uz: резюме «Видеомонтажёр» · vacancy.argos.uz"),
         ("Интересы", "Игровая индустрия и тестирование игр (Unity), моушн-графика, AI-инструменты для создания контента."),
         ("Рекомендации", "Предоставляются по запросу.")],
)

europass("EN", EP_EN)
europass("RU", EP_RU)
