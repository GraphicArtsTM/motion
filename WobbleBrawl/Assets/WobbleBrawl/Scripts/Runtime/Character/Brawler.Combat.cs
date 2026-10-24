using UnityEngine;

namespace WobbleBrawl
{
    public sealed partial class Brawler
    {
        struct Strike
        {
            public AttackKind kind;
            public int phase;   // 0 idle, 1 windup, 2 strike, 3 recover
            public float t;
            public Vector3 dir;
            public int side;
        }

        readonly Strike[] armStrike = new Strike[2];
        Strike legStrike, headStrike;
        int nextPunchSide, nextKickSide = 1;

        bool IsStriking => armStrike[0].phase == 2 || armStrike[1].phase == 2 || legStrike.phase == 2 || headStrike.phase == 2;

        // ------------------------------------------------------------------ starting attacks

        void StartPunch()
        {
            // holding someone with both hands turns the punch into a headbutt
            if (handL.IsHolding && handR.IsHolding)
            {
                StartHeadbutt();
                return;
            }

            int s = nextPunchSide;
            if (HandOf(s).IsHolding || armStrike[s].phase == 1 || armStrike[s].phase == 2) s = 1 - s;
            if (HandOf(s).IsHolding || armStrike[s].phase == 1 || armStrike[s].phase == 2) return;

            armStrike[s] = new Strike { kind = AttackKind.Punch, phase = 1, side = s };
            nextPunchSide = 1 - s;
            SoftLockOnFoe();
        }

        void StartKick()
        {
            if (legStrike.phase != 0) return;
            if (!grounded && airTime > 0.06f)
            {
                legStrike = new Strike { kind = AttackKind.DropKick, phase = 2, side = 2 };
                SoftLockOnFoe();
                Vector3 right = Vector3.Cross(Vector3.up, facing);
                pelvis.AddForce(facing * 4f + Vector3.up * 1.2f, ForceMode.VelocityChange);
                chest.AddTorque(-right * 9f, ForceMode.VelocityChange);
                foreach (var shin in new[] { shinL, shinR })
                {
                    shin.AddForce(facing * Tune.KickSpeed, ForceMode.VelocityChange);
                    PartOf(shin).BeginAttack(AttackKind.DropKick);
                }
                flopTimer = Tune.DropKickTime + Tune.DropKickFlop;
                Sfx.Play(Sfx.Whoosh, pelvis.position, 0.7f, 0.8f);
                Sfx.Play(Sfx.RandomGrunt(), head.position, 0.6f, VoicePitch);
                return;
            }
            legStrike = new Strike { kind = AttackKind.Kick, phase = 1, side = nextKickSide };
            nextKickSide = 1 - nextKickSide;
            SoftLockOnFoe();
        }

        void StartHeadbutt()
        {
            if (headStrike.phase != 0) return;
            headStrike = new Strike { kind = AttackKind.Headbutt, phase = 1 };
        }

        Hand HandOf(int side) => side == 0 ? handL : handR;

        void SoftLockOnFoe()
        {
            var foe = FindFoe(Tune.AutoAimRange, out _);
            if (foe == null) return;
            Vector3 to = foe.pelvis.position - pelvis.position;
            to.y = 0f;
            if (to.sqrMagnitude > 0.01f) facing = Vector3.Slerp(facing, to.normalized, 0.7f).normalized;
        }

        public Brawler FindFoe(float range, out Vector3 aimPoint)
        {
            Brawler best = null;
            float bestScore = float.MaxValue;
            aimPoint = Vector3.zero;
            foreach (var b in All)
            {
                if (b == this || b.IsOut) continue;
                Vector3 to = b.head.position - chest.position;
                float d = to.magnitude;
                if (d > range) continue;
                Vector3 flat = new Vector3(to.x, 0f, to.z);
                float dot = flat.sqrMagnitude > 0.0001f ? Vector3.Dot(flat.normalized, facing) : 1f;
                if (dot < 0.2f) continue;
                float score = d - dot;
                if (score < bestScore)
                {
                    bestScore = score;
                    best = b;
                    aimPoint = b.IsKnockedOut ? b.chest.position : b.head.position;
                }
            }
            return best;
        }

        // ------------------------------------------------------------------ strike phases

        void TickStrikes(float dt)
        {
            if (!IsConscious)
            {
                EndAllStrikes();
                return;
            }
            for (int s = 0; s < 2; s++) TickArm(s, dt);
            TickLeg(dt);
            TickHead(dt);
        }

