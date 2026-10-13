using System.Collections.Generic;

namespace Shatranj.Chess
{
    /// <summary>
    /// Даёт каждой фигуре постоянный номер, чтобы 3D-модель «помнила» себя между ходами:
    /// сколько врагов она сразила (звание «Пахлавон»), во что превратилась пешка и т.п.
    /// Состояние полностью выводится из начальной позиции и списка ходов, поэтому
    /// корректно переживает отмену хода и загрузку сохранения.
    /// </summary>
    public sealed class PieceTracker
    {
        public struct Info
        {
            public int Id;
            public int Piece;
            public int Square;
            public int Kills;
        }

        readonly int[] idAt = new int[64];
        readonly Dictionary<int, Info> alive = new Dictionary<int, Info>();
        int nextId = 1;

        public PieceTracker(Position start)
        {
            for (int i = 0; i < 64; i++)
            {
                idAt[i] = 0;
                int p = start.Board[i];
                if (p == 0) continue;
                int id = nextId++;
                idAt[i] = id;
                alive[id] = new Info { Id = id, Piece = p, Square = i, Kills = 0 };
            }
        }

        public static PieceTracker Build(ChessGame game)
        {
            var t = new PieceTracker(new Position(game.Variant, game.StartFen));
            foreach (var r in game.History) t.Apply(r);
            return t;
        }

        public IEnumerable<Info> Alive { get { return alive.Values; } }

        public int IdAt(int sq) { return sq >= 0 && sq < 64 ? idAt[sq] : 0; }

        public bool TryGet(int id, out Info info) { return alive.TryGetValue(id, out info); }

        public void Apply(MoveRecord r)
        {
            var m = r.Move;
            int mover = idAt[m.From];
            if (r.CapturedSquare >= 0)
            {
                int victim = idAt[r.CapturedSquare];
                if (victim != 0) alive.Remove(victim);
                idAt[r.CapturedSquare] = 0;
            }
            idAt[m.From] = 0;
            idAt[m.To] = mover;
            if (mover != 0)
            {
                var info = alive[mover];
                info.Square = m.To;
                if (r.CapturedPiece != 0) info.Kills++;
                if (m.IsPromotion) info.Piece = Pc.Make(r.Mover, m.Promotion);
                alive[mover] = info;
            }
            if (r.RookFrom >= 0)
            {
                int rook = idAt[r.RookFrom];
                idAt[r.RookFrom] = 0;
                idAt[r.RookTo] = rook;
                if (rook != 0)
                {
                    var info = alive[rook];
                    info.Square = r.RookTo;
                    alive[rook] = info;
                }
            }
        }
    }
}
