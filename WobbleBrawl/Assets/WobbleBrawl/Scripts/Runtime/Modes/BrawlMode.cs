using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Last fighter standing wins the round. After two minutes: sudden death (double damage).</summary>
    public sealed class BrawlMode : GameMode
    {
        public override string Title => "ДРАКА";
        public override string Description => "Все против всех. Выкинь соперников с арены — последний оставшийся побеждает раунд.";

        float time;
        bool suddenDeath;
        float endDelay = -1f;

        public override void BeginRound()
        {
            base.BeginRound();
            time = 0f;
            suddenDeath = false;
            endDelay = -1f;
            GameManager.DamageMultiplier = 1f;
        }

        public override void Tick(float dt)
        {
            if (RoundOver) return;
            time += dt;
            if (!suddenDeath && time > Tune.SuddenDeathTime)
            {
                suddenDeath = true;
                GameManager.DamageMultiplier = 2f;
                gm.UI.Banner("ВНЕЗАПНАЯ СМЕРТЬ!", "Двойной урон", Palette.UiDanger, 2f);
                Sfx.PlayUI(Sfx.Whistle, 0.6f, 0.8f);
            }

            int alive = 0;
            Brawler last = null;
            foreach (var b in Brawler.All)
            {
                if (b.IsOut) continue;
                alive++;
                last = b;
            }

            if (alive <= 1)
            {
                // short grace period so near-simultaneous falls become a draw
                if (endDelay < 0f) endDelay = 0.6f;
                endDelay -= dt;
                if (endDelay > 0f) return;

                RoundOver = true;
                last = null;
                foreach (var b in Brawler.All) if (!b.IsOut) last = b;
                if (last != null)
                {
                    RoundWinner = last.participant;
                    RoundWinner.wins++;
                    ResultText = RoundWinner.name + " побеждает!";
                    if (RoundWinner.wins >= gm.Config.roundsToWin) MatchOver = true;
                }
                else ResultText = "Ничья!";
            }
        }

        public override string HudCenter() => suddenDeath ? "<color=#FF5A4D>ВНЕЗАПНАЯ СМЕРТЬ</color>" : Clock(Tune.SuddenDeathTime - time);
        public override string HudScore(Participant p) => p.wins > 0 ? new string('★', p.wins) : "";
    }
}