        void TickArm(int s, float dt)
        {
            ref Strike st = ref armStrike[s];
            if (st.phase == 0) return;
            st.t += dt;
            var fore = s == 0 ? foreArmL : foreArmR;
            var upper = s == 0 ? upperArmL : upperArmR;
            switch (st.phase)
            {
                case 1:
                    if (st.t >= Tune.PunchWindup)
                    {
                        st.phase = 2; st.t = 0f;
                        Vector3 shoulder = chest.transform.TransformPoint(s == 0 ? shoulderLocalL : shoulderLocalR);
                        Vector3 target = FindFoe(Tune.AutoAimRange, out var aim) != null
                            ? aim
                            : shoulder + facing * 0.8f + Vector3.down * 0.05f;
                        st.dir = (target - shoulder).normalized;
                        fore.AddForce(st.dir * Tune.PunchSpeed, ForceMode.VelocityChange);
                        upper.AddForce(st.dir * Tune.PunchSpeed * 0.35f, ForceMode.VelocityChange);
                        chest.AddForce(facing * 0.6f, ForceMode.VelocityChange);
                        PartOf(fore).BeginAttack(AttackKind.Punch);
                        Sfx.Play(Sfx.Whoosh, fore.position, 0.35f, Random.Range(1.2f, 1.5f));
                    }
                    break;
                case 2:
                    if (st.t >= Tune.PunchStrike)
                    {
                        st.phase = 3; st.t = 0f;
                        PartOf(fore).EndAttack();
                    }
                    break;
                case 3:
                    if (st.t >= Tune.PunchRecover) st.phase = 0;
                    break;
            }
        }

        void TickLeg(float dt)
        {
            if (legStrike.phase == 0) return;
            legStrike.t += dt;
            if (legStrike.kind == AttackKind.DropKick)
            {
                if (legStrike.t >= Tune.DropKickTime)
                {
                    PartOf(shinL).EndAttack();
                    PartOf(shinR).EndAttack();
                    legStrike.phase = 0;
                }
                return;
            }

            var shin = legStrike.side == 0 ? shinL : shinR;
            var thigh = legStrike.side == 0 ? thighL : thighR;
            switch (legStrike.phase)
            {
                case 1:
                    if (legStrike.t >= Tune.KickWindup)
                    {
                        legStrike.phase = 2; legStrike.t = 0f;
                        Vector3 dir = (facing + Vector3.up * 0.3f).normalized;
                        shin.AddForce(dir * Tune.KickSpeed, ForceMode.VelocityChange);
                        thigh.AddForce(dir * Tune.KickSpeed * 0.4f, ForceMode.VelocityChange);
                        pelvis.AddForce(-facing * 0.8f, ForceMode.VelocityChange);
                        PartOf(shin).BeginAttack(AttackKind.Kick);
                        Sfx.Play(Sfx.Whoosh, shin.position, 0.45f, Random.Range(0.9f, 1.1f));
                    }
                    break;
                case 2:
                    if (legStrike.t >= Tune.KickStrike)
                    {
                        legStrike.phase = 3; legStrike.t = 0f;
                        PartOf(shin).EndAttack();
                    }
                    break;
                case 3:
                    if (legStrike.t >= Tune.KickRecover) legStrike.phase = 0;
                    break;
            }
        }

        void TickHead(float dt)
        {
            if (headStrike.phase == 0) return;
            headStrike.t += dt;
            switch (headStrike.phase)
            {
                case 1:
                    if (headStrike.t >= Tune.HeadbuttWindup)
                    {
                        headStrike.phase = 2; headStrike.t = 0f;
                        head.AddForce(facing * Tune.HeadbuttSpeed, ForceMode.VelocityChange);
                        chest.AddForce(facing * 2.5f, ForceMode.VelocityChange);
                        PartOf(head).BeginAttack(AttackKind.Headbutt);
                        Sfx.Play(Sfx.RandomGrunt(), head.position, 0.6f, VoicePitch);
                    }
                    break;
                case 2:
                    if (headStrike.t >= Tune.HeadbuttStrike)
                    {
                        headStrike.phase = 3; headStrike.t = 0f;
                        PartOf(head).EndAttack();
                    }
                    break;
                case 3:
                    if (headStrike.t >= Tune.HeadbuttRecover) headStrike.phase = 0;
                    break;
            }
        }

        void EndAllStrikes()
        {
            armStrike[0].phase = armStrike[1].phase = 0;
            legStrike.phase = 0;
            headStrike.phase = 0;
            if (parts == null) return;
            foreach (var p in parts) p.EndAttack();
        }

        // ------------------------------------------------------------------ hits & damage

