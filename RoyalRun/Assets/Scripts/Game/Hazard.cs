using UnityEngine;

// "Running into this object is a hit". It is put on fences, walls, carts and falling obstacles.
// (The road and the curbs have no Hazard, so touching them does nothing.)
//
// Every Hazard registers in its player's world, and the hero checks the distance to them himself
// every frame (Touches). This does not depend on physics events, which Unity does not send for a
// kinematic body touching static colliders - so a hit is never missed.
// On a hit the object breaks into pieces (Smash), so you can see what you ran into.
public class Hazard : MonoBehaviour
{
    [SerializeField] Color debrisColor = new Color(0.55f, 0.36f, 0.2f);
    [SerializeField] float timePenalty = 2f;       // seconds taken from the timer on a hit

    PlayerWorld world;
    Collider shape;
    bool smashed;

    public float TimePenalty { get { return timePenalty; } }
    public bool Smashed { get { return smashed; } }

    public void Configure(Color debris, float penalty)
    {
        debrisColor = debris;
        timePenalty = penalty;
    }

    void OnEnable()
    {
        shape = GetComponent<Collider>();
        world = GetComponentInParent<PlayerWorld>();
        if (world != null) world.RegisterHazard(this);
    }

    void OnDisable()
    {
        if (world != null) world.UnregisterHazard(this);
    }

    // Does a vertical capsule (the hero: from bottom to top, with a radius) touch this object?
    public bool Touches(Vector3 bottom, Vector3 top, float radius)
    {
        if (smashed || shape == null || !shape.enabled || shape.isTrigger) return false;
        for (int i = 0; i <= 4; i++)
        {
            Vector3 p = Vector3.Lerp(bottom, top, i / 4f);
            if (Distance(p) < radius) return true;
        }
        return false;
    }

    // Distance from a point to the collider, computed from the transform (always up to date).
    float Distance(Vector3 p)
    {
        Transform t = shape.transform;
        BoxCollider box = shape as BoxCollider;
        if (box != null)
        {
            Vector3 local = t.InverseTransformPoint(p) - box.center;
            Vector3 half = box.size * 0.5f;
            Vector3 clamped = new Vector3(Mathf.Clamp(local.x, -half.x, half.x), Mathf.Clamp(local.y, -half.y, half.y), Mathf.Clamp(local.z, -half.z, half.z));
            return t.TransformVector(local - clamped).magnitude;
        }

        Vector3 s = t.lossyScale;
        float scale = Mathf.Max(Mathf.Abs(s.x), Mathf.Max(Mathf.Abs(s.y), Mathf.Abs(s.z)));

        SphereCollider sphere = shape as SphereCollider;
        if (sphere != null)
            return Vector3.Distance(p, t.TransformPoint(sphere.center)) - sphere.radius * scale;

        CapsuleCollider cap = shape as CapsuleCollider;
        if (cap != null)
        {
            Vector3 axis = cap.direction == 0 ? Vector3.right : cap.direction == 1 ? Vector3.up : Vector3.forward;
            float half = Mathf.Max(0f, cap.height * 0.5f - cap.radius);
            Vector3 a = t.TransformPoint(cap.center - axis * half);
            Vector3 b = t.TransformPoint(cap.center + axis * half);
            Vector3 ab = b - a;
            float k = ab.sqrMagnitude > 0f ? Mathf.Clamp01(Vector3.Dot(p - a, ab) / ab.sqrMagnitude) : 0f;
            return Vector3.Distance(p, a + ab * k) - cap.radius * scale;
        }

        // any other collider: its bounding box
        return Vector3.Distance(p, shape.bounds.ClosestPoint(p));
    }

    // The hero crashed into it: it breaks into pieces (a falling obstacle is knocked off the road instead).
    public void Smash(Vector3 from)
    {
        if (smashed) return;
        smashed = true;

        Vector3 centre = shape != null ? shape.bounds.center : transform.position + Vector3.up * 0.6f;
        // the pieces travel with the road piece the object stood on
        Transform parent = transform.parent != null ? transform.parent : (world != null ? world.transform : null);
        DebrisBurst.Shatter(centre, debrisColor, parent);

        Rigidbody rb = GetComponent<Rigidbody>();
        if (rb != null && !rb.isKinematic)
        {
            Vector3 dir = (centre - from);
            dir.y = 0f;
            if (dir.sqrMagnitude < 0.01f) dir = Vector3.right;
            rb.AddForce((dir.normalized * 6f + Vector3.up * 7f + Vector3.forward * 3f) * rb.mass, ForceMode.Impulse);
            rb.AddTorque(Random.insideUnitSphere * 8f * rb.mass, ForceMode.Impulse);
            Destroy(gameObject, 2.5f);
        }
        else
        {
            Destroy(gameObject);
        }
    }
}
