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
            clothes[i].sharedMaterial = MatLib.Get(new Color(Mathf.Clamp01(main.r * k), Mathf.Clamp01(main.g * k), Mathf.Clamp01(main.b * k)));
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
            hipLx = -42f * s;                 hipRx = 42f * s;
            kneeLx = 8f + 75f * Mathf.Max(0f, c); kneeRx = 8f + 75f * Mathf.Max(0f, -c);
            shLx = 40f * s;                   shRx = -40f * s;
            shLz = -8f; shRz = 8f;
            elLx = -80f + 10f * s;            elRx = -80f - 10f * s;
            bodyX = 10f + Mathf.Clamp(runSpeed - 1f, 0f, 1f) * 6f;
            bodyY = 7f * s + lateral * 10f;
            bodyZ = -lateral * 13f;
            headX = -7f; headY = -5f * s;
            float flutter = Mathf.Sin(time * 13f);
            capeA = 25f + 12f * runSpeed + 6f * flutter;
            capeB = 12f + 9f * Mathf.Sin(time * 13f + 1.2f);
            bob = 0.05f * Mathf.Abs(c);
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
        float wantOpen = (hitTimer > 0f || cheering || airborne) ? 1f : (defeated ? 0.5f : 0f);
        mouthOpen = Mathf.Lerp(mouthOpen, wantOpen, 1f - Mathf.Exp(-12f * dt));
        if (mouth != null)
            mouth.localScale = new Vector3(mouthBase.x * (1f - 0.3f * mouthOpen), mouthBase.y * (1f + 3.5f * mouthOpen), mouthBase.z);

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
    //  Building the model
    // ======================================================================

    class Builder
    {
        public readonly List<Renderer> clothes = new List<Renderer>();
        public readonly List<float> shade = new List<float>();
        public readonly List<Transform> eyes = new List<Transform>();
        public readonly List<Transform> flickers = new List<Transform>();

        public GameObject Cloth(GameObject go, float k)
        {
            clothes.Add(go.GetComponent<Renderer>());
            shade.Add(k);
            return go;
        }
    }

    static GameObject P(PrimitiveType t, string n, Transform parent, Vector3 pos, Vector3 scale, Color c,
                        Vector3 euler = default(Vector3), float smooth = 0.15f, float emission = 0f)
    {
        return MatLib.Prim(t, n, parent, pos, scale, c, false, euler, smooth, emission);
    }

    public static GameObject Build(int style, Transform parent)
    {
        style = Mathf.Clamp(style, 0, DefaultMain.Length - 1);
        Color main = DefaultMain[style];
        Color hair = HairColor[style];
        Builder b = new Builder();

        GameObject root = new GameObject("Hero " + style);
        root.transform.SetParent(parent, false);
        CharacterRig rig = root.AddComponent<CharacterRig>();
        rig.defaultColor = main;

        rig.visual = Pivot("Visual", root.transform, Vector3.zero);

        // ---- legs: hip -> thigh -> knee -> shin -> boot ----
        rig.hipL = Pivot("Hip L", rig.visual, new Vector3(-0.11f, 0.8f, 0f));
        rig.hipR = Pivot("Hip R", rig.visual, new Vector3(0.11f, 0.8f, 0f));
        rig.kneeL = BuildLeg(rig.hipL);
        rig.kneeR = BuildLeg(rig.hipR);

        // ---- body (pivot at the hips) ----
        rig.body = Pivot("Body", rig.visual, new Vector3(0f, 0.8f, 0f));
        Transform bd = rig.body;
        P(PrimitiveType.Cube, "Pelvis", bd, new Vector3(0f, 0.02f, 0f), new Vector3(0.36f, 0.16f, 0.24f), Pants);
        b.Cloth(P(PrimitiveType.Capsule, "Torso", bd, new Vector3(0f, 0.31f, 0f), new Vector3(0.46f, 0.3f, 0.3f), main), 1f);
        P(PrimitiveType.Cylinder, "Belt", bd, new Vector3(0f, 0.1f, 0f), new Vector3(0.44f, 0.035f, 0.3f), style == 0 ? Gold : Wood, default(Vector3), 0.5f);
        P(PrimitiveType.Cube, "Buckle", bd, new Vector3(0f, 0.1f, 0.15f), new Vector3(0.07f, 0.06f, 0.02f), Gold, default(Vector3), 0.8f, 0.2f);
        P(PrimitiveType.Cylinder, "Neck", bd, new Vector3(0f, 0.6f, 0f), new Vector3(0.12f, 0.05f, 0.12f), Skin);

        // ---- cape (two parts so it can wave) ----
        rig.capeTop = Pivot("Cape", bd, new Vector3(0f, 0.56f, -0.15f));
        b.Cloth(P(PrimitiveType.Cube, "Cape Top", rig.capeTop, new Vector3(0f, -0.16f, 0f), new Vector3(0.44f, 0.33f, 0.03f), main), 0.6f);
        rig.capeBottom = Pivot("Cape Low", rig.capeTop, new Vector3(0f, -0.32f, 0f));
        b.Cloth(P(PrimitiveType.Cube, "Cape Bottom", rig.capeBottom, new Vector3(0f, -0.15f, 0f), new Vector3(0.47f, 0.3f, 0.03f), main), 0.55f);

        // ---- arms: shoulder -> upper arm -> elbow -> forearm -> hand ----
        rig.shoulderL = Pivot("Shoulder L", bd, new Vector3(-0.27f, 0.49f, 0f));
        rig.shoulderR = Pivot("Shoulder R", bd, new Vector3(0.27f, 0.49f, 0f));
        rig.elbowL = BuildArm(rig.shoulderL, main, b);
        rig.elbowR = BuildArm(rig.shoulderR, main, b);

        // ---- head ----
        rig.head = Pivot("Head", bd, new Vector3(0f, 0.62f, 0f));
        Transform h = rig.head;
        P(PrimitiveType.Sphere, "Face", h, new Vector3(0f, 0.18f, 0f), Vector3.one * 0.36f, Skin);
        P(PrimitiveType.Sphere, "Ear L", h, new Vector3(-0.175f, 0.18f, 0f), new Vector3(0.05f, 0.09f, 0.06f), Skin);
        P(PrimitiveType.Sphere, "Ear R", h, new Vector3(0.175f, 0.18f, 0f), new Vector3(0.05f, 0.09f, 0.06f), Skin);
        P(PrimitiveType.Sphere, "Nose", h, new Vector3(0f, 0.16f, 0.18f), new Vector3(0.06f, 0.07f, 0.07f), new Color(0.93f, 0.7f, 0.56f));
        for (int i = -1; i <= 1; i += 2)
        {
            Transform eye = P(PrimitiveType.Sphere, "Eye", h, new Vector3(i * 0.068f, 0.215f, 0.148f), Vector3.one * 0.075f, White, default(Vector3), 0.6f).transform;
            P(PrimitiveType.Sphere, "Pupil", eye, new Vector3(0f, 0f, 0.38f), Vector3.one * 0.55f, Dark, default(Vector3), 0.8f);
            b.eyes.Add(eye);
            P(PrimitiveType.Cube, "Brow", h, new Vector3(i * 0.07f, 0.268f, 0.163f), new Vector3(0.075f, 0.016f, 0.02f), hair, new Vector3(0f, 0f, -i * 8f));
        }
        rig.mouth = P(PrimitiveType.Cube, "Mouth", h, new Vector3(0f, 0.095f, 0.165f), new Vector3(0.075f, 0.016f, 0.02f), Lips).transform;
        P(PrimitiveType.Sphere, "Cheek L", h, new Vector3(-0.1f, 0.13f, 0.135f), new Vector3(0.06f, 0.035f, 0.03f), new Color(1f, 0.62f, 0.6f));
        P(PrimitiveType.Sphere, "Cheek R", h, new Vector3(0.1f, 0.13f, 0.135f), new Vector3(0.06f, 0.035f, 0.03f), new Color(1f, 0.62f, 0.6f));
        if (style != 1) P(PrimitiveType.Sphere, "Hair", h, new Vector3(0f, 0.26f, -0.04f), new Vector3(0.38f, 0.32f, 0.38f), hair);

        BuildOutfit(style, rig, b, main, hair);

        rig.eyes = b.eyes.ToArray();
        rig.flickers = b.flickers.ToArray();
        rig.clothes = b.clothes.ToArray();
        rig.clothShade = b.shade.ToArray();
        return root;
    }

    static Transform BuildLeg(Transform hip)
    {
        P(PrimitiveType.Capsule, "Thigh", hip, new Vector3(0f, -0.2f, 0f), new Vector3(0.17f, 0.21f, 0.17f), Pants);
        Transform knee = Pivot("Knee", hip, new Vector3(0f, -0.39f, 0f));
        P(PrimitiveType.Capsule, "Shin", knee, new Vector3(0f, -0.19f, 0f), new Vector3(0.15f, 0.2f, 0.15f), Pants);
        P(PrimitiveType.Cube, "Boot", knee, new Vector3(0f, -0.36f, 0.035f), new Vector3(0.16f, 0.1f, 0.25f), Boots);
        P(PrimitiveType.Sphere, "Toe", knee, new Vector3(0f, -0.365f, 0.15f), new Vector3(0.16f, 0.1f, 0.1f), Boots);
        P(PrimitiveType.Cylinder, "Cuff", knee, new Vector3(0f, -0.29f, 0f), new Vector3(0.18f, 0.025f, 0.18f), Boots);
        return knee;
    }

    static Transform BuildArm(Transform shoulder, Color main, Builder b)
    {
        b.Cloth(P(PrimitiveType.Sphere, "Shoulder", shoulder, Vector3.zero, Vector3.one * 0.17f, main), 0.9f);
        b.Cloth(P(PrimitiveType.Capsule, "Upper Arm", shoulder, new Vector3(0f, -0.13f, 0f), new Vector3(0.13f, 0.15f, 0.13f), main), 0.85f);
        Transform elbow = Pivot("Elbow", shoulder, new Vector3(0f, -0.27f, 0f));
        b.Cloth(P(PrimitiveType.Capsule, "Forearm", elbow, new Vector3(0f, -0.11f, 0f), new Vector3(0.12f, 0.13f, 0.12f), main), 0.75f);
        P(PrimitiveType.Sphere, "Hand", elbow, new Vector3(0f, -0.26f, 0f), new Vector3(0.11f, 0.12f, 0.11f), Skin);
        return elbow;
    }

    static void BuildOutfit(int style, CharacterRig rig, Builder b, Color main, Color hair)
    {
        Transform h = rig.head, bd = rig.body;
        switch (style)
        {
            case 0: // King: crown with gems, ermine collar, beard, sceptre
            {
                P(PrimitiveType.Cylinder, "Crown", h, new Vector3(0f, 0.37f, 0f), new Vector3(0.3f, 0.05f, 0.3f), Gold, default(Vector3), 0.85f, 0.25f);
                for (int i = 0; i < 5; i++)
                {
                    float a = i * Mathf.PI * 2f / 5f;
                    Vector3 p = new Vector3(Mathf.Sin(a) * 0.13f, 0.45f, Mathf.Cos(a) * 0.13f);
                    P(PrimitiveType.Cube, "Crown Tip", h, p, new Vector3(0.055f, 0.1f, 0.055f), Gold, new Vector3(0f, a * Mathf.Rad2Deg, 45f), 0.85f, 0.25f);
                    P(PrimitiveType.Sphere, "Pearl", h, p + Vector3.up * 0.06f, Vector3.one * 0.035f, White, default(Vector3), 0.9f);
                }
                P(PrimitiveType.Sphere, "Gem", h, new Vector3(0f, 0.375f, 0.152f), Vector3.one * 0.055f, new Color(0.9f, 0.1f, 0.2f), default(Vector3), 0.9f, 0.7f);
                P(PrimitiveType.Sphere, "Beard", h, new Vector3(0f, 0.06f, 0.12f), new Vector3(0.24f, 0.2f, 0.14f), hair);
                P(PrimitiveType.Sphere, "Moustache", h, new Vector3(0f, 0.12f, 0.17f), new Vector3(0.14f, 0.04f, 0.05f), hair);
                P(PrimitiveType.Cylinder, "Ermine", bd, new Vector3(0f, 0.55f, -0.02f), new Vector3(0.44f, 0.04f, 0.34f), White);
                for (int i = -1; i <= 1; i++)
                    P(PrimitiveType.Sphere, "Spot", bd, new Vector3(i * 0.12f, 0.56f, 0.14f), Vector3.one * 0.03f, Dark);
                Transform sceptre = Pivot("Sceptre", rig.elbowR, new Vector3(0f, -0.26f, 0.02f));
                P(PrimitiveType.Cylinder, "Rod", sceptre, new Vector3(0f, 0.02f, 0.12f), new Vector3(0.035f, 0.2f, 0.035f), Gold, new Vector3(80f, 0f, 0f), 0.85f, 0.2f);
                P(PrimitiveType.Sphere, "Orb", sceptre, new Vector3(0f, 0.05f, 0.33f), Vector3.one * 0.08f, new Color(0.85f, 0.15f, 0.25f), default(Vector3), 0.9f, 0.6f);
                break;
            }

            case 1: // Knight: helmet, visor, plume, breastplate, shield, sword
            {
                P(PrimitiveType.Sphere, "Helmet", h, new Vector3(0f, 0.2f, -0.005f), Vector3.one * 0.4f, Metal, default(Vector3), 0.8f);
                P(PrimitiveType.Cube, "Visor", h, new Vector3(0f, 0.215f, 0.188f), new Vector3(0.24f, 0.03f, 0.04f), Dark);
                P(PrimitiveType.Cube, "Nasal", h, new Vector3(0f, 0.17f, 0.195f), new Vector3(0.03f, 0.1f, 0.03f), Metal, default(Vector3), 0.8f);
                b.Cloth(P(PrimitiveType.Cube, "Plume", h, new Vector3(0f, 0.43f, -0.04f), new Vector3(0.05f, 0.14f, 0.3f), main, new Vector3(-12f, 0f, 0f)), 1.15f);
                P(PrimitiveType.Capsule, "Breastplate", bd, new Vector3(0f, 0.34f, 0.025f), new Vector3(0.44f, 0.22f, 0.3f), Metal, default(Vector3), 0.8f);
                P(PrimitiveType.Sphere, "Pauldron L", rig.shoulderL, new Vector3(0f, 0.02f, 0f), new Vector3(0.22f, 0.16f, 0.22f), Metal, default(Vector3), 0.8f);
                P(PrimitiveType.Sphere, "Pauldron R", rig.shoulderR, new Vector3(0f, 0.02f, 0f), new Vector3(0.22f, 0.16f, 0.22f), Metal, default(Vector3), 0.8f);
                Transform shield = Pivot("Shield", rig.elbowL, new Vector3(-0.08f, -0.12f, 0.02f));
                b.Cloth(P(PrimitiveType.Cylinder, "Shield", shield, Vector3.zero, new Vector3(0.38f, 0.02f, 0.44f), main, new Vector3(0f, 0f, 90f)), 1f);
                P(PrimitiveType.Cylinder, "Rim", shield, new Vector3(0.004f, 0f, 0f), new Vector3(0.4f, 0.015f, 0.46f), Metal, new Vector3(0f, 0f, 90f), 0.8f);
                P(PrimitiveType.Cube, "Emblem", shield, new Vector3(-0.025f, 0f, 0f), new Vector3(0.01f, 0.18f, 0.05f), Gold, default(Vector3), 0.8f, 0.2f);
                P(PrimitiveType.Cube, "Emblem 2", shield, new Vector3(-0.025f, 0.03f, 0f), new Vector3(0.01f, 0.05f, 0.16f), Gold, default(Vector3), 0.8f, 0.2f);
                Transform sword = Pivot("Sword", bd, new Vector3(0.1f, 0.35f, -0.2f));
                P(PrimitiveType.Cube, "Blade", sword, new Vector3(0f, 0.05f, 0f), new Vector3(0.05f, 0.6f, 0.015f), Metal, new Vector3(0f, 0f, 25f), 0.9f);
                P(PrimitiveType.Cube, "Guard", sword, new Vector3(0.12f, 0.31f, 0f), new Vector3(0.18f, 0.03f, 0.03f), Gold, new Vector3(0f, 0f, 25f), 0.8f);
                break;
            }

            case 2: // Ranger: hood, quiver with arrows, bow on the back
            {
                b.Cloth(P(PrimitiveType.Sphere, "Hood", h, new Vector3(0f, 0.23f, -0.05f), new Vector3(0.42f, 0.4f, 0.42f), main), 0.75f);
                b.Cloth(P(PrimitiveType.Cube, "Hood Tip", h, new Vector3(0f, 0.3f, -0.24f), new Vector3(0.1f, 0.1f, 0.12f), main, new Vector3(35f, 0f, 0f)), 0.75f);
                Transform quiver = Pivot("Quiver", bd, new Vector3(0.12f, 0.36f, -0.2f));
                P(PrimitiveType.Cylinder, "Tube", quiver, Vector3.zero, new Vector3(0.12f, 0.2f, 0.12f), Wood, new Vector3(-10f, 0f, -20f));
                for (int i = 0; i < 3; i++)
                {
                    Vector3 p = new Vector3(0.08f + (i - 1) * 0.03f, 0.25f, -0.04f);
                    P(PrimitiveType.Cube, "Arrow", quiver, p, new Vector3(0.012f, 0.22f, 0.012f), Wood, new Vector3(-10f, 0f, -20f));
                    P(PrimitiveType.Cube, "Fletching", quiver, p + new Vector3(0.04f, 0.1f, -0.02f), new Vector3(0.04f, 0.06f, 0.01f), White, new Vector3(-10f, 0f, -20f));
                }
                Transform bow = Pivot("Bow", bd, new Vector3(-0.05f, 0.3f, -0.2f));
                for (int i = -2; i <= 2; i++)
                {
                    float a = i * 18f;
                    Vector3 p = new Vector3(Mathf.Sin(a * Mathf.Deg2Rad) * 0.32f - 0.06f, Mathf.Cos(a * Mathf.Deg2Rad) * 0.32f - 0.32f, 0f);
                    P(PrimitiveType.Cube, "Limb", bow, Quaternion.Euler(0f, 0f, 40f) * p, new Vector3(0.03f, 0.12f, 0.03f), Wood, new Vector3(0f, 0f, 40f - a));
                }
                break;
            }

            case 3: // Alchemist: pointed hat with a star, long beard, glowing potion, belt bottles
            {
                b.Cloth(P(PrimitiveType.Cylinder, "Brim", h, new Vector3(0f, 0.34f, 0f), new Vector3(0.52f, 0.015f, 0.52f), main), 0.7f);
                float[] r = { 0.3f, 0.23f, 0.16f, 0.1f, 0.05f };
                for (int i = 0; i < r.Length; i++)
                    b.Cloth(P(PrimitiveType.Cylinder, "Hat", h, new Vector3(0f, 0.41f + i * 0.1f, -0.012f * i * i), new Vector3(r[i], 0.055f, r[i]), main, new Vector3(-4f * i, 0f, 0f)), 0.7f);
                P(PrimitiveType.Cylinder, "Hat Band", h, new Vector3(0f, 0.38f, 0f), new Vector3(0.31f, 0.02f, 0.31f), Gold, default(Vector3), 0.8f, 0.2f);
                Transform star = P(PrimitiveType.Sphere, "Star", h, new Vector3(0f, 0.92f, -0.22f), Vector3.one * 0.07f, Gold, default(Vector3), 0.8f, 1f).transform;
                b.flickers.Add(star);
                P(PrimitiveType.Sphere, "Beard", h, new Vector3(0f, 0.0f, 0.12f), new Vector3(0.24f, 0.36f, 0.14f), hair);
                P(PrimitiveType.Sphere, "Moustache", h, new Vector3(0f, 0.12f, 0.17f), new Vector3(0.16f, 0.045f, 0.05f), hair);
                Transform potion = P(PrimitiveType.Sphere, "Potion", rig.elbowR, new Vector3(0f, -0.33f, 0.04f), Vector3.one * 0.12f, new Color(0.3f, 1f, 0.5f), default(Vector3), 0.9f, 1.4f).transform;
                b.flickers.Add(potion);
                P(PrimitiveType.Cylinder, "Cork", rig.elbowR, new Vector3(0f, -0.25f, 0.04f), new Vector3(0.04f, 0.03f, 0.04f), Wood);
                Color[] bottles = { new Color(1f, 0.3f, 0.3f), new Color(0.3f, 0.6f, 1f), new Color(1f, 0.85f, 0.2f) };
                for (int i = 0; i < 3; i++)
                    P(PrimitiveType.Capsule, "Bottle", bd, new Vector3(-0.16f + i * 0.16f, 0.06f, 0.17f), new Vector3(0.06f, 0.05f, 0.06f), bottles[i], default(Vector3), 0.9f, 0.7f);
                break;
            }

            default: // Pyro: flaming hair, goggles, scarf, glowing fists
            {
                Color[] flame = { new Color(1f, 0.32f, 0.05f), new Color(1f, 0.58f, 0.1f), new Color(1f, 0.86f, 0.25f) };
                for (int i = 0; i < 7; i++)
                {
                    float x = (i - 3) * 0.055f;
                    Transform f = P(PrimitiveType.Cube, "Flame", h, new Vector3(x, 0.4f + (i % 2) * 0.04f, -0.03f - (i % 3) * 0.03f),
                        new Vector3(0.07f, 0.2f + (i % 3) * 0.06f, 0.14f), flame[i % 3], new Vector3(-15f, 0f, -x * 220f), 0.3f, 1.2f).transform;
                    b.flickers.Add(f);
                }
                P(PrimitiveType.Cylinder, "Goggle Strap", h, new Vector3(0f, 0.27f, 0f), new Vector3(0.375f, 0.02f, 0.375f), Dark);
                P(PrimitiveType.Sphere, "Lens L", h, new Vector3(-0.07f, 0.28f, 0.16f), new Vector3(0.09f, 0.08f, 0.05f), new Color(1f, 0.7f, 0.2f), default(Vector3), 0.95f, 0.5f);
                P(PrimitiveType.Sphere, "Lens R", h, new Vector3(0.07f, 0.28f, 0.16f), new Vector3(0.09f, 0.08f, 0.05f), new Color(1f, 0.7f, 0.2f), default(Vector3), 0.95f, 0.5f);
                b.Cloth(P(PrimitiveType.Cylinder, "Scarf", bd, new Vector3(0f, 0.58f, 0f), new Vector3(0.3f, 0.05f, 0.3f), main), 0.7f);
                b.Cloth(P(PrimitiveType.Cube, "Scarf End", rig.capeTop, new Vector3(0.12f, -0.05f, -0.03f), new Vector3(0.08f, 0.25f, 0.02f), main), 0.7f);
                Transform fl = P(PrimitiveType.Sphere, "Fire L", rig.elbowL, new Vector3(0f, -0.27f, 0f), Vector3.one * 0.15f, flame[1], default(Vector3), 0.3f, 1.4f).transform;
                Transform fr = P(PrimitiveType.Sphere, "Fire R", rig.elbowR, new Vector3(0f, -0.27f, 0f), Vector3.one * 0.15f, flame[1], default(Vector3), 0.3f, 1.4f).transform;
                b.flickers.Add(fl);
                b.flickers.Add(fr);
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
