using System;
using System.Collections.Generic;
using System.Text;
using UnityEngine;
using UnityEngine.UI;
using Shatranj.Chess;
using Shatranj.Core;
using Shatranj.Visual;

namespace Shatranj.UI
{
    // ====================================================================== Карточка игрока

    public class PlayerCard
    {
        public RectTransform Root;
        Image bg, frame, clockBg;
        RawImage icon;
        Text name, clock, material, turn;
        RectTransform captured;
        readonly List<RawImage> capIcons = new List<RawImage>();
        public Side Side { get; private set; }

        public PlayerCard(Transform parent, string id)
        {
            Root = UIKit.Rect(parent, "card_" + id);
            bg = Root.gameObject.AddComponent<Image>();
            bg.sprite = UIKit.Round;
            bg.type = Image.Type.Sliced;
            bg.color = new Color(UIKit.Deep.r, UIKit.Deep.g, UIKit.Deep.b, 0.86f);
            frame = UIKit.Img(Root, UIKit.Frame, UIKit.Gold, "frame");
            frame.rectTransform.offsetMin = new Vector2(4, 4);
            frame.rectTransform.offsetMax = new Vector2(-4, -4);

            var iconBg = UIKit.Img(Root, UIKit.Circle, new Color(1, 1, 1, 0.08f), "iconBg");
            iconBg.rectTransform.anchorMin = new Vector2(0, 0.5f);
            iconBg.rectTransform.anchorMax = new Vector2(0, 0.5f);
            iconBg.rectTransform.sizeDelta = new Vector2(130, 130);
            iconBg.rectTransform.anchoredPosition = new Vector2(85, 0);
            icon = UIKit.Raw(iconBg.rectTransform, null, Color.white, "icon");
            icon.rectTransform.offsetMin = new Vector2(-12, -12);
            icon.rectTransform.offsetMax = new Vector2(12, 12);

            name = UIKit.Label(Root, "", 42, UIKit.Ivory, TextAnchor.UpperLeft, FontStyle.Bold, "name");
            name.rectTransform.offsetMin = new Vector2(170, 0);
            name.rectTransform.offsetMax = new Vector2(-260, -22);
            name.horizontalOverflow = HorizontalWrapMode.Overflow;

            captured = UIKit.Rect(Root, "captured");
            captured.anchorMin = new Vector2(0, 0);
            captured.anchorMax = new Vector2(1, 0);
            captured.pivot = new Vector2(0, 0);
            captured.offsetMin = new Vector2(166, 18);
            captured.offsetMax = new Vector2(-330, 72);
            var h = UIKit.HList(captured.gameObject, -14f, null, TextAnchor.MiddleLeft);
            h.childForceExpandHeight = false;
            h.childControlHeight = false;
            h.childControlWidth = false;

            material = UIKit.Label(Root, "", 34, UIKit.Turq, TextAnchor.LowerRight, FontStyle.Bold, "material");
            material.rectTransform.offsetMin = new Vector2(0, 22);
            material.rectTransform.offsetMax = new Vector2(-250, 0);

            var clockRt = UIKit.Rect(Root, "clock");
            clockRt.anchorMin = new Vector2(1, 0.5f);
            clockRt.anchorMax = new Vector2(1, 0.5f);
            clockRt.pivot = new Vector2(1, 0.5f);
            clockRt.sizeDelta = new Vector2(220, 96);
            clockRt.anchoredPosition = new Vector2(-24, 0);
            clockBg = clockRt.gameObject.AddComponent<Image>();
            clockBg.sprite = UIKit.Pill;
            clockBg.type = Image.Type.Sliced;
            clockBg.color = new Color(0, 0, 0, 0.45f);
            clock = UIKit.Label(clockRt, "", 52, UIKit.Ivory, TextAnchor.MiddleCenter, FontStyle.Bold, "time");

            turn = UIKit.Label(Root, "", 30, UIKit.Gold, TextAnchor.UpperRight, FontStyle.Italic, "turn");
            turn.rectTransform.offsetMax = new Vector2(-30, -10);
            turn.rectTransform.offsetMin = new Vector2(0, 0);
            turn.gameObject.SetActive(false);
        }

        public void SetSide(Side s, string playerName)
        {
            Side = s;
            name.text = playerName;
            icon.texture = IconRenderer.Get(PieceType.King, s);
        }

