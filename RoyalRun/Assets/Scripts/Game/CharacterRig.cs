using System.Collections.Generic;
using UnityEngine;

// A hero model built from simple shapes, with a procedural run / idle / hit animation.
// It replaces the imported King model: the project works without any third-party assets.
// Index (style): 0 King (crown), 1 Knight (helmet), 2 Ranger (hood), 3 Alchemist (pointed hat), 4 Pyro (flaming hair).
// The model faces +Z (the direction of running). Height is about 1.75 m.
public class CharacterRig : MonoBehaviour
{
    static readonly Color Skin = new Color(0.96f, 0.78f, 0.62f);
    static readonly Color Pants = new Color(0.20f, 0.18f, 0.26f);
    static readonly Color Boots = new Color(0.28f, 0.17f, 0.09f);
    static readonly Color Gold = new Color(1f, 0.78f, 0.22f);
    static readonly Color Metal = new Color(0.72f, 0.74f, 0.80f);
    static readonly Color Dark = new Color(0.08f, 0.06f, 0.10f);
    static readonly Color Wood = new Color(0.45f, 0.28f, 0.14f);

    // the main ("clothes") colour of each hero when no tint is given
    static readonly Color[] DefaultMain =
    {
        new Color(0.80f, 0.14f, 0.18f),   // King - royal red
        new Color(0.30f, 0.50f, 0.95f),   // Knight - blue
        new Color(0.30f, 0.62f, 0.28f),   // Ranger - green
        new Color(0.55f, 0.30f, 0.80f),   // Alchemist - purple
        new Color(0.95f, 0.45f, 0.15f),   // Pyro - orange
    };

    [SerializeField] Transform body, head, legL, legR, armL, armR;
    [SerializeField] Renderer[] clothes;      // tinted with the main colour
    [SerializeField] float[] clothShade;      // brightness of each tinted part (the cape is darker, etc.)
    [SerializeField] Color defaultColor = Color.white;

    // set by PlayerAvatar
    [System.NonSerialized] public bool running;
    [System.NonSerialized] public float runSpeed = 1f;

    float phase;
    float hitTimer;
    Vector3 bodyBase;
    bool baseKnown;

    public void PlayHit()
    {
        hitTimer = 0.45f;
    }

    public void ApplyTint(Color tint)
    {
        Color main = (tint == Color.white) ? defaultColor : tint;
        if (clothes == null) return;
        for (int i = 0; i < clothes.Length; i++)
        {
            if (clothes[i] == null) continue;
            float k = (clothShade != null && i < clothShade.Length) ? clothShade[i] : 1f;
            clothes[i].sharedMaterial = MatLib.Get(new Color(main.r * k, main.g * k, main.b * k));
        }
    }

    void Update()
    {
        if (body == null) return;
        if (!baseKnown) { bodyBase = body.localPosition; baseKnown = true; }

        float dt = Time.deltaTime;
        float t;

        if (running)
        {
            phase += dt * 10f * Mathf.Clamp(runSpeed, 0.6f, 2.2f);
            t = Mathf.Sin(phase);
            float swing = t * 42f;
            legL.localRotation = Quaternion.Euler(swing, 0f, 0f);
            legR.localRotation = Quaternion.Euler(-swing, 0f, 0f);
            armL.localRotation = Quaternion.Euler(-swing * 0.85f, 0f, 4f);
            armR.localRotation = Quaternion.Euler(swing * 0.85f, 0f, -4f);
            body.localPosition = bodyBase + Vector3.up * (Mathf.Abs(Mathf.Cos(phase)) * 0.06f);
            body.localRotation = Quaternion.Euler(9f, 0f, 0f);
        }
        else
        {
            phase += dt * 2.2f;
            t = Mathf.Sin(phase);
            legL.localRotation = Quaternion.identity;
            legR.localRotation = Quaternion.identity;
            armL.localRotation = Quaternion.Euler(t * 4f, 0f, 6f + t * 2f);
            armR.localRotation = Quaternion.Euler(-t * 4f, 0f, -6f - t * 2f);
            body.localPosition = bodyBase + Vector3.up * (t * 0.012f);
            body.localRotation = Quaternion.identity;
        }

        if (hitTimer > 0f)
        {
            hitTimer -= dt;
            float k = Mathf.Clamp01(hitTimer / 0.45f);
            body.localRotation = Quaternion.Euler(-28f * k, 0f, Mathf.Sin(hitTimer * 45f) * 8f * k);
            armL.localRotation = Quaternion.Euler(-120f * k, 0f, 25f * k);
            armR.localRotation = Quaternion.Euler(-120f * k, 0f, -25f * k);
        }

        if (head != null) head.localRotation = Quaternion.Euler(0f, Mathf.Sin(phase * 0.5f) * (running ? 3f : 8f), 0f);
    }

    // ======================================================================
    //  Building the model
    // ======================================================================

