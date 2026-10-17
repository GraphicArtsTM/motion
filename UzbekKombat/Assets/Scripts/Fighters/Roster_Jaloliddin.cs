using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public static partial class Roster
    {
        public static FighterDefinition Jaloliddin()
        {
            var d = new FighterDefinition
            {
                id = "jaloliddin", name = "JALOLIDDIN MANGUBERDI", title = "Xorazm sheri", years = "1199 — 1231",
                bio = "Xorazmshohlar davlatining so'nggi sultoni. Mo'g'ul bosqiniga qarshi taslim bo'lmagan qahramon; Sind daryosiga ot bilan sakragan.",
                quote = "«Vatan himoyasi — eng oliy burch.»",
                style = "Qo'sh qilich • Tezlik • Uzun kombolar",
                mainColor = Pal.Teal, accentColor = Pal.White, energyColor = new Color(0.45f, 0.95f, 1f),
                walkFwd = 2.9f, walkBack = 2.4f, jumpVel = 12f, jumpX = 3.9f, damageMult = 0.92f, juggleWeight = 0.95f, dashSpeed = 8.4f,
                signatureFx = HitFx.Wind,
            };
            d.buildVisual = t => FbxPuppet.Build("jaloliddin", CharacterVisuals.BuildJaloliddin, t);
            d.bounceAmp = 0.024f; d.bounceRate = 6.8f;
            d.introLine = "Vatan uchun jangga tayyorman!";
            d.vsLines["chingiz"] = "Sind daryosi seni ham kutmoqda, Chingiz!";
            d.vsLines["temur"] = "Sohibqiron, qilichlarimiz bir-birini tanisin.";
            d.vsLines["ulugbek"] = "Yulduzlaring tezligimni o'lchay olarmikan?";
            d.vsLines["jaloliddin"] = "O'zim bilan jang — eng og'ir jang.";
            d.winLines = new[] { "Taslim bo'lmadim, bo'lmayman ham!", "Xorazm sheri hamon tik!", "Tezlik — qalqondan kuchli." };
            var p = PoseLib.Jaloliddin();
            d.anims = PoseLib.BuildBase(p);
            var cfg = new NormalsCfg { reach = 1.08f, power = 0.95f, speed = 1.15f, weaponTrail = Trail.WeaponR, heavyTrail = Trail.WeaponR | Trail.WeaponL, trailColor = new Color(0.6f, 0.95f, 1f, 0.95f) };
            AddNormals(d, p, cfg);
            d.Get("LP2").trails = Trail.WeaponL;

            // --- Zanjirlar: LP, LP, HP, HK (4 zarba) ---
            var str3 = Normal(d, p, "str3", "Qo'sh kesish", "LP, LP, HP", "HP_w", "HP_s", null, 9, 4, 18, 50, HitLevel.Mid, new Rect(0.2f, 0.7f, 1.1f, 1.0f), cfg, true);
            str3.trails = Trail.WeaponR | Trail.WeaponL;
            d.Get("LP2").Chain(Btn.HP, "str3");
            var str4 = Normal(d, p, "str4", "Xorazm tepkisi", "LP, LP, HP, HK", "HK_w", "HK_s", null, 9, 4, 22, 55, HitLevel.High, new Rect(0.2f, 1.0f, 1.05f, 0.6f), cfg, true);
            str4.trails = Trail.FootR; str4.launch = true; str4.knockback = new Vector2(2f, 9f); str4.fx = HitFx.Wind; str4.hitSfx = Sfx.HitHeavy;
            str3.Chain(Btn.HK, "str4");
            var lk2 = Normal(d, p, "lk2", "Ikki tepki", "LK, HK", "HK_w", "HK_s", null, 9, 4, 20, 62, HitLevel.High, new Rect(0.2f, 1.0f, 1.05f, 0.6f), cfg, true);
            lk2.trails = Trail.FootR; lk2.knockdown = true; lk2.knockback = new Vector2(4f, 5f); lk2.fx = HitFx.Blunt; lk2.hitSfx = Sfx.HitHeavy;
            d.Get("LK").Chain(Btn.HK, "lk2");

            // --- Maxsus usullar ---
            ProjectileSpec DaggerSpec() => new ProjectileSpec
            {
                damage = 52, level = HitLevel.High, hitstun = 18, knockback = new Vector2(1.8f, 0), size = new Vector2(0.45f, 0.3f),
                visual = ProjVisual.Dagger, color = new Color(0.7f, 0.95f, 1f), fx = HitFx.Slash, hitSfx = Sfx.Slash, lifetime = 1.4f
            };
            var dagger = Special(d, "dagger", "Xanjar otish", "← → + LP", 11, 1, 19, 0, HitLevel.High, new Rect(0, 0, 0, 0));
            dagger.clip = AnimClip.Attack("dagger", p.stance, p["dagger_w"], p["dagger_s"], 11, 1, 19);
            dagger.trails = Trail.WeaponR;
            dagger.onFrame = (f, fr) =>
            {
                if (fr == 11)
                {
                    f.match.SpawnProjectile(DaggerSpec(), f, f.pos + new Vector2(f.facing * 0.8f, 1.35f), new Vector2(f.facing * 15f, 0));
                    SynthAudio.Play(Sfx.WhooshLight, 0.9f, 1.3f);
                }
            };
            Input(d, "dagger", Btn.LP, B, F);
            var jdagger = Special(d, "jdagger", "Havodan xanjar", "havoda ← → + LP", 9, 1, 14, 0, HitLevel.Overhead, new Rect(0, 0, 0, 0));
            jdagger.air = true; jdagger.airOK = true;
            jdagger.clip = AnimClip.Attack("jdagger", PoseLib.JumpTuck(p.stance), p["dagger_w"], p["dagger_s"], 9, 1, 14, null, false);
            jdagger.onFrame = (f, fr) =>
            {
                if (fr == 9)
                {
                    var s = DaggerSpec(); s.level = HitLevel.Overhead;
                    f.match.SpawnProjectile(s, f, f.pos + new Vector2(f.facing * 0.6f, 0.9f), new Vector2(f.facing * 12f, -7f));
                    SynthAudio.Play(Sfx.WhooshLight, 0.9f, 1.3f);
                    f.vel.y = Mathf.Max(f.vel.y, 2f);
                }
            };
            Input(d, "jdagger", Btn.LP, B, F);

            var whirl = Special(d, "whirl", "Qo'sh qilich girdobi", "← → + HP", 8, 32, 18, 26, HitLevel.Mid, new Rect(-0.3f, 0.5f, 1.4f, 1.2f));
            whirl.hits = 4; whirl.hitInterval = 8; whirl.lastHitLaunch = true; whirl.knockback = new Vector2(1.2f, 0); whirl.hitstun = 20; whirl.blockstun = 10;
            whirl.moveVel = new Vector2(4.5f, 0); whirl.moveStart = 8; whirl.moveEnd = 38; whirl.trails = Trail.WeaponR | Trail.WeaponL; whirl.fx = HitFx.Wind; whirl.hitSfx = Sfx.Slash; whirl.hitstop = 4;
            whirl.clip = new AnimClip("whirl").F(0, p.stance).F(8, p["whirl_s"], Ease.OutQuad).F(40, p["whirl_s"], Ease.Linear).F(58, p.stance, Ease.InOutQuad);
            whirl.onFrame = (f, fr) =>
            {
                if (fr >= 8 && fr <= 40) f.anim.spin = Quaternion.Euler(0, (fr - 8) * 45f * -1, 0);
                if (fr == 41) f.anim.spin = Quaternion.identity;
                if (fr >= 8 && fr <= 40 && fr % 8 == 0) { SynthAudio.Play(Sfx.WhooshHeavy, 0.7f, 1.2f); VFX.Emit(VFX.Kind.Ring, new Vector3(f.pos.x, 1.1f, 0), new Color(0.5f, 1f, 1f, 0.6f), 1, 0, 2.2f, 0.25f, default, 0); }
            };
            whirl.onEnd = f => f.anim.spin = Quaternion.identity;
            Input(d, "whirl", Btn.HP, B, F);

            var leap = Special(d, "leap", "Sind sakrashi", "↓ → + HK", 22, 22, 16, 105, HitLevel.Overhead, new Rect(0.0f, 0.0f, 1.2f, 1.5f));
            leap.knockdown = true; leap.knockback = new Vector2(3.5f, 6f); leap.trails = Trail.WeaponR | Trail.WeaponL; leap.fx = HitFx.Water; leap.hitSfx = Sfx.SlashHeavy; leap.shake = 0.3f;
            leap.clip = new AnimClip("leap", false, false).F(0, p.stance).F(7, p["leap_w"], Ease.OutQuad).F(12, p["leap_air"], Ease.OutCubic).F(22, p["leap_air"], Ease.Linear).F(26, p["leap_s"], Ease.OutExpo).F(60, p["leap_s"], Ease.Linear);
            leap.projectileInvulStart = 8; leap.projectileInvulEnd = 30;
            leap.onFrame = (f, fr) =>
            {
                if (fr == 8) { f.vel = new Vector2(f.facing * 5.5f, 12.5f); f.pos.y = 0.01f; SynthAudio.Play(Sfx.Jump, 0.8f); f.fx.Dust(1f); }
                if (fr == 22) { f.vel = new Vector2(f.facing * 7f, -15f); SynthAudio.Play(Sfx.WhooshHeavy, 1f); }
                if (fr > 22 && f.Grounded)
                {
                    VFX.HitSpark(new Vector3(f.pos.x + f.facing * 0.5f, 0.2f, -0.2f), HitFx.Water, false, 1.2f, f.facing);
                    SynthAudio.Play(Sfx.Water, 0.8f);
                    f.fx.Dust(1.2f);
                    f.SkipToRecovery();
                    f.vel = Vector2.zero;
                    f.anim.Play(new AnimClip("leapLand").K(0, p["leap_s"]).K(0.27f, p.stance, Ease.InOutQuad), 0.04f);
                }
            };
            Input(d, "leap", Btn.HK, D, F);

            var step = Special(d, "step", "Shamol qadami", "↓ ← + LK", 14, 1, 12, 0, HitLevel.Mid, new Rect(0, 0, 0, 0));
            step.invulStart = 4; step.invulEnd = 18;
            step.clip = new AnimClip("step").F(0, p.stance).F(8, p["step_s"], Ease.OutQuad).F(14, p["step_s"], Ease.Linear).F(27, p.stance, Ease.OutCubic);
            step.onFrame = (f, fr) =>
            {
                if (fr == 9)
                {
                    VFX.Emit(VFX.Kind.Smoke, new Vector3(f.pos.x, 0.9f, 0), new Color(0.7f, 0.95f, 1f, 0.7f), 12, 1.5f, 1f, 0.6f, Vector3.up, 1f);
                    SynthAudio.Play(Sfx.Teleport, 0.9f);
                    f.rig.gameObject.SetActive(false);
                }
                if (fr == 13)
                {
                    var o = f.opp;
                    float x = o.pos.x - o.facing * 1.1f;
                    x = Mathf.Clamp(x, -FightConst.StageHalfWidth + 0.4f, FightConst.StageHalfWidth - 0.4f);
                    if (Mathf.Abs(x - o.pos.x) < 0.6f) x = o.pos.x + o.facing * 1.1f;
                    f.pos = new Vector2(x, 0); f.prevPos = f.pos;
                    f.FaceOpponentNow();
                    f.rig.gameObject.SetActive(true);
                    VFX.Emit(VFX.Kind.Smoke, new Vector3(f.pos.x, 0.9f, 0), new Color(0.7f, 0.95f, 1f, 0.7f), 12, 1.5f, 1f, 0.6f, Vector3.up, 1f);
                }
            };
            step.onEnd = f => f.rig.gameObject.SetActive(true);
            Input(d, "step", Btn.LK, D, B);

            // --- Super ---
            var sup = Special(d, "super", "Xorazm bo'roni", "HP + HK (3 bo'lak)", 7, 4, 30, 30, HitLevel.Mid, new Rect(0.1f, 0.3f, 1.5f, 1.5f));
            sup.kind = MoveKind.Super; sup.invulStart = 0; sup.invulEnd = 11; sup.trails = Trail.WeaponR | Trail.WeaponL;
            sup.moveVel = new Vector2(12f, 0); sup.moveStart = 2; sup.moveEnd = 9;
            sup.clip = AnimClip.Attack("super", p.stance, p["LP_w"], p["LP_s"], 7, 4, 30);
            sup.onHit = (a, b) => a.match.StartCinematic(a, b, a.def.superScript, false);
            d.superMoveId = "super";
            d.superScript = c =>
            {
                var a = c.attacker; var df = c.defender; int fc = a.facing;
                var steps = new List<CineStep>
                {
                    new CineStep(0f, x => { x.cam.Shot(a.rig.Pos(Bone.Head) + new Vector3(fc * 1.0f, 0.0f, -1.8f), a.rig.Pos(Bone.Head), 30, 0.15f);
                        CineAnim(a, Hold(p["HP_w"]), 0.1f); a.fx.aura = 1; a.fx.auraColor = d.energyColor; SynthAudio.Play(Sfx.Gong, 1f, 1.1f); x.match.Announce("XORAZM BO'RONI", 1.4f, d.energyColor); }),
                    new CineStep(0.6f, x => { x.cam.Shot(Mid(x) + new Vector3(0, 1.4f, -4.6f), Mid(x) + Vector3.up * 1.1f, 36, 0.1f); }),
                };
                string[] seq = { "LP_s", "LP2_s", "HP_s", "LP_s", "LP2_s", "cHP_s" };
                for (int i = 0; i < seq.Length; i++)
                {
                    int k = i;
                    steps.Add(new CineStep(0.65f + i * 0.17f, x =>
                    {
                        float side = k % 2 == 0 ? -1 : 1;
                        a.pos.x = df.pos.x + side * fc * 1.0f; a.SetFacing(df.pos.x > a.pos.x ? 1 : -1);
                        VFX.Emit(VFX.Kind.Smoke, new Vector3(a.pos.x, 1f, 0), new Color(0.6f, 0.95f, 1f, 0.5f), 6, 1f, 0.8f, 0.4f, Vector3.up, 1f);
                        CineAnim(a, Strike(p[seq[k].Replace("_s", "_w")], p[seq[k]], 0.06f));
                        a.fx.StartTrails(d.Get("str3"));
                        CineAnim(df, k % 2 == 0 ? df.def.anims.hitHigh : df.def.anims.hitMid, 0.02f);
                        CineHit(x, 26, HitFx.Wind, Sfx.Slash, 0.15f);
                    }));
                }
                steps.Add(new CineStep(1.75f, x => { df.cinePhysics = true; df.vel = new Vector2(0, 13f); CineAnim(df, df.def.anims.juggle); a.cinePhysics = true; a.cineGroundLock = false; a.vel = new Vector2(0, 15f);
                    CineAnim(a, Hold(p["leap_air"])); x.cam.Shot(Mid(x) + new Vector3(0, 2.5f, -6f), Mid(x) + Vector3.up * 3f, 40, 0.3f); SynthAudio.Play(Sfx.Jump, 0.8f); }));
                steps.Add(new CineStep(2.15f, x => { CineAnim(a, Strike(p["leap_air"], p["leap_s"])); df.vel = new Vector2(fc * 1f, -18f); a.vel = new Vector2(0, -14f); CineHit(x, 60, HitFx.Water, Sfx.SlashHeavy, 0.4f, 1.5f); }));
                steps.Add(new CineStep(2.45f, x => { CineAnim(df, df.def.anims.lying, 0.05f); SynthAudio.Play(Sfx.Water, 1f); VFX.HitSpark(new Vector3(df.pos.x, 0.2f, -0.3f), HitFx.Water, false, 2f, fc);
                    x.cam.Shake(0.4f); a.cineGroundLock = true; CineAnim(a, Hold(p.stance)); }));
                steps.Add(new CineStep(3.1f, x => { a.fx.aura = 0; }));
                return steps;
            };

            // --- Yakuniy zarba ---
            d.finisherName = "SIND TO'LQINI";
            d.finisherInput = new SpecialInput("finisher", Btn.HK, D, F, B);
            d.finisherScript = c =>
            {
                var a = c.attacker; var df = c.defender; int fc = a.facing;
                return new List<CineStep>
                {
                    new CineStep(0f, x => { x.cam.Shot(a.rig.Pos(Bone.Chest) + new Vector3(fc * 1.4f, 0f, -2.4f), a.rig.Pos(Bone.Head), 32, 0.4f);
                        CineAnim(a, Hold(p["whirl_s"]), 0.3f); a.fx.aura = 1; a.fx.auraColor = new Color(0.3f, 0.8f, 1f); SynthAudio.Play(Sfx.Water, 1f, 0.7f); }),
                    new CineStep(0.9f, x => { CineAnim(a, Strike(p["HP_w"], p["HP_s"], 0.12f)); a.fx.StartTrails(d.Get("str3"));
                        var spec = new ProjectileSpec { damage = 0, visual = ProjVisual.WaterWave, color = new Color(0.4f, 0.8f, 1f), size = new Vector2(1.2f, 2f), lifetime = 3f, reflectable = false };
                        x.match.SpawnProjectile(spec, a, new Vector2(a.pos.x + fc * 0.8f, 0.6f), new Vector2(fc * 5f, 0)).spec.damage = 0;
                        x.cam.Shot(Mid(x) + new Vector3(0, 1.6f, -6f), Mid(x) + Vector3.up * 1.2f, 40, 0.3f); SynthAudio.Play(Sfx.Water, 1f); }),
                    new CineStep(1.4f, x => { CineAnim(df, df.def.anims.juggle); df.cinePhysics = true; df.vel = new Vector2(fc * 5f, 6f); df.flashTimer = 1f; df.flashColor = new Color(0.4f, 0.8f, 1f);
                        VFX.HitSpark(df.rig.Pos(Bone.Chest), HitFx.Water, false, 2.5f, fc); x.cam.Shake(0.3f); }),
                    new CineStep(2.1f, x => { VFX.Disintegrate(df.rig, new Color(0.5f, 0.85f, 1f), VFX.Kind.Water); df.rig.gameObject.SetActive(false); SynthAudio.Play(Sfx.Water, 1f, 0.6f); }),
                    new CineStep(2.7f, x => { CineAnim(a, a.def.anims.victory, 0.2f); a.fx.aura = 0;
                        x.cam.Shot(a.rig.Pos(Bone.Chest) + new Vector3(fc * 2.2f, 0.2f, -3.2f), a.rig.Pos(Bone.Chest) + Vector3.up * 0.4f, 34, 1.2f); }),
                    new CineStep(4.4f, x => { }),
                };
            };
            return d;
        }
    }
}
