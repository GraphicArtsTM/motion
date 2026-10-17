using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public static partial class Roster
    {
        public static FighterDefinition Temur()
        {
            var d = new FighterDefinition
            {
                id = "temur", name = "AMIR TEMUR", title = "Sohibqiron", years = "1336 — 1405",
                bio = "Buyuk saltanat asoschisi, Movarounnahr hukmdori. Og'ir qilichi va temir irodasi bilan yengilmas sarkarda.",
                quote = "«Kuch — adolatdadir.»",
                style = "Og'ir qilich • Kuchli zarbalar • Zirh (armor)",
                mainColor = Pal.Crimson, accentColor = Pal.Gold, energyColor = new Color(1f, 0.78f, 0.3f),
                walkFwd = 2.3f, walkBack = 1.9f, jumpVel = 11f, jumpX = 3.2f, damageMult = 1.1f, juggleWeight = 1.15f, dashSpeed = 6.8f,
                signatureFx = HitFx.Gold,
            };
            d.buildVisual = t => FbxPuppet.Build("temur", CharacterVisuals.BuildTemur, t);
            d.bounceAmp = 0.011f; d.bounceRate = 3.2f;
            d.introLine = "Adolatsiz kuch — bo'ron, adolatli kuch — qal'a.";
            d.vsLines["jaloliddin"] = "Jasoratingni bilaman, Manguberdi. Ko'rsat-chi!";
            d.vsLines["ulugbek"] = "Nabiram, kitobni qo'y — bugun qilich gapiradi.";
            d.vsLines["chingiz"] = "Dasht bo'roni ham Turon tog'iga urilib to'xtaydi.";
            d.vsLines["temur"] = "Soyam ham menga bo'ysunadi.";
            d.winLines = new[] { "Kuch — adolatdadir.", "Saltanat tinch — dushman yengildi.", "Bu g'alaba — Turon xalqiniki." };
            var p = PoseLib.Temur();
            d.anims = PoseLib.BuildBase(p);
            var cfg = new NormalsCfg { reach = 1.25f, power = 1.0f, speed = 0.92f, hpOverhead = true, trailColor = new Color(1f, 0.8f, 0.45f, 0.95f) };
            AddNormals(d, p, cfg);

            // --- Zanjirlar (kombo string) ---
            var str3 = Normal(d, p, "str3", "Sohibqiron uchligi", "LP, LP, HP", "HP_w", "HP_s", "HP_f", 12, 4, 24, 70, HitLevel.Mid, new Rect(0.2f, 0.7f, 1.2f, 1.0f), cfg, true);
            str3.trails = Trail.WeaponR; str3.launch = true; str3.knockback = new Vector2(2.2f, 9.5f); str3.fx = HitFx.Gold;
            d.Get("LP2").Chain(Btn.HP, "str3");
            var hk2 = Normal(d, p, "hk2", "Qilich va tepki", "HP, HK", "HK_w", "HK_s", null, 10, 4, 22, 60, HitLevel.Mid, new Rect(0.2f, 0.9f, 1.05f, 0.6f), cfg, true);
            hk2.trails = Trail.FootR; hk2.fx = HitFx.Blunt; hk2.hitSfx = Sfx.HitHeavy; hk2.knockdown = true; hk2.knockback = new Vector2(4.5f, 5);
            d.Get("HP").Chain(Btn.HK, "hk2");

            // --- Maxsus usullar ---
            var wave = Special(d, "wave", "Qilich to'lqini", "← → + LP", 16, 1, 22, 0, HitLevel.Mid, new Rect(0, 0, 0, 0));
            wave.trails = Trail.WeaponR;
            wave.clip = AnimClip.Attack("wave", p.stance, p["wave_w"], p["wave_s"], 16, 1, 22);
            wave.onFrame = (f, fr) =>
            {
                if (fr == 16)
                {
                    var spec = new ProjectileSpec
                    {
                        damage = 80, level = HitLevel.Mid, hitstun = 22, knockback = new Vector2(2.6f, 0), size = new Vector2(0.7f, 1.3f),
                        visual = ProjVisual.SwordWave, color = new Color(1f, 0.75f, 0.25f), fx = HitFx.Gold, hitSfx = Sfx.SlashHeavy, lifetime = 1.6f
                    };
                    f.match.SpawnProjectile(spec, f, f.pos + new Vector2(f.facing * 0.9f, 0.85f), new Vector2(f.facing * 9.5f, 0));
                    SynthAudio.Play(Sfx.Projectile, 0.8f, 0.8f);
                    f.match.cam.Shake(0.05f);
                }
            };
            Input(d, "wave", Btn.LP, B, F);

            var charge = Special(d, "charge", "Sohibqiron hamlasi", "← → + LK", 12, 16, 22, 110, HitLevel.Mid, new Rect(0.0f, 0.5f, 0.95f, 1.2f));
            charge.moveVel = new Vector2(9f, 0); charge.moveStart = 10; charge.moveEnd = 28;
            charge.armorStart = 3; charge.armorEnd = 26;
            charge.knockdown = true; charge.knockback = new Vector2(5.5f, 4.5f); charge.hitSfx = Sfx.HitHeavy; charge.fx = HitFx.Gold; charge.blockstun = 14;
            charge.clip = new AnimClip("charge").F(0, p.stance).F(10, p["charge_w"], Ease.OutQuad).F(14, p["charge_s"], Ease.OutExpo).F(28, p["charge_s"], Ease.Linear).F(50, p.stance, Ease.InOutQuad);
            charge.onFrame = (f, fr) => { if (fr >= 10 && fr <= 28 && fr % 3 == 0) f.fx.Dust(0.5f); f.fx.aura = fr < 28 ? 1f : 0f; f.fx.auraColor = new Color(1f, 0.7f, 0.2f); };
            charge.onEnd = f => f.fx.aura = 0;
            Input(d, "charge", Btn.LK, B, F);

            var quake = Special(d, "quake", "Yer titrashi", "↓ ↓ + HP", 22, 6, 28, 95, HitLevel.Low, new Rect(-1.4f, 0f, 3.6f, 0.6f));
            quake.launch = true; quake.knockback = new Vector2(1.5f, 9f); quake.fx = HitFx.Earth; quake.hitSfx = Sfx.Boom; quake.shake = 0.35f;
            quake.trails = Trail.WeaponR;
            quake.clip = new AnimClip("quake").F(0, p.stance).F(14, p["quake_w"], Ease.OutCubic).F(22, p["quake_s"], Ease.InCubic).F(36, p["quake_s"], Ease.Linear).F(56, p.stance, Ease.InOutQuad);
            quake.onFrame = (f, fr) =>
            {
                if (fr == 22)
                {
                    f.match.cam.Shake(0.4f);
                    SynthAudio.Play(Sfx.Boom, 1f);
                    SynthAudio.Play(Sfx.Thunder, 0.5f, 1.4f);
                    VFX.Burst(new Vector3(f.pos.x + f.facing * 0.6f, 0.1f, 0), new Color(1f, 0.6f, 0.2f), 0.9f);
                    VFX.Dust(new Vector3(f.pos.x + f.facing * 1.2f, 0, 0), 3f);
                    VFX.Dust(new Vector3(f.pos.x - f.facing * 1.0f, 0, 0), 2f);
                    var spec = new ProjectileSpec
                    {
                        damage = 45, level = HitLevel.Low, hitstun = 20, knockback = new Vector2(1f, 7f), launch = true, size = new Vector2(0.8f, 0.7f),
                        visual = ProjVisual.Shockwave, color = new Color(1f, 0.55f, 0.2f), fx = HitFx.Earth, hitSfx = Sfx.Boom, lifetime = 0.45f, reflectable = false, groundHugging = true
                    };
                    f.match.SpawnProjectile(spec, f, new Vector2(f.pos.x + f.facing * 1.6f, 0.3f), new Vector2(f.facing * 8f, 0));
                }
            };
            Input(d, "quake", Btn.HP, D, D);

            var counter = Special(d, "counter", "Adolat qalqoni", "↓ ← + HP", 3, 26, 18, 0, HitLevel.Mid, new Rect(0, 0, 0, 0));
            counter.counterStart = 3; counter.counterEnd = 26; counter.counterMove = "counterHit";
            counter.clip = new AnimClip("counter").F(0, p.stance).F(4, p["counter_s"], Ease.OutExpo).F(29, p["counter_s"], Ease.Linear).F(47, p.stance, Ease.InOutQuad);
            counter.onFrame = (f, fr) => { f.fx.aura = fr >= 3 && fr <= 26 ? 0.8f : 0; f.fx.auraColor = new Color(1, 0.85f, 0.4f); };
            counter.onEnd = f => f.fx.aura = 0;
            Input(d, "counter", Btn.HP, D, B);

            var ch = Special(d, "counterHit", "Adolat zarbasi", "(qarshi zarba)", 4, 4, 22, 140, HitLevel.Unblockable, new Rect(0.0f, 0.3f, 1.7f, 1.8f));
            ch.knockdown = true; ch.knockback = new Vector2(5f, 6f); ch.invulStart = 0; ch.invulEnd = 8; ch.trails = Trail.WeaponR; ch.fx = HitFx.Gold;
            ch.clip = AnimClip.Attack("counterHit", p["counter_s"], p["HP_w"], p["HP_s"], 4, 4, 22, p["HP_f"]);
            ch.onStart = f => { f.fx.aura = 0; f.match.Announce("ADOLAT!", 0.8f, Pal.Gold); SynthAudio.Play(Sfx.Clang, 1f, 0.8f); f.match.HitStopVisual(0.12f); };

            // --- Super ---
            var sup = Special(d, "super", "Jahongir g'azabi", "HP + HK (3 bo'lak)", 8, 4, 30, 30, HitLevel.Mid, new Rect(0.1f, 0.3f, 1.5f, 1.5f));
            sup.kind = MoveKind.Super; sup.invulStart = 0; sup.invulEnd = 12; sup.trails = Trail.WeaponR; sup.fx = HitFx.Gold;
            sup.moveVel = new Vector2(10f, 0); sup.moveStart = 2; sup.moveEnd = 10;
            sup.clip = AnimClip.Attack("super", p.stance, p["LP_w"], p["LP_s"], 8, 4, 30);
            sup.onHit = (a, b) => a.match.StartCinematic(a, b, a.def.superScript, false);
            d.superMoveId = "super";
            d.superScript = c =>
            {
                var a = c.attacker; var df = c.defender; int fc = a.facing;
                return new List<CineStep>
                {
                    new CineStep(0f, x => { x.cam.Shot(a.rig.Pos(Bone.Head) + new Vector3(fc * 1.1f, 0.0f, -1.9f), a.rig.Pos(Bone.Head), 30, 0.15f);
                        CineAnim(a, Hold(p["wave_w"]), 0.1f); a.fx.aura = 1; a.fx.auraColor = Pal.Gold; SynthAudio.Play(Sfx.Gong, 1f); x.match.Announce("JAHONGIR G'AZABI", 1.4f, Pal.Gold); }),
                    new CineStep(0.7f, x => { a.pos.x = df.pos.x - fc * 1.0f; x.cam.Shot(Mid(x) + new Vector3(0, 1.3f, -4.2f), Mid(x) + Vector3.up * 1.1f, 34, 0.1f);
                        CineAnim(a, Strike(p["LP_w"], p["LP_s"])); a.fx.StartTrails(d.Get("LP")); CineAnim(df, df.def.anims.hitHigh); CineHit(x, 35, HitFx.Gold, Sfx.Slash); }),
                    new CineStep(0.9f, x => { CineAnim(a, Strike(p["LP2_w"], p["LP2_s"])); CineAnim(df, df.def.anims.hitMid); CineHit(x, 35, HitFx.Gold, Sfx.Slash); }),
                    new CineStep(1.12f, x => { CineAnim(a, Strike(p["HP_w"], p["HP_s"], 0.1f)); CineAnim(df, df.def.anims.hitHigh); CineHit(x, 50, HitFx.Gold, Sfx.SlashHeavy, 0.3f); }),
                    new CineStep(1.4f, x => { CineAnim(a, Strike(p["cHP_w"], p["cHP_s"])); df.cinePhysics = true; df.vel = new Vector2(fc * 0.8f, 12f); CineAnim(df, df.def.anims.juggle);
                        CineHit(x, 40, HitFx.Gold, Sfx.SlashHeavy, 0.3f); x.cam.Shot(Mid(x) + new Vector3(fc * -0.5f, 1.2f, -5.5f), Mid(x) + Vector3.up * 2.2f, 38, 0.3f); }),
                    new CineStep(1.65f, x => { a.cinePhysics = true; a.vel = new Vector2(fc * 1.2f, 12.5f); a.cineGroundLock = false; CineAnim(a, Hold(p["jP_w"])); SynthAudio.Play(Sfx.Jump, 0.6f); }),
                    new CineStep(1.95f, x => { CineAnim(a, Strike(p["jP_w"], p["jP_s"])); df.vel = new Vector2(fc * 1.5f, -16f); CineHit(x, 55, HitFx.Gold, Sfx.SlashHeavy, 0.35f, 1.3f); }),
                    new CineStep(2.2f, x => { CineAnim(df, df.def.anims.lying, 0.05f); SynthAudio.Play(Sfx.BodyFall, 1f); VFX.Dust(new Vector3(df.pos.x, 0, 0), 2.5f); x.cam.Shake(0.3f); }),
                    new CineStep(2.45f, x => { a.cineGroundLock = true; CineAnim(a, Strike(p["quake_w"], p["quake_s"], 0.1f, Ease.InCubic)); }),
                    new CineStep(2.6f, x => { CineHit(x, 70, HitFx.Earth, Sfx.Boom, 0.6f, 1.6f); SynthAudio.Play(Sfx.Thunder, 0.9f); VFX.Burst(new Vector3(df.pos.x, 0.2f, 0), new Color(1f, 0.6f, 0.2f), 1.5f);
                        x.match.ScreenFlash(new Color(1f, 0.85f, 0.5f), 0.3f); }),
                    new CineStep(3.3f, x => { a.fx.aura = 0; }),
                };
            };

            // --- Yakuniy zarba (Finisher) ---
            d.finisherName = "SOHIBQIRON HUKMI";
            d.finisherInput = new SpecialInput("finisher", Btn.HP, F, B, F);
            d.finisherScript = c =>
            {
                var a = c.attacker; var df = c.defender; int fc = a.facing;
                return new List<CineStep>
                {
                    new CineStep(0f, x => { x.cam.Shot(a.rig.Pos(Bone.Chest) + new Vector3(fc * 1.6f, -0.4f, -2.6f), a.rig.Pos(Bone.Head) + Vector3.up * 0.3f, 34, 0.4f);
                        CineAnim(a, Hold(p.victoryA), 0.3f); x.match.SetDarkSky(true); SynthAudio.Play(Sfx.DrumRoll, 1f); a.fx.aura = 1; a.fx.auraColor = Pal.Gold; }),
                    new CineStep(1.2f, x => { SynthAudio.Play(Sfx.Thunder, 1f); x.match.ScreenFlash(Color.white, 0.25f); x.match.Lightning(new Vector3(a.rig.weaponTipR.position.x, 0, 0));
                        x.cam.Shot(Mid(x) + new Vector3(0, 1.8f, -6.5f), Mid(x) + Vector3.up * 1.3f, 40, 0.2f); }),
                    new CineStep(1.6f, x => { a.pos.x = df.pos.x - fc * 1.0f; CineAnim(a, Strike(p["HP_w"], p["HP_s"], 0.12f)); a.fx.StartTrails(d.Get("HP")); }),
                    new CineStep(1.75f, x => { x.match.Lightning(new Vector3(df.pos.x, 0, 0)); SynthAudio.Play(Sfx.Thunder, 1f, 1.2f); x.match.ScreenFlash(new Color(1f, 0.9f, 0.6f), 0.35f);
                        CineAnim(df, df.def.anims.hitHigh); df.flashTimer = 1f; df.flashColor = Pal.Gold; x.cam.Shake(0.5f); }),
                    new CineStep(2.3f, x => { VFX.Disintegrate(df.rig, new Color(1f, 0.75f, 0.3f)); SynthAudio.Play(Sfx.Shatter, 1f); df.rig.gameObject.SetActive(false); x.cam.Shake(0.2f); }),
                    new CineStep(2.9f, x => { CineAnim(a, a.def.anims.victory, 0.2f); a.fx.aura = 0; x.match.SetDarkSky(false);
                        x.cam.Shot(a.rig.Pos(Bone.Chest) + new Vector3(fc * 2.2f, 0.2f, -3.2f), a.rig.Pos(Bone.Chest) + Vector3.up * 0.4f, 34, 1.2f); }),
                    new CineStep(4.6f, x => { }),
                };
            };
            return d;
        }
    }
}
