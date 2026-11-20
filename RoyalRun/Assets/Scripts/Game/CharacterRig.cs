using System.Collections.Generic;
using UnityEngine;

// A hero model built from simple shapes, with a procedural animation:
//   run (knees and elbows bend, the body twists and leans into turns, the cape flutters),
//   jump / fall, landing squash, hit stumble, idle breathing and blinking, waving, cheering.
// It replaces the imported King model: the project works without any third-party assets.
// Style (index in CharacterCatalog): 0 King, 1 Knight, 2 Ranger, 3 Alchemist, 4 Pyro.
// The model faces +Z (the direction of running). Height is about 1.8 m.
public class CharacterRig : MonoBehaviour
{
    static readonly Color Skin = new Color(0.96f, 0.78f, 0.63f);
    static readonly Color Pants = new Color(0.22f, 0.19f, 0.28f);
    static readonly Color Boots = new Color(0.30f, 0.18f, 0.10f);
    static readonly Color Gold = new Color(1f, 0.78f, 0.22f);
    static readonly Color Metal = new Color(0.74f, 0.76f, 0.82f);
    static readonly Color Dark = new Color(0.07f, 0.05f, 0.09f);
    static readonly Color White = new Color(0.97f, 0.96f, 0.93f);
    static readonly Color Wood = new Color(0.45f, 0.28f, 0.14f);
    static readonly Color Lips = new Color(0.62f, 0.25f, 0.25f);

    // the main ("clothes") colour of each hero when no tint is given
    static readonly Color[] DefaultMain =
    {
        new Color(0.80f, 0.14f, 0.18f),   // King - royal red
        new Color(0.28f, 0.48f, 0.95f),   // Knight - blue
        new Color(0.28f, 0.60f, 0.27f),   // Ranger - green
        new Color(0.55f, 0.30f, 0.80f),   // Alchemist - purple
        new Color(0.95f, 0.45f, 0.15f),   // Pyro - orange
    };

    static readonly Color[] HairColor =
    {
        new Color(0.85f, 0.85f, 0.82f),   // King - grey
        new Color(0.35f, 0.22f, 0.12f),   // Knight
        new Color(0.55f, 0.33f, 0.15f),   // Ranger
        new Color(0.90f, 0.90f, 0.92f),   // Alchemist - white
        new Color(1f, 0.45f, 0.10f),      // Pyro
    };

    [SerializeField] Transform visual, body, head, hipL, hipR, kneeL, kneeR, shoulderL, shoulderR, elbowL, elbowR, capeTop, capeBottom;
    [SerializeField] Transform[] eyes;
    [SerializeField] Transform mouth;
    [SerializeField] Transform[] bouncers;     // plume, hood tip, scarf end: they wobble with the run
    [SerializeField] int style;
    [SerializeField] Transform[] flickers;     // flames that flicker (Pyro), glowing things
    [SerializeField] Renderer[] clothes;       // tinted with the main colour
    [SerializeField] float[] clothShade;       // brightness of each tinted part (the cape is darker, etc.)
    [SerializeField] Color defaultColor = Color.white;

    // ---- set every frame by PlayerAvatar (or the lobby) ----
    [System.NonSerialized] public bool running;
    [System.NonSerialized] public float runSpeed = 1f;    // 1 = normal speed
    [System.NonSerialized] public float lateral;          // -1..1 sideways movement (lean into the turn)
    [System.NonSerialized] public bool airborne;
    [System.NonSerialized] public float verticalSpeed;
    [System.NonSerialized] public bool showcase;          // on a podium: waves now and then
    [System.NonSerialized] public bool cheering;          // arms up, hopping (READY in the lobby)
    [System.NonSerialized] public bool defeated;          // time is up: tired, hands on the knees
    [System.NonSerialized] public bool sliding;           // sliding under a beam: leaning back, legs forward

    // A foot touched the ground while running (PlayerAvatar puts a puff of dust there).
    public event System.Action Footstep;

    // each hero runs a little differently: arm swing (degrees), forward lean, bounce
    static readonly float[] ArmSwing = { 34f, 30f, 46f, 28f, 52f };
    static readonly float[] Lean = { 8f, 11f, 14f, 7f, 13f };
    static readonly float[] Bounce = { 0.04f, 0.065f, 0.05f, 0.035f, 0.06f };
    Quaternion[] bouncerBase;
    float lastStepSin;

    float phase;
    float hitTimer;
    float landTimer;
    float blinkTimer = 2f;
    float waveTimer = 3f;
    float time;
    Vector3[] flickerBase;
    Vector3 mouthBase;
    float mouthOpen;

    const float Smooth = 16f;

    public void PlayHit() { hitTimer = 0.5f; }
    public void Land() { landTimer = 0.18f; }

    public void ApplyTint(Color tint)
    {
        Color main = (tint == Color.white) ? defaultColor : tint;
        if (clothes == null) return;
        for (int i = 0; i < clothes.Length; i++)
        {
            if (clothes[i] == null) continue;
            float k = (clothShade != null && i < clothShade.Length) ? clothShade[i] : 1f;
            clothes[i].sharedMaterial = MatLib.Get(new Color(Mathf.Clamp01(main.r * k), Mathf.Clamp01(main.g * k), Mathf.Clamp01(main.b * k)),
                                                   0.05f, 0f, Surface.Fabric, Vector2.one * 2f);
        }
    }

