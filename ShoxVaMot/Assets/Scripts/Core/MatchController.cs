using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Shatranj.Audio;
using Shatranj.Chess;
using Shatranj.Visual;

namespace Shatranj.Core
{
    /// <summary>
    /// Партия «игрок против игрока» на одном устройстве: выбор фигуры, ход, превращение,
    /// поединок, шах/мат, часы, отмена хода, ничья, сдача, автосохранение и статистика.
    /// Архитектура готова к подключению ИИ: ход делается через Commit(Move), откуда бы он ни пришёл.
    /// </summary>
    public class MatchController : MonoBehaviour
    {
        GameRoot root;

        public ChessGame Game { get; private set; }
        public MatchConfig Config { get; private set; }
        public PieceTracker Tracker { get; private set; }
        public bool Busy { get; private set; }
        public bool Active { get; private set; }
        public Side BottomSide { get; private set; }

        float clockW, clockB;
        int selected = -1;
        List<Move> selMoves = new List<Move>();
        int lastTickSecond = -1;
        int heroesThisGame;

        public void Init(GameRoot r)
        {
            root = r;
            Config = new MatchConfig();
        }

        public float ClockOf(Side s) { return s == Side.White ? clockW : clockB; }

        bool Paused { get { return root.UI.HasOverlay || root.UI.Current != root.UI.Hud; } }

        // ------------------------------------------------------------------ Старт / стоп

        public void Begin(MatchConfig cfg, SavedMatch save)
        {
            StopAllCoroutines();
            Fx.ResetTime();
            Fx.ClearDebris();
            Config = cfg;
            Game = new ChessGame(cfg.Variant);
            float start = cfg.Time.Minutes * 60f;
            clockW = clockB = start;
            if (save != null)
            {
                foreach (var u in save.moves)
                    if (!Game.PlayUci(u)) break;
                if (save.clockWhite > 0f) clockW = save.clockWhite;
                if (save.clockBlack > 0f) clockB = save.clockBlack;
            }
            Tracker = PieceTracker.Build(Game);
            Busy = false;
            selected = -1;
            selMoves.Clear();
            heroesThisGame = 0;
            Active = !Game.IsOver;

            root.Board.ClearHighlights();
            root.Board.SpawnAll(Tracker);
            BottomSide = root.Settings.autoRotate ? Game.SideToMove : Side.White;
            root.Rig.MenuOrbit = false;
            root.Rig.SetView(BottomSide, false);

            root.UI.Show(root.UI.Hud);
            root.UI.Hud.ShowResultButton(false);
            RefreshAll();
            AudioManager.Play(Sfx.Open);
            if (Game.IsOver) EndGame();
        }

        public void StopMatch()
        {
            StopAllCoroutines();
            Fx.ResetTime();
            Game = null;
            Active = false;
            Busy = false;
            selected = -1;
            selMoves.Clear();
            if (root.Board != null) root.Board.ClearHighlights();
            if (root.Rig != null) root.Rig.ReleaseFocus();
        }

        // ------------------------------------------------------------------ Часы

        void Update()
        {
            if (Game == null || !Active || Busy || Paused || Config.Time.Unlimited) return;
            float dt = Time.unscaledDeltaTime;
            Side s = Game.SideToMove;
            if (s == Side.White) clockW -= dt; else clockB -= dt;
            float c = ClockOf(s);
            if (c < 10f && c > 0f)
            {
                int sec = Mathf.CeilToInt(c);
                if (sec != lastTickSecond) { lastTickSecond = sec; AudioManager.Play(Sfx.Tick, 0.8f, 0f); }
            }
            if (c <= 0f)
            {
                if (s == Side.White) clockW = 0f; else clockB = 0f;
                Game.Timeout(s);
                root.UI.Banner.Show(Loc.T("hud.flag"), "", UI.UIKit.Terra);
                EndGame();
            }
        }

        // ------------------------------------------------------------------ Ввод

        /// <summary>
        /// Тап по доске. pieceSq — клетка фигуры, в которую попал луч, planeSq — клетка под пальцем
        /// на плоскости доски (важно, когда высокая фигура заслоняет клетку за собой).
        /// </summary>
        public void OnTap(int pieceSq, int planeSq)
        {
            if (Game == null || !Active || Busy || Paused) return;
            if (selected >= 0)
            {
                if (IsDestination(planeSq)) { TryCommit(selected, planeSq); return; }
                if (IsDestination(pieceSq)) { TryCommit(selected, pieceSq); return; }
            }
            OnSquareTapped(pieceSq >= 0 ? pieceSq : planeSq);
        }

        bool IsDestination(int sq)
        {
            if (sq < 0) return false;
            foreach (var m in selMoves) if (m.To == sq) return true;
            return false;
        }

