using System.Collections.Generic;
using UnityEngine;

// Builds every game "prefab" from code: road pieces (chunks), the checkpoint, fences, coins, apples,
// falling obstacles and the heroes. The guide used imported assets (the King model, GDTV prefabs);
// here they are replaced with templates made of simple shapes, so the project needs no third-party files.
//
// The templates lie under an INACTIVE object, so their scripts do not run.
// Instantiate(template, parent) makes an active copy - exactly like a prefab.
// Any field you fill in GameAssets by hand (your own prefab) is kept: only empty fields are filled.
public static class ProceduralAssets
{
    static readonly Color Road = new Color(0.27f, 0.26f, 0.31f);
    static readonly Color Line = new Color(0.92f, 0.90f, 0.82f);
    static readonly Color Curb = new Color(0.80f, 0.78f, 0.74f);
    static readonly Color Grass = new Color(0.27f, 0.50f, 0.30f);
    static readonly Color GrassDark = new Color(0.20f, 0.40f, 0.24f);
    static readonly Color Wood = new Color(0.52f, 0.32f, 0.16f);
    static readonly Color WoodLight = new Color(0.74f, 0.54f, 0.31f);
    static readonly Color WoodDark = new Color(0.33f, 0.20f, 0.10f);
    static readonly Color Iron = new Color(0.20f, 0.20f, 0.23f);
    static readonly Color Stone = new Color(0.52f, 0.52f, 0.55f);
    static readonly Color Gold = new Color(1f, 0.78f, 0.22f);
    static readonly Color FenceRed = new Color(0.82f, 0.20f, 0.18f);
    static readonly Color Leaves = new Color(0.22f, 0.48f, 0.26f);
    static readonly Color LampLight = new Color(1f, 0.85f, 0.5f);

    const float ChunkLength = 10f;
    const float RoadWidth = 9f;

    public static void Fill(GameAssets a, Transform templates)
    {
        GameObject fence = BuildFence(templates);
        GameObject coin = BuildCoin(templates);
        GameObject apple = BuildApple(templates);

        if (a.kingPrefab == null)
        {
            // one model per hero (index = number in CharacterCatalog)
            GameObject[] heroes = new GameObject[CharacterCatalog.Count];
            for (int i = 0; i < heroes.Length; i++) heroes[i] = CharacterRig.Build(i, templates);
            a.kingPrefab = heroes[0];
            if (IsEmpty(a.characterModels)) a.characterModels = heroes;
        }

        if (IsEmpty(a.chunkPrefabs))
        {
            // as in the guide: three plain pieces and three with lampposts
            a.chunkPrefabs = new[]
            {
                BuildChunk("Chunk Plain A", templates, fence, apple, coin, false, false, 11),
                BuildChunk("Chunk Plain B", templates, fence, apple, coin, false, false, 23),
                BuildChunk("Chunk Plain C", templates, fence, apple, coin, false, false, 37),
                BuildChunk("Chunk Lightpost Both", templates, fence, apple, coin, true, true, 41),
                BuildChunk("Chunk Lightpost Left", templates, fence, apple, coin, true, false, 53),
                BuildChunk("Chunk Lightpost Right", templates, fence, apple, coin, false, true, 67),
            };
        }

        if (a.checkpointChunkPrefab == null)
        {
            GameObject cp = BuildChunk("Checkpoint Chunk", templates, fence, apple, coin, true, true, 79);
            AddCheckpointArch(cp.transform);
            a.checkpointChunkPrefab = cp;
        }

        if (IsEmpty(a.obstaclePrefabs))
        {
            a.obstaclePrefabs = new[]
            {
                BuildBarrel(templates), BuildBench(templates), BuildBox(templates),
                BuildCannon(templates), BuildCart(templates), BuildRock(templates),
            };
        }
    }

    public static bool IsEmpty(GameObject[] arr)
    {
        if (arr == null) return true;
        foreach (GameObject g in arr) if (g != null) return false;
        return true;
    }

    // ------------------------------------------------------------------
    //  Road
    // ------------------------------------------------------------------

