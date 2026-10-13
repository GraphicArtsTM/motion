using System.Collections.Generic;
using System.Text;

namespace Shatranj.Chess
{
    /// <summary>Сыгранный ход со всей информацией, нужной для анимации, нотации и отмены.</summary>
    public sealed class MoveRecord
    {
        public Move Move;
        public Side Mover;
        public string San;
        public int MovedPiece;
        public int CapturedPiece;
        public int CapturedSquare = -1;
        public bool GivesCheck;
        public bool IsMate;
        public UndoInfo Undo;
        public int RookFrom = -1, RookTo = -1;

        public bool IsCapture { get { return CapturedPiece != 0; } }
    }

    /// <summary>
    /// Партия: история ходов, нотация, правила окончания (мат, пат, повторение, 50 ходов,
    /// недостаточный материал, «голый король» в режиме Афросиёб).
    /// </summary>
    public sealed class ChessGame
    {
        public readonly Position Pos;
        public readonly Variant Variant;
        public readonly string StartFen;
        public readonly List<MoveRecord> History = new List<MoveRecord>();

        public GameResult Result { get; private set; }
        public EndReason Reason { get; private set; }
        public bool IsOver { get { return Result != GameResult.Ongoing; } }
        public Side SideToMove { get { return Pos.SideToMove; } }

        readonly List<string> keys = new List<string>();
        List<Move> legalCache;

        public ChessGame(Variant variant, string fen = null)
        {
            Variant = variant;
            StartFen = fen ?? Position.StartFen;
            Pos = new Position(variant, StartFen);
            keys.Add(Pos.RepetitionKey());
            Evaluate();
        }

        public List<Move> LegalMoves()
        {
            if (legalCache == null) legalCache = Pos.LegalMoves();
            return legalCache;
        }

        public List<Move> LegalMovesFrom(int sq)
        {
            var res = new List<Move>();
            foreach (var m in LegalMoves()) if (m.From == sq) res.Add(m);
            return res;
        }

        public bool InCheck { get { return Pos.InCheck(Pos.SideToMove); } }

        public MoveRecord LastMove { get { return History.Count > 0 ? History[History.Count - 1] : null; } }

        public bool TryFind(int from, int to, PieceType promo, out Move move)
        {
            foreach (var m in LegalMoves())
            {
                if (m.From == from && m.To == to && (m.Promotion == promo || (promo == PieceType.None && !m.IsPromotion)))
                {
                    move = m;
                    return true;
                }
            }
            move = default(Move);
            return false;
        }

        public bool IsPromotionMove(int from, int to)
        {
            foreach (var m in LegalMoves())
                if (m.From == from && m.To == to && m.IsPromotion) return true;
            return false;
        }

        public MoveRecord Play(Move m)
        {
            if (IsOver) return null;
            Side mover = Pos.SideToMove;
            var rec = new MoveRecord
            {
                Move = m,
                Mover = mover,
                MovedPiece = Pos.Board[m.From],
                San = SanBeforeMove(m)
            };
            int cs = Position.CapturedSquareOf(m, mover);
            if (Pos.Board[cs] != 0 && cs != m.From)
            {
                rec.CapturedPiece = Pos.Board[cs];
                rec.CapturedSquare = cs;
            }
            if (m.IsCastle) Position.CastleRookSquares(m, out rec.RookFrom, out rec.RookTo);

            rec.Undo = Pos.Make(m);
            legalCache = null;

            rec.GivesCheck = Pos.InCheck(Pos.SideToMove);
            if (rec.GivesCheck)
            {
                rec.IsMate = LegalMoves().Count == 0;
                rec.San += rec.IsMate ? "#" : "+";
            }

            History.Add(rec);
            keys.Add(Pos.RepetitionKey());
            Evaluate();
            return rec;
        }

        public bool PlayUci(string uci)
        {
            var m = Pos.ParseUci(uci);
            if (!m.IsValid) return false;
            return Play(m) != null;
        }

        public bool CanUndo { get { return History.Count > 0; } }

        public MoveRecord Undo()
        {
            if (History.Count == 0) return null;
            var rec = History[History.Count - 1];
            History.RemoveAt(History.Count - 1);
            keys.RemoveAt(keys.Count - 1);
            Pos.Unmake(rec.Move, rec.Undo);
            legalCache = null;
            Result = GameResult.Ongoing;
            Reason = EndReason.None;
            Evaluate();
            return rec;
        }

