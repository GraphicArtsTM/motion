using System.Collections.Generic;
using System.IO;
using System.Text;
using PushPals.UI;
using UnityEditor;
using UnityEditor.U2D.Sprites;
using UnityEngine;

namespace PushPals.EditorTools
{
    /// <summary>
    /// Конвейер картинок интерфейса (Этап 17.1). Меню: PushPals → Интерфейс → Нарезать листы UI.
    /// Берёт листы из Assets/Art/UI/_Source (их не меняет), убирает фон-мадженту (или нарисованную «шахматку»),
    /// чистит розовую кромку, находит кусочки по прозрачным промежуткам, выкидывает крошки, раскладывает по рядам
    /// (слева направо, сверху вниз) и даёт имена из списка — ТОЛЬКО если число кусочков совпало; иначе лист не режется,
    /// а в UiSlicePreview/ кладётся картинка с номерами кусочков, чтобы показать художнику.
    /// Ещё: 9-slice рамки, курсоры 32/64 с горячей точкой (набор Assets/Data/UI/Cursors.asset), копии фонов.
    /// </summary>
    public static class UiSheetTool
    {
        private const string SourceDir = "Assets/Art/UI/_Source/";
        private const string SheetDir = "Assets/Art/UI/Sheets/";
        private const string CursorDir = "Assets/Art/UI/Cursors/";
        private const string BackgroundDir = "Assets/Art/UI/Backgrounds/";
        private const string CursorSetPath = "Assets/Data/UI/Cursors.asset";
        private const string PreviewDir = "UiSlicePreview/"; // в корне проекта, не в Assets (в git не идёт)
        private const string UpscaledDir = "Assets/Art/UI/_Upscaled~/"; // увеличенные Upscayl (Tools/upscale_ui.py) — Unity их не импортирует
        private const int Pad = 6; // запас вокруг кусочка (мягкая тень), в пикселях исходника

        // Все размеры в таблицах — в пикселях исходника из _Source; увеличенный лист больше в k раз
        private static int pad = Pad;
        private static float borderScale = 1f;
        private static float pixelsPerUnit = 100f; // увеличенный ×2 лист — 200: «родной» размер спрайта как у исходника

        private enum Back { Magenta, Checker }

        private class Sheet
        {
            public string file;
            public Back back = Back.Magenta;
            public string[] names;
            public int gap = 18;        // кусочки ближе этого (пиксели) — одна картинка
            public int edge = 8;        // ширина кромки, где убирается маджента-оттенок
            public int minArea = 150;   // меньше — крошка
            public int minThickness = 0; // уже этого (пиксели) по ширине или высоте — не картинка, а линия-разделитель
            public RectInt[] groups = new RectInt[0];        // всё внутри — одна картинка (x, y от левого верхнего угла)
            public Vector2Int[] holes = new Vector2Int[0];   // нарисованная «шахматка» внутри — сделать прозрачной
            public float scale = 1f;    // уменьшить лист после очистки (одиночная крупная картинка — к размеру остальных)
            public Sheet MemberwiseCloneSheet() => (Sheet)MemberwiseClone();
        }

        // Имя «-» — кусочек есть на листе, но спрайт из него не делается (заменён отдельным файлом)
        private const string Skip = "-";

        private static readonly Sheet[] Sheets =
        {
            new Sheet
            {
                file = "ui_buttons",
                edge = 30, // свечение menu_highlight розовое от фона — его надо очистить целиком
                // Четыре уголка рамки фокуса — одна картинка (9-slice: уголки в рамке, середина пустая)
                groups = new[] { new RectInt(680, 430, 260, 175) },
                names = new[] { "btn_primary_normal", "btn_primary_hover", "btn_primary_pressed", "btn_primary_disabled",
                    "btn_secondary_normal", "btn_secondary_hover", "btn_secondary_pressed", "btn_secondary_disabled",
                    Skip /* menu_highlight — отдельным файлом */, "menu_pointer", "focus_frame", "btn_square", "toggle_off", "toggle_on", "checkbox_off", "checkbox_on" },
            },
            new Sheet
            {
                file = "ui_panels",
                holes = new[] { new Vector2Int(1083, 190) }, // внутри рамки card_level нарисована «шахматка»
                names = new[] { "panel_dialog", "banner_header", "tooltip", "card_level", "tab_off", "tab_on", "input_field", "dropdown",
                    "slider_track", "slider_fill", "slider_knob", "scroll_thumb" },
            },
            new Sheet
            {
                file = "ui_icons_main",
                names = new[] { "ic_play", "ic_settings", "ic_exit", "ic_back", "ic_pause", "ic_restart", "ic_invite", "ic_lobby",
                    "ic_mic", "ic_mic_off", "ic_sound", "ic_sound_off", "ic_golden_match", "ic_golden_match_empty", "ic_lock", "ic_check",
                    "ic_cross", "ic_trophy", "ic_hat", "ic_brush", "ic_graphics", Skip /* ic_keyboard — отдельным файлом */, "ic_gamepad", "ic_language" },
            },
            new Sheet
            {
                file = "ui_icons_game",
                names = new[] { "ic_fire", "ic_water", "ic_magnet", "ic_heavy", "ic_light", "ic_small", "ic_ghost", "ic_traitor",
                    "ic_vote", "ic_infinity", "ic_timer", "ic_key", "em_heart", "em_angry", "em_exclaim", "em_question", "em_wave",
                    "em_laugh", "ic_ping", "ic_speaking", "ic_host", "ic_connection", "ic_warning", "ic_checkpoint" },
            },
            new Sheet
            {
                file = "ui_hud",
                back = Back.Checker, // перерисован на нарисованной «шахматке»
                holes = new[] { new Vector2Int(350, 105) }, // внутри рамки полосы горения
                groups = new[] { new RectInt(395, 615, 180, 175) }, // две стрелки hud_swap — одна картинка
                names = new[] { "hud_burn_frame", "hud_burn_fill", "badge_red", "badge_green", "badge_blue", "badge_purple",
                    "hud_collectible_plate", "hud_nametag", "hud_backpack", "hud_swap", "hud_timer_plate", "hud_team_plate" },
            },
            new Sheet
            {
                file = "ui_cursors",
                names = new[] { "cur_default", "cur_hover", "cur_hand_open", "cur_hand_closed", "cur_text", "cur_busy", "cur_forbidden", "cur_aim" },
            },
            new Sheet
            {
                file = "ui_menu_objects",
                gap = 24, // ниточка у банок-телефона
                names = new[] { "menu_obj_play", "menu_obj_online", "menu_obj_settings", "menu_obj_wardrobe", "menu_obj_collection", "menu_obj_exit" },
            },
            // Отсчёт перед стартом (Countdown): цифры 5…1 — между ними на листе тонкие чёрные линии, их выкидываем
            new Sheet
            {
                file = "ui_countdown_digits",
                minThickness = 24,
                names = new[] { "cd_5", "cd_4", "cd_3", "cd_2", "cd_1" },
            },
            // Слова: сверху лента «Старт через», под ней табличка «Поехали!»
            new Sheet { file = "ui_countdown_words_ru", names = new[] { "cd_title_ru", "cd_go_ru" } },
            new Sheet { file = "ui_countdown_words_en", names = new[] { "cd_title_en", "cd_go_en" } },
            // Отдельные картинки вместо кусочков листов
            new Sheet { file = "menu_highlight", names = new[] { "menu_highlight" }, minArea = 2000 },
            new Sheet { file = "ic_keyboard", names = new[] { "ic_keyboard" }, minArea = 2000, scale = 0.15f }, // к размеру иконок (~150 px)
            new Sheet { file = "ui_logo", back = Back.Checker, names = new[] { "logo_full" }, minArea = 2000 },
            new Sheet { file = "ui_logo_icon", back = Back.Checker, names = new[] { "logo_icon" }, minArea = 2000 },
        };

