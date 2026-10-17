using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public enum GameMode { Arcade, Versus, Training, Watch }

    public enum MatchPhase { Intro, RoundStart, Fight, KO, FinishHim, Cinematic, RoundEnd, MatchEnd, TimeUp }

    /// <summary>
    /// Jang boshqaruvchisi: raundlar, taymer, KO, "TUGAT UNI!", yakuniy zarba, super kinematikasi,
    /// snaryadlar va kombo statistikasi.
    /// </summary>
    public class MatchController : MonoBehaviour
    {
        public Fighter f1, f2;
        public FightCamera cam;
        public Arena arena;
        public GameMode mode;
        public MatchPhase phase;
        public int round = 1;
        public int roundsToWin = 2;
        public float timer = 99;
        int timerFrames;
        public readonly List<Projectile> projectiles = new List<Projectile>();
        public bool FightActive => phase == MatchPhase.Fight || phase == MatchPhase.FinishHim;
        public bool paused;

        // UI hodisalari
        public struct Announcement { public string text; public float time, duration; public Color color; public bool big; }
        public readonly List<Announcement> announcements = new List<Announcement>();
        public float flashTime, flashDur;
        public Color flashColor;
        public float darken;      // super paytida ekran qorong'ilashuvi
        public int comboDisplayHits; public Fighter comboOwner; public float comboTimer; public float comboDamage;
        public string winnerText, winnerQuote;
        public bool matchOver;
        public Fighter matchWinner;
        public System.Action<MatchController> onMatchOver;
        public bool finisherDone;
        public string finisherTitle;

        Fighter finishTarget;      // "TUGAT UNI!" — kim
        Fighter finishWinner;
        float finishTimer;
        Fighter pendingKO;
        bool koResolving;
        float slowmoUntil = -1, slowmoScale = 1;
        float freezeUntil = -1;

        public static MatchController Create(FighterDefinition d1, FighterDefinition d2, IInputSource in1, IInputSource in2, GameMode mode, Arena arena, FightCamera cam)
        {
            var go = new GameObject("Match");
            var m = go.AddComponent<MatchController>();
            m.mode = mode;
            m.arena = arena;
            m.cam = cam;
            m.f1 = MakeFighter(d1, 0, in1, m);
            m.f2 = MakeFighter(d2, 1, in2, m);
            m.f1.opp = m.f2; m.f2.opp = m.f1;
            if (mode == GameMode.Training) { m.f2.training = true; m.f1.training = true; }
            cam.a = m.f1; cam.b = m.f2;
            return m;
        }

        static Fighter MakeFighter(FighterDefinition d, int idx, IInputSource input, MatchController m)
        {
            var go = new GameObject("Fighter_" + d.id + "_" + idx);
            go.transform.SetParent(m.transform, false);
            var f = go.AddComponent<Fighter>();
            f.Setup(d, idx, input, m);
            return f;
        }

        public void Begin()
        {
            Time.fixedDeltaTime = 1f / 60f;
            round = 1;
            firstHitDone = false;
            f1.roundsWon = f2.roundsWon = 0;
            f1.meter = f2.meter = mode == GameMode.Training ? FightConst.MaxMeter : 0;
            StartCoroutine(RoundIntro(true));
            SynthAudio.I?.PlayMusic("battle");
        }

        // ======================= Raund oqimi =======================
        IEnumerator RoundIntro(bool first)
        {
            phase = MatchPhase.Intro;
            ClearProjectiles();
            f1.ResetForRound(-2.4f, 1);
            f2.ResetForRound(2.4f, -1);
            f1.rig.gameObject.SetActive(true); f2.rig.gameObject.SetActive(true);
            f1.inputEnabled = f2.inputEnabled = false;
            timer = mode == GameMode.Training ? 99 : 99;
            timerFrames = 0;
            finishTarget = null; finishWinner = null; pendingKO = null; koResolving = false; finisherDone = false;
            arena?.SetDarkSky(false);
            Time.timeScale = 1f;
            if (mode == GameMode.Training)
            {
                cam.SnapFight();
                phase = MatchPhase.Fight;
                f1.inputEnabled = f2.inputEnabled = true;
                Announce("MASHQ", 1.2f, Pal.Gold, true);
                yield break;
            }
            if (first)
            {
                f1.state = FState.Intro; f2.state = FState.Intro;
                f1.anim.Play(f1.def.anims.intro, 0.05f);
                f2.anim.Play(f2.def.anims.cinematicHold, 0.05f);
                cam.Cut(new Vector3(-2.4f + 1.4f, 1.5f, -3.2f), new Vector3(-2.4f, 1.35f, 0), 34);
                cam.Shot(new Vector3(-2.4f + 0.9f, 1.6f, -2.7f), new Vector3(-2.4f, 1.45f, 0), 32, 2.2f);
                Announce(f1.def.name, 2.0f, f1.def.mainColor.Mul(1.6f), false);
                Say(f1, f2);
                SynthAudio.Play(Sfx.Gong, 0.7f);
                yield return new WaitForSeconds(2.2f);
                f2.anim.Play(f2.def.anims.intro, 0.05f);
                f1.anim.Play(f1.def.anims.idle, 0.2f);
                cam.Cut(new Vector3(2.4f - 1.4f, 1.5f, -3.2f), new Vector3(2.4f, 1.35f, 0), 34);
                cam.Shot(new Vector3(2.4f - 0.9f, 1.6f, -2.7f), new Vector3(2.4f, 1.45f, 0), 32, 2.2f);
                Announce(f2.def.name, 2.0f, f2.def.mainColor.Mul(1.6f), false);
                Say(f2, f1);
                SynthAudio.Play(Sfx.Gong, 0.7f, 1.1f);
                yield return new WaitForSeconds(2.2f);
                arena?.Cheer(1f);
                SynthAudio.Play(Sfx.CrowdBig, 0.5f);
            }
            f1.state = FState.Idle; f2.state = FState.Idle;
            f1.anim.Play(f1.def.anims.idle, 0.2f); f2.anim.Play(f2.def.anims.idle, 0.2f);
            if (first) cam.Shot(new Vector3(0, 1.9f, -8.4f), new Vector3(0, 1.4f, 0), 34, 0.8f);
            else cam.Cut(new Vector3(0, 1.9f, -8.4f), new Vector3(0, 1.4f, 0), 34);
            phase = MatchPhase.RoundStart;
            yield return new WaitForSeconds(0.6f);
            Announce(round == 1 ? "1-RAUND" : round == 2 ? "2-RAUND" : (f1.roundsWon == 1 && f2.roundsWon == 1 ? "HAL QILUVCHI RAUND" : round + "-RAUND"), 1.3f, Pal.Gold, true);
            SynthAudio.Play(Sfx.DrumRoll, 0.8f);
            yield return new WaitForSeconds(1.4f);
            Announce("JANG!", 0.9f, new Color(1f, 0.35f, 0.25f), true);
            SynthAudio.Play(Sfx.Gong, 1f, 1.2f);
            arena?.Cheer(0.7f);
            cam.FightMode();
            phase = MatchPhase.Fight;
            f1.inputEnabled = f2.inputEnabled = true;
        }

        void FixedUpdate()
        {
            if (paused) return;
            if (phase == MatchPhase.Cinematic)
            {
                f1.Tick(); f2.Tick();
                TickProjectiles();
                return;
            }
            f1.Tick();
            f2.Tick();
            if (phase == MatchPhase.Fight || phase == MatchPhase.FinishHim || phase == MatchPhase.KO || phase == MatchPhase.TimeUp)
            {
                PushApart();
                TickProjectiles();
                CombatResolver.Resolve(this);
            }
            else PushApart();
            ClampStage();

            if (phase == MatchPhase.Fight)
            {
                if (mode != GameMode.Training)
                {
                    if (++timerFrames >= 60)
                    {
                        timerFrames = 0;
                        timer = Mathf.Max(0, timer - 1);
                        if (timer <= 0) StartCoroutine(TimeUp());
                    }
                }
                else TrainingTick();
                CheckFinishPhase();
            }
            else if (phase == MatchPhase.FinishHim)
            {
                FinishHimTick();
            }
            if (comboTimer > 0) comboTimer -= 1f / 60f;
        }

        void TickProjectiles()
        {
            foreach (var p in projectiles) if (p != null && !p.dead) p.Tick();
            projectiles.RemoveAll(p => p == null || p.dead);
        }

        void ClearProjectiles()
        {
            foreach (var p in projectiles) if (p) Destroy(p.gameObject);
            projectiles.Clear();
        }

        void Update()
        {
            // Sekinlashtirish va muzlatish (real vaqt bo'yicha)
            if (!paused)
            {
                float now = Time.unscaledTime;
                float ts = 1f;
                if (now < freezeUntil) ts = 0.02f;
                else if (now < slowmoUntil) ts = slowmoScale;
                if (Mathf.Abs(Time.timeScale - ts) > 0.001f) Time.timeScale = ts;
                SynthAudio.I?.SetMusicPitch(ts < 0.9f ? Mathf.Lerp(0.85f, 1f, ts) : 1f);
            }
            darken = Mathf.MoveTowards(darken, phase == MatchPhase.Cinematic ? 0.35f : 0f, Time.unscaledDeltaTime * 2f);
        }

        // ======================= Fizik cheklovlar =======================
        void PushApart()
        {
            if (!Collidable(f1) || !Collidable(f2)) return;
            float dx = f2.pos.x - f1.pos.x;
            float overlap = FightConst.PushWidth * 2f * 0.5f - Mathf.Abs(dx);
            float yOverlap = Mathf.Min(f1.pos.y + 1.6f, f2.pos.y + 1.6f) - Mathf.Max(f1.pos.y, f2.pos.y);
            if (overlap > 0 && yOverlap > 0.2f)
            {
                float dir = dx == 0 ? (f1.facing > 0 ? 1 : -1) : Mathf.Sign(dx);
                float w = FightConst.StageHalfWidth - 0.3f;
                bool f1Wall = Mathf.Abs(f1.pos.x) >= w - 0.01f && Mathf.Sign(f1.pos.x) == -dir;
                bool f2Wall = Mathf.Abs(f2.pos.x) >= w - 0.01f && Mathf.Sign(f2.pos.x) == dir;
                float s1 = f1Wall ? 0 : f2Wall ? 1 : 0.5f;
                f1.pos.x -= dir * overlap * s1;
                f2.pos.x += dir * overlap * (1 - s1);
            }
        }

        static bool Collidable(Fighter f) => f.state != FState.Thrown && f.state != FState.Throwing && f.state != FState.Cinematic && f.state != FState.Knockdown && f.state != FState.KO && f.rig.gameObject.activeSelf;

        void ClampStage()
        {
            float w = FightConst.StageHalfWidth - 0.3f;
            foreach (var f in new[] { f1, f2 })
            {
                if (f.state == FState.Cinematic) continue;
                f.pos.x = Mathf.Clamp(f.pos.x, -w, w);
            }
            // Kamera masofasi chegarasi
            float sep = f2.pos.x - f1.pos.x;
            if (Mathf.Abs(sep) > FightConst.MaxSeparation && f1.state != FState.Cinematic && f2.state != FState.Cinematic)
            {
                float excess = (Mathf.Abs(sep) - FightConst.MaxSeparation) * 0.5f * Mathf.Sign(sep);
                f1.pos.x += excess; f2.pos.x -= excess;
            }
        }

        // ======================= Hodisalar =======================
        public Projectile SpawnProjectile(ProjectileSpec spec, Fighter owner, Vector2 pos, Vector2 vel)
        {
            if (owner != null && owner.enhanced && spec.damage > 0)
            {
                spec.damage *= 1.35f;
                spec.hitstun += 6;
                spec.color = Color.Lerp(spec.color, Color.white, 0.35f);
                spec.size *= 1.15f;
                vel *= 1.25f;
            }
            var p = Projectile.Spawn(spec, owner, pos, vel);
            p.transform.SetParent(transform, true);
            projectiles.Add(p);
            return p;
        }

        /// <summary>Jang oldidan qahramon gapi (subtitr).</summary>
        public string subtitle; public float subtitleTime; public Color subtitleColor;
        public void Subtitle(string text, Color c) { subtitle = text; subtitleTime = Time.unscaledTime; subtitleColor = c; }

        void Say(Fighter who, Fighter to)
        {
            string line = who.def.vsLines.TryGetValue(to.def.id, out var l) ? l : who.def.introLine;
            if (!string.IsNullOrEmpty(line)) Subtitle("«" + line + "»", who.def.mainColor.Mul(1.6f));
        }

        public void Announce(string text, float dur, Color c, bool big = false)
        {
            announcements.Add(new Announcement { text = text, time = Time.unscaledTime, duration = dur, color = c, big = big });
            if (announcements.Count > 6) announcements.RemoveAt(0);
        }

        public void ScreenFlash(Color c, float dur) { flashColor = c; flashTime = Time.unscaledTime; flashDur = dur; }

        public void HitStopVisual(float seconds) { freezeUntil = Mathf.Max(freezeUntil, Time.unscaledTime + seconds); }

        public void SlowMo(float scale, float seconds) { slowmoScale = scale; slowmoUntil = Time.unscaledTime + seconds; }

        public void SetDarkSky(bool on) => arena?.SetDarkSky(on);
        public void Lightning(Vector3 at) => arena?.Lightning(at);

        public void OnSuperStart(Fighter f)
        {
            HitStopVisual(0.4f);
            ScreenFlash(f.def.energyColor, 0.35f);
            SynthAudio.Play(Sfx.Gong, 0.8f, 1.3f);
            cam.zoomPunch = 1.2f;
            VFX.Burst(f.rig.Pos(Bone.Chest), f.def.energyColor, 0.8f);
        }

        public void OnSpecialStart(Fighter f, MoveData m) { }

        public void OnBreaker(Fighter f)
        {
            Announce("UZISH!", 0.9f, new Color(0.5f, 0.9f, 1f), true);
            ScreenFlash(new Color(0.6f, 0.9f, 1f), 0.25f);
            SynthAudio.Play(Sfx.Clang, 1f, 0.7f);
            VFX.Burst(f.rig.Pos(Bone.Chest), new Color(0.6f, 0.9f, 1f), 1f);
            HitStopVisual(0.25f);
            cam.Shake(0.3f);
        }

        public void OnBlock(Fighter att, Fighter def) { }

        bool firstHitDone;
        static readonly (int hits, string text)[] Praise = { (4, "YAXSHI!"), (6, "AJOYIB!"), (9, "AFSONAVIY!"), (12, "SOHIBQIRONA!") };

        public void OnHitLanded(Fighter att, Fighter def, MoveData m, bool counter, float dmg)
        {
            if (!firstHitDone && mode != GameMode.Training && phase == MatchPhase.Fight)
            {
                firstHitDone = true;
                Announce("BIRINCHI ZARBA!", 1.1f, new Color(1f, 0.55f, 0.3f));
                att.meter = Mathf.Min(FightConst.MaxMeter, att.meter + 25);
            }
            foreach (var pr in Praise)
                if (def.comboHits == pr.hits) { Announce(pr.text, 0.9f, Color.Lerp(Pal.Gold, Color.white, pr.hits / 14f)); SynthAudio.Play(Sfx.Crowd, 0.35f + pr.hits * 0.03f); }
            if (m.hitstop >= 9 || dmg >= 90) cam.Punch(0.35f);
            if (def.comboHits >= 2)
            {
                comboOwner = att;
                comboDisplayHits = def.comboHits;
                comboDamage = def.comboDamage;
                comboTimer = 1.6f;
                if (def.comboHits == 5) arena?.Cheer(0.6f);
                if (def.comboHits == 8) { arena?.Cheer(1f); SynthAudio.Play(Sfx.Crowd, 0.6f); }
            }
            if (counter && m.kind != MoveKind.Special) Announce("QARSHI ZARBA!", 0.6f, new Color(1f, 0.6f, 0.3f));
        }

        public void OnThrowLanded(Fighter att, Fighter def) { arena?.Cheer(0.5f); cam.Punch(0.4f); }

        /// <summary>Majaqlovchi zarba: sekinlashuv, kamera yaqinlashuvi, rangsizlanish va nur.</summary>
        public void OnKrushingBlow(Fighter att, Fighter def, Vector3 point)
        {
            Announce("MAJAQLOVCHI ZARBA!", 1.4f, new Color(1f, 0.3f, 0.2f), true);
            SlowMo(0.12f, 0.75f);
            cam.Punch(1.6f);
            cam.Shake(0.6f);
            if (cam.post) { cam.post.Kick(3f); StartCoroutine(Desat(0.7f)); }
            SynthAudio.Play(Sfx.Shatter, 0.9f, 0.8f);
            SynthAudio.Play(Sfx.HitHeavy, 1f, 0.7f);
            VFX.Burst(point, new Color(1f, 0.5f, 0.3f), 1.2f);
            def.flashTimer = 0.4f; def.flashColor = new Color(1f, 0.85f, 0.7f);
            arena?.Cheer(1f);
        }

        IEnumerator Desat(float seconds)
        {
            float t = 0;
            while (t < seconds)
            {
                t += Time.unscaledDeltaTime;
                if (cam.post) cam.post.desaturate = 0.75f * (1 - t / seconds);
                yield return null;
            }
            if (cam.post) cam.post.desaturate = 0;
        }

        // ======================= KO =======================
        public void OnKO(Fighter loser, Fighter winner)
        {
            if (mode == GameMode.Training) { loser.health = 1; return; }
            if (phase == MatchPhase.Cinematic) { pendingKO = loser; return; }
            if (phase != MatchPhase.Fight && phase != MatchPhase.FinishHim) return;
            if (phase == MatchPhase.FinishHim) return; // dizzy holatda — boshqacha
            bool final = winner.roundsWon + 1 >= roundsToWin;
            if (final && winner.def.finisherScript != null)
            {
                // "TUGAT UNI!" fazasiga tayyorlanish
                finishTarget = loser;
                finishWinner = winner;
                loser.health = 0;
                loser.inputEnabled = false;
                SlowMo(0.35f, 0.6f);
                return;
            }
            loser.isKO = true;
            koResolving = true;
            phase = MatchPhase.KO;
            SlowMo(0.25f, 1.2f);
            cam.Punch(1.2f);
            if (cam.post) StartCoroutine(Desat(1.3f));
            ScreenFlash(Color.white, 0.2f);
            SynthAudio.Play(Sfx.Boom, 0.8f, 0.8f);
            f1.inputEnabled = f2.inputEnabled = false;
            StartCoroutine(KOSequence(loser, winner));
        }

        IEnumerator KOSequence(Fighter loser, Fighter winner)
        {
            // Yiqilguncha kutish
            float t = 0;
            while (loser.state != FState.KO && t < 4f) { t += Time.unscaledDeltaTime; yield return null; }
            yield return new WaitForSeconds(0.5f);
            yield return RoundWon(winner, loser, false);
        }

        public void OnFighterLanded(Fighter f) { }

        void CheckFinishPhase()
        {
            if (finishTarget == null) return;
            var l = finishTarget;
            // Zarba reaksiyasi tugagach "dizzy" holatga o'tadi
            if (l.state == FState.Idle || l.state == FState.Crouch || l.state == FState.Walk || l.state == FState.Block || l.state == FState.CrouchBlock || l.state == FState.Landing)
            {
                l.EnterDizzy();
                l.inputEnabled = false;
                phase = MatchPhase.FinishHim;
                finishTimer = 7f;
                Announce("TUGAT UNI!", 2.2f, new Color(1f, 0.25f, 0.2f), true);
                SynthAudio.Play(Sfx.Gong, 1f, 0.75f);
                SynthAudio.Play(Sfx.Heartbeat, 0.8f);
                arena?.SetDarkSky(true);
                ClearProjectiles();
            }
        }

        void FinishHimTick()
        {
            var w = finishWinner; var l = finishTarget;
            finishTimer -= 1f / 60f;
            if (Mathf.FloorToInt(finishTimer * 60) % 50 == 0) SynthAudio.Play(Sfx.Heartbeat, 0.5f);
            // Yakuniy zarba kombinatsiyasi
            var fin = w.def.finisherInput;
            if (fin != null && w.IsNeutral)
            {
                int ago = w.FreshPress(fin.button, 4);
                if (ago >= 0 && w.buf.MatchMotion(fin.motion, ago, 40))
                {
                    StartFinisher(w, l);
                    return;
                }
            }
            if (w is Fighter && w.input is FighterAI ai && ai.WantsFinisher())
            {
                StartFinisher(w, l);
                return;
            }
            // Oddiy zarba bilan yiqitish
            if (l.state == FState.Juggle || l.state == FState.KO || l.state == FState.Knockdown)
            {
                l.isKO = true;
                if (!koResolving)
                {
                    koResolving = true;
                    phase = MatchPhase.KO;
                    w.inputEnabled = false;
                    arena?.SetDarkSky(false);
                    SlowMo(0.3f, 1f);
                    StartCoroutine(KOSequence(l, w));
                }
                return;
            }
            if (finishTimer <= 0)
            {
                l.isKO = true;
                l.EnterJuggle(new Vector2(0.5f, 3f), true);
                koResolving = true;
                phase = MatchPhase.KO;
                w.inputEnabled = false;
                arena?.SetDarkSky(false);
                StartCoroutine(KOSequence(l, w));
            }
        }

        void StartFinisher(Fighter w, Fighter l)
        {
            finisherDone = true;
            w.inputEnabled = false;
            StartCinematic(w, l, w.def.finisherScript, true);
        }

        IEnumerator TimeUp()
        {
            phase = MatchPhase.TimeUp;
            f1.inputEnabled = f2.inputEnabled = false;
            Announce("VAQT TUGADI!", 1.5f, Pal.Gold, true);
            SynthAudio.Play(Sfx.Gong, 1f);
            yield return new WaitForSeconds(1.6f);
            Fighter w = f1.health > f2.health ? f1 : f2.health > f1.health ? f2 : null;
            if (w == null)
            {
                Announce("DURRANG", 1.5f, Color.white, true);
                yield return new WaitForSeconds(1.8f);
                round++;
                StartCoroutine(RoundIntro(false));
                yield break;
            }
            var l = w.opp;
            l.EnterCinematic(l.def.anims.defeat, 0.3f);
            yield return RoundWon(w, l, false);
        }

        IEnumerator RoundWon(Fighter w, Fighter l, bool viaFinisher)
        {
            phase = MatchPhase.RoundEnd;
            Time.timeScale = 1f;
            slowmoUntil = -1;
            f1.inputEnabled = f2.inputEnabled = false;
            w.roundsWon++;
            bool flawless = w.health >= w.maxHealth - 0.5f;
            yield return new WaitForSeconds(0.4f);
            if (w.state != FState.Cinematic || viaFinisher) w.PlayVictory();
            arena?.Cheer(1f);
            SynthAudio.Play(Sfx.CrowdBig, 0.7f);
            if (!viaFinisher) Announce(w.def.name + " G'OLIB", 2.2f, w.def.mainColor.Mul(1.7f), true);
            if (flawless && !viaFinisher) { yield return new WaitForSeconds(0.9f); Announce("MUKAMMAL G'ALABA!", 1.8f, Pal.Gold, true); }
            cam.Shot(w.rig.Pos(Bone.Chest) + new Vector3(-w.facing * -1.8f, 0.3f, -3.4f), w.rig.Pos(Bone.Chest) + Vector3.up * 0.4f, 34, 1.4f);
            yield return new WaitForSeconds(2.6f);
            if (w.roundsWon >= roundsToWin)
            {
                phase = MatchPhase.MatchEnd;
                matchOver = true;
                matchWinner = w;
                winnerText = w.def.name;
                winnerQuote = w.def.winLines != null && w.def.winLines.Length > 0 ? "«" + w.def.winLines[Random.Range(0, w.def.winLines.Length)] + "»" : w.def.quote;
                cam.Orbit(w.rig.Pos(Bone.Chest), 4.2f, 0.4f, 9f, -90f + (w.facing > 0 ? 20 : -20), 34f);
                onMatchOver?.Invoke(this);
                yield break;
            }
            round++;
            StartCoroutine(RoundIntro(false));
        }

        // ======================= Kinematika =======================
        public void StartCinematic(Fighter a, Fighter d, System.Func<CineContext, List<CineStep>> script, bool finisher)
        {
            if (script == null) return;
            StartCoroutine(RunCinematic(a, d, script, finisher));
        }

        IEnumerator RunCinematic(Fighter a, Fighter d, System.Func<CineContext, List<CineStep>> script, bool finisher)
        {
            var prevPhase = phase;
            phase = MatchPhase.Cinematic;
            ClearProjectiles();
            Time.timeScale = 1f;
            slowmoUntil = -1; freezeUntil = -1;
            a.EnterCinematic(); d.EnterCinematic(d.def.anims.hitMid, 0.05f);
            a.cinePhysics = d.cinePhysics = false;
            a.cineGroundLock = d.cineGroundLock = true;
            a.hitstop = d.hitstop = 0;
            a.anim.spin = Quaternion.identity; d.anim.spin = Quaternion.identity;
            d.pos.y = 0;
            a.pos.y = 0;
            var ctx = new CineContext { attacker = a, defender = d, match = this, cam = cam };
            var steps = script(ctx);
            steps.Sort((x, y) => x.time.CompareTo(y.time));
            float t = 0;
            int i = 0;
            float end = steps.Count > 0 ? steps[steps.Count - 1].time + 0.3f : 0.5f;
            while (t <= end)
            {
                while (i < steps.Count && steps[i].time <= t)
                {
                    try { steps[i].action(ctx); } catch (System.Exception e) { Debug.LogException(e); }
                    i++;
                }
                yield return null;
                t += Time.deltaTime;
            }
            a.cinePhysics = d.cinePhysics = false;
            a.cineGroundLock = d.cineGroundLock = true;
            a.fx.aura = 0;
            a.fx.StopTrails();
            if (a.rig.weaponBaseR) a.rig.weaponBaseR.parent.gameObject.SetActive(true);
            var props = a.rig.GetComponent<CharacterProps>();
            props?.Show("bowHand", false); props?.Show("bowBack", true);
            arena?.SetDarkSky(false);

            if (finisher)
            {
                Announce(a.def.finisherName, 2.4f, new Color(1f, 0.3f, 0.2f), true);
                SynthAudio.Play(Sfx.Gong, 1f, 0.7f);
                finisherTitle = a.def.finisherName;
                d.isKO = true;
                yield return new WaitForSeconds(1.2f);
                yield return RoundWon(a, d, true);
                yield break;
            }

            // Super tugadi: himoyachi yiqilgan holatda
            a.pos.y = 0; d.pos.y = 0;
            a.ToNeutral();
            if (pendingKO == d || d.health <= 0)
            {
                pendingKO = null;
                phase = MatchPhase.Fight;
                bool final = a.roundsWon + 1 >= roundsToWin;
                d.health = 0;
                if (final && a.def.finisherScript != null)
                {
                    finishTarget = d; finishWinner = a;
                    d.state = FState.Knockdown; d.anim.Play(d.def.anims.lying, 0.1f);
                    // tez orada turib "dizzy" bo'ladi
                    yield break;
                }
                d.isKO = true;
                d.EnterKnockdownDirect();
                phase = MatchPhase.KO;
                koResolving = true;
                StartCoroutine(KOSequence(d, a));
                yield break;
            }
            d.EnterKnockdownDirect();
            phase = prevPhase == MatchPhase.Cinematic ? MatchPhase.Fight : prevPhase;
            if (phase != MatchPhase.Fight && phase != MatchPhase.FinishHim) phase = MatchPhase.Fight;
            cam.FightMode();
        }

        // Ulug'bek effektlari
        public void Orrery(Fighter target, float duration, Color c) => StartCoroutine(OrreryRoutine(target, duration, c));

        IEnumerator OrreryRoutine(Fighter target, float duration, Color c)
        {
            var root = new GameObject("Orrery").transform;
            var rings = new List<Transform>();
            for (int i = 0; i < 3; i++)
            {
                var mb = new MeshBuilder();
                mb.SetColor(Color.white).Torus(Vector3.zero, 0.9f + i * 0.25f, 0.025f, 40, 4);
                var go = mb.Build("ring" + i, root, Mat.Toon(Color.white, null, 0.3f, c * 1.5f), false);
                rings.Add(go.transform);
                var pl = new MeshBuilder();
                pl.SetColor(Color.white).Sphere(new Vector3(0.9f + i * 0.25f, 0, 0), 0.09f, 6, 8);
                pl.Build("planet" + i, go.transform, Mat.Toon(Color.white, null, 0.3f, Color.Lerp(c, Pal.Gold, i * 0.4f) * 1.6f), false);
            }
            float t = 0;
            while (t < duration && target)
            {
                root.position = target.rig.Pos(Bone.Chest);
                for (int i = 0; i < rings.Count; i++)
                    rings[i].localRotation = Quaternion.Euler(60 * i + t * (90 + i * 40), t * (120 - i * 30), 30 * i);
                if (Random.value < 0.4f) VFX.Emit(VFX.Kind.Star, root.position + Random.insideUnitSphere * 1.2f, c, 1, 0.3f, 0.25f, 0.5f, Vector3.up, 1f);
                t += Time.deltaTime;
                yield return null;
            }
            Destroy(root.gameObject);
        }

        public void FloatFighter(Fighter f, float height, float duration) => StartCoroutine(FloatRoutine(f, height, duration));

        IEnumerator FloatRoutine(Fighter f, float h, float dur)
        {
            float t = 0; float y0 = f.pos.y;
            f.cineGroundLock = false;
            while (t < dur)
            {
                t += Time.deltaTime;
                float k = Mathf.SmoothStep(0, 1, t / dur);
                f.pos.y = Mathf.Lerp(y0, h, k);
                f.prevPos = f.pos;
                f.anim.spin = Quaternion.Euler(-k * 40, k * 200, 0);
                yield return null;
            }
        }

        public void Constellation(Vector3 at)
        {
            var go = new GameObject("Constellation");
            var lr = go.AddComponent<LineRenderer>();
            Vector3[] pts =
            {
                at + new Vector3(-1.6f, 0.2f, 0), at + new Vector3(-0.8f, 0.9f, 0), at + new Vector3(0, 0.5f, 0), at + new Vector3(0.6f, 1.3f, 0),
                at + new Vector3(1.4f, 0.8f, 0), at + new Vector3(0.9f, -0.2f, 0), at + new Vector3(0, 0.5f, 0)
            };
            lr.positionCount = pts.Length;
            lr.SetPositions(pts);
            lr.widthMultiplier = 0.035f;
            lr.material = Mat.Additive(TextureFactory.SoftDot(), Color.white);
            lr.startColor = lr.endColor = new Color(0.7f, 0.85f, 1f, 0.9f);
            foreach (var p in pts) VFX.Emit(VFX.Kind.Star, p, new Color(0.85f, 0.9f, 1f), 2, 0.1f, 0.5f, 3f, Vector3.zero, 0.1f);
            Destroy(go, 3.5f);
        }

        // ======================= Mashq rejimi =======================
        void TrainingTick()
        {
            foreach (var f in new[] { f1, f2 })
            {
                if (f.IsNeutral && f.stateFrame > 40 && f.health < f.maxHealth) f.health = f.displayHealth = f.maxHealth;
                f.meter = FightConst.MaxMeter;
            }
        }

        public void Pause(bool p)
        {
            paused = p;
            Time.timeScale = p ? 0f : 1f;
            if (!p) { slowmoUntil = -1; freezeUntil = -1; }
        }

        public void Cleanup()
        {
            Time.timeScale = 1f;
            ClearProjectiles();
            Destroy(gameObject);
        }
    }
}
