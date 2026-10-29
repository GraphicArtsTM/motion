"""Шпаргалки «для себя»: сценарий видеоинтервью и тексты для профилей hh.uz / LinkedIn / argos."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from data import *  # noqa: E402,F403
from common import h, save as _save  # noqa: E402

OUT = sys.argv[1]


def save(*a):
    _save(OUT, *a)


CSS = """
@page { size: A4; margin: 15mm 16mm; }
body { font-family: Arial, 'Liberation Sans', sans-serif; font-size: 11pt; line-height: 1.45; color: #1d1d1f; }
.todo { background: #fff3a0; }
h1 { font-size: 17pt; color: #1f4e79; margin: 0 0 4px; }
h2 { font-size: 12.5pt; color: #1f4e79; margin: 14px 0 4px; border-bottom: 1px solid #c9d6e3; }
h3 { font-size: 11pt; margin: 10px 0 2px; }
p { margin: 0 0 6px; } .muted { color: #555; font-size: 10pt; }
.q { break-inside: avoid; margin-top: 12px; }
.q .t { font-size: 9.5pt; color: #1f4e79; font-weight: bold; }
.ans { border-left: 3px solid #1f4e79; padding: 4px 10px; background: #f4f7fb; }
.cue { font-size: 10pt; color: #333; margin-top: 3px; }
.copy { border: 1px dashed #9db3cc; padding: 6px 10px; background: #fafcff; margin: 3px 0 8px; }
ul { margin: 2px 0 6px; padding-left: 18px; } li { margin-bottom: 2px; }
table { border-collapse: collapse; width: 100%; font-size: 10pt; }
td, th { border: 1px solid #c9d6e3; padding: 3px 6px; text-align: left; vertical-align: top; }
th { background: #eef3f9; }
"""

# =========================================================================== ВИДЕОИНТЕРВЬЮ
QA = [
    ("1. Кратко расскажите о себе. Ваша самоценность и профессиональная ценность", "≈ 50 с",
     "Здравствуйте! Меня зовут Мухаммад Рузибоев. Я студент 4-го курса Ташкентского государственного "
     "экономического университета, направление «Искусственный интеллект», и претендую на должность "
     "видеомонтажёра и моушн-дизайнера. Параллельно с учёбой я работаю на фрилансе под своим брендом "
     "GraphicArts: монтирую ролики для соцсетей — Reels, Shorts, TikTok. Последний проект — рекламный ролик "
     "для платёжного сервиса Muhr: тридцать две секунды, восемь сцен и собственная музыка. "
     "Моя профессиональная ценность в том, что я соединяю креатив монтажёра и технический подход из "
     "AI-образования: я не только монтирую, но и автоматизирую рутину, чтобы правки делались быстрее. "
     "Как человек я ответственный и спокойно принимаю правки — для меня это нормальная часть работы.",
     "Имя → 4 курс ТГЭУ, ИИ → должность → GraphicArts, Reels/Shorts → Muhr: 32 с, 8 сцен → креатив + техника → ответственность"),
    ("2. Почему вы выбрали именно эту должность и эту организацию?", "≈ 45 с",
     "Короткое видео сегодня — главный способ рассказать о продукте, и мне нравится, что результат монтажа "
     "сразу виден в цифрах: досмотры, клики, продажи. Компания Uzum выпускает очень много видеоконтента — "
     "промо распродаж, ролики о товарах, рекламу Uzum Bank. Мне интересен такой масштаб, когда ролик смотрят "
     "сотни тысяч людей. К тому же мой проект Muhr — это реклама платёжного сервиса, то есть я уже умею "
     "объяснять финансовый продукт за тридцать секунд. Поэтому думаю, что быстро включусь в работу вашей команды.",
     "Видео = результат в цифрах → Uzum: много контента, масштаб → Muhr — тоже финтех → быстро включусь"),
    ("3. Каковы ваши сильные и слабые стороны?", "≈ 45 с",
     "Первая сильная сторона — внимание к деталям: в ролике Muhr каждый звук — щелчок замка, монеты, клики "
     "клавиш — точно совпадает с движением в кадре. Вторая — техническая база: благодаря учёбе я умею "
     "писать код и могу автоматизировать повторяющиеся задачи. Третья — быстро осваиваю новые инструменты. "
     "Слабая сторона — иногда я слишком долго шлифую детали и рискую затянуть сроки. Сейчас я работаю так: "
     "сначала собираю черновую версию целиком и показываю заказчику, а детали дорабатываю после "
     "согласования. Так я укладываюсь в дедлайны.",
     "Детали (звук в кадр) → код/автоматизация → быстро учусь | Слабость: перфекционизм → черновик сначала"),
    ("4. Пример решения в сложной ситуации (метод STAR)", "≈ 60 с",
     "<b>Ситуация.</b> Нужно было сделать рекламный ролик для платёжного сервиса Muhr, но без бюджета на "
     "лицензионную музыку и стоковые шаблоны. <b>Задача.</b> Сделать ролик на тридцать две секунды в формате "
     "4:5 для ленты соцсетей, причём музыка должна совпадать с движением в кадре. <b>Действия.</b> Я разбил "
     "ролик на восемь сцен по четыре секунды на ритмической сетке 120 ударов в минуту. Анимацию собрал "
     "кодом вместе с AI-ассистентом, а музыку синтезировал на Python и привязал звуки к событиям в кадре. "
     "Сборку автоматизировал, чтобы весь ролик пересобирался одной командой. <b>Результат.</b> Готовый ролик "
     "1080 на 1350, шестьдесят кадров в секунду, громкость −14 LUFS — это стандарт соцсетей. В нём нет ни "
     "одного чужого сэмпла, значит, нет проблем с авторскими правами, а любая правка занимает минуты, а не часы.",
     "S: Muhr без бюджета на музыку → T: 32 с, 4:5, звук в такт → A: 8 сцен × 4 с, 120 BPM, код + AI, музыка на Python → R: 60 к/с, −14 LUFS, без чужих сэмплов, правки за минуты"),
    ("5. Где вы видите себя через пять лет?", "≈ 40 с",
     "Через пять лет я вижу себя ведущим моушн-дизайнером или руководителем небольшой видеокоманды в крупной "
     "компании. Хочу, чтобы мои ролики давали измеримый результат — рост досмотров и продаж. План такой: "
     "в ближайший год углубить After Effects и освоить 3D в Blender, в 2027 году получить диплом, а дальше "
     "внедрять AI-инструменты в видеопродакшн, чтобы команда выпускала больше контента без потери качества. "
     "Спасибо за ваше время! Буду рад работать в вашей команде.",
     "Ведущий моушн-дизайнер / лид видеокоманды → измеримый результат → After Effects + Blender → диплом 2027 → AI в продакшене → «Спасибо!»"),
]

qa = "".join(f"<div class='q'><div class='t'>{q} · {t}</div><div class='ans'>{a}</div>"
             f"<div class='cue'><b>Тезисы:</b> {c}</div></div>" for q, t, a, c in QA)
save("interview_script.html", f"""
<h1>Видеоинтервью — сценарий ответов</h1>
<p class="muted">Должность: видеомонтажёр / моушн-дизайнер · пример организации: Uzum (можно заменить на свою
— тогда перепиши 2-й ответ). Общая длительность ≈ 4 мин (норма 3–5 мин). Не читай с листа: прочитай 3–5 раз,
потом говори по тезисам своими словами.</p>
{qa}
<h2>Перед записью — чек-лист</h2>
<ul>
<li>Телефон горизонтально, на штативе/опоре, камера на уровне глаз; режим «Не беспокоить».</li>
<li>Свет спереди (сядь лицом к окну), фон — однотонная стена, без кровати и вещей в кадре.</li>
<li>Рубашка или пиджак, без надписей; в кадре лицо и плечи.</li>
<li>Тестовая запись 10 секунд → проверь звук в наушниках.</li>
<li>Одним дублем, без монтажа. Начни с улыбки, смотри в объектив, не на экран.</li>
<li>Название файла: <b>Рузибоев_Мухаммад</b> · отправить в группу Telegram, не в личку.</li>
</ul>
<h2>Что могут спросить устно (будь готов)</h2>
<ul>
<li>Какой софт используешь и почему? → назови только то, чем реально владеешь (и убери лишнее из резюме).</li>
<li>Что такое LUFS и почему −14? → единица громкости; −14 LUFS — норма YouTube/Instagram, площадка не «приглушает» ролик.</li>
<li>Почему 120 BPM и сцены по 4 секунды? → 120 ударов/мин = 2 удара в секунду, 4 с = 2 такта: склейки попадают в бит.</li>
<li>Какую роль играл AI-ассистент? → помогал писать код анимации; идея, сценарий, сцены и проверка результата — мои.</li>
</ul>
""", CSS, "Видеоинтервью")

# =========================================================================== ПРОФИЛИ
ABOUT_EN = ("Video editor and motion designer based in Tashkent, and a 4th-year Artificial Intelligence student at "
            "Tashkent State University of Economics. I edit short-form videos for social media (Reels, Shorts, "
            "TikTok) and create motion-graphics ads. My latest project is a 32-second promo for the Muhr payment "
            "service: 8 scenes on a 120 BPM grid, original music synthesised in Python, −14 LUFS loudness. "
            "I combine creative editing with a technical background — I automate routine work so revisions take "
            "minutes, not hours. Open to Video Editor / Motion Designer roles.")
ABOUT_RU = ("Видеомонтажёр и моушн-дизайнер из Ташкента, студент 4-го курса ТГЭУ по направлению «Искусственный "
            "интеллект». Монтирую короткие ролики для соцсетей (Reels, Shorts, TikTok) и делаю рекламную "
            "моушн-графику. Последний проект — промо-ролик для платёжного сервиса Muhr: 32 с, 8 сцен на сетке "
            "120 BPM, собственная музыка, громкость −14 LUFS. Соединяю креатив и технический подход: автоматизирую "
            "рутину, чтобы правки занимали минуты, а не часы. Ответственно отношусь к срокам и спокойно принимаю правки.")

save("profiles_guide.html", f"""
<h1>Задания 4–5: что заполнить в профилях</h1>
<p class="muted">Преподаватель проверит: фото (лицо видно, светлый фон, деловая одежда), имя, заголовок, о себе,
образование, опыт, навыки, языки, контакты — и что всё совпадает с резюме и CV. После заполнения сделай заново
скриншоты главных страниц (на них должны быть видны <b>фото и имя</b>) и замени ими файлы в папках 4 и 5.</p>

<h2>⚠ Сейчас на твоих скриншотах</h2>
<table><tr><th>Профиль</th><th>Чего не хватает</th></tr>
<tr><td>hh.uz</td><td>Нет фото («Добавим фото?»); статус «Не ищу работу» → поставь «Активно ищу работу»;
резюме «Начинающий специалист» не опубликовано — допиши или удали; контакты: нет телефона.</td></tr>
<tr><td>LinkedIn</td><td>Нет фото, нет Headline (сейчас «Student at…»), нет About, нет опыта, нет навыков (нужно ≥ 5), нет языков.</td></tr>
<tr><td>vacancy.argos.uz</td><td>Телефон и email не введены; «Mutaxassisligi» пусто; «Chet tillari: Yo‘q» — исправь на русский и английский;
заполни вкладки Ma’lumoti, Mehnat faoliyati, Qarindoshlari.</td></tr></table>

<h2>LinkedIn</h2>
<h3>Headline</h3><div class="copy">Video Editor &amp; Motion Designer | AI student at TSUE | Reels, Shorts, promo videos</div>
<h3>About</h3><div class="copy">{ABOUT_EN}</div>
<h3>Experience → Add position</h3><div class="copy"><b>Title:</b> Video Editor &amp; Motion Designer ·
<b>Employment type:</b> Freelance · <b>Company:</b> GraphicArts · <b>Location:</b> Tashkent, Uzbekistan (Remote) ·
<b>Start:</b> {h(FREELANCE_FROM_EN)} · I currently work here<br><b>Description:</b> Editing short-form videos for social
media (Reels, Shorts, TikTok) in 9:16, 4:5 and 16:9. Muhr promo (10/2026): 32 s, 1080×1350, 60 fps, 8 scenes,
original music, −14 LUFS.</div>
<h3>Education</h3><div class="copy">Tashkent State University of Economics · Bachelor’s degree, Artificial Intelligence · 2023 – 2027</div>
<h3>Skills (добавь минимум 5)</h3><div class="copy">Video Editing · Motion Graphics · Adobe Premiere Pro ·
Adobe After Effects · Color Correction · Sound Design · DaVinci Resolve · Python</div>
<h3>Languages</h3><div class="copy">Uzbek — Native or bilingual · Russian — Full professional · English — Limited working</div>
<p>Ещё: «Open to» → Finding a new job → Video Editor, Motion Designer. В Featured загрузи ролик Muhr.</p>

<h2>hh.uz — резюме «Видеомонтажёр»</h2>
<table>
<tr><th>Поле</th><th>Что вписать</th></tr>
<tr><td>Должность</td><td>Видеомонтажёр / моушн-дизайнер</td></tr>
<tr><td>Опыт работы</td><td>GraphicArts (фриланс), {h(FREELANCE_FROM)} — по настоящее время, «Видеомонтажёр и моушн-дизайнер»;
обязанности — как в резюме (2 пункта + проект Muhr)</td></tr>
<tr><td>Образование</td><td>Высшее (бакалавр) — Ташкентский государственный экономический университет, «Искусственный интеллект», 2027</td></tr>
<tr><td>Ключевые навыки</td><td>Видеомонтаж · Моушн-дизайн · Adobe Premiere Pro · Adobe After Effects · DaVinci Resolve ·
Цветокоррекция · Саунд-дизайн · Python</td></tr>
<tr><td>Языки</td><td>Узбекский — родной · Русский — C1 · Английский — B1</td></tr>
<tr><td>Контакты</td><td>{h(PHONE)} · {EMAIL} · Telegram {TELEGRAM}</td></tr>
</table>
<h3>О себе</h3><div class="copy">{ABOUT_RU}</div>

<h2>vacancy.argos.uz</h2>
<table>
<tr><th>Поле</th><th>Что вписать</th></tr>
<tr><td>Telefon raqami / Email</td><td>{h(PHONE)} · {EMAIL}</td></tr>
<tr><td>Mutaxassisligi</td><td>Sun’iy intellekt (talaba, 4-kurs)</td></tr>
<tr><td>Chet tillari</td><td>Rus tili — erkin (C1); Ingliz tili — o‘rta (B1)</td></tr>
<tr><td>Ma’lumoti</td><td>Toshkent davlat iqtisodiyot universiteti, «Sun’iy intellekt», 2023–2027; maktab № __, Termiz</td></tr>
<tr><td>Mehnat faoliyati</td><td>{h(FREELANCE_FROM)} – h. v.: GraphicArts, videomontajchi va motion-dizayner (frilans)</td></tr>
<tr><td>Qarindoshlari</td><td>как в объективке (отец, мать, братья/сёстры)</td></tr>
</table>
<p>Для сдачи: скриншоты главной страницы и вкладок (Umumiy ma’lumotlar, Ma’lumoti, Mehnat faoliyati, Qarindoshlari).</p>
""", CSS, "Профили")
