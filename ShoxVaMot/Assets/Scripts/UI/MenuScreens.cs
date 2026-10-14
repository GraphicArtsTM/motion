using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using Shatranj.Chess;
using Shatranj.Core;
using Shatranj.Visual;

namespace Shatranj.UI
{
    // ====================================================================== Загрузка

    public class LoadingScreen : UIScreen
    {
        Text status;

        protected override void Build()
        {
            var bg = UIKit.Raw(Root, TextureFactory.VerticalGradient("loading", UIKit.Deep, UIKit.Lapis), Color.white, "bg");
            bg.raycastTarget = true;
            var pattern = UIKit.Raw(Root, TextureFactory.Majolica("ui.loading", UIKit.Deep, UIKit.Lapis, UIKit.Gold, UIKit.Turq, 2, 128), new Color(1, 1, 1, 0.07f), "pattern");
            pattern.uvRect = new Rect(0, 0, 4, 7);

            var em = UIKit.Emblem(Root, 360);
            UIKit.Place(em, new Vector2(0.5f, 0.62f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(360, 360));
            em.gameObject.AddComponent<Spin>().Speed = 20f;

            var title = UIKit.Label(Root, Loc.T("app.title"), 130, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            UIKit.Place(title.rectTransform, new Vector2(0.5f, 0.45f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(1000, 170));
            UIKit.Shadow(title, new Color(0, 0, 0, 0.6f), 5f);
            var sub = UIKit.Label(Root, Loc.T("app.subtitle"), 46, UIKit.Ivory, TextAnchor.MiddleCenter, FontStyle.Italic);
            UIKit.Place(sub.rectTransform, new Vector2(0.5f, 0.39f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(1000, 80));

            var proverb = UIKit.Label(Root, Loc.RandomProverb(), 36, UIKit.Turq, TextAnchor.MiddleCenter, FontStyle.Italic);
            UIKit.Place(proverb.rectTransform, new Vector2(0.5f, 0.2f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(900, 160));
            status = UIKit.Label(Root, Loc.T("loading"), 34, new Color(1, 1, 1, 0.6f));
            UIKit.Place(status.rectTransform, new Vector2(0.5f, 0.08f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(900, 60));
        }

        public void SetProgress(float p)
        {
            if (status != null) status.text = Loc.T("loading") + "  " + Mathf.RoundToInt(p * 100f) + "%";
        }
    }

    // ====================================================================== Главное меню

    public class MainMenuScreen : UIScreen
    {
        Button continueBtn;

        protected override void Build()
        {
            var shade = UIKit.Raw(Root, TextureFactory.VerticalGradient("menu.shade", new Color(0.02f, 0.05f, 0.14f, 0.92f), new Color(0.02f, 0.05f, 0.14f, 0.0f)), Color.white, "shade");
            shade.rectTransform.anchorMax = new Vector2(1, 0.62f);
            var top = UIKit.Raw(Root, TextureFactory.VerticalGradient("menu.top", new Color(0.02f, 0.05f, 0.14f, 0f), new Color(0.02f, 0.05f, 0.14f, 0.75f)), Color.white, "topshade");
            top.rectTransform.anchorMin = new Vector2(0, 0.7f);

            var em = UIKit.Emblem(Root, 220);
            UIKit.Place(em, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0, -60), new Vector2(220, 220));
            em.gameObject.AddComponent<Spin>().Speed = 6f;

            var title = UIKit.Label(Root, Loc.T("app.title"), 136, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold, "title");
            UIKit.Place(title.rectTransform, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0, -280), new Vector2(1060, 170));
            UIKit.Outline(title, new Color(0.3f, 0.15f, 0.02f, 1f), 3f);
            UIKit.Shadow(title, new Color(0, 0, 0, 0.7f), 7f);
            var sub = UIKit.Label(Root, Loc.T("app.subtitle"), 48, UIKit.Ivory, TextAnchor.MiddleCenter, FontStyle.Italic);
            UIKit.Place(sub.rectTransform, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0, -440), new Vector2(1000, 70));
            UIKit.Shadow(sub, new Color(0, 0, 0, 0.7f), 3f);
            var strip = UIKit.Raw(Root, UIKit.Ornament, Color.white, "strip");
            UIKit.Place(strip.rectTransform, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0, -520), new Vector2(620, 36));
            strip.uvRect = new Rect(0, 0, 4f, 1f);

            var list = UIKit.Rect(Root, "buttons");
            UIKit.Place(list, new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0, 90), new Vector2(780, 0));
            UIKit.VList(list.gameObject, 20f);
            list.gameObject.AddComponent<ContentSizeFitter>().verticalFit = ContentSizeFitter.FitMode.PreferredSize;

            continueBtn = UIKit.Btn(list, Loc.T("menu.continue"), () => Game.ContinueSaved(), BtnStyle.Primary, 124, 48);
            UIKit.Btn(list, Loc.T("menu.newgame"), () => UI.Show(UI.NewGame), BtnStyle.Primary, 124, 48);
            UIKit.Btn(list, Loc.T("menu.museum"), () => UI.Show(UI.Museum), BtnStyle.Secondary, 112);
            UIKit.Btn(list, Loc.T("menu.rules"), () => UI.Show(UI.Rules), BtnStyle.Secondary, 112);
            var row = UIKit.Rect(list, "row");
            UIKit.Layout(row, 112);
            var h = UIKit.HList(row.gameObject, 20f);
            h.childForceExpandWidth = true;
            UIKit.Btn(row, Loc.T("menu.settings"), () => UI.Show(UI.Settings), BtnStyle.Secondary, -1, 40);
            UIKit.Btn(row, Loc.T("menu.stats"), () => UI.Show(UI.Stats), BtnStyle.Secondary, -1, 40);
            UIKit.Btn(list, Loc.T("menu.exit"), () => OnBack(), BtnStyle.Ghost, 96, 38);

            // кнопка языка в правом верхнем углу: O'zbekcha → Ўзбекча → Русский → English
            var lang = UIKit.Btn(Root, Loc.LanguageName(Game.Settings.Lang), () =>
            {
                int idx = System.Array.IndexOf(Loc.Order, Game.Settings.Lang);
                Game.SetLanguage(Loc.Order[(idx + 1) % Loc.Order.Length]);
            }, BtnStyle.Ghost, -1, 32);
            var lrt = (RectTransform)lang.transform;
            UIKit.Place(lrt, new Vector2(1f, 1f), new Vector2(1f, 1f), new Vector2(-24, -24), new Vector2(250, 84));

            var ver = UIKit.Label(Root, Loc.T("version") + " " + Application.version, 26, new Color(1, 1, 1, 0.45f));
            UIKit.Place(ver.rectTransform, new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0, 30), new Vector2(800, 40));
        }

