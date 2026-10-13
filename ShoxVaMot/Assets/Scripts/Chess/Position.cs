using System;
using System.Collections.Generic;
using System.Text;

namespace Shatranj.Chess
{
    /// <summary>
    /// Позиция на доске: расстановка, очередь хода, права рокировки, взятие на проходе.
    /// Поля a1..h8 = 0..63. Генерация ходов учитывает вариант (Классика / Афросиёб).
    /// </summary>
    public sealed class Position
    {
        public const string StartFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

        public const int WK = 1, WQ = 2, BK = 4, BQ = 8;

        public readonly int[] Board = new int[64];
        public Side SideToMove;
        public int Castling;
        public int EpSquare = -1;
        public int HalfmoveClock;
        public int FullmoveNumber = 1;
        public Variant Variant;

        readonly int[] kingSq = { -1, -1 };

        static readonly int[] CastleMask = BuildCastleMask();
        static readonly int[] KnightDF = { 1, 2, 2, 1, -1, -2, -2, -1 };
        static readonly int[] KnightDR = { 2, 1, -1, -2, -2, -1, 1, 2 };
        static readonly int[] KingDF = { 1, 1, 0, -1, -1, -1, 0, 1 };
        static readonly int[] KingDR = { 0, 1, 1, 1, 0, -1, -1, -1 };
        static readonly int[] DiagDF = { 1, 1, -1, -1 };
        static readonly int[] DiagDR = { 1, -1, 1, -1 };
        static readonly int[] OrthDF = { 1, -1, 0, 0 };
        static readonly int[] OrthDR = { 0, 0, 1, -1 };

        static int[] BuildCastleMask()
        {
            var m = new int[64];
            for (int i = 0; i < 64; i++) m[i] = 15;
            m[0] &= ~WQ; m[7] &= ~WK; m[4] &= ~(WK | WQ);
            m[56] &= ~BQ; m[63] &= ~BK; m[60] &= ~(BK | BQ);
            return m;
        }

        public Position(Variant variant = Variant.Classic, string fen = null)
        {
            Variant = variant;
            LoadFen(fen ?? StartFen);
        }

        public Position Clone()
        {
            var p = new Position(Variant, ToFen());
            return p;
        }

        public int KingSquare(Side s) { return kingSq[(int)s]; }

        // ------------------------------------------------------------------ FEN

        public void LoadFen(string fen)
        {
            Array.Clear(Board, 0, 64);
            string[] parts = fen.Trim().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            int rank = 7, file = 0;
            foreach (char c in parts[0])
            {
                if (c == '/') { rank--; file = 0; }
                else if (char.IsDigit(c)) file += c - '0';
                else
                {
                    if (Sq.OnBoard(file, rank)) Board[Sq.Make(file, rank)] = Pc.FromFenChar(c);
                    file++;
                }
            }
            SideToMove = parts.Length > 1 && parts[1] == "b" ? Side.Black : Side.White;
            Castling = 0;
            if (parts.Length > 2 && Variant == Variant.Classic)
            {
                if (parts[2].Contains("K")) Castling |= WK;
                if (parts[2].Contains("Q")) Castling |= WQ;
                if (parts[2].Contains("k")) Castling |= BK;
                if (parts[2].Contains("q")) Castling |= BQ;
            }
            EpSquare = parts.Length > 3 && Variant == Variant.Classic ? Sq.Parse(parts[3]) : -1;
            HalfmoveClock = parts.Length > 4 ? ParseInt(parts[4], 0) : 0;
            FullmoveNumber = parts.Length > 5 ? ParseInt(parts[5], 1) : 1;
            RefreshKings();
        }

        static int ParseInt(string s, int def)
        {
            int v;
            return int.TryParse(s, out v) ? v : def;
        }

        void RefreshKings()
        {
            kingSq[0] = kingSq[1] = -1;
            for (int i = 0; i < 64; i++)
                if (Pc.Type(Board[i]) == PieceType.King) kingSq[(int)Pc.SideOf(Board[i])] = i;
        }

        public string ToFen()
        {
            var sb = new StringBuilder();
            sb.Append(PlacementKey()).Append(' ');
            sb.Append(SideToMove == Side.White ? 'w' : 'b').Append(' ');
            sb.Append(CastlingString()).Append(' ');
            sb.Append(Sq.Name(EpSquare)).Append(' ');
            sb.Append(HalfmoveClock).Append(' ').Append(FullmoveNumber);
            return sb.ToString();
        }

