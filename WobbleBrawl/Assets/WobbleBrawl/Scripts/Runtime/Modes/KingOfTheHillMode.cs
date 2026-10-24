using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Hold the glowing zone alone to score. The zone hops around the arena; fallen fighters respawn.</summary>
    public sealed class KingOfTheHillMode : GameMode
    {
        public override string Title => "ЦАРЬ ГОРЫ";
        public override string Description => "Стой в светящейся зоне один, чтобы набирать очки. Зона переезжает. Упавшие возрождаются.";
        public override bool MultiRound => false;
        public override bool AllowRespawn => true;

        const float ZoneRadius = 1.8f;
        int spot;
        float moveTimer;
        Transform zone;
        Renderer zoneRenderer, ringRenderer;
        Brawler holder;
        bool contested;

        public override void BeginRound()
        {
            base.BeginRound();
            foreach (var p in gm.Config.participants) p.score = 0f;
            spot = Random.Range(0, Mathf.Max(1, gm.Arena.HillSpots.Count));
            moveTimer = Tune.KothMoveInterval;
            BuildZone();
            PlaceZone();
        }

        void BuildZone()
        {
            zone = Kit.Group(gm.Arena.Root, "Hill").transform;
            zoneRenderer = Kit.Deco(PrimitiveType.Cylinder, zone, Vector3.up * 0.02f, new Vector3(ZoneRadius * 2f, 0.015f, ZoneRadius * 2f),
                new Color(1f, 0.85f, 0.2f), null, false, 0.5f, 1.2f).GetComponent<Renderer>();
            ringRenderer = Kit.Deco(PrimitiveType.Cylinder, zone, Vector3.up * 1.6f, new Vector3(ZoneRadius * 2f, 0.01f, ZoneRadius * 2f),
                new Color(1f, 0.85f, 0.2f), null, false, 0.5f, 1.5f).GetComponent<Renderer>();
            var bob = ringRenderer.gameObject.AddComponent<Bob>();
            bob.amp = 0.4f;
            bob.speed = 2f;
        }

        void PlaceZone()
        {
            if (gm.Arena.HillSpots.Count == 0) { zone.position = gm.Arena.Center; return; }
            zone.position = gm.Arena.HillSpots[spot % gm.Arena.HillSpots.Count];
        }

        public override void Tick(float dt)
        {
            if (RoundOver) return;
            moveTimer -= dt;
            if (moveTimer <= 0f && gm.Arena.HillSpots.Count > 1)
            {
                int next = spot;
                while (next == spot) next = Random.Range(0, gm.Arena.HillSpots.Count);
                spot = next;
                PlaceZone();
                moveTimer = Tune.KothMoveInterval;
                gm.UI.Feed("Зона переехала!");
                Sfx.PlayUI(Sfx.Select, 0.6f, 0.8f);
                Fx.Confetti(zone.position + Vector3.up, 18);
            }

            holder = null;
            contested = false;
            Vector3 c = zone.position;
            foreach (var b in Brawler.All)
            {
                if (!b.IsConscious) continue;
                Vector3 d = b.Position - c;
                if (Mathf.Abs(d.y) > 2.5f) continue;
                d.y = 0f;
                if (d.magnitude > ZoneRadius) continue;
                if (holder == null) holder = b;
                else contested = true;
            }

            Color col = contested ? new Color(1f, 0.35f, 0.3f) : holder != null ? holder.participant.color : new Color(1f, 0.85f, 0.2f);
            zoneRenderer.sharedMaterial = MatFactory.Lit(col, 0.5f, 1.2f);
            ringRenderer.sharedMaterial = MatFactory.Lit(col, 0.5f, 1.5f);

            if (holder != null && !contested)
            {
                var p = holder.participant;
                p.score += dt;
                if (p.score >= Tune.KothScoreToWin)
                {
                    p.score = Tune.KothScoreToWin;
                    p.wins++;
                    RoundOver = true;
                    MatchOver = true;
                    RoundWinner = p;
                    ResultText = p.name + " — царь горы!";
                }
            }
        }

        public override string HudCenter()
        {
            if (holder == null) return "Зона свободна · " + Clock(moveTimer);
            if (contested) return "<color=#FF5A4D>Зона оспаривается!</color>";
            return Palette.Paint(holder.participant.name, holder.participant.color) + " держит зону · " + Clock(moveTimer);
        }

        public override string HudScore(Participant p) => Mathf.FloorToInt(p.score) + " / " + Tune.KothScoreToWin;
        public override float HudProgress(Participant p) => p.score / Tune.KothScoreToWin;

        public override Vector3? BotObjective(Brawler b) => zone != null ? zone.position : (Vector3?)null;
    }
}
