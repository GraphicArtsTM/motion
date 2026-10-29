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
     "видеомонтажёра и моушн-дизайнера. С 2023 года я работаю на фрилансе под брендом GraphicArts: "
     "монтирую ролики для соцсетей — Reels, Shorts, TikTok — и делаю моушн-графику. А начинал я с игр: "
     "после школы освоил Unity и сделал две игры для Android — AirFly и UzbekAdventure, а ещё два года "
     "был графическим дизайнером в семейном бизнесе. Моя ценность в том, что я смотрю на видео сразу глазами "
     "дизайнера, разработчика и монтажёра: понимаю и картинку, и технику. Как человек я ответственный "
     "и спокойно принимаю правки — для меня это нормальная часть работы.",
     "Имя → 4 курс ТГЭУ, ИИ → должность → GraphicArts с 2023: Reels/Shorts, моушн → начинал с игр: AirFly, UzbekAdventure → дизайнер в семейном бизнесе → дизайнер + разработчик + монтажёр"),
    ("2. Почему вы выбрали именно эту должность и эту организацию?", "≈ 45 с",
     "Короткое видео сегодня — главный способ рассказать о продукте, и мне нравится, что результат монтажа "
     "сразу виден в цифрах: досмотры, клики, продажи. Компания Uzum выпускает очень много видеоконтента — "
     "промо распродаж, ролики о товарах, рекламу Uzum Bank. Мне интересен такой масштаб, когда ролик смотрят "
     "сотни тысяч людей. А ещё в семейном бизнесе я понял, что реклама должна не просто красиво выглядеть, "
     "а продавать, — и этот опыт я хочу применить в вашей команде.",
     "Видео = результат в цифрах → Uzum: много контента, масштаб → опыт семейного бизнеса: реклама должна продавать"),
    ("3. Каковы ваши сильные и слабые стороны?", "≈ 45 с",
     "Первая сильная сторона — внимание к деталям: в играх я понял, что мелочь в интерфейсе или анимации "
     "меняет всё впечатление, и в монтаже так же. Вторая — техническая база: я программирую на C# и Python "
     "и могу разобраться в любом инструменте. Третья — самостоятельность: Unity и монтаж я освоил сам. "
     "Слабая сторона — иногда я слишком долго шлифую детали и рискую затянуть сроки. Сейчас я работаю так: "
     "сначала собираю черновую версию целиком и показываю заказчику, а детали дорабатываю после "
     "согласования. Так я укладываюсь в дедлайны.",
     "Детали (игры → монтаж) → C#/Python → освоил сам | Слабость: перфекционизм → черновик сначала"),
    ("4. Пример решения в сложной ситуации (метод STAR)", "≈ 60 с",
     "<b>Ситуация.</b> Когда я закончил свою игру UzbekAdventure, о ней никто не знал, а денег на рекламу "
     "не было. <b>Задача.</b> Нужно было самому сделать трейлер, который за тридцать секунд покажет, чем "
     "игра интересна. <b>Действия.</b> Я написал короткий сценарий, записал геймплей и выбрал самые яркие "
     "моменты. Смонтировал динамичный трейлер под музыку, добавил титры и анимированный логотип и сделал "
     "отдельную вертикальную версию для соцсетей. <b>Результат.</b> Трейлер стал главным материалом для "
     "продвижения: я выложил его в соцсети и Telegram, и люди начали скачивать игру и писать отзывы. "
     "А для меня это стало поворотом: я понял, что монтаж мне нравится больше всего, и с 2023 года занимаюсь "
     "видео профессионально.",
     "S: UzbekAdventure готова, никто не знает, нет бюджета → T: трейлер 30 с → A: сценарий, геймплей, монтаж под музыку, титры, логотип, вертикальная версия → R: соцсети + Telegram, скачивания и отзывы → ушёл в видео"),
    ("5. Где вы видите себя через пять лет?", "≈ 40 с",
     "Через пять лет я вижу себя ведущим моушн-дизайнером или руководителем небольшой видеокоманды в крупной "
     "компании. Хочу, чтобы мои ролики давали измеримый результат — рост досмотров и продаж. План такой: "
     "в ближайший год углубить After Effects и освоить 3D в Blender — это пригодится и в рекламе, и в играх, "
     "в 2027 году получить диплом, а дальше внедрять AI-инструменты в видеопродакшн, чтобы команда выпускала "
     "больше контента без потери качества. Спасибо за ваше время! Буду рад работать в вашей команде.",
     "Ведущий моушн-дизайнер / лид видеокоманды → измеримый результат → After Effects + Blender → диплом 2027 → AI в продакшене → «Спасибо!»"),
]

qa = "".join(f"<div class='q'><div class='t'>{q} · {t}</div><div class='ans'>{a}</div>"
             f"<div class='cue'><b>Тезисы:</b> {c}</div></div>" for q, t, a, c in QA)