        // 9-slice: рамка в пикселях листа (слева, снизу, справа, сверху). Середина тянется, уголки — нет.
        private static readonly Dictionary<string, Vector4> Borders = new Dictionary<string, Vector4>
        {
            { "btn_primary_normal", new Vector4(26, 26, 26, 26) }, { "btn_primary_hover", new Vector4(26, 26, 26, 26) },
            { "btn_primary_pressed", new Vector4(26, 26, 26, 26) }, { "btn_primary_disabled", new Vector4(26, 26, 26, 26) },
            { "btn_secondary_normal", new Vector4(26, 26, 26, 26) }, { "btn_secondary_hover", new Vector4(26, 26, 26, 26) },
            { "btn_secondary_pressed", new Vector4(26, 26, 26, 26) }, { "btn_secondary_disabled", new Vector4(26, 26, 26, 26) },
            { "menu_highlight", new Vector4(22, 26, 22, 14) }, // свечение — кодом
            { "focus_frame", new Vector4(56, 52, 56, 52) },
            { "btn_square", new Vector4(28, 28, 28, 28) },
            { "panel_dialog", new Vector4(44, 44, 44, 44) },
            { "banner_header", new Vector4(80, 0, 80, 0) },
            { "tooltip", new Vector4(24, 40, 24, 16) },
            { "card_level", new Vector4(24, 24, 24, 24) },
            { "tab_off", new Vector4(36, 16, 36, 36) }, { "tab_on", new Vector4(36, 16, 36, 36) },
            { "input_field", new Vector4(20, 18, 20, 18) },
            { "dropdown", new Vector4(18, 30, 60, 30) },
            { "slider_track", new Vector4(28, 0, 28, 0) },
            { "slider_fill", new Vector4(10, 0, 10, 0) },
            { "scroll_thumb", new Vector4(0, 24, 0, 24) },
            { "hud_burn_frame", new Vector4(30, 0, 30, 0) }, { "hud_burn_fill", new Vector4(20, 0, 20, 0) },
            { "hud_collectible_plate", new Vector4(80, 0, 34, 0) }, { "hud_nametag", new Vector4(90, 0, 24, 0) }, // тянуть только в ширину
            { "hud_team_plate", new Vector4(26, 18, 26, 18) },
        };

        // Курсоры: у этих горячая точка — кончик стрелки, у остальных — середина
        private static readonly HashSet<string> TipCursors = new HashSet<string> { "cur_default", "cur_hover" };
        // Горячая точка вручную (доля от левого верхнего угла): у горящей стрелки кончик — головка под пламенем,
        // само пламя в обводке мешает найти кончик автоматически. После перерисовки курсора — проверить.
        private static readonly Dictionary<string, Vector2> HotspotOverride = new Dictionary<string, Vector2>
        {
            { "cur_hover", new Vector2(7.5f / 64f, 17f / 64f) },
        };

        // ---------- Картинка: пиксели сверху вниз ----------
        private class Img
        {
            public int w, h;
            public Color[] c;
            public Img(int w, int h) { this.w = w; this.h = h; c = new Color[w * h]; }
            public Color this[int x, int y] { get => c[y * w + x]; set => c[y * w + x] = value; }
        }

        private struct Box
        {
            public int minX, minY, maxX, maxY, area;
            public int W => maxX - minX + 1;
            public int H => maxY - minY + 1;
            public float CX => (minX + maxX) * 0.5f;
            public float CY => (minY + maxY) * 0.5f;
            public bool Contains(float x, float y) => x >= minX && x <= maxX && y >= minY && y <= maxY;
            public void Add(Box b)
            {
                minX = Mathf.Min(minX, b.minX); minY = Mathf.Min(minY, b.minY);
                maxX = Mathf.Max(maxX, b.maxX); maxY = Mathf.Max(maxY, b.maxY);
                area += b.area;
            }
        }

        [MenuItem("PushPals/Интерфейс/Нарезать листы UI")]
        public static string ProcessAll()
        {
            Directory.CreateDirectory(SheetDir);
            Directory.CreateDirectory(PreviewDir);
            var report = new StringBuilder();
            var cut = new Dictionary<string, KeyValuePair<Img, List<Box>>>();
            foreach (var s in Sheets) report.AppendLine(Process(s, cut));
            KeyValuePair<Img, List<Box>> cursors;
            report.AppendLine(cut.TryGetValue("ui_cursors", out cursors) ? MakeCursors(cursors.Key, cursors.Value) : "Курсоры: лист не нарезан — пропущено");
            report.AppendLine(CopyBackgrounds());
            report.AppendLine(FillRegistry());
            report.AppendLine("Превью нарезки и растяжения 9-slice: " + Path.GetFullPath(PreviewDir));
            AssetDatabase.Refresh();
            Debug.Log(report.ToString());
            return report.ToString();
        }

