using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Zarbalarni aniqlash va natijani qo'llash: urish, blok, zirh, qarshi turish, snaryadlar.</summary>
    public static class CombatResolver
    {
        struct Pending { public Fighter att, def; public MoveData move; public int idx; public Vector3 point; }

        public static void Resolve(MatchController m)
        {
            var a = m.f1; var b = m.f2;
            var list = new List<Pending>(2);
            if (Check(a, b, out var pa)) list.Add(pa);
            if (Check(b, a, out var pb)) list.Add(pb);
            foreach (var p in list) ApplyHit(m, p.att, p.def, p.move, p.idx, p.point);
            ResolveProjectiles(m);
        }

        static bool CanBeHit(Fighter d)
        {
            if (d.invul > 0 || d.isKO) return false;
            switch (d.state)
            {
                case FState.Thrown:
                case FState.Throwing:
                case FState.Cinematic:
                case FState.Knockdown:
                case FState.GetUp:
                case FState.KO:
                case FState.Intro:
                case FState.Victory:
                    return false;
            }
            return true;
        }

        static bool Check(Fighter att, Fighter def, out Pending p)
        {
            p = default;
            if (!att.GetActiveHitbox(out Rect hb, out int idx)) return false;
            if (!CanBeHit(def)) return false;
            Rect hurt = def.HurtBox();
            if (!hb.Overlaps(hurt)) return false;
            float x = (Mathf.Max(hb.xMin, hurt.xMin) + Mathf.Min(hb.xMax, hurt.xMax)) * 0.5f;
            float y = (Mathf.Max(hb.yMin, hurt.yMin) + Mathf.Min(hb.yMax, hurt.yMax)) * 0.5f;
            p = new Pending { att = att, def = def, move = att.move, idx = idx, point = new Vector3(x, y, -0.35f) };
            return true;
        }

        public static void ApplyHit(MatchController m, Fighter att, Fighter def, MoveData move, int idx, Vector3 point)
        {
            if (move == null) return;
            // Qarshi turish (parry)
            if (def.InCounterWindow && move.level != HitLevel.Unblockable)
            {
                att.MarkHit(idx, false);
                att.hitstop = 14;
                def.hitstop = 4;
                VFX.HitSpark(point, HitFx.Gold, true, 1.4f, def.facing);
                var cm = def.def.Get(def.move.counterMove);
                def.StartMove(cm);
                m.cam.Shake(0.15f);
                return;
            }
            bool blocked = def.IsBlockingAgainst(move.level);
            bool lastHit = move.hits <= 1 || idx >= move.hits - 1;

            if (!blocked && def.HasArmor)
            {
                float ad = move.damage * att.def.damageMult * 0.6f;
                def.ApplyDamage(ad, att, false);
                def.flashTimer = 0.15f; def.flashColor = new Color(1f, 0.8f, 0.4f);
                att.MarkHit(idx, true);
                att.hitstop = def.hitstop = 6;
                VFX.HitSpark(point, HitFx.Gold, true, 1f, att.facing);
                SynthAudio.Play(Sfx.Clang, 0.9f, 0.8f);
                m.Announce("ZIRH!", 0.5f, Pal.Gold);
                return;
            }

            if (blocked)
            {
                float chip = move.damage * att.def.damageMult * (move.kind == MoveKind.Normal ? 0.02f : move.chip);
                def.OnBlocked(move, att, chip);
                att.MarkHit(idx, false);
                int hs = Mathf.Max(4, move.hitstop - 3);
                att.hitstop = def.hitstop = hs;
                VFX.HitSpark(point, move.fx, true, 0.8f, att.facing);
                SynthAudio.Play(move.fx == HitFx.Slash || move.fx == HitFx.Gold || move.fx == HitFx.Wind ? Sfx.Clang : Sfx.Block, 0.8f);
                att.meter = Mathf.Min(FightConst.MaxMeter, att.meter + move.meterGain * 0.4f);
                CornerPush(att, def, move.blockPush);
                m.cam.Shake(move.shake * 0.4f);
                m.OnBlock(att, def);
                return;
            }

            bool counter = def.InStartup;
            float scale = Mathf.Max(0.35f, Mathf.Pow(0.9f, def.comboHits));
            float dmg = move.damage * att.def.damageMult * scale / def.def.defenseMult * (counter ? 1.15f : 1f);
            Vector2 knock = move.knockback;
            bool launchNow = move.launch || (move.lastHitLaunch && lastHit);
            if (move.lastHitLaunch && lastHit) knock = new Vector2(2f, 9f);
            var temp = launchNow && !move.launch ? CloneWithLaunch(move) : move;
            def.OnHit(temp, att, dmg, knock, counter);
            att.MarkHit(idx, true);
            int stop = move.hitstop + (counter ? 3 : 0);
            att.hitstop = def.hitstop = stop;
            VFX.HitSpark(point, move.fx, false, move.hitstop >= 9 ? 1.3f : 0.9f, att.facing);
            SynthAudio.Play(move.hitSfx, 1f);
            if (move.hitSfx == Sfx.Slash || move.hitSfx == Sfx.SlashHeavy) SynthAudio.Play(Sfx.HitLight, 0.5f);
            m.cam.Shake(move.shake * (counter ? 1.5f : 1f));
            att.meter = Mathf.Min(FightConst.MaxMeter, att.meter + move.meterGain);
            if (!launchNow && !move.knockdown && !move.sweep) CornerPush(att, def, knock.x);
            move.onHit?.Invoke(att, def);
            m.OnHitLanded(att, def, move, counter, dmg);
        }

        static MoveData CloneWithLaunch(MoveData m)
        {
            return new MoveData { id = m.id, name = m.name, launch = true, knockback = m.knockback, hitbox = m.hitbox, level = m.level, hitstun = m.hitstun };
        }

        /// <summary>Burchakda bo'lsa — hujumchi orqaga suriladi (MK uslubi).</summary>
        static void CornerPush(Fighter att, Fighter def, float push)
        {
            float wall = FightConst.StageHalfWidth - 0.35f;
            bool cornered = Mathf.Abs(def.pos.x) >= wall && Mathf.Sign(def.pos.x) == att.facing;
            if (cornered && att.Grounded) att.vel.x = -att.facing * push * 0.8f;
        }

        // ---------------- Snaryadlar ----------------
        static void ResolveProjectiles(MatchController m)
        {
            var ps = m.projectiles;
            // To'qnashuv (clash)
            for (int i = 0; i < ps.Count; i++)
                for (int j = i + 1; j < ps.Count; j++)
                {
                    var p = ps[i]; var q = ps[j];
                    if (!p.Active || !q.Active || p.owner == q.owner || p.spec.damage <= 0 || q.spec.damage <= 0) continue;
                    if (p.Box.Overlaps(q.Box))
                    {
                        p.Kill(true); q.Kill(true);
                        SynthAudio.Play(Sfx.Boom, 0.6f, 1.3f);
                        m.cam.Shake(0.12f);
                    }
                }
            foreach (var p in ps)
            {
                if (!p.Active || p.spec.damage <= 0 || p.owner == null) continue;
                var target = p.owner.opp;
                if (target == null) continue;
                // Qaytarish (reflect)
                if (target.InReflectWindow && p.spec.reflectable)
                {
                    Rect zone = target.HurtBox();
                    zone.xMin -= 0.7f; zone.xMax += 0.7f;
                    if (zone.Overlaps(p.Box) && Mathf.Sign(p.vel.x) != target.facing) { p.Reflect(target); continue; }
                }
                if (!CanBeHit(target) || target.ProjectileInvul) continue;
                if (!p.Box.Overlaps(target.HurtBox())) continue;
                HitWithProjectile(m, p, target);
            }
            ps.RemoveAll(x => x == null || x.dead);
        }

        static void HitWithProjectile(MatchController m, Projectile p, Fighter def)
        {
            var s = p.spec;
            var att = p.owner;
            var fake = new MoveData
            {
                id = "proj", name = "Snaryad", damage = s.damage, level = s.level, hitstun = s.hitstun, blockstun = s.blockstun, knockback = s.knockback,
                launch = s.launch, knockdown = s.knockdown, hitstop = s.hitstop, fx = s.fx, hitSfx = s.hitSfx, kind = MoveKind.Special, chip = s.chip,
                hitbox = new Rect(0, p.pos.y, 0.1f, 0.1f), blockPush = 2.2f
            };
            Vector3 point = new Vector3(p.pos.x, p.pos.y, -0.35f);
            int dirSign = p.vel.x >= 0 ? 1 : -1;
            bool blocked = def.IsBlockingAgainst(s.level);
            if (def.InCounterWindow)
            {
                // Qalqon snaryadni ham qaytaradi
                if (s.reflectable) { p.Reflect(def); return; }
            }
            if (blocked)
            {
                def.OnBlocked(fake, att, s.damage * s.chip * att.def.damageMult);
                def.vel.x = dirSign * 2.2f;
                def.hitstop = 5;
                VFX.HitSpark(point, s.fx, true, 0.8f, dirSign);
                SynthAudio.Play(Sfx.Block, 0.8f);
                att.meter = Mathf.Min(FightConst.MaxMeter, att.meter + s.meterGain * 0.4f);
            }
            else
            {
                float scale = Mathf.Max(0.35f, Mathf.Pow(0.9f, def.comboHits));
                float dmg = s.damage * att.def.damageMult * scale / def.def.defenseMult;
                int oldFacing = att.facing;
                def.OnHit(fake, att, dmg, s.knockback, false);
                // Snaryad yo'nalishida itarish
                if (def.state == FState.Hitstun) def.vel.x = dirSign * s.knockback.x;
                def.hitstop = s.hitstop;
                VFX.HitSpark(point, s.fx, false, 1.1f, dirSign);
                SynthAudio.Play(s.hitSfx, 1f);
                m.cam.Shake(0.12f);
                att.meter = Mathf.Min(FightConst.MaxMeter, att.meter + s.meterGain);
                s.onHit?.Invoke(att, def);
                m.OnHitLanded(att, def, fake, false, dmg);
            }
            if (s.destroyOnHit) p.Kill(true);
        }
    }
}