        public void OnPartCollision(BodyPart part, Collision c)
        {
            if (IsOut) return;
            float rel = c.relativeVelocity.magnitude;
            Vector3 point = c.contactCount > 0 ? c.GetContact(0).point : part.rb.position;
            var otherRb = c.rigidbody;
            var otherPart = otherRb != null ? otherRb.GetComponent<BodyPart>() : null;

            if (otherPart != null)
            {
                if (otherPart.owner == this) return;
                if (otherPart.attack != AttackKind.None) otherPart.owner.ResolveStrike(otherPart, part, point, rel);
                else if (rel > 9f && part.kind == PartKind.Head) TakeDamage((rel - 9f) * 2f, point, null); // thrown bodies colliding
                return;
            }

            bool prop = otherRb != null && !otherRb.isKinematic;
            float threshold = prop ? 6.5f : part.kind == PartKind.Head ? 9f : 13f;
            if (rel > threshold)
                TakeDamage((rel - threshold) * (prop ? 5f : 3f), point, null);

            if (rel > 3.5f && Time.time > nextThudTime)
            {
                nextThudTime = Time.time + 0.12f;
                Sfx.Play(Sfx.Thud, point, Mathf.Clamp01(rel / 12f), Random.Range(0.8f, 1.2f));
                if (rel > 6f) Fx.Dust(point, Mathf.RoundToInt(rel * 0.6f));
            }
        }

        public void ResolveStrike(BodyPart weapon, BodyPart target, Vector3 point, float relSpeed)
        {
            var victim = target.owner;
            if (victim == this || victim.IsOut) return;
            if (!weapon.struck.Add(victim)) return;

            float baseDamage;
            float knock;
            switch (weapon.attack)
            {
                case AttackKind.Kick: baseDamage = Tune.KickDamage; knock = 4.5f; break;
                case AttackKind.Headbutt: baseDamage = Tune.HeadbuttDamage; knock = 4f; break;
                case AttackKind.DropKick: baseDamage = Tune.DropKickDamage; knock = 7f; break;
                default: baseDamage = Tune.PunchDamage; knock = 3f; break;
            }
            float speedK = Mathf.Clamp(relSpeed / 6f, 0.5f, 1.6f);
            float partK = target.kind == PartKind.Head ? Tune.HeadMultiplier
                : target.kind == PartKind.Chest || target.kind == PartKind.Pelvis ? 1f : Tune.LimbMultiplier;
            float damage = baseDamage * speedK * partK * GameManager.DamageMultiplier;

            Vector3 dir = target.rb.position - weapon.rb.position;
            dir.y = 0f;
            if (dir.sqrMagnitude < 0.0001f) dir = facing;
            dir.Normalize();
            target.rb.AddForce((dir + Vector3.up * 0.25f) * knock, ForceMode.VelocityChange);
            victim.chest.AddForce(dir * knock * 0.4f, ForceMode.VelocityChange);

            victim.TakeDamage(damage, point, this);
            if (weapon.attack == AttackKind.Headbutt) TakeDamage(3f, head.position, null);

            Fx.Hit(point, damage);
            bool big = damage > 18f;
            Sfx.Play(big ? Sfx.Smack : Sfx.Punch, point, Mathf.Clamp(damage / 25f, 0.4f, 1f), Random.Range(0.85f, 1.15f));
            GameManager.I?.Shake(Mathf.Clamp01(damage / 40f) * 0.45f);
            participant?.slot?.Rumble(0.2f, 0.5f, 0.12f);
            victim.participant?.slot?.Rumble(0.6f, 0.3f, 0.2f);
        }

        public void TakeDamage(float amount, Vector3 point, Brawler attacker)
        {
            if (IsOut || amount <= 0f) return;
            if (attacker != null)
            {
                LastAttacker = attacker;
                LastAttackTime = Time.time;
            }
            lastDamageTime = Time.time;
            face?.Hurt();

            if (IsKnockedOut)
            {
                koTimer = Mathf.Min(koTimer + amount * 0.02f, 8f);
                return;
            }

            consciousness -= amount;
            if (amount >= 12f) staggerTimer = Tune.StaggerTime;
            if (amount > 5f) Sfx.Play(Sfx.RandomGrunt(), head.position, 0.55f, VoicePitch);
            if (consciousness <= 0f)
                Knockout(Tune.KnockoutBase + Mathf.Min(3f, -consciousness * 0.05f), attacker);
        }

        public void Knockout(float duration, Brawler attacker)
        {
            if (IsOut) return;
            koTimer = duration;
            consciousness = 0f;
            handL.Release(0.5f);
            handR.Release(0.5f);
            EndAllStrikes();
            Sfx.Play(Sfx.KO, head.position, 0.8f, 1f);
            Fx.Stars(head.position, 10);
            GameManager.I?.NotifyKnockout(this, attacker);
        }
    }
}