        private static string Process(Sheet s, Dictionary<string, KeyValuePair<Img, List<Box>>> cut)
        {
            string src = SourceDir + s.file + ".png";
            if (!File.Exists(src)) return s.file + ": нет файла " + src;
            // Есть увеличенный Upscayl — берём его (чище края), размеры из таблиц умножаем
            string up = UpscaledDir + s.file + ".png";
            bool upscaled = File.Exists(up);
            var img = Load(upscaled ? up : src);
            float k = upscaled ? img.w / (float)WidthOf(src) : 1f;
            s = Scaled(s, k);
            if (s.back == Back.Magenta) KeyMagenta(img, s.edge, Mathf.RoundToInt(5 * k));
            else KeyChecker(img, BorderSeeds(img));
            if (s.holes.Length > 0) KeyChecker(img, s.holes);
            if (s.scale != 1f) img = Resize(img, Mathf.RoundToInt(img.w * s.scale), Mathf.RoundToInt(img.h * s.scale));
            // После уменьшения (s.scale) — расстояния и рамки в новых пикселях
            float kPost = k * s.scale;
            pixelsPerUnit = 100f * k;
            pad = Mathf.RoundToInt(Pad * kPost);
            borderScale = kPost;
            s.gap = Mathf.RoundToInt(s.gap * s.scale);
            s.minArea = Mathf.RoundToInt(s.minArea * s.scale * s.scale);
            s.minThickness = Mathf.RoundToInt(s.minThickness * s.scale);

            var boxes = Merge(Components(img), s);
            boxes.RemoveAll(b => b.area < s.minArea || Mathf.Min(b.W, b.H) < s.minThickness);
            boxes = Order(boxes);
            ClearOutside(img, boxes);

            bool ok = boxes.Count == s.names.Length;
            string path = SheetDir + s.file + ".png";
            Save(img, path);
            ImportSheet(path, img, boxes, ok ? s.names : null);
            SavePreview(img, boxes, ok, PreviewDir + s.file + ".png");
            if (!ok) return s.file + ": НЕ СОВПАЛО — найдено " + boxes.Count + ", в списке " + s.names.Length
                              + ". Лист не нарезан, номера кусочков — в " + PreviewDir + s.file + ".png";
            cut[s.file] = new KeyValuePair<Img, List<Box>>(img, boxes);
            int sliced = SaveSlicePreview(img, boxes, s.names, PreviewDir + s.file + "_9slice.png");
            return s.file + ": " + boxes.Count + " из " + s.names.Length + " ✓" + (sliced > 0 ? ", 9-slice: " + sliced : "") + (upscaled ? " (увеличенный ×" + k.ToString("0.#") + ")" : "");
        }

        // Копия описания листа с размерами для картинки, увеличенной в k раз (до s.scale)
        private static Sheet Scaled(Sheet s, float k)
        {
            var r = (Sheet)s.MemberwiseCloneSheet();
            r.gap = Mathf.RoundToInt(s.gap * k);
            r.edge = Mathf.RoundToInt(s.edge * k);
            r.minArea = Mathf.RoundToInt(s.minArea * k * k);
            r.minThickness = Mathf.RoundToInt(s.minThickness * k);
            r.groups = new RectInt[s.groups.Length];
            for (int i = 0; i < s.groups.Length; i++)
                r.groups[i] = new RectInt(Mathf.RoundToInt(s.groups[i].x * k * s.scale), Mathf.RoundToInt(s.groups[i].y * k * s.scale),
                                          Mathf.RoundToInt(s.groups[i].width * k * s.scale), Mathf.RoundToInt(s.groups[i].height * k * s.scale));
            r.holes = new Vector2Int[s.holes.Length];
            for (int i = 0; i < s.holes.Length; i++) r.holes[i] = new Vector2Int(Mathf.RoundToInt(s.holes[i].x * k), Mathf.RoundToInt(s.holes[i].y * k));
            return r;
        }

        // Рамка 9-slice спрайта в пикселях текущего листа
        private static bool BorderOf(string name, out Vector4 border)
        {
            if (!Borders.TryGetValue(name, out border)) return false;
            border *= borderScale;
            border = new Vector4(Mathf.Round(border.x), Mathf.Round(border.y), Mathf.Round(border.z), Mathf.Round(border.w));
            return true;
        }

        private static int WidthOf(string path)
        {
            var tex = new Texture2D(2, 2);
            tex.LoadImage(File.ReadAllBytes(path));
            int w = tex.width;
            Object.DestroyImmediate(tex);
            return w;
        }

        // ---------- Фон ----------

