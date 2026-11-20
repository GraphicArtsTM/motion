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

    void Build()
    {
        Transform r = transform;
        body = new GameObject("Body").transform; body.SetParent(r, false); body.localPosition = new Vector3(0f, 1.25f, 0f);
        head = new GameObject("Head").transform; head.SetParent(body, false); head.localPosition = new Vector3(0f, 0.85f, 0.1f);
        armL = Joint("Arm L", body, new Vector3(-0.75f, 0.45f, 0f));
        armR = Joint("Arm R", body, new Vector3(0.75f, 0.45f, 0f));
        legL = Joint("Leg L", r, new Vector3(-0.35f, 0.85f, 0f));
        legR = Joint("Leg R", r, new Vector3(0.35f, 0.85f, 0f));

        // smooth boulders for the body, glowing eyes and runes - one skinned mesh
        ShapeBuilder sb = new ShapeBuilder(r);
        sb.Detail = PlayerWorld.Lite ? 10 : 12;
        sb.Ellipsoid(body, new Vector3(0f, 0.25f, 0f), new Vector3(0.66f, 0.52f, 0.44f), Rock);
        sb.Ellipsoid(body, new Vector3(0f, -0.25f, 0.05f), new Vector3(0.46f, 0.36f, 0.36f), RockDark);
        sb.Ellipsoid(body, new Vector3(0.22f, 0.66f, -0.2f), new Vector3(0.32f, 0.13f, 0.26f), Moss);
        sb.Ellipsoid(body, new Vector3(-0.3f, 0.5f, -0.15f), new Vector3(0.22f, 0.1f, 0.2f), Moss);
        sb.Ellipsoid(body, new Vector3(0f, 0.25f, 0.42f), new Vector3(0.1f, 0.1f, 0.04f), Glow, ShapeBuilder.Glow);
        sb.Ellipsoid(head, Vector3.zero, new Vector3(0.3f, 0.25f, 0.27f), Rock);
        sb.RoundBox(head, new Vector3(0f, 0.12f, 0.2f), new Vector3(0.58f, 0.12f, 0.16f), RockDark, ShapeBuilder.Matte, default(Quaternion), 0.6f);
        sb.Ellipsoid(head, new Vector3(-0.13f, 0.02f, 0.24f), new Vector3(0.06f, 0.045f, 0.03f), Glow, ShapeBuilder.Glow);
        sb.Ellipsoid(head, new Vector3(0.13f, 0.02f, 0.24f), new Vector3(0.06f, 0.045f, 0.03f), Glow, ShapeBuilder.Glow);
        sb.Ellipsoid(head, new Vector3(0f, -0.17f, 0.12f), new Vector3(0.24f, 0.08f, 0.16f), RockDark);
        foreach (Transform t in new[] { armL, armR })
        {
            sb.Ellipsoid(t, new Vector3(0f, -0.29f, 0f), new Vector3(0.22f, 0.3f, 0.22f), Rock);
            sb.Ellipsoid(t, new Vector3(0f, -0.76f, 0.05f), new Vector3(0.26f, 0.26f, 0.25f), RockDark);
        }
        foreach (Transform t in new[] { legL, legR })
        {
            sb.Ellipsoid(t, new Vector3(0f, -0.24f, 0f), new Vector3(0.21f, 0.26f, 0.21f), Rock);
            sb.Ellipsoid(t, new Vector3(0f, -0.66f, 0.06f), new Vector3(0.24f, 0.2f, 0.28f), RockDark);
        }
        sb.BuildSkinned(gameObject, r, "Golem");
    }

    static Transform Joint(string name, Transform parent, Vector3 pos)
    {
        Transform t = new GameObject(name).transform;
        t.SetParent(parent, false);
        t.localPosition = pos;
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
