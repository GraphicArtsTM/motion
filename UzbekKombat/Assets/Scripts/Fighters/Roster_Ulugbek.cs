using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    public static partial class Roster
    {
        public static FighterDefinition Ulugbek()
        {
            var starC = new Color(0.55f, 0.75f, 1f);
            var d = new FighterDefinition
            {
                id = "ulugbek", name = "MIRZO ULUG'BEK", title = "Olim podshoh", years = "1394 — 1449",
                bio = "Temuriylar hukmdori va buyuk astronom. Samarqand rasadxonasini qurib, 1018 yulduzni jadvalga kiritgan «Zij»ning muallifi.",
                quote = "«Ilm — yulduzlar kabi abadiydir.»",
                style = "Uzun hassa • Yulduz sehri • Masofadan jang",
                mainColor = Pal.Indigo, accentColor = Pal.Gold, energyColor = starC,
                walkFwd = 2.4f, walkBack = 2.2f, jumpVel = 11.2f, jumpX = 3.4f, damageMult = 0.95f, juggleWeight = 1f, dashSpeed = 7f,
                signatureFx = HitFx.Star,
            };
            d.buildVisual = t => FbxPuppet.Build("ulugbek", CharacterVisuals.BuildUlugbek, t);
            d.bounceAmp = 0.008f; d.bounceRate = 2.6f;
            d.introLine = "Har bir harakatingni yulduzlar allaqachon hisoblagan.";
            d.vsLines["temur"] = "Bobojon, ilm ham qilich kabi o'tkir.";
            d.vsLines["chingiz"] = "Osmon jadvalida sening yulduzing so'nmoqda.";
            d.vsLines["jaloliddin"] = "Tezliging chaqmoqdek, ammo yorug'lik tezroq.";
            d.vsLines["ulugbek"] = "Ko'zgudagi yulduz — haqiqiysi emas.";
            d.winLines = new[] { "Ilm — yulduzlar kabi abadiydir.", "Hisob-kitob aniq chiqdi.", "Zij'ga yangi g'alaba yulduzi qo'shildi." };
            var p = PoseLib.Ulugbek();
            d.anims = PoseLib.BuildBase(p);
            var cfg = new NormalsCfg { reach = 1.4f, power = 0.95f, speed = 0.95f, fx = HitFx.Blunt, hit = Sfx.HitLight, hitHeavy = Sfx.HitHeavy, trailColor = new Color(0.6f, 0.8f, 1f, 0.9f) };
            AddNormals(d, p, cfg);

            var str3 = Normal(d, p, "str3", "Falak zarbasi", "LP, LP, HP", "HP_w", "HP_s", "HP_f", 12, 4, 22, 66, HitLevel.Overhead, new Rect(0.2f, 0.6f, 1.4f, 1.1f), cfg, true);
            str3.trails = Trail.WeaponR; str3.knockdown = true; str3.knockback = new Vector2(3.5f, 5f); str3.fx = HitFx.Star;
            d.Get("LP2").Chain(Btn.HP, "str3");
            var lk2 = Normal(d, p, "lk2", "Qo'sh tepki", "LK, LK", "LK_w", "LK_s", null, 7, 3, 14, 40, HitLevel.Mid, new Rect(0.25f, 0.5f, 0.95f, 0.6f), cfg, false);
            lk2.trails = Trail.FootL; lk2.fx = HitFx.Blunt;
            d.Get("LK").Chain(Btn.LK, "lk2");

            var orb = Special(d, "orb", "Yulduz shari", "← → + LP", 17, 1, 24, 0, HitLevel.Mid, new Rect(0, 0, 0, 0));
            orb.clip = AnimClip.Attack("orb", p.stance, p["orb_w"], p["orb_s"], 17, 1, 24);
            orb.onFrame = (f, fr) =>
            {
                if (fr == 6) { SynthAudio.Play(Sfx.Magic, 0.6f); VFX.Emit(VFX.Kind.Star, f.rig.Pos(Bone.HandL), starC, 10, 1.5f, 0.25f, 0.5f, Vector3.zero, 1f); }
                if (fr == 17)
                {
                    var s = new ProjectileSpec
                    {
                        damage = 72, level = HitLevel.Mid, hitstun = 22, knockback = new Vector2(2.6f, 0), size = new Vector2(0.65f, 0.65f),
                        visual = ProjVisual.StarOrb, color = starC, fx = HitFx.Star, hitSfx = Sfx.Stars, lifetime = 2.6f
                    };
                    f.match.SpawnProjectile(s, f, f.pos + new Vector2(f.facing * 0.9f, 1.25f), new Vector2(f.facing * 6.5f, 0));
                    SynthAudio.Play(Sfx.Projectile, 0.8f, 1.2f);
                }
            };
            Input(d, "orb", Btn.LP, B, F);

            var sext = Special(d, "sextant", "Samarqand sekstanti", "↓ → + HP", 7, 15, 30, 32, HitLevel.Mid, new Rect(-0.1f, 0.6f, 1.4f, 2.0f));
            sext.hits = 3; sext.hitInterval = 5; sext.lastHitLaunch = true; sext.invulStart = 1; sext.invulEnd = 10; sext.trails = Trail.WeaponR;
            sext.knockback = new Vector2(0.8f, 6f); sext.fx = HitFx.Star; sext.hitSfx = Sfx.Stars; sext.hitstop = 5;
            sext.clip = new AnimClip("sextant").F(0, p.stance).F(4, p["sextant_w"], Ease.OutQuad).F(9, p["sextant_s"], Ease.OutExpo).F(22, p["sextant_s"], Ease.Linear).F(52, p.stance, Ease.InOutQuad);
            sext.onFrame = (f, fr) =>
            {
                if (fr >= 7 && fr <= 20)
                {
                    float t = (fr - 7) / 13f;
                    float ang = Mathf.Lerp(-30, 200, t) * Mathf.Deg2Rad;
                    Vector3 c = new Vector3(f.pos.x + f.facing * 0.2f, 0.9f, -0.2f);
                    Vector3 pnt = c + new Vector3(Mathf.Cos(ang) * f.facing * 1.3f, Mathf.Sin(ang) * 1.3f, 0);
                    VFX.Emit(VFX.Kind.Star, pnt, starC, 3, 0.6f, 0.35f, 0.6f, Vector3.up, 1f);
                    VFX.Emit(VFX.Kind.Glow, pnt, starC.WithA(0.6f), 1, 0.2f, 0.9f, 0.3f, Vector3.up, 0.2f);
                }
                if (fr == 7) SynthAudio.Play(Sfx.Stars, 1f);
            };
            Input(d, "sextant", Btn.HP, D, F);

            var rain = Special(d, "rain", "Yulduzlar yomg'iri", "↓ ← + HP", 18, 1, 32, 0, HitLevel.Overhead, new Rect(0, 0, 0, 0));
            rain.clip = new AnimClip("rain").F(0, p.stance).F(12, p["rain_s"], Ease.OutCubic).F(36, p["rain_s"], Ease.Linear).F(51, p.stance, Ease.InOutQuad);
            rain.onFrame = (f, fr) =>
            {
                if (fr == 12) { SynthAudio.Play(Sfx.Stars, 1f, 0.8f); VFX.Emit(VFX.Kind.Star, f.rig.weaponTipR.position, starC, 20, 3f, 0.3f, 0.8f, Vector3.up, 0.7f); }
                if (fr == 18 || fr == 26 || fr == 34)
                {
                    float off = fr == 18 ? 0 : fr == 26 ? -0.9f : 0.9f;
                    float x = f.opp.pos.x + off;
                    var s = new ProjectileSpec
                    {
                        damage = 38, level = HitLevel.Overhead, hitstun = 18, knockback = new Vector2(1f, 0), size = new Vector2(0.55f, 0.6f),
                        visual = ProjVisual.FallingStar, color = new Color(0.8f, 0.85f, 1f), fx = HitFx.Star, hitSfx = Sfx.Stars, lifetime = 2f, activationDelay = 14, reflectable = false
                    };
                    var pr = f.match.SpawnProjectile(s, f, new Vector2(x, 6.5f), new Vector2(0.6f * f.facing, -13f));
                }
            };
            Input(d, "rain", Btn.HP, D, B);

            var ring = Special(d, "ring", "Zij halqasi", "↓ ← + LK", 4, 22, 16, 22, HitLevel.Mid, new Rect(0.0f, 0.2f, 1.0f, 1.6f));
            ring.reflectStart = 4; ring.reflectEnd = 26; ring.knockback = new Vector2(4.5f, 0); ring.fx = HitFx.Star; ring.hitSfx = Sfx.Stars; ring.chip = 0;
            ring.clip = new AnimClip("ring").F(0, p.stance).F(4, p["ring_s"], Ease.OutExpo).F(26, p["ring_s"], Ease.Linear).F(42, p.stance, Ease.InOutQuad);
            ring.onFrame = (f, fr) =>
            {
                if (fr >= 4 && fr <= 26 && fr % 3 == 0)
                    VFX.Emit(VFX.Kind.Ring, new Vector3(f.pos.x + f.facing * 0.6f, 1.1f, -0.1f), starC.WithA(0.7f), 1, 0, 2.4f, 0.3f, default, 0);
                if (fr == 4) SynthAudio.Play(Sfx.Magic, 0.8f, 1.4f);
            };
            Input(d, "ring", Btn.LK, D, B);

            // --- Super: Koinot ilmi ---
            var sup = Special(d, "super", "Koinot ilmi", "HP + HK (3 bo'lak)", 10, 4, 30, 30, HitLevel.Mid, new Rect(0.1f, 0.2f, 1.9f, 1.7f));
            sup.kind = MoveKind.Super; sup.invulStart = 0; sup.invulEnd = 14; sup.trails = Trail.WeaponR; sup.fx = HitFx.Star;
            sup.clip = AnimClip.Attack("super", p.stance, p["orb_w"], p["orb_s"], 10, 4, 30);
            sup.onHit = (a, b) => a.match.StartCinematic(a, b, a.def.superScript, false);
            d.superMoveId = "super";
            d.superScript = c =>
            {
                var a = c.attacker; var df = c.defender; int fc = a.facing;
                var steps = new List<CineStep>
                {
                    new CineStep(0f, x => { x.cam.Shot(a.rig.Pos(Bone.Head) + new Vector3(fc * 1.0f, 0.1f, -1.8f), a.rig.Pos(Bone.Head), 30, 0.15f);
                        CineAnim(a, Hold(p["rain_s"]), 0.1f); a.fx.aura = 1; a.fx.auraColor = starC; SynthAudio.Play(Sfx.Gong, 1f, 0.9f); x.match.Announce("KOINOT ILMI", 1.4f, starC); x.match.SetDarkSky(true); }),
                    new CineStep(0.6f, x => { df.cinePhysics = true; df.vel = new Vector2(0, 5f); CineAnim(df, df.def.anims.juggle);
                        x.cam.Shot(Mid(x) + new Vector3(0, 1.8f, -5.5f), Mid(x) + Vector3.up * 1.8f, 38, 0.4f); SynthAudio.Play(Sfx.Stars, 1f); }),
                    new CineStep(0.95f, x => { df.vel = Vector2.zero; df.cinePhysics = false; x.match.Orrery(df, 2.2f, starC); }),
                };
                for (int i = 0; i < 7; i++)
                {
                    int k = i;
                    steps.Add(new CineStep(1.1f + i * 0.2f, x => { CineHit(x, 24, HitFx.Star, Sfx.Stars, 0.12f, 0.8f); df.anim.Flinch(new Vector3(k % 2 == 0 ? -20 : 20, 0, 0), 1f); }));
                }
                steps.Add(new CineStep(2.6f, x => { CineAnim(a, Strike(p["HP_w"], p["HP_s"], 0.1f)); x.match.ScreenFlash(starC, 0.4f); }));
                steps.Add(new CineStep(2.7f, x => { CineHit(x, 70, HitFx.Star, Sfx.Boom, 0.5f, 1.8f); df.cinePhysics = true; df.vel = new Vector2(fc * 4f, -6f); CineAnim(df, df.def.anims.juggle); VFX.Burst(df.rig.Pos(Bone.Chest), starC, 1.5f); }));
                steps.Add(new CineStep(3.1f, x => { CineAnim(df, df.def.anims.lying, 0.05f); SynthAudio.Play(Sfx.BodyFall, 1f); x.match.SetDarkSky(false); }));
                steps.Add(new CineStep(3.5f, x => { a.fx.aura = 0; CineAnim(a, Hold(p.stance), 0.2f); }));
                return steps;
            };

            d.finisherName = "ABADIY YULDUZ";
            d.finisherInput = new SpecialInput("finisher", Btn.LP, D, D, B);
            d.finisherScript = c =>
            {
                var a = c.attacker; var df = c.defender; int fc = a.facing;
                return new List<CineStep>
                {
                    new CineStep(0f, x => { x.cam.Shot(a.rig.Pos(Bone.Chest) + new Vector3(fc * 1.4f, -0.2f, -2.4f), a.rig.Pos(Bone.Head), 32, 0.4f);
                        CineAnim(a, Hold(p["rain_s"]), 0.3f); a.fx.aura = 1; a.fx.auraColor = starC; x.match.SetDarkSky(true); SynthAudio.Play(Sfx.Stars, 1f, 0.7f); }),
                    new CineStep(1.0f, x => { CineAnim(df, df.def.anims.juggle); df.cinePhysics = false; x.match.Orrery(df, 3f, starC);
                        x.cam.Shot(new Vector3(df.pos.x, 2.4f, -6f), new Vector3(df.pos.x, 2.6f, 0), 40, 0.6f); }),
                    new CineStep(1.2f, x => { x.match.FloatFighter(df, 3.2f, 1.8f); }),
                    new CineStep(2.5f, x => { VFX.Disintegrate(df.rig, new Color(0.8f, 0.9f, 1f), VFX.Kind.Star); df.rig.gameObject.SetActive(false); SynthAudio.Play(Sfx.Shatter, 1f, 1.3f);
                        x.match.ScreenFlash(starC, 0.4f); x.match.Constellation(new Vector3(df.pos.x, 4.5f, 2f)); }),
                    new CineStep(3.2f, x => { CineAnim(a, a.def.anims.victory, 0.2f); a.fx.aura = 0;
                        x.cam.Shot(a.rig.Pos(Bone.Chest) + new Vector3(fc * 2.2f, 0.4f, -3.4f), a.rig.Pos(Bone.Chest) + Vector3.up * 0.8f, 36, 1.2f); }),
                    new CineStep(5.0f, x => { x.match.SetDarkSky(false); }),
                };
            };
            return d;
        }
    }
}