    static GameObject BuildChunk(string name, Transform parent, GameObject fence, GameObject apple, GameObject coin,
                                 bool lampLeft, bool lampRight, int seed)
    {
        GameObject root = new GameObject(name);
        root.transform.SetParent(parent, false);
        Transform t = root.transform;

        // the floor: top surface at y = 0, the piece "grows" forward from z = 0 to z = 10
        MatLib.Prim(PrimitiveType.Cube, "Floor", t, new Vector3(0f, -0.1f, ChunkLength * 0.5f), new Vector3(RoadWidth, 0.2f, ChunkLength), Road, true);

        // curbs keep rolling obstacles on the road
        float curbX = RoadWidth * 0.5f + 0.18f;
        MatLib.Prim(PrimitiveType.Cube, "Curb L", t, new Vector3(-curbX, 0.06f, ChunkLength * 0.5f), new Vector3(0.36f, 0.32f, ChunkLength), Curb, true);
        MatLib.Prim(PrimitiveType.Cube, "Curb R", t, new Vector3(curbX, 0.06f, ChunkLength * 0.5f), new Vector3(0.36f, 0.32f, ChunkLength), Curb, true);

        // dashed lines between the lanes (lanes are at x = -2.5, 0, 2.5)
        foreach (float x in new[] { -1.25f, 1.25f })
            for (int i = 0; i < 2; i++)
                MatLib.Prim(PrimitiveType.Cube, "Lane Line", t, new Vector3(x, 0.005f, 2.5f + i * 5f), new Vector3(0.1f, 0.02f, 2.4f), Line);

        // grass on both sides
        float grassX = RoadWidth * 0.5f + 0.36f + 11f;
        MatLib.Prim(PrimitiveType.Cube, "Grass L", t, new Vector3(-grassX, -0.12f, ChunkLength * 0.5f), new Vector3(22f, 0.2f, ChunkLength), Grass);
        MatLib.Prim(PrimitiveType.Cube, "Grass R", t, new Vector3(grassX, -0.12f, ChunkLength * 0.5f), new Vector3(22f, 0.2f, ChunkLength), Grass);

        if (lampLeft) AddLamp(t, -1f);
        if (lampRight) AddLamp(t, 1f);

        // a little decoration (trees, bushes) - each template has its own layout
        System.Random rnd = new System.Random(seed);
        for (int side = -1; side <= 1; side += 2)
        {
            int count = 1 + rnd.Next(2);
            for (int i = 0; i < count; i++)
            {
                float x = side * (7.5f + (float)rnd.NextDouble() * 9f);
                float z = 1f + (float)rnd.NextDouble() * 8f;
                if (rnd.Next(3) == 0) AddBush(t, new Vector3(x, 0f, z), (float)rnd.NextDouble());
                else AddTree(t, new Vector3(x, 0f, z), (float)rnd.NextDouble());
            }
        }

        Chunk chunk = root.AddComponent<Chunk>();
        chunk.Configure(fence, apple, coin);
        return root;
    }

    static void AddLamp(Transform chunk, float side)
    {
        float x = side * (RoadWidth * 0.5f + 1.0f);
        Transform lamp = new GameObject("Lightpost").transform;
        lamp.SetParent(chunk, false);
        lamp.localPosition = new Vector3(x, 0f, ChunkLength * 0.5f);
        MatLib.Prim(PrimitiveType.Cylinder, "Pole", lamp, new Vector3(0f, 1.6f, 0f), new Vector3(0.14f, 1.6f, 0.14f), Iron, false, default(Vector3), 0.5f);
        MatLib.Prim(PrimitiveType.Cube, "Arm", lamp, new Vector3(-side * 0.35f, 3.15f, 0f), new Vector3(0.75f, 0.07f, 0.07f), Iron, false, default(Vector3), 0.5f);
        MatLib.Prim(PrimitiveType.Sphere, "Lamp", lamp, new Vector3(-side * 0.7f, 3.0f, 0f), Vector3.one * 0.34f, LampLight, false, default(Vector3), 0.6f, 1.6f);
    }

    static void AddTree(Transform chunk, Vector3 pos, float v)
    {
        Transform tree = new GameObject("Tree").transform;
        tree.SetParent(chunk, false);
        tree.localPosition = pos;
        float s = 0.85f + v * 0.5f;
        tree.localScale = Vector3.one * s;
        MatLib.Prim(PrimitiveType.Cylinder, "Trunk", tree, new Vector3(0f, 0.7f, 0f), new Vector3(0.3f, 0.7f, 0.3f), WoodDark);
        Color leaf = Color.Lerp(Leaves, GrassDark, v);
        MatLib.Prim(PrimitiveType.Sphere, "Crown", tree, new Vector3(0f, 2.0f, 0f), new Vector3(1.7f, 1.5f, 1.7f), leaf);
        MatLib.Prim(PrimitiveType.Sphere, "Crown Top", tree, new Vector3(0.15f, 2.7f, -0.1f), new Vector3(1.1f, 1.0f, 1.1f), leaf);
    }