        public void SetActive(bool active, string turnText)
        {
            frame.color = active ? UIKit.Gold : new Color(1, 1, 1, 0.15f);
            bg.color = active ? new Color(UIKit.Lapis.r * 0.7f, UIKit.Lapis.g * 0.7f, UIKit.Lapis.b * 0.7f, 0.92f) : new Color(UIKit.Deep.r, UIKit.Deep.g, UIKit.Deep.b, 0.8f);
            name.color = active ? UIKit.Gold : UIKit.Ivory;
            clockBg.color = active ? new Color(UIKit.Gold.r, UIKit.Gold.g, UIKit.Gold.b, 0.9f) : new Color(0, 0, 0, 0.45f);
            clock.color = active ? UIKit.Ink : UIKit.Ivory;
        }

        public void SetClock(float seconds, bool visible)
        {
            clockBg.gameObject.SetActive(visible);
            if (!visible) return;
            seconds = Mathf.Max(0f, seconds);
            int s = Mathf.CeilToInt(seconds);
            clock.text = seconds < 10f ? seconds.ToString("0.0") : (s / 60) + ":" + (s % 60).ToString("00");
            if (seconds < 20f) clock.color = UIKit.Terra;
        }

        public void SetCaptured(List<int> pieces, int advantage)
        {
            while (capIcons.Count < pieces.Count)
            {
                var r = UIKit.Raw(captured, null, Color.white, "cap");
                r.rectTransform.sizeDelta = new Vector2(58, 58);
                capIcons.Add(r);
            }
            for (int i = 0; i < capIcons.Count; i++)
            {
                bool on = i < pieces.Count;
                capIcons[i].gameObject.SetActive(on);
                if (on) capIcons[i].texture = IconRenderer.Get(Pc.Type(pieces[i]), Pc.SideOf(pieces[i]));
            }
            material.text = advantage > 0 ? "+" + advantage : "";
        }
    }

    // ====================================================================== HUD

    public class HudScreen : UIScreen
    {
        PlayerCard top, bottom;
        Text moves, turnLabel;
        Button undoBtn;
        RectTransform resultBtn;

        protected override void Build()
        {
            top = new PlayerCard(Root, "top");
            top.Root.anchorMin = new Vector2(0, 1);
            top.Root.anchorMax = new Vector2(1, 1);
            top.Root.pivot = new Vector2(0.5f, 1);
            top.Root.offsetMin = new Vector2(20, -196);
            top.Root.offsetMax = new Vector2(-20, -20);

            var movesRt = UIKit.Rect(Root, "moves");
            movesRt.anchorMin = new Vector2(0, 1);
            movesRt.anchorMax = new Vector2(1, 1);
            movesRt.pivot = new Vector2(0.5f, 1);
            movesRt.offsetMin = new Vector2(40, -266);
            movesRt.offsetMax = new Vector2(-40, -206);
            movesRt.gameObject.AddComponent<RectMask2D>();
            var mbg = UIKit.Img(movesRt, UIKit.Pill, new Color(0, 0, 0, 0.35f), "bg");
            moves = UIKit.Label(movesRt, "", 32, UIKit.Ivory, TextAnchor.MiddleRight);
            moves.horizontalOverflow = HorizontalWrapMode.Overflow;
            moves.rectTransform.offsetMin = new Vector2(30, 0);
            moves.rectTransform.offsetMax = new Vector2(-30, 0);
            mbg.raycastTarget = false;

            var buttons = UIKit.Rect(Root, "buttons");
            buttons.anchorMin = new Vector2(0, 0);
            buttons.anchorMax = new Vector2(1, 0);
            buttons.pivot = new Vector2(0.5f, 0);
            buttons.offsetMin = new Vector2(20, 20);
            buttons.offsetMax = new Vector2(-20, 128);
            var h = UIKit.HList(buttons.gameObject, 18f);
            h.childForceExpandWidth = true;
            UIKit.Btn(buttons, Loc.T("hud.menu"), () => Game.Match.OpenPause(), BtnStyle.Secondary, -1, 38);
            undoBtn = UIKit.Btn(buttons, Loc.T("hud.undo"), () => Game.Match.Undo(), BtnStyle.Secondary, -1, 38);
            UIKit.Btn(buttons, Loc.T("hud.view"), () => Game.Match.RotateView(), BtnStyle.Secondary, -1, 38);

            bottom = new PlayerCard(Root, "bottom");
            bottom.Root.anchorMin = new Vector2(0, 0);
            bottom.Root.anchorMax = new Vector2(1, 0);
            bottom.Root.pivot = new Vector2(0.5f, 0);
            bottom.Root.offsetMin = new Vector2(20, 146);
            bottom.Root.offsetMax = new Vector2(-20, 322);

            var turnRt = UIKit.Rect(Root, "turn");
            turnRt.anchorMin = new Vector2(0.5f, 0);
            turnRt.anchorMax = new Vector2(0.5f, 0);
            turnRt.pivot = new Vector2(0.5f, 0);
            turnRt.sizeDelta = new Vector2(560, 66);
            turnRt.anchoredPosition = new Vector2(0, 336);
            UIKit.Img(turnRt, UIKit.Pill, new Color(0.02f, 0.05f, 0.14f, 0.8f), "bg");
            turnLabel = UIKit.Label(turnRt, "", 34, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold);

            resultBtn = (RectTransform)UIKit.Btn(Root, Loc.T("over.result"), () => UI.PushOverlay(UI.GameOver), BtnStyle.Primary, -1, 40).transform;
            resultBtn.anchorMin = resultBtn.anchorMax = new Vector2(0.5f, 0);
            resultBtn.pivot = new Vector2(0.5f, 0);
            resultBtn.sizeDelta = new Vector2(520, 110);
            resultBtn.anchoredPosition = new Vector2(0, 420);
            resultBtn.gameObject.SetActive(false);
        }

