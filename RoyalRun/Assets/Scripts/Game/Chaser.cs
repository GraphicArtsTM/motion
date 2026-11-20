using UnityEngine;

// The stone golem that chases the hero in the endless mode.
//
// * At the start it stands right behind the hero (you see it while the camera flies around), roars at "GO!"
//   and falls back.
// * After a stumble it runs up close behind the hero for a few seconds - beside the hero, in sight of the
//   camera (lower corner of the screen), never hidden under the camera. Stumble again while it is near -
//   and it catches you.
// * Any crash in the endless mode: it runs up to the fallen hero, stops, roars with its jaw open and its
//   chest core blazing, and beats its chest - that is what the camera shows while it flies around the hero.
//
// The body is one smooth skinned mesh (boulders, moss, glowing cracks and runes) with 12 bones:
// knees and elbows bend, the jaw opens, the chest core pulses.
public class Chaser : MonoBehaviour
{
    static readonly Color Rock = new Color(0.47f, 0.45f, 0.43f);
    static readonly Color RockDark = new Color(0.33f, 0.31f, 0.31f);
    static readonly Color RockLight = new Color(0.58f, 0.56f, 0.52f);
    static readonly Color Moss = new Color(0.27f, 0.45f, 0.22f);
    static readonly Color MossDark = new Color(0.19f, 0.34f, 0.17f);
    static readonly Color Glow = new Color(1f, 0.55f, 0.12f);
    static readonly Color GlowHot = new Color(1f, 0.82f, 0.4f);
    static readonly Color Crystal = new Color(0.45f, 0.85f, 1f);

    public const float ChaseDistance = 2.4f;   // how far behind the hero it runs when it is "near"
    const float GrabDistance = 1.5f;
    const float HiddenDistance = 16f;

    Transform body, head, jaw, core, armL, armR, foreL, foreR, legL, legR, kneeL, kneeR;
    float phase;
    float lastStep;
    float distanceBehind = HiddenDistance;
    float targetDistance = HiddenDistance;
    float side = 1f;              // which side of the hero it runs on (-1 left, 1 right)
    float roar;                   // 1 while roaring, fades out
    float stopped;                // 0 running .. 1 standing (blend)
    float idleTime;
    bool grabbing;

    // a heavy footfall: 0..1 how close it is (the world shakes the camera and raises dust)
    public System.Action<Vector3, float> Stepped;

    public bool IsClose { get { return distanceBehind < 4.5f; } }

    public static Chaser Create(Transform parent)
    {
        GameObject root = new GameObject("Golem");
        root.transform.SetParent(parent, false);
        root.transform.localScale = Vector3.one * 0.9f;    // about 2.5 m tall
        Chaser c = root.AddComponent<Chaser>();
        c.Build();
        root.SetActive(false);
        return c;
    }

    // ================= the model =================