    void Start()
    {
        phase = Random.value * 10f;
        waveTimer = 2f + Random.value * 4f;
        if (flickers != null)
        {
            flickerBase = new Vector3[flickers.Length];
            for (int i = 0; i < flickers.Length; i++) if (flickers[i] != null) flickerBase[i] = flickers[i].localScale;
        }
        if (mouth != null) mouthBase = mouth.localScale;
        if (bouncers != null)
        {
            bouncerBase = new Quaternion[bouncers.Length];
            for (int i = 0; i < bouncers.Length; i++) if (bouncers[i] != null) bouncerBase[i] = bouncers[i].localRotation;
        }
    }

    // ======================================================================
    //  Animation
    // ======================================================================

    void Update()
    {
        if (body == null) return;
        float dt = Time.deltaTime;
        if (dt <= 0f) return;
        time += dt;
        float blend = 1f - Mathf.Exp(-Smooth * dt);

        // target angles (pitch = around X, roll = around Z)
        float hipLx, hipRx, kneeLx, kneeRx, shLx, shRx, shLz, shRz, elLx, elRx;
        float bodyX, bodyY, bodyZ, headX, headY, capeA, capeB;
        float bob;

        if (airborne)
        {
            bool falling = verticalSpeed < 0f;
            hipLx = falling ? -18f : -40f;  hipRx = falling ? -8f : -20f;
            kneeLx = falling ? 30f : 90f;   kneeRx = falling ? 20f : 60f;
            shLx = falling ? -110f : -150f; shRx = falling ? -100f : -140f;
            shLz = -22f; shRz = 22f;
            elLx = -25f; elRx = -25f;
            bodyX = falling ? 6f : -4f; bodyY = 0f; bodyZ = -lateral * 10f;
            headX = -8f; headY = 0f;
            capeA = 70f; capeB = 25f;
            bob = 0f;
        }
        else if (running)
        {
            phase += dt * 10f * Mathf.Clamp(runSpeed, 0.6f, 2.3f);
            float s = Mathf.Sin(phase), c = Mathf.Cos(phase);
            int st = Mathf.Clamp(style, 0, ArmSwing.Length - 1);
            float swing = ArmSwing[st];
            hipLx = -42f * s;                 hipRx = 42f * s;
            kneeLx = 8f + 75f * Mathf.Max(0f, c); kneeRx = 8f + 75f * Mathf.Max(0f, -c);
            shLx = swing * s;                 shRx = -swing * s;
            shLz = -8f; shRz = 8f;
            elLx = -80f + 10f * s;            elRx = -80f - 10f * s;
            if (st == 3) { shRx = -swing * 0.3f * s - 20f; elRx = -100f; }   // the alchemist holds the potion up
            bodyX = Lean[st] + Mathf.Clamp(runSpeed - 1f, 0f, 1f) * 6f;

            // a footstep each time a leg passes under the body
            if (!airborne && !sliding && Mathf.Sign(s) != Mathf.Sign(lastStepSin) && Footstep != null) Footstep();
            lastStepSin = s;
            bodyY = 7f * s + lateral * 10f;
            bodyZ = -lateral * 13f;
            headX = -7f; headY = -5f * s;
            float flutter = Mathf.Sin(time * 13f);
            capeA = 25f + 12f * runSpeed + 6f * flutter;
            capeB = 12f + 9f * Mathf.Sin(time * 13f + 1.2f);
            bob = Bounce[st] * Mathf.Abs(c);
        }
        else
        {
            // idle: breathing, slight sway
            phase += dt * 2.2f;
            float s = Mathf.Sin(phase);
            hipLx = 0f; hipRx = 0f; kneeLx = 3f; kneeRx = 3f;
            shLx = 4f * s; shRx = -4f * s; shLz = -7f - 2f * s; shRz = 7f + 2f * s;
            elLx = -12f; elRx = -12f;
            bodyX = 0f; bodyY = 0f; bodyZ = 0f;
            headX = 0f; headY = Mathf.Sin(phase * 0.45f) * 10f;
            capeA = 6f + 2f * s; capeB = 3f;
            bob = 0.01f * s;

            if (showcase && !cheering)
            {
                // a wave of the right hand every few seconds
                waveTimer -= dt;
                if (waveTimer < 1.6f)
                {
                    float w = Mathf.Sin(Mathf.Clamp01(waveTimer / 1.6f) * Mathf.PI);
                    shRx = Mathf.Lerp(shRx, -155f, w);
                    shRz = Mathf.Lerp(shRz, 25f, w);
                    elRx = Mathf.Lerp(elRx, -35f + 30f * Mathf.Sin(time * 13f), w);
                    headY = Mathf.Lerp(headY, 0f, w);
                }
                if (waveTimer <= 0f) waveTimer = 5f + Random.value * 4f;
            }

            if (cheering)
            {
                float h = Mathf.Abs(Mathf.Sin(time * 6.5f));
                shLx = -165f; shRx = -165f; shLz = -28f; shRz = 28f;
                elLx = -15f + 15f * h; elRx = -15f + 15f * h;
                kneeLx = 25f * (1f - h); kneeRx = 25f * (1f - h);
                headX = -10f;
                bob = 0.18f * h;
            }
        }

        // a slide: low, leaning back, legs straight forward, arms back for balance
        if (sliding && !airborne)
        {
            bodyX = -55f; bodyY = 0f; bodyZ = -lateral * 8f;
            hipLx = -85f; hipRx = -78f; kneeLx = 8f; kneeRx = 20f;
            shLx = 45f; shRx = 45f; shLz = -35f; shRz = 35f;
            elLx = -20f; elRx = -20f;
            headX = 30f; headY = 0f;
            capeA = 85f; capeB = 10f;
            bob = -0.58f;
        }

        // time is up: bent forward, hands on the knees, heavy breathing
        if (defeated && !airborne)
        {
            float br = Mathf.Sin(time * 4f);
            bodyX = 38f + br * 3f; bodyY = 0f; bodyZ = 0f;
            hipLx = -38f; hipRx = -38f; kneeLx = 45f; kneeRx = 45f;
            shLx = -50f; shRx = -50f; shLz = 12f; shRz = -12f;
            elLx = -10f; elRx = -10f;
            headX = -20f + br * 2f; headY = 0f;
            capeA = 15f; capeB = 5f;
            bob = -0.12f;
        }

        // a hit: the body is thrown back, the arms flail
        if (hitTimer > 0f)
        {
            hitTimer -= dt;
            float k = Mathf.Clamp01(hitTimer / 0.5f);
            bodyX = Mathf.Lerp(bodyX, -28f, k);
            bodyZ += Mathf.Sin(hitTimer * 40f) * 10f * k;
            shLx = Mathf.Lerp(shLx, -100f, k); shRx = Mathf.Lerp(shRx, -100f, k);
            shLz = Mathf.Lerp(shLz, -45f, k); shRz = Mathf.Lerp(shRz, 45f, k);
            headX = Mathf.Lerp(headX, -18f, k);
            blend = 1f - Mathf.Exp(-30f * dt);
        }

        Rot(hipL, hipLx, 0f, 0f, blend);
        Rot(hipR, hipRx, 0f, 0f, blend);
        Rot(kneeL, kneeLx, 0f, 0f, blend);
        Rot(kneeR, kneeRx, 0f, 0f, blend);
        Rot(shoulderL, shLx, 0f, shLz, blend);
        Rot(shoulderR, shRx, 0f, shRz, blend);
        Rot(elbowL, elLx, 0f, 0f, blend);
        Rot(elbowR, elRx, 0f, 0f, blend);
        Rot(body, bodyX, bodyY, bodyZ, blend);
        Rot(head, headX, headY, 0f, blend);
        Rot(capeTop, capeA, 0f, 0f, blend);
        Rot(capeBottom, capeB, 0f, 0f, blend);

        // bounce and landing squash
        if (visual != null)
        {
            Vector3 p = visual.localPosition;
            p.y = Mathf.Lerp(p.y, bob, blend);
            visual.localPosition = p;

            Vector3 scale = Vector3.one;
            if (landTimer > 0f)
            {
                landTimer -= dt;
                float k = Mathf.Sin(Mathf.Clamp01(landTimer / 0.18f) * Mathf.PI);
                scale = new Vector3(1f + 0.09f * k, 1f - 0.13f * k, 1f + 0.09f * k);
            }
            visual.localScale = scale;
        }

        // the mouth opens in a jump, on a hit and when cheering ("O!")
        float wantOpen = (hitTimer > 0f || cheering || airborne || sliding) ? 1f : (defeated ? 0.5f : 0f);
        mouthOpen = Mathf.Lerp(mouthOpen, wantOpen, 1f - Mathf.Exp(-12f * dt));
        if (mouth != null)
            mouth.localScale = new Vector3(mouthBase.x * (1f - 0.3f * mouthOpen), mouthBase.y * (1f + 3.5f * mouthOpen), mouthBase.z);

        // plumes, hoods and scarves wobble (more when running or jumping)
        if (bouncers != null && bouncerBase != null)
        {
            float amp = airborne ? 18f : running ? 10f : 3f;
            for (int i = 0; i < bouncers.Length; i++)
            {
                if (bouncers[i] == null) continue;
                float w = Mathf.Sin(time * (running ? 14f : 3f) + i * 1.7f);
                bouncers[i].localRotation = bouncerBase[i] * Quaternion.Euler(w * amp, 0f, w * amp * 0.4f);
            }
        }

        // blinking
        blinkTimer -= dt;
        float eyeY = blinkTimer < 0.12f ? 0.15f : 1f;
        if (blinkTimer <= 0f) blinkTimer = 2.5f + Random.value * 3f;
        if (eyes != null)
            foreach (Transform e in eyes)
                if (e != null) { Vector3 ls = e.localScale; ls.y = ls.x * eyeY; e.localScale = ls; }

        // flames flicker
        if (flickers != null && flickerBase != null)
        {
            for (int i = 0; i < flickers.Length; i++)
            {
                if (flickers[i] == null) continue;
                float n = Mathf.PerlinNoise(time * 6f, i * 3.7f);
                Vector3 b = flickerBase[i];
                flickers[i].localScale = new Vector3(b.x * (0.85f + 0.3f * n), b.y * (0.75f + 0.5f * n), b.z);
            }
        }
    }