        public void ShowResultButton(bool on) { resultBtn.gameObject.SetActive(on); }

        public override void OnShow()
        {
            if (Game.Match != null && Game.Match.Game != null) Refresh(Game.Match);
        }

        /// <summary>Полное обновление по состоянию партии.</summary>
        public void Refresh(MatchController m)
        {
            if (m == null || m.Game == null) return;
            var g = m.Game;
            Side bottomSide = m.BottomSide;
            bottom.SetSide(bottomSide, m.Config.NameOf(bottomSide));
            top.SetSide(Pc.Other(bottomSide), m.Config.NameOf(Pc.Other(bottomSide)));
            bool over = g.IsOver;
            bottom.SetActive(!over && g.SideToMove == bottom.Side, "");
            top.SetActive(!over && g.SideToMove == top.Side, "");
            turnLabel.text = over ? Loc.T("over.result") : Loc.T("hud.turn", m.Config.NameOf(g.SideToMove));
            turnLabel.transform.parent.gameObject.SetActive(!over);

            var capW = new List<int>();
            var capB = new List<int>();
            foreach (var r in g.History)
                if (r.CapturedPiece != 0) (r.Mover == Side.White ? capW : capB).Add(r.CapturedPiece);
            Comparison<int> byValue = (a, b) => Pc.Value(Pc.Type(b), g.Variant).CompareTo(Pc.Value(Pc.Type(a), g.Variant));
            capW.Sort(byValue);
            capB.Sort(byValue);
            int bal = g.MaterialBalance();
            (bottom.Side == Side.White ? bottom : top).SetCaptured(capW, bal);
            (bottom.Side == Side.Black ? bottom : top).SetCaptured(capB, -bal);

            var sb = new StringBuilder();
            int startIdx = Mathf.Max(0, g.History.Count - 10);
            if (startIdx % 2 == 1) startIdx--;
            for (int i = startIdx; i < g.History.Count; i++)
            {
                if (i % 2 == 0) sb.Append("<color=#E2B04A>").Append(i / 2 + 1).Append(".</color> ");
                sb.Append(g.History[i].San).Append("  ");
            }
            moves.text = sb.Length > 0 ? sb.ToString() : "—";
            undoBtn.interactable = g.CanUndo && !m.Busy;
            UpdateClocks(m);
        }

        public void UpdateClocks(MatchController m)
        {
            bool show = !m.Config.Time.Unlimited;
            bottom.SetClock(m.ClockOf(bottom.Side), show);
            top.SetClock(m.ClockOf(top.Side), show);
        }

        public override void Tick()
        {
            var m = Game.Match;
            if (m != null && m.Game != null && !m.Config.Time.Unlimited) UpdateClocks(m);
        }

        public override bool OnBack()
        {
            Game.Match.OpenPause();
            return true;
        }
    }

    // ====================================================================== Пауза

    public class PauseScreen : UIScreen
    {
        Button undoBtn;