    static void AddBush(Transform chunk, Vector3 pos, float v)
    {
        MatLib.Prim(PrimitiveType.Sphere, "Bush", chunk, pos + Vector3.up * 0.3f, new Vector3(1.3f, 0.8f, 1.1f) * (0.8f + v * 0.5f), GrassDark);
    }

    // The arch over the road and the invisible trigger that adds time (the Checkpoint script).
    static void AddCheckpointArch(Transform chunk)
    {
        const float z = 2f;
        float px = RoadWidth * 0.5f + 0.3f;
        MatLib.Prim(PrimitiveType.Cube, "Pillar L", chunk, new Vector3(-px, 2.1f, z), new Vector3(0.6f, 4.2f, 0.6f), Gold, false, default(Vector3), 0.6f, 0.1f);
        MatLib.Prim(PrimitiveType.Cube, "Pillar R", chunk, new Vector3(px, 2.1f, z), new Vector3(0.6f, 4.2f, 0.6f), Gold, false, default(Vector3), 0.6f, 0.1f);
        MatLib.Prim(PrimitiveType.Cube, "Beam", chunk, new Vector3(0f, 4.45f, z), new Vector3(px * 2f + 0.8f, 0.6f, 0.6f), Gold, false, default(Vector3), 0.6f, 0.1f);

        // a chequered finish banner
        for (int i = 0; i < 10; i++)
        {
            for (int row = 0; row < 2; row++)
            {
                bool dark = (i + row) % 2 == 0;
                MatLib.Prim(PrimitiveType.Cube, "Banner", chunk,
                    new Vector3(-2.7f + i * 0.6f, 3.65f + row * 0.4f, z), new Vector3(0.6f, 0.4f, 0.08f),
                    dark ? new Color(0.1f, 0.08f, 0.14f) : Color.white);
            }
        }
        MatLib.Prim(PrimitiveType.Cube, "Flag L", chunk, new Vector3(-px, 4.95f, z), new Vector3(0.08f, 0.6f, 0.5f), FenceRed, false, new Vector3(0f, 0f, 10f));
        MatLib.Prim(PrimitiveType.Cube, "Flag R", chunk, new Vector3(px, 4.95f, z), new Vector3(0.08f, 0.6f, 0.5f), FenceRed, false, new Vector3(0f, 0f, -10f));

        GameObject trigger = new GameObject("Checkpoint Trigger");
        trigger.transform.SetParent(chunk, false);
        trigger.transform.localPosition = new Vector3(0f, 1.5f, z);
        BoxCollider box = trigger.AddComponent<BoxCollider>();
        box.size = new Vector3(8f, 3f, 0.4f);
        box.isTrigger = true;
        trigger.AddComponent<Checkpoint>();
    }

    // ------------------------------------------------------------------
    //  Things on the road
    // ------------------------------------------------------------------

