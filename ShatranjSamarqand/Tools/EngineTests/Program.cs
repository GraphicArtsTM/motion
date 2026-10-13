using System;
using Shatranj.Chess;

// Проверка шахматного движка: perft на эталонных позициях + правила партии.
// Запуск: dotnet run -c Release
static class Program
{
    static int failures;

    static void Check(string name, long got, long expected)
    {
        bool ok = got == expected;
        if (!ok) failures++;
        Console.WriteLine($"{(ok ? "OK  " : "FAIL")} {name}: {got} (ожидалось {expected})");
    }

    static void CheckTrue(string name, bool cond)
    {
        if (!cond) failures++;
        Console.WriteLine($"{(cond ? "OK  " : "FAIL")} {name}");
    }

    static int Main()
    {
        var start = new Position(Variant.Classic);
        Check("start d1", start.Perft(1), 20);
        Check("start d2", start.Perft(2), 400);
        Check("start d3", start.Perft(3), 8902);
        Check("start d4", start.Perft(4), 197281);

        var kiwi = new Position(Variant.Classic, "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
        Check("kiwipete d1", kiwi.Perft(1), 48);
        Check("kiwipete d2", kiwi.Perft(2), 2039);
        Check("kiwipete d3", kiwi.Perft(3), 97862);

        var p3 = new Position(Variant.Classic, "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");
        Check("pos3 d4", p3.Perft(4), 43238);
        var p4 = new Position(Variant.Classic, "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");
        Check("pos4 d3", p4.Perft(3), 9467);
        var p5 = new Position(Variant.Classic, "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8");
        Check("pos5 d3", p5.Perft(3), 62379);

        Console.WriteLine(start.ToFen());
        CheckTrue("fen roundtrip", start.ToFen() == Position.StartFen);

        // Мат в 2 хода (детский мат с SAN)
        var g = new ChessGame(Variant.Classic);
        foreach (var u in new[] { "f2f3", "e7e5", "g2g4", "d8h4" }) g.PlayUci(u);
        CheckTrue("fool's mate result", g.Result == GameResult.BlackWins && g.Reason == EndReason.Checkmate);
        CheckTrue("fool's mate SAN Qh4#", g.History[3].San == "Qh4#");
        g.Undo();
        CheckTrue("undo resets result", !g.IsOver && g.SideToMove == Side.Black);

        // Рокировка и SAN
        var c = new ChessGame(Variant.Classic);
        foreach (var u in new[] { "e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1g1" }) c.PlayUci(u);
        CheckTrue("castle SAN", c.History[6].San == "O-O");
        CheckTrue("castle rook moved", c.Pos.Board[5] == Pc.Make(Side.White, PieceType.Rook));

        // Повторение
        var r = new ChessGame(Variant.Classic);
        foreach (var u in new[] { "g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8" }) r.PlayUci(u);
        CheckTrue("threefold repetition", r.Result == GameResult.Draw && r.Reason == EndReason.Repetition);

        // Пат
        var s = new ChessGame(Variant.Classic, "7k/5Q2/6K1/8/8/8/8/8 w - - 0 1");
        s.PlayUci("f7f6"); // не пат
        CheckTrue("not stalemate", !s.IsOver);
        var s2 = new ChessGame(Variant.Classic, "7k/8/6K1/8/8/8/8/5Q2 w - - 0 1");
        s2.PlayUci("f1f7");
        CheckTrue("stalemate classic draw", s2.Result == GameResult.Draw && s2.Reason == EndReason.Stalemate);
        var s3 = new ChessGame(Variant.Afrosiyob, "k7/3N4/1K6/8/8/8/8/7R w - - 0 1");
        s3.PlayUci("h1h2");
        CheckTrue("stalemate afrosiyob = win", s3.Result == GameResult.WhiteWins && s3.Reason == EndReason.StalemateWin);

        // SAN двусмысленность
        var d = new ChessGame(Variant.Classic, "4k3/8/8/8/8/8/4K3/R6R w - - 0 1");
        Move dm; d.TryFind(Sq.Parse("a1"), Sq.Parse("d1"), PieceType.None, out dm);
        d.Play(dm);
        CheckTrue("SAN disambiguation Rad1: " + d.History[0].San, d.History[0].San == "Rad1");

        // Превращение
        var pr = new ChessGame(Variant.Classic, "8/P6k/8/8/8/8/8/K7 w - - 0 1");
        CheckTrue("promotion detect", pr.IsPromotionMove(Sq.Parse("a7"), Sq.Parse("a8")));
        pr.PlayUci("a7a8n");
        CheckTrue("promotion SAN a8=N", pr.History[0].San == "a8=N");

        // Афросиёб: ходы фарзина и фила, без двойного хода пешки
        var af = new Position(Variant.Afrosiyob);
        Check("afrosiyob start moves", af.Perft(1), 8 + 4 + 4); // 8 пешек, 4 хода коней, 4 прыжка филов
        var af2 = new Position(Variant.Afrosiyob, "4k3/8/8/8/3Q4/8/8/4K3 w - - 0 1");
        int ferzMoves = 0; foreach (var m in af2.LegalMoves()) if (m.From == Sq.Parse("d4")) ferzMoves++;
        Check("ferz moves", ferzMoves, 4);
        var af3 = new Position(Variant.Afrosiyob, "4k3/8/8/8/3B4/8/8/4K3 w - - 0 1");
        int filMoves = 0; foreach (var m in af3.LegalMoves()) if (m.From == Sq.Parse("d4")) filMoves++;
        Check("fil moves", filMoves, 4);

        // Голый король
        var bk = new ChessGame(Variant.Afrosiyob, "4k3/8/8/8/8/8/3n4/R3K3 w - - 0 1");
        bk.PlayUci("a1a8"); // шах, но не голый
        CheckTrue("bare king not yet", !bk.IsOver);
        var bk2 = new ChessGame(Variant.Afrosiyob, "7k/8/8/8/8/8/n7/R3K3 w - - 0 1");
        bk2.PlayUci("a1a2");
        CheckTrue("bare king win", bk2.Result == GameResult.WhiteWins && bk2.Reason == EndReason.BareKing);

        // Недостаточный материал
        var im = new ChessGame(Variant.Classic, "4k3/8/8/8/8/8/3n4/4K3 w - - 0 1");
        CheckTrue("insufficient K+N vs K", im.Result == GameResult.Draw);

        // Трекер фигур
        var tg = new ChessGame(Variant.Classic);
        foreach (var u in new[] { "e2e4", "d7d5", "e4d5", "d8d5" }) tg.PlayUci(u);
        var tr = PieceTracker.Build(tg);
        int count = 0; foreach (var _ in tr.Alive) count++;
        Check("tracker alive", count, 30);
        PieceTracker.Info qi; tr.TryGet(tr.IdAt(Sq.Parse("d5")), out qi);
        Check("tracker queen kills", qi.Kills, 1);

        Console.WriteLine(failures == 0 ? "\nВСЕ ТЕСТЫ ПРОЙДЕНЫ" : $"\nПРОВАЛЕНО: {failures}");
        return failures == 0 ? 0 : 1;
    }
}