        protected override void Build()
        {
            UIKit.Dimmer(Root);
            var panel = UIKit.Panel(Root, "panel");
            UIKit.Place(panel, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(860, 1180));
            var title = UIKit.Label(panel, Loc.T("pause.title"), 64, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            title.rectTransform.anchorMin = new Vector2(0, 1);
            title.rectTransform.offsetMin = new Vector2(20, -170);
            title.rectTransform.offsetMax = new Vector2(-20, -62);
            var list = UIKit.Rect(panel, "list");
            UIKit.Stretch(list, 70, 60, 70, 190);
            UIKit.VList(list.gameObject, 18f);
            UIKit.Btn(list, Loc.T("pause.resume"), () => Game.Match.ClosePause(), BtnStyle.Primary, 112, 44);
            undoBtn = UIKit.Btn(list, Loc.T("pause.undo"), () => { Game.Match.ClosePause(); Game.Match.Undo(); }, BtnStyle.Secondary, 106, 40);
            UIKit.Btn(list, Loc.T("pause.draw"), () => Game.Match.OfferDraw(), BtnStyle.Secondary, 106, 40);
            UIKit.Btn(list, Loc.T("pause.resign"), () => Game.Match.Resign(), BtnStyle.Danger, 106, 40);
            UIKit.Btn(list, Loc.T("pause.restart"), () => UI.Ask(Loc.T("confirm.restart"), () => Game.Match.Restart()), BtnStyle.Secondary, 106, 40);
            UIKit.Btn(list, Loc.T("menu.settings"), () =>
            {
                UI.Settings.ReturnTo = UI.Hud;
                UI.Show(UI.Settings);
            }, BtnStyle.Secondary, 106, 40);
            UIKit.Btn(list, Loc.T("pause.menu"), () => UI.Ask(Loc.T("confirm.menu"), () => Game.ExitToMenu()), BtnStyle.Ghost, 100, 38);
        }

        public override void OnShow()
        {
            var m = Game.Match;
            undoBtn.interactable = m != null && m.Game != null && m.Game.CanUndo;
        }

        public override bool OnBack()
        {
            Game.Match.ClosePause();
            return true;
        }
    }

    // ====================================================================== Итог партии

    public class GameOverScreen : UIScreen
    {
        Text title, reason, info, proverb;

        protected override void Build()
        {
            UIKit.Dimmer(Root);
            var panel = UIKit.Panel(Root, "panel");
            UIKit.Place(panel, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(920, 1200));

            var em = UIKit.Emblem(panel, 200);
            UIKit.Place(em, new Vector2(0.5f, 1f), new Vector2(0.5f, 0.5f), new Vector2(0, -170), new Vector2(200, 200));
            em.gameObject.AddComponent<Spin>().Speed = 12f;

            title = UIKit.Label(panel, "", 70, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            UIKit.Place(title.rectTransform, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0, -290), new Vector2(840, 180));
            UIKit.Shadow(title, new Color(0, 0, 0, 0.6f), 4f);
            reason = UIKit.Label(panel, "", 42, UIKit.Ivory, TextAnchor.MiddleCenter, FontStyle.Bold);
            UIKit.Place(reason.rectTransform, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0, -470), new Vector2(840, 70));
            info = UIKit.Label(panel, "", 34, new Color(1, 1, 1, 0.7f), TextAnchor.MiddleCenter);
            UIKit.Place(info.rectTransform, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0, -540), new Vector2(840, 60));
            proverb = UIKit.Label(panel, "", 34, UIKit.Turq, TextAnchor.MiddleCenter, FontStyle.Italic);
            UIKit.Place(proverb.rectTransform, new Vector2(0.5f, 1f), new Vector2(0.5f, 1f), new Vector2(0, -610), new Vector2(800, 130));

            var list = UIKit.Rect(panel, "list");
            UIKit.Place(list, new Vector2(0.5f, 0f), new Vector2(0.5f, 0f), new Vector2(0, 60), new Vector2(720, 380));
            UIKit.VList(list.gameObject, 18f);
            UIKit.Btn(list, Loc.T("over.rematch"), () => Game.Match.Restart(), BtnStyle.Primary, 116, 46);
            UIKit.Btn(list, Loc.T("over.view"), () => { UI.PopOverlay(this); UI.Hud.ShowResultButton(true); }, BtnStyle.Secondary, 106, 40);
            UIKit.Btn(list, Loc.T("pause.menu"), () => Game.ExitToMenu(), BtnStyle.Secondary, 106, 40);
        }

        public void Setup(ChessGame g, MatchConfig cfg)
        {
            if (g.Result == GameResult.Draw) title.text = Loc.T("over.draw");
            else title.text = Loc.T("over.winner", cfg.NameOf(g.Result == GameResult.WhiteWins ? Side.White : Side.Black));
            reason.text = Loc.T("reason." + g.Reason);
            info.text = Loc.T("over.moves", (g.History.Count + 1) / 2);
            proverb.text = Loc.RandomProverb();
        }