        string PlacementKey()
        {
            var sb = new StringBuilder(80);
            for (int r = 7; r >= 0; r--)
            {
                int empty = 0;
                for (int f = 0; f < 8; f++)
                {
                    int p = Board[Sq.Make(f, r)];
                    if (p == 0) { empty++; continue; }
                    if (empty > 0) { sb.Append(empty); empty = 0; }
                    sb.Append(Pc.FenChar(p));
                }
                if (empty > 0) sb.Append(empty);
                if (r > 0) sb.Append('/');
            }
            return sb.ToString();
        }

        string CastlingString()
        {
            if (Castling == 0) return "-";
            var sb = new StringBuilder();
            if ((Castling & WK) != 0) sb.Append('K');
            if ((Castling & WQ) != 0) sb.Append('Q');
            if ((Castling & BK) != 0) sb.Append('k');
            if ((Castling & BQ) != 0) sb.Append('q');
            return sb.ToString();
        }

        /// <summary>Ключ позиции для правила троекратного повторения.</summary>
        public string RepetitionKey()
        {
            int ep = -1;
            if (EpSquare >= 0)
            {
                // Поле взятия на проходе учитывается, только если взятие реально возможно.
                var tmp = new List<Move>(48);
                GenerateLegal(tmp);
                foreach (var m in tmp) if (m.IsEnPassant) { ep = EpSquare; break; }
            }
            return PlacementKey() + (SideToMove == Side.White ? " w " : " b ") + CastlingString() + " " + Sq.Name(ep);
        }

        // ------------------------------------------------------------------ Атаки

        public bool InCheck(Side s)
        {
            int k = kingSq[(int)s];
            return k >= 0 && IsAttacked(k, Pc.Other(s));
        }

        public bool IsAttacked(int sq, Side by)
        {
            int f = Sq.File(sq), r = Sq.Rank(sq);

            // Пешки
            int dir = by == Side.White ? 1 : -1;
            int pawn = Pc.Make(by, PieceType.Pawn);
            for (int df = -1; df <= 1; df += 2)
            {
                int ff = f + df, rr = r - dir;
                if (Sq.OnBoard(ff, rr) && Board[Sq.Make(ff, rr)] == pawn) return true;
            }

            // Кони
            int knight = Pc.Make(by, PieceType.Knight);
            for (int i = 0; i < 8; i++)
            {
                int ff = f + KnightDF[i], rr = r + KnightDR[i];
                if (Sq.OnBoard(ff, rr) && Board[Sq.Make(ff, rr)] == knight) return true;
            }

            // Король
            int king = Pc.Make(by, PieceType.King);
            for (int i = 0; i < 8; i++)
            {
                int ff = f + KingDF[i], rr = r + KingDR[i];
                if (Sq.OnBoard(ff, rr) && Board[Sq.Make(ff, rr)] == king) return true;
            }

            int rook = Pc.Make(by, PieceType.Rook);
            int queen = Pc.Make(by, PieceType.Queen);
            int bishop = Pc.Make(by, PieceType.Bishop);

            // Ладьи (и ферзь в классике) — по вертикалям и горизонталям
            for (int d = 0; d < 4; d++)
            {
                int ff = f + OrthDF[d], rr = r + OrthDR[d];
                while (Sq.OnBoard(ff, rr))
                {
                    int p = Board[Sq.Make(ff, rr)];
                    if (p != 0)
                    {
                        if (p == rook || (Variant == Variant.Classic && p == queen)) return true;
                        break;
                    }
                    ff += OrthDF[d]; rr += OrthDR[d];
                }
            }

            if (Variant == Variant.Classic)
            {
                for (int d = 0; d < 4; d++)
                {
                    int ff = f + DiagDF[d], rr = r + DiagDR[d];
                    while (Sq.OnBoard(ff, rr))
                    {
                        int p = Board[Sq.Make(ff, rr)];
                        if (p != 0)
                        {
                            if (p == bishop || p == queen) return true;
                            break;
                        }
                        ff += DiagDF[d]; rr += DiagDR[d];
                    }
                }
            }
            else
            {
                // Фарзин: на одно поле по диагонали. Фил: прыжок ровно на два поля по диагонали.
                for (int d = 0; d < 4; d++)
                {
                    int ff = f + DiagDF[d], rr = r + DiagDR[d];
                    if (Sq.OnBoard(ff, rr) && Board[Sq.Make(ff, rr)] == queen) return true;
                    ff = f + 2 * DiagDF[d]; rr = r + 2 * DiagDR[d];
                    if (Sq.OnBoard(ff, rr) && Board[Sq.Make(ff, rr)] == bishop) return true;
                }
            }
            return false;
        }

