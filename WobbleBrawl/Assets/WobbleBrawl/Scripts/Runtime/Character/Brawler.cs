using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Active-ragdoll fighter. Nothing is animated: every pose is a set of muscle targets that the
    /// physics engine tries (and often fails) to reach, which is where all the comedy comes from.
    ///
    /// Each physics step:
    ///   1. sense the ground (sphere-cast from the pelvis)
    ///   2. update consciousness / knockout / get-up state
    ///   3. balance: upright torque on pelvis and chest + a "hover" spring that carries body weight
    ///   4. locomotion: velocity-tracking acceleration on the torso, procedural gait on the legs
    ///   5. arms: reach / grab / punch / carry / climb
    /// </summary>
    public sealed partial class Brawler : MonoBehaviour
    {
        public static readonly List<Brawler> All = new List<Brawler>();

        public Participant participant;
        public IBrain brain;

        [System.NonSerialized] public Rigidbody pelvis, chest, head, upperArmL, upperArmR, foreArmL, foreArmR, thighL, thighR, shinL, shinR;
        [System.NonSerialized] public Muscle spine, neck, shoulderL, shoulderR, elbowL, elbowR, hipL, hipR, kneeL, kneeR;
        [System.NonSerialized] public Hand handL, handR;
        [System.NonSerialized] public Vector3 shoulderLocalL, shoulderLocalR;
        [System.NonSerialized] public BrawlerFace face;
        [System.NonSerialized] public BrawlerCommand cmd;

        BodyPart[] parts;
        Rigidbody[] bodies;
        Vector3[] restLocal;
        CollisionDetectionMode[] collisionModes;
        readonly HashSet<Collider> own = new HashSet<Collider>();
        GameObject crown;

        // --- state ---
        float consciousness = Tune.MaxConsciousness;
        float koTimer, staggerTimer, flopTimer, jumpCooldown, airTime, struggle;
        float wakeBlend = 1f;
        float lastDamageTime = -10f, nextThudTime;
        bool grounded, onIce, carrying;
        Vector3 groundPoint, groundVelocity;
        Rigidbody groundBody;
        Vector3 facing = Vector3.forward;
        float gaitPhase, aimPitch, speed01;

        static readonly RaycastHit[] castHits = new RaycastHit[24];

        public IReadOnlyList<Rigidbody> Bodies => bodies;
        public float TotalMass { get; private set; }
        public bool IsOut { get; private set; }
        public float OutTime { get; private set; }
        public bool IsKnockedOut => koTimer > 0f && !IsOut;
        public bool IsConscious => !IsOut && koTimer <= 0f;
        public float Consciousness01 => Mathf.Clamp01(consciousness / Tune.MaxConsciousness);
        public float KnockoutTimeLeft => koTimer;
        public bool Grounded => grounded;
        public Vector3 Facing => facing;
        public Vector3 Position => pelvis.position;
        /// <summary>Interpolated pelvis position — use for cameras and UI, not physics.</summary>
        public Vector3 VisualPosition => pelvis.transform.position;
        public Vector3 HeadVisualPosition => head.transform.position;
        public Brawler LastAttacker { get; private set; }
        public float LastAttackTime { get; private set; } = -100f;
        public bool IsStraining => carrying || (handL.IsHolding && handL.heldWorld) || (handR.IsHolding && handR.heldWorld);
        public bool IsCarrying => carrying;
        public Quaternion FacingRotation => Quaternion.LookRotation(facing, Vector3.up);
        public float AimPitch => aimPitch;

        public bool IsHeldByOthers
        {
            get
            {
                foreach (var b in All)
                {
                    if (b == this) continue;
                    if (b.handL.heldBrawler == this || b.handR.heldBrawler == this) return true;
                }
                return false;
            }
        }

        public void Initialise(BodyPart[] parts, Rigidbody[] bodies)
        {
            this.parts = parts;
            this.bodies = bodies;
            restLocal = new Vector3[bodies.Length];
            collisionModes = new CollisionDetectionMode[bodies.Length];
            TotalMass = 0f;
            for (int i = 0; i < bodies.Length; i++)
            {
                restLocal[i] = transform.InverseTransformPoint(bodies[i].transform.position);
                collisionModes[i] = bodies[i].collisionDetectionMode;
                TotalMass += bodies[i].mass;
            }

            var cols = GetComponentsInChildren<Collider>();
            foreach (var c in cols) own.Add(c);
            for (int i = 0; i < cols.Length; i++)
                for (int j = i + 1; j < cols.Length; j++)
                    Physics.IgnoreCollision(cols[i], cols[j], true);

            facing = transform.forward;
            facing.y = 0f;
            facing.Normalize();
            All.Add(this);
        }

        void OnDestroy() => All.Remove(this);

        public bool Owns(Collider c) => own.Contains(c);

        public BodyPart PartOf(Rigidbody rb) => rb.GetComponent<BodyPart>();

        public void SetChampion(bool on)
        {
            if (on && crown == null) crown = Hats.Crown(head.transform);
            if (crown != null) crown.SetActive(on);
        }

        void Update()
        {
            if (!IsOut && brain != null) brain.Think(this, ref cmd, Time.deltaTime);
            else cmd = default;
        }

        void FixedUpdate()
        {
            float dt = Time.fixedDeltaTime;
            SenseGround();
            UpdateStatus(dt);

            float bal = Balance01();
            ApplyStrength();

            if (IsConscious)
            {
                Upright(bal);
                Hover(bal);
                Locomote(dt, bal);
                TryJump(bal);
                if (cmd.punchPressed) StartPunch();
                if (cmd.kickPressed) StartKick();
                Struggle(dt);
            }

            TickStrikes(dt);
            DriveSpine();
            DriveLegs(dt);
            DriveArms(dt);
            handL.FixedTick(dt);
            handR.FixedTick(dt);

            if (!IsOut && pelvis.position.y < GameManager.KillHeight) Eliminate();
            // park bodies that fell far out of the world instead of simulating them forever
            if (IsOut && !pelvis.isKinematic && pelvis.position.y < GameManager.KillHeight - 25f) SetFrozen(true);
            cmd.ClearEdges();
        }

        // ------------------------------------------------------------------ sensing & status

        void SenseGround()
        {
            int n = Physics.SphereCastNonAlloc(pelvis.position, Tune.GroundProbeRadius, Vector3.down, castHits,
                Tune.GroundProbe, ~0, QueryTriggerInteraction.Ignore);
            float best = float.MaxValue;
            int bi = -1;
            Vector3 bestPoint = Vector3.zero;
            for (int i = 0; i < n; i++)
            {
                var h = castHits[i];
                if (own.Contains(h.collider)) continue;
                Vector3 point = h.point;
                if (h.distance <= 0f && h.point == Vector3.zero)
                {
                    // the probe started inside this collider (lying on the floor): use the closest point instead
                    point = h.collider.ClosestPoint(pelvis.position);
                    if (point.y > pelvis.position.y) continue;
                }
                else if (h.normal.y < 0.45f) continue;
                if (h.distance < best) { best = h.distance; bi = i; bestPoint = point; }
            }

            bool jumping = jumpCooldown > Tune.JumpCooldown - 0.2f;
            grounded = bi >= 0 && !jumping;
            if (grounded)
            {
                var h = castHits[bi];
                groundPoint = bestPoint;
                groundBody = h.rigidbody;
                onIce = h.collider.sharedMaterial == Kit.IceMat;
                var surface = h.collider.GetComponentInParent<ISurfaceVelocity>();
                if (surface != null) groundVelocity = surface.SurfaceVelocityAt(h.point);
                else if (groundBody != null) groundVelocity = groundBody.GetPointVelocity(h.point);
                else groundVelocity = Vector3.zero;
                airTime = 0f;
            }
            else
            {
                groundBody = null;
                onIce = false;
                airTime += Time.fixedDeltaTime;
            }
        }

        void UpdateStatus(float dt)
        {
            if (jumpCooldown > 0f) jumpCooldown -= dt;
            if (staggerTimer > 0f) staggerTimer -= dt;

            if (koTimer > 0f)
            {
                koTimer -= dt;
                if (cmd.jumpPressed) koTimer -= 0.15f; // mash to wake up
                if (koTimer <= 0f)
                {
                    koTimer = 0f;
                    consciousness = Tune.WakeConsciousness;
                    wakeBlend = 0f;
                }
            }
            else if (!IsOut && Time.time - lastDamageTime > Tune.RegenDelay)
            {
                consciousness = Mathf.Min(Tune.MaxConsciousness, consciousness + Tune.RegenRate * dt);
            }

            if (flopTimer > 0f)
            {
                flopTimer -= dt;
                if (flopTimer <= 0f) wakeBlend = 0f;
            }
            else if (wakeBlend < 1f)
            {
                wakeBlend = Mathf.Min(1f, wakeBlend + dt / Tune.GetUpTime);
            }
        }

        float Balance01()
        {
            if (!IsConscious || flopTimer > 0f) return 0f;
            float b = wakeBlend;
            if (staggerTimer > 0f) b *= 0.45f;
            return b;
        }

        void ApplyStrength()
        {
            float s = IsConscious ? Mathf.Lerp(0.3f, 1f, wakeBlend) : Tune.KnockedOutStrength;
            if (staggerTimer > 0f) s *= 0.6f;
            if (flopTimer > 0f) s *= 0.7f;
            spine.SetStrength(s);
            neck.SetStrength(s);
            hipL.SetStrength(s); hipR.SetStrength(s);
            kneeL.SetStrength(s); kneeR.SetStrength(s);
            float armL = s * (handL.IsHolding ? Tune.HoldingArmBoost : 1f);
            float armR = s * (handR.IsHolding ? Tune.HoldingArmBoost : 1f);
            shoulderL.SetStrength(armL); elbowL.SetStrength(armL);
            shoulderR.SetStrength(armR); elbowR.SetStrength(armR);
        }

        // ------------------------------------------------------------------ balance & locomotion

        static void UprightTorque(Rigidbody rb, Quaternion target, float kp, float kd)
        {
            Quaternion q = target * Quaternion.Inverse(rb.rotation);
            if (q.w < 0f) { q.x = -q.x; q.y = -q.y; q.z = -q.z; q.w = -q.w; }
            q.ToAngleAxis(out float angle, out Vector3 axis);
            Vector3 acc = -rb.angularVelocity * kd;
            if (angle > 0.01f && !float.IsNaN(axis.x) && !float.IsInfinity(axis.x))
                acc += axis.normalized * (angle * Mathf.Deg2Rad * kp);
            rb.AddTorque(acc, ForceMode.Acceleration);
        }

        void Upright(float bal)
        {
            if (bal <= 0.001f) return;
            Quaternion face = FacingRotation;
            UprightTorque(pelvis, face, Tune.UprightSpring * bal, Tune.UprightDamper * Mathf.Sqrt(bal));
            float strikeLoosen = IsStriking ? 0.5f : 1f;
            UprightTorque(chest, face * Quaternion.Euler(SpineLean(), SpineTwist(), 0f),
                Tune.ChestUprightSpring * bal * strikeLoosen, Tune.ChestUprightDamper * Mathf.Sqrt(bal));
        }

        void Hover(float bal)
        {
            if (!grounded || bal <= 0.001f) return;
            float target = groundPoint.y + Tune.StandHeight;
            float err = target - pelvis.position.y;
            if (err < -0.35f) return;
            float vRel = pelvis.linearVelocity.y - groundVelocity.y;
            float acc = Mathf.Clamp(err * Tune.HoverSpring - vRel * Tune.HoverDamper, -15f, 45f);
            float support = Mathf.Max(0f, -Physics.gravity.y + acc) * bal;
            Vector3 force = Vector3.up * support * TotalMass;
            pelvis.AddForce(force * 0.75f);
            chest.AddForce(force * 0.25f);
            // push back on dynamic ground so floating floes tilt and crates get squashed
            if (groundBody != null && !groundBody.isKinematic)
                groundBody.AddForceAtPosition(-force * 0.6f, groundPoint);
        }

        void Locomote(float dt, float bal)
        {
            Vector3 move = cmd.move;
            move.y = 0f;
            move = Vector3.ClampMagnitude(move, 1f);
            if (IsHeldByOthers) move *= 0.35f;

            float maxSpeed = Tune.WalkSpeed * (carrying ? Tune.CarrySpeedFactor : 1f);
            Vector3 v = pelvis.linearVelocity;
            Vector3 vRel = new Vector3(v.x - groundVelocity.x, 0f, v.z - groundVelocity.z);
            speed01 = Mathf.Clamp01(vRel.magnitude / Tune.WalkSpeed);

            Vector3 desired = move * maxSpeed;
            float accel = (grounded ? Tune.GroundAccel : Tune.AirAccel) * bal;
            if (onIce) accel *= 0.22f;
            Vector3 a = Vector3.ClampMagnitude((desired - vRel) * accel, 30f);
            if (!grounded && move.sqrMagnitude < 0.01f) a = Vector3.zero; // no air braking
            pelvis.AddForce(a, ForceMode.Acceleration);
            chest.AddForce(a, ForceMode.Acceleration);

            if (move.sqrMagnitude > 0.01f)
                facing = Vector3.RotateTowards(facing, move.normalized, Tune.TurnRate * dt, 0f);
        }

        void TryJump(float bal)
        {
            if (!cmd.jumpPressed || bal < 0.6f || jumpCooldown > 0f) return;
            if (!grounded && airTime > 0.12f) return;
            if (IsHeldByOthers) return;
            foreach (var rb in bodies)
            {
                var v = rb.linearVelocity;
                float k = rb == pelvis || rb == chest || rb == head ? 1f : 0.85f;
                v.y = Mathf.Max(v.y, groundVelocity.y) + Tune.JumpVelocity * k;
                rb.linearVelocity = v;
            }
            jumpCooldown = Tune.JumpCooldown;
            grounded = false;
            airTime = 0.2f;
            Sfx.Play(Sfx.Jump, pelvis.position, 0.5f, Random.Range(0.9f, 1.15f));
            Fx.Dust(groundPoint, 4);
        }

        // ------------------------------------------------------------------ legs & spine

        void DriveSpine()
        {
            if (!IsConscious)
            {
                spine.SetTarget(Quaternion.identity);
                neck.SetTarget(Quaternion.identity);
                return;
            }
            spine.SetTarget(Quaternion.Euler(SpineLean(), SpineTwist(), 0f));
            neck.SetTarget(Quaternion.Euler(NeckPitch(), 0f, 0f));
        }

        float SpineLean()
        {
            float lean = grounded ? 5f + 9f * speed01 : -6f;
            if (headStrike.phase == 1) lean = -18f;
            else if (headStrike.phase == 2) lean = 38f;
            if (carrying) lean -= 12f;
            return lean;
        }

        float SpineTwist()
        {
            float twist = 0f;
            for (int s = 0; s < 2; s++)
            {
                float dir = s == 0 ? 1f : -1f;
                if (armStrike[s].phase == 1) twist -= 12f * dir;
                else if (armStrike[s].phase == 2) twist += 24f * dir;
            }
            return twist;
        }

        float NeckPitch()
        {
            if (headStrike.phase == 1) return -35f;
            if (headStrike.phase == 2) return 45f;
            return IsHeldByOthers ? -10f : 0f;
        }

        void DriveLegs(float dt)
        {
            if (!IsConscious)
            {
                hipL.SetTarget(Quaternion.identity); hipR.SetTarget(Quaternion.identity);
                kneeL.SetTarget(Muscle.Bend(10f)); kneeR.SetTarget(Muscle.Bend(10f));
                return;
            }

            float hl, hr, kl, kr;
            if (grounded)
            {
                if (speed01 > 0.07f) gaitPhase += dt * (5.5f + speed01 * Tune.WalkSpeed * 2.4f);
                float amp = 42f * speed01;
                float s = Mathf.Sin(gaitPhase), c = Mathf.Cos(gaitPhase);
                hl = s * amp;
                hr = -s * amp;
                kl = Mathf.Max(0f, c) * amp * 1.5f + 5f;
                kr = Mathf.Max(0f, -c) * amp * 1.5f + 5f;
            }
            else
            {
                hl = 28f; hr = 8f; kl = 55f; kr = 30f;
            }

            // kicks override one or both legs
            if (legStrike.phase != 0)
            {
                float kh, kk;
                switch (legStrike.phase)
                {
                    case 1: kh = 35f; kk = 95f; break;
                    case 2: kh = 95f; kk = 0f; break;
                    default: kh = 30f; kk = 30f; break;
                }
                if (legStrike.kind == AttackKind.DropKick) { hl = hr = 85f; kl = kr = 0f; }
                else if (legStrike.side == 0) { hl = kh; kl = kk; }
                else { hr = kh; kr = kk; }
            }

            hipL.SetTarget(Muscle.Flex(hl));
            hipR.SetTarget(Muscle.Flex(hr));
            kneeL.SetTarget(Muscle.Bend(kl));
            kneeR.SetTarget(Muscle.Bend(kr));
        }

        // ------------------------------------------------------------------ life cycle

        void Struggle(float dt)
        {
            struggle = Mathf.Max(0f, struggle - dt * 1.2f);
            if (!IsHeldByOthers) return;
            if (cmd.jumpPressed || cmd.punchPressed || cmd.kickPressed)
            {
                struggle += 1f;
                chest.AddForce(Random.insideUnitSphere * 2.5f + Vector3.up, ForceMode.VelocityChange);
                if (Random.value < 0.4f) Sfx.Play(Sfx.RandomGrunt(), head.position, 0.4f, VoicePitch);
            }
            if (struggle >= Tune.StruggleToBreak)
            {
                struggle = 0f;
                foreach (var b in All)
                {
                    if (b == this) continue;
                    if (b.handL.heldBrawler == this) b.handL.Release(0.9f);
                    if (b.handR.heldBrawler == this) b.handR.Release(0.9f);
                }
                Fx.Hit(chest.position, 8f);
            }
        }

        public float VoicePitch => 0.85f + (participant != null ? (participant.index * 0.137f) % 0.4f : 0.2f);

        public void Eliminate()
        {
            if (IsOut) return;
            IsOut = true;
            OutTime = Time.time;
            koTimer = 0f;
            handL.Release(); handR.Release();
            EndAllStrikes();
            GameManager.I?.NotifyOut(this);
        }

        void SetFrozen(bool frozen)
        {
            for (int i = 0; i < bodies.Length; i++)
            {
                var rb = bodies[i];
                if (frozen == rb.isKinematic) continue;
                if (frozen)
                {
                    rb.linearVelocity = Vector3.zero;
                    rb.angularVelocity = Vector3.zero;
                    rb.collisionDetectionMode = CollisionDetectionMode.ContinuousSpeculative; // the only CCD mode kinematic bodies allow
                    rb.isKinematic = true;
                }
                else
                {
                    rb.isKinematic = false;
                    rb.collisionDetectionMode = collisionModes[i];
                }
            }
        }

        public void Respawn(Vector3 feet, Quaternion rotation)
        {
            SetFrozen(false);
            transform.SetPositionAndRotation(feet, rotation);
            for (int i = 0; i < bodies.Length; i++)
            {
                var rb = bodies[i];
                Vector3 p = transform.TransformPoint(restLocal[i]);
                rb.transform.SetPositionAndRotation(p, rotation);
                rb.position = p;
                rb.rotation = rotation;
                rb.linearVelocity = Vector3.zero;
                rb.angularVelocity = Vector3.zero;
            }
            handL.Release(); handR.Release();
            EndAllStrikes();
            IsOut = false;
            koTimer = 0f;
            flopTimer = 0f;
            consciousness = Tune.MaxConsciousness;
            wakeBlend = 0.6f;
            facing = rotation * Vector3.forward;
            facing.y = 0f;
            facing.Normalize();
            Fx.Confetti(feet + Vector3.up, 12);
        }

        /// <summary>Instantly pushes the whole ragdoll (used by bounce pads, explosions, pistons).</summary>
        public void AddVelocity(Vector3 dv)
        {
            foreach (var rb in bodies) rb.AddForce(dv, ForceMode.VelocityChange);
        }
    }
}