        public override void OnShow()
        {
            continueBtn.gameObject.SetActive(SavedMatch.Exists);
            Game.EnterMenuScene();
        }

        public override bool OnBack()
        {
            UI.Ask(Loc.T("confirm.exit"), () => Game.Quit());
            return true;
        }
    }

    // ====================================================================== Новая игра

    public class NewGameScreen : UIScreen
    {
        MatchConfig cfg;
        Text variantDesc;

        protected override void Build()
        {
            cfg = new MatchConfig();
            RectTransform content, footer;
            Page(Loc.T("menu.newgame"), out content, out footer);

            UIKit.Heading(content, Loc.T("ng.mode"), 44);
            var modes = UIKit.Rect(content, "modes");
            UIKit.Layout(modes, 170);
            var h = UIKit.HList(modes.gameObject, 20f);
            h.childForceExpandWidth = true;
            var pvp = UIKit.Btn(modes, Loc.T("mode.pvp") + "\n<size=28>" + Loc.T("mode.pvp.desc") + "</size>", null, BtnStyle.Primary, -1, 40);
            var ai = UIKit.Btn(modes, Loc.T("mode.ai") + "\n<size=28><color=#2BB3B1>" + Loc.T("common.soon") + "</color></size>", null, BtnStyle.Secondary, -1, 40);
            ai.interactable = false;
            pvp.onClick.AddListener(() => { });

            UIKit.Heading(content, Loc.T("ng.variant"), 44);
            UIKit.OptionRow(content, Loc.T("ng.variant"), new[] { Loc.T("variant.classic"), Loc.T("variant.afrosiyob") }, cfg.variant, i =>
            {
                cfg.variant = i;
                variantDesc.text = Loc.T(i == 0 ? "variant.classic.desc" : "variant.afrosiyob.desc");
            });
            variantDesc = UIKit.Paragraph(content, Loc.T("variant.classic.desc"), 32, TextAnchor.UpperCenter);
            variantDesc.color = UIKit.Turq;

            var times = new string[TimeControl.Presets.Length];
            for (int i = 0; i < times.Length; i++) times[i] = TimeControl.Presets[i].Label;
            UIKit.OptionRow(content, Loc.T("ng.time"), times, cfg.timeIndex, i => cfg.timeIndex = i);

            UIKit.Heading(content, Loc.T("mode.pvp"), 44);
            UIKit.InputRow(content, Loc.T("ng.white"), PlayerPrefs.GetString("shatranj.name.w", ""), Loc.T("side.white"), v => { cfg.whiteName = v; PlayerPrefs.SetString("shatranj.name.w", v); });
            UIKit.InputRow(content, Loc.T("ng.black"), PlayerPrefs.GetString("shatranj.name.b", ""), Loc.T("side.black"), v => { cfg.blackName = v; PlayerPrefs.SetString("shatranj.name.b", v); });
            UIKit.OptionRow(content, Loc.T("set.autorotate"), new[] { Loc.T("common.on"), Loc.T("common.off") }, Game.Settings.autoRotate ? 0 : 1, i =>
            {
                Game.Settings.autoRotate = i == 0;
                Game.Settings.Save();
            });

            UIKit.Btn(footer, Loc.T("common.back"), () => OnBack(), BtnStyle.Secondary, -1);
            UIKit.Btn(footer, Loc.T("common.start"), Start, BtnStyle.Primary, -1, 46);
        }