    void Build()
    {
        Transform r = transform;
        body = Joint("Body", r, new Vector3(0f, 1.25f, 0f));
        head = Joint("Head", body, new Vector3(0f, 0.86f, 0.12f));
        jaw = Joint("Jaw", head, new Vector3(0f, -0.1f, 0.06f));
        core = Joint("Core", body, new Vector3(0f, 0.3f, 0.46f));
        armL = Joint("Arm L", body, new Vector3(-0.8f, 0.5f, 0f));
        armR = Joint("Arm R", body, new Vector3(0.8f, 0.5f, 0f));
        foreL = Joint("Forearm L", armL, new Vector3(0f, -0.55f, 0f));
        foreR = Joint("Forearm R", armR, new Vector3(0f, -0.55f, 0f));
        legL = Joint("Leg L", r, new Vector3(-0.36f, 0.95f, 0f));
        legR = Joint("Leg R", r, new Vector3(0.36f, 0.95f, 0f));
        kneeL = Joint("Knee L", legL, new Vector3(0f, -0.47f, 0.02f));
        kneeR = Joint("Knee R", legR, new Vector3(0f, -0.47f, 0.02f));

        ShapeBuilder sb = new ShapeBuilder(r);
        sb.Detail = PlayerWorld.Lite ? 10 : 14;

        // ---- torso: a great boulder with a smaller one for the belly, moss on the shoulders ----
        sb.Ellipsoid(body, new Vector3(0f, 0.32f, 0f), new Vector3(0.74f, 0.6f, 0.5f), Rock);
        sb.Ellipsoid(body, new Vector3(0f, -0.2f, 0.04f), new Vector3(0.52f, 0.4f, 0.42f), RockDark);
        sb.Ellipsoid(body, new Vector3(0.05f, 0.62f, -0.12f), new Vector3(0.62f, 0.26f, 0.38f), RockLight);   // hunched back
        sb.Ellipsoid(body, new Vector3(0.28f, 0.82f, -0.18f), new Vector3(0.34f, 0.12f, 0.26f), Moss);
        sb.Ellipsoid(body, new Vector3(-0.32f, 0.74f, -0.1f), new Vector3(0.26f, 0.1f, 0.22f), MossDark);
        sb.Ellipsoid(body, new Vector3(-0.1f, 0.88f, -0.25f), new Vector3(0.2f, 0.08f, 0.16f), Moss);
        // crystals growing out of the back
        sb.Lathe(body, new Vector3(-0.18f, 0.78f, -0.36f), new[] { 0.09f, 0.07f, 0f }, new[] { 0f, 0.28f, 0.42f }, Crystal, ShapeBuilder.Glow, Quaternion.Euler(-35f, 0f, 12f));
        sb.Lathe(body, new Vector3(0.12f, 0.84f, -0.34f), new[] { 0.07f, 0.055f, 0f }, new[] { 0f, 0.2f, 0.32f }, Crystal, ShapeBuilder.Glow, Quaternion.Euler(-40f, 0f, -18f));
        sb.Lathe(body, new Vector3(0.34f, 0.66f, -0.36f), new[] { 0.06f, 0.045f, 0f }, new[] { 0f, 0.16f, 0.26f }, Crystal, ShapeBuilder.Glow, Quaternion.Euler(-50f, 0f, -35f));

        // glowing cracks spreading from the core over the chest
        sb.Ellipsoid(core, Vector3.zero, new Vector3(0.15f, 0.15f, 0.06f), GlowHot, ShapeBuilder.Glow);
        sb.Torus(core, new Vector3(0f, 0f, -0.02f), 0.17f, 0.03f, RockDark, ShapeBuilder.Matte, Quaternion.Euler(90f, 0f, 0f));
        float[] crackAngles = { 25f, 80f, 150f, 205f, 260f, 320f };
        foreach (float a in crackAngles)
        {
            float rad = a * Mathf.Deg2Rad;
            Vector3 dir = new Vector3(Mathf.Cos(rad), Mathf.Sin(rad), 0f);
            Vector3 p = new Vector3(0f, 0.3f, 0.47f) + dir * 0.27f;
            p.z = 0.47f - dir.sqrMagnitude * 0.06f - Mathf.Abs(dir.x) * 0.08f;
            sb.Ellipsoid(body, p, new Vector3(0.13f, 0.022f, 0.02f), Glow, ShapeBuilder.Glow, Quaternion.Euler(0f, dir.x * 25f, a));
        }
        // a rune on the belly
        sb.Ellipsoid(body, new Vector3(0f, -0.18f, 0.44f), new Vector3(0.025f, 0.12f, 0.02f), Glow, ShapeBuilder.Glow);
        sb.Ellipsoid(body, new Vector3(0f, -0.14f, 0.435f), new Vector3(0.09f, 0.022f, 0.02f), Glow, ShapeBuilder.Glow);

        // ---- head: a heavy brow, deep-set glowing eyes, a jaw that opens on a glowing mouth ----
        sb.Ellipsoid(head, new Vector3(0f, 0.04f, 0f), new Vector3(0.34f, 0.28f, 0.3f), Rock);
        sb.RoundBox(head, new Vector3(0f, 0.14f, 0.2f), new Vector3(0.62f, 0.13f, 0.18f), RockDark, ShapeBuilder.Matte, Quaternion.Euler(-8f, 0f, 0f), 0.6f);
        sb.Ellipsoid(head, new Vector3(0f, 0.27f, -0.05f), new Vector3(0.24f, 0.08f, 0.2f), Moss);
        sb.Ellipsoid(head, new Vector3(-0.13f, 0.04f, 0.24f), new Vector3(0.065f, 0.045f, 0.03f), GlowHot, ShapeBuilder.Glow);
        sb.Ellipsoid(head, new Vector3(0.13f, 0.04f, 0.24f), new Vector3(0.065f, 0.045f, 0.03f), GlowHot, ShapeBuilder.Glow);
        sb.Ellipsoid(head, new Vector3(0f, -0.08f, 0.2f), new Vector3(0.17f, 0.05f, 0.08f), Glow, ShapeBuilder.Glow);   // inside the mouth
        sb.RoundBox(jaw, new Vector3(0f, -0.06f, 0.12f), new Vector3(0.48f, 0.15f, 0.34f), RockDark, ShapeBuilder.Matte, default(Quaternion), 0.55f);
        for (int i = -2; i <= 2; i++)       // stubby stone teeth
            sb.Ellipsoid(jaw, new Vector3(i * 0.08f, 0.03f, 0.25f), new Vector3(0.028f, 0.045f, 0.025f), RockLight);

        // ---- arms: shoulder boulders, thick bending arms, huge fists ----
        foreach (int s in new[] { -1, 1 })
        {
            Transform arm = s < 0 ? armL : armR, fore = s < 0 ? foreL : foreR;
            float x = s * 0.8f;
            sb.Ellipsoid(arm, new Vector3(0f, 0.06f, 0f), new Vector3(0.38f, 0.32f, 0.36f), Rock);
            sb.Ellipsoid(arm, new Vector3(s * 0.05f, 0.24f, -0.05f), new Vector3(0.22f, 0.08f, 0.2f), Moss);
            sb.Limb(arm, fore, new Vector3(x, 1.72f, 0f), new Vector3(x, 1.2f, 0.02f), new Vector3(x, 0.72f, 0.06f), 0.24f, 0.21f, 0.23f, RockDark);
            sb.Ellipsoid(fore, new Vector3(s * 0.08f, -0.25f, 0.05f), new Vector3(0.2f, 0.26f, 0.2f), Rock);              // forearm plate
            sb.Ellipsoid(fore, new Vector3(s * 0.1f, -0.2f, 0.12f), new Vector3(0.1f, 0.02f, 0.02f), Glow, ShapeBuilder.Glow);
            sb.Ellipsoid(fore, new Vector3(0f, -0.68f, 0.06f), new Vector3(0.3f, 0.27f, 0.29f), RockDark);                 // fist
            for (int k = -1; k <= 1; k++)
                sb.Ellipsoid(fore, new Vector3(k * 0.11f, -0.72f, 0.28f), new Vector3(0.07f, 0.07f, 0.06f), Rock);       // knuckles
        }

        // ---- legs: short and massive, with knee stones and wide stone feet ----
        foreach (int s in new[] { -1, 1 })
        {
            Transform leg = s < 0 ? legL : legR, knee = s < 0 ? kneeL : kneeR;
            float x = s * 0.36f;
            sb.Limb(leg, knee, new Vector3(x, 0.98f, 0f), new Vector3(x, 0.5f, 0.03f), new Vector3(x, 0.16f, 0f), 0.27f, 0.23f, 0.22f, RockDark);
            sb.Ellipsoid(knee, new Vector3(0f, 0.02f, 0.18f), new Vector3(0.17f, 0.15f, 0.1f), Rock);
            sb.RoundBox(knee, new Vector3(0f, -0.36f, 0.09f), new Vector3(0.42f, 0.24f, 0.58f), Rock, ShapeBuilder.Matte, default(Quaternion), 0.5f);
            sb.Ellipsoid(knee, new Vector3(s * 0.05f, -0.28f, -0.12f), new Vector3(0.15f, 0.1f, 0.14f), Moss);
        }

        SkinnedMeshRenderer smr = sb.BuildSkinned(gameObject, r, "Golem");
        smr.updateWhenOffscreen = false;
    }

