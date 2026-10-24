using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    public enum ModeKind { Brawl, KingOfTheHill, Climb }

    public enum BotSkill { Easy, Normal, Hard }

    /// <summary>Lobby choices for a match.</summary>
    public sealed class MatchConfig
    {
        public ModeKind mode = ModeKind.Brawl;
        public int arenaIndex;
        public int botCount = 2;
        public BotSkill botSkill = BotSkill.Normal;
        public int roundsToWin = 3;
        public readonly List<Participant> participants = new List<Participant>();

        public float SkillValue => botSkill == BotSkill.Easy ? 0.55f : botSkill == BotSkill.Hard ? 1.1f : 0.82f;
    }

    /// <summary>Rules of a match: when a round ends, who wins, what the HUD shows, what bots aim for.</summary>
    public abstract class GameMode
    {
        protected GameManager gm;

        public abstract string Title { get; }
        public abstract string Description { get; }
        public virtual bool UsesBots => true;
        public virtual bool MultiRound => true;
        public virtual bool AllowRespawn => false;
        public virtual float RespawnDelay => Tune.RespawnDelay;

        public bool RoundOver { get; protected set; }
        public bool MatchOver { get; protected set; }
        public Participant RoundWinner { get; protected set; }
        public string ResultText { get; protected set; }

        public void Bind(GameManager manager) => gm = manager;

        public virtual Arena CreateArena(MatchConfig cfg) => ArenaCatalog.CreateBrawl(cfg.arenaIndex);

        public virtual void BeginRound()
        {
            RoundOver = false;
            RoundWinner = null;
            ResultText = null;
        }

        public virtual void Tick(float dt) { }
        public virtual void OnBrawlerOut(Brawler b) { }
        public virtual void OnKnockout(Brawler victim, Brawler attacker) { }
        public virtual Vector3 RespawnPoint(Brawler b) => gm.Arena.SpawnPoint(Random.Range(0, 8));

        public virtual string HudCenter() => "";
        public virtual string HudScore(Participant p) => new string('★', p.wins);
        public virtual float HudProgress(Participant p) => -1f;
        public virtual string Hint => null;
        public virtual Vector3? BotObjective(Brawler b) => null;

        protected static string Clock(float seconds)
        {
            int s = Mathf.Max(0, Mathf.CeilToInt(seconds));
            return $"{s / 60}:{s % 60:00}";
        }

        public static GameMode Create(ModeKind kind)
        {
            switch (kind)
            {
                case ModeKind.KingOfTheHill: return new KingOfTheHillMode();
                case ModeKind.Climb: return new ClimbMode();
                default: return new BrawlMode();
            }
        }

        public static string TitleOf(ModeKind kind) => Create(kind).Title;
    }
}