        public override void OnShow()
        {
            cfg.whiteName = PlayerPrefs.GetString("shatranj.name.w", "");
            cfg.blackName = PlayerPrefs.GetString("shatranj.name.b", "");
        }

        void Start()
        {
            PlayerPrefs.Save();
            Game.StartNewMatch(cfg.Clone());
        }

        public override bool OnBack()
        {
            UI.Show(UI.Main);
            return true;
        }
    }

    // ====================================================================== Настройки

    public class SettingsScreen : UIScreen
    {
        public UIScreen ReturnTo;

        protected override void Build()
        {
            var s = Game.Settings;
            RectTransform content, footer;
            Page(Loc.T("menu.settings"), out content, out footer);

            var langNames = new string[Loc.Order.Length];
            for (int i = 0; i < langNames.Length; i++) langNames[i] = Loc.LanguageName(Loc.Order[i]);
            UIKit.OptionRow(content, Loc.T("set.language"), langNames,
                System.Array.IndexOf(Loc.Order, s.Lang), i => Game.SetLanguage(Loc.Order[i]));
            UIKit.SliderRow(content, Loc.T("set.music"), s.musicVolume, v => { s.musicVolume = v; Game.ApplyAudio(); });
            UIKit.SliderRow(content, Loc.T("set.sfx"), s.sfxVolume, v => { s.sfxVolume = v; Game.ApplyAudio(); });
            string[] onOff = { Loc.T("common.on"), Loc.T("common.off") };
            UIKit.OptionRow(content, Loc.T("set.battle"), new[] { Loc.T("battle.full"), Loc.T("battle.fast"), Loc.T("battle.off") }, s.battleMode, i => { s.battleMode = i; s.Save(); });
            UIKit.OptionRow(content, Loc.T("set.cinematic"), onOff, s.cinematicCamera ? 0 : 1, i => { s.cinematicCamera = i == 0; s.Save(); });
            UIKit.OptionRow(content, Loc.T("set.showmoves"), onOff, s.showLegalMoves ? 0 : 1, i => { s.showLegalMoves = i == 0; s.Save(); Game.RefreshBoardHints(); });
            UIKit.OptionRow(content, Loc.T("set.coords"), onOff, s.showCoordinates ? 0 : 1, i => { s.showCoordinates = i == 0; Game.ApplyVisualSettings(); });
            UIKit.OptionRow(content, Loc.T("set.autorotate"), onOff, s.autoRotate ? 0 : 1, i => { s.autoRotate = i == 0; s.Save(); });
            UIKit.OptionRow(content, Loc.T("set.vibration"), onOff, s.vibration ? 0 : 1, i => { s.vibration = i == 0; s.Save(); });
            UIKit.OptionRow(content, Loc.T("set.ambience"), new[] { Loc.T("amb.day"), Loc.T("amb.sunset"), Loc.T("amb.night") }, s.timeOfDay, i => { s.timeOfDay = i; Game.ApplyVisualSettings(); });
            UIKit.OptionRow(content, Loc.T("set.quality"), new[] { Loc.T("q.low"), Loc.T("q.med"), Loc.T("q.high") }, s.quality, i => { s.quality = i; Game.ApplyVisualSettings(); });
            UIKit.OptionRow(content, Loc.T("set.postfx"), onOff, s.postFx ? 0 : 1, i => { s.postFx = i == 0; Game.ApplyVisualSettings(); });

            UIKit.Btn(footer, Loc.T("common.back"), () => OnBack(), BtnStyle.Primary, -1);
        }