        // ------------------------------------------------------------------ Генерация ходов

        public void GenerateLegal(List<Move> result)
        {
            result.Clear();
            var pseudo = new List<Move>(64);
            GeneratePseudo(pseudo);
            Side us = SideToMove;
            foreach (var m in pseudo)
            {
                var u = Make(m);
                if (!InCheck(us)) result.Add(m);
                Unmake(m, u);
            }
        }

        public List<Move> LegalMoves()
        {
            var l = new List<Move>(48);
            GenerateLegal(l);
            return l;
        }

        public void GeneratePseudo(List<Move> list)
        {
            Side us = SideToMove;
            for (int sq = 0; sq < 64; sq++)
            {
                int p = Board[sq];
                if (p == 0 || Pc.SideOf(p) != us) continue;
                switch (Pc.Type(p))
                {
                    case PieceType.Pawn: GenPawn(sq, us, list); break;
                    case PieceType.Knight: GenSteps(sq, us, KnightDF, KnightDR, 8, 1, list); break;
                    case PieceType.King:
                        GenSteps(sq, us, KingDF, KingDR, 8, 1, list);
                        if (Variant == Variant.Classic) GenCastles(sq, us, list);
                        break;
                    case PieceType.Rook: GenSlides(sq, us, OrthDF, OrthDR, list); break;
                    case PieceType.Bishop:
                        if (Variant == Variant.Classic) GenSlides(sq, us, DiagDF, DiagDR, list);
                        else GenSteps(sq, us, DiagDF, DiagDR, 4, 2, list);
                        break;
                    case PieceType.Queen:
                        if (Variant == Variant.Classic)
                        {
                            GenSlides(sq, us, OrthDF, OrthDR, list);
                            GenSlides(sq, us, DiagDF, DiagDR, list);
                        }
                        else GenSteps(sq, us, DiagDF, DiagDR, 4, 1, list);
                        break;
                }
            }
        }

        void GenSteps(int sq, Side us, int[] dfs, int[] drs, int n, int mul, List<Move> list)
        {
            int f = Sq.File(sq), r = Sq.Rank(sq);
            for (int i = 0; i < n; i++)
            {
                int ff = f + dfs[i] * mul, rr = r + drs[i] * mul;
                if (!Sq.OnBoard(ff, rr)) continue;
                int to = Sq.Make(ff, rr);
                int t = Board[to];
                if (t == 0) list.Add(new Move(sq, to));
                else if (Pc.SideOf(t) != us) list.Add(new Move(sq, to, MoveFlags.Capture));
            }
        }

        void GenSlides(int sq, Side us, int[] dfs, int[] drs, List<Move> list)
        {
            int f = Sq.File(sq), r = Sq.Rank(sq);
            for (int d = 0; d < 4; d++)
            {
                int ff = f + dfs[d], rr = r + drs[d];
                while (Sq.OnBoard(ff, rr))
                {
                    int to = Sq.Make(ff, rr);
                    int t = Board[to];
                    if (t == 0) list.Add(new Move(sq, to));
                    else
                    {
                        if (Pc.SideOf(t) != us) list.Add(new Move(sq, to, MoveFlags.Capture));
                        break;
                    }
                    ff += dfs[d]; rr += drs[d];
                }
            }
        }

        void AddPawnMove(int from, int to, MoveFlags flags, List<Move> list)
        {
            int rank = Sq.Rank(to);
            if (rank == 7 || rank == 0)
            {
                list.Add(new Move(from, to, flags, PieceType.Queen));
                if (Variant == Variant.Classic)
                {
                    list.Add(new Move(from, to, flags, PieceType.Rook));
                    list.Add(new Move(from, to, flags, PieceType.Bishop));
                    list.Add(new Move(from, to, flags, PieceType.Knight));
                }
            }
            else list.Add(new Move(from, to, flags));
        }