        public void Resign(Side loser) { Finish(loser == Side.White ? GameResult.BlackWins : GameResult.WhiteWins, EndReason.Resignation); }
        public void Timeout(Side loser) { Finish(loser == Side.White ? GameResult.BlackWins : GameResult.WhiteWins, EndReason.Timeout); }
        public void AgreeDraw() { Finish(GameResult.Draw, EndReason.Agreement); }

        void Finish(GameResult r, EndReason why)
        {
            if (IsOver) return;
            Result = r;
            Reason = why;
        }

        static GameResult WinFor(Side s) { return s == Side.White ? GameResult.WhiteWins : GameResult.BlackWins; }

        void Evaluate()
        {
            Side toMove = Pos.SideToMove;
            Side mover = Pc.Other(toMove);
            var legal = LegalMoves();

            if (legal.Count == 0)
            {
                if (Pos.InCheck(toMove)) Finish(WinFor(mover), EndReason.Checkmate);
                else if (Variant == Variant.Afrosiyob) Finish(WinFor(mover), EndReason.StalemateWin);
                else Finish(GameResult.Draw, EndReason.Stalemate);
                return;
            }

            if (Variant == Variant.Afrosiyob && History.Count > 0)
            {
                // «Голый король»: у соперника остался один король, а у нас ещё есть фигуры.
                int oppPieces = Pos.CountPieces(toMove, false);
                int ourPieces = Pos.CountPieces(mover, false);
                if (oppPieces == 0 && ourPieces > 0)
                {
                    bool canBareBack = false;
                    if (ourPieces == 1)
                        foreach (var m in legal) if (m.IsCapture) { canBareBack = true; break; }
                    if (!canBareBack)
                    {
                        Finish(WinFor(mover), EndReason.BareKing);
                        return;
                    }
                }
            }

            if (Pos.HalfmoveClock >= 100) { Finish(GameResult.Draw, EndReason.FiftyMove); return; }

            if (keys.Count > 0)
            {
                string cur = keys[keys.Count - 1];
                int rep = 0;
                foreach (var k in keys) if (k == cur) rep++;
                if (rep >= 3) { Finish(GameResult.Draw, EndReason.Repetition); return; }
            }

            if (Pos.InsufficientMaterial()) Finish(GameResult.Draw, EndReason.InsufficientMaterial);
        }

        // ------------------------------------------------------------------ Нотация

        string SanBeforeMove(Move m)
        {
            if ((m.Flags & MoveFlags.CastleKing) != 0) return "O-O";
            if ((m.Flags & MoveFlags.CastleQueen) != 0) return "O-O-O";

            int piece = Pos.Board[m.From];
            var type = Pc.Type(piece);
            bool capture = m.IsCapture;
            var sb = new StringBuilder(8);

            if (type == PieceType.Pawn)
            {
                if (capture) sb.Append((char)('a' + Sq.File(m.From))).Append('x');
                sb.Append(Sq.Name(m.To));
                if (m.IsPromotion) sb.Append('=').Append(Pc.SanLetter(m.Promotion));
                return sb.ToString();
            }

            sb.Append(Pc.SanLetter(type));
            bool ambiguous = false, sameFile = false, sameRank = false;
            foreach (var o in LegalMoves())
            {
                if (o.To != m.To || o.From == m.From) continue;
                if (Pos.Board[o.From] != piece) continue;
                ambiguous = true;
                if (Sq.File(o.From) == Sq.File(m.From)) sameFile = true;
                if (Sq.Rank(o.From) == Sq.Rank(m.From)) sameRank = true;
            }
            if (ambiguous)
            {
                if (!sameFile) sb.Append((char)('a' + Sq.File(m.From)));
                else if (!sameRank) sb.Append((char)('1' + Sq.Rank(m.From)));
                else sb.Append(Sq.Name(m.From));
            }
            if (capture) sb.Append('x');
            sb.Append(Sq.Name(m.To));
            return sb.ToString();
        }

        public List<string> UciHistory()
        {
            var l = new List<string>(History.Count);
            foreach (var r in History) l.Add(r.Move.Uci);
            return l;
        }

        /// <summary>Материальный перевес белых (положительный — у белых больше).</summary>
        public int MaterialBalance()
        {
            int sum = 0;
            for (int i = 0; i < 64; i++)
            {
                int p = Pos.Board[i];
                if (p == 0) continue;
                int v = Pc.Value(Pc.Type(p), Variant);
                sum += Pc.SideOf(p) == Side.White ? v : -v;
            }
            return sum;
        }
    }
}