        public override void OnHide() { Game.Settings.Save(); }

        public override bool OnBack()
        {
            Game.Settings.Save();
            if (ReturnTo != null)
            {
                var r = ReturnTo;
                ReturnTo = null;
                UI.Show(r);
                if (r == UI.Hud) UI.PushOverlay(UI.Pause);
            }
            else UI.Show(UI.Main);
            return true;
        }
    }

    // ====================================================================== Правила

    public class RulesScreen : UIScreen
    {
        RectTransform content;
        bool filled;

        protected override void Build()
        {
            RectTransform footer;
            Page(Loc.T("menu.rules"), out content, out footer);
            UIKit.Btn(footer, Loc.T("common.back"), () => OnBack(), BtnStyle.Primary, -1);
        }

        public override void OnShow()
        {
            if (filled) return;
            filled = true;
            Section(content, "rules.goal");
            Section(content, "rules.controls");

            UIKit.Heading(content, Loc.T("menu.museum"), 46);
            for (int t = 6; t >= 1; t--)
            {
                var type = (PieceType)t;
                var row = UIKit.Rect(content, "piece");
                var bg = row.gameObject.AddComponent<Image>();
                bg.sprite = UIKit.Round;
                bg.type = Image.Type.Sliced;
                bg.color = new Color(1, 1, 1, 0.05f);
                UIKit.Layout(bg, 210);
                var icon = UIKit.Raw(row, IconRenderer.Get(type, Side.White), Color.white, "icon");
                icon.rectTransform.anchorMax = new Vector2(0, 1);
                icon.rectTransform.offsetMax = new Vector2(190, 0);
                var name = UIKit.Label(row, Loc.T("piece." + type) + "  <size=30><color=#F6ECD6>— " + Loc.T("hero." + type) + "</color></size>", 40, UIKit.Gold, TextAnchor.UpperLeft, FontStyle.Bold);
                name.rectTransform.offsetMin = new Vector2(200, 0);
                name.rectTransform.offsetMax = new Vector2(-20, -18);
                var mv = UIKit.Label(row, Loc.T("move." + type), 30, UIKit.Ivory, TextAnchor.UpperLeft);
                mv.rectTransform.offsetMin = new Vector2(200, 10);
                mv.rectTransform.offsetMax = new Vector2(-20, -78);
            }

            Section(content, "rules.special");
            Section(content, "rules.hero");
            Section(content, "rules.afro");
            Section(content, "rules.draw");
            Section(content, "rules.about");
        }

        static void Section(RectTransform content, string key)
        {
            UIKit.Heading(content, Loc.T(key + ".t"), 46);
            UIKit.Paragraph(content, Loc.T(key), 34);
        }

        public override bool OnBack()
        {
            UI.Show(UI.Main);
            return true;
        }
    }

    // ====================================================================== Статистика

    public class StatsScreen : UIScreen
    {
        RectTransform content;

        protected override void Build()
        {
            RectTransform footer;
            Page(Loc.T("menu.stats"), out content, out footer);
            UIKit.Btn(footer, Loc.T("common.back"), () => OnBack(), BtnStyle.Primary, -1);
        }

