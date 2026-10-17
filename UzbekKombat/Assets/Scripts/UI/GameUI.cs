using System.Collections.Generic;
using System.Text;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Butun interfeys (IMGUI, 1920×1080 virtual o'lcham). Teksturalar va bezaklar protsedural.
    /// </summary>
    public class GameUI : MonoBehaviour
    {
        public GameManager gm;
        Font font;
        readonly Dictionary<int, GUIStyle> styles = new Dictionary<int, GUIStyle>();
        float W, H = 1080f, scale;
        int menuIndex;
        int pauseIndex;
        int resultIndex;
        int optionIndex;
        bool showMoveList;
        float screenTime;
        UIScreen lastScreen;
        Texture2D white, panel, vignette, rosette, hpFill, hpBack, hpTrail, meterFill, meterFull, gold, darkBlue, tileBorder, girih;

        static readonly string[] MainItems = { "ARKADA", "IKKI O'YINCHI", "MASHQ", "TOMOSHA (CPU vs CPU)", "BOSHQARUV", "SOZLAMALAR", "CHIQISH" };
        static readonly string[] DiffNames = { "OSON", "O'RTA", "QIYIN", "AFSONAVIY" };
        static readonly string[] ArenaNames = { "QISHLOQ — SHOM", "QISHLOQ — TUN", "TASODIFIY" };

        void Start()
        {
            font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            white = TextureFactory.Solid(Color.white);
            panel = TextureFactory.OrnatePanel();
            vignette = TextureFactory.Vignette();
            rosette = TextureFactory.Rosette();
            hpFill = TextureFactory.HorizontalGradient(ColorUtil.Hex("#e8c23a"), ColorUtil.Hex("#3fbf6a"));
            hpBack = TextureFactory.VerticalGradient(ColorUtil.Hex("#2a1416"), ColorUtil.Hex("#120808"));
            hpTrail = TextureFactory.Solid(ColorUtil.Hex("#c0262a"));
            meterFill = TextureFactory.HorizontalGradient(ColorUtil.Hex("#1a5fb4"), ColorUtil.Hex("#3fd0e0"));
            meterFull = TextureFactory.HorizontalGradient(ColorUtil.Hex("#e0a020"), ColorUtil.Hex("#fff0a0"));
            gold = TextureFactory.Solid(ColorUtil.Hex("#d9a441"));
            darkBlue = TextureFactory.Solid(new Color(0.04f, 0.06f, 0.14f, 0.85f));
            tileBorder = TextureFactory.TileBorder();
            girih = TextureFactory.GirihTile();
        }

        // ======================= Kiritish (menyular) =======================
        void Update()
        {
            if (gm == null) return;
            if (gm.screen != lastScreen) { lastScreen = gm.screen; screenTime = 0; }
            screenTime += Time.unscaledDeltaTime;
            bool up = Input.GetKeyDown(KeyCode.W) || Input.GetKeyDown(KeyCode.UpArrow);
            bool down = Input.GetKeyDown(KeyCode.S) || Input.GetKeyDown(KeyCode.DownArrow);
            bool left = Input.GetKeyDown(KeyCode.A) || Input.GetKeyDown(KeyCode.LeftArrow);
            bool right = Input.GetKeyDown(KeyCode.D) || Input.GetKeyDown(KeyCode.RightArrow);
            bool ok = Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter) || Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.U);
            bool back = Input.GetKeyDown(KeyCode.Escape) || Input.GetKeyDown(KeyCode.Backspace);

            switch (gm.screen)
            {
                case UIScreen.Title:
                    if (screenTime > 0.5f && Input.anyKeyDown) { gm.OpenScreen(UIScreen.MainMenu); menuIndex = 0; }
                    break;
                case UIScreen.MainMenu:
                    if (up) { menuIndex = (menuIndex + MainItems.Length - 1) % MainItems.Length; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                    if (down) { menuIndex = (menuIndex + 1) % MainItems.Length; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                    if (ok) MainAction(menuIndex);
                    if (back) gm.OpenScreen(UIScreen.Title);
                    break;
                case UIScreen.CharSelect:
                    if (Input.GetKeyDown(KeyCode.A)) gm.SelectMove(0, -1);
                    if (Input.GetKeyDown(KeyCode.D)) gm.SelectMove(0, 1);
                    if (Input.GetKeyDown(KeyCode.U) || Input.GetKeyDown(KeyCode.Space) || Input.GetKeyDown(KeyCode.Return)) gm.Confirm(0);
                    if (Input.GetKeyDown(KeyCode.I) || Input.GetKeyDown(KeyCode.Escape)) gm.Back(0);
                    if (gm.mode == GameMode.Versus)
                    {
                        if (Input.GetKeyDown(KeyCode.LeftArrow)) gm.SelectMove(1, -1);
                        if (Input.GetKeyDown(KeyCode.RightArrow)) gm.SelectMove(1, 1);
                        if (Input.GetKeyDown(KeyCode.Keypad4) || Input.GetKeyDown(KeyCode.KeypadEnter) || Input.GetKeyDown(KeyCode.RightControl)) gm.Confirm(1);
                        if (Input.GetKeyDown(KeyCode.Keypad5) || Input.GetKeyDown(KeyCode.Backspace)) gm.Back(1);
                    }
                    if (Input.GetKeyDown(KeyCode.T)) { gm.arenaChoice = (gm.arenaChoice + 1) % 3; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                    if (Input.GetKeyDown(KeyCode.Tab)) { showMoveList = !showMoveList; }
                    break;
                case UIScreen.Fight:
                    if (gm.paused)
                    {
                        if (showMoveList) { if (back || ok) showMoveList = false; break; }
                        string[] items = PauseItems();
                        if (up) { pauseIndex = (pauseIndex + items.Length - 1) % items.Length; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                        if (down) { pauseIndex = (pauseIndex + 1) % items.Length; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                        if (ok) PauseAction(pauseIndex);
                    }
                    break;
                case UIScreen.Results:
                    if (up || left) { resultIndex = (resultIndex + 2) % 3; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                    if (down || right) { resultIndex = (resultIndex + 1) % 3; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                    if (ok && screenTime > 0.6f) { gm.ResultsAction(resultIndex); resultIndex = 0; }
                    break;
                case UIScreen.Controls:
                    if (back || ok) gm.OpenScreen(UIScreen.MainMenu);
                    break;
                case UIScreen.Options:
                    if (up) { optionIndex = (optionIndex + 5) % 6; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                    if (down) { optionIndex = (optionIndex + 1) % 6; SynthAudio.Play(Sfx.UIMove, 0.5f); }
                    if (left) ChangeOption(optionIndex, -1);
                    if (right || ok) ChangeOption(optionIndex, 1);
                    if (back) gm.OpenScreen(UIScreen.MainMenu);
                    break;
                case UIScreen.Ending:
                    if (screenTime > 1.5f && (ok || back)) gm.GoMainMenu();
                    break;
            }
        }

        void MainAction(int i)
        {
            SynthAudio.Play(Sfx.UISelect, 0.8f);
            switch (i)
            {
                case 0: gm.StartMode(GameMode.Arcade); break;
                case 1: gm.StartMode(GameMode.Versus); break;
                case 2: gm.StartMode(GameMode.Training); break;
                case 3: gm.StartMode(GameMode.Watch); break;
                case 4: gm.OpenScreen(UIScreen.Controls); break;
                case 5: gm.OpenScreen(UIScreen.Options); optionIndex = 0; break;
                case 6: gm.Quit(); break;
            }
        }

        string[] PauseItems() => new[] { "DAVOM ETISH", "HARAKATLAR RO'YXATI", "QAYTA BOSHLASH", "QAHRAMON TANLASH", "BOSH MENYU" };

        void PauseAction(int i)
        {
            SynthAudio.Play(Sfx.UISelect, 0.7f);
            switch (i)
            {
                case 0: gm.TogglePause(); break;
                case 1: showMoveList = true; break;
                case 2: gm.StartFight(); break;
                case 3: gm.EndMatch(); gm.StartMode(gm.mode); break;
                case 4: gm.GoMainMenu(); break;
            }
            pauseIndex = 0;
        }

        void ChangeOption(int i, int d)
        {
            SynthAudio.Play(Sfx.UIMove, 0.6f);
            switch (i)
            {
                case 0: gm.difficulty = Mathf.Clamp(gm.difficulty + d, 0, 3); break;
                case 1: gm.roundsToWin = Mathf.Clamp(gm.roundsToWin + d, 1, 3); break;
                case 2: gm.arenaChoice = (gm.arenaChoice + d + 3) % 3; break;
                case 3: SynthAudio.I.MusicVolume = Mathf.Clamp01(SynthAudio.I.MusicVolume + d * 0.1f); break;
                case 4: SynthAudio.I.sfxVolume = Mathf.Clamp01(SynthAudio.I.sfxVolume + d * 0.1f); break;
                case 5:
                    {
                        int q = Mathf.Clamp(QualitySettings.GetQualityLevel() + d, 0, QualitySettings.names.Length - 1);
                        QualitySettings.SetQualityLevel(q, true);
                        QualitySettings.shadowDistance = 45f;
                        break;
                    }
            }
        }

        // ======================= Chizish yordamchilari =======================
        GUIStyle Style(int size, TextAnchor align, FontStyle fs = FontStyle.Bold)
        {
            int key = size * 100 + (int)align * 10 + (int)fs;
            if (!styles.TryGetValue(key, out var s))
            {
                s = new GUIStyle { font = font, fontSize = size, alignment = align, fontStyle = fs, richText = false, wordWrap = false, clipping = TextClipping.Overflow };
                s.normal.textColor = Color.white;
                styles[key] = s;
            }
            return s;
        }

        void Text(Rect r, string t, int size, Color c, TextAnchor a = TextAnchor.MiddleCenter, float outline = 2f, FontStyle fs = FontStyle.Bold, bool wrap = false)
        {
            var s = Style(size, a, fs);
            s.wordWrap = wrap;
            if (outline > 0)
            {
                s.normal.textColor = new Color(0.03f, 0.02f, 0.05f, c.a * 0.9f);
                for (int i = 0; i < 8; i++)
                {
                    float ang = i * Mathf.PI / 4;
                    GUI.Label(new Rect(r.x + Mathf.Cos(ang) * outline, r.y + Mathf.Sin(ang) * outline, r.width, r.height), t, s);
                }
                GUI.Label(new Rect(r.x + outline * 1.5f, r.y + outline * 2f, r.width, r.height), t, s);
            }
            s.normal.textColor = c;
            GUI.Label(r, t, s);
            s.wordWrap = false;
        }

        void Box(Rect r, Color c) { var o = GUI.color; GUI.color = c; GUI.DrawTexture(r, white); GUI.color = o; }
        void Tex(Rect r, Texture t, Color c, ScaleMode m = ScaleMode.StretchToFill) { if (t == null) return; var o = GUI.color; GUI.color = c; GUI.DrawTexture(r, t, m, true); GUI.color = o; }

        void Frame(Rect r, Color c, float th)
        {
            Box(new Rect(r.x, r.y, r.width, th), c);
            Box(new Rect(r.x, r.yMax - th, r.width, th), c);
            Box(new Rect(r.x, r.y, th, r.height), c);
            Box(new Rect(r.xMax - th, r.y, th, r.height), c);
        }

        void Panel(Rect r, float alpha = 1f) => Tex(r, panel, new Color(1, 1, 1, alpha));

        bool MenuButton(Rect r, string label, bool selected, int size = 34)
        {
            bool hover = r.Contains(Event.current.mousePosition);
            Color bg = selected ? new Color(0.85f, 0.62f, 0.2f, 0.9f) : hover ? new Color(0.2f, 0.3f, 0.55f, 0.85f) : new Color(0.05f, 0.08f, 0.18f, 0.75f);
            Box(r, bg);
            Frame(r, selected ? ColorUtil.Hex("#fff0b0") : ColorUtil.Hex("#d9a441").WithA(0.7f), selected ? 3 : 1.5f);
            if (selected)
            {
                float p = Mathf.Sin(Time.unscaledTime * 6) * 4;
                Tex(new Rect(r.x - 52 + p, r.center.y - 20, 40, 40), rosette, Color.white);
                Tex(new Rect(r.xMax + 12 - p, r.center.y - 20, 40, 40), rosette, Color.white);
            }
            Text(r, label, size, selected ? ColorUtil.Hex("#1a0e04") : Color.white, TextAnchor.MiddleCenter, selected ? 0 : 2);
            return GUI.Button(r, GUIContent.none, GUIStyle.none);
        }

        // ======================= OnGUI =======================
        void OnGUI()
        {
            if (gm == null || font == null) return;
            scale = Screen.height / 1080f;
            W = Screen.width / scale;
            GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(scale, scale, 1));
            GUI.depth = 0;

            switch (gm.screen)
            {
                case UIScreen.Title: DrawTitle(); break;
                case UIScreen.MainMenu: DrawMainMenu(); break;
                case UIScreen.CharSelect: DrawCharSelect(); break;
                case UIScreen.Versus: DrawVersus(); break;
                case UIScreen.Fight: DrawFight(); break;
                case UIScreen.Results: DrawFight(); DrawResults(); break;
                case UIScreen.Controls: DrawControls(); break;
                case UIScreen.Options: DrawOptions(); break;
                case UIScreen.Ending: DrawEnding(); break;
            }
        }

        void Logo(float cy, float s)
        {
            float glow = 0.85f + 0.15f * Mathf.Sin(Time.unscaledTime * 2f);
            Tex(new Rect(W / 2 - 520 * s, cy - 95 * s, 1040 * s, 26 * s), tileBorder, Color.white);
            Text(new Rect(0, cy - 70 * s, W, 140 * s), "O'ZBEK JANGI", Mathf.RoundToInt(128 * s), new Color(1f, 0.82f * glow, 0.35f), TextAnchor.MiddleCenter, 5 * s);
            Text(new Rect(0, cy + 60 * s, W, 60 * s), "Q A D I M I Y   Q A H R A M O N L A R", Mathf.RoundToInt(36 * s), ColorUtil.Hex("#bfe8f0"), TextAnchor.MiddleCenter, 3 * s);
            Tex(new Rect(W / 2 - 520 * s, cy + 112 * s, 1040 * s, 26 * s), tileBorder, Color.white);
            Tex(new Rect(W / 2 - 600 * s, cy - 50 * s, 90 * s, 90 * s), rosette, Color.white);
            Tex(new Rect(W / 2 + 510 * s, cy - 50 * s, 90 * s, 90 * s), rosette, Color.white);
        }

        void DrawTitle()
        {
            Tex(new Rect(0, 0, W, H), vignette, Color.white);
            float a = Mathf.Clamp01(screenTime / 1.2f);
            GUI.color = new Color(1, 1, 1, a);
            Logo(380, 1f);
            float blink = 0.5f + 0.5f * Mathf.Sin(Time.unscaledTime * 4f);
            Text(new Rect(0, 760, W, 60), "BOSHLASH UCHUN ISTALGAN TUGMANI BOSING", 34, new Color(1, 1, 1, blink * a));
            Text(new Rect(0, 1010, W, 40), "Amir Temur • Jaloliddin Manguberdi • Mirzo Ulug'bek • Chingizxon", 24, new Color(0.9f, 0.85f, 0.7f, 0.8f * a), TextAnchor.MiddleCenter, 1);
            GUI.color = Color.white;
        }

        void DrawMainMenu()
        {
            Tex(new Rect(0, 0, W, H), vignette, Color.white);
            Logo(200, 0.8f);
            float y0 = 400;
            for (int i = 0; i < MainItems.Length; i++)
            {
                var r = new Rect(W / 2 - 300, y0 + i * 78, 600, 62);
                if (r.Contains(Event.current.mousePosition) && Event.current.type == EventType.MouseMove) menuIndex = i;
                if (MenuButton(r, MainItems[i], i == menuIndex)) { menuIndex = i; MainAction(i); }
            }
            Text(new Rect(0, H - 50, W, 40), "W/S — tanlash   •   ENTER — tasdiqlash   •   ESC — orqaga", 22, new Color(1, 1, 1, 0.7f), TextAnchor.MiddleCenter, 1);
        }

        // ---------------- Qahramon tanlash ----------------
        void DrawCharSelect()
        {
            Tex(new Rect(0, 0, W, H), vignette, Color.white);
            Text(new Rect(0, 24, W, 70), "QAHRAMONNI TANLANG", 60, Pal.Gold, TextAnchor.MiddleCenter, 4);
            string modeName = gm.mode == GameMode.Arcade ? "ARKADA" : gm.mode == GameMode.Versus ? "IKKI O'YINCHI" : gm.mode == GameMode.Training ? "MASHQ" : "TOMOSHA";
            Text(new Rect(0, 92, W, 36), modeName, 26, ColorUtil.Hex("#bfe8f0"), TextAnchor.MiddleCenter, 2);

            var roster = gm.Roster;
            float cw = 210, ch = 262, gap = 26;
            float total = roster.Count * cw + (roster.Count - 1) * gap;
            float x0 = W / 2 - total / 2, y = H - ch - 70;
            for (int i = 0; i < roster.Count; i++)
            {
                var d = roster[i];
                var r = new Rect(x0 + i * (cw + gap), y, cw, ch);
                Box(r, new Color(0.04f, 0.05f, 0.12f, 0.85f));
                Tex(new Rect(r.x, r.y, r.width, r.height * 0.8f), girih, new Color(1, 1, 1, 0.22f));
                Box(new Rect(r.x, r.y + r.height * 0.55f, r.width, r.height * 0.45f), new Color(d.mainColor.r, d.mainColor.g, d.mainColor.b, 0.35f));
                if (gm.portraits.TryGetValue(d.id, out var rt)) Tex(new Rect(r.x + 5, r.y + 5, r.width - 10, r.height - 50), rt, Color.white, ScaleMode.ScaleAndCrop);
                Box(new Rect(r.x, r.yMax - 46, r.width, 46), new Color(0, 0, 0, 0.65f));
                Text(new Rect(r.x, r.yMax - 46, r.width, 46), Short(d.name), 22, Color.white, TextAnchor.MiddleCenter, 1.5f);
                Frame(r, Pal.Gold.WithA(0.6f), 2);
                bool p1 = gm.p1Index == i, p2 = gm.p2Index == i && (gm.mode == GameMode.Versus || gm.p2Ready);
                float pulse = 0.6f + 0.4f * Mathf.Sin(Time.unscaledTime * 8);
                if (p1)
                {
                    Frame(new Rect(r.x - 6, r.y - 6, r.width + 12, r.height + 12), new Color(0.3f, 0.6f, 1f, gm.p1Ready ? 1 : pulse), 6);
                    Text(new Rect(r.x - 6, r.y - 44, 80, 36), "1P", 30, new Color(0.4f, 0.7f, 1f), TextAnchor.MiddleLeft, 2);
                }
                if (p2)
                {
                    Frame(new Rect(r.x - 12, r.y - 12, r.width + 24, r.height + 24), new Color(1f, 0.3f, 0.25f, gm.p2Ready ? 1 : pulse), 5);
                    Text(new Rect(r.xMax - 80, r.y - 44, 86, 36), gm.mode == GameMode.Versus ? "2P" : "CPU", 30, new Color(1f, 0.4f, 0.35f), TextAnchor.MiddleRight, 2);
                }
                if (Event.current.type == EventType.MouseDown && r.Contains(Event.current.mousePosition))
                {
                    if (!gm.p1Ready) { gm.p1Index = i; gm.SelectMove(0, 0); if (Event.current.clickCount >= 2) gm.Confirm(0); }
                }
            }
            // Ma'lumot panellari
            InfoPanel(new Rect(40, 150, 520, 520), roster[gm.p1Index], gm.p1Ready, new Color(0.4f, 0.7f, 1f), "1-O'YINCHI");
            if (gm.mode == GameMode.Versus || gm.p2Ready)
                InfoPanel(new Rect(W - 560, 150, 520, 520), roster[gm.p2Index], gm.p2Ready, new Color(1f, 0.4f, 0.35f), gm.mode == GameMode.Versus ? "2-O'YINCHI" : "RAQIB");

            Text(new Rect(0, H - 60, W, 40), "1P: A/D — tanlash, U — tasdiq, I — orqaga" + (gm.mode == GameMode.Versus ? "    •    2P: ←/→ — tanlash, Num4 — tasdiq, Num5 — orqaga" : "") + "    •    TAB — usullar    •    T — maydon: " + ArenaNames[gm.arenaChoice], 21, new Color(1, 1, 1, 0.75f), TextAnchor.MiddleCenter, 1);
            if (showMoveList) MoveListPanel(roster[gm.p1Index]);
        }

        static string Short(string n) => n.Replace("JALOLIDDIN MANGUBERDI", "JALOLIDDIN").Replace("MIRZO ULUG'BEK", "ULUG'BEK");

        void InfoPanel(Rect r, FighterDefinition d, bool ready, Color pc, string who)
        {
            Panel(r, 0.95f);
            Text(new Rect(r.x + 30, r.y + 22, r.width - 60, 30), who, 22, pc, TextAnchor.MiddleLeft, 1);
            Text(new Rect(r.x + 30, r.y + 56, r.width - 60, 56), d.name, d.name.Length > 16 ? 34 : 44, d.mainColor.Mul(1.8f), TextAnchor.MiddleLeft, 3);
            Text(new Rect(r.x + 30, r.y + 112, r.width - 60, 34), d.title + "  •  " + d.years, 24, Pal.Gold, TextAnchor.MiddleLeft, 1.5f);
            Box(new Rect(r.x + 30, r.y + 154, r.width - 60, 2), Pal.Gold.WithA(0.6f));
            Text(new Rect(r.x + 30, r.y + 166, r.width - 60, 150), d.bio, 22, new Color(0.92f, 0.9f, 0.85f), TextAnchor.UpperLeft, 1, FontStyle.Normal, true);
            Text(new Rect(r.x + 30, r.y + 318, r.width - 60, 34), d.style, 22, ColorUtil.Hex("#9fe0ea"), TextAnchor.MiddleLeft, 1);
            Text(new Rect(r.x + 30, r.y + 356, r.width - 60, 34), d.quote, 22, new Color(1f, 0.9f, 0.7f), TextAnchor.MiddleLeft, 1, FontStyle.Italic);
            // Ko'rsatkichlar
            StatBar(new Rect(r.x + 30, r.y + 404, r.width - 60, 22), "KUCH", Mathf.InverseLerp(0.85f, 1.15f, d.damageMult));
            StatBar(new Rect(r.x + 30, r.y + 434, r.width - 60, 22), "TEZLIK", Mathf.InverseLerp(2.1f, 3.0f, d.walkFwd));
            StatBar(new Rect(r.x + 30, r.y + 464, r.width - 60, 22), "MASOFA", d.id == "ulugbek" ? 0.95f : d.id == "chingiz" ? 0.7f : d.id == "temur" ? 0.55f : 0.45f);
            if (ready) Text(new Rect(r.x, r.yMax - 40, r.width, 40), "TAYYOR!", 30, new Color(0.5f, 1f, 0.6f), TextAnchor.MiddleCenter, 2);
        }

        void StatBar(Rect r, string label, float v)
        {
            Text(new Rect(r.x, r.y, 130, r.height), label, 18, Color.white, TextAnchor.MiddleLeft, 1);
            var b = new Rect(r.x + 130, r.y + 4, r.width - 130, r.height - 8);
            Box(b, new Color(0, 0, 0, 0.6f));
            Tex(new Rect(b.x, b.y, b.width * Mathf.Clamp(v, 0.1f, 1f), b.height), hpFill, Color.white);
            Frame(b, Pal.Gold.WithA(0.5f), 1);
        }

        void MoveListPanel(FighterDefinition d)
        {
            var r = new Rect(W / 2 - 520, 120, 1040, 820);
            Box(new Rect(0, 0, W, H), new Color(0, 0, 0, 0.6f));
            Panel(r);
            Text(new Rect(r.x, r.y + 20, r.width, 60), d.name + " — HARAKATLAR", 40, Pal.Gold, TextAnchor.MiddleCenter, 3);
            float y = r.y + 100;
            void Row(string a, string b, Color c)
            {
                Text(new Rect(r.x + 60, y, 520, 34), a, 24, c, TextAnchor.MiddleLeft, 1);
                Text(new Rect(r.x + 560, y, 420, 34), b, 24, Color.white, TextAnchor.MiddleRight, 1);
                y += 36;
            }
            void Header(string h) { y += 8; Text(new Rect(r.x + 50, y, r.width - 100, 36), h, 26, ColorUtil.Hex("#9fe0ea"), TextAnchor.MiddleLeft, 2); y += 40; }
            Header("MAXSUS USULLAR");
            var seen = new HashSet<string>();
            foreach (var sp in d.specials)
            {
                var m = d.Get(sp.moveId);
                if (m == null || seen.Contains(m.name)) continue;
                seen.Add(m.name);
                Row(m.name, m.notation, Color.white);
            }
            Header("KOMBO ZANJIRLARI");
            foreach (var id in new[] { "str3", "str4", "hk2", "lk2" }) { var m = d.Get(id); if (m != null) Row(m.name, m.notation, Color.white); }
            Header("SUPER VA YAKUNIY ZARBA");
            var su = d.Get(d.superMoveId);
            if (su != null) Row(su.name + " (super)", "HP + HK  [3 bo'lak]", Pal.Gold);
            if (d.finisherInput != null) Row(d.finisherName, Notation(d.finisherInput) + "  (TUGAT UNI!)", new Color(1f, 0.4f, 0.35f));
            Header("UMUMIY");
            Row("Otish", "O  (yaqin masofada)", Color.white);
            Row("Uzish (Breaker)", "→ + BLOK  [2 bo'lak, kombo ostida]", Color.white);
            Row("Yugurish / Orqaga sakrash", "→ →  /  ← ←", Color.white);
            Text(new Rect(r.x, r.yMax - 50, r.width, 40), "TAB / ESC — yopish", 20, new Color(1, 1, 1, 0.7f), TextAnchor.MiddleCenter, 1);
        }

        static string Arrow(int d) => d switch { 4 => "←", 6 => "→", 2 => "↓", 8 => "↑", 3 => "↘", 1 => "↙", 9 => "↗", 7 => "↖", _ => "•" };

        static string Notation(SpecialInput s)
        {
            var sb = new StringBuilder();
            foreach (var m in s.motion) sb.Append(Arrow(m)).Append(' ');
            sb.Append("+ ").Append(s.button.ToString());
            return sb.ToString();
        }

        // ---------------- QARSHI ekrani ----------------
        void DrawVersus()
        {
            Box(new Rect(0, 0, W, H), new Color(0.02f, 0.02f, 0.06f, 0.92f));
            Tex(new Rect(0, 0, W, H), girih, new Color(1, 1, 1, 0.08f), ScaleMode.ScaleAndCrop);
            var a = gm.Roster[gm.p1Index]; var b = gm.Roster[gm.p2Index];
            float t = Mathf.Clamp01(screenTime / 0.5f);
            float e = 1 - Mathf.Pow(1 - t, 3);
            float pw = 560, ph = 700;
            var ra = new Rect(Mathf.Lerp(-pw, 120, e), 170, pw, ph);
            var rb = new Rect(Mathf.Lerp(W, W - 120 - pw, e), 170, pw, ph);
            foreach (var (r, d) in new[] { (ra, a), (rb, b) })
            {
                Box(r, new Color(d.mainColor.r, d.mainColor.g, d.mainColor.b, 0.5f));
                if (gm.portraits.TryGetValue(d.id, out var rt)) Tex(r, rt, Color.white, ScaleMode.ScaleAndCrop);
                Frame(r, Pal.Gold, 4);
                Text(new Rect(r.x, r.yMax + 10, r.width, 60), d.name, d.name.Length > 16 ? 38 : 48, Color.white, TextAnchor.MiddleCenter, 3);
                Text(new Rect(r.x, r.yMax + 66, r.width, 40), d.title, 26, Pal.Gold, TextAnchor.MiddleCenter, 2);
            }
            float s = 1 + Mathf.Max(0, 0.6f - screenTime) * 2;
            Text(new Rect(0, H / 2 - 100 * s, W, 200 * s), "QARSHI", Mathf.RoundToInt(110 * s), new Color(1f, 0.3f, 0.2f), TextAnchor.MiddleCenter, 6);
            if (gm.mode == GameMode.Arcade && gm.ladder.Count > 0)
            {
                Text(new Rect(0, 60, W, 50), (gm.ladderStep + 1) + " / " + gm.ladder.Count + "  JANG" + (gm.ladderStep == gm.ladder.Count - 1 ? "  —  SOYA JANGI" : ""), 34, ColorUtil.Hex("#bfe8f0"), TextAnchor.MiddleCenter, 2);
            }
        }

        // ---------------- Jang HUD ----------------
        void DrawFight()
        {
            var m = gm.match;
            if (m == null) return;
            Tex(new Rect(0, 0, W, H), vignette, new Color(1, 1, 1, 0.55f));
            if (m.darken > 0.01f) Box(new Rect(0, 0, W, H), new Color(0, 0, 0, m.darken));
            if (gm.showHitboxes) DrawBoxes(m);

            bool hudVisible = m.phase != MatchPhase.Cinematic || true;
            if (hudVisible)
            {
                HealthBar(m.f1, new Rect(60, 34, W / 2 - 170, 48), false);
                HealthBar(m.f2, new Rect(W / 2 + 110, 34, W / 2 - 170, 48), true);
                // Taymer
                var tr = new Rect(W / 2 - 75, 14, 150, 150);
                Tex(tr, rosette, Color.white);
                string ts = m.mode == GameMode.Training ? "∞" : Mathf.CeilToInt(m.timer).ToString();
                Text(new Rect(tr.x, tr.y + 6, tr.width, tr.height), ts, 64, m.timer <= 10 && m.mode != GameMode.Training ? new Color(1f, 0.35f, 0.3f) : Color.white, TextAnchor.MiddleCenter, 3);
                MeterBar(m.f1, new Rect(60, H - 86, 480, 30), false);
                MeterBar(m.f2, new Rect(W - 540, H - 86, 480, 30), true);
            }
            // Kombo
            if (m.comboTimer > 0 && m.comboOwner != null)
            {
                bool left = m.comboOwner == m.f1;
                float a = Mathf.Clamp01(m.comboTimer / 0.4f);
                float pop = 1 + Mathf.Max(0, m.comboTimer - 1.35f) * 2.5f;
                var r = new Rect(left ? 70 : W - 470, 330, 400, 140);
                Text(new Rect(r.x, r.y, r.width, 90 * pop), m.comboDisplayHits + " ZARBA", Mathf.RoundToInt(64 * pop), new Color(1f, 0.85f, 0.3f, a), left ? TextAnchor.MiddleLeft : TextAnchor.MiddleRight, 4);
                int pct = Mathf.RoundToInt(m.comboDamage / 10f);
                Text(new Rect(r.x, r.y + 86, r.width, 44), pct + "% ZARAR", 30, new Color(1, 1, 1, a), left ? TextAnchor.MiddleLeft : TextAnchor.MiddleRight, 2);
            }
            // E'lonlar
            float now = Time.unscaledTime;
            float ay = 420;
            for (int i = m.announcements.Count - 1; i >= 0; i--)
            {
                var an = m.announcements[i];
                float t = now - an.time;
                if (t > an.duration) continue;
                float inT = Mathf.Clamp01(t / 0.18f);
                float outT = Mathf.Clamp01((an.duration - t) / 0.25f);
                float s = (an.big ? 1f : 0.7f) * (1 + (1 - EaseUtil.Apply(Ease.OutBack, inT)) * 0.8f);
                int size = Mathf.RoundToInt((an.big ? 110 : 64) * s);
                Text(new Rect(0, ay - size * 0.6f, W, size * 1.2f), an.text, size, new Color(an.color.r, an.color.g, an.color.b, outT), TextAnchor.MiddleCenter, an.big ? 6 : 4);
                ay += size * 1.05f;
            }
            // Chaqnash
            float ft = now - m.flashTime;
            if (ft < m.flashDur) Box(new Rect(0, 0, W, H), new Color(m.flashColor.r, m.flashColor.g, m.flashColor.b, (1 - ft / m.flashDur) * 0.7f));

            if (m.mode == GameMode.Training) TrainingOverlay(m);
            if (gm.paused) DrawPause();
        }

        void HealthBar(Fighter f, Rect r, bool mirror)
        {
            // Bezakli ramka
            Box(new Rect(r.x - 6, r.y - 6, r.width + 12, r.height + 12), new Color(0.05f, 0.03f, 0.02f, 0.85f));
            Tex(new Rect(r.x - 4, r.y - 4, r.width + 8, r.height + 8), gold, Color.white);
            Tex(r, hpBack, Color.white);
            float hp = Mathf.Clamp01(f.health / f.maxHealth);
            float tr = Mathf.Clamp01(f.displayHealth / f.maxHealth);
            Rect trail = mirror ? new Rect(r.xMax - r.width * tr, r.y, r.width * tr, r.height) : new Rect(r.x, r.y, r.width * tr, r.height);
            Tex(trail, hpTrail, Color.white);
            Rect fill = mirror ? new Rect(r.xMax - r.width * hp, r.y, r.width * hp, r.height) : new Rect(r.x, r.y, r.width * hp, r.height);
            Color hc = hp < 0.25f ? new Color(1f, 0.55f + 0.45f * Mathf.Sin(Time.unscaledTime * 10), 0.5f) : Color.white;
            if (mirror) GUI.DrawTextureWithTexCoords(fill, hpFill, new Rect(1, 0, -1, 1)); else Tex(fill, hpFill, hc);
            Box(new Rect(fill.x, fill.y, fill.width, fill.height * 0.35f), new Color(1, 1, 1, 0.18f));
            Tex(new Rect(r.x, r.yMax - 8, r.width, 8), tileBorder, new Color(1, 1, 1, 0.35f));
            // Rozetka ichki uchida
            Tex(new Rect(mirror ? r.x - 34 : r.xMax - 30, r.center.y - 32, 64, 64), rosette, Color.white);
            // Ism va raund medallari
            Text(new Rect(r.x + (mirror ? 0 : 6), r.yMax + 8, r.width - 6, 40), f.def.name, 32, Color.white, mirror ? TextAnchor.MiddleRight : TextAnchor.MiddleLeft, 2.5f);
            int need = gm.match != null ? gm.match.roundsToWin : 2;
            for (int i = 0; i < need; i++)
            {
                float x = mirror ? r.x + i * 44 : r.xMax - 40 - i * 44;
                var mr = new Rect(x, r.yMax + 10, 36, 36);
                Tex(mr, rosette, i < f.roundsWon ? Color.white : new Color(0.3f, 0.3f, 0.35f, 0.8f));
            }
        }

        void MeterBar(Fighter f, Rect r, bool mirror)
        {
            Box(new Rect(r.x - 4, r.y - 4, r.width + 8, r.height + 8), new Color(0.05f, 0.03f, 0.02f, 0.85f));
            float seg = r.width / 3f;
            for (int i = 0; i < 3; i++)
            {
                var sr = new Rect(r.x + i * seg + 2, r.y, seg - 4, r.height);
                Box(sr, new Color(0.1f, 0.1f, 0.18f, 0.9f));
                float v = Mathf.Clamp01((f.meter - i * 100f) / 100f);
                int idx = mirror ? 2 - i : i;
                v = Mathf.Clamp01((f.meter - idx * 100f) / 100f);
                Rect fill = mirror ? new Rect(sr.xMax - sr.width * v, sr.y, sr.width * v, sr.height) : new Rect(sr.x, sr.y, sr.width * v, sr.height);
                Tex(fill, f.meter >= FightConst.MaxMeter ? meterFull : meterFill, Color.white);
                Frame(sr, Pal.Gold.WithA(0.7f), 1.5f);
            }
            bool full = f.meter >= FightConst.MaxMeter;
            string label = full ? "SUPER TAYYOR: HP + HK" : "QAHRAMONLIK  " + f.Bars + "/3";
            Color lc = full ? new Color(1f, 0.85f, 0.3f, 0.6f + 0.4f * Mathf.Sin(Time.unscaledTime * 8)) : new Color(0.8f, 0.9f, 1f, 0.9f);
            Text(new Rect(r.x, r.y - 36, r.width, 30), label, 22, lc, mirror ? TextAnchor.MiddleRight : TextAnchor.MiddleLeft, 1.5f);
        }

        void TrainingOverlay(MatchController m)
        {
            var r = new Rect(W - 470, 170, 430, 330);
            Box(r, new Color(0.02f, 0.03f, 0.08f, 0.7f));
            Frame(r, Pal.Gold.WithA(0.5f), 1.5f);
            float y = r.y + 12;
            void L(string s, Color c) { Text(new Rect(r.x + 18, y, r.width - 36, 28), s, 20, c, TextAnchor.MiddleLeft, 1, FontStyle.Normal); y += 28; }
            L("MASHQ REJIMI", Pal.Gold);
            L("Qo'g'irchoq: " + gm.dummy.mode, Color.white);
            L("F1 Turish  F2 Cho'kish  F3 Sakrash", new Color(0.8f, 0.9f, 1f));
            L("F4 Blok  F5 Tasodifiy blok  F6 CPU", new Color(0.8f, 0.9f, 1f));
            L("F7 Hitbox ko'rsatish  F8 Joylashuv", new Color(0.8f, 0.9f, 1f));
            y += 6;
            var f = m.f1;
            if (f.move != null || f.lastMoveName != null)
            {
                var mv = f.move;
                L("Oxirgi usul: " + (f.lastMoveName ?? "-"), Color.white);
                if (mv != null) L($"Kadr: start {mv.startup} / faol {mv.active} / tiklanish {mv.recovery}", Color.white);
            }
            L("Kombo zarari: " + Mathf.RoundToInt(m.f2.comboDamage), Color.white);
        }

        void DrawBoxes(MatchController m)
        {
            var c = gm.cam.cam;
            foreach (var f in new[] { m.f1, m.f2 })
            {
                WorldRect(c, f.HurtBox(), new Color(0.3f, 0.6f, 1f, 0.8f));
                if (f.GetActiveHitbox(out var hb, out _)) WorldRect(c, hb, new Color(1f, 0.2f, 0.2f, 0.9f));
            }
            foreach (var p in m.projectiles) if (p != null && p.Active) WorldRect(c, p.Box, new Color(1f, 0.6f, 0.1f, 0.9f));
        }

        void WorldRect(Camera c, Rect r, Color col)
        {
            Vector3 a = c.WorldToScreenPoint(new Vector3(r.xMin, r.yMin, 0));
            Vector3 b = c.WorldToScreenPoint(new Vector3(r.xMax, r.yMax, 0));
            if (a.z < 0 || b.z < 0) return;
            var sr = new Rect(a.x / scale, (Screen.height - b.y) / scale, (b.x - a.x) / scale, (b.y - a.y) / scale);
            Frame(sr, col, 2);
            Box(sr, col.WithA(0.12f));
        }

        void DrawPause()
        {
            Box(new Rect(0, 0, W, H), new Color(0, 0, 0, 0.6f));
            if (showMoveList) { MoveListPanel(gm.match.f1.def); return; }
            var r = new Rect(W / 2 - 360, 220, 720, 620);
            Panel(r);
            Text(new Rect(r.x, r.y + 30, r.width, 70), "TO'XTATILDI", 60, Pal.Gold, TextAnchor.MiddleCenter, 4);
            var items = PauseItems();
            for (int i = 0; i < items.Length; i++)
            {
                var b = new Rect(r.x + 110, r.y + 140 + i * 86, r.width - 220, 66);
                if (b.Contains(Event.current.mousePosition) && Event.current.type == EventType.MouseMove) pauseIndex = i;
                if (MenuButton(b, items[i], i == pauseIndex, 30)) PauseAction(i);
            }
        }

        void DrawResults()
        {
            var m = gm.match;
            if (m == null) return;
            var w = m.matchWinner;
            Box(new Rect(0, 0, W, H), new Color(0, 0, 0, 0.35f));
            var r = new Rect(W / 2 - 480, H - 430, 960, 380);
            Panel(r);
            Text(new Rect(r.x, r.y + 20, r.width, 80), (w != null ? w.def.name : "") + " G'OLIB!", 62, w != null ? w.def.mainColor.Mul(1.8f) : Color.white, TextAnchor.MiddleCenter, 4);
            Text(new Rect(r.x, r.y + 100, r.width, 44), m.winnerQuote ?? "", 30, new Color(1f, 0.9f, 0.7f), TextAnchor.MiddleCenter, 2, FontStyle.Italic);
            if (m.finisherDone) Text(new Rect(r.x, r.y + 146, r.width, 40), "YAKUNIY ZARBA: " + m.finisherTitle, 26, new Color(1f, 0.4f, 0.35f), TextAnchor.MiddleCenter, 2);
            string first = gm.mode == GameMode.Arcade ? (gm.lastMatchWon ? (gm.ladderStep + 1 >= gm.ladder.Count ? "YAKUNLASH" : "KEYINGI JANG") : "QAYTA URINISH") : "QAYTA JANG";
            string[] items = { first, "QAHRAMON TANLASH", "BOSH MENYU" };
            for (int i = 0; i < 3; i++)
            {
                var b = new Rect(r.x + 40 + i * 300, r.yMax - 110, 280, 66);
                if (b.Contains(Event.current.mousePosition) && Event.current.type == EventType.MouseMove) resultIndex = i;
                if (MenuButton(b, items[i], i == resultIndex, 24)) { gm.ResultsAction(i); resultIndex = 0; }
            }
        }

        // ---------------- Boshqaruv ----------------
        void DrawControls()
        {
            Tex(new Rect(0, 0, W, H), vignette, Color.white);
            var r = new Rect(W / 2 - 820, 60, 1640, 960);
            Panel(r);
            Text(new Rect(r.x, r.y + 20, r.width, 70), "BOSHQARUV VA MEXANIKA", 54, Pal.Gold, TextAnchor.MiddleCenter, 3);
            string[,] rows =
            {
                { "Harakat", "W A S D", "↑ ← ↓ →" },
                { "Yengil qo'l / qurol (LP)", "U", "Num 4" },
                { "Kuchli qo'l / qurol (HP)", "I", "Num 5" },
                { "Yengil tepki (LK)", "J", "Num 1" },
                { "Kuchli tepki (HK)", "K", "Num 2" },
                { "Blok (ushlab turing)", "L", "Num 6" },
                { "Otish", "O", "Num 3" },
            };
            float y = r.y + 110;
            Text(new Rect(r.x + 60, y, 600, 40), "TUGMA", 28, ColorUtil.Hex("#9fe0ea"), TextAnchor.MiddleLeft, 2);
            Text(new Rect(r.x + 620, y, 240, 40), "1-O'YINCHI", 28, ColorUtil.Hex("#9fe0ea"), TextAnchor.MiddleCenter, 2);
            Text(new Rect(r.x + 860, y, 240, 40), "2-O'YINCHI", 28, ColorUtil.Hex("#9fe0ea"), TextAnchor.MiddleCenter, 2);
            y += 50;
            for (int i = 0; i < rows.GetLength(0); i++)
            {
                Box(new Rect(r.x + 50, y, 1060, 44), new Color(1, 1, 1, i % 2 == 0 ? 0.05f : 0.02f));
                Text(new Rect(r.x + 60, y, 560, 44), rows[i, 0], 26, Color.white, TextAnchor.MiddleLeft, 1);
                Text(new Rect(r.x + 620, y, 240, 44), rows[i, 1], 28, Pal.Gold, TextAnchor.MiddleCenter, 1);
                Text(new Rect(r.x + 860, y, 240, 44), rows[i, 2], 28, Pal.Gold, TextAnchor.MiddleCenter, 1);
                y += 48;
            }
            float x2 = r.x + 1150;
            float y2 = r.y + 110;
            string[] mech =
            {
                "MEXANIKA",
                "• Blok — tugmani ushlang. Cho'kib blok past zarbalarni to'xtatadi.",
                "• Yuqoridan (overhead) zarbalarni faqat tik turib bloklang.",
                "• Kombo: LP, LP, HP kabi zanjirlar; normal zarbani maxsus usul bilan bekor qiling.",
                "• → → yugurish,  ← ← orqaga sakrash.",
                "• Qahramonlik shkalasi 3 bo'lak to'lsa: HP + HK — SUPER zarba.",
                "• Kombo ostida → + BLOK — Uzish (2 bo'lak).",
                "• Hal qiluvchi raundda raqib gandiraklasa — 'TUGAT UNI!':",
                "   qahramonning yakuniy zarba kombinatsiyasini kiriting.",
                "• Raqib havoda — juggle kombolar davom etadi.",
                "• ESC — pauza va harakatlar ro'yxati.",
            };
            foreach (var s in mech)
            {
                bool head = s == "MEXANIKA";
                Text(new Rect(x2, y2, 440, head ? 44 : 64), s, head ? 30 : 21, head ? ColorUtil.Hex("#9fe0ea") : Color.white, TextAnchor.UpperLeft, 1, head ? FontStyle.Bold : FontStyle.Normal, true);
                y2 += head ? 50 : 66;
            }
            Text(new Rect(r.x, r.yMax - 60, r.width, 40), "ENTER / ESC — orqaga", 22, new Color(1, 1, 1, 0.7f), TextAnchor.MiddleCenter, 1);
        }

        void DrawOptions()
        {
            Tex(new Rect(0, 0, W, H), vignette, Color.white);
            var r = new Rect(W / 2 - 500, 160, 1000, 760);
            Panel(r);
            Text(new Rect(r.x, r.y + 24, r.width, 70), "SOZLAMALAR", 56, Pal.Gold, TextAnchor.MiddleCenter, 3);
            string[] names = { "QIYINLIK", "G'ALABA UCHUN RAUND", "MAYDON", "MUSIQA", "EFFEKTLAR", "GRAFIKA" };
            string[] vals =
            {
                DiffNames[gm.difficulty], gm.roundsToWin.ToString(), ArenaNames[gm.arenaChoice],
                Mathf.RoundToInt(SynthAudio.I.MusicVolume * 100) + "%", Mathf.RoundToInt(SynthAudio.I.sfxVolume * 100) + "%",
                QualitySettings.names.Length > 0 ? QualitySettings.names[QualitySettings.GetQualityLevel()].ToUpper() : "-"
            };
            for (int i = 0; i < names.Length; i++)
            {
                var b = new Rect(r.x + 80, r.y + 140 + i * 90, r.width - 160, 70);
                bool sel = i == optionIndex;
                Box(b, sel ? new Color(0.85f, 0.62f, 0.2f, 0.85f) : new Color(0.05f, 0.08f, 0.18f, 0.75f));
                Frame(b, Pal.Gold.WithA(sel ? 1 : 0.5f), sel ? 3 : 1);
                Text(new Rect(b.x + 30, b.y, 420, b.height), names[i], 30, sel ? ColorUtil.Hex("#1a0e04") : Color.white, TextAnchor.MiddleLeft, sel ? 0 : 2);
                Text(new Rect(b.x + 400, b.y, b.width - 430, b.height), "◄  " + vals[i] + "  ►", 30, sel ? ColorUtil.Hex("#1a0e04") : Pal.Gold, TextAnchor.MiddleRight, sel ? 0 : 2);
                if (GUI.Button(b, GUIContent.none, GUIStyle.none)) { optionIndex = i; ChangeOption(i, 1); }
            }
            Text(new Rect(r.x, r.yMax - 60, r.width, 40), "W/S — tanlash   A/D — o'zgartirish   ESC — orqaga", 22, new Color(1, 1, 1, 0.7f), TextAnchor.MiddleCenter, 1);
        }

        void DrawEnding()
        {
            Tex(new Rect(0, 0, W, H), vignette, Color.white);
            var d = gm.Roster[gm.p1Index];
            Text(new Rect(0, 60, W, 110), "TABRIKLAYMIZ!", 96, Pal.Gold, TextAnchor.MiddleCenter, 5);
            var r = new Rect(W / 2 - 640, H - 380, 1280, 330);
            Panel(r);
            Text(new Rect(r.x, r.y + 20, r.width, 60), d.name + " — YAKUN", 44, d.mainColor.Mul(1.8f), TextAnchor.MiddleCenter, 3);
            Text(new Rect(r.x + 60, r.y + 90, r.width - 120, 180), EndingText(d.id), 26, new Color(0.95f, 0.92f, 0.85f), TextAnchor.UpperCenter, 1, FontStyle.Normal, true);
            Text(new Rect(r.x, r.yMax - 50, r.width, 40), "ENTER — bosh menyu", 22, new Color(1, 1, 1, 0.7f), TextAnchor.MiddleCenter, 1);
        }

        static string EndingText(string id) => id switch
        {
            "temur" => "Barcha raqiblarini yengib, Sohibqiron Samarqandga qaytdi. U zafar sharafiga Ko'k saroyni bezatdi va adolat qonunlarini yangiladi: «Kuch — adolatdadir». Uning nomi asrlar osha yashaydi.",
            "jaloliddin" => "Xorazm sheri bosqinchilarni ortga qaytardi. U Sind daryosi bo'yida qasam ichdi: vatan himoyasi hech qachon to'xtamaydi. Xalq uni dostonlarda kuylaydi.",
            "ulugbek" => "Jangdagi g'alabadan so'ng Ulug'bek rasadxonasiga qaytdi va «Zij»ga yangi yulduzni qo'shdi — g'alaba yulduzini. Ilm qilichdan kuchliroq ekanini u yana bir bor isbotladi.",
            _ => "Dasht bo'roni barcha raqiblarni yengdi. Ammo qadimiy qishloqning mehmondo'stligi uni hayratga soldi — u bu yurtni bosib olmay, unga do'stlik qo'lini cho'zdi.",
        };
    }
}