        void GenPawn(int sq, Side us, List<Move> list)
        {
            int f = Sq.File(sq), r = Sq.Rank(sq);
            int dir = us == Side.White ? 1 : -1;
            int startRank = us == Side.White ? 1 : 6;
            int r1 = r + dir;
            if (!Sq.OnBoard(f, r1)) return;

            int one = Sq.Make(f, r1);
            if (Board[one] == 0)
            {
                AddPawnMove(sq, one, MoveFlags.None, list);
                if (Variant == Variant.Classic && r == startRank)
                {
                    int two = Sq.Make(f, r + 2 * dir);
                    if (Board[two] == 0) list.Add(new Move(sq, two, MoveFlags.DoublePush));
                }
            }
            for (int df = -1; df <= 1; df += 2)
            {
                int ff = f + df;
                if (!Sq.OnBoard(ff, r1)) continue;
                int to = Sq.Make(ff, r1);
                int t = Board[to];
                if (t != 0 && Pc.SideOf(t) != us) AddPawnMove(sq, to, MoveFlags.Capture, list);
                else if (t == 0 && to == EpSquare && Variant == Variant.Classic)
                    list.Add(new Move(sq, to, MoveFlags.Capture | MoveFlags.EnPassant));
            }
        }

        void GenCastles(int sq, Side us, List<Move> list)
        {
            Side them = Pc.Other(us);
            int rook = Pc.Make(us, PieceType.Rook);
            if (us == Side.White && sq == 4)
            {
                if ((Castling & WK) != 0 && Board[5] == 0 && Board[6] == 0 && Board[7] == rook &&
                    !IsAttacked(4, them) && !IsAttacked(5, them) && !IsAttacked(6, them))
                    list.Add(new Move(4, 6, MoveFlags.CastleKing));
                if ((Castling & WQ) != 0 && Board[3] == 0 && Board[2] == 0 && Board[1] == 0 && Board[0] == rook &&
                    !IsAttacked(4, them) && !IsAttacked(3, them) && !IsAttacked(2, them))
                    list.Add(new Move(4, 2, MoveFlags.CastleQueen));
            }
            else if (us == Side.Black && sq == 60)
            {
                if ((Castling & BK) != 0 && Board[61] == 0 && Board[62] == 0 && Board[63] == rook &&
                    !IsAttacked(60, them) && !IsAttacked(61, them) && !IsAttacked(62, them))
                    list.Add(new Move(60, 62, MoveFlags.CastleKing));
                if ((Castling & BQ) != 0 && Board[59] == 0 && Board[58] == 0 && Board[57] == 0 && Board[56] == rook &&
                    !IsAttacked(60, them) && !IsAttacked(59, them) && !IsAttacked(58, them))
                    list.Add(new Move(60, 58, MoveFlags.CastleQueen));
            }
        }

        // ------------------------------------------------------------------ Сделать / отменить

        public static int CapturedSquareOf(Move m, Side mover)
        {
            if (m.IsEnPassant) return m.To + (mover == Side.White ? -8 : 8);
            return m.To;
        }

        public static void CastleRookSquares(Move m, out int rookFrom, out int rookTo)
        {
            if ((m.Flags & MoveFlags.CastleKing) != 0) { rookFrom = m.To + 1; rookTo = m.To - 1; }
            else if ((m.Flags & MoveFlags.CastleQueen) != 0) { rookFrom = m.To - 2; rookTo = m.To + 1; }
            else { rookFrom = rookTo = -1; }
        }