    static void Rot(Transform t, float x, float y, float z, float blend)
    {
        if (t == null) return;
        t.localRotation = Quaternion.Slerp(t.localRotation, Quaternion.Euler(x, y, z), blend);
    }

    // ======================================================================
    //  Building the model: one smooth skinned mesh (no boxes)
    // ======================================================================

    static readonly Color[] HairByStyle =
    {
        new Color(0.88f, 0.88f, 0.86f),   // King - silver
        new Color(0.40f, 0.25f, 0.13f),   // Knight
        new Color(0.62f, 0.38f, 0.17f),   // Ranger - auburn
        new Color(0.93f, 0.93f, 0.95f),   // Alchemist - white
        new Color(1f, 0.42f, 0.08f),      // Pyro
    };

    static readonly Color Cheek = new Color(1f, 0.62f, 0.58f);
    static readonly Color Iris = new Color(0.22f, 0.36f, 0.62f);

    // main: the clothes colour (null = the hero's own colour).
    public static GameObject Build(int style, Transform parent)
    {
        return Build(style, parent, Color.white);
    }

    public static GameObject Build(int style, Transform parent, Color tint)
    {
        style = Mathf.Clamp(style, 0, DefaultMain.Length - 1);
        Color main = tint == Color.white ? DefaultMain[style] : tint;
        Color dark = new Color(main.r * 0.6f, main.g * 0.6f, main.b * 0.6f);
        Color hair = HairByStyle[style];

        GameObject root = new GameObject("Hero " + style);
        root.transform.SetParent(parent, false);
        CharacterRig rig = root.AddComponent<CharacterRig>();
        rig.defaultColor = main;
        rig.style = style;
        Transform r = root.transform;

        // ---- the skeleton (the animation moves these) ----
        rig.visual = Pivot("Visual", r, Vector3.zero);
        rig.hipL = Pivot("Hip L", rig.visual, new Vector3(-0.11f, 0.8f, 0f));
        rig.hipR = Pivot("Hip R", rig.visual, new Vector3(0.11f, 0.8f, 0f));
        rig.kneeL = Pivot("Knee L", rig.hipL, new Vector3(0f, -0.38f, 0f));
        rig.kneeR = Pivot("Knee R", rig.hipR, new Vector3(0f, -0.38f, 0f));
        rig.body = Pivot("Body", rig.visual, new Vector3(0f, 0.8f, 0f));
        rig.shoulderL = Pivot("Shoulder L", rig.body, new Vector3(-0.25f, 0.5f, 0f));
        rig.shoulderR = Pivot("Shoulder R", rig.body, new Vector3(0.25f, 0.5f, 0f));
        rig.elbowL = Pivot("Elbow L", rig.shoulderL, new Vector3(-0.015f, -0.26f, 0f));
        rig.elbowR = Pivot("Elbow R", rig.shoulderR, new Vector3(0.015f, -0.26f, 0f));
        rig.head = Pivot("Head", rig.body, new Vector3(0f, 0.6f, 0f));
        rig.capeTop = Pivot("Cape", rig.body, new Vector3(0f, 0.56f, -0.13f));
        rig.capeBottom = Pivot("Cape Low", rig.capeTop, new Vector3(0f, -0.3f, 0f));
        Transform eyeL = Pivot("Eye L", rig.head, new Vector3(-0.078f, 0.215f, 0.185f));
        Transform eyeR = Pivot("Eye R", rig.head, new Vector3(0.078f, 0.215f, 0.185f));
        rig.mouth = Pivot("Mouth", rig.head, new Vector3(0f, 0.1f, 0.2f));
        rig.eyes = new[] { eyeL, eyeR };

        ShapeBuilder sb = new ShapeBuilder(r);
        sb.Detail = PlayerWorld.Lite ? 10 : 14;
        List<Transform> flick = new List<Transform>();
        List<Transform> bounce = new List<Transform>();

        // ---- legs: one smooth tube from hip to ankle that bends at the knee ----
        Color pants = style == 4 ? new Color(0.25f, 0.22f, 0.2f) : Pants;
        foreach (int side in new[] { -1, 1 })
        {
            Transform hip = side < 0 ? rig.hipL : rig.hipR;
            Transform knee = side < 0 ? rig.kneeL : rig.kneeR;
            float x = side * 0.11f;
            sb.Limb(hip, knee, new Vector3(x, 0.84f, 0f), new Vector3(x, 0.42f, 0.01f), new Vector3(x, 0.1f, 0f), 0.09f, 0.068f, 0.058f, pants);
            // a rounded boot with a toe and a cuff
            sb.RoundBox(knee, new Vector3(0f, -0.34f, 0.045f), new Vector3(0.15f, 0.12f, 0.27f), Boots, ShapeBuilder.Matte, default(Quaternion), 0.55f);
            sb.Ellipsoid(knee, new Vector3(0f, -0.355f, 0.15f), new Vector3(0.075f, 0.055f, 0.06f), Boots);
            sb.Torus(knee, new Vector3(0f, -0.27f, 0f), 0.068f, 0.022f, Color.Lerp(Boots, Color.black, 0.2f));
        }

        // ---- body: a smooth torso (hips -> waist -> chest -> shoulders) ----
        sb.Ellipsoid(rig.body, new Vector3(0f, 0.03f, 0f), new Vector3(0.2f, 0.13f, 0.15f), pants);
        sb.Lathe(rig.body, Vector3.zero,
                 new[] { 0.19f, 0.185f, 0.17f, 0.18f, 0.2f, 0.205f, 0.17f, 0.07f },
                 new[] { -0.02f, 0.08f, 0.2f, 0.3f, 0.4f, 0.48f, 0.55f, 0.6f }, main, ShapeBuilder.Matte, default(Quaternion), 0.74f);
        // a short skirt of the tunic over the hips
        sb.Lathe(rig.body, Vector3.zero, new[] { 0.245f, 0.215f, 0.195f }, new[] { -0.17f, -0.05f, 0.06f }, dark, ShapeBuilder.Matte, default(Quaternion), 0.8f, false, false);
        sb.Torus(rig.body, new Vector3(0f, 0.07f, 0f), 0.19f, 0.03f, style == 0 ? Gold : Wood, style == 0 ? ShapeBuilder.Shiny : ShapeBuilder.Matte, default(Quaternion), 0.76f);
        sb.RoundBox(rig.body, new Vector3(0f, 0.07f, 0.145f), new Vector3(0.08f, 0.07f, 0.03f), Gold, ShapeBuilder.Shiny);
        sb.Lathe(rig.body, Vector3.zero, new[] { 0.07f, 0.065f }, new[] { 0.56f, 0.66f }, Skin, ShapeBuilder.Matte, default(Quaternion), 1f, false, false);

        // ---- arms: a smooth tube from shoulder to wrist that bends at the elbow, round hands ----
        foreach (int side in new[] { -1, 1 })
        {
            Transform sh = side < 0 ? rig.shoulderL : rig.shoulderR;
            Transform el = side < 0 ? rig.elbowL : rig.elbowR;
            float x = side * 0.25f;
            sb.Ellipsoid(sh, Vector3.zero, new Vector3(0.09f, 0.085f, 0.09f), main);
            sb.Limb(sh, el, new Vector3(x, 1.3f, 0f), new Vector3(x + side * 0.015f, 1.04f, 0f), new Vector3(x + side * 0.015f, 0.82f, 0.01f), 0.07f, 0.058f, 0.05f, main);
            sb.Torus(el, new Vector3(0f, -0.21f, 0f), 0.05f, 0.016f, dark);
            sb.Ellipsoid(el, new Vector3(0f, -0.29f, 0.01f), new Vector3(0.058f, 0.075f, 0.05f), Skin);
            sb.Ellipsoid(el, new Vector3(-side * 0.045f, -0.27f, 0.035f), new Vector3(0.022f, 0.038f, 0.022f), Skin, ShapeBuilder.Matte, Quaternion.Euler(0f, 0f, side * 30f));
        }

        // ---- head: a big rounded head, cheeks, nose, ears, shiny eyes with a highlight, brows, mouth ----
        Transform h = rig.head;
        sb.Ellipsoid(h, new Vector3(0f, 0.21f, 0f), new Vector3(0.215f, 0.225f, 0.205f), Skin);
        sb.Ellipsoid(h, new Vector3(0f, 0.13f, 0.04f), new Vector3(0.175f, 0.125f, 0.165f), Skin);
        sb.Ellipsoid(h, new Vector3(0f, 0.165f, 0.205f), new Vector3(0.034f, 0.04f, 0.035f), Color.Lerp(Skin, Cheek, 0.35f));
        sb.Ellipsoid(h, new Vector3(-0.21f, 0.19f, 0f), new Vector3(0.035f, 0.06f, 0.03f), Skin);
        sb.Ellipsoid(h, new Vector3(0.21f, 0.19f, 0f), new Vector3(0.035f, 0.06f, 0.03f), Skin);
        sb.Ellipsoid(h, new Vector3(-0.115f, 0.13f, 0.165f), new Vector3(0.045f, 0.025f, 0.02f), Cheek);
        sb.Ellipsoid(h, new Vector3(0.115f, 0.13f, 0.165f), new Vector3(0.045f, 0.025f, 0.02f), Cheek);
        foreach (Transform e in rig.eyes)
        {
            sb.Ellipsoid(e, Vector3.zero, new Vector3(0.046f, 0.058f, 0.03f), White, ShapeBuilder.Shiny);
            sb.Ellipsoid(e, new Vector3(0f, -0.005f, 0.021f), new Vector3(0.028f, 0.036f, 0.014f), Iris, ShapeBuilder.Shiny);
            sb.Ellipsoid(e, new Vector3(0f, -0.005f, 0.03f), new Vector3(0.016f, 0.02f, 0.008f), Dark, ShapeBuilder.Shiny);
            sb.Ellipsoid(e, new Vector3(0.011f, 0.014f, 0.036f), new Vector3(0.008f, 0.009f, 0.004f), Color.white, ShapeBuilder.Glow);
        }
        if (style != 1)
        {
            sb.RoundBox(h, new Vector3(-0.078f, 0.288f, 0.18f), new Vector3(0.075f, 0.02f, 0.025f), Color.Lerp(hair, Dark, 0.3f), ShapeBuilder.Matte, Quaternion.Euler(0f, 0f, -10f), 0.8f);
            sb.RoundBox(h, new Vector3(0.078f, 0.288f, 0.18f), new Vector3(0.075f, 0.02f, 0.025f), Color.Lerp(hair, Dark, 0.3f), ShapeBuilder.Matte, Quaternion.Euler(0f, 0f, 10f), 0.8f);
        }
        sb.Ellipsoid(rig.mouth, Vector3.zero, new Vector3(0.042f, 0.012f, 0.014f), new Color(0.45f, 0.12f, 0.15f));

        BuildOutfit(style, rig, sb, main, dark, hair, flick, bounce);

        // ---- one skinned renderer for everything ----
        rig.flickers = flick.ToArray();
        rig.bouncers = bounce.ToArray();
        rig.clothes = new Renderer[0];
        rig.clothShade = new float[0];
        PaletteLib.Flush();
        SkinnedMeshRenderer smr = sb.BuildSkinned(root, rig.visual, "Hero " + style);
        smr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
        return root;
    }