    static Transform Joint(string name, Transform parent, Vector3 pos)
    {
        Transform t = new GameObject(name).transform;
        t.SetParent(parent, false);
        t.localPosition = pos;
        return t;
    }

    // ================= what the world tells it =================

    // The start of an endless run: it stands right behind the hero (the camera sees it while flying around).
    public void Intro()
    {
        gameObject.SetActive(true);
        CancelInvoke("FallBack");
        grabbing = false;
        distanceBehind = targetDistance = 3.2f;
        stopped = 1f;
    }

    // "GO!": a roar, then it falls behind.
    public void StartChase(float seconds)
    {
        roar = 1f;
        Sfx.Play(SynthAudio.GolemRoar, 0.7f);
        targetDistance = ChaseDistance;
        CancelInvoke("FallBack");
        Invoke("FallBack", seconds);
    }

    // A stumble: the golem comes close for a while.
    public void Approach(float seconds)
    {
        if (!gameObject.activeSelf || distanceBehind > 8f)
        {
            Sfx.Play(SynthAudio.GolemRoar, 0.6f);
            roar = 1f;
        }
        if (!gameObject.activeSelf) distanceBehind = 12f;     // it comes running from behind the camera
        gameObject.SetActive(true);
        targetDistance = ChaseDistance;
        CancelInvoke("FallBack");
        Invoke("FallBack", seconds);
    }