save("interview_script.html", f"""
<h1>Видеоинтервью — сценарий ответов</h1>
<p class="muted">Должность: видеомонтажёр / моушн-дизайнер · пример организации: Uzum (можно заменить на свою
— тогда перепиши 2-й ответ). Общая длительность ≈ 4 мин (норма 3–5 мин). Не читай с листа: прочитай 3–5 раз,
потом говори по тезисам своими словами. Если у игры есть цифры (скачивания, отзывы) — назови их в 4-м ответе.</p>
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
<li>Какие игры ты сделал и на чём? → AirFly и UzbekAdventure, Unity + C#, для Android. Будь готов коротко рассказать, в чём суть каждой.</li>
<li>Как связаны игры и видеомонтаж? → трейлеры к своим играм: сценарий, динамика, ритм — то же, что в рекламном ролике.</li>
<li>Что ты делал в семейном бизнесе? → логотипы, баннеры, посты для соцсетей, помогал с клиентами (2021–2023).</li>
<li>Какой софт используешь и почему? → назови только то, чем реально владеешь (и убери лишнее из резюме).</li>
</ul>
""", CSS, "Видеоинтервью")

# =========================================================================== ПРОФИЛИ
ABOUT_EN = ("Video editor and motion designer based in Tashkent, and a 4th-year Artificial Intelligence student at "
            "Tashkent State University of Economics. Since 2023 I edit short-form videos for social media (Reels, "
            "Shorts, TikTok) and create motion graphics. I started with game development: I built two Android "
            "games in Unity (C#) — AirFly and UzbekAdventure — and edited their trailers myself, and I worked as a "
            "graphic designer in a family business. I look at video as a designer, a developer and an editor at "
            "once. Open to Video Editor / Motion Designer roles.")
ABOUT_RU = ("Видеомонтажёр и моушн-дизайнер из Ташкента, студент 4-го курса ТГЭУ по направлению «Искусственный "
            "интеллект». С 2023 года монтирую короткие ролики для соцсетей (Reels, Shorts, TikTok) и делаю "
            "моушн-графику. Начинал с разработки игр: создал на Unity (C#) две игры для Android — AirFly и "
            "UzbekAdventure — и сам смонтировал к ним трейлеры; два года работал графическим дизайнером в семейном "
            "бизнесе. Ответственно отношусь к срокам и спокойно принимаю правки.")

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
заполни вкладки Ma’lumoti и Mehnat faoliyati (родственники уже есть).</td></tr></table>

<h2>LinkedIn</h2>
<h3>Headline</h3><div class="copy">Video Editor &amp; Motion Designer | Game developer (Unity) | AI student at TSUE</div>
<h3>About</h3><div class="copy">{ABOUT_EN}</div>
<h3>Experience → Add position (3 позиции)</h3><div class="copy">
<b>1.</b> Video Editor &amp; Motion Designer · Freelance · GraphicArts · Tashkent (Remote) · Sep 2023 – Present ·
<i>Editing short-form videos for social media (Reels, Shorts, TikTok); motion graphics — animated logos, titles, intros.</i><br>
<b>2.</b> Mobile Game Developer · Self-employed · Jul 2021 – Present ·
<i>Built 2 Android games in Unity (C#): AirFly and UzbekAdventure; edited their promo trailers.</i><br>
<b>3.</b> Graphic Designer · Family business · Termez · Jul 2021 – Aug 2023 ·
<i>Logos, banners and social-media posts; customer service.</i></div>
<h3>Education</h3><div class="copy">Tashkent State University of Economics · Bachelor’s degree, Artificial Intelligence · 2023 – 2027</div>
<h3>Skills (добавь минимум 5)</h3><div class="copy">Video Editing · Motion Graphics · Adobe Premiere Pro ·
Adobe After Effects · Color Correction · Unity · C# · Graphic Design</div>
<h3>Languages</h3><div class="copy">Uzbek — Native or bilingual · Russian — Full professional · English — Limited working</div>
<p>Ещё: «Open to» → Finding a new job → Video Editor, Motion Designer. В Projects добавь AirFly и UzbekAdventure.</p>

<h2>hh.uz — резюме «Видеомонтажёр»</h2>
<table>
<tr><th>Поле</th><th>Что вписать</th></tr>
<tr><td>Должность</td><td>Видеомонтажёр / моушн-дизайнер</td></tr>
<tr><td>Опыт работы</td><td>1) GraphicArts (фриланс), сентябрь 2023 — по настоящее время, «Видеомонтажёр и моушн-дизайнер»;<br>
2) Разработчик мобильных игр (собственные проекты), июль 2021 — по настоящее время;<br>
3) Семейный бизнес, Термез, июль 2021 — август 2023, «Графический дизайнер». Обязанности — как в резюме.</td></tr>
<tr><td>Образование</td><td>Высшее (бакалавр) — Ташкентский государственный экономический университет, «Искусственный интеллект», 2027</td></tr>
<tr><td>Ключевые навыки</td><td>Видеомонтаж · Моушн-дизайн · Adobe Premiere Pro · Adobe After Effects · DaVinci Resolve ·
Цветокоррекция · Unity · C# · Графический дизайн</td></tr>
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
<tr><td>Ma’lumoti</td><td>Toshkent davlat iqtisodiyot universiteti, «Sun’iy intellekt», 2023–2027; Termiz shahridagi 18-maktab, 2010–2021</td></tr>
<tr><td>Mehnat faoliyati</td><td>07.2021 – 08.2023: oilaviy biznes, grafik dizayner (Termiz);<br>
07.2021 – h. v.: mobil o‘yinlar dasturchisi (Unity, C#), shaxsiy loyihalar;<br>
09.2023 – h. v.: GraphicArts, videomontajchi va motion-dizayner (frilans)</td></tr>
</table>
<p>Для сдачи: скриншоты главной страницы и вкладок (Umumiy ma’lumotlar, Ma’lumoti, Mehnat faoliyati, Qarindoshlari).</p>
""", CSS, "Профили")
