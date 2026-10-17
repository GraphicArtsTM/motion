using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public static partial class Roster
    {
        public static FighterDefinition Chingiz()
        {
            var wolfC = new Color(0.45f, 0.75f, 1f);
            var d = new FighterDefinition
            {
                id = "chingiz", name = "CHINGIZXON", title = "Dasht bo'roni", years = "1162 — 1227",
                bio = "Mo'g'ul imperiyasi asoschisi. Dasht qabilalarini birlashtirib, tarixdagi eng katta saltanatlardan birini barpo etgan.",
                quote = "«Dasht faqat kuchlini taniydi.»",
                style = "Qilich va kamon • Kurash (otish) • Bosim",
                mainColor = Pal.Burgundy, accentColor = Pal.Fur, energyColor = wolfC,
                walkFwd = 2.6f, walkBack = 2.0f, jumpVel = 11f, jumpX = 3.4f, damageMult = 1.05f, juggleWeight = 1.1f, dashSpeed = 7.6f,
                signatureFx = HitFx.Arrow,
            };
            d.buildVisual = t => FbxPuppet.Build("chingiz", CharacterVisuals.BuildChingiz, t);
            d.bounceAmp = 0.018f; d.bounceRate = 4.6f;
            d.introLine = "Dasht faqat kuchlini taniydi!";
            d.vsLines["jaloliddin"] = "Bu safar daryo seni qutqarmaydi.";
            d.vsLines["temur"] = "Temirni ham sindirish mumkin.";
            d.vsLines["ulugbek"] = "Yulduz sanagan qo'l kamon tortolmaydi.";
            d.vsLines["chingiz"] = "Ikki bo'ri — bitta dasht.";
            d.winLines = new[] { "Dasht g'olibni tanidi.", "Ko'k bo'ri hech qachon ochiqmaydi.", "Yana bir qabila bo'ysundi." };
            var p = PoseLib.Chingiz();
            d.anims = PoseLib.BuildBase(p);
            var cfg = new NormalsCfg { reach = 1.12f, power = 1.03f, speed = 1.0f, trailColor = new Color(1f, 0.85f, 0.6f, 0.9f) };
            AddNormals(d, p, cfg);
            var lp2 = d.Get("LP2"); lp2.trails = Trail.HandL; lp2.fx = HitFx.Blunt; lp2.hitSfx = Sfx.HitLight;
            var chp = d.Get("cHP"); chp.trails = Trail.HandL; chp.fx = HitFx.Blunt; chp.hitSfx = Sfx.HitHeavy;
            var hk = d.Get("HK"); hk.hitbox = new Rect(0.1f, 0.8f, 0.85f, 0.7f); hk.level = HitLevel.Mid; hk.knockdown = false; hk.launch = true; hk.knockback = new Vector2(1.5f, 8.5f);
            d.Get("throw").throwDamage = 135;

            var str3 = Normal(d, p, "str3", "Xon g'azabi", "LP, LP, HP", "HP_w", "HP_s", "HP_f", 12, 4, 22, 74, HitLevel.Mid, new Rect(0.2f, 0.7f, 1.15f, 1.0f), cfg, true);
            str3.trails = Trail.WeaponR; str3.knockdown = true; str3.knockback = new Vector2(5f, 5f);
            d.Get("LP2").Chain(Btn.HP, "str3");

            ProjectileSpec ArrowSpec() => new ProjectileSpec
            {
                damage = 58, level = HitLevel.High, hitstun = 18, knockback = new Vector2(2f, 0), size = new Vector2(0.6f, 0.25f),
                visual = ProjVisual.Arrow, color = new Color(1f, 0.85f, 0.6f), fx = HitFx.Arrow, hitSfx = Sfx.Arrow, lifetime = 1.3f
            };
            void ShowBow(Fighter f, bool on)
            {
                var props = f.rig.GetComponent<CharacterProps>();
                props.Show("bowHand", on); props.Show("bowBack", !on);
                if (f.rig.weaponBaseR) f.rig.weaponBaseR.parent.gameObject.SetActive(!on);
            }
            var arrow = Special(d, "arrow", "Mo'g'ul o'qi", "← → + LP", 15, 1, 18, 0, HitLevel.High, new Rect(0, 0, 0, 0));
            arrow.clip = new AnimClip("arrow").F(0, p.stance).F(6, p["arrow_w"], Ease.OutQuad).F(15, p["arrow_w"], Ease.Linear).F(17, p["arrow_s"], Ease.OutExpo).F(34, p.stance, Ease.InOutQuad);
            arrow.onStart = f => ShowBow(f, true);
            arrow.onEnd = f => ShowBow(f, false);
            arrow.onFrame = (f, fr) =>
            {
                if (fr == 15)
                {
                    f.match.SpawnProjectile(ArrowSpec(), f, f.pos + new Vector2(f.facing * 0.9f, 1.4f), new Vector2(f.facing * 17f, 0));
                    SynthAudio.Play(Sfx.Arrow, 1f);
                }
            };
            Input(d, "arrow", Btn.LP, B, F);
            var jarrow = Special(d, "jarrow", "Havodan o'q", "havoda ← → + LP", 10, 1, 14, 0, HitLevel.Overhead, new Rect(0, 0, 0, 0));
            jarrow.air = true; jarrow.airOK = true;
            jarrow.clip = new AnimClip("jarrow", false, false).F(0, PoseLib.JumpTuck(p.stance)).F(6, PoseLib.JumpTuck(p.stance).CopyArms(p["arrow_w"]), Ease.OutQuad).F(24, PoseLib.Fall(p.stance), Ease.InOutQuad);
            jarrow.onStart = f => ShowBow(f, true);
            jarrow.onEnd = f => ShowBow(f, false);
            jarrow.onFrame = (f, fr) =>
            {
                if (fr == 10)
                {
                    var s = ArrowSpec(); s.level = HitLevel.Overhead;
                    f.match.SpawnProjectile(s, f, f.pos + new Vector2(f.facing * 0.7f, 1.0f), new Vector2(f.facing * 14f, -8f));
                    SynthAudio.Play(Sfx.Arrow, 1f);
                }
            };
            Input(d, "jarrow", Btn.LP, B, F);

            var lasso = Special(d, "lasso", "Arqon tuzog'i", "← → + HK", 16, 1, 30, 0, HitLevel.Mid, new Rect(0, 0, 0, 0));
            lasso.clip = new AnimClip("lasso").F(0, p.stance).F(10, p["lasso_w"], Ease.OutQuad).F(16, p["lasso_s"], Ease.OutExpo).F(32, p["lasso_s"], Ease.Linear).F(47, p.stance, Ease.InOutQuad);
            lasso.onStart = f => { if (f.rig.weaponBaseR) f.rig.weaponBaseR.parent.gameObject.SetActive(false); };
            lasso.onEnd = f => { if (f.rig.weaponBaseR) f.rig.weaponBaseR.parent.gameObject.SetActive(true); };
            lasso.onFrame = (f, fr) =>
            {
                if (fr == 16)
                {
                    var s = new ProjectileSpec
                    {
                        damage = 30, level = HitLevel.Mid, hitstun = 40, knockback = new Vector2(0, 0), size = new Vector2(0.6f, 0.6f),
                        visual = ProjVisual.Lasso, color = new Color(0.9f, 0.75f, 0.45f), fx = HitFx.Blunt, hitSfx = Sfx.Whip, lifetime = 0.42f, reflectable = false,
                        onHit = (att, def) =>
                        {
                            def.vel = new Vector2((att.pos.x + att.facing * 1.0f - def.pos.x) * 3.2f, 2.5f);
                            def.stun = 34;
                            att.ForceMove("lassoPull");
                            att.match.Announce("TUTILDI!", 0.7f, new Color(1f, 0.85f, 0.5f));
                        }
                    };
                    f.match.SpawnProjectile(s, f, f.pos + new Vector2(f.facing * 0.8f, 1.3f), new Vector2(f.facing * 14f, 0));
                    SynthAudio.Play(Sfx.Whip, 1f);
                }
            };
            Input(d, "lasso", Btn.HK, B, F);
            var pull = Special(d, "lassoPull", "Tortib urish", "(arqondan keyin)", 22, 4, 24, 80, HitLevel.Unblockable, new Rect(0.0f, 0.4f, 1.3f, 1.3f));
            pull.knockdown = true; pull.knockback = new Vector2(4.5f, 6f); pull.trails = Trail.WeaponR; pull.fx = HitFx.Slash;
            pull.clip = new AnimClip("lassoPull").F(0, p["lasso_s"]).F(10, p["lasso_pull"], Ease.OutQuad).F(16, p["HP_w"], Ease.InOutQuad).F(22, p["HP_s"], Ease.OutExpo).F(26, p["HP_f"], Ease.OutQuad).F(50, p.stance, Ease.InOutQuad);
            pull.onStart = f => { if (f.rig.weaponBaseR) f.rig.weaponBaseR.parent.gameObject.SetActive(true); };

            var wolf = Special(d, "wolf", "Ko'k bo'ri hamlasi", "↓ → + LK", 10, 16, 22, 92, HitLevel.Mid, new Rect(0.1f, 0.5f, 0.95f, 1.0f));
            wolf.moveVel = new Vector2(9.5f, 0); wolf.moveStart = 8; wolf.moveEnd = 26; wolf.knockdown = true; wolf.knockback = new Vector2(5f, 6f);
            wolf.fx = HitFx.Blunt; wolf.hitSfx = Sfx.HitHeavy; wolf.trails = Trail.FootR;
            wolf.clip = new AnimClip("wolf").F(0, p.stance).F(8, p["wolf_w"], Ease.OutQuad).F(12, p["wolf_s"], Ease.OutExpo).F(26, p["wolf_s"], Ease.Linear).F(48, p.stance, Ease.InOutQuad);
            wolf.onFrame = (f, fr) =>
            {
                if (fr == 8)
                {
                    SynthAudio.Play(Sfx.Wolf, 0.8f);
                    var s = new ProjectileSpec { damage = 0, visual = ProjVisual.WolfSpirit, size = new Vector2(0.01f, 0.01f), lifetime = 0.5f, reflectable = false, color = wolfC };
                    var pr = f.match.SpawnProjectile(s, f, f.pos + new Vector2(f.facing * 0.2f, 0.6f), new Vector2(f.facing * 10.5f, 0));
                    pr.spec.damage = 0;
                }
                if (fr > 8 && fr < 26 && fr % 3 == 0) f.fx.Dust(0.5f);
            };
            Input(d, "wolf", Btn.LK, D, F);

            var grip = new MoveData
            {
                id = "grip", name = "Xon changali", notation = "↓ ← + HP (yaqin)", kind = MoveKind.Special, isThrow = true,
                startup = 6, active = 2, recovery = 30, throwRange = 1.35f, throwDamage = 165, hitbox = new Rect(0, 0, 0, 0), meterGain = 15,
            };
            grip.clip = new AnimClip("gripTry").F(0, p.stance).F(6, p.stance.Clone().A(Bone.UpperArmR, -60).A(Bone.UpperArmL, -70).A(Bone.Spine, 14), Ease.OutQuad).F(38, p.stance, Ease.InOutQuad);
            grip.onHit = (a, b) => { SynthAudio.Play(Sfx.Wolf, 0.7f, 0.8f); a.match.Announce("XON CHANGALI!", 0.8f, wolfC); a.fx.aura = 1; a.fx.auraColor = wolfC; };
            grip.onEnd = f => f.fx.aura = 0;
            d.Add(grip);
            Input(d, "grip", Btn.HP, D, B);

            // --- Super: Dasht bo'roni ---
            var sup = Special(d, "super", "Dasht bo'roni", "HP + HK (3 bo'lak)", 9, 4, 30, 30, HitLevel.Mid, new Rect(0.1f, 0.3f, 1.5f, 1.5f));
            sup.kind = MoveKind.Super; sup.invulStart = 0; sup.invulEnd = 12; sup.trails = Trail.WeaponR;
            sup.moveVel = new Vector2(10f, 0); sup.moveStart = 2; sup.moveEnd = 10;
            sup.clip = AnimClip.Attack("super", p.stance, p["HP_w"], p["HP_s"], 9, 4, 30);
            sup.onHit = (a, b) => a.match.StartCinematic(a, b, a.def.superScript, false);
            d.superMoveId = "super";
            d.superScript = c =>
            {
                var a = c.attacker; var df = c.defender; int fc = a.facing;
                var steps = new List<CineStep>
                {
                    new CineStep(0f, x => { x.cam.Shot(a.rig.Pos(Bone.Head) + new Vector3(fc * 1.0f, 0.0f, -1.8f), a.rig.Pos(Bone.Head), 30, 0.15f);
                        CineAnim(a, Hold(p.victoryA), 0.1f); a.fx.aura = 1; a.fx.auraColor = wolfC; SynthAudio.Play(Sfx.Wolf, 1f); x.match.Announce("DASHT BO'RONI", 1.4f, wolfC); }),
                    new CineStep(0.7f, x => { CineAnim(a, Hold(p["arrow_w"]), 0.08f); var props = a.rig.GetComponent<CharacterProps>(); props.Show("bowHand", true); props.Show("bowBack", false);
                        if (a.rig.weaponBaseR) a.rig.weaponBaseR.parent.gameObject.SetActive(false);
                        a.pos.x = df.pos.x - fc * 3.5f; x.cam.Shot(Mid(x) + new Vector3(0, 1.4f, -6f), Mid(x) + Vector3.up * 1.2f, 38, 0.15f); }),
                };
                for (int i = 0; i < 5; i++)
                {
                    int k = i;
                    steps.Add(new CineStep(0.9f + i * 0.14f, x =>
                    {
                        CineAnim(a, Strike(p["arrow_w"], p["arrow_s"], 0.05f));
                        SynthAudio.Play(Sfx.Arrow, 0.9f);
                        var s = new ProjectileSpec { damage = 0, visual = ProjVisual.Arrow, size = new Vector2(0.01f, 0.01f), lifetime = 0.25f, reflectable = false };
                        x.match.SpawnProjectile(s, a, a.pos + new Vector2(fc * 0.9f, 1.4f), new Vector2(fc * 17f, 0));
                    }));
                    steps.Add(new CineStep(1.08f + i * 0.14f, x => { CineHit(x, 22, HitFx.Arrow, Sfx.Arrow, 0.1f, 0.7f); CineAnim(df, k % 2 == 0 ? df.def.anims.hitHigh : df.def.anims.hitMid, 0.02f); }));
                }
                steps.Add(new CineStep(1.75f, x => { var props = a.rig.GetComponent<CharacterProps>(); props.Show("bowHand", false); props.Show("bowBack", true);
                    if (a.rig.weaponBaseR) a.rig.weaponBaseR.parent.gameObject.SetActive(true);
                    CineAnim(a, Hold(p["wolf_s"]), 0.05f); a.cinePhysics = true; a.vel = new Vector2(fc * 14f, 0); SynthAudio.Play(Sfx.Wolf, 1f, 1.1f);
                    var s = new ProjectileSpec { damage = 0, visual = ProjVisual.WolfSpirit, size = new Vector2(0.01f, 0.01f), lifetime = 0.5f, reflectable = false, color = wolfC };
                    x.match.SpawnProjectile(s, a, a.pos + new Vector2(fc * 0.2f, 0.6f), new Vector2(fc * 16f, 0)); }));
                steps.Add(new CineStep(1.95f, x => { a.vel = Vector2.zero; a.pos.x = df.pos.x - fc * 0.9f; CineHit(x, 50, HitFx.Blunt, Sfx.HitHeavy, 0.35f, 1.3f);
                    df.cinePhysics = true; df.vel = new Vector2(fc * 1f, 10f); CineAnim(df, df.def.anims.juggle); }));
                steps.Add(new CineStep(2.2f, x => { CineAnim(a, Strike(p["HP_w"], p["HP_s"], 0.1f)); a.fx.StartTrails(d.Get("HP")); }));
                steps.Add(new CineStep(2.3f, x => { CineHit(x, 70, HitFx.Slash, Sfx.SlashHeavy, 0.5f, 1.6f); df.vel = new Vector2(fc * 6f, 2f); x.match.ScreenFlash(new Color(0.7f, 0.85f, 1f), 0.3f); }));
                steps.Add(new CineStep(2.8f, x => { CineAnim(df, df.def.anims.lying, 0.05f); SynthAudio.Play(Sfx.BodyFall, 1f); VFX.Dust(new Vector3(df.pos.x, 0, 0), 2f); }));
                steps.Add(new CineStep(3.2f, x => { a.fx.aura = 0; CineAnim(a, Hold(p.stance), 0.2f); }));
                return steps;
            };

            d.finisherName = "BO'RILAR HUKMI";
            d.finisherInput = new SpecialInput("finisher", Btn.HK, B, F, B);
            d.finisherScript = c =>
            {
                var a = c.attacker; var df = c.defender; int fc = a.facing;
                var steps = new List<CineStep>
                {
                    new CineStep(0f, x => { x.cam.Shot(a.rig.Pos(Bone.Chest) + new Vector3(fc * 1.5f, -0.3f, -2.5f), a.rig.Pos(Bone.Head), 32, 0.4f);
                        CineAnim(a, Hold(p.victoryA), 0.3f); a.fx.aura = 1; a.fx.auraColor = wolfC; x.match.SetDarkSky(true); SynthAudio.Play(Sfx.Wolf, 1f, 0.9f); }),
                    new CineStep(1.0f, x => { x.cam.Shot(Mid(x) + new Vector3(0, 1.6f, -7f), Mid(x) + Vector3.up * 1f, 42, 0.5f); SynthAudio.Play(Sfx.Wolf, 1f, 1.15f); }),
                };
                for (int i = 0; i < 6; i++)
                {
                    int k = i;
                    steps.Add(new CineStep(1.2f + i * 0.18f, x =>
                    {
                        float side = k % 2 == 0 ? -1 : 1;
                        var s = new ProjectileSpec { damage = 0, visual = ProjVisual.WolfSpirit, size = new Vector2(0.01f, 0.01f), lifetime = 0.9f, reflectable = false, color = wolfC };
                        x.match.SpawnProjectile(s, a, new Vector2(df.pos.x - side * 5f, 0.6f), new Vector2(side * 12f, 0));
                    }));
                    steps.Add(new CineStep(1.6f + i * 0.18f, x => { VFX.HitSpark(df.rig.Pos(Bone.Chest), HitFx.Wind, false, 1f, k % 2 == 0 ? 1 : -1); CineAnim(df, k % 2 == 0 ? df.def.anims.hitHigh : df.def.anims.hitMid, 0.02f);
                        SynthAudio.Play(Sfx.HitHeavy, 0.8f); x.cam.Shake(0.15f); }));
                }
                steps.Add(new CineStep(2.9f, x => { VFX.Disintegrate(df.rig, wolfC, VFX.Kind.Glow); df.rig.gameObject.SetActive(false); SynthAudio.Play(Sfx.Wolf, 1f, 0.8f); x.match.ScreenFlash(wolfC, 0.3f); }));
                steps.Add(new CineStep(3.4f, x => { CineAnim(a, a.def.anims.victory, 0.2f); a.fx.aura = 0; x.match.SetDarkSky(false);
                    x.cam.Shot(a.rig.Pos(Bone.Chest) + new Vector3(fc * 2.2f, 0.2f, -3.2f), a.rig.Pos(Bone.Chest) + Vector3.up * 0.4f, 34, 1.2f); }));
                steps.Add(new CineStep(5.0f, x => { }));
                return steps;
            };
            return d;
        }
    }
}