    static GameObject BuildFence(Transform parent)
    {
        GameObject root = new GameObject("Fence");
        root.transform.SetParent(parent, false);
        BoxCollider box = root.AddComponent<BoxCollider>();
        box.center = new Vector3(0f, 0.5f, 0f);
        box.size = new Vector3(2.0f, 1.0f, 0.3f);
        root.AddComponent<Hazard>();

        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Cube, "Post L", t, new Vector3(-0.9f, 0.55f, 0f), new Vector3(0.14f, 1.1f, 0.2f), WoodDark);
        MatLib.Prim(PrimitiveType.Cube, "Post R", t, new Vector3(0.9f, 0.55f, 0f), new Vector3(0.14f, 1.1f, 0.2f), WoodDark);
        for (int i = 0; i < 5; i++)
        {
            Color c = i % 2 == 0 ? FenceRed : Color.white;
            MatLib.Prim(PrimitiveType.Cube, "Plank", t, new Vector3(-0.72f + i * 0.36f, 0.78f, 0.02f), new Vector3(0.36f, 0.26f, 0.1f), c);
        }
        MatLib.Prim(PrimitiveType.Cube, "Rail", t, new Vector3(0f, 0.38f, 0.02f), new Vector3(1.8f, 0.1f, 0.08f), WoodDark);
        return root;
    }

    static GameObject BuildCoin(Transform parent)
    {
        GameObject root = new GameObject("Coin Pickup");
        root.transform.SetParent(parent, false);
        SphereCollider sc = root.AddComponent<SphereCollider>();
        sc.center = new Vector3(0f, 1f, 0f);
        sc.radius = 0.45f;
        sc.isTrigger = true;
        root.AddComponent<Coin>();

        MatLib.Prim(PrimitiveType.Cylinder, "Disc", root.transform, new Vector3(0f, 1f, 0f), new Vector3(0.62f, 0.05f, 0.62f), Gold, false, new Vector3(90f, 0f, 0f), 0.85f, 0.35f);
        MatLib.Prim(PrimitiveType.Cylinder, "Inner", root.transform, new Vector3(0f, 1f, 0f), new Vector3(0.42f, 0.06f, 0.42f), new Color(1f, 0.9f, 0.4f), false, new Vector3(90f, 0f, 0f), 0.85f, 0.35f);
        return root;
    }

    static GameObject BuildApple(Transform parent)
    {
        GameObject root = new GameObject("Apple Pickup");
        root.transform.SetParent(parent, false);
        SphereCollider sc = root.AddComponent<SphereCollider>();
        sc.center = new Vector3(0f, 0.9f, 0f);
        sc.radius = 0.5f;
        sc.isTrigger = true;
        root.AddComponent<Apple>();

        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Sphere, "Apple", t, new Vector3(0f, 0.9f, 0f), new Vector3(0.55f, 0.5f, 0.55f), new Color(0.88f, 0.12f, 0.12f), false, default(Vector3), 0.7f, 0.15f);
        MatLib.Prim(PrimitiveType.Cylinder, "Stem", t, new Vector3(0f, 1.18f, 0f), new Vector3(0.04f, 0.07f, 0.04f), WoodDark);
        MatLib.Prim(PrimitiveType.Cube, "Leaf", t, new Vector3(0.08f, 1.2f, 0f), new Vector3(0.16f, 0.02f, 0.08f), new Color(0.3f, 0.75f, 0.25f), false, new Vector3(0f, 0f, 25f));
        return root;
    }

    // ------------------------------------------------------------------
    //  Falling obstacles: Barrel, Bench, Box, Cannon, Cart, Rock
    // ------------------------------------------------------------------

    static GameObject ObstacleRoot(string name, Transform parent, float mass)
    {
        GameObject root = new GameObject(name);
        root.transform.SetParent(parent, false);
        Rigidbody rb = root.AddComponent<Rigidbody>();
        rb.mass = mass;
        rb.interpolation = RigidbodyInterpolation.Interpolate;
        rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
        root.AddComponent<Hazard>();

        AudioSource src = root.AddComponent<AudioSource>();
        src.playOnAwake = false;
        src.spatialBlend = 0f;
        src.volume = 0.18f;
        src.clip = SynthAudio.Thud;

        Rock rock = root.AddComponent<Rock>();
        rock.Configure(null, src);
        return root;
    }

    static GameObject BuildBarrel(Transform parent)
    {
        GameObject root = ObstacleRoot("Barrel", parent, 1.5f);
        CapsuleCollider c = root.AddComponent<CapsuleCollider>();
        c.radius = 0.46f; c.height = 1.15f; c.direction = 1;
        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Cylinder, "Body", t, Vector3.zero, new Vector3(0.9f, 0.56f, 0.9f), Wood);
        MatLib.Prim(PrimitiveType.Cylinder, "Band Top", t, new Vector3(0f, 0.36f, 0f), new Vector3(0.94f, 0.04f, 0.94f), Iron, false, default(Vector3), 0.5f);
        MatLib.Prim(PrimitiveType.Cylinder, "Band Bottom", t, new Vector3(0f, -0.36f, 0f), new Vector3(0.94f, 0.04f, 0.94f), Iron, false, default(Vector3), 0.5f);
        return root;
    }

    static GameObject BuildBench(Transform parent)
    {
        GameObject root = ObstacleRoot("Bench", parent, 1.2f);
        BoxCollider c = root.AddComponent<BoxCollider>();
        c.size = new Vector3(1.6f, 0.75f, 0.55f);
        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Cube, "Seat", t, new Vector3(0f, 0.03f, 0.03f), new Vector3(1.6f, 0.1f, 0.48f), WoodLight);
        MatLib.Prim(PrimitiveType.Cube, "Back", t, new Vector3(0f, 0.27f, -0.22f), new Vector3(1.6f, 0.36f, 0.08f), WoodLight);
        for (int i = 0; i < 4; i++)
        {
            float x = i < 2 ? -0.68f : 0.68f;
            float z = i % 2 == 0 ? -0.16f : 0.2f;
            MatLib.Prim(PrimitiveType.Cube, "Leg", t, new Vector3(x, -0.18f, z), new Vector3(0.08f, 0.36f, 0.08f), Iron);
        }
        return root;
    }

    static GameObject BuildBox(Transform parent)
    {
        GameObject root = ObstacleRoot("Box", parent, 1.3f);
        BoxCollider c = root.AddComponent<BoxCollider>();
        c.size = Vector3.one * 1.05f;
        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Cube, "Crate", t, Vector3.zero, Vector3.one * 1.0f, WoodLight);
        MatLib.Prim(PrimitiveType.Cube, "Strap 1", t, new Vector3(0f, 0.38f, 0f), new Vector3(1.04f, 0.14f, 1.04f), Wood);
        MatLib.Prim(PrimitiveType.Cube, "Strap 2", t, new Vector3(0f, -0.38f, 0f), new Vector3(1.04f, 0.14f, 1.04f), Wood);
        MatLib.Prim(PrimitiveType.Cube, "Strap 3", t, Vector3.zero, new Vector3(0.14f, 1.04f, 1.04f), Wood);
        return root;
    }

    static GameObject BuildCannon(Transform parent)
    {
        GameObject root = ObstacleRoot("Cannon", parent, 2.5f);
        CapsuleCollider c = root.AddComponent<CapsuleCollider>();
        c.radius = 0.38f; c.height = 1.7f; c.direction = 2;
        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Cylinder, "Barrel", t, Vector3.zero, new Vector3(0.5f, 0.8f, 0.5f), Iron, false, new Vector3(90f, 0f, 0f), 0.6f);
        MatLib.Prim(PrimitiveType.Cylinder, "Muzzle", t, new Vector3(0f, 0f, 0.78f), new Vector3(0.6f, 0.05f, 0.6f), Iron, false, new Vector3(90f, 0f, 0f), 0.6f);
        MatLib.Prim(PrimitiveType.Sphere, "Breech", t, new Vector3(0f, 0f, -0.8f), Vector3.one * 0.5f, Iron, false, default(Vector3), 0.6f);
        MatLib.Prim(PrimitiveType.Cylinder, "Wheel L", t, new Vector3(-0.36f, -0.18f, -0.25f), new Vector3(0.75f, 0.06f, 0.75f), Wood, false, new Vector3(0f, 0f, 90f));
        MatLib.Prim(PrimitiveType.Cylinder, "Wheel R", t, new Vector3(0.36f, -0.18f, -0.25f), new Vector3(0.75f, 0.06f, 0.75f), Wood, false, new Vector3(0f, 0f, 90f));
        return root;
    }

    static GameObject BuildCart(Transform parent)
    {
        GameObject root = ObstacleRoot("Cart", parent, 2f);
        BoxCollider c = root.AddComponent<BoxCollider>();
        c.size = new Vector3(1.3f, 0.95f, 1.6f);
        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Cube, "Bed", t, new Vector3(0f, 0.08f, 0f), new Vector3(1.1f, 0.45f, 1.5f), Wood);
        MatLib.Prim(PrimitiveType.Cube, "Rim", t, new Vector3(0f, 0.32f, 0f), new Vector3(1.14f, 0.06f, 1.54f), WoodDark);
        MatLib.Prim(PrimitiveType.Sphere, "Hay", t, new Vector3(0f, 0.32f, 0f), new Vector3(0.9f, 0.35f, 1.2f), new Color(0.93f, 0.8f, 0.35f));
        for (int i = 0; i < 4; i++)
        {
            float x = i < 2 ? -0.6f : 0.6f;
            float z = i % 2 == 0 ? -0.5f : 0.5f;
            MatLib.Prim(PrimitiveType.Cylinder, "Wheel", t, new Vector3(x, -0.25f, z), new Vector3(0.55f, 0.05f, 0.55f), Iron, false, new Vector3(0f, 0f, 90f));
        }
        return root;
    }

    static GameObject BuildRock(Transform parent)
    {
        GameObject root = ObstacleRoot("Rock", parent, 3f);
        SphereCollider c = root.AddComponent<SphereCollider>();
        c.radius = 0.58f;
        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Sphere, "Stone", t, Vector3.zero, new Vector3(1.25f, 1.0f, 1.1f), Stone, false, new Vector3(10f, 20f, 0f));
        MatLib.Prim(PrimitiveType.Sphere, "Bump", t, new Vector3(0.25f, 0.25f, 0.1f), new Vector3(0.6f, 0.5f, 0.6f), new Color(0.45f, 0.45f, 0.48f));
        return root;
    }
}