    public static GameObject Build(int style, Transform parent)
    {
        style = Mathf.Clamp(style, 0, DefaultMain.Length - 1);
        Color main = DefaultMain[style];

        GameObject root = new GameObject("Hero " + style);
        root.transform.SetParent(parent, false);
        CharacterRig rig = root.AddComponent<CharacterRig>();
        rig.defaultColor = main;

        List<Renderer> clothes = new List<Renderer>();
        List<float> shade = new List<float>();
        System.Action<GameObject, float> cloth = delegate (GameObject go, float k)
        {
            clothes.Add(go.GetComponent<Renderer>());
            shade.Add(k);
        };

        // legs (pivot at the hip)
        rig.legL = Pivot("Leg L", root.transform, new Vector3(-0.12f, 0.72f, 0f));
        rig.legR = Pivot("Leg R", root.transform, new Vector3(0.12f, 0.72f, 0f));
        foreach (Transform leg in new[] { rig.legL, rig.legR })
        {
            MatLib.Prim(PrimitiveType.Cube, "Thigh", leg, new Vector3(0f, -0.33f, 0f), new Vector3(0.17f, 0.62f, 0.2f), Pants);
            MatLib.Prim(PrimitiveType.Cube, "Boot", leg, new Vector3(0f, -0.66f, 0.04f), new Vector3(0.2f, 0.13f, 0.28f), Boots);
        }

        // body (pivot at the hip, everything above moves with it)
        rig.body = Pivot("Body", root.transform, new Vector3(0f, 0.72f, 0f));
        cloth(MatLib.Prim(PrimitiveType.Cube, "Torso", rig.body, new Vector3(0f, 0.31f, 0f), new Vector3(0.5f, 0.58f, 0.32f), main), 1f);
        MatLib.Prim(PrimitiveType.Cube, "Belt", rig.body, new Vector3(0f, 0.06f, 0f), new Vector3(0.52f, 0.08f, 0.34f), style == 0 ? Gold : Wood);
        cloth(MatLib.Prim(PrimitiveType.Cube, "Cape", rig.body, new Vector3(0f, 0.27f, -0.2f), new Vector3(0.48f, 0.6f, 0.04f), main, false, new Vector3(-6f, 0f, 0f)), 0.6f);

        // arms (pivot at the shoulder)
        rig.armL = Pivot("Arm L", rig.body, new Vector3(-0.32f, 0.55f, 0f));
        rig.armR = Pivot("Arm R", rig.body, new Vector3(0.32f, 0.55f, 0f));
        foreach (Transform arm in new[] { rig.armL, rig.armR })
        {
            cloth(MatLib.Prim(PrimitiveType.Cube, "Sleeve", arm, new Vector3(0f, -0.24f, 0f), new Vector3(0.14f, 0.5f, 0.15f), main), 0.85f);
            MatLib.Prim(PrimitiveType.Sphere, "Hand", arm, new Vector3(0f, -0.53f, 0f), Vector3.one * 0.13f, Skin);
        }

        // head (pivot at the neck)
        rig.head = Pivot("Head", rig.body, new Vector3(0f, 0.62f, 0f));
        MatLib.Prim(PrimitiveType.Sphere, "Face", rig.head, new Vector3(0f, 0.2f, 0f), Vector3.one * 0.38f, Skin);
        MatLib.Prim(PrimitiveType.Sphere, "Eye L", rig.head, new Vector3(-0.075f, 0.23f, 0.165f), Vector3.one * 0.06f, Dark);
        MatLib.Prim(PrimitiveType.Sphere, "Eye R", rig.head, new Vector3(0.075f, 0.23f, 0.165f), Vector3.one * 0.06f, Dark);

        switch (style)
        {
            case 0: // King: crown and a white beard
                MatLib.Prim(PrimitiveType.Cylinder, "Crown", rig.head, new Vector3(0f, 0.4f, 0f), new Vector3(0.31f, 0.05f, 0.31f), Gold, false, default(Vector3), 0.8f, 0.25f);
                for (int i = 0; i < 5; i++)
                {
                    float a = i * Mathf.PI * 2f / 5f;
                    MatLib.Prim(PrimitiveType.Cube, "Crown Tip", rig.head,
                        new Vector3(Mathf.Sin(a) * 0.13f, 0.49f, Mathf.Cos(a) * 0.13f), new Vector3(0.06f, 0.11f, 0.06f), Gold,
                        false, new Vector3(0f, a * Mathf.Rad2Deg, 45f), 0.8f, 0.25f);
                }
                MatLib.Prim(PrimitiveType.Sphere, "Gem", rig.head, new Vector3(0f, 0.41f, 0.155f), Vector3.one * 0.06f, new Color(0.9f, 0.1f, 0.2f), false, default(Vector3), 0.9f, 0.6f);
                MatLib.Prim(PrimitiveType.Cube, "Beard", rig.head, new Vector3(0f, 0.07f, 0.15f), new Vector3(0.24f, 0.16f, 0.08f), new Color(0.95f, 0.95f, 0.92f));
                break;

            case 1: // Knight: helmet, visor and a plume
                MatLib.Prim(PrimitiveType.Sphere, "Helmet", rig.head, new Vector3(0f, 0.22f, -0.01f), Vector3.one * 0.42f, Metal, false, default(Vector3), 0.75f);
                MatLib.Prim(PrimitiveType.Cube, "Visor", rig.head, new Vector3(0f, 0.23f, 0.19f), new Vector3(0.26f, 0.035f, 0.06f), Dark);
                cloth(MatLib.Prim(PrimitiveType.Cube, "Plume", rig.head, new Vector3(0f, 0.47f, -0.03f), new Vector3(0.05f, 0.16f, 0.3f), main), 1.1f);
                MatLib.Prim(PrimitiveType.Sphere, "Pad L", rig.armL, new Vector3(0f, 0.02f, 0f), Vector3.one * 0.22f, Metal, false, default(Vector3), 0.75f);
                MatLib.Prim(PrimitiveType.Sphere, "Pad R", rig.armR, new Vector3(0f, 0.02f, 0f), Vector3.one * 0.22f, Metal, false, default(Vector3), 0.75f);
                break;

            case 2: // Ranger: hood and a quiver with arrows
                cloth(MatLib.Prim(PrimitiveType.Sphere, "Hood", rig.head, new Vector3(0f, 0.25f, -0.07f), Vector3.one * 0.44f, main), 0.75f);
                GameObject quiver = MatLib.Prim(PrimitiveType.Cylinder, "Quiver", rig.body, new Vector3(0.12f, 0.38f, -0.24f), new Vector3(0.13f, 0.2f, 0.13f), Wood, false, new Vector3(0f, 0f, -20f));
                for (int i = 0; i < 3; i++)
                    MatLib.Prim(PrimitiveType.Cube, "Arrow", quiver.transform, new Vector3((i - 1) * 0.25f, 1.25f, 0f), new Vector3(0.12f, 0.6f, 0.12f), new Color(0.95f, 0.95f, 0.9f));
                break;

            case 3: // Alchemist: pointed hat, long beard, a glowing potion
                cloth(MatLib.Prim(PrimitiveType.Cylinder, "Brim", rig.head, new Vector3(0f, 0.37f, 0f), new Vector3(0.52f, 0.015f, 0.52f), main), 0.7f);
                cloth(MatLib.Prim(PrimitiveType.Cylinder, "Hat 1", rig.head, new Vector3(0f, 0.45f, 0f), new Vector3(0.3f, 0.07f, 0.3f), main), 0.7f);
                cloth(MatLib.Prim(PrimitiveType.Cylinder, "Hat 2", rig.head, new Vector3(0f, 0.58f, -0.01f), new Vector3(0.21f, 0.07f, 0.21f), main), 0.7f);
                cloth(MatLib.Prim(PrimitiveType.Cylinder, "Hat 3", rig.head, new Vector3(0f, 0.7f, -0.03f), new Vector3(0.12f, 0.06f, 0.12f), main), 0.7f);
                MatLib.Prim(PrimitiveType.Sphere, "Star", rig.head, new Vector3(0f, 0.8f, -0.05f), Vector3.one * 0.07f, Gold, false, default(Vector3), 0.8f, 0.6f);
                MatLib.Prim(PrimitiveType.Cube, "Beard", rig.head, new Vector3(0f, 0.0f, 0.15f), new Vector3(0.22f, 0.3f, 0.08f), new Color(0.82f, 0.82f, 0.86f));
                MatLib.Prim(PrimitiveType.Sphere, "Potion", rig.armR, new Vector3(0f, -0.62f, 0.06f), Vector3.one * 0.13f, new Color(0.3f, 1f, 0.5f), false, default(Vector3), 0.9f, 1.2f);
                break;

            default: // Pyro: flaming hair and a scarf
                Color[] flame = { new Color(1f, 0.35f, 0.05f), new Color(1f, 0.6f, 0.1f), new Color(1f, 0.85f, 0.2f) };
                for (int i = 0; i < 5; i++)
                {
                    float x = (i - 2) * 0.07f;
                    MatLib.Prim(PrimitiveType.Cube, "Flame", rig.head, new Vector3(x, 0.4f + (i % 2) * 0.05f, -0.02f),
                        new Vector3(0.08f, 0.2f + (i % 3) * 0.05f, 0.18f), flame[i % 3], false, new Vector3(0f, 0f, -x * 150f), 0.3f, 1.0f);
                }
                cloth(MatLib.Prim(PrimitiveType.Cube, "Scarf", rig.body, new Vector3(0f, 0.6f, 0.02f), new Vector3(0.36f, 0.08f, 0.36f), main), 0.7f);
                break;
        }

        rig.clothes = clothes.ToArray();
        rig.clothShade = shade.ToArray();
        return root;
    }

    static Transform Pivot(string name, Transform parent, Vector3 localPos)
    {
        Transform t = new GameObject(name).transform;
        t.SetParent(parent, false);
        t.localPosition = localPos;
        return t;
    }
}
