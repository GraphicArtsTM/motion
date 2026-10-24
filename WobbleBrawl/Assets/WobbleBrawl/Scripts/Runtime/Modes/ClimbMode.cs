using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Co-op puzzle climb. Checkpoints are shared by the team; reach the summit flag to win.</summary>
    public sealed class ClimbMode : GameMode
    {
        public override string Title => "ВОСХОЖДЕНИЕ";
        public override string Description => "Кооператив в стиле Human: Fall Flat. Лазай, таскай ящики, жми кнопки и доберись до флага на вершине.";
        public override bool UsesBots => false;
        public override bool MultiRound => false;
        public override bool AllowRespawn => true;
        public override float RespawnDelay => 1.2f;

        TowerLevel tower;
        int checkpoint;
        float time;

        public override Arena CreateArena(MatchConfig cfg) => ArenaCatalog.CreateClimb();

        public override void BeginRound()
        {
            base.BeginRound();
            tower = (TowerLevel)gm.Arena;
            checkpoint = 0;
            time = 0f;
            tower.onCheckpoint = (b, i) =>
            {
                if (i <= checkpoint) return;
                checkpoint = i;
                gm.UI.Feed(Palette.Paint(b.participant.name, b.participant.color) + " открыл чекпоинт " + i + "!");
                Sfx.PlayUI(Sfx.Select, 0.7f, 1.2f);
                Fx.Confetti(tower.Checkpoints[i] + Vector3.up, 24);
            };
            tower.onGoal = b =>
            {
                if (RoundOver) return;
                RoundOver = true;
                MatchOver = true;
                RoundWinner = b.participant;
                b.participant.wins++;
                ResultText = "Вершина покорена за " + Clock(time) + "!";
            };
        }

        public override void Tick(float dt)
        {
            if (!RoundOver) time += dt;
        }

        public override Vector3 RespawnPoint(Brawler b)
        {
            var p = tower.Checkpoints[Mathf.Clamp(checkpoint, 0, tower.Checkpoints.Count - 1)];
            return p + new Vector3(Random.Range(-1.2f, 1.2f), 0.1f, 0f);
        }

        public override string HudCenter() => "Чекпоинт " + checkpoint + " / " + (tower.Checkpoints.Count - 1) + " · " + Clock(time);
        public override string HudScore(Participant p) => "";
        public override string Hint => tower != null && checkpoint < tower.Hints.Count ? tower.Hints[checkpoint] : null;
    }
}