        // Маджента: кромка — смесь рисунка F и фона B. F — ближайший сплошной пиксель рисунка; доля рисунка (прозрачность) —
        // положение цвета на отрезке B→F, а если пиксель на нём не лежит (тёмный контур, тень, свечение) — по «розовости»
        // min(r,b) − g. Потом цвет очищается от фона и лишний розовый оттенок убирается. Тени — тёмные полупрозрачные.
        private static void KeyMagenta(Img img, int edge, int solidDist)
        {
            int n = img.w * img.h;
            var border = new List<Color>();
            for (int x = 0; x < img.w; x++) { border.Add(img[x, 0]); border.Add(img[x, img.h - 1]); }
            for (int y = 0; y < img.h; y++) { border.Add(img[0, y]); border.Add(img[img.w - 1, y]); }
            Color bg = Median(border);
            float mBg = Mathf.Max(0.3f, Mathf.Min(bg.r, bg.b) - bg.g);

            var m = new float[n];
            for (int i = 0; i < n; i++) m[i] = Mathf.Min(img.c[i].r, img.c[i].b) - img.c[i].g;
            // Расстояние до чистого фона — обрабатываем только кромку, середина рисунка не трогается
            var gap = new bool[n];
            var dist = new int[n];
            var queue = new Queue<int>();
            for (int i = 0; i < n; i++)
            {
                dist[i] = int.MaxValue;
                // Чистый фон: ярко-розовый или затенённый (тёмная маджента между пальцами, в щелях)
                var c = img.c[i];
                float rb = Mathf.Min(c.r, c.b);
                // …и ярко-розовые «зазоры» фона внутри рисунка (между чертой и микрофоном): увеличение смешало их с красным
                gap[i] = m[i] > 0.28f && rb > 0.65f && c.g < 0.55f;
                if (m[i] > mBg - 0.25f || (rb > 0.35f && c.g < rb * 0.3f) || gap[i]) { dist[i] = 0; queue.Enqueue(i); }
            }
            Bfs(img, dist, queue, edge + 2);
            // Ближайший сплошной пиксель рисунка: не розовый и не ближе 5 пикселей к фону (JPEG размазывает фон внутрь на 2–3)
            var near = new int[n];
            var hop = new int[n];
            for (int i = 0; i < n; i++)
            {
                near[i] = -1;
                if (dist[i] >= solidDist && m[i] < 0.05f) { near[i] = i; queue.Enqueue(i); }
            }
            while (queue.Count > 0)
            {
                int i = queue.Dequeue(), x = i % img.w, y = i / img.w;
                if (hop[i] >= edge + 6) continue;
                for (int k = 0; k < 4; k++)
                {
                    int nx = x + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
                    if (nx < 0 || ny < 0 || nx >= img.w || ny >= img.h) continue;
                    int j = ny * img.w + nx;
                    if (near[j] >= 0) continue;
                    near[j] = near[i]; hop[j] = hop[i] + 1; queue.Enqueue(j);
                }
            }
            var result = new Color[n];
            for (int i = 0; i < n; i++)
            {
                result[i] = img.c[i];
                if (gap[i]) { result[i] = Color.clear; continue; } // розовый зазор — это фон, насквозь
                if (dist[i] > edge || near[i] == i) continue;
                var c = img.c[i];
                // Доля рисунка: если пиксель лежит на отрезке «цвет рисунка рядом → фон» — по положению на нём;
                // иначе (тёмный контур, тень, свечение) — по «розовости» min(r,b) − g
                float a = Mathf.Clamp01((mBg - m[i]) / mBg);
                float spill = 0f;
                if (near[i] >= 0)
                {
                    var f = img.c[near[i]];
                    spill = Mathf.Max(0f, m[near[i]]);
                    var d = new Vector3(f.r - bg.r, f.g - bg.g, f.b - bg.b);
                    var v = new Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b);
                    if (d.sqrMagnitude > 0.05f)
                    {
                        float ap = Mathf.Clamp01(Vector3.Dot(v, d) / d.sqrMagnitude);
                        var rest = v - d * ap;
                        if (Mathf.Max(Mathf.Abs(rest.x), Mathf.Max(Mathf.Abs(rest.y), Mathf.Abs(rest.z))) < 0.15f) a = ap;
                    }
                }
                // …но не меньше, чем нужно, чтобы очищенный цвет остался в пределах 0..1
                a = Mathf.Max(a, MinAlpha(c.r, bg.r), Mathf.Max(MinAlpha(c.g, bg.g), MinAlpha(c.b, bg.b)));
                if (a < 0.06f) { result[i] = Color.clear; continue; }
                var col = a < 1f ? (c - bg * (1f - a)) / a : c;
                col = new Color(Mathf.Clamp01(col.r), Mathf.Clamp01(col.g), Mathf.Clamp01(col.b), a);
                // Розовый оттенок сверх собственного у рисунка — убрать
                float s = Mathf.Min(col.r, col.b) - col.g - spill;
                if (s > 0f) { col.r -= s; col.b -= s; }
                result[i] = col;
            }
            img.c = result;
        }

        // Наименьшая доля рисунка, при которой (c − (1 − a)·B) / a не выходит за 0..1 по этому каналу
        // (с допуском на шум JPEG — иначе фон около 1 по каналу считался непрозрачным)
        private static float MinAlpha(float c, float b)
        {
            const float noise = 0.04f, slack = 0.03f;
            float d = Mathf.Abs(c - b) - noise;
            if (d <= 0f) return 0f;
            return c < b ? d / (b + slack) : d / (1f - b + slack);
        }

        // Нарисованная «шахматка» (серо-белые клетки): заливка от точек через бесцветные светлые пиксели
        private static void KeyChecker(Img img, IEnumerable<Vector2Int> seeds)
        {
            int n = img.w * img.h;
            var cleared = new bool[n];
            var queue = new Queue<int>();
            foreach (var p in seeds)
            {
                int i = p.y * img.w + p.x;
                if (p.x < 0 || p.y < 0 || p.x >= img.w || p.y >= img.h || cleared[i] || !IsChecker(img.c[i])) continue;
                cleared[i] = true; queue.Enqueue(i);
            }
            while (queue.Count > 0)
            {
                int i = queue.Dequeue(), x = i % img.w, y = i / img.w;
                for (int k = 0; k < 4; k++)
                {
                    int nx = x + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
                    if (nx < 0 || ny < 0 || nx >= img.w || ny >= img.h) continue;
                    int j = ny * img.w + nx;
                    if (cleared[j] || !IsChecker(img.c[j])) continue;
                    cleared[j] = true; queue.Enqueue(j);
                }
            }
            // Мягкая кромка в 1 пиксель
            for (int i = 0; i < n; i++)
            {
                if (cleared[i]) continue;
                int x = i % img.w, y = i / img.w;
                bool near = (x > 0 && cleared[i - 1]) || (x < img.w - 1 && cleared[i + 1]) || (y > 0 && cleared[i - img.w]) || (y < img.h - 1 && cleared[i + img.w]);
                if (near) img.c[i].a = Mathf.Min(img.c[i].a, 0.55f);
            }
            for (int i = 0; i < n; i++) if (cleared[i]) img.c[i] = Color.clear;
        }

        private static bool IsChecker(Color c)
        {
            float max = Mathf.Max(c.r, Mathf.Max(c.g, c.b)), min = Mathf.Min(c.r, Mathf.Min(c.g, c.b));
            return c.a > 0f && max - min < 0.07f && max > 0.62f;
        }

