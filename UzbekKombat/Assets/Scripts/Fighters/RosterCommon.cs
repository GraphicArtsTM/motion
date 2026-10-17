using System;
using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Qahramonlar ro'yxati va umumiy harakatlar (normal zarbalar) yaratuvchi.</summary>
    public static partial class Roster
    {
        static List<FighterDefinition> all;

        public static List<FighterDefinition> All
        {
            get
            {
                if (all == null) all = new List<FighterDefinition> { Temur(), Jaloliddin(), Ulugbek(), Chingiz() };
                return all;
            }
        }

        // Yo'nalish yozuvlari (nisbiy numpad)
        public const int B = 4, F = 6, D = 2, U = 8, DF = 3, DB = 1;

        public class NormalsCfg
        {
            public float reach = 1f;
            public float power = 1f;
            public HitFx fx = HitFx.Slash;
            public Sfx hit = Sfx.Slash, hitHeavy = Sfx.SlashHeavy;
            public int weaponTrail = Trail.WeaponR;
            public int heavyTrail = Trail.WeaponR;
            public float speed = 1f; // >1 — tezroq
            public Color trailColor = new Color(1f, 0.85f, 0.55f, 0.9f);
            public bool hpOverhead;
        }

        static int Fr(float f, NormalsCfg c) => Mathf.Max(1, Mathf.RoundToInt(f / c.speed));

        static MoveData Normal(FighterDefinition d, CharPoses p, string id, string name, string notation, string wind, string strike, string follow,
            int s, int a, int r, float dmg, HitLevel lvl, Rect box, NormalsCfg c, bool heavy, bool crouching = false, bool air = false)
        {
            var m = new MoveData
            {
                id = id, name = name, notation = notation, kind = MoveKind.Normal,
                startup = Fr(s, c), active = a, recovery = Fr(r, c),
                damage = dmg * c.power, level = lvl,
                hitbox = new Rect(box.x, box.y, box.width * (box.width > 0.6f ? c.reach : 1f), box.height),
                hitstun = heavy ? 22 : 16, blockstun = heavy ? 14 : 10,
                knockback = new Vector2(heavy ? 3f : 1.8f, 0),
                hitstop = heavy ? 9 : 6,
                meterGain = heavy ? 12 : 7,
                fx = c.fx, hitSfx = heavy ? c.hitHeavy : c.hit,
                whoosh = heavy ? Sfx.WhooshHeavy : Sfx.WhooshLight,
                shake = heavy ? 0.14f : 0.06f,
                crouching = crouching, air = air,
                trailColor = c.trailColor,
            };
            Pose ready = air ? PoseLib.JumpTuck(p.stance) : crouching ? p.crouch : p.stance;
            m.clip = AnimClip.Attack(id, ready, p[wind], p[strike], m.startup, m.active, m.recovery, follow != null ? p[follow] : null, !air);
            return d.Add(m);
        }

        /// <summary>Barcha qahramonlar uchun standart normal zarbalar to'plami.</summary>
        static void AddNormals(FighterDefinition d, CharPoses p, NormalsCfg c)
        {
            float R = c.reach;
            var lp = Normal(d, p, "LP", "Tez zarba", "LP", "LP_w", "LP_s", null, 6, 3, 10, 34, HitLevel.High, new Rect(0.25f, 1.15f, 0.95f, 0.45f), c, false);
            lp.trails = c.weaponTrail;
            var lp2 = Normal(d, p, "LP2", "Qaytma zarba", "LP, LP", "LP2_w", "LP2_s", null, 7, 3, 13, 38, HitLevel.High, new Rect(0.25f, 1.1f, 0.95f, 0.45f), c, false);
            lp2.trails = c.weaponTrail;
            lp.Chain(Btn.LP, "LP2");

            var hp = Normal(d, p, "HP", "Kuchli zarba", "HP", "HP_w", "HP_s", "HP_f", 13, 4, 20, 88, c.hpOverhead ? HitLevel.Overhead : HitLevel.Mid, new Rect(0.2f, 0.7f, 1.05f, 1.0f), c, true);
            hp.trails = c.heavyTrail;
            hp.knockback = new Vector2(3.2f, 0);
            hp.moveVel = new Vector2(1.6f, 0); hp.moveStart = 4; hp.moveEnd = hp.startup;

            var lk = Normal(d, p, "LK", "Yengil tepki", "LK", "LK_w", "LK_s", null, 7, 3, 13, 42, HitLevel.Mid, new Rect(0.25f, 0.5f, 0.95f, 0.5f), c, false);
            lk.trails = Trail.FootL; lk.fx = HitFx.Blunt; lk.hitSfx = Sfx.HitLight;
            var hk = Normal(d, p, "HK", "Kuchli tepki", "HK", "HK_w", "HK_s", null, 12, 4, 20, 84, HitLevel.High, new Rect(0.2f, 1.05f, 1.05f, 0.55f), c, true);
            hk.trails = Trail.FootR; hk.fx = HitFx.Blunt; hk.hitSfx = Sfx.HitHeavy;
            hk.knockdown = true; hk.knockback = new Vector2(3.5f, 5f);

            var clp = Normal(d, p, "cLP", "Past kesish", "↓ + LP", "cLP_w", "cLP_s", null, 6, 3, 11, 30, HitLevel.Low, new Rect(0.2f, 0.15f, 1.0f, 0.55f), c, false, true);
            clp.trails = c.weaponTrail;
            var chp = Normal(d, p, "cHP", "Ko'tarma zarba", "↓ + HP", "cHP_w", "cHP_s", null, 9, 5, 24, 82, HitLevel.Mid, new Rect(0.05f, 0.7f, 0.95f, 1.5f), c, true, true);
            chp.trails = c.heavyTrail;
            chp.launch = true; chp.knockback = new Vector2(1.2f, 11f);
            chp.invulStart = 2; chp.invulEnd = 7; // anti-air
            chp.clip.grounded = true;
            var clk = Normal(d, p, "cLK", "Past tepki", "↓ + LK", "cLK_s", "cLK_s", null, 6, 3, 12, 26, HitLevel.Low, new Rect(0.25f, 0.0f, 1.0f, 0.35f), c, false, true);
            clk.trails = Trail.FootL; clk.fx = HitFx.Blunt; clk.hitSfx = Sfx.HitLight;
            var chk = Normal(d, p, "cHK", "Oyoqdan chalish", "↓ + HK", "cHK_w", "cHK_s", null, 10, 4, 26, 68, HitLevel.Low, new Rect(0.15f, 0.0f, 1.2f, 0.35f), c, true, true);
            chk.trails = Trail.FootR; chk.fx = HitFx.Earth; chk.hitSfx = Sfx.HitHeavy;
            chk.sweep = true; chk.knockdown = true;

            var jlp = Normal(d, p, "jLP", "Havodan zarba", "↑ LP", "jP_w", "jP_s", null, 6, 6, 8, 42, HitLevel.Overhead, new Rect(0.05f, 0.5f, 1.0f, 0.9f), c, false, false, true);
            jlp.trails = c.weaponTrail;
            var jhp = Normal(d, p, "jHP", "Havodan chopish", "↑ HP", "jP_w", "jP_s", null, 9, 7, 10, 72, HitLevel.Overhead, new Rect(0.05f, 0.4f, 1.1f, 1.0f), c, true, false, true);
            jhp.trails = c.heavyTrail;
            var jlk = Normal(d, p, "jLK", "Uchar tepki", "↑ LK", "jK_s", "jK_s", null, 6, 8, 8, 46, HitLevel.Overhead, new Rect(0.05f, 0.15f, 1.0f, 0.7f), c, false, false, true);
            jlk.trails = Trail.FootL; jlk.fx = HitFx.Blunt; jlk.hitSfx = Sfx.HitLight;
            var jhk = Normal(d, p, "jHK", "Uchar kuchli tepki", "↑ HK", "jHK_s", "jHK_s", null, 8, 8, 10, 76, HitLevel.Overhead, new Rect(0.05f, 0.25f, 1.1f, 0.8f), c, true, false, true);
            jhk.trails = Trail.FootR; jhk.fx = HitFx.Blunt; jhk.hitSfx = Sfx.HitHeavy;

            var th = new MoveData
            {
                id = "throw", name = "Otish", notation = "O (yaqin)", kind = MoveKind.Throw, isThrow = true,
                startup = 5, active = 2, recovery = 26, throwRange = 1.15f, throwDamage = 120 * c.power, hitbox = new Rect(0, 0, 0, 0),
            };
            th.clip = new AnimClip("throwTry").K(0, p.stance).K(0.08f, p.stance.Clone().A(Bone.UpperArmR, -60).A(Bone.UpperArmL, -60).A(Bone.Spine, 10), Ease.OutQuad).K(0.5f, p.stance, Ease.InOutQuad);
            d.Add(th);
        }

        static MoveData Special(FighterDefinition d, string id, string name, string notation, int s, int a, int r, float dmg, HitLevel lvl, Rect box)
        {
            var m = new MoveData
            {
                id = id, name = name, notation = notation, kind = MoveKind.Special,
                startup = s, active = a, recovery = r, damage = dmg, level = lvl, hitbox = box,
                hitstun = 22, blockstun = 16, chip = 0.15f, knockback = new Vector2(3f, 0), hitstop = 9, meterGain = 14,
                whoosh = Sfx.WhooshHeavy, hitSfx = Sfx.SlashHeavy, shake = 0.16f, fx = d.signatureFx, trailColor = d.energyColor.WithA(0.95f)
            };
            return d.Add(m);
        }

        static void Input(FighterDefinition d, string id, Btn b, params int[] motion) => d.specials.Add(new SpecialInput(id, b, motion));

        // ================== Kinematik yordamchilar ==================
        public static void CineHit(CineContext c, float dmg, HitFx fx, Sfx sfx, float shake = 0.2f, float power = 1f)
        {
            var d = c.defender;
            d.ApplyDamage(dmg * c.attacker.def.damageMult, c.attacker, false);
            d.comboHits++;
            Vector3 p = d.rig.Pos(Bone.Chest) + new Vector3(0, 0, -0.4f);
            VFX.HitSpark(p, fx, false, power, c.attacker.facing);
            SynthAudio.Play(sfx, 1f);
            d.anim.Flinch(new Vector3(-18, 0, 0), 1.2f);
            d.flashTimer = 0.12f;
            c.cam.Shake(shake);
            c.match.HitStopVisual(0.05f);
        }

        public static void CineAnim(Fighter f, AnimClip clip, float fade = 0.06f) => f.anim.Play(clip, fade);

        public static AnimClip Hold(Pose p) => new AnimClip("hold", true).K(0, p);

        public static AnimClip Strike(Pose from, Pose to, float t = 0.08f, Ease e = Ease.OutExpo) => new AnimClip("cineStrike").K(0, from).K(t, to, e);

        public static Vector3 Mid(CineContext c) => new Vector3((c.attacker.pos.x + c.defender.pos.x) / 2f, 0, 0);
    }
}