        void OnSquareTapped(int sq)
        {
            int p = sq >= 0 ? Game.Pos.Board[sq] : 0;
            if (selected >= 0 && sq == selected) { Deselect(); return; }
            if (p != 0 && Pc.SideOf(p) == Game.SideToMove) { Select(sq); return; }
            if (selected >= 0) AudioManager.Play(Sfx.Illegal, 0.5f, 0f);
            Deselect();
        }

        void Select(int sq)
        {
            SetSelectedVisual(selected, false);
            selected = sq;
            selMoves = Game.LegalMovesFrom(sq);
            SetSelectedVisual(sq, true);
            AudioManager.Play(Sfx.Tap, 0.8f);
            RefreshHighlights();
        }

        void Deselect()
        {
            SetSelectedVisual(selected, false);
            selected = -1;
            selMoves.Clear();
            RefreshHighlights();
        }

        void SetSelectedVisual(int sq, bool on)
        {
            if (sq < 0 || Tracker == null) return;
            var v = root.Board.ViewAt(Tracker, sq);
            if (v != null) v.SetSelected(on);
        }

        void TryCommit(int from, int to)
        {
            if (Game.IsPromotionMove(from, to))
            {
                if (Config.Variant == Variant.Afrosiyob) Commit(from, to, PieceType.Queen);
                else
                {
                    root.UI.Promotion.Setup(Game.SideToMove, t => Commit(from, to, t));
                    root.UI.PushOverlay(root.UI.Promotion);
                }
            }
            else Commit(from, to, PieceType.None);
        }

        void Commit(int from, int to, PieceType promo)
        {
            Move m;
            if (Game == null || !Game.TryFind(from, to, promo, out m)) { Deselect(); return; }
            Commit(m);
        }

        /// <summary>Сделать ход (от человека — а в будущем и от ИИ).</summary>
        public void Commit(Move m)
        {
            SetSelectedVisual(selected, false);
            selected = -1;
            selMoves.Clear();

            Side mover = Game.SideToMove;
            int moverId = Tracker.IdAt(m.From);
            int victimId = m.IsCapture ? Tracker.IdAt(Position.CapturedSquareOf(m, mover)) : 0;
            int rookId = 0;
            if (m.IsCastle)
            {
                int rf, rt;
                Position.CastleRookSquares(m, out rf, out rt);
                rookId = Tracker.IdAt(rf);
            }

            var rec = Game.Play(m);
            if (rec == null) return;
            Tracker.Apply(rec);
            PieceTracker.Info info;
            int kills = Tracker.TryGet(moverId, out info) ? info.Kills : 0;
            if (!Config.Time.Unlimited)
            {
                if (mover == Side.White) clockW += Config.Time.Increment; else clockB += Config.Time.Increment;
            }
            StartCoroutine(AnimateRoutine(rec, moverId, victimId, rookId, kills));
        }

        IEnumerator AnimateRoutine(MoveRecord rec, int moverId, int victimId, int rookId, int kills)
        {
            Busy = true;
            root.Board.ClearHighlights();
            RefreshHud();
            var style = (BattleStyle)Mathf.Clamp(root.Settings.battleMode, 0, 2);
            yield return root.Board.AnimateMove(rec, moverId, victimId, rookId, kills, style, root.Settings.cinematicCamera);
            AudioManager.Play(Sfx.Place, 0.9f);
            Busy = false;

            if (Game == null) yield break;
            if (Game.IsOver) { EndGame(); yield break; }

            if (rec.GivesCheck)
            {
                root.UI.Banner.Show(Loc.T("hud.check"), "", UI.UIKit.Gold);
                AudioManager.Play(Sfx.Check);
            }
            if (root.Settings.autoRotate)
            {
                BottomSide = Game.SideToMove;
                root.Rig.SetView(BottomSide, false);
            }
            RefreshAll();
            Save();
        }

        public void OnHero(PieceView v)
        {
            heroesThisGame++;
            root.UI.Banner.Show(Loc.T("hud.hero"), Loc.T("hud.hero.desc", Loc.T("piece." + v.Type)), UI.UIKit.Gold);
            AudioManager.Play(Sfx.Hero);
        }

        // ------------------------------------------------------------------ Действия меню

        public void Undo()
        {
            if (Game == null || Busy || !Game.CanUndo) return;
            StopAllCoroutines();
            Fx.ResetTime();
            Fx.ClearDebris();
            root.UI.CloseAllOverlays();
            root.UI.Hud.ShowResultButton(false);
            root.Rig.MenuOrbit = false;
            root.Rig.ReleaseFocus();

            Game.Undo();
            Active = !Game.IsOver;
            Tracker = PieceTracker.Build(Game);
            selected = -1;
            selMoves.Clear();
            root.Board.SyncTo(Tracker, true);
            if (root.Settings.autoRotate)
            {
                BottomSide = Game.SideToMove;
                root.Rig.SetView(BottomSide, false);
            }
            RefreshAll();
            Save();
            AudioManager.Play(Sfx.Open, 0.7f);
        }

