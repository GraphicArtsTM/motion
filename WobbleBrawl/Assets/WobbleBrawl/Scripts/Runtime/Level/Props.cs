using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Conveyor belt: carries anything standing on it. Fighters read it as ground velocity.</summary>
    public sealed class Conveyor : MonoBehaviour, ISurfaceVelocity
    {
        public Vector3 direction = Vector3.right;
        public float speed = 2.5f;
        readonly List<Transform> stripes = new List<Transform>();
        float length;

        public Vector3 SurfaceVelocityAt(Vector3 worldPoint) => direction.normalized * speed;

        public static Conveyor Create(Transform parent, Vector3 center, Vector3 size, Vector3 dir, float speed)
        {
            var go = Kit.Box(parent, center, size, new Color(0.18f, 0.18f, 0.2f));
            go.name = "Conveyor";
            var c = go.AddComponent<Conveyor>();
            c.direction = dir.normalized;
            c.speed = speed;
            // moving chevrons sell the motion
            bool alongX = Mathf.Abs(dir.x) > Mathf.Abs(dir.z);
            c.length = alongX ? size.x : size.z;
            int count = Mathf.Max(2, Mathf.RoundToInt(c.length / 0.9f));
            for (int i = 0; i < count; i++)
            {
                var s = Kit.Deco(PrimitiveType.Cube, parent, center, Vector3.one, new Color(1f, 0.75f, 0.1f), null, false).transform;
                s.localScale = alongX ? new Vector3(0.18f, 0.02f, size.z * 0.85f) : new Vector3(size.x * 0.85f, 0.02f, 0.18f);
                s.localPosition = center + Vector3.up * (size.y * 0.5f + 0.011f);
                c.stripes.Add(s);
            }
            return c;
        }

        void Update()
        {
            if (stripes.Count == 0) return;
            float spacing = length / stripes.Count;
            float offset = Mathf.Repeat(Time.time * speed, spacing);
            Vector3 dir = direction.normalized;
            Vector3 start = transform.localPosition - dir * length * 0.5f;
            for (int i = 0; i < stripes.Count; i++)
            {
                var p = start + dir * (i * spacing + offset);
                p.y = stripes[i].localPosition.y;
                stripes[i].localPosition = p;
            }
        }

        void OnCollisionStay(Collision c)
        {
            var rb = c.rigidbody;
            if (rb == null || rb.isKinematic) return;
            var part = rb.GetComponent<BodyPart>();
            if (part != null && part.owner.IsConscious) return; // standing fighters use the surface velocity instead
            Vector3 dir = direction.normalized;
            float along = Vector3.Dot(rb.linearVelocity, dir);
            rb.AddForce(dir * (speed - along) * 5f, ForceMode.Acceleration);
        }
    }

    /// <summary>Kinematic body that loops between two points with a wind-up — used for wall pistons and lifts.</summary>
    public sealed class Piston : MonoBehaviour, ISurfaceVelocity
    {
        public Vector3 restPos, extendedPos;
        public float waitTime = 2.5f, extendTime = 0.18f, holdTime = 0.6f, retractTime = 1.2f, phaseOffset;
        public Renderer warningLight;
        Rigidbody rb;
        Vector3 velocity;
        Material lightOn, lightOff;

        public Vector3 SurfaceVelocityAt(Vector3 worldPoint) => velocity;

        public static Piston Create(Transform parent, Vector3 rest, Vector3 extended, Vector3 size, Color color, float offset)
        {
            var go = Kit.Box(parent, rest, size, color);
            go.name = "Piston";
            var p = go.AddComponent<Piston>();
            p.restPos = rest;
            p.extendedPos = extended;
            p.phaseOffset = offset;
            p.rb = Kit.AddBody(go, 500f, true);
            // striped face so it reads as a hazard
            Vector3 face = (extended - rest).normalized;
            for (int i = -1; i <= 1; i++)
                Kit.Deco(PrimitiveType.Cube, go.transform, face * 0.51f + Vector3.up * i * 0.3f, new Vector3(1.02f, 0.12f, 1.02f), new Color(0.1f, 0.1f, 0.1f), null, false);
            return p;
        }

        void Start()
        {
            lightOn = MatFactory.Lit(new Color(1f, 0.2f, 0.1f), 0.5f, 3f);
            lightOff = MatFactory.Lit(new Color(0.3f, 0.08f, 0.05f), 0.5f);
        }

        void FixedUpdate()
        {
            float cycle = waitTime + extendTime + holdTime + retractTime;
            float t = Mathf.Repeat(Time.time + phaseOffset, cycle);
            float k;
            if (t < waitTime) k = 0f;
            else if (t < waitTime + extendTime) k = (t - waitTime) / extendTime;
            else if (t < waitTime + extendTime + holdTime) k = 1f;
            else k = 1f - (t - waitTime - extendTime - holdTime) / retractTime;
            k = Mathf.Clamp01(k);

            Vector3 target = transform.parent.TransformPoint(Vector3.Lerp(restPos, extendedPos, k));
            velocity = (target - rb.position) / Time.fixedDeltaTime;
            rb.MovePosition(target);

            if (warningLight != null)
            {
                bool warn = t > waitTime - 0.8f && t < waitTime + extendTime && Mathf.Repeat(t * 8f, 1f) > 0.5f;
                warningLight.sharedMaterial = warn ? lightOn : lightOff;
            }
        }

        void OnCollisionEnter(Collision c)
        {
            if (velocity.sqrMagnitude < 4f) return;
            var part = c.rigidbody != null ? c.rigidbody.GetComponent<BodyPart>() : null;
            if (part == null) return;
            part.owner.AddVelocity(velocity.normalized * 6f + Vector3.up * 2.5f);
            part.owner.TakeDamage(20f, c.GetContact(0).point, null);
            Sfx.Play(Sfx.Smack, c.GetContact(0).point, 1f, 0.7f);
            GameManager.I?.Shake(0.4f);
        }
    }

    /// <summary>Kinematic rotation around an axis (spinning logs, sweeper arms).</summary>
    public sealed class Spinner : MonoBehaviour, ISurfaceVelocity
    {
        public Vector3 axis = Vector3.up;
        public float degreesPerSecond = 60f;
        Rigidbody rb;
        Quaternion baseRot;
        float angle;

        public Vector3 SurfaceVelocityAt(Vector3 worldPoint)
        {
            Vector3 w = transform.TransformDirection(axis).normalized * degreesPerSecond * Mathf.Deg2Rad;
            return Vector3.Cross(w, worldPoint - transform.position);
        }

        public static Spinner Attach(GameObject go, Vector3 localAxis, float speed)
        {
            var s = go.AddComponent<Spinner>();
            s.axis = localAxis;
            s.degreesPerSecond = speed;
            s.rb = go.GetComponent<Rigidbody>();
            if (s.rb == null) s.rb = Kit.AddBody(go, 1000f, true);
            s.baseRot = go.transform.rotation;
            return s;
        }

        void FixedUpdate()
        {
            angle += degreesPerSecond * Time.fixedDeltaTime;
            rb.MoveRotation(baseRot * Quaternion.AngleAxis(angle, axis));
        }
    }

    /// <summary>A gondola that rides a circular path while staying level (Ferris wheel cars, sky lifts).</summary>
    public sealed class OrbitMover : MonoBehaviour, ISurfaceVelocity
    {
        public Vector3 center;
        public float radius, angularSpeed, angle;
        public Vector3 planeRight = Vector3.right, planeUp = Vector3.up;
        public Vector3 hangOffset;
        Rigidbody rb;
        Vector3 velocity;

        public Vector3 SurfaceVelocityAt(Vector3 worldPoint) => velocity;

        public static OrbitMover Attach(GameObject go, Vector3 center, float radius, float speedDeg, float startDeg, Vector3 hang)
        {
            var m = go.AddComponent<OrbitMover>();
            m.center = center;
            m.radius = radius;
            m.angularSpeed = speedDeg;
            m.angle = startDeg;
            m.hangOffset = hang;
            m.rb = Kit.AddBody(go, 800f, true);
            go.transform.position = m.PointAt(startDeg);
            return m;
        }

        Vector3 PointAt(float deg)
        {
            float a = deg * Mathf.Deg2Rad;
            return center + (planeRight * Mathf.Cos(a) + planeUp * Mathf.Sin(a)) * radius + hangOffset;
        }

        void FixedUpdate()
        {
            angle += angularSpeed * Time.fixedDeltaTime;
            Vector3 p = PointAt(angle);
            velocity = (p - rb.position) / Time.fixedDeltaTime;
            rb.MovePosition(p);
        }
    }

    /// <summary>Swinging wrecking ball kept in motion by a gentle motor.</summary>
    public sealed class Pendulum : MonoBehaviour
    {
        public Rigidbody bob;
        public Transform anchor;
        public Vector3 swingAxis = Vector3.forward;
        public float targetSpeed = 6f;
        LineRenderer rope;

        public static Pendulum Create(Transform parent, Vector3 anchorPos, float length, float radius, float mass, Vector3 swingDir, Color color)
        {
            var anchor = Kit.Deco(PrimitiveType.Cube, parent, anchorPos, new Vector3(0.6f, 0.4f, 0.6f), new Color(0.25f, 0.25f, 0.28f));
            var ballGo = Kit.Deco(PrimitiveType.Sphere, parent, anchorPos + Vector3.down * length, Vector3.one * radius * 2f, color, null, true, 0.7f);
            ballGo.name = "WreckingBall";
            ballGo.AddComponent<SphereCollider>().sharedMaterial = Kit.PropMat;
            var rb = Kit.AddBody(ballGo, mass);
            rb.linearDamping = 0f;
            rb.angularDamping = 0.5f;
            var hinge = ballGo.AddComponent<ConfigurableJoint>();
            hinge.autoConfigureConnectedAnchor = false;
            hinge.anchor = Vector3.up * (length / (radius * 2f));
            hinge.connectedAnchor = anchor.transform.position;
            hinge.xMotion = hinge.yMotion = hinge.zMotion = ConfigurableJointMotion.Locked;
            hinge.angularXMotion = hinge.angularYMotion = hinge.angularZMotion = ConfigurableJointMotion.Free;

            var p = anchor.AddComponent<Pendulum>();
            p.bob = rb;
            p.anchor = anchor.transform;
            p.swingAxis = swingDir.normalized;

            p.rope = anchor.AddComponent<LineRenderer>();
            p.rope.positionCount = 2;
            p.rope.widthMultiplier = 0.08f;
            p.rope.sharedMaterial = MatFactory.Lit(new Color(0.15f, 0.15f, 0.15f));
            p.rope.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            rb.linearVelocity = p.swingAxis * p.targetSpeed;
            return p;
        }

        void FixedUpdate()
        {
            if (bob == null) return;
            Vector3 v = bob.linearVelocity;
            float along = Vector3.Dot(v, swingAxis);
            Vector3 down = (bob.position - anchor.position).normalized;
            // pump energy near the bottom of the arc so the swing never dies
            if (Vector3.Dot(down, Vector3.down) > 0.97f)
            {
                float sign = along >= 0f ? 1f : -1f;
                float deficit = targetSpeed - Mathf.Abs(along);
                if (deficit > 0f) bob.AddForce(swingAxis * sign * deficit * 2f, ForceMode.Acceleration);
            }
            // keep the swing in its plane
            Vector3 side = Vector3.Cross(swingAxis, Vector3.up);
            bob.AddForce(-side * Vector3.Dot(v, side) * 2f, ForceMode.Acceleration);
        }

        void LateUpdate()
        {
            if (rope == null || bob == null) return;
            rope.SetPosition(0, anchor.position);
            rope.SetPosition(1, bob.position);
        }
    }

    /// <summary>Floating platform with spring buoyancy at four corners — tilts when fighters crowd an edge.</summary>
    public sealed class Buoyant : MonoBehaviour
    {
        public float waterLevel;
        public Vector3 home;
        public float waveAmp = 0.12f, wavePhase;
        Rigidbody rb;

        /// <summary>Expects a unit cube scaled to the floe size (as built by <see cref="Kit.Box"/>).</summary>
        public static Buoyant Attach(GameObject go, float waterLevel, float mass, float phase)
        {
            var b = go.AddComponent<Buoyant>();
            b.waterLevel = waterLevel;
            b.home = go.transform.position;
            b.wavePhase = phase;
            b.rb = Kit.AddBody(go, mass);
            b.rb.linearDamping = 0.6f;
            b.rb.angularDamping = 1.2f;
            b.rb.centerOfMass = Vector3.down * 0.25f;
            return b;
        }

        void FixedUpdate()
        {
            float g = -Physics.gravity.y;
            float perCorner = rb.mass * g / 4f;
            float t = Time.time;
            for (int i = 0; i < 4; i++)
            {
                Vector3 local = new Vector3((i & 1) == 0 ? -0.5f : 0.5f, -0.5f, (i & 2) == 0 ? -0.5f : 0.5f);
                Vector3 corner = transform.TransformPoint(local);
                float wave = Mathf.Sin(t * 1.3f + corner.x * 0.4f + wavePhase) * waveAmp + Mathf.Sin(t * 0.9f + corner.z * 0.5f) * waveAmp * 0.6f;
                float depth = waterLevel + wave - corner.y;
                if (depth <= 0f) continue;
                Vector3 vel = rb.GetPointVelocity(corner);
                float f = perCorner * (1f + depth * 6f) - vel.y * rb.mass * 0.6f;
                rb.AddForceAtPosition(Vector3.up * Mathf.Max(0f, f), corner);
            }
            // weak tether so floes drift but come home
            Vector3 off = home - rb.position;
            off.y = 0f;
            rb.AddForce(off * rb.mass * 0.4f);
        }
    }

    /// <summary>Launches everything that lands on it.</summary>
    public sealed class BouncePad : MonoBehaviour
    {
        public float power = 13f;
        float cooldown;

        void Update()
        {
            if (cooldown > 0f) cooldown -= Time.deltaTime;
        }

        void OnCollisionEnter(Collision c)
        {
            var rb = c.rigidbody;
            if (rb == null || cooldown > 0f) return;
            var part = rb.GetComponent<BodyPart>();
            Vector3 up = transform.up;
            if (part != null)
            {
                foreach (var body in part.owner.Bodies)
                {
                    var v = body.linearVelocity;
                    v -= up * Vector3.Dot(v, up);
                    body.linearVelocity = v + up * power;
                }
            }
            else if (!rb.isKinematic) rb.linearVelocity = up * power;
            else return;
            cooldown = 0.25f;
            Sfx.Play(Sfx.Boing, transform.position, 0.9f, Random.Range(0.9f, 1.1f));
        }
    }

    /// <summary>Pressure plate. Reports true while enough mass rests on it.</summary>
    public sealed class PressurePlate : MonoBehaviour
    {
        public float requiredMass = 20f;
        public bool Pressed { get; private set; }
        public System.Action<bool> onChanged;
        Vector3 halfExtents;
        Transform plate;
        Renderer plateRenderer;
        Vector3 plateUp;
        static readonly Collider[] buf = new Collider[32];
        readonly HashSet<Rigidbody> counted = new HashSet<Rigidbody>();

        public static PressurePlate Create(Transform parent, Vector3 pos, Vector2 size, float requiredMass)
        {
            var root = Kit.Group(parent, "PressurePlate", pos);
            Kit.Box(root.transform, new Vector3(0, 0.05f, 0), new Vector3(size.x + 0.3f, 0.1f, size.y + 0.3f), new Color(0.3f, 0.3f, 0.33f));
            var plate = Kit.Deco(PrimitiveType.Cube, root.transform, new Vector3(0, 0.14f, 0), new Vector3(size.x, 0.08f, size.y), new Color(0.95f, 0.25f, 0.2f), null, true, 0.5f, 0.8f);
            var p = root.AddComponent<PressurePlate>();
            p.requiredMass = requiredMass;
            p.halfExtents = new Vector3(size.x * 0.5f, 0.35f, size.y * 0.5f);
            p.plate = plate.transform;
            p.plateRenderer = plate.GetComponent<Renderer>();
            p.plateUp = plate.transform.localPosition;
            return p;
        }

        void FixedUpdate()
        {
            Vector3 c = transform.position + Vector3.up * 0.45f;
            int n = Physics.OverlapBoxNonAlloc(c, halfExtents, buf, transform.rotation, ~0, QueryTriggerInteraction.Ignore);
            counted.Clear();
            float mass = 0f;
            for (int i = 0; i < n; i++)
            {
                var rb = buf[i].attachedRigidbody;
                if (rb == null || rb.isKinematic || !counted.Add(rb)) continue;
                var part = rb.GetComponent<BodyPart>();
                mass += part != null ? part.owner.TotalMass / 3f : rb.mass; // a fighter's feet register a third of the body
            }
            bool pressed = mass >= requiredMass;
            if (pressed != Pressed)
            {
                Pressed = pressed;
                onChanged?.Invoke(pressed);
                Sfx.Play(Sfx.Tick, transform.position, 0.8f, pressed ? 1.2f : 0.8f);
            }
            plate.localPosition = plateUp + Vector3.down * (Pressed ? 0.06f : 0f);
            plateRenderer.sharedMaterial = Pressed
                ? MatFactory.Lit(new Color(0.3f, 1f, 0.35f), 0.5f, 1.2f)
                : MatFactory.Lit(new Color(0.95f, 0.25f, 0.2f), 0.5f, 0.8f);
        }
    }

    /// <summary>Kinematic door that slides open while it is powered.</summary>
    public sealed class SlidingDoor : MonoBehaviour
    {
        public Vector3 closedPos, openPos;
        public bool open;
        public float speed = 2f;
        Rigidbody rb;

        public static SlidingDoor Create(Transform parent, Vector3 closed, Vector3 openOffset, Vector3 size, Color color)
        {
            var go = Kit.Box(parent, closed, size, color);
            go.name = "Door";
            var d = go.AddComponent<SlidingDoor>();
            d.closedPos = closed;
            d.openPos = closed + openOffset;
            d.rb = Kit.AddBody(go, 1000f, true);
            Kit.Deco(PrimitiveType.Cube, go.transform, Vector3.zero, new Vector3(1.02f, 0.1f, 1.02f), new Color(1f, 0.8f, 0.1f), null, false);
            return d;
        }

        void FixedUpdate()
        {
            Vector3 target = open ? openPos : closedPos;
            Vector3 cur = transform.parent.InverseTransformPoint(rb.position);
            Vector3 next = Vector3.MoveTowards(cur, target, speed * Time.fixedDeltaTime);
            rb.MovePosition(transform.parent.TransformPoint(next));
        }
    }

    /// <summary>Zone that fires once per fighter when their pelvis enters it (checkpoints, finish line).</summary>
    public sealed class Zone : MonoBehaviour
    {
        public Bounds bounds;
        public System.Action<Brawler> onEnter;
        readonly HashSet<Brawler> inside = new HashSet<Brawler>();

        public static Zone Create(Transform parent, Vector3 center, Vector3 size, System.Action<Brawler> onEnter)
        {
            var go = Kit.Group(parent, "Zone", center);
            var z = go.AddComponent<Zone>();
            z.bounds = new Bounds(go.transform.position, size);
            z.onEnter = onEnter;
            return z;
        }

        void FixedUpdate()
        {
            foreach (var b in Brawler.All)
            {
                if (b.IsOut) { inside.Remove(b); continue; }
                bool now = bounds.Contains(b.Position);
                if (now && inside.Add(b)) onEnter?.Invoke(b);
                else if (!now) inside.Remove(b);
            }
        }
    }

    /// <summary>Gently bobbing / spinning decoration.</summary>
    public sealed class Bob : MonoBehaviour
    {
        public float amp = 0.2f, speed = 1f, spin;
        Vector3 basePos;

        void Start() => basePos = transform.localPosition;

        void Update()
        {
            transform.localPosition = basePos + Vector3.up * Mathf.Sin(Time.time * speed) * amp;
            if (spin != 0f) transform.Rotate(0f, spin * Time.deltaTime, 0f, Space.World);
        }
    }
}