        private static IEnumerable<Vector2Int> BorderSeeds(Img img)
        {
            for (int x = 0; x < img.w; x++) { yield return new Vector2Int(x, 0); yield return new Vector2Int(x, img.h - 1); }
            for (int y = 0; y < img.h; y++) { yield return new Vector2Int(0, y); yield return new Vector2Int(img.w - 1, y); }
        }

        private static void Bfs(Img img, int[] dist, Queue<int> queue, int limit)
        {
            while (queue.Count > 0)
            {
                int i = queue.Dequeue(), x = i % img.w, y = i / img.w;
                if (dist[i] >= limit) continue;
                for (int k = 0; k < 4; k++)
                {
                    int nx = x + (k == 0 ? 1 : k == 1 ? -1 : 0), ny = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
                    if (nx < 0 || ny < 0 || nx >= img.w || ny >= img.h) continue;
                    int j = ny * img.w + nx;
                    if (dist[j] <= dist[i] + 1) continue;
                    dist[j] = dist[i] + 1; queue.Enqueue(j);
                }
            }
        }

        // ---------- Кусочки ----------

        private static List<Box> Components(Img img)
        {
            int n = img.w * img.h;
            var seen = new bool[n];
            var list = new List<Box>();
            var stack = new Stack<int>();
            for (int s = 0; s < n; s++)
            {
                if (seen[s] || img.c[s].a <= 0.5f) continue;
                var b = new Box { minX = int.MaxValue, minY = int.MaxValue, maxX = -1, maxY = -1 };
                seen[s] = true; stack.Push(s);
                while (stack.Count > 0)
                {
                    int i = stack.Pop(), x = i % img.w, y = i / img.w;
                    b.minX = Mathf.Min(b.minX, x); b.maxX = Mathf.Max(b.maxX, x);
                    b.minY = Mathf.Min(b.minY, y); b.maxY = Mathf.Max(b.maxY, y);
                    b.area++;
                    for (int dy = -1; dy <= 1; dy++)
                        for (int dx = -1; dx <= 1; dx++)
                        {
                            int nx = x + dx, ny = y + dy;
                            if (nx < 0 || ny < 0 || nx >= img.w || ny >= img.h) continue;
                            int j = ny * img.w + nx;
                            if (seen[j] || img.c[j].a <= 0.5f) continue;
                            seen[j] = true; stack.Push(j);
                        }
                }
                list.Add(b);
            }
            return list;
        }

        // Склейка: близко друг к другу, мелкое внутри крупного (точка прицела в кольце), или в одной заданной группе
        private static List<Box> Merge(List<Box> boxes, Sheet s)
        {
            bool changed = true;
            while (changed)
            {
                changed = false;
                for (int i = 0; i < boxes.Count && !changed; i++)
                    for (int j = i + 1; j < boxes.Count; j++)
                    {
                        if (!ShouldMerge(boxes[i], boxes[j], s)) continue;
                        var b = boxes[i]; b.Add(boxes[j]); boxes[i] = b;
                        boxes.RemoveAt(j);
                        changed = true;
                        break;
                    }
            }
            return boxes;
        }

        private static bool ShouldMerge(Box a, Box b, Sheet s)
        {
            int dx = Mathf.Max(0, Mathf.Max(a.minX, b.minX) - Mathf.Min(a.maxX, b.maxX));
            int dy = Mathf.Max(0, Mathf.Max(a.minY, b.minY) - Mathf.Min(a.maxY, b.maxY));
            if (dx <= s.gap && dy <= s.gap) return true;
            var small = a.area < b.area ? a : b;
            var big = a.area < b.area ? b : a;
            if (big.Contains(small.CX, small.CY)) return true;
            foreach (var g in s.groups)
            {
                bool ina = a.CX >= g.xMin && a.CX <= g.xMax && a.CY >= g.yMin && a.CY <= g.yMax;
                bool inb = b.CX >= g.xMin && b.CX <= g.xMax && b.CY >= g.yMin && b.CY <= g.yMax;
                if (ina && inb) return true;
            }
            return false;
        }

        // Порядок: полосы сверху вниз (кусочек попадает в полосу, если перекрывается с ней по высоте хотя бы наполовину),
        // внутри полосы — столбцы слева направо (пересекаются по x), в столбце — сверху вниз
        private static List<Box> Order(List<Box> boxes)
        {
            boxes.Sort((a, b) => a.minY.CompareTo(b.minY));
            var bands = new List<List<Box>>();
            var ranges = new List<Vector2Int>();
            foreach (var b in boxes)
            {
                // В ряд — если по высоте перекрывается с ним хотя бы наполовину (по середине — неустойчиво:
                // на увеличенном листе вкладки и поле ввода разъехались по разным рядам, и имена перепутались)
                int k = ranges.FindIndex(r => Mathf.Min(b.maxY, r.y) - Mathf.Max(b.minY, r.x) >= 0.5f * Mathf.Min(b.H, r.y - r.x + 1));
                if (k < 0) { bands.Add(new List<Box>()); ranges.Add(new Vector2Int(b.minY, b.maxY)); k = bands.Count - 1; }
                bands[k].Add(b);
                ranges[k] = new Vector2Int(Mathf.Min(ranges[k].x, b.minY), Mathf.Max(ranges[k].y, b.maxY));
            }
            var result = new List<Box>();
            foreach (var band in bands)
            {
                band.Sort((a, b) => a.minX.CompareTo(b.minX));
                var columns = new List<List<Box>>();
                int right = int.MinValue;
                foreach (var b in band)
                {
                    if (columns.Count == 0 || b.minX > right) { columns.Add(new List<Box>()); right = b.maxX; }
                    else right = Mathf.Max(right, b.maxX);
                    columns[columns.Count - 1].Add(b);
                }
                foreach (var col in columns)
                {
                    col.Sort((a, b) => a.minY.CompareTo(b.minY));
                    result.AddRange(col);
                }
            }
            return result;
        }

