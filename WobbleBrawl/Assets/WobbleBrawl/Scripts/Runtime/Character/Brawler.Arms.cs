using UnityEngine;

namespace WobbleBrawl
{
    public sealed partial class Brawler
    {
        float lastSingleRelease = -10f;

        void DriveArms(float dt)
        {
            aimPitch = Mathf.MoveTowards(aimPitch, Mathf.Clamp(cmd.pitch, Tune.PitchMin, Tune.PitchMax), 360f * dt);
            bool conscious = IsConscious;
            DriveArm(0, handL, shoulderL, elbowL, foreArmL, shoulderLocalL, conscious && cmd.grabL);
            DriveArm(1, handR, shoulderR, elbowR, foreArmR, shoulderLocalR, conscious && cmd.grabR);

            carrying = false;
            if (conscious)
            {
                CarryAssist();
                ClimbAssist();
            }
        }

        void DriveArm(int s, Hand hand, Muscle shoulder, Muscle elbow, Rigidbody fore, Vector3 shoulderLocal, bool wantHold)
        {
            ref Strike st = ref armStrike[s];
            if (!wantHold && hand.IsHolding) ReleaseHand(hand);
            hand.wantGrab = wantHold && st.phase == 0;

            if (!IsConscious)
            {
                shoulder.SetTarget(Quaternion.identity);
                elbow.SetTarget(Quaternion.identity);
                return;
            }

            float side = s == 0 ? -1f : 1f;
            Quaternion face = FacingRotation;
            Vector3 dir;
            float bend;

            if (st.phase == 1)
            {
                dir = face * new Vector3(side * 0.15f, -0.65f, 0.2f).normalized;
                bend = 125f;
            }
            else if (st.phase == 2)
            {
                dir = st.dir;
                bend = 0f;
            }
            else if (wantHold || hand.IsHolding)
            {
                dir = face * (Quaternion.Euler(-aimPitch, side * 7f, 0f) * Vector3.forward);
                bend = hand.IsHolding ? 12f : 4f;
            }
            else if (st.phase == 3)
            {
                dir = face * new Vector3(side * 0.1f, -0.7f, 0.4f).normalized;
                bend = 95f;
            }
            else if (!grounded && airTime > 0.15f)
            {
                // flailing arms in the air
                float flap = Mathf.Sin(Time.time * 14f + s) * 0.25f;
                dir = face * new Vector3(side * 0.85f, 0.35f + flap, 0.15f).normalized;
                bend = 30f;
            }
            else
            {
                float swing = Mathf.Sin(gaitPhase) * (s == 0 ? -1f : 1f) * 0.55f * speed01;
                dir = face * new Vector3(side * 0.22f, -1f, swing).normalized;
                bend = 15f + 15f * speed01;
            }

            SetArmPose(shoulder, elbow, dir, bend);

            // reach assist: pull the fist towards the aim point so grabbing feels responsive
            if (wantHold && !hand.IsHolding && st.phase == 0)
            {
                Vector3 shoulderW = chest.transform.TransformPoint(shoulderLocal);
                Vector3 target = shoulderW + dir * Tune.ReachLength;
                Vector3 err = target - hand.Fist;
                Vector3 relVel = fore.linearVelocity - chest.linearVelocity;
                fore.AddForce(err * Tune.ReachForce - relVel * Tune.ReachDamping, ForceMode.Acceleration);
            }
        }

        void SetArmPose(Muscle shoulder, Muscle elbow, Vector3 dirWorld, float elbowBend)
        {
            Quaternion face = FacingRotation;
            Vector3 local = Quaternion.Inverse(face) * dirWorld;
            if (local.sqrMagnitude < 0.0001f) local = Vector3.down;
            // keep away from the singular "straight up" direction of FromToRotation
            if (local.y > 0.98f) local = new Vector3(local.x, 0.98f, 0.2f).normalized;
            Quaternion world = face * Quaternion.FromToRotation(Vector3.down, local);
            shoulder.SetTarget(Quaternion.Inverse(chest.rotation) * world);
            elbow.SetTarget(Muscle.Flex(elbowBend));
        }