        public override void OnShow()
        {
            for (int i = content.childCount - 1; i >= 0; i--) Object.Destroy(content.GetChild(i).gameObject);
            var st = Game.Stats;
            Row("stats.played", st.played);
            Row("stats.white", st.whiteWins);
            Row("stats.black", st.blackWins);
            Row("stats.draws", st.draws);
            Row("stats.captures", st.captures);
            Row("stats.heroes", st.heroes);
            Row("stats.fastest", st.fastestMate);
            Row("stats.afro", st.afrosiyobGames);
            var spacer = UIKit.Rect(content, "spacer");
            UIKit.Layout(spacer, 30);
            UIKit.Btn(content, Loc.T("stats.reset"), () =>
                UI.Ask(Loc.T("stats.reset.confirm"), () => { Game.Stats.Reset(); OnShow(); }), BtnStyle.Danger, 104, 38);
            var proverb = UIKit.Paragraph(content, "\n" + Loc.RandomProverb(), 32, TextAnchor.UpperCenter);
            proverb.color = UIKit.Turq;
            proverb.fontStyle = FontStyle.Italic;
        }

        void Row(string key, int value)
        {
            var row = UIKit.Rect(content, key);
            var bg = row.gameObject.AddComponent<Image>();
            bg.sprite = UIKit.Round;
            bg.type = Image.Type.Sliced;
            bg.color = new Color(1, 1, 1, 0.05f);
            UIKit.Layout(bg, 100);
            var l = UIKit.Label(row, Loc.T(key), 38, UIKit.Ivory, TextAnchor.MiddleLeft);
            l.rectTransform.offsetMin = new Vector2(32, 0);
            var v = UIKit.Label(row, value > 0 ? value.ToString() : "—", 44, UIKit.Gold, TextAnchor.MiddleRight, FontStyle.Bold);
            v.rectTransform.offsetMax = new Vector2(-36, 0);
        }

        public override bool OnBack()
        {
            UI.Show(UI.Main);
            return true;
        }
    }

    // ====================================================================== Музей Афросиаба

    public class MuseumScreen : UIScreen
    {
        int index;
        Side side = Side.White;
        Text name, hero, lore, moves;
        RawImage view;
        ShowcaseDrag drag;

        static readonly PieceType[] Order = { PieceType.King, PieceType.Queen, PieceType.Rook, PieceType.Bishop, PieceType.Knight, PieceType.Pawn };

