using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Kompyuter raqibi. Kiritish navbati (InputFrame ketma-ketligi) orqali ishlaydi — xuddi o'yinchi kabi
    /// kombinatsiyalarni "bosadi". Reaksiya kechikishi, blok ehtimoli, anti-air, kombo, maxsus usullar.
    /// </summary>
    public class FighterAI : IInputSource
    {
        public int difficulty; // 0..3
        readonly Queue<(int dir, Btn press, Btn hold)> queue = new Queue<(int, Btn, Btn)>();
        readonly System.Random rng;

        struct Snap { public FState state; public bool attacking; public HitLevel level; public bool air; public float x, y, vx; public int moveFrame, startup; public bool projectileNear; }
        readonly Snap[] hist = new Snap[64];
        int histHead;

        int holdBlockFrames;
        bool holdDown;
        int cooldown;
        int walkDir;
        int walkFrames;
        float finisherDelay = -1;
        int frame;

        static readonly HashSet<string> Zoning = new HashSet<string> { "wave", "dagger", "orb", "arrow", "rain" };
        static readonly HashSet<string> Rush = new HashSet<string> { "charge", "leap", "wolf", "whirl", "lasso" };
        static readonly HashSet<string> Close = new HashSet<string> { "quake", "grip", "step", "whirl" };
        static readonly HashSet<string> Defensive = new HashSet<string> { "counter", "ring", "step", "sextant" };

        int Reaction => difficulty switch { 0 => 26, 1 => 17, 2 => 11, _ => 7 };
        float BlockChance => difficulty switch { 0 => 0.22f, 1 => 0.5f, 2 => 0.76f, _ => 0.92f };
        float Aggression => difficulty switch { 0 => 0.35f, 1 => 0.5f, 2 => 0.65f, _ => 0.75f };

        public FighterAI(int difficulty, int seed = 0)
        {
            this.difficulty = Mathf.Clamp(difficulty, 0, 3);
            rng = new System.Random(seed + 12345);
        }

        float R() => (float)rng.NextDouble();

        public bool WantsFinisher()
        {
            if (finisherDelay < 0) finisherDelay = 1.2f + R() * 2f;
            finisherDelay -= 1f / 60f;
            return finisherDelay <= 0 && R() < 0.02f + difficulty * 0.03f;
        }

        void Record(Fighter self)
        {
            var o = self.opp;
            bool projNear = false;
            foreach (var p in self.match.projectiles)
                if (p != null && p.owner == o && p.Active && p.spec.damage > 0 && Mathf.Abs(p.pos.x - self.pos.x) < 3.5f && Mathf.Sign(p.vel.x) == Mathf.Sign(self.pos.x - p.pos.x)) projNear = true;
            histHead = (histHead + 1) % hist.Length;
            hist[histHead] = new Snap
            {
                state = o.state, attacking = o.IsAttacking && o.move != null && o.move.HasHitbox, level = o.move != null ? o.move.level : HitLevel.Mid,
                air = !o.Grounded, x = o.pos.x, y = o.pos.y, vx = o.vel.x, moveFrame = o.moveFrame, startup = o.move != null ? o.move.startup : 0, projectileNear = projNear
            };
        }

        Snap Seen(int ago) => hist[(histHead - Mathf.Min(ago, hist.Length - 1) + hist.Length) % hist.Length];

        public InputFrame Poll(Fighter self)
        {
            frame++;
            Record(self);
            if (self.match == null || !self.match.FightActive || !self.inputEnabled)
            {
                queue.Clear();
                self.blockHeldAI = false;
                return default;
            }
            if (self.match.phase == MatchPhase.FinishHim && self.opp.state == FState.Dizzy)
            {
                // G'olib: bir oz kutib, oddiy zarba (yakuniy zarbani MatchController boshqaradi)
                return default;
            }

            var snap = Seen(Reaction);
            float dist = Mathf.Abs(snap.x - self.pos.x);

            // Blok holatini ushlab turish
            if (holdBlockFrames > 0)
            {
                holdBlockFrames--;
                self.blockHeldAI = true;
                var bf = Make(self, holdDown ? 2 : 5, Btn.None, Btn.Block);
                if (holdBlockFrames == 0) self.blockHeldAI = false;
                return bf;
            }
            self.blockHeldAI = false;

            // Zarba ostida navbat bekor
            if (self.state == FState.Hitstun || self.state == FState.Juggle || self.state == FState.Knockdown || self.state == FState.Thrown) queue.Clear();
            // Otishdan qutulish
            if (self.state == FState.Thrown && self.stateFrame < 9 && R() < 0.05f * difficulty) return Make(self, 5, Btn.Throw, Btn.None);
            // Yiqilgandan keyin: dumalash yoki tez turish
            if (self.state == FState.Knockdown && self.stateFrame == 11 + difficulty)
            {
                float c = R();
                if (c < 0.3f) return Make(self, 4, Btn.None, Btn.None);
                if (c < 0.45f) return Make(self, 6, Btn.None, Btn.None);
                if (c < 0.7f) return Make(self, 8, Btn.None, Btn.None);
            }

            if (queue.Count > 0)
            {
                var q = queue.Dequeue();
                return Make(self, q.dir, q.press, q.hold);
            }

            if (cooldown > 0) { cooldown--; return Walk(self); }

            // Kombo uzish (breaker)
            if ((self.state == FState.Hitstun || self.state == FState.Juggle) && self.comboHits >= 3 && self.meter >= FightConst.BreakerCost && R() < 0.04f * difficulty)
                return Make(self, 6, Btn.Block, Btn.None);

            if (!self.IsNeutral && self.state != FState.Air) return default;

            // Himoya: raqib hujum qilyapti
            if ((snap.attacking && dist < 3.2f) || snap.projectileNear)
            {
                if (R() < BlockChance)
                {
                    holdBlockFrames = 14 + rng.Next(10);
                    holdDown = snap.level == HitLevel.Low || (snap.level != HitLevel.Overhead && R() < 0.3f);
                    if (snap.level == HitLevel.Overhead) holdDown = false;
                    self.blockHeldAI = true;
                    return Make(self, holdDown ? 2 : 5, Btn.None, Btn.Block);
                }
                if (snap.projectileNear && difficulty >= 2 && R() < 0.3f) { Jump(1); return Next(self); }
            }

            // Anti-air
            if (snap.air && dist < 2.6f && snap.y > 0.5f && self.Grounded)
            {
                if (R() < 0.12f + difficulty * 0.2f)
                {
                    string aa = HasSpecial(self, "sextant") && R() < 0.5f ? "sextant" : null;
                    if (aa != null) QueueSpecial(self, aa);
                    else { queue.Enqueue((2, Btn.None, Btn.None)); queue.Enqueue((2, Btn.HP, Btn.None)); }
                    cooldown = 20;
                    return Next(self);
                }
            }

            // Raqib yiqilgan — yaqinlashish
            if (snap.state == FState.Knockdown || snap.state == FState.GetUp)
            {
                walkDir = dist > 1.8f ? 1 : 0;
                return Walk(self);
            }

            // Super
            if (self.meter >= FightConst.SuperCost && dist < 2.2f && R() < 0.02f + 0.01f * difficulty)
            {
                queue.Enqueue((5, Btn.HP | Btn.HK, Btn.None));
                cooldown = 30;
                return Next(self);
            }

            // Hujum qarorlari
            float roll = R();
            if (roll > Aggression * 0.25f + 0.05f) { return Walk(self, dist); }

            if (dist > 4.6f)
            {
                var z = PickSpecial(self, Zoning);
                if (z != null && R() < 0.55f) { QueueSpecial(self, z); cooldown = 30 + rng.Next(30); return Next(self); }
                if (R() < 0.3f) { queue.Enqueue((6, Btn.None, Btn.None)); queue.Enqueue((5, Btn.None, Btn.None)); queue.Enqueue((6, Btn.None, Btn.None)); return Next(self); }
                walkDir = 1; walkFrames = 30;
                return Walk(self);
            }
            if (dist > 2.3f)
            {
                float c = R();
                if (c < 0.3f)
                {
                    var rs = PickSpecial(self, Rush);
                    if (rs != null) { QueueSpecial(self, rs); cooldown = 30; return Next(self); }
                }
                if (c < 0.5f)
                {
                    var z = PickSpecial(self, Zoning);
                    if (z != null) { QueueSpecial(self, z); cooldown = 30; return Next(self); }
                }
                if (c < 0.65f) { Jump(1); queue.Enqueue((5, Btn.None, Btn.None)); for (int i = 0; i < 14; i++) queue.Enqueue((5, Btn.None, Btn.None)); queue.Enqueue((5, R() < 0.5f ? Btn.HK : Btn.HP, Btn.None)); cooldown = 20; return Next(self); }
                walkDir = 1; walkFrames = 20;
                return Walk(self);
            }
            // Yaqin masofa
            {
                float c = R();
                if (c < 0.12f && self.CanBeThrown(self.opp, 1.1f)) { queue.Enqueue((5, Btn.Throw, Btn.None)); cooldown = 30; return Next(self); }
                if (c < 0.42f) { QueueString(self); cooldown = 24; return Next(self); }
                if (c < 0.55f) { queue.Enqueue((2, Btn.None, Btn.None)); queue.Enqueue((2, R() < 0.5f ? Btn.LK : Btn.HK, Btn.None)); cooldown = 22; return Next(self); }
                if (c < 0.66f) { queue.Enqueue((5, Btn.HP, Btn.None)); cooldown = 20; return Next(self); }
                if (c < 0.78f)
                {
                    var cl = PickSpecial(self, Close);
                    if (cl != null) { QueueSpecial(self, cl); cooldown = 30; return Next(self); }
                }
                if (c < 0.86f)
                {
                    var df = PickSpecial(self, Defensive);
                    if (df != null) { QueueSpecial(self, df); cooldown = 30; return Next(self); }
                }
                // Orqaga chekinish
                walkDir = -1; walkFrames = 14;
                return Walk(self);
            }
        }

        InputFrame Next(Fighter self)
        {
            if (queue.Count == 0) return default;
            var q = queue.Dequeue();
            return Make(self, q.dir, q.press, q.hold);
        }

        InputFrame Walk(Fighter self, float dist = -1)
        {
            if (walkFrames <= 0)
            {
                walkFrames = 10 + rng.Next(25);
                float r = R();
                walkDir = dist < 0 ? walkDir : dist > 3f ? (r < 0.75f ? 1 : 0) : dist < 1.4f ? (r < 0.4f ? -1 : 0) : (r < 0.45f ? 1 : r < 0.7f ? -1 : 0);
            }
            walkFrames--;
            return Make(self, walkDir > 0 ? 6 : walkDir < 0 ? 4 : 5, Btn.None, Btn.None);
        }

        void Jump(int dir)
        {
            int d = dir > 0 ? 9 : dir < 0 ? 7 : 8;
            queue.Enqueue((d, Btn.None, Btn.None));
            queue.Enqueue((d, Btn.None, Btn.None));
        }

        void QueueString(Fighter self)
        {
            var d = self.def;
            bool hasStr3 = d.Get("str3") != null;
            float r = R();
            if (hasStr3 && r < 0.4f + difficulty * 0.12f)
            {
                Press(Btn.LP, 9); Press(Btn.LP, 10); Press(Btn.HP, 1);
                if (d.Get("str4") != null && R() < 0.6f) { Wait(12); Press(Btn.HK, 1); }
                // Juggle davomi
                if (difficulty >= 2 && R() < 0.5f)
                {
                    Wait(26);
                    var z = PickSpecial(self, Zoning) ?? PickSpecial(self, Rush);
                    if (z != null) QueueSpecial(self, z);
                }
            }
            else if (d.Get("hk2") != null && r < 0.75f) { Press(Btn.HP, 12); Press(Btn.HK, 1); }
            else if (d.Get("lk2") != null && r < 0.8f) { Press(Btn.LK, 10); Press(d.Get("LK").chains != null && d.Get("LK").chains.ContainsKey(Btn.HK) ? Btn.HK : Btn.LK, 1); }
            else
            {
                Press(Btn.LP, 9);
                // normal → maxsus bekor qilish
                if (difficulty >= 1 && R() < 0.6f)
                {
                    var sp = PickSpecial(self, Rush) ?? PickSpecial(self, Zoning);
                    if (sp != null) QueueSpecial(self, sp);
                }
            }
        }

        void Press(Btn b, int waitAfter)
        {
            queue.Enqueue((5, b, Btn.None));
            Wait(waitAfter);
        }

        void Wait(int frames) { for (int i = 0; i < frames; i++) queue.Enqueue((5, Btn.None, Btn.None)); }

        bool HasSpecial(Fighter self, string id) => self.def.specials.Exists(s => s.moveId == id);

        string PickSpecial(Fighter self, HashSet<string> set)
        {
            var list = self.def.specials.FindAll(s => set.Contains(s.moveId) && !self.def.Get(s.moveId).air);
            if (list.Count == 0) return null;
            return list[rng.Next(list.Count)].moveId;
        }

        void QueueSpecial(Fighter self, string id)
        {
            var sp = self.def.specials.Find(s => s.moveId == id && !self.def.Get(s.moveId).air);
            if (sp == null) return;
            foreach (var m in sp.motion) { queue.Enqueue((m, Btn.None, Btn.None)); queue.Enqueue((m, Btn.None, Btn.None)); }
            bool enhance = difficulty >= 1 && self.meter >= FightConst.EnhanceCost + (self.meter >= FightConst.SuperCost ? 0 : 50) && R() < 0.15f + difficulty * 0.1f;
            queue.Enqueue((sp.motion[sp.motion.Length - 1], sp.button | (enhance ? Btn.Block : Btn.None), Btn.None));
            queue.Enqueue((5, Btn.None, Btn.None));
        }

        /// <summary>Nisbiy numpad yo'nalishidan mutlaq InputFrame.</summary>
        static InputFrame Make(Fighter self, int numpad, Btn press, Btn hold)
        {
            var f = new InputFrame { pressed = press, held = hold | press };
            int h = (numpad - 1) % 3 - 1;   // -1,0,1
            int v = (numpad - 1) / 3 - 1;   // -1 (past), 0, 1 (tepa)
            int abs = h * self.facing;
            f.right = abs > 0; f.left = abs < 0;
            f.up = v > 0; f.down = v < 0;
            return f;
        }
    }

    /// <summary>Mashq rejimi qo'g'irchog'i.</summary>
    public class DummyInput : IInputSource
    {
        public enum Mode { Stand, Crouch, Jump, BlockAll, BlockRandom, CPU }
        public Mode mode = Mode.Stand;
        public FighterAI cpu = new FighterAI(1, 99);
        int t;
        static readonly System.Random rng = new System.Random(5);

        public InputFrame Poll(Fighter self)
        {
            t++;
            self.blockHeldAI = false;
            switch (mode)
            {
                case Mode.Crouch: return new InputFrame { down = true };
                case Mode.Jump: return new InputFrame { up = t % 50 < 2 };
                case Mode.BlockAll:
                    {
                        var o = self.opp;
                        bool low = o.move != null && o.move.level == HitLevel.Low || o.crouching;
                        self.blockHeldAI = true;
                        return new InputFrame { held = Btn.Block, down = low };
                    }
                case Mode.BlockRandom:
                    if (rng.NextDouble() < 0.5) { self.blockHeldAI = true; return new InputFrame { held = Btn.Block }; }
                    return default;
                case Mode.CPU: return cpu.Poll(self);
                default: return default;
            }
        }
    }
}
