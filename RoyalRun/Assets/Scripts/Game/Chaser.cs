using UnityEngine;

// The stone golem that chases the hero in the endless mode.
// After a stumble it runs up close behind the hero for a few seconds;
// stumble again while it is near - and it catches you. Then it falls back out of sight.
public class Chaser : MonoBehaviour
{
    static readonly Color Rock = new Color(0.45f, 0.43f, 0.42f);
    static readonly Color RockDark = new Color(0.33f, 0.31f, 0.31f);
    static readonly Color Moss = new Color(0.25f, 0.42f, 0.22f);
    static readonly Color Glow = new Color(1f, 0.55f, 0.1f);

    Transform body, head, armL, armR, legL, legR;
    float phase;
    float distanceBehind = 14f;     // how far behind the hero it is now (metres)
    float targetDistance = 14f;
    bool grabbing;

    public bool IsClose { get { return distanceBehind < 4.5f; } }

    public static Chaser Create(Transform parent)
    {
        GameObject root = new GameObject("Golem");
        root.transform.SetParent(parent, false);
        root.transform.localScale = Vector3.one * 0.72f;   // about 1.9 m tall: seen from above, below the hero
        Chaser c = root.AddComponent<Chaser>();
        c.Build();
        root.SetActive(false);
        return c;
    }

    static GameObject P(PrimitiveType t, string n, Transform p, Vector3 pos, Vector3 scale, Color c, Surface s = Surface.Stone, float emission = 0f)
    {
        GameObject go = MatLib.Prim(t, n, p, pos, scale, c, false, default(Vector3), 0.1f, emission, s);
        return go;
    }

    void Build()
    {
        Transform r = transform;
        body = new GameObject("Body").transform; body.SetParent(r, false); body.localPosition = new Vector3(0f, 1.25f, 0f);
        P(PrimitiveType.Sphere, "Chest", body, new Vector3(0f, 0.25f, 0f), new Vector3(1.25f, 1.0f, 0.85f), Rock);
        P(PrimitiveType.Sphere, "Belly", body, new Vector3(0f, -0.25f, 0.05f), new Vector3(0.9f, 0.7f, 0.7f), RockDark);
        P(PrimitiveType.Sphere, "Moss", body, new Vector3(0.2f, 0.65f, -0.2f), new Vector3(0.6f, 0.25f, 0.5f), Moss, Surface.Grass);
        P(PrimitiveType.Sphere, "Rune", body, new Vector3(0f, 0.25f, 0.42f), Vector3.one * 0.18f, Glow, Surface.Plain, 2f);

        head = new GameObject("Head").transform; head.SetParent(body, false); head.localPosition = new Vector3(0f, 0.85f, 0.1f);
        P(PrimitiveType.Cube, "Skull", head, Vector3.zero, new Vector3(0.55f, 0.45f, 0.5f), Rock);
        P(PrimitiveType.Cube, "Brow", head, new Vector3(0f, 0.12f, 0.22f), new Vector3(0.6f, 0.12f, 0.15f), RockDark);
        P(PrimitiveType.Sphere, "Eye L", head, new Vector3(-0.13f, 0.02f, 0.25f), Vector3.one * 0.1f, Glow, Surface.Plain, 3f);
        P(PrimitiveType.Sphere, "Eye R", head, new Vector3(0.13f, 0.02f, 0.25f), Vector3.one * 0.1f, Glow, Surface.Plain, 3f);
        P(PrimitiveType.Cube, "Jaw", head, new Vector3(0f, -0.2f, 0.12f), new Vector3(0.45f, 0.14f, 0.3f), RockDark);

        armL = Limb("Arm L", body, new Vector3(-0.75f, 0.45f, 0f), 0.95f, 0.42f);
        armR = Limb("Arm R", body, new Vector3(0.75f, 0.45f, 0f), 0.95f, 0.42f);
        legL = Limb("Leg L", r, new Vector3(-0.35f, 0.85f, 0f), 0.8f, 0.4f);
        legR = Limb("Leg R", r, new Vector3(0.35f, 0.85f, 0f), 0.8f, 0.4f);

        MeshBaker.Bake(head.gameObject);
    }

    static Transform Limb(string name, Transform parent, Vector3 pos, float length, float thick)
    {
        Transform t = new GameObject(name).transform;
        t.SetParent(parent, false);
        t.localPosition = pos;
        P(PrimitiveType.Sphere, "Upper", t, new Vector3(0f, -length * 0.3f, 0f), new Vector3(thick, length * 0.6f, thick), Rock);
        P(PrimitiveType.Sphere, "Lower", t, new Vector3(0f, -length * 0.8f, 0.05f), new Vector3(thick * 1.15f, length * 0.5f, thick * 1.1f), RockDark);
        return t;
    }

    // A stumble: the golem comes close for a while.
    public void Approach(float seconds)
    {
        gameObject.SetActive(true);
        targetDistance = 1.8f;
        CancelInvoke("FallBack");
        Invoke("FallBack", seconds);
    }

    void FallBack()
    {
        targetDistance = 16f;
    }

    // Caught: it rushes to the hero and raises its arms.
    public void Grab()
    {
        gameObject.SetActive(true);
        CancelInvoke("FallBack");
        targetDistance = 0.9f;
        grabbing = true;
    }

    public void ResetChase()
    {
        CancelInvoke("FallBack");
        targetDistance = 14f;
        distanceBehind = 14f;
        grabbing = false;
        gameObject.SetActive(false);
    }

    // Called by the world every frame: hero position, how fast the road runs.
    public void Follow(Vector3 hero, float roadSpeed, float dt)
    {
        distanceBehind = Mathf.MoveTowards(distanceBehind, targetDistance, (targetDistance < distanceBehind ? 6f : 3f) * dt);
        if (!grabbing && targetDistance > 10f && distanceBehind > 13f) { gameObject.SetActive(false); return; }

        // a little to the side, so it does not block the view of the hero
        float side = grabbing ? 0.3f : 1.1f;
        transform.position = new Vector3(hero.x - side, 0f, hero.z - distanceBehind);

        // a heavy run
        phase += dt * (grabbing ? 4f : 6f + roadSpeed * 0.25f);
        float s = Mathf.Sin(phase);
        legL.localRotation = Quaternion.Euler(-35f * s, 0f, 0f);
        legR.localRotation = Quaternion.Euler(35f * s, 0f, 0f);
        body.localPosition = new Vector3(0f, 1.25f + Mathf.Abs(Mathf.Cos(phase)) * 0.12f, 0f);
        body.localRotation = Quaternion.Euler(12f, 6f * s, 0f);
        if (grabbing)
        {
            armL.localRotation = Quaternion.Slerp(armL.localRotation, Quaternion.Euler(-160f, 0f, -20f), 6f * dt);
            armR.localRotation = Quaternion.Slerp(armR.localRotation, Quaternion.Euler(-160f, 0f, 20f), 6f * dt);
        }
        else
        {
            armL.localRotation = Quaternion.Euler(40f * s, 0f, -10f);
            armR.localRotation = Quaternion.Euler(-40f * s, 0f, 10f);
        }
        head.localRotation = Quaternion.Euler(0f, Mathf.Sin(phase * 0.5f) * 10f, 0f);
    }
}