        public override bool OnBack()
        {
            UI.PopOverlay(this);
            UI.Hud.ShowResultButton(true);
            return true;
        }
    }

    // ====================================================================== Превращение пешки

    public class PromotionDialog : UIScreen
    {
        Action<PieceType> callback;
        readonly RawImage[] icons = new RawImage[4];
        static readonly PieceType[] Choices = { PieceType.Queen, PieceType.Rook, PieceType.Bishop, PieceType.Knight };

        protected override void Build()
        {
            UIKit.Dimmer(Root);
            var panel = UIKit.Panel(Root, "panel");
            UIKit.Place(panel, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(980, 620));
            var title = UIKit.Label(panel, Loc.T("promo.title"), 52, UIKit.Gold, TextAnchor.MiddleCenter, FontStyle.Bold);
            title.rectTransform.anchorMin = new Vector2(0, 1);
            title.rectTransform.offsetMin = new Vector2(20, -160);
            title.rectTransform.offsetMax = new Vector2(-20, -62);
            var row = UIKit.Rect(panel, "row");
            UIKit.Stretch(row, 50, 50, 50, 180);
            var h = UIKit.HList(row.gameObject, 20f);
            h.childForceExpandWidth = true;
            for (int i = 0; i < 4; i++)
            {
                var type = Choices[i];
                var b = UIKit.Btn(row, "", () => Choose(type), BtnStyle.Secondary, -1);
                var label = UIKit.BtnLabel(b);
                label.text = Loc.T("piece." + type).Split(' ')[0];
                label.fontSize = 32;
                label.alignment = TextAnchor.LowerCenter;
                label.rectTransform.offsetMin = new Vector2(6, 18);
                icons[i] = UIKit.Raw(b.transform, null, Color.white, "icon");
                icons[i].rectTransform.offsetMin = new Vector2(8, 64);
                icons[i].rectTransform.offsetMax = new Vector2(-8, -8);
                icons[i].gameObject.AddComponent<AspectRatioFitter>().aspectMode = AspectRatioFitter.AspectMode.FitInParent;
            }
        }

        public void Setup(Side side, Action<PieceType> cb)
        {
            callback = cb;
            for (int i = 0; i < 4; i++) icons[i].texture = IconRenderer.Get(Choices[i], side);
        }

        void Choose(PieceType t)
        {
            UI.PopOverlay(this);
            var cb = callback;
            callback = null;
            if (cb != null) cb(t);
        }

        public override bool OnBack()
        {
            Choose(PieceType.Queen);
            return true;
        }
    }

    // ====================================================================== Подтверждение

    public class ConfirmDialog : UIScreen
    {
        Text message;
        Text yesLabel, noLabel;
        Action onYes, onNo;

        protected override void Build()
        {
            UIKit.Dimmer(Root);
            var panel = UIKit.Panel(Root, "panel");
            UIKit.Place(panel, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(900, 560));
            message = UIKit.Label(panel, "", 44, UIKit.Ivory, TextAnchor.MiddleCenter);
            UIKit.Stretch(message.rectTransform, 50, 190, 50, 90);
            var row = UIKit.Rect(panel, "row");
            row.anchorMin = new Vector2(0, 0);
            row.anchorMax = new Vector2(1, 0);
            row.pivot = new Vector2(0.5f, 0);
            row.offsetMin = new Vector2(50, 50);
            row.offsetMax = new Vector2(-50, 166);
            var h = UIKit.HList(row.gameObject, 24f);
            h.childForceExpandWidth = true;
            var no = UIKit.Btn(row, Loc.T("common.no"), () => Close(false), BtnStyle.Secondary, -1);
            var yes = UIKit.Btn(row, Loc.T("common.yes"), () => Close(true), BtnStyle.Primary, -1);
            noLabel = UIKit.BtnLabel(no);
            yesLabel = UIKit.BtnLabel(yes);
        }

        public void Setup(string text, Action yes, Action no, string yesText, string noText)
        {
            message.text = text;
            onYes = yes;
            onNo = no;
            yesLabel.text = yesText ?? Loc.T("common.yes");
            noLabel.text = noText ?? Loc.T("common.no");
        }

        void Close(bool yes)
        {
            UI.PopOverlay(this);
            var a = yes ? onYes : onNo;
            onYes = onNo = null;
            if (a != null) a();
        }

        public override bool OnBack()
        {
            Close(false);
            return true;
        }
    }
}
