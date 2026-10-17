using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public enum FState
    {
        Intro, Idle, Walk, Crouch, Block, CrouchBlock, JumpSquat, Air, Landing, Dash, Attack,
        Blockstun, Hitstun, Juggle, Knockdown, GetUp, Throwing, Thrown, Dizzy, Victory, Defeat, Cinematic, KO
    }

    public static class FightConst
    {
        public const float Gravity = 34f;
        public const float StageHalfWidth = 9.6f;
        public const float MaxSeparation = 7.4f;
        public const float PushWidth = 0.62f;
        public const float MaxMeter = 300f;
        public const float SuperCost = 300f;
        public const float BreakerCost = 200f;
        public const int KnockdownFrames = 38;
        public const int GetUpFrames = 26;
    }

    /// <summary>
    /// Jangchi: holat mashinasi, fizika, kombo/bekor qilish (cancel), otish, juggle, meter.
    /// Mantiq qat'iy 60 kadr/soniyada (FixedUpdate orqali MatchController chaqiradi).
    /// </summary>
    public class Fighter : MonoBehaviour
    {
        // --- Havolalar ---
        public FighterDefinition def;
        public int index;
        public Fighter opp;
        public MatchController match;
        public Rig rig;
        public ProceduralAnimator anim;
        public IInputSource input;
        public readonly InputBuffer buf = new InputBuffer();
        public FighterVisualFx fx;

        // --- Fizika ---
        public Vector2 pos, vel, prevPos;
        public int facing = 1;
        public float gravityMult = 1f;
        public bool Grounded => pos.y <= 0.0001f;

        // --- Ko'rsatkichlar ---
        public float maxHealth = 1000f;
        public float health = 1000f;
        public float displayHealth = 1000f;   // UI uchun kechikkan qizil chiziq
        public float meter;
        public int roundsWon;

        // --- Holat ---
        public FState state = FState.Idle;
        public int stateFrame;
        public MoveData move;
        public int moveFrame;
        public bool moveConnected;      // urildi yoki blokka tushdi
        public bool moveHit;            // aniq urildi
        int lastHitIdx = -1;
        public int stun;
        public int hitstop;
        public bool crouching;
        public int invul;
        public bool inputEnabled = true;
        public bool training;
        public int comboHits;           // shu jangchi qabul qilgan ketma-ket zarbalar
        public float comboDamage;
        public int juggleHits;
        public int jumpDir;
        int jumpFrame;
        bool usedAirAttack;
        string queuedMove;
        int queuedAt = -1;
        public Fighter thrower;
        int throwFrame;
        bool throwBroken;
        public bool isKO;
        public float spinAngle;
        public float spinSpeed;
        public string lastMoveName;
        public float flashTimer;
        public Color flashColor = Color.white;
        int lastConsumedFrame = -1;
        int frameCounter;
        public bool counterHitFlag;
        public bool blockHeldAI; // AI uchun
        public InputFrame lastInput;

        // Dizzy/finisher
        public bool canFinish;

        public System.Action<Fighter, string> onAnnounce;

        public bool IsAttacking => state == FState.Attack;
        public bool InHitstun => state == FState.Hitstun || state == FState.Juggle;
        public bool IsNeutral => state == FState.Idle || state == FState.Walk || state == FState.Crouch || state == FState.Block || state == FState.CrouchBlock;
        public bool IsBlockingState => state == FState.Block || state == FState.CrouchBlock || state == FState.Blockstun;
        public float HealthFrac => Mathf.Clamp01(health / maxHealth);
        public int Bars => Mathf.FloorToInt(meter / 100f);

        // ======================= Sozlash =======================
        public void Setup(FighterDefinition d, int idx, IInputSource inp, MatchController m)
        {
            def = d; index = idx; input = inp; match = m;
            rig = d.buildVisual(transform);
            rig.transform.localRotation = Quaternion.Euler(0, 90, 0);
            anim = rig.gameObject.AddComponent<ProceduralAnimator>();
            anim.rig = rig;
            fx = gameObject.AddComponent<FighterVisualFx>();
            fx.Init(this);
            anim.Play(def.anims.idle, 0);
        }

        public void ResetForRound(float x, int face)
        {
            pos = prevPos = new Vector2(x, 0);
            vel = Vector2.zero;
            facing = face;
            health = displayHealth = maxHealth;
            state = FState.Idle;
            stateFrame = 0;
            move = null;
            stun = hitstop = invul = 0;
            crouching = false;
            comboHits = juggleHits = 0;
            comboDamage = 0;
            isKO = false;
            canFinish = false;
            queuedMove = null;
            thrower = null;
            spinAngle = 0;
            spinSpeed = 0;
            anim.spin = Quaternion.identity;
            flashTimer = 0;
            cinePhysics = false;
            cineGroundLock = true;
            blockHeldAI = false;
            inputEnabled = true;
            if (fx != null) fx.aura = 0;
            if (rig != null) rig.gameObject.SetActive(true);
            buf.Clear();
            ApplyFacing();
            anim.Play(def.anims.idle, 0.1f);
            fx.StopTrails();
            transform.position = new Vector3(pos.x, pos.y, 0);
        }

        // ======================= Asosiy kadr =======================
        public void Tick()
        {
            frameCounter++;
            prevPos = pos;
            InputFrame inp = default;
            if (input != null)
            {
                inp = input.Poll(this);
                if (!inputEnabled) inp = default;
            }
            lastInput = inp;
            buf.Push(inp, facing);

            if (hitstop > 0)
            {
                hitstop--;
                return;
            }

            stateFrame++;
            if (invul > 0) invul--;
            if (flashTimer > 0) flashTimer -= 1f / 60f;

            int dir = buf.Dir(0);

            switch (state)
            {
                case FState.Idle:
                case FState.Walk:
                case FState.Crouch:
                case FState.Block:
                case FState.CrouchBlock:
                    Neutral(inp, dir);
                    break;
                case FState.JumpSquat:
                    if (stateFrame >= 3) LaunchJump();
                    break;
                case FState.Air:
                    AirTick(inp);
                    break;
                case FState.Landing:
                    vel.x = 0;
                    if (stateFrame >= 4) ToNeutral();
                    break;
                case FState.Dash:
                    DashTick();
                    break;
                case FState.Attack:
                    AttackTick(inp);
                    break;
                case FState.Blockstun:
                    vel.x = Mathf.MoveTowards(vel.x, 0, 22f / 60f);
                    if (--stun <= 0)
                    {
                        if (inp.Held(Btn.Block) || blockHeldAI) SetState(crouching ? FState.CrouchBlock : FState.Block);
                        else ToNeutral();
                    }
                    break;
                case FState.Hitstun:
                    vel.x = Mathf.MoveTowards(vel.x, 0, 18f / 60f);
                    TryBreaker(inp);
                    if (state == FState.Hitstun && --stun <= 0) { ToNeutral(); }
                    break;
                case FState.Juggle:
                    spinAngle += spinSpeed / 60f;
                    TryBreaker(inp);
                    break;
                case FState.Knockdown:
                    vel.x = Mathf.MoveTowards(vel.x, 0, 30f / 60f);
                    invul = 2;
                    if (!isKO && stateFrame >= FightConst.KnockdownFrames && match.FightActive) StartGetUp();
                    break;
                case FState.GetUp:
                    invul = 2;
                    if (stateFrame >= FightConst.GetUpFrames) ToNeutral();
                    break;
                case FState.Throwing:
                    ThrowingTick();
                    break;
                case FState.Thrown:
                    if (thrower == null || thrower.state != FState.Throwing)
                    {
                        // Otuvchi to'xtadi — yiqilish
                        if (state == FState.Thrown) EnterJuggle(new Vector2(-1.5f * facing, 3f), false);
                    }
                    else if (stateFrame <= 10 && !throwBroken && FreshPress(Btn.Throw, 3) >= 0)
                    {
                        thrower.BreakThrow();
                    }
                    break;
                case FState.Dizzy:
                    vel.x = 0;
                    break;
                case FState.Cinematic:
                    if (!cinePhysics) vel.x = Mathf.MoveTowards(vel.x, 0, 20f / 60f);
                    break;
                case FState.Intro:
                case FState.Victory:
                case FState.Defeat:
                case FState.KO:
                    vel.x = Mathf.MoveTowards(vel.x, 0, 20f / 60f);
                    break;
            }

            Physics();
            UpdateFacingIfAllowed();
            HealthTrail();
        }

        void HealthTrail()
        {
            if (comboHits == 0 || !InHitstun) displayHealth = Mathf.MoveTowards(displayHealth, health, maxHealth * 0.3f / 60f);
            if (displayHealth < health) displayHealth = health;
        }

        // ======================= Neytral =======================
        void Neutral(InputFrame inp, int dir)
        {
            bool fwd = dir == 6 || dir == 9 || dir == 3;
            bool back = dir == 4 || dir == 7 || dir == 1;
            bool down = dir == 1 || dir == 2 || dir == 3;
            bool up = dir == 7 || dir == 8 || dir == 9;
            if (comboHits > 0 && stateFrame > 2) { comboHits = 0; comboDamage = 0; juggleHits = 0; }

            if (TryCommands(inp, false)) return;

            bool blockHeld = inp.Held(Btn.Block) || blockHeldAI;
            if (blockHeld)
            {
                crouching = down;
                SetSub(crouching ? FState.CrouchBlock : FState.Block);
                vel.x = 0;
                return;
            }
            if (up)
            {
                jumpDir = fwd ? 1 : back ? -1 : 0;
                SetState(FState.JumpSquat);
                anim.Play(def.anims.jumpSquat, 0.04f);
                vel.x = 0;
                return;
            }
            if (buf.DoubleTap(6)) { StartDash(1); return; }
            if (buf.DoubleTap(4)) { StartDash(-1); return; }

            if (down)
            {
                crouching = true;
                SetSub(FState.Crouch);
                vel.x = 0;
                return;
            }
            crouching = false;
            if (fwd) { SetSub(FState.Walk, 1); vel.x = def.walkFwd * facing; }
            else if (back) { SetSub(FState.Walk, -1); vel.x = -def.walkBack * facing; }
            else { SetSub(FState.Idle); vel.x = 0; }
        }

        int walkSign;
        /// <summary>Neytral ichki holatni almashtirish (animatsiya bilan).</summary>
        void SetSub(FState s, int walk = 0)
        {
            if (s == state && (s != FState.Walk || walk == walkSign)) return;
            FState prev = state;
            state = s;
            stateFrame = 0;
            walkSign = walk;
            var a = def.anims;
            switch (s)
            {
                case FState.Idle: anim.Play(prev == FState.Crouch || prev == FState.CrouchBlock ? a.standUp : a.idle, 0.1f); break;
                case FState.Walk: anim.Play(walk > 0 ? a.walkF : a.walkB, 0.12f); break;
                case FState.Crouch: anim.Play(prev == FState.CrouchBlock ? a.crouch : a.crouchDown, 0.06f); break;
                case FState.Block: anim.Play(a.block, 0.05f); break;
                case FState.CrouchBlock: anim.Play(a.crouchBlock, 0.05f); break;
            }
        }

        public void ToNeutral()
        {
            move = null;
            fx.StopTrails();
            anim.spin = Quaternion.identity;
            spinAngle = 0;
            gravityMult = 1f;
            if (!Grounded) { SetState(FState.Air); usedAirAttack = true; anim.Play(def.anims.fall, 0.1f); return; }
            pos.y = 0;
            vel = Vector2.zero;
            bool down = buf.Dir(0) <= 3;
            state = FState.Walk; // majburiy qayta tanlash
            walkSign = 99;
            crouching = down;
            stateFrame = 0;
            if (down) { state = FState.Crouch; anim.Play(def.anims.crouch, 0.12f); }
            else { state = FState.Idle; anim.Play(def.anims.idle, 0.14f); }
        }

        void SetState(FState s)
        {
            state = s;
            stateFrame = 0;
        }

        // ======================= Buyruqlar =======================
        /// <summary>Yangi (iste'mol qilinmagan) tugma bosilishi necha kadr oldin bo'lgan.</summary>
        public int FreshPress(Btn b, int window)
        {
            for (int i = 0; i < window && i < buf.Count; i++)
            {
                if ((buf.Pressed(i) & b) != 0 && frameCounter - i > lastConsumedFrame) return i;
            }
            return -1;
        }

        void Consume(int ago) { lastConsumedFrame = Mathf.Max(lastConsumedFrame, frameCounter - ago); }

        bool TryCommands(InputFrame inp, bool air)
        {
            if (!air && TrySuper()) return true;
            if (TrySpecials(air, 4)) return true;
            if (!air)
            {
                int t = FreshPress(Btn.Throw, 3);
                if (t >= 0) { Consume(t); if (StartMove(def.Get("throw"))) return true; }
            }
            return TryNormals(air);
        }

        bool TryNormals(bool air)
        {
            Btn[] order = { Btn.HP, Btn.HK, Btn.LP, Btn.LK };
            int dir = buf.Dir(0);
            bool down = dir <= 3;
            bool fwd = dir == 6 || dir == 9;
            bool back = dir == 4 || dir == 7;
            foreach (var b in order)
            {
                int ago = FreshPress(b, 3);
                if (ago < 0) continue;
                string n = b.ToString();
                string id = air ? "j" + n : down ? "c" + n : fwd && def.Get("f" + n) != null ? "f" + n : back && def.Get("b" + n) != null ? "b" + n : n;
                var m = def.Get(id);
                if (m == null) continue;
                Consume(ago);
                if (air) usedAirAttack = true;
                return StartMove(m);
            }
            return false;
        }

        bool TrySpecials(bool air, int leniency)
        {
            foreach (var sp in def.specials)
            {
                int ago = FreshPress(sp.button, leniency);
                if (ago < 0) continue;
                var m = def.Get(sp.moveId);
                if (m == null) continue;
                if (air && !m.airOK) continue;
                if (!air && m.air) continue;
                if (!buf.MatchMotion(sp.motion, ago, sp.window)) continue;
                Consume(ago);
                return StartMove(m);
            }
            return false;
        }

        bool TrySuper()
        {
            if (def.superMoveId == null || meter < FightConst.SuperCost) return false;
            int a = FreshPress(Btn.HP, 5), b = FreshPress(Btn.HK, 5);
            if (a < 0 || b < 0 || Mathf.Abs(a - b) > 3) return false;
            Consume(Mathf.Min(a, b));
            var m = def.Get(def.superMoveId);
            if (m == null) return false;
            meter -= FightConst.SuperCost;
            match.OnSuperStart(this);
            return StartMove(m);
        }

        /// <summary>Kombo uzish (Breaker): zarba ostida, 2 bo'lak meter, oldinga + Blok.</summary>
        void TryBreaker(InputFrame inp)
        {
            if (meter < FightConst.BreakerCost || comboHits < 2 || isKO) return;
            int ago = FreshPress(Btn.Block, 3);
            if (ago < 0) return;
            int dir = buf.Dir(0);
            if (!(dir == 6 || dir == 9 || dir == 3)) return;
            Consume(ago);
            meter -= FightConst.BreakerCost;
            match.OnBreaker(this);
            invul = 30;
            comboHits = 0;
            juggleHits = 0;
            if (opp != null && !opp.isKO) opp.EnterJuggle(new Vector2(5.5f, 6f), false);
            if (Grounded) { ToNeutral(); }
            else { SetState(FState.Air); usedAirAttack = true; vel = new Vector2(-facing * 2.5f, 4f); anim.Play(def.anims.fall, 0.1f); anim.spin = Quaternion.identity; }
        }

        // ======================= Harakatlar =======================
        public bool StartMove(MoveData m)
        {
            if (m == null) return false;
            if (m.isThrow && m.kind == MoveKind.Throw && opp != null && !CanBeThrown(opp, m.throwRange * 1.6f) && !m.air)
            {
                // juda uzoq — otish urinish baribir animatsiya qilinadi (whiff)
            }
            move = m;
            moveFrame = 0;
            moveConnected = false;
            moveHit = false;
            lastHitIdx = -1;
            SetState(FState.Attack);
            crouching = m.crouching;
            lastMoveName = m.name;
            counterHitFlag = false;
            if (!m.keepMomentum && !m.air) vel.x = 0;
            if (m.air) vel.x *= 0.95f;
            anim.Play(m.clip, m.kind == MoveKind.Normal ? 0.04f : 0.06f);
            SynthAudio.Play(Sfx.None);
            m.onStart?.Invoke(this);
            if (m.kind == MoveKind.Special && match != null) match.OnSpecialStart(this, m);
            return true;
        }

        public void ForceMove(string id)
        {
            var m = def.Get(id);
            if (m != null) StartMove(m);
        }

        /// <summary>Faol kadrlarni o'tkazib, tiklanish (recovery) bosqichiga o'tish.</summary>
        public void SkipToRecovery(int extra = 0)
        {
            if (move == null) return;
            moveFrame = Mathf.Max(moveFrame, move.startup + move.active - extra);
            fx.StopTrails();
        }

        public void QueueMove(string id, int atFrame)
        {
            queuedMove = id;
            queuedAt = atFrame;
        }

        void AttackTick(InputFrame inp)
        {
            var m = move;
            moveFrame++;
            int f = moveFrame;

            // Siljish
            if (m.moveEnd >= 0 && f >= m.moveStart && f <= m.moveEnd)
            {
                vel.x = m.moveVel.x * facing;
                if (m.moveVel.y != 0 && f == m.moveStart) vel.y = m.moveVel.y;
            }
            else if (Grounded && !m.keepMomentum && f > m.moveEnd) vel.x = Mathf.MoveTowards(vel.x, 0, 30f / 60f);

            // Invul / armor
            if (m.invulStart >= 0 && f >= m.invulStart && f <= m.invulEnd) invul = Mathf.Max(invul, 1);

            // Shamol / trail
            if (f == Mathf.Max(1, m.startup - 3))
            {
                SynthAudio.Play(m.whoosh, 0.7f);
                fx.StartTrails(m);
            }
            if (f == m.startup + m.active + 3) fx.StopTrails();

            // Otish
            if (m.isThrow && f == m.startup)
            {
                if (CanBeThrown(opp, m.throwRange)) { BeginThrow(m); return; }
            }

            m.onFrame?.Invoke(this, f);
            if (state != FState.Attack || move != m) return; // callback holatni o'zgartirgan bo'lishi mumkin

            if (queuedMove != null && f >= queuedAt)
            {
                string q = queuedMove; queuedMove = null;
                ForceMove(q);
                return;
            }

            // Zanjir (string) va bekor qilish (cancel)
            int cancelStart = m.startup;
            int cancelEnd = m.startup + m.active + Mathf.Max(4, (int)(m.recovery * 0.75f));
            if (f >= cancelStart && f <= cancelEnd)
            {
                if (m.chains != null && (moveConnected || m.whiffChain))
                {
                    foreach (var kv in m.chains)
                    {
                        int ago = FreshPress(kv.Key, 10);
                        if (ago >= 0)
                        {
                            Consume(ago);
                            StartMove(def.Get(kv.Value));
                            return;
                        }
                    }
                }
                if (moveConnected && m.kind == MoveKind.Normal && m.specialCancel)
                {
                    if (TrySuper()) return;
                    if (TrySpecials(m.air, 10)) return;
                }
            }

            if (f >= m.TotalFrames)
            {
                m.onEnd?.Invoke(this);
                if (m.air && !Grounded)
                {
                    move = null;
                    SetState(FState.Air);
                    anim.Play(def.anims.fall, 0.12f);
                }
                else ToNeutral();
            }
        }

        void AirTick(InputFrame inp)
        {
            jumpFrame++;
            if (jumpDir != 0)
            {
                float airTime = 2f * def.jumpVel / FightConst.Gravity;
                float t = Mathf.Clamp01(jumpFrame / 60f / airTime);
                float a = Mathf.SmoothStep(0, 1, Mathf.Clamp01((t - 0.12f) / 0.7f)) * 360f;
                anim.spin = Quaternion.Euler(jumpDir > 0 ? a : -a, 0, 0);
            }
            if (!usedAirAttack && TryCommands(inp, true))
            {
                anim.spin = Quaternion.identity;
                return;
            }
        }

        void LaunchJump()
        {
            SetState(FState.Air);
            vel = new Vector2(jumpDir * def.jumpX * facing, def.jumpVel);
            jumpFrame = 0;
            usedAirAttack = false;
            anim.Play(jumpDir == 0 ? def.anims.jumpUp : def.anims.jumpF, 0.05f);
            SynthAudio.Play(Sfx.Jump, 0.5f);
            fx.Dust(0.6f);
        }

        void StartDash(int d)
        {
            SetState(FState.Dash);
            jumpDir = d;
            anim.Play(d > 0 ? def.anims.dashF : def.anims.dashB, 0.05f);
            if (d < 0) invul = 6;
            SynthAudio.Play(Sfx.WhooshLight, 0.4f);
            fx.Dust(0.5f);
        }

        void DashTick()
        {
            int len = jumpDir > 0 ? 14 : 16;
            float k = 1f - Mathf.Clamp01(stateFrame / (float)len);
            vel.x = jumpDir * def.dashSpeed * (0.35f + 0.65f * k) * facing * (jumpDir > 0 ? 1f : 0.9f);
            if (stateFrame >= len) ToNeutral();
        }

        void StartGetUp()
        {
            SetState(FState.GetUp);
            anim.Play(def.anims.getUp, 0.08f);
            invul = FightConst.GetUpFrames;
            juggleHits = 0;
        }

        // ======================= Otish (throw) =======================
        public bool CanBeThrown(Fighter target, float range)
        {
            if (target == null) return false;
            if (!target.Grounded || target.invul > 0 || target.isKO) return false;
            if (target.state == FState.Hitstun || target.state == FState.Blockstun || target.state == FState.Juggle ||
                target.state == FState.Knockdown || target.state == FState.GetUp || target.state == FState.Thrown ||
                target.state == FState.Throwing || target.state == FState.JumpSquat || target.state == FState.Cinematic) return false;
            return Mathf.Abs(target.pos.x - pos.x) <= range;
        }

        MoveData throwMove;
        void BeginThrow(MoveData m)
        {
            throwMove = m;
            SetState(FState.Throwing);
            throwFrame = 0;
            throwBroken = false;
            opp.SetState(FState.Thrown);
            opp.thrower = this;
            opp.move = null;
            opp.fx.StopTrails();
            opp.vel = Vector2.zero;
            opp.crouching = false;
            opp.anim.Play(opp.def.anims.thrown, 0.05f);
            anim.Play(def.anims.throwGrab, 0.05f);
            SynthAudio.Play(Sfx.Grab, 0.8f);
            match.cam?.Shake(0.05f);
            m.onHit?.Invoke(this, opp);
        }

        public void BreakThrow()
        {
            if (throwBroken) return;
            throwBroken = true;
            SynthAudio.Play(Sfx.Block, 0.9f);
            match.Announce("OZOD!", 0.8f, new Color(0.6f, 0.9f, 1f));
            var o = opp;
            o.thrower = null;
            o.SetState(FState.Hitstun);
            o.stun = 14;
            o.vel = new Vector2(-o.facing * 4f, 0);
            o.anim.Play(o.def.anims.hitMid, 0.05f);
            SetState(FState.Hitstun);
            stun = 14;
            vel = new Vector2(-facing * 4f, 0);
            anim.Play(def.anims.hitMid, 0.05f);
            fx.Spark(new Vector3((pos.x + o.pos.x) / 2, 1.2f, -0.3f), HitFx.Blunt, true, 0.8f);
        }

        void ThrowingTick()
        {
            throwFrame++;
            var o = opp;
            if (o.state != FState.Thrown) { ToNeutral(); return; }
            // Raqib harakati: oldinda ushlash → boshdan oshirib → yerga urish
            const int lift = 14, slam = 32, end = 50;
            Vector2 front = pos + new Vector2(facing * 0.75f, 0);
            if (throwFrame <= lift)
            {
                float t = throwFrame / (float)lift;
                o.pos = Vector2.Lerp(o.pos, front + new Vector2(0, 0.25f * t), 0.5f);
                o.anim.spin = Quaternion.identity;
            }
            else if (throwFrame <= slam)
            {
                float t = (throwFrame - lift) / (float)(slam - lift);
                float ang = Mathf.Lerp(0, Mathf.PI, t);
                float dist = throwMove != null && throwMove.forwardThrow ? 1.25f : -1.25f;
                Vector2 p = pos + new Vector2(facing * (0.15f + Mathf.Cos(Mathf.PI - ang) * 0.0f + Mathf.Lerp(0.6f, dist, t)), 0.3f + Mathf.Sin(ang) * 1.6f);
                o.pos = p;
                o.anim.spin = Quaternion.Euler(-t * 200f, 0, 0);
                if (throwFrame == lift + 1) SynthAudio.Play(Sfx.Throw, 0.8f);
            }
            if (throwFrame == slam)
            {
                float dmg = (throwMove != null ? throwMove.throwDamage : 120f) * def.damageMult;
                o.thrower = null;
                o.anim.spin = Quaternion.identity;
                o.pos.y = 0;
                o.ApplyDamage(dmg, this, false);
                o.vel = new Vector2(facing * 2.5f, 0);
                o.EnterKnockdownDirect();
                match.OnThrowLanded(this, o);
                meter = Mathf.Min(FightConst.MaxMeter, meter + 20);
                fx.Dust(1.5f, o.pos.x);
                SynthAudio.Play(Sfx.BodyFall, 1f);
                SynthAudio.Play(Sfx.HitHeavy, 0.9f);
                match.cam?.Shake(0.25f);
            }
            if (throwFrame >= end) ToNeutral();
        }

        // ======================= Zarba qabul qilish =======================
        public bool IsBlockingAgainst(HitLevel level)
        {
            if (!Grounded || isKO) return false;
            bool blockHeld = lastInput.Held(Btn.Block) || blockHeldAI;
            bool canBlockNow = state == FState.Block || state == FState.CrouchBlock || state == FState.Blockstun ||
                               ((state == FState.Idle || state == FState.Walk || state == FState.Crouch) && blockHeld);
            if (!canBlockNow) return false;
            bool low = crouching || state == FState.CrouchBlock;
            switch (level)
            {
                case HitLevel.Low: return low;
                case HitLevel.Overhead: return !low;
                case HitLevel.Unblockable: return false;
                default: return true;
            }
        }

        public void ApplyDamage(float dmg, Fighter from, bool chip)
        {
            if (training && health - dmg < 1) dmg = Mathf.Max(0, health - 1);
            health = Mathf.Max(0, health - dmg);
            if (!chip) comboDamage += dmg;
            meter = Mathf.Min(FightConst.MaxMeter, meter + dmg * 0.07f);
            if (health <= 0 && !isKO) match.OnKO(this, from);
        }

        public void OnBlocked(MoveData m, Fighter attacker, float chipDmg)
        {
            ApplyDamage(chipDmg, attacker, true);
            SetState(FState.Blockstun);
            stun = m.blockstun;
            move = null;
            fx.StopTrails();
            vel = new Vector2(attacker.facing * m.blockPush, 0);
            anim.Play(crouching ? def.anims.crouchBlockHit : def.anims.blockHit, 0.03f);
            anim.Flinch(new Vector3(-6, 0, 0), 0.5f);
            comboHits = 0;
            juggleHits = 0;
            meter = Mathf.Min(FightConst.MaxMeter, meter + 4);
        }

        public void OnHit(MoveData m, Fighter attacker, float dmg, Vector2 knock, bool counter)
        {
            bool wasAir = !Grounded || state == FState.Juggle;
            comboHits++;
            ApplyDamage(dmg, attacker, false);
            move = null;
            fx.StopTrails();
            flashTimer = 0.12f;
            flashColor = Color.white;
            if (isKO && !canFinish)
            {
                // Yakuniy zarba — havoga uchib yiqilish
                EnterJuggle(new Vector2(knock.x * 1.4f + 2f, Mathf.Max(7.5f, knock.y)), true);
                return;
            }
            if (state == FState.Dizzy || canFinish)
            {
                EnterJuggle(new Vector2(knock.x + 2f, Mathf.Max(6f, knock.y)), true);
                return;
            }
            if (m.launch || m.knockdown || m.sweep || wasAir)
            {
                Vector2 v = knock;
                if (m.sweep) v = new Vector2(0.6f, 4.5f);
                else if (m.knockdown && !m.launch && !wasAir) v = new Vector2(Mathf.Max(knock.x, 3f), Mathf.Max(knock.y, 5.5f));
                else if (wasAir && !m.launch) v = new Vector2(Mathf.Max(1.6f, knock.x * 0.7f), Mathf.Max(4.5f, knock.y));
                EnterJuggle(v, m.sweep);
                juggleHits++;
                return;
            }
            SetState(FState.Hitstun);
            stun = m.hitstun + (counter ? 4 : 0);
            vel = new Vector2(attacker.facing * knock.x, 0);
            var a = def.anims;
            AnimClip c = crouching ? a.hitCrouch : m.level == HitLevel.Low ? a.hitLow : (m.hitbox.y > 1.2f ? a.hitHigh : a.hitMid);
            anim.Play(c, 0.03f, 0, Mathf.Max(0.6f, c.Length / Mathf.Max(0.1f, stun / 60f)));
            anim.Flinch(new Vector3(-12, 0, 0), 1f);
        }

        /// <summary>Havoga uchish (juggle). v.x — hujumchidan uzoqlashish tezligi.</summary>
        public void EnterJuggle(Vector2 v, bool sweep)
        {
            float away = opp != null ? Mathf.Sign(pos.x - opp.pos.x) : -facing;
            if (away == 0) away = -facing;
            SetState(FState.Juggle);
            move = null;
            fx.StopTrails();
            gravityMult = 1f + juggleHits * 0.1f * def.juggleWeight;
            vel = new Vector2(away * Mathf.Abs(v.x), v.y);
            if (pos.y < 0.05f) pos.y = 0.05f;
            spinSpeed = sweep ? 0 : -(260f + Random.value * 120f);
            spinAngle = 0;
            anim.Play(sweep ? def.anims.knockFall : def.anims.juggle, 0.04f);
            if (juggleHits > 9) invul = 60;
        }

        public void EnterKnockdownDirect()
        {
            SetState(FState.Knockdown);
            anim.spin = Quaternion.identity;
            anim.Play(def.anims.lying, 0.1f);
            if (isKO) state = FState.KO;
        }

        void OnLand()
        {
            switch (state)
            {
                case FState.Air:
                    SetState(FState.Landing);
                    anim.spin = Quaternion.identity;
                    anim.Play(def.anims.land, 0.04f);
                    vel = Vector2.zero;
                    SynthAudio.Play(Sfx.Land, 0.4f);
                    fx.Dust(0.5f);
                    break;
                case FState.Attack:
                    if (move != null && move.air)
                    {
                        move = null;
                        fx.StopTrails();
                        SetState(FState.Landing);
                        anim.spin = Quaternion.identity;
                        anim.Play(def.anims.land, 0.04f);
                        vel = Vector2.zero;
                        stateFrame = -4; // qo'shimcha qo'nish kechikishi
                    }
                    else vel.y = 0;
                    break;
                case FState.Juggle:
                    anim.spin = Quaternion.identity;
                    spinAngle = 0;
                    SetState(isKO ? FState.KO : FState.Knockdown);
                    anim.Play(def.anims.lying, 0.08f);
                    vel = new Vector2(vel.x * 0.3f, 0);
                    SynthAudio.Play(Sfx.BodyFall, 0.9f);
                    fx.Dust(1.2f);
                    match.cam?.Shake(0.1f);
                    comboHits = 0;
                    juggleHits = 0;
                    match.OnFighterLanded(this);
                    break;
                case FState.Cinematic:
                    vel = Vector2.zero;
                    break;
                default:
                    vel.y = 0;
                    break;
            }
        }

        // ======================= Fizika =======================
        void Physics()
        {
            if (state == FState.Thrown || (state == FState.Cinematic && !cinePhysics)) return;
            float dt = 1f / 60f;
            bool airborne = pos.y > 0.0001f || vel.y > 0;
            if (airborne) vel.y -= FightConst.Gravity * gravityMult * dt;
            pos += vel * dt;
            if (pos.y <= 0 && airborne && vel.y <= 0)
            {
                pos.y = 0;
                OnLand();
                if (pos.y <= 0 && vel.y < 0) vel.y = 0;
            }
            if (state == FState.Juggle)
            {
                anim.spin = Quaternion.Euler(spinAngle, 0, 0);
            }
        }

        void UpdateFacingIfAllowed()
        {
            if (opp == null) return;
            if (!(IsNeutral || state == FState.Landing || state == FState.Intro || state == FState.Dizzy || (state == FState.Attack && moveFrame <= 1 && Grounded))) return;
            if (!Grounded) return;
            float dx = opp.pos.x - pos.x;
            if (Mathf.Abs(dx) < 0.05f) return;
            int f = dx > 0 ? 1 : -1;
            if (f != facing) { facing = f; ApplyFacing(); }
        }

        public void FaceOpponentNow()
        {
            if (opp == null) return;
            float dx = opp.pos.x - pos.x;
            if (Mathf.Abs(dx) > 0.01f) facing = dx > 0 ? 1 : -1;
            ApplyFacing();
        }

        public void SetFacing(int f) { facing = f; ApplyFacing(); }

        void ApplyFacing()
        {
            if (rig == null) return;
            float h = rig.shape.height;
            rig.model.localScale = new Vector3(h, h, facing > 0 ? h : -h);
        }

        // ======================= Hitbox / Hurtbox =======================
        public Rect HurtBox()
        {
            float s = rig != null ? rig.shape.height : 1f;
            if (state == FState.Knockdown || state == FState.KO) return new Rect(pos.x - 0.8f, pos.y, 1.6f, 0.4f);
            if (crouching || state == FState.Crouch || state == FState.CrouchBlock) return new Rect(pos.x - 0.36f, pos.y, 0.72f, 1.15f * s);
            if (!Grounded) return new Rect(pos.x - 0.35f, pos.y + 0.25f, 0.7f, 1.45f * s);
            return new Rect(pos.x - 0.33f, pos.y, 0.66f, 1.85f * s);
        }

        public bool GetActiveHitbox(out Rect world, out int hitIdx)
        {
            world = default;
            hitIdx = -1;
            if (state != FState.Attack || move == null || !move.HasHitbox || move.isThrow) return false;
            int f = moveFrame - move.startup;
            if (f < 0 || f >= move.active) return false;
            int idx = move.hits > 1 ? Mathf.Min(move.hits - 1, f / Mathf.Max(1, move.hitInterval)) : 0;
            if (idx <= lastHitIdx) return false;
            hitIdx = idx;
            world = LocalToWorldRect(move.hitbox);
            return true;
        }

        public Rect LocalToWorldRect(Rect r)
        {
            float x0 = facing > 0 ? pos.x + r.xMin : pos.x - r.xMax;
            return new Rect(x0, pos.y + r.yMin, r.width, r.height);
        }

        public void MarkHit(int idx, bool hit)
        {
            lastHitIdx = idx;
            moveConnected = true;
            if (hit) moveHit = true;
        }

        public bool InCounterWindow => state == FState.Attack && move != null && move.counterStart >= 0 && moveFrame >= move.counterStart && moveFrame <= move.counterEnd;
        public bool InReflectWindow => state == FState.Attack && move != null && move.reflectStart >= 0 && moveFrame >= move.reflectStart && moveFrame <= move.reflectEnd;
        public bool HasArmor => state == FState.Attack && move != null && move.armorStart >= 0 && moveFrame >= move.armorStart && moveFrame <= move.armorEnd;
        public bool ProjectileInvul => state == FState.Attack && move != null && move.projectileInvulStart >= 0 && moveFrame >= move.projectileInvulStart && moveFrame <= move.projectileInvulEnd;
        public bool InStartup => state == FState.Attack && move != null && moveFrame < move.startup;

        // ======================= Kinematik boshqaruv =======================
        public void EnterCinematic(AnimClip clip = null, float fade = 0.08f)
        {
            SetState(FState.Cinematic);
            move = null;
            vel = Vector2.zero;
            fx.StopTrails();
            if (clip != null) anim.Play(clip, fade);
        }

        public void PlayVictory()
        {
            SetState(FState.Victory);
            vel = Vector2.zero;
            move = null;
            anim.spin = Quaternion.identity;
            anim.Play(def.anims.victory, 0.2f);
        }

        public void EnterDizzy()
        {
            SetState(FState.Dizzy);
            move = null;
            vel = Vector2.zero;
            anim.spin = Quaternion.identity;
            anim.Play(def.anims.dizzy, 0.25f);
            canFinish = true;
        }

        // ======================= Vizual yangilash =======================
        void Update()
        {
            if (rig == null) return;
            float alpha = Time.fixedDeltaTime > 0 ? Mathf.Clamp01((Time.time - Time.fixedTime) / Time.fixedDeltaTime) : 1f;
            Vector2 p = hitstop > 0 ? pos : Vector2.Lerp(prevPos, pos, alpha);
            transform.position = new Vector3(p.x, p.y, 0);
            anim.paused = hitstop > 0;
            bool groundedState = Grounded && state != FState.Juggle && state != FState.Thrown &&
                                 !(state == FState.Attack && move != null && (move.air || !anim.Current.grounded)) && state != FState.Air && state != FState.Cinematic;
            anim.groundLock = groundedState || (state == FState.Cinematic && cineGroundLock && Grounded);
            anim.groundY = 0;
            anim.Tick(Time.deltaTime);
            fx.Tick();
        }

        public bool cineGroundLock = true;
        public bool cinePhysics;
    }
}