    // Hair cap: covers the top and the back of the head, a fringe over the forehead.
    static void Hair(ShapeBuilder sb, Transform h, Color hair, bool fringe)
    {
        sb.Ellipsoid(h, new Vector3(0f, 0.255f, -0.03f), new Vector3(0.232f, 0.215f, 0.225f), hair);
        if (!fringe) return;
        for (int i = -1; i <= 1; i++)
            sb.Ellipsoid(h, new Vector3(i * 0.09f, 0.35f, 0.14f), new Vector3(0.075f, 0.05f, 0.06f), hair, ShapeBuilder.Matte, Quaternion.Euler(20f, 0f, -i * 25f));
    }

    static void BuildOutfit(int style, CharacterRig rig, ShapeBuilder sb, Color main, Color dark, Color hair,
                            List<Transform> flick, List<Transform> bounce)
    {
        Transform h = rig.head, bd = rig.body;
        switch (style)
        {
            case 0: // King: silver hair and a big beard, a gold crown with jewels, an ermine collar, a sceptre, a red cape
            {
                Hair(sb, h, hair, false);
                sb.Ellipsoid(h, new Vector3(0f, 0.04f, 0.1f), new Vector3(0.19f, 0.17f, 0.14f), hair);
                sb.Ellipsoid(h, new Vector3(0f, 0.115f, 0.19f), new Vector3(0.09f, 0.025f, 0.03f), hair);
                sb.Lathe(h, new Vector3(0f, 0.36f, -0.01f), new[] { 0.2f, 0.205f, 0.2f }, new[] { 0f, 0.05f, 0.09f }, Gold, ShapeBuilder.Shiny, default(Quaternion), 1f, false, false);
                for (int i = 0; i < 6; i++)
                {
                    float a = i * Mathf.PI * 2f / 6f;
                    Vector3 p = new Vector3(Mathf.Sin(a) * 0.19f, 0.45f, Mathf.Cos(a) * 0.19f - 0.01f);
                    sb.Lathe(h, p, new[] { 0.035f, 0.0f }, new[] { 0f, 0.09f }, Gold, ShapeBuilder.Shiny, default(Quaternion), 1f, true, false);
                    sb.Ellipsoid(h, p + Vector3.up * 0.1f, Vector3.one * 0.02f, White, ShapeBuilder.Shiny);
                }
                sb.Ellipsoid(h, new Vector3(0f, 0.405f, 0.2f), new Vector3(0.035f, 0.035f, 0.02f), new Color(0.9f, 0.1f, 0.2f), ShapeBuilder.Glow);
                sb.Ellipsoid(h, new Vector3(0f, 0.43f, -0.01f), new Vector3(0.18f, 0.06f, 0.17f), new Color(0.65f, 0.1f, 0.15f));
                sb.Torus(bd, new Vector3(0f, 0.53f, 0f), 0.17f, 0.05f, White, ShapeBuilder.Matte, default(Quaternion), 0.8f);
                for (int i = -1; i <= 1; i++) sb.Ellipsoid(bd, new Vector3(i * 0.09f, 0.54f, 0.155f), Vector3.one * 0.016f, Dark);
                sb.Cloth(rig.capeTop, rig.capeBottom, new Vector3(-0.2f, 1.36f, -0.15f), new Vector3(0.2f, 1.36f, -0.15f), 0.78f, 0.08f, dark);
                sb.Lathe(rig.elbowR, new Vector3(0f, -0.29f, 0.04f), new[] { 0.02f, 0.02f }, new[] { -0.08f, 0.35f }, Gold, ShapeBuilder.Shiny, Quaternion.Euler(70f, 0f, 0f));
                sb.Ellipsoid(rig.elbowR, new Vector3(0f, -0.17f, 0.37f), Vector3.one * 0.05f, new Color(0.9f, 0.15f, 0.3f), ShapeBuilder.Glow);
                break;
            }

            case 1: // Knight: a rounded helmet with a visor and a plume, a breastplate, pauldrons, a shield, a sword
            {
                Color metal = Metal;
                sb.Ellipsoid(h, new Vector3(0f, 0.23f, -0.005f), new Vector3(0.245f, 0.255f, 0.235f), metal, ShapeBuilder.Shiny);
                sb.RoundBox(h, new Vector3(0f, 0.2f, 0.22f), new Vector3(0.3f, 0.07f, 0.04f), Dark, ShapeBuilder.Matte, default(Quaternion), 0.6f);
                sb.Torus(h, new Vector3(0f, 0.1f, 0f), 0.2f, 0.025f, Gold, ShapeBuilder.Shiny);
                Transform plume = Pivot("Plume", h, new Vector3(0f, 0.46f, -0.04f));
                bounce.Add(plume);
                for (int i = 0; i < 4; i++)
                    sb.Ellipsoid(plume, new Vector3(0f, 0.03f - i * 0.025f, -i * 0.07f), new Vector3(0.04f, 0.06f, 0.06f), main);
                sb.Lathe(bd, new Vector3(0f, 0.01f, 0.012f), new[] { 0.2f, 0.19f, 0.205f, 0.215f, 0.18f }, new[] { 0.12f, 0.22f, 0.34f, 0.46f, 0.55f },
                         metal, ShapeBuilder.Shiny, default(Quaternion), 0.78f, false, false);
                sb.Ellipsoid(rig.shoulderL, new Vector3(-0.02f, 0.03f, 0f), new Vector3(0.12f, 0.08f, 0.11f), metal, ShapeBuilder.Shiny);
                sb.Ellipsoid(rig.shoulderR, new Vector3(0.02f, 0.03f, 0f), new Vector3(0.12f, 0.08f, 0.11f), metal, ShapeBuilder.Shiny);
                // the shield on the left forearm
                Quaternion face = Quaternion.Euler(0f, 0f, 90f);
                sb.Lathe(rig.elbowL, new Vector3(-0.07f, -0.13f, 0.02f), new[] { 0.21f, 0.2f, 0.0f }, new[] { 0f, 0.02f, 0.045f }, main, ShapeBuilder.Matte, face);
                sb.Torus(rig.elbowL, new Vector3(-0.072f, -0.13f, 0.02f), 0.205f, 0.018f, metal, ShapeBuilder.Shiny, face);
                sb.RoundBox(rig.elbowL, new Vector3(-0.12f, -0.13f, 0.02f), new Vector3(0.02f, 0.2f, 0.05f), Gold, ShapeBuilder.Shiny);
                sb.RoundBox(rig.elbowL, new Vector3(-0.12f, -0.1f, 0.02f), new Vector3(0.02f, 0.05f, 0.17f), Gold, ShapeBuilder.Shiny);
                // a sword on the back
                Quaternion tilt = Quaternion.Euler(0f, 0f, 30f);
                sb.RoundBox(bd, new Vector3(0.05f, 0.33f, -0.18f), new Vector3(0.05f, 0.62f, 0.015f), metal, ShapeBuilder.Shiny, tilt, 0.3f);
                sb.RoundBox(bd, new Vector3(0.21f, 0.62f, -0.18f), new Vector3(0.18f, 0.035f, 0.035f), Gold, ShapeBuilder.Shiny, tilt, 0.5f);
                sb.Cloth(rig.capeTop, rig.capeBottom, new Vector3(-0.19f, 1.36f, -0.16f), new Vector3(0.19f, 1.36f, -0.16f), 0.62f, 0.06f, dark);
                break;
            }

            case 2: // Ranger: a pointed hood with a cape, a quiver of arrows, a bow on the back
            {
                Hair(sb, h, hair, true);
                sb.Ellipsoid(h, new Vector3(0f, 0.24f, -0.06f), new Vector3(0.25f, 0.245f, 0.245f), main);
                Transform tip = Pivot("Hood Tip", h, new Vector3(0f, 0.33f, -0.27f));
                bounce.Add(tip);
                sb.Lathe(tip, Vector3.zero, new[] { 0.09f, 0.0f }, new[] { 0f, 0.2f }, main, ShapeBuilder.Matte, Quaternion.Euler(-120f, 0f, 0f), 1f, true, false);
                sb.Torus(bd, new Vector3(0f, 0.55f, -0.01f), 0.15f, 0.05f, dark, ShapeBuilder.Matte, default(Quaternion), 0.85f);
                sb.Cloth(rig.capeTop, rig.capeBottom, new Vector3(-0.2f, 1.36f, -0.15f), new Vector3(0.2f, 1.36f, -0.15f), 0.7f, 0.07f, dark);
                Quaternion q = Quaternion.Euler(-10f, 0f, -22f);
                sb.Lathe(bd, new Vector3(0.12f, 0.15f, -0.21f), new[] { 0.065f, 0.07f, 0.065f }, new[] { 0f, 0.2f, 0.4f }, Wood, ShapeBuilder.Matte, q);
                for (int i = 0; i < 3; i++)
                {
                    Vector3 p = new Vector3(0.18f + (i - 1) * 0.03f, 0.58f, -0.24f);
                    sb.RoundBox(bd, p, new Vector3(0.012f, 0.22f, 0.012f), Wood, ShapeBuilder.Matte, q, 0.6f);
                    sb.Ellipsoid(bd, p + new Vector3(0.04f, 0.1f, 0f), new Vector3(0.03f, 0.05f, 0.008f), White, ShapeBuilder.Matte, q);
                }
                sb.Torus(bd, new Vector3(-0.04f, 0.3f, -0.22f), 0.32f, 0.018f, Wood, ShapeBuilder.Matte, Quaternion.Euler(90f, 0f, 30f), 1f, 160f);
                break;
            }

            case 3: // Alchemist: a tall bent wizard hat with a star, a long beard, a long robe, a glowing potion
            {
                Hair(sb, h, hair, false);
                sb.Ellipsoid(h, new Vector3(0f, -0.02f, 0.1f), new Vector3(0.17f, 0.25f, 0.12f), hair);
                sb.Ellipsoid(h, new Vector3(0f, 0.115f, 0.19f), new Vector3(0.1f, 0.028f, 0.03f), hair);
                sb.Lathe(h, new Vector3(0f, 0.36f, 0f), new[] { 0.33f, 0.33f, 0.21f, 0.2f }, new[] { 0f, 0.02f, 0.03f, 0.06f }, dark);
                Transform tip = Pivot("Hat", h, new Vector3(0f, 0.4f, 0f));
                bounce.Add(tip);
                sb.Lathe(tip, Vector3.zero, new[] { 0.19f, 0.14f, 0.09f, 0.045f, 0.0f }, new[] { 0f, 0.14f, 0.27f, 0.38f, 0.46f }, main,
                         ShapeBuilder.Matte, Quaternion.Euler(-14f, 0f, 0f), 1f, false, false);
                sb.Torus(tip, new Vector3(0f, 0.02f, 0f), 0.19f, 0.022f, Gold, ShapeBuilder.Shiny);
                Transform star = Pivot("Star", tip, new Vector3(0f, 0.3f, 0.13f));
                flick.Add(star);
                sb.Ellipsoid(star, Vector3.zero, new Vector3(0.045f, 0.045f, 0.015f), Gold, ShapeBuilder.Glow);
                // a long robe to the knees
                sb.Lathe(bd, Vector3.zero, new[] { 0.36f, 0.3f, 0.24f, 0.2f }, new[] { -0.5f, -0.3f, -0.12f, 0.05f }, main, ShapeBuilder.Matte, default(Quaternion), 0.85f, false, false);
                sb.Torus(bd, new Vector3(0f, -0.49f, 0f), 0.355f, 0.02f, Gold, ShapeBuilder.Shiny, default(Quaternion), 0.85f);
                Transform potion = Pivot("Potion", rig.elbowR, new Vector3(0f, -0.34f, 0.06f));
                flick.Add(potion);
                sb.Ellipsoid(potion, Vector3.zero, Vector3.one * 0.065f, new Color(0.3f, 1f, 0.5f), ShapeBuilder.Glow);
                sb.Lathe(rig.elbowR, new Vector3(0f, -0.29f, 0.06f), new[] { 0.025f, 0.025f }, new[] { 0f, 0.05f }, Wood);
                Color[] bottles = { new Color(1f, 0.3f, 0.3f), new Color(0.3f, 0.6f, 1f), new Color(1f, 0.85f, 0.2f) };
                for (int i = 0; i < 3; i++)
                    sb.Ellipsoid(bd, new Vector3(-0.12f + i * 0.12f, 0.06f, 0.17f), new Vector3(0.03f, 0.045f, 0.03f), bottles[i], ShapeBuilder.Glow);
                break;
            }

            default: // Pyro: flaming hair, goggles on the forehead, a scarf with a waving end, glowing fists
            {
                Hair(sb, h, Color.Lerp(hair, Color.black, 0.3f), false);
                Color[] flame = { new Color(1f, 0.32f, 0.05f), new Color(1f, 0.58f, 0.1f), new Color(1f, 0.86f, 0.25f) };
                for (int i = 0; i < 6; i++)
                {
                    float x = (i - 2.5f) * 0.07f;
                    Transform f = Pivot("Flame", h, new Vector3(x, 0.37f + (i % 2) * 0.03f, -0.03f - (i % 3) * 0.04f));
                    flick.Add(f);
                    sb.Lathe(f, Vector3.zero, new[] { 0.055f, 0.045f, 0.0f }, new[] { 0f, 0.1f, 0.22f + (i % 3) * 0.05f }, flame[i % 3],
                             ShapeBuilder.Glow, Quaternion.Euler(-15f, 0f, -x * 200f), 1f, true, false);
                }
                sb.Torus(h, new Vector3(0f, 0.3f, 0f), 0.215f, 0.018f, Dark);
                foreach (int side in new[] { -1, 1 })
                {
                    sb.Torus(h, new Vector3(side * 0.07f, 0.32f, 0.19f), 0.045f, 0.012f, Dark, ShapeBuilder.Matte, Quaternion.Euler(90f, 0f, 0f));
                    sb.Ellipsoid(h, new Vector3(side * 0.07f, 0.32f, 0.195f), new Vector3(0.04f, 0.04f, 0.012f), new Color(1f, 0.65f, 0.2f), ShapeBuilder.Glow);
                }
                sb.Torus(bd, new Vector3(0f, 0.56f, 0f), 0.13f, 0.055f, main);
                Transform scarf = Pivot("Scarf End", rig.capeTop, new Vector3(0.1f, -0.02f, -0.02f));
                bounce.Add(scarf);
                sb.RoundBox(scarf, new Vector3(0f, -0.13f, 0f), new Vector3(0.09f, 0.28f, 0.025f), main, ShapeBuilder.Matte, default(Quaternion), 0.7f);
                foreach (Transform el in new[] { rig.elbowL, rig.elbowR })
                {
                    Transform fire = Pivot("Fire", el, new Vector3(0f, -0.29f, 0f));
                    flick.Add(fire);
                    sb.Ellipsoid(fire, Vector3.zero, Vector3.one * 0.085f, flame[1], ShapeBuilder.Glow);
                }
                break;
            }
        }
    }

    static Transform Pivot(string name, Transform parent, Vector3 localPos)
    {
        Transform t = new GameObject(name).transform;
        t.SetParent(parent, false);
        t.localPosition = localPos;
        return t;
    }
}