        public UndoInfo Make(Move m)
        {
            Side us = SideToMove;
            int piece = Board[m.From];
            var u = new UndoInfo
            {
                Castling = Castling, EpSquare = EpSquare, Halfmove = HalfmoveClock,
                Captured = 0, CapturedSquare = -1, Moved = piece
            };

            int capSq = CapturedSquareOf(m, us);
            int captured = Board[capSq];
            if (captured != 0 && capSq != m.From)
            {
                u.Captured = captured;
                u.CapturedSquare = capSq;
                Board[capSq] = 0;
            }

            Board[m.From] = 0;
            Board[m.To] = m.Promotion != PieceType.None ? Pc.Make(us, m.Promotion) : piece;

            if (m.IsCastle)
            {
                int rf, rt;
                CastleRookSquares(m, out rf, out rt);
                Board[rt] = Board[rf];
                Board[rf] = 0;
            }

            if (Pc.Type(piece) == PieceType.King) kingSq[(int)us] = m.To;

            Castling &= CastleMask[m.From] & CastleMask[m.To];
            EpSquare = (m.Flags & MoveFlags.DoublePush) != 0 ? (m.From + m.To) / 2 : -1;
            HalfmoveClock = (Pc.Type(piece) == PieceType.Pawn || u.Captured != 0) ? 0 : HalfmoveClock + 1;
            if (us == Side.Black) FullmoveNumber++;
            SideToMove = Pc.Other(us);
            return u;
        }

        public void Unmake(Move m, UndoInfo u)
        {
            SideToMove = Pc.Other(SideToMove);
            Side us = SideToMove;
            if (us == Side.Black) FullmoveNumber--;

            Board[m.From] = u.Moved;
            Board[m.To] = 0;
            if (u.Captured != 0) Board[u.CapturedSquare] = u.Captured;

            if (m.IsCastle)
            {
                int rf, rt;
                CastleRookSquares(m, out rf, out rt);
                Board[rf] = Board[rt];
                Board[rt] = 0;
            }

            if (Pc.Type(u.Moved) == PieceType.King) kingSq[(int)us] = m.From;

            Castling = u.Castling;
            EpSquare = u.EpSquare;
            HalfmoveClock = u.Halfmove;
        }

        // ------------------------------------------------------------------ Материал

        public int CountPieces(Side s, bool includeKing)
        {
            int n = 0;
            for (int i = 0; i < 64; i++)
            {
                int p = Board[i];
                if (p == 0 || Pc.SideOf(p) != s) continue;
                if (!includeKing && Pc.Type(p) == PieceType.King) continue;
                n++;
            }
            return n;
        }

        public bool InsufficientMaterial()
        {
            int minorsW = 0, minorsB = 0, bishopsLight = 0, bishopsDark = 0, knights = 0;
            for (int i = 0; i < 64; i++)
            {
                int p = Board[i];
                if (p == 0) continue;
                var t = Pc.Type(p);
                switch (t)
                {
                    case PieceType.King: continue;
                    case PieceType.Pawn:
                    case PieceType.Rook:
                    case PieceType.Queen:
                        return false;
                    case PieceType.Knight:
                        knights++;
                        break;
                    case PieceType.Bishop:
                        if (Sq.IsLight(i)) bishopsLight++; else bishopsDark++;
                        break;
                }
                if (Pc.SideOf(p) == Side.White) minorsW++; else minorsB++;
            }
            int minors = minorsW + minorsB;
            if (minors == 0) return true;
            if (Variant == Variant.Afrosiyob) return false; // там действует правило «голого короля»
            if (minors == 1) return true;
            if (knights == 0 && (bishopsLight == 0 || bishopsDark == 0)) return true;
            return false;
        }

        public Move ParseUci(string uci)
        {
            if (string.IsNullOrEmpty(uci) || uci.Length < 4) return default(Move);
            int from = Sq.Parse(uci.Substring(0, 2));
            int to = Sq.Parse(uci.Substring(2, 2));
            PieceType promo = PieceType.None;
            if (uci.Length > 4)
            {
                switch (char.ToLowerInvariant(uci[4]))
                {
                    case 'q': promo = PieceType.Queen; break;
                    case 'r': promo = PieceType.Rook; break;
                    case 'b': promo = PieceType.Bishop; break;
                    case 'n': promo = PieceType.Knight; break;
                }
            }
            foreach (var m in LegalMoves())
                if (m.From == from && m.To == to && m.Promotion == promo) return m;
            return default(Move);
        }

        // ------------------------------------------------------------------ Perft (для тестов)

        public long Perft(int depth)
        {
            if (depth == 0) return 1;
            var moves = LegalMoves();
            if (depth == 1) return moves.Count;
            long n = 0;
            foreach (var m in moves)
            {
                var u = Make(m);
                n += Perft(depth - 1);
                Unmake(m, u);
            }
            return n;
        }
    }
}