    void FallBack()
    {
        targetDistance = HiddenDistance;
    }

    // The run is over: it rushes to the hero, stops and roars.
    public void Grab()
    {
        if (!gameObject.activeSelf) distanceBehind = 9f;
        gameObject.SetActive(true);
        CancelInvoke("FallBack");
        targetDistance = GrabDistance;
        grabbing = true;
        idleTime = 0f;
        Sfx.PlayDelayed(SynthAudio.GolemRoar, 0.85f, distanceBehind > 4f ? 0.6f : 0.1f);
    }

    public void ResetChase()
    {
        CancelInvoke("FallBack");
        targetDistance = distanceBehind = HiddenDistance;
        grabbing = false;
        roar = stopped = 0f;
        gameObject.SetActive(false);
    }

    // ================= every frame =================

    // hero: the hero's position; roadX: the centre of the road; roadSpeed: how fast the road runs (0 = stopped).
    public void Follow(Vector3 hero, float roadX, float roadSpeed, float dt)
    {
        float speedTo = grabbing ? 7f : targetDistance < distanceBehind ? 6f : 3f;
        distanceBehind = Mathf.MoveTowards(distanceBehind, targetDistance, speedTo * dt);
        if (!grabbing && targetDistance >= HiddenDistance && distanceBehind > HiddenDistance - 1f)
        {
            gameObject.SetActive(false);
            return;
        }

        // it runs beside the hero on the side of the road's centre, so the camera always sees it
        float wantSide = hero.x > roadX + 0.5f ? -1f : 1f;
        side = Mathf.MoveTowards(side, wantSide, dt * 1.5f);
        float sideOffset = grabbing ? 1.25f : 1.0f;
        transform.position = new Vector3(hero.x + side * sideOffset, 0f, hero.z - distanceBehind);
        transform.rotation = Quaternion.Euler(0f, -side * (grabbing ? 12f : 6f), 0f);

        // running or standing?
        bool moving = roadSpeed > 0.1f || Mathf.Abs(distanceBehind - targetDistance) > 0.05f;
        stopped = Mathf.MoveTowards(stopped, moving ? 0f : 1f, dt * 3f);
        roar = Mathf.MoveTowards(roar, 0f, dt * 0.8f);
        if (!moving) idleTime += dt;
        else idleTime = 0f;

        // ---- the run: a heavy gait ----
        phase += dt * (6f + Mathf.Min(roadSpeed, 25f) * 0.22f) * (1f - stopped * 0.85f);
        float s = Mathf.Sin(phase);
        float run = 1f - stopped;

        if (run > 0.3f && Mathf.Sign(s) != Mathf.Sign(lastStep))
        {
            float near = Mathf.Clamp01(1f - (distanceBehind - 1f) / 13f);
            if (near > 0.05f)
            {
                Sfx.Play(SynthAudio.GolemStep, 0.15f + 0.5f * near, Random.Range(0.9f, 1.05f));
                if (Stepped != null) Stepped(s > 0f ? legR.position : legL.position, near);
            }
        }
        lastStep = s;

        float liftL = Mathf.Max(0f, -s), liftR = Mathf.Max(0f, s);
        legL.localRotation = Quaternion.Euler(-38f * s * run, 0f, 0f);
        legR.localRotation = Quaternion.Euler(38f * s * run, 0f, 0f);
        kneeL.localRotation = Quaternion.Euler((25f + 45f * liftL) * run, 0f, 0f);
        kneeR.localRotation = Quaternion.Euler((25f + 45f * liftR) * run, 0f, 0f);

        float bob = Mathf.Abs(Mathf.Cos(phase)) * 0.14f * run;
        float breathe = Mathf.Sin(Time.time * 2.2f) * 0.03f * stopped;
        body.localPosition = new Vector3(0f, 1.25f - 0.12f * run + bob + breathe, 0f);
        float leanFwd = 16f * run - 6f * roar;
        body.localRotation = Quaternion.Euler(leanFwd, 7f * s * run, 3f * s * run);

        // ---- arms: swinging while running; standing - raised in a roar, then beating the chest ----
        Quaternion runL = Quaternion.Euler(45f * s, 0f, -12f), runR = Quaternion.Euler(-45f * s, 0f, 12f);
        Quaternion foreRun = Quaternion.Euler(-35f - 15f * Mathf.Abs(s), 0f, 0f);
        Quaternion upL = Quaternion.Euler(-150f, 0f, -25f), upR = Quaternion.Euler(-150f, 0f, 25f);

        Quaternion standL, standR, standForeL, standForeR;
        if (grabbing && idleTime > 1.4f)
        {
            // beating the chest: the fists swing in turn to the core
            float beat = Mathf.Repeat(idleTime * 2.4f, 2f);
            float hitL = beat < 1f ? Mathf.Sin(beat * Mathf.PI) : 0f;
            float hitR = beat >= 1f ? Mathf.Sin((beat - 1f) * Mathf.PI) : 0f;
            standL = Quaternion.Euler(-60f - 25f * hitL, 25f * hitL, -20f + 30f * hitL);
            standR = Quaternion.Euler(-60f - 25f * hitR, -25f * hitR, 20f - 30f * hitR);
            standForeL = Quaternion.Euler(-100f, 0f, 0f);
            standForeR = Quaternion.Euler(-100f, 0f, 0f);
            float prev = Mathf.Repeat((idleTime - dt) * 2.4f, 1f), now = Mathf.Repeat(idleTime * 2.4f, 1f);
            if (now < prev) { Sfx.Play(SynthAudio.GolemStep, 0.35f, 1.3f); roar = Mathf.Max(roar, 0.5f); }
        }
        else if (grabbing)
        {
            standL = upL; standR = upR;
            standForeL = standForeR = Quaternion.Euler(-30f, 0f, 0f);
            roar = Mathf.Max(roar, 0.9f);
        }
        else
        {
            // waiting at the start: fists down, slowly flexing
            float flex = Mathf.Sin(Time.time * 1.6f) * 6f;
            standL = Quaternion.Euler(10f + flex, 0f, -14f);
            standR = Quaternion.Euler(10f - flex, 0f, 14f);
            standForeL = standForeR = Quaternion.Euler(-25f, 0f, 0f);
        }
        float k = stopped;
        armL.localRotation = Quaternion.Slerp(runL, standL, k);
        armR.localRotation = Quaternion.Slerp(runR, standR, k);
        foreL.localRotation = Quaternion.Slerp(foreRun, standForeL, k);
        foreR.localRotation = Quaternion.Slerp(foreRun, standForeR, k);

        // ---- head and jaw: looking around while running, head up and jaw wide open when roaring ----
        float look = Mathf.Sin(phase * 0.5f) * 10f * run;
        head.localRotation = Quaternion.Euler(-22f * roar + 6f * run, look - side * 8f * stopped, 0f);
        float shake = roar > 0.2f ? Mathf.Sin(Time.time * 40f) * 2f * roar : 0f;
        jaw.localRotation = Quaternion.Euler(32f * roar + shake + 3f * Mathf.Abs(s) * run, 0f, 0f);

        // ---- the core pulses (faster and brighter while roaring) ----
        float pulse = 1f + 0.12f * Mathf.Sin(Time.time * (4f + 8f * roar)) + 0.35f * roar;
        core.localScale = Vector3.one * pulse;
    }
}