        private static RectInt Padded(Img img, Box b)
        {
            int x0 = Mathf.Max(0, b.minX - pad), y0 = Mathf.Max(0, b.minY - pad);
            int x1 = Mathf.Min(img.w - 1, b.maxX + pad), y1 = Mathf.Min(img.h - 1, b.maxY + pad);
            return new RectInt(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
        }

        // Крошки и всё вне кусочков — прозрачное
        private static void ClearOutside(Img img, List<Box> boxes)
        {
            var keep = new bool[img.w * img.h];
            foreach (var b in boxes)
            {
                var r = Padded(img, b);
                for (int y = r.yMin; y < r.yMax; y++)
                    for (int x = r.xMin; x < r.xMax; x++) keep[y * img.w + x] = true;
            }
            for (int i = 0; i < keep.Length; i++) if (!keep[i]) img.c[i] = Color.clear;
        }

        // ---------- Импорт ----------

        private static void ImportSheet(string path, Img img, List<Box> boxes, string[] names)
        {
            AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
            var importer = (TextureImporter)AssetImporter.GetAtPath(path);
            importer.textureType = TextureImporterType.Sprite;
            importer.spriteImportMode = names != null ? SpriteImportMode.Multiple : SpriteImportMode.Single;
            importer.mipmapEnabled = false;
            importer.alphaIsTransparency = true;
            importer.wrapMode = TextureWrapMode.Clamp;
            importer.filterMode = FilterMode.Bilinear;
            importer.maxTextureSize = 4096;
            importer.spritePixelsPerUnit = pixelsPerUnit;
            importer.textureCompression = TextureImporterCompression.CompressedHQ;
            var settings = new TextureImporterSettings();
            importer.ReadTextureSettings(settings);
            settings.spriteMeshType = SpriteMeshType.FullRect; // для 9-slice
            importer.SetTextureSettings(settings);
            importer.SaveAndReimport();
            if (names == null) return;

            var factory = new SpriteDataProviderFactories();
            factory.Init();
            var dp = factory.GetSpriteEditorDataProviderFromObject(importer);
            dp.InitSpriteEditorDataProvider();
            // Те же id у тех же имён — ссылки на спрайты не рвутся при повторной нарезке
            var oldIds = new Dictionary<string, GUID>();
            foreach (var r in dp.GetSpriteRects()) oldIds[r.name] = r.spriteID;
            var rects = new List<SpriteRect>();
            for (int i = 0; i < boxes.Count; i++)
            {
                if (names[i] == Skip) continue;
                var p = Padded(img, boxes[i]);
                Vector4 border;
                BorderOf(names[i], out border);
                GUID id;
                rects.Add(new SpriteRect
                {
                    name = names[i],
                    rect = new Rect(p.x, img.h - p.y - p.height, p.width, p.height),
                    alignment = SpriteAlignment.Center,
                    pivot = new Vector2(0.5f, 0.5f),
                    border = border,
                    spriteID = oldIds.TryGetValue(names[i], out id) ? id : GUID.Generate(),
                });
            }
            dp.SetSpriteRects(rects.ToArray());
            var ids = dp.GetDataProvider<ISpriteNameFileIdDataProvider>();
            if (ids != null)
            {
                var pairs = new List<SpriteNameFileIdPair>();
                foreach (var r in rects) pairs.Add(new SpriteNameFileIdPair(r.name, r.spriteID));
                ids.SetNameFileIdPairs(pairs);
            }
            dp.Apply();
            importer.SaveAndReimport();
        }

        // ---------- Курсоры ----------

        private static string MakeCursors(Img sheet, List<Box> boxes)
        {
            Directory.CreateDirectory(CursorDir);
            Directory.CreateDirectory(Path.GetDirectoryName(CursorSetPath));
            var names = System.Array.Find(Sheets, s => s.file == "ui_cursors").names;
            var entries = new List<CursorSet.Entry>();
            for (int i = 0; i < boxes.Count; i++)
            {
                var b = boxes[i];
                bool tip = TipCursors.Contains(names[i]);
                // Квадрат: стрелка прижата к левому верхнему углу, остальное — по центру
                int side = Mathf.Max(b.W, b.H) + 4;
                var sq = new Img(side, side);
                int ox = tip ? 2 : (side - b.W) / 2, oy = tip ? 2 : (side - b.H) / 2;
                for (int y = 0; y < b.H; y++)
                    for (int x = 0; x < b.W; x++) sq[ox + x, oy + y] = sheet[b.minX + x, b.minY + y];
                var entry = new CursorSet.Entry { name = names[i] };
                foreach (int size in new[] { 32, 64 })
                {
                    var small = Resize(sq, size, size);
                    string path = CursorDir + names[i] + "_" + size + ".png";
                    Save(small, path);
                    AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
                    var imp = (TextureImporter)AssetImporter.GetAtPath(path);
                    imp.textureType = TextureImporterType.Cursor;
                    imp.mipmapEnabled = false;
                    imp.alphaIsTransparency = true;
                    imp.npotScale = TextureImporterNPOTScale.None;
                    imp.textureCompression = TextureImporterCompression.Uncompressed;
                    imp.SaveAndReimport();
                    var tex = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
                    if (size == 32) entry.small = tex; else entry.large = tex;
                    if (size == 64 && !HotspotOverride.TryGetValue(names[i], out entry.hotspot))
                        entry.hotspot = tip ? TipOf(small) : new Vector2(0.5f, 0.5f);
                }
                entries.Add(entry);
            }
            var set = AssetDatabase.LoadAssetAtPath<CursorSet>(CursorSetPath);
            if (set == null) { set = ScriptableObject.CreateInstance<CursorSet>(); AssetDatabase.CreateAsset(set, CursorSetPath); }
            set.cursors = entries.ToArray();
            EditorUtility.SetDirty(set);
            AssetDatabase.SaveAssets();
            return "Курсоры: " + entries.Count + " × (32, 64) → " + CursorDir + ", набор " + CursorSetPath;
        }

        // Кончик стрелки: непрозрачный пиксель ближе всех к левому верхнему углу (пламя не считается)
        private static Vector2 TipOf(Img img)
        {
            int best = int.MaxValue; var at = Vector2.zero;
            for (int y = 0; y < img.h; y++)
                for (int x = 0; x < img.w; x++)
                {
                    var c = img[x, y];
                    bool flame = c.r > 0.8f && c.g > 0.35f && c.b < 0.35f;
                    if (c.a < 0.5f || flame || x + y >= best) continue;
                    best = x + y; at = new Vector2((x + 0.5f) / img.w, (y + 0.5f) / img.h);
                }
            return at;
        }

        // Уменьшение усреднением (с учётом прозрачности — без тёмной каймы)
        private static Img Resize(Img src, int nw, int nh)
        {
            var dst = new Img(nw, nh);
            float kx = src.w / (float)nw, ky = src.h / (float)nh;
            for (int y = 0; y < nh; y++)
                for (int x = 0; x < nw; x++)
                {
                    int x0 = Mathf.FloorToInt(x * kx), x1 = Mathf.Max(x0 + 1, Mathf.FloorToInt((x + 1) * kx));
                    int y0 = Mathf.FloorToInt(y * ky), y1 = Mathf.Max(y0 + 1, Mathf.FloorToInt((y + 1) * ky));
                    float r = 0, g = 0, b = 0, a = 0; int cnt = 0;
                    for (int sy = y0; sy < y1 && sy < src.h; sy++)
                        for (int sx = x0; sx < x1 && sx < src.w; sx++)
                        {
                            var c = src[sx, sy];
                            r += c.r * c.a; g += c.g * c.a; b += c.b * c.a; a += c.a; cnt++;
                        }
                    dst[x, y] = a > 0f ? new Color(r / a, g / a, b / a, a / cnt) : Color.clear;
                }
            return dst;
        }

        // ---------- Реестр для игры ----------

        // Все нарезанные спрайты — в Resources/UI/UiSprites.asset (игра берёт их по имени: UiSprites.Get)
        private static string FillRegistry()
        {
            string path = "Assets/Resources/" + UiSprites.ResourcePath + ".asset";
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            var set = AssetDatabase.LoadAssetAtPath<UiSprites>(path);
            if (set == null) { set = ScriptableObject.CreateInstance<UiSprites>(); AssetDatabase.CreateAsset(set, path); }
            var list = new List<Sprite>();
            foreach (var file in Directory.GetFiles(SheetDir, "*.png"))
                foreach (var o in AssetDatabase.LoadAllAssetsAtPath(file.Replace("\\", "/")))
                {
                    var sp = o as Sprite;
                    if (sp != null) list.Add(sp);
                }
            list.Sort((x, y) => string.CompareOrdinal(x.name, y.name));
            set.sprites = list.ToArray();
            EditorUtility.SetDirty(set);
            AssetDatabase.SaveAssets();
            return "Реестр картинок: " + list.Count + " → " + path;
        }

        // ---------- Фоны ----------

        private static string CopyBackgrounds()
        {
            Directory.CreateDirectory(BackgroundDir);
            var sb = new StringBuilder("Фоны:");
            foreach (var src in Directory.GetFiles(SourceDir, "bg_*.png"))
            {
                // Увеличенный до 4K (Upscayl) — PNG; иначе исходник (на самом деле JPEG) — копия с честным расширением
                string name = Path.GetFileNameWithoutExtension(src);
                string up = UpscaledDir + name + ".png";
                bool upscaled = File.Exists(up);
                string dst = BackgroundDir + name + (upscaled ? ".png" : ".jpg");
                File.Copy(upscaled ? up : src, dst, true);
                // Прежняя копия другого формата — наш же вывод, заменён
                string other = BackgroundDir + name + (upscaled ? ".jpg" : ".png");
                if (File.Exists(other)) AssetDatabase.DeleteAsset(other);
                AssetDatabase.ImportAsset(dst, ImportAssetOptions.ForceUpdate);
                var imp = (TextureImporter)AssetImporter.GetAtPath(dst);
                imp.textureType = TextureImporterType.Sprite;
                imp.spriteImportMode = SpriteImportMode.Single;
                imp.mipmapEnabled = false;
                imp.wrapMode = TextureWrapMode.Clamp;
                imp.maxTextureSize = 4096;
                imp.textureCompression = TextureImporterCompression.CompressedHQ;
                imp.SaveAndReimport();
                var tex = AssetDatabase.LoadAssetAtPath<Texture2D>(dst);
                sb.Append(" ").Append(name).Append(" ").Append(tex != null ? tex.width + "×" + tex.height : "?").Append(";");

                // Крошечная копия для размытых краёв на сверхшироких экранах (растянутая — уже размыта)
                string blur = BackgroundDir + name + "_blur.png";
                string upBlur = UpscaledDir + name + "_blur.png";
                if (File.Exists(upBlur)) File.Copy(upBlur, blur, true); // из увеличенного (рамка уже обрезана)
                else
                {
                    var small = Load(src);
                    small = Resize(small, 48, Mathf.Max(1, Mathf.RoundToInt(48f * small.h / small.w)));
                    Save(small, blur);
                }
                AssetDatabase.ImportAsset(blur, ImportAssetOptions.ForceUpdate);
                var bi = (TextureImporter)AssetImporter.GetAtPath(blur);
                bi.textureType = TextureImporterType.Sprite;
                bi.spriteImportMode = SpriteImportMode.Single;
                bi.mipmapEnabled = false;
                bi.wrapMode = TextureWrapMode.Clamp;
                bi.filterMode = FilterMode.Bilinear;
                bi.textureCompression = TextureImporterCompression.Uncompressed;
                bi.SaveAndReimport();
            }
            return sb.ToString();
        }

        // ---------- Превью ----------

        // Лист на «шахматке» с рамками и номерами кусочков (зелёные — нарезано, красные — не совпало)
        private static void SavePreview(Img img, List<Box> boxes, bool ok, string path)
        {
            var p = new Img(img.w, img.h);
            for (int y = 0; y < img.h; y++)
                for (int x = 0; x < img.w; x++)
                {
                    float chk = ((x / 16 + y / 16) & 1) == 0 ? 0.8f : 0.65f;
                    var c = img[x, y];
                    p[x, y] = new Color(Mathf.Lerp(chk, c.r, c.a), Mathf.Lerp(chk, c.g, c.a), Mathf.Lerp(chk, c.b, c.a), 1f);
                }
            var line = ok ? new Color(0.1f, 0.7f, 0.2f) : new Color(0.9f, 0.1f, 0.1f);
            for (int i = 0; i < boxes.Count; i++)
            {
                var r = Padded(img, boxes[i]);
                DrawRect(p, r, line);
                DrawNumber(p, r.xMin + 3, r.yMin + 3, i + 1, line);
            }
            Save(p, path);
        }

        // Растяжение 9-slice: каждый спрайт с рамкой — как есть и вдвое шире/выше
        private static int SaveSlicePreview(Img img, List<Box> boxes, string[] names, string path)
        {
            var items = new List<KeyValuePair<Img, Img>>();
            for (int i = 0; i < boxes.Count; i++)
            {
                Vector4 bd;
                if (!BorderOf(names[i], out bd)) continue;
                var r = Padded(img, boxes[i]);
                var src = new Img(r.width, r.height);
                for (int y = 0; y < r.height; y++)
                    for (int x = 0; x < r.width; x++) src[x, y] = img[r.x + x, r.y + y];
                bool wide = bd.x + bd.z > 0f, tall = bd.y + bd.w > 0f;
                int tw = wide ? src.w * 2 : src.w, th = tall ? Mathf.RoundToInt(src.h * (wide ? 1.5f : 2f)) : src.h;
                items.Add(new KeyValuePair<Img, Img>(src, Slice9(src, bd, tw, th)));
            }
            if (items.Count == 0) return 0;
            int width = 0, height = 0;
            foreach (var it in items) { width = Mathf.Max(width, it.Key.w + it.Value.w + 30); height += Mathf.Max(it.Key.h, it.Value.h) + 10; }
            var p = new Img(width, height);
            for (int i = 0; i < p.c.Length; i++) { int x = i % width, y = i / width; float chk = ((x / 16 + y / 16) & 1) == 0 ? 0.8f : 0.65f; p.c[i] = new Color(chk, chk, chk); }
            int oy = 0;
            foreach (var it in items)
            {
                Blit(p, it.Key, 0, oy);
                Blit(p, it.Value, it.Key.w + 20, oy);
                oy += Mathf.Max(it.Key.h, it.Value.h) + 10;
            }
            Save(p, path);
            return items.Count;
        }

        private static Img Slice9(Img src, Vector4 bd, int tw, int th)
        {
            int L = (int)bd.x, B = (int)bd.y, R = (int)bd.z, T = (int)bd.w;
            var dst = new Img(tw, th);
            for (int y = 0; y < th; y++)
            {
                int sy = Map(y, th, src.h, T, B);
                for (int x = 0; x < tw; x++) dst[x, y] = src[Map(x, tw, src.w, L, R), sy];
            }
            return dst;
        }

        private static int Map(int t, int tLen, int sLen, int lo, int hi)
        {
            if (t < lo) return t;
            if (t >= tLen - hi) return sLen - (tLen - t);
            float k = (t - lo) / (float)Mathf.Max(1, tLen - lo - hi);
            return Mathf.Clamp(lo + (int)(k * (sLen - lo - hi)), 0, sLen - 1);
        }

        private static void Blit(Img dst, Img src, int ox, int oy)
        {
            for (int y = 0; y < src.h && oy + y < dst.h; y++)
                for (int x = 0; x < src.w && ox + x < dst.w; x++)
                {
                    var c = src[x, y]; var d = dst[ox + x, oy + y];
                    dst[ox + x, oy + y] = new Color(Mathf.Lerp(d.r, c.r, c.a), Mathf.Lerp(d.g, c.g, c.a), Mathf.Lerp(d.b, c.b, c.a), 1f);
                }
        }

        private static void DrawRect(Img p, RectInt r, Color c)
        {
            for (int t = 0; t < 2; t++)
            {
                for (int x = r.xMin; x < r.xMax; x++) { Put(p, x, r.yMin + t, c); Put(p, x, r.yMax - 1 - t, c); }
                for (int y = r.yMin; y < r.yMax; y++) { Put(p, r.xMin + t, y, c); Put(p, r.xMax - 1 - t, y, c); }
            }
        }

        // Цифры 3×5 точек, крупно
        private static readonly string[] Digits = { "111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
                                                    "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111" };

        private static void DrawNumber(Img p, int x0, int y0, int value, Color c)
        {
            string s = value.ToString();
            const int k = 4;
            for (int y = -2; y < 5 * k + 2; y++)
                for (int x = -2; x < s.Length * 4 * k; x++) Put(p, x0 + x, y0 + y, Color.white);
            for (int d = 0; d < s.Length; d++)
            {
                string bits = Digits[s[d] - '0'];
                for (int i = 0; i < 15; i++)
                {
                    if (bits[i] != '1') continue;
                    int bx = i % 3, by = i / 3;
                    for (int yy = 0; yy < k; yy++)
                        for (int xx = 0; xx < k; xx++) Put(p, x0 + d * 4 * k + bx * k + xx, y0 + by * k + yy, c);
                }
            }
        }

        private static void Put(Img p, int x, int y, Color c)
        {
            if (x >= 0 && y >= 0 && x < p.w && y < p.h) p[x, y] = c;
        }

        // ---------- Файлы ----------

        private static Img Load(string path)
        {
            var tex = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            tex.LoadImage(File.ReadAllBytes(path));
            var img = new Img(tex.width, tex.height);
            var px = tex.GetPixels();
            for (int y = 0; y < img.h; y++)
                for (int x = 0; x < img.w; x++) img[x, y] = px[(img.h - 1 - y) * img.w + x];
            Object.DestroyImmediate(tex);
            return img;
        }

        private static void Save(Img img, string path)
        {
            var tex = new Texture2D(img.w, img.h, TextureFormat.RGBA32, false);
            var px = new Color[img.c.Length];
            for (int y = 0; y < img.h; y++)
                for (int x = 0; x < img.w; x++) px[(img.h - 1 - y) * img.w + x] = img[x, y];
            tex.SetPixels(px);
            tex.Apply();
            File.WriteAllBytes(path, tex.EncodeToPNG());
            Object.DestroyImmediate(tex);
        }

        private static Color Median(List<Color> list)
        {
            var r = new List<float>(); var g = new List<float>(); var b = new List<float>();
            foreach (var c in list) { r.Add(c.r); g.Add(c.g); b.Add(c.b); }
            r.Sort(); g.Sort(); b.Sort();
            int m = list.Count / 2;
            return new Color(r[m], g[m], b[m], 1f);
        }
    }
}