        static bool SameTarget(Hand h, Brawler victim, Rigidbody body)
        {
            if (!h.IsHolding) return false;
            return victim != null ? h.heldBrawler == victim : body != null && h.heldBody == body;
        }

        void ReleaseHand(Hand hand)
        {
            var victim = hand.heldBrawler;
            var body = hand.heldBody;
            float heldFor = Time.time - hand.heldSince;
            Hand other = hand == handL ? handR : handL;
            bool wasTwoHanded = SameTarget(other, victim, body);
            hand.Release(0.12f);

            if (wasTwoHanded)
            {
                lastSingleRelease = Time.time;
                return; // the other hand still holds on; the throw happens when it lets go
            }

            bool twoHandThrow = Time.time - lastSingleRelease < 0.25f;
            if (aimPitch < 25f || heldFor < 0.2f) return;

            float k = twoHandThrow ? 1f : 0.55f;
            Vector3 v = (facing * Tune.ThrowForward + Vector3.up * Tune.ThrowUp) * k;
            if (victim != null && !victim.IsOut)
            {
                victim.AddVelocity(v);
                victim.LastAttacker = this;
                victim.LastAttackTime = Time.time;
            }
            else if (body != null && !body.isKinematic && body.mass < 120f)
            {
                body.AddForce(v * Mathf.Clamp(40f / body.mass, 0.4f, 1.2f), ForceMode.VelocityChange);
            }
            else return;

            Sfx.Play(Sfx.Whoosh, chest.position, 0.8f, 0.7f);
            Sfx.Play(Sfx.RandomGrunt(), head.position, 0.7f, VoicePitch);
        }

        void CarryAssist()
        {
            if (!handL.IsHolding || !handR.IsHolding) return;
            float lift = Mathf.Clamp01((aimPitch + 15f) / 55f);

            var victim = handL.heldBrawler;
            if (victim != null && victim == handR.heldBrawler && !victim.IsOut)
            {
                carrying = true;
                float comp = (victim.IsConscious ? Tune.CarryGravityCompConscious : Tune.CarryGravityCompUnconscious) * lift;
                foreach (var rb in victim.bodies) rb.AddForce(-Physics.gravity * comp, ForceMode.Acceleration);
                return;
            }

            var body = handL.heldBody;
            if (body != null && body == handR.heldBody && !body.isKinematic && body.GetComponent<BodyPart>() == null)
            {
                carrying = true;
                if (body.mass < 150f) body.AddForce(-Physics.gravity * 0.7f * lift, ForceMode.Acceleration);
            }
        }

        void ClimbAssist()
        {
            int n = 0;
            Vector3 grip = Vector3.zero;
            if (handL.IsHolding && handL.heldWorld) { grip += handL.Fist; n++; }
            if (handR.IsHolding && handR.heldWorld) { grip += handR.Fist; n++; }
            if (n == 0) return;
            grip /= n;

            float k = n == 2 ? 1f : 0.55f;
            if (!grounded)
            {
                // hanging is hard enough already — take some weight off the arms
                foreach (var rb in bodies) rb.AddForce(-Physics.gravity * 0.22f * k, ForceMode.Acceleration);
            }

            float above = grip.y - chest.position.y;
            bool pulling = cmd.jump || (aimPitch < 10f && cmd.move.sqrMagnitude > 0.1f);
            if (pulling && above > -0.35f)
            {
                chest.AddForce(Vector3.up * Tune.ClimbLift * k, ForceMode.Acceleration);
                pelvis.AddForce(Vector3.up * Tune.ClimbLift * 0.8f * k, ForceMode.Acceleration);
            }
            if (above < 0.15f && cmd.move.sqrMagnitude > 0.1f)
            {
                Vector3 f = cmd.move.normalized * Tune.ClimbForward;
                chest.AddForce(f, ForceMode.Acceleration);
                pelvis.AddForce(f, ForceMode.Acceleration);
            }
        }
    }
}
