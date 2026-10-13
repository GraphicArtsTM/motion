using System;

namespace Shatranj.Chess
{
    /// <summary>Тип фигуры. В режиме «Афросиёб» Queen = Фарзин (ферзь старого образца), Bishop = Фил (альфил).</summary>
    public enum PieceType : byte { None = 0, Pawn = 1, Knight = 2, Bishop = 3, Rook = 4, Queen = 5, King = 6 }

    public enum Side : byte { White = 0, Black = 1 }

    /// <summary>Классические шахматы или древний шатрандж (по находкам Афросиаба, Самарканд, VII–VIII вв.).</summary>
    public enum Variant : byte { Classic = 0, Afrosiyob = 1 }

    public enum GameResult : byte { Ongoing, WhiteWins, BlackWins, Draw }

    public enum EndReason : byte
    {
        None, Checkmate, Stalemate, StalemateWin, BareKing, Resignation, Timeout,
        Agreement, FiftyMove, Repetition, InsufficientMaterial
    }

    [Flags]
    public enum MoveFlags : byte
    {
        None = 0, Capture = 1, EnPassant = 2, DoublePush = 4, CastleKing = 8, CastleQueen = 16, Promotion = 32
    }

    public static class Pc
    {
        public const int Empty = 0;
        public static int Make(Side s, PieceType t) { return (int)t | ((int)s << 3); }
        public static PieceType Type(int p) { return (PieceType)(p & 7); }
        public static Side SideOf(int p) { return (Side)((p >> 3) & 1); }
        public static Side Other(Side s) { return s == Side.White ? Side.Black : Side.White; }

        public static char FenChar(int p)
        {
            char c;
            switch (Type(p))
            {
                case PieceType.Pawn: c = 'p'; break;
                case PieceType.Knight: c = 'n'; break;
                case PieceType.Bishop: c = 'b'; break;
                case PieceType.Rook: c = 'r'; break;
                case PieceType.Queen: c = 'q'; break;
                case PieceType.King: c = 'k'; break;
                default: return '.';
            }
            return SideOf(p) == Side.White ? char.ToUpperInvariant(c) : c;
        }

        public static int FromFenChar(char c)
        {
            Side s = char.IsUpper(c) ? Side.White : Side.Black;
            switch (char.ToLowerInvariant(c))
            {
                case 'p': return Make(s, PieceType.Pawn);
                case 'n': return Make(s, PieceType.Knight);
                case 'b': return Make(s, PieceType.Bishop);
                case 'r': return Make(s, PieceType.Rook);
                case 'q': return Make(s, PieceType.Queen);
                case 'k': return Make(s, PieceType.King);
            }
            return Empty;
        }

        public static char SanLetter(PieceType t)
        {
            switch (t)
            {
                case PieceType.Knight: return 'N';
                case PieceType.Bishop: return 'B';
                case PieceType.Rook: return 'R';
                case PieceType.Queen: return 'Q';
                case PieceType.King: return 'K';
            }
            return ' ';
        }

        /// <summary>Классическая ценность фигуры (для подсчёта материального перевеса).</summary>
        public static int Value(PieceType t, Variant v)
        {
            switch (t)
            {
                case PieceType.Pawn: return 1;
                case PieceType.Knight: return 3;
                case PieceType.Bishop: return v == Variant.Afrosiyob ? 1 : 3;
                case PieceType.Rook: return 5;
                case PieceType.Queen: return v == Variant.Afrosiyob ? 2 : 9;
            }
            return 0;
        }
    }

    public static class Sq
    {
        public static int File(int s) { return s & 7; }
        public static int Rank(int s) { return s >> 3; }
        public static int Make(int file, int rank) { return rank * 8 + file; }
        public static bool OnBoard(int file, int rank) { return file >= 0 && file < 8 && rank >= 0 && rank < 8; }
        public static string Name(int s) { return s < 0 ? "-" : ((char)('a' + File(s))).ToString() + (char)('1' + Rank(s)); }
        public static bool IsLight(int s) { return ((File(s) + Rank(s)) & 1) == 1; }

        public static int Parse(string n)
        {
            if (string.IsNullOrEmpty(n) || n.Length < 2) return -1;
            int f = n[0] - 'a', r = n[1] - '1';
            return OnBoard(f, r) ? Make(f, r) : -1;
        }
    }

    public struct Move : IEquatable<Move>
    {
        public int From;
        public int To;
        public PieceType Promotion;
        public MoveFlags Flags;

        public Move(int from, int to, MoveFlags flags = MoveFlags.None, PieceType promotion = PieceType.None)
        {
            From = from; To = to; Flags = flags; Promotion = promotion;
            if (promotion != PieceType.None) Flags |= MoveFlags.Promotion;
        }

        public bool IsCapture { get { return (Flags & MoveFlags.Capture) != 0; } }
        public bool IsEnPassant { get { return (Flags & MoveFlags.EnPassant) != 0; } }
        public bool IsCastle { get { return (Flags & (MoveFlags.CastleKing | MoveFlags.CastleQueen)) != 0; } }
        public bool IsPromotion { get { return Promotion != PieceType.None; } }
        public bool IsValid { get { return From != To; } }

        public string Uci
        {
            get
            {
                string s = Sq.Name(From) + Sq.Name(To);
                if (Promotion != PieceType.None) s += char.ToLowerInvariant(Pc.SanLetter(Promotion));
                return s;
            }
        }

        public bool Equals(Move o) { return From == o.From && To == o.To && Promotion == o.Promotion; }
        public override bool Equals(object obj) { return obj is Move && Equals((Move)obj); }
        public override int GetHashCode() { return From | (To << 6) | ((int)Promotion << 12); }
        public override string ToString() { return Uci; }
    }

    /// <summary>Данные для отмены хода.</summary>
    public struct UndoInfo
    {
        public int Castling;
        public int EpSquare;
        public int Halfmove;
        public int Captured;
        public int CapturedSquare;
        public int Moved;
    }
}
