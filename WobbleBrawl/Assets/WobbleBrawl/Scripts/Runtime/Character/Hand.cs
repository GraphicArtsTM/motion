using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Physical grabbing, Human-Fall-Flat style: while the grab button is held the fist sticks to
    /// whatever it touches with a FixedJoint — another fighter, a prop, or the static world (climbing).
    /// </summary>
    public sealed class Hand : MonoBehaviour
    {
        public Brawler owner;
        public Rigidbody rb;
        public Vector3 fistLocal;
        public bool isLeft;

        public bool wantGrab;
        public FixedJoint joint;
        public Rigidbody heldBody;
        public Brawler heldBrawler;
        public bool heldWorld;   // static geometry or kinematic body — counts as a climbing hold
        public float heldSince;
        float cooldown;
        bool holding;

        static readonly Collider[] overlap = new Collider[24];

        public bool IsHolding => holding && joint != null;
        public Vector3 Fist => rb.transform.TransformPoint(fistLocal);

        public void FixedTick(float dt)
        {
            if (cooldown > 0f) cooldown -= dt;

            // the joint was broken by force (or the held object was destroyed)
            if (holding && joint == null) Clear();
            if (holding && heldBody == null && !heldWorld) Release(0.1f);

            if (wantGrab && !holding && cooldown <= 0f) TryGrab();
        }

        void TryGrab()
        {
            Vector3 fist = Fist;
            int n = Physics.OverlapSphereNonAlloc(fist, Tune.GrabRadius, overlap, ~0, QueryTriggerInteraction.Ignore);
            Collider best = null;
            Vector3 bestPoint = fist;
            float bestDist = float.MaxValue; // metres, biased
            for (int i = 0; i < n; i++)
            {
                var c = overlap[i];
                if (owner.Owns(c)) continue;
                Vector3 p = c.ClosestPoint(fist);
                float d = (p - fist).magnitude;
                // prefer fighters and props over the floor so reaching down picks up bodies, not tiles
                var body = c.attachedRigidbody;
                if (body != null && !body.isKinematic) d -= 0.12f;
                if (d < bestDist) { bestDist = d; best = c; bestPoint = p; }
            }
            if (best != null) Attach(best, bestPoint);
        }

        void Attach(Collider c, Vector3 point)
        {
            var other = c.attachedRigidbody;
            joint = gameObject.AddComponent<FixedJoint>();
            joint.anchor = fistLocal;
            joint.connectedBody = other;
            joint.breakForce = Tune.GripBreakForce;
            joint.breakTorque = Tune.GripBreakForce;
            joint.enablePreprocessing = false;
            joint.enableCollision = false;

            heldBody = other;
            heldWorld = other == null || other.isKinematic;
            heldBrawler = null;
            if (other != null)
            {
                var part = other.GetComponent<BodyPart>();
                if (part != null) heldBrawler = part.owner;
            }
            heldSince = Time.time;
            holding = true;
            Sfx.Play(Sfx.Grab, point, 0.5f, Random.Range(0.9f, 1.2f));
        }

        public void Release(float cooldownTime = 0f)
        {
            if (joint != null) Destroy(joint);
            Clear();
            cooldown = Mathf.Max(cooldown, cooldownTime);
        }

        void Clear()
        {
            joint = null;
            heldBody = null;
            heldBrawler = null;
            heldWorld = false;
            holding = false;
        }
    }
}