        protected override void Build()
        {
            var panel = UIKit.Panel(Root, "page");
            UIKit.Stretch(panel, 30, 40, 30, 50);
            var title = UIKit.Label(panel, Loc.T("menu.museum"), 60, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            title.rectTransform.anchorMin = new Vector2(0, 1);
            title.rectTransform.offsetMin = new Vector2(30, -165);
            title.rectTransform.offsetMax = new Vector2(-30, -62);
            UIKit.Shadow(title, new Color(0, 0, 0, 0.6f), 3f);

            // витрина
            var stage = UIKit.Rect(panel, "stage");
            stage.anchorMin = new Vector2(0, 0);
            stage.anchorMax = new Vector2(1, 1);
            stage.offsetMin = new Vector2(40, 760);
            stage.offsetMax = new Vector2(-40, -170);
            var glow = UIKit.Raw(stage, TextureFactory.Glow(), new Color(0.17f, 0.7f, 0.69f, 0.35f), "glow");
            glow.gameObject.AddComponent<AspectRatioFitter>().aspectMode = AspectRatioFitter.AspectMode.FitInParent;
            var star = UIKit.Img(stage, UIKit.StarOutline, new Color(UIKit.Gold.r, UIKit.Gold.g, UIKit.Gold.b, 0.35f), "star");
            star.gameObject.AddComponent<AspectRatioFitter>().aspectMode = AspectRatioFitter.AspectMode.FitInParent;
            star.gameObject.AddComponent<Spin>().Speed = -4f;
            view = UIKit.Raw(stage, null, Color.white, "view");
            view.gameObject.AddComponent<AspectRatioFitter>().aspectMode = AspectRatioFitter.AspectMode.FitInParent;
            view.raycastTarget = true;
            drag = view.gameObject.AddComponent<ShowcaseDrag>();
            var hint = UIKit.Label(stage, Loc.T("museum.hint"), 28, new Color(1, 1, 1, 0.5f), TextAnchor.LowerCenter, FontStyle.Italic);
            hint.rectTransform.offsetMin = new Vector2(0, -10);

            name = UIKit.Label(panel, "", 58, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            Bottom(name.rectTransform, 680, 80);
            UIKit.Shadow(name, new Color(0, 0, 0, 0.6f), 3f);
            hero = UIKit.Label(panel, "", 38, UIKit.Turq, TextAnchor.MiddleCenter, FontStyle.Italic);
            Bottom(hero.rectTransform, 630, 56);
            lore = UIKit.Label(panel, "", 32, UIKit.Ivory, TextAnchor.UpperCenter);
            Bottom(lore.rectTransform, 430, 190);
            moves = UIKit.Label(panel, "", 30, new Color(1f, 0.9f, 0.65f), TextAnchor.UpperCenter);
            Bottom(moves.rectTransform, 300, 120);

            var row = UIKit.Rect(panel, "row");
            Bottom(row, 165, 120);
            var h = UIKit.HList(row.gameObject, 18f);
            h.childForceExpandWidth = false;
            UIKit.Layout(UIKit.Btn(row, "‹", () => Step(-1), BtnStyle.Secondary, -1, 64), -1, 150);
            var atk = UIKit.Btn(row, Loc.T("museum.attack"), () => { if (Game.Showcase != null) Game.Showcase.Attack(); }, BtnStyle.Primary, -1, 44);
            UIKit.Layout(atk, -1, 0, 1);
            UIKit.Layout(UIKit.Btn(row, "›", () => Step(1), BtnStyle.Secondary, -1, 64), -1, 150);

            var row2 = UIKit.Rect(panel, "row2");
            Bottom(row2, 40, 110);
            var h2 = UIKit.HList(row2.gameObject, 18f);
            h2.childForceExpandWidth = true;
            UIKit.Btn(row2, Loc.T("common.back"), () => OnBack(), BtnStyle.Secondary, -1, 40);
            UIKit.Btn(row2, Loc.T("museum.side"), () => { side = Pc.Other(side); Refresh(); }, BtnStyle.Secondary, -1, 36);
        }

        static void Bottom(RectTransform rt, float y, float h)
        {
            rt.anchorMin = new Vector2(0, 0);
            rt.anchorMax = new Vector2(1, 0);
            rt.pivot = new Vector2(0.5f, 0);
            rt.offsetMin = new Vector2(50, y);
            rt.offsetMax = new Vector2(-50, y + h);
        }

        void Step(int d)
        {
            index = (index + d + Order.Length) % Order.Length;
            Refresh();
        }

        void Refresh()
        {
            var t = Order[index];
            name.text = Loc.T("piece." + t);
            hero.text = Loc.T("hero." + t);
            lore.text = Loc.T("lore." + t);
            moves.text = "<b>" + Loc.T("museum.moves") + ":</b> " + Loc.T("move." + t);
            if (Game.Showcase != null)
            {
                Game.Showcase.Show(t, side);
                view.texture = Game.Showcase.Texture;
            }
            Shatranj.Audio.AudioManager.Play(Shatranj.Audio.Sfx.Open, 0.6f);
        }

        public override void OnShow()
        {
            drag.Stage = Game.Showcase;
            if (Game.Showcase != null) Game.Showcase.SetActive(true);
            Refresh();
        }

        public override void OnHide()
        {
            if (Game.Showcase != null) Game.Showcase.SetActive(false);
        }

        public override bool OnBack()
        {
            UI.Show(UI.Main);
            return true;
        }
    }

    /// <summary>Вращение фигуры в витрине пальцем.</summary>
    public class ShowcaseDrag : MonoBehaviour, IDragHandler, IEndDragHandler
    {
        public ShowcaseStage Stage;
        float lastVx;

        public void OnDrag(PointerEventData e)
        {
            if (Stage == null) return;
            Stage.Drag(e.delta.x);
            lastVx = e.delta.x / Mathf.Max(Time.unscaledDeltaTime, 0.001f);
        }

        public void OnEndDrag(PointerEventData e)
        {
            if (Stage != null) Stage.Release(lastVx * 0.02f);
        }
    }
}