        public void OfferDraw()
        {
            if (Game == null || !Active) return;
            Side offer = Game.SideToMove;
            root.UI.Ask(Loc.T("confirm.draw", Config.NameOf(offer), Config.NameOf(Pc.Other(offer))),
                () =>
                {
                    Game.AgreeDraw();
                    root.UI.CloseAllOverlays();
                    EndGame();
                },
                () => root.UI.Banner.Toast(Loc.T("draw.declined")));
        }

        public void Resign()
        {
            if (Game == null || !Active) return;
            Side loser = Game.SideToMove;
            root.UI.Ask(Loc.T("confirm.resign", Config.NameOf(loser)), () =>
            {
                Game.Resign(loser);
                root.UI.CloseAllOverlays();
                EndGame();
            });
        }

        public void Restart()
        {
            var cfg = Config.Clone();
            root.UI.CloseAllOverlays();
            SavedMatch.Clear();
            Begin(cfg, null);
        }

        public void OpenPause()
        {
            if (Game == null) return;
            root.UI.PushOverlay(root.UI.Pause);
        }

        public void ClosePause()
        {
            root.UI.PopOverlay(root.UI.Pause);
        }

        public void RotateView()
        {
            if (Game == null) return;
            BottomSide = Pc.Other(BottomSide);
            root.Rig.SetView(BottomSide, false);
            RefreshHud();
        }

        // ------------------------------------------------------------------ Конец партии

        void EndGame()
        {
            Active = false;
            SetSelectedVisual(selected, false);
            selected = -1;
            selMoves.Clear();
            SavedMatch.Clear();
            UpdateStats();
            RefreshAll();
            StartCoroutine(FinaleRoutine());
        }

        void UpdateStats()
        {
            var st = root.Stats;
            st.played++;
            if (Game.Result == GameResult.WhiteWins) st.whiteWins++;
            else if (Game.Result == GameResult.BlackWins) st.blackWins++;
            else st.draws++;
            if (Game.Variant == Variant.Afrosiyob) st.afrosiyobGames++;
            foreach (var r in Game.History) if (r.IsCapture) st.captures++;
            st.heroes += heroesThisGame;
            if (Game.Reason == EndReason.Checkmate)
            {
                int n = (Game.History.Count + 1) / 2;
                st.fastestMate = st.fastestMate == 0 ? n : Mathf.Min(st.fastestMate, n);
            }
            st.Save();
        }

        IEnumerator FinaleRoutine()
        {
            Busy = true;
            bool mate = Game.Reason == EndReason.Checkmate;
            Side? winner = null;
            if (Game.Result == GameResult.WhiteWins) winner = Side.White;
            else if (Game.Result == GameResult.BlackWins) winner = Side.Black;

            if (mate) { root.UI.Banner.Show(Loc.T("hud.mate"), "", UI.UIKit.Gold); AudioManager.Play(Sfx.Check); }
            int kingId = 0;
            if (winner.HasValue)
            {
                int ks = Game.Pos.KingSquare(Pc.Other(winner.Value));
                kingId = Tracker.IdAt(ks);
            }
            yield return root.Board.PlayFinale(winner, kingId, mate || Game.Reason == EndReason.BareKing || Game.Reason == EndReason.StalemateWin);
            for (float t = 0; t < 0.9f; t += Time.unscaledDeltaTime) yield return null;
            if (winner.HasValue) { AudioManager.Play(Sfx.Victory); if (AudioManager.I != null) AudioManager.I.Duck(0.25f, 3.5f); }
            else AudioManager.Play(Sfx.Draw);
            root.Rig.MenuOrbit = true;
            for (float t = 0; t < 1.4f; t += Time.unscaledDeltaTime) yield return null;
            Busy = false;
            root.UI.GameOver.Setup(Game, Config);
            root.UI.PushOverlay(root.UI.GameOver);
            RefreshHud();
        }

        // ------------------------------------------------------------------ Отрисовка и сохранение

        public void RefreshAll()
        {
            RefreshHighlights();
            RefreshHud();
        }

        public void RefreshHighlights()
        {
            var board = root.Board;
            if (board == null) return;
            board.ClearHighlights();
            if (Game == null) return;
            var last = Game.LastMove;
            if (last != null) board.ShowLastMove(last.Move.From, last.Move.To);
            if (!Game.IsOver && Game.InCheck) board.ShowCheck(Game.Pos.KingSquare(Game.SideToMove));
            if (selected >= 0) board.ShowSelection(selected, selMoves, root.Settings.showLegalMoves);
        }

        void RefreshHud()
        {
            if (root.UI != null && root.UI.Hud != null) root.UI.Hud.Refresh(this);
        }

        public void Save()
        {
            if (Game == null || Game.IsOver || Game.History.Count == 0) return;
            new SavedMatch
            {
                config = Config,
                moves = Game.UciHistory(),
                clockWhite = clockW,
                clockBlack = clockB
            }.Store();
        }
    }
}
