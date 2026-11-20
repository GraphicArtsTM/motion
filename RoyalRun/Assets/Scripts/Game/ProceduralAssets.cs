using UnityEngine;

// Builds every game "prefab" from code: road pieces (chunks), the checkpoint, fences and walls, coins, gems,
// apples, power-ups, falling obstacles and the heroes. The guide used imported assets (the King model, GDTV prefabs);
// here they are replaced with templates made of simple shapes, so the project needs no third-party files.
//
// The templates lie under an INACTIVE object, so their scripts do not run.
// Instantiate(template, parent) makes an active copy - exactly like a prefab.
// After building, each template is "baked" (MeshBaker): its small shapes are merged into a few meshes.
// Any field you fill in GameAssets by hand (your own prefab) is kept: only empty fields are filled.
public static class ProceduralAssets
{
    static readonly Color Road = new Color(0.88f, 0.86f, 0.84f);    // tints the cobblestone texture
    static readonly Color Line = new Color(0.95f, 0.88f, 0.60f);
    static readonly Color CurbRed = new Color(0.78f, 0.18f, 0.18f);
    static readonly Color CurbWhite = new Color(0.90f, 0.88f, 0.84f);
    static readonly Color GrassDark = new Color(0.21f, 0.42f, 0.24f);
    static readonly Color Wood = new Color(0.52f, 0.32f, 0.16f);
    static readonly Color WoodLight = new Color(0.74f, 0.54f, 0.31f);
    static readonly Color WoodDark = new Color(0.33f, 0.20f, 0.10f);
    static readonly Color Iron = new Color(0.20f, 0.20f, 0.23f);
    static readonly Color Stone = new Color(0.55f, 0.55f, 0.58f);
    static readonly Color StoneDark = new Color(0.42f, 0.41f, 0.46f);
    static readonly Color Gold = new Color(1f, 0.78f, 0.22f);
    static readonly Color FenceRed = new Color(0.82f, 0.20f, 0.18f);
    static readonly Color LampLight = new Color(1f, 0.85f, 0.5f);
    static readonly Color Royal = new Color(0.45f, 0.18f, 0.62f);
    static readonly Color RoofBlue = new Color(0.22f, 0.32f, 0.62f);

    const float ChunkLength = 10f;
    const float RoadWidth = 9f;

    // A zone of the road. Every checkpoint leads into the next zone: meadows -> autumn forest -> winter peaks.
    class Biome
    {
        public string name;
        public Color grass, grassDark, leaves, leaves2, pine, trunk, ground;
        public Color[] flowers;
        public bool snow, fallenLeaves;
    }

    static readonly Biome[] Biomes =
    {
        new Biome
        {
            name = "Meadow",
            grass = new Color(0.30f, 0.54f, 0.30f), grassDark = new Color(0.21f, 0.42f, 0.24f),
            leaves = new Color(0.24f, 0.52f, 0.27f), leaves2 = new Color(0.32f, 0.58f, 0.28f),
            pine = new Color(0.14f, 0.36f, 0.24f), trunk = new Color(0.33f, 0.20f, 0.10f), ground = new Color(0.36f, 0.30f, 0.22f),
            flowers = new[] { new Color(1f, 0.85f, 0.25f), new Color(0.95f, 0.35f, 0.45f), new Color(0.95f, 0.95f, 1f), new Color(0.6f, 0.45f, 1f) },
        },
        new Biome
        {
            name = "Autumn",
            grass = new Color(0.52f, 0.48f, 0.24f), grassDark = new Color(0.42f, 0.34f, 0.18f),
            leaves = new Color(0.90f, 0.45f, 0.12f), leaves2 = new Color(0.80f, 0.20f, 0.12f),
            pine = new Color(0.20f, 0.33f, 0.20f), trunk = new Color(0.30f, 0.18f, 0.09f), ground = new Color(0.40f, 0.28f, 0.16f),
            flowers = new[] { new Color(1f, 0.6f, 0.1f), new Color(0.85f, 0.2f, 0.12f), new Color(1f, 0.85f, 0.3f), new Color(0.6f, 0.3f, 0.15f) },
            fallenLeaves = true,
        },
        new Biome
        {
            name = "Winter",
            grass = new Color(0.86f, 0.89f, 0.95f), grassDark = new Color(0.74f, 0.79f, 0.88f),
            leaves = new Color(0.88f, 0.92f, 0.98f), leaves2 = new Color(0.78f, 0.85f, 0.95f),
            pine = new Color(0.12f, 0.30f, 0.24f), trunk = new Color(0.28f, 0.18f, 0.12f), ground = new Color(0.75f, 0.8f, 0.9f),
            flowers = new[] { new Color(0.6f, 0.85f, 1f), new Color(0.85f, 0.95f, 1f) },
            snow = true,
        },
    };

    static Biome B = Biomes[0];

    // Fewer decorations (phones): set by GameBootstrap before the templates are built.
    public static bool Lite;

    public static int BiomeCount { get { return Biomes.Length; } }

    struct ChunkStyle
    {
        public bool lampLeft, lampRight, rail, banners, castle;
        public int seed;
    }

    public static void Fill(GameAssets a, Transform templates)
    {
        GameObject fence = Bake(BuildFence(templates));
        GameObject wall = Bake(BuildWall(templates));
        GameObject coin = Bake(BuildCoin(templates, false));
        GameObject gem = Bake(BuildCoin(templates, true));
        GameObject apple = Bake(BuildApple(templates));
        GameObject[] powerUps =
        {
            Bake(BuildPowerUp(templates, PowerUpType.Shield)),
            Bake(BuildPowerUp(templates, PowerUpType.Magnet)),
            Bake(BuildPowerUp(templates, PowerUpType.Hourglass)),
        };
        GameObject mover = BuildMovingCart(templates);
        GameObject beam = Bake(BuildBeam(templates));

        if (a.kingPrefab == null)
        {
            // one model per hero (index = number in CharacterCatalog); heroes are animated, so they are not baked
            GameObject[] heroes = new GameObject[CharacterCatalog.Count];
            for (int i = 0; i < heroes.Length; i++) heroes[i] = CharacterRig.Build(i, templates);
            a.kingPrefab = heroes[0];
            if (IsEmpty(a.characterModels)) a.characterModels = heroes;
        }

        if (IsEmpty(a.chunkPrefabs))
        {
            // as in the guide: plain pieces and pieces with lampposts (plus fences, banners and castles in the distance)
            ChunkStyle[] styles =
            {
                new ChunkStyle { seed = 11 },
                new ChunkStyle { seed = 23, rail = true },
                new ChunkStyle { seed = 37, castle = true },
                new ChunkStyle { seed = 41, lampLeft = true, lampRight = true },
                new ChunkStyle { seed = 53, lampLeft = true, banners = true },
                new ChunkStyle { seed = 67, lampRight = true, rail = true, castle = true },
                new ChunkStyle { seed = 71, banners = true },
            };
            bool ownCheckpoint = a.checkpointChunkPrefab != null;
            a.biomeChunks = new GameObject[Biomes.Length][];
            a.biomeCheckpoints = new GameObject[Biomes.Length];
            a.biomeCorners = new GameObject[Biomes.Length][];
            for (int b = 0; b < Biomes.Length; b++)
            {
                B = Biomes[b];
                a.biomeChunks[b] = new GameObject[styles.Length];
                for (int i = 0; i < styles.Length; i++)
                {
                    ChunkStyle st = styles[i];
                    st.seed += b * 1000;
                    GameObject c = BuildChunk(B.name + " Chunk " + (i + 1), templates, st);
                    SetupChunk(c, fence, apple, coin, wall, gem, powerUps, mover);
                    c.GetComponent<Chunk>().ConfigureBeam(beam);
                    a.biomeChunks[b][i] = Bake(c);
                }
                // corners: the road turns left or right (swipe at the right moment!)
                a.biomeCorners[b] = new GameObject[2];
                for (int d = 0; d < 2; d++)
                {
                    int dir = d == 0 ? -1 : 1;
                    GameObject c = BuildChunk(B.name + (dir < 0 ? " Corner Left" : " Corner Right"), templates,
                                              new ChunkStyle { seed = 500 + b * 10 + d, banners = true }, dir);
                    AddCornerEnd(c.transform, dir);
                    SetupChunk(c, fence, apple, coin, wall, gem, powerUps, mover);
                    c.GetComponent<Chunk>().ConfigureCorner(dir);
                    a.biomeCorners[b][d] = Bake(c);
                }
                if (!ownCheckpoint)
                {
                    GameObject cp = BuildChunk(B.name + " Checkpoint", templates, new ChunkStyle { seed = 79 + b, lampLeft = true, lampRight = true, banners = true });
                    AddCheckpointArch(cp.transform);
                    SetupChunk(cp, fence, apple, coin, wall, gem, powerUps, mover);
                    cp.GetComponent<Chunk>().ConfigureBeam(beam);
                    a.biomeCheckpoints[b] = Bake(cp);
                }
            }
            B = Biomes[0];
            a.chunkPrefabs = a.biomeChunks[0];
            if (!ownCheckpoint) a.checkpointChunkPrefab = a.biomeCheckpoints[0];
            else a.biomeCheckpoints = null;
        }

        if (a.checkpointChunkPrefab == null)
        {
            GameObject cp = BuildChunk("Checkpoint Chunk", templates, new ChunkStyle { seed = 79, lampLeft = true, lampRight = true, banners = true });
            AddCheckpointArch(cp.transform);
            SetupChunk(cp, fence, apple, coin, wall, gem, powerUps, mover);
            a.checkpointChunkPrefab = Bake(cp);
        }

        if (IsEmpty(a.obstaclePrefabs))
        {
            a.obstaclePrefabs = new[]
            {
                Bake(BuildBarrel(templates)), Bake(BuildBench(templates)), Bake(BuildBox(templates)),
                Bake(BuildCannon(templates)), Bake(BuildCart(templates)), Bake(BuildRock(templates)),
            };
        }
    }

    static GameObject Bake(GameObject go)
    {
        MeshBaker.Bake(go);
        return go;
    }

    static void SetupChunk(GameObject c, GameObject fence, GameObject apple, GameObject coin,
                           GameObject wall, GameObject gem, GameObject[] powerUps, GameObject mover)
    {
        Chunk chunk = c.AddComponent<Chunk>();
        chunk.Configure(fence, apple, coin);
        chunk.ConfigureExtras(wall, gem, powerUps);
        chunk.ConfigureMover(mover);
    }

    public static bool IsEmpty(GameObject[] arr)
    {
        if (arr == null) return true;
        foreach (GameObject g in arr) if (g != null) return false;
        return true;
    }

    static GameObject Box(string n, Transform p, Vector3 pos, Vector3 scale, Color c, bool collider = false, Vector3 euler = default(Vector3), float smooth = 0.15f, float emission = 0f, Surface surf = Surface.Grime)
    {
        return MatLib.Prim(PrimitiveType.Cube, n, p, pos, scale, c, collider, euler, smooth, emission, Infer(c, surf, false));
    }

    static GameObject Ball(string n, Transform p, Vector3 pos, Vector3 scale, Color c, float smooth = 0.15f, float emission = 0f, Surface surf = Surface.Grime)
    {
        return MatLib.Prim(PrimitiveType.Sphere, n, p, pos, scale, c, false, default(Vector3), smooth, emission, Infer(c, surf, true));
    }

    static GameObject Cyl(string n, Transform p, Vector3 pos, Vector3 scale, Color c, Vector3 euler = default(Vector3), float smooth = 0.15f, float emission = 0f, Surface surf = Surface.Grime)
    {
        return MatLib.Prim(PrimitiveType.Cylinder, n, p, pos, scale, c, false, euler, smooth, emission, Infer(c, surf, false));
    }

    // Which texture a colour gets when the caller did not say: wood colours -> wood, stone -> bricks (rocks for
    // round shapes), iron and gold -> metal, the zone's grass and earth -> grass, bark -> bark, leaves -> leaves.
    static Surface Infer(Color c, Surface asked, bool round)
    {
        if (asked != Surface.Grime) return asked;
        if (c == Wood || c == WoodLight || c == WoodDark) return Surface.Wood;
        if (c == Stone || c == StoneDark) return round ? Surface.Stone : Surface.Bricks;
        if (c == CurbRed || c == CurbWhite) return Surface.Stone;
        if (c == Iron || c == Gold) return Surface.Metal;
        if (c == Royal || c == RoofBlue) return Surface.Fabric;
        if (c == B.grass || c == B.grassDark || c == B.ground || c == GrassDark) return Surface.Grass;
        if (c == B.trunk) return Surface.Bark;
        if (c == B.leaves || c == B.leaves2 || c == B.pine) return Surface.Leaves;
        return Surface.Grime;
    }

    // ------------------------------------------------------------------
    //  Road
    // ------------------------------------------------------------------

    // openSide: -1 / 1 = the road turns to that side here, so that side has no curb, grass or trees
    // (the next piece of road lies there).
    static GameObject BuildChunk(string name, Transform parent, ChunkStyle style, int openSide = 0)
    {
        GameObject root = new GameObject(name);
        root.transform.SetParent(parent, false);
        Transform t = root.transform;
        System.Random rnd = new System.Random(style.seed);

        // the floor: top surface at y = 0, the piece "grows" forward from z = 0 to z = 10
        // cobblestones: a whole number of texture repeats per piece, so there is no seam between pieces
        MatLib.Prim(PrimitiveType.Cube, "Floor", t, new Vector3(0f, -0.1f, ChunkLength * 0.5f), new Vector3(RoadWidth, 0.2f, ChunkLength), Road,
                    true, default(Vector3), 0.2f, 0f, Surface.Road, new Vector2(3f, 3f));

        // dashed lines between the lanes (lanes are at x = -2.5, 0, 2.5) and gold edge lines
        foreach (float x in new[] { -1.25f, 1.25f })
            for (int i = 0; i < 2; i++)
                Box("Lane Line", t, new Vector3(x, 0.006f, 2.5f + i * 5f), new Vector3(0.1f, 0.012f, 2.4f), Line);
        foreach (float x in new[] { -4.3f, 4.3f })
            if (openSide == 0 || Mathf.Sign(x) != openSide)
                Box("Edge Line", t, new Vector3(x, 0.006f, ChunkLength * 0.5f), new Vector3(0.08f, 0.012f, ChunkLength), Gold);

        // the grass height differs a tiny bit between templates, so overlapping grass near corners does not flicker
        float grassY = -0.12f - (style.seed % 7) * 0.004f;

        // red-and-white curbs keep rolling obstacles on the road
        float curbX = RoadWidth * 0.5f + 0.18f;
        for (int side = -1; side <= 1; side += 2)
        {
            bool open = side == openSide;
            for (int i = 0; i < 5; i++)
                if (!open || i == 0)
                    Box("Curb", t, new Vector3(side * curbX, 0.06f, open ? 0.5f : 1f + i * 2f), new Vector3(0.36f, 0.32f, open ? 1f : 2f), i % 2 == 0 ? CurbRed : CurbWhite, true);

            // grass and a strip of earth (or snow) between the curb and the grass
            float grassX = RoadWidth * 0.5f + 0.36f + 11f;
            float len = open ? 1f : ChunkLength;
            Box("Grass", t, new Vector3(side * grassX, grassY, len * 0.5f), new Vector3(22f, 0.2f, len), B.grass);
            Box("Verge", t, new Vector3(side * (RoadWidth * 0.5f + 0.75f), -0.04f, len * 0.5f), new Vector3(0.8f, 0.1f, len), B.ground);
        }

        if (style.lampLeft && openSide != -1) AddLamp(t, -1f);
        if (style.lampRight && openSide != 1) AddLamp(t, 1f);
        if (style.rail && openSide == 0) { AddRail(t, -1f); AddRail(t, 1f); }
        if (style.banners) { if (openSide != -1) AddBanner(t, -1f, 2.5f); if (openSide != 1) AddBanner(t, 1f, 7.5f); }
        if (style.castle && openSide == 0) AddCastle(t, rnd.Next(2) == 0 ? -1f : 1f, rnd);

        // trees, bushes, rocks and flowers - each template has its own layout
        for (int side = -1; side <= 1; side += 2)
        {
            if (side == openSide) continue;
            int count = Lite ? 1 : 1 + rnd.Next(3);
            for (int i = 0; i < count; i++)
            {
                float x = side * (7.5f + (float)rnd.NextDouble() * 10f);
                float z = 1f + (float)rnd.NextDouble() * 8f;
                int kind = rnd.Next(4);
                float v = (float)rnd.NextDouble();
                if (kind == 0) AddBush(t, new Vector3(x, 0f, z), v);
                else if (kind == 1) AddPine(t, new Vector3(x, 0f, z), v);
                else AddTree(t, new Vector3(x, 0f, z), v);
            }
            if (rnd.Next(2) == 0)
                AddRock(t, new Vector3(side * (6.3f + (float)rnd.NextDouble() * 3f), 0f, 1f + (float)rnd.NextDouble() * 8f), (float)rnd.NextDouble());
            for (int i = 0; i < (Lite ? 3 : 6); i++)
            {
                Vector3 p = new Vector3(side * (5.6f + (float)rnd.NextDouble() * 6f), 0.06f, (float)rnd.NextDouble() * 10f);
                Ball("Flower", t, p, Vector3.one * 0.14f, B.flowers[rnd.Next(B.flowers.Length)], 0.3f, 0.15f);
            }
            if (B.fallenLeaves)
                for (int i = 0; i < 8; i++)
                {
                    Vector3 p = new Vector3(side * (5.3f + (float)rnd.NextDouble() * 8f), 0.0f, (float)rnd.NextDouble() * 10f);
                    Box("Fallen Leaf", t, p, new Vector3(0.22f, 0.02f, 0.14f), rnd.Next(2) == 0 ? B.leaves : B.leaves2, false, new Vector3(0f, (float)rnd.NextDouble() * 180f, 0f));
                }
            if (B.snow)
                for (int i = 0; i < 3; i++)
                {
                    Vector3 p = new Vector3(side * (6f + (float)rnd.NextDouble() * 9f), 0.0f, (float)rnd.NextDouble() * 10f);
                    Ball("Snowdrift", t, p, new Vector3(1.6f, 0.45f, 1.2f) * (0.7f + (float)rnd.NextDouble() * 0.6f), Color.white, 0.4f);
                }
        }

        return root;
    }

    static void AddLamp(Transform chunk, float side)
    {
        Transform lamp = new GameObject("Lightpost").transform;
        lamp.SetParent(chunk, false);
        lamp.localPosition = new Vector3(side * (RoadWidth * 0.5f + 1.0f), 0f, ChunkLength * 0.5f);
        Cyl("Base", lamp, new Vector3(0f, 0.15f, 0f), new Vector3(0.32f, 0.15f, 0.32f), Iron, default(Vector3), 0.5f);
        Cyl("Pole", lamp, new Vector3(0f, 1.6f, 0f), new Vector3(0.13f, 1.6f, 0.13f), Iron, default(Vector3), 0.5f);
        Box("Arm", lamp, new Vector3(-side * 0.35f, 3.15f, 0f), new Vector3(0.75f, 0.07f, 0.07f), Iron, false, default(Vector3), 0.5f);
        Cyl("Hood", lamp, new Vector3(-side * 0.7f, 3.12f, 0f), new Vector3(0.36f, 0.06f, 0.36f), Iron, default(Vector3), 0.5f);
        Ball("Lamp", lamp, new Vector3(-side * 0.7f, 2.98f, 0f), Vector3.one * 0.3f, LampLight, 0.6f, 1.8f);
        Ball("Top", lamp, new Vector3(0f, 3.25f, 0f), Vector3.one * 0.14f, Gold, 0.8f, 0.2f);
    }

    static void AddRail(Transform chunk, float side)
    {
        float x = side * (RoadWidth * 0.5f + 1.6f);
        for (int i = 0; i < 4; i++)
            Box("Rail Post", chunk, new Vector3(x, 0.4f, 1.25f + i * 2.5f), new Vector3(0.14f, 0.8f, 0.14f), WoodDark);
        Box("Rail", chunk, new Vector3(x, 0.62f, ChunkLength * 0.5f), new Vector3(0.08f, 0.1f, ChunkLength), Wood);
        Box("Rail Low", chunk, new Vector3(x, 0.3f, ChunkLength * 0.5f), new Vector3(0.08f, 0.1f, ChunkLength), Wood);
    }

    static void AddBanner(Transform chunk, float side, float z)
    {
        Transform b = new GameObject("Banner").transform;
        b.SetParent(chunk, false);
        b.localPosition = new Vector3(side * (RoadWidth * 0.5f + 1.2f), 0f, z);
        Cyl("Pole", b, new Vector3(0f, 1.9f, 0f), new Vector3(0.1f, 1.9f, 0.1f), WoodDark);
        Ball("Finial", b, new Vector3(0f, 3.85f, 0f), Vector3.one * 0.16f, Gold, 0.8f, 0.3f);
        Box("Bar", b, new Vector3(-side * 0.35f, 3.6f, 0f), new Vector3(0.8f, 0.05f, 0.05f), WoodDark);
        Box("Cloth", b, new Vector3(-side * 0.35f, 2.85f, 0f), new Vector3(0.7f, 1.4f, 0.04f), Royal);
        Box("Stripe", b, new Vector3(-side * 0.35f, 2.85f, -0.025f), new Vector3(0.14f, 1.4f, 0.02f), Gold, false, default(Vector3), 0.6f, 0.15f);
        Box("Crown", b, new Vector3(-side * 0.35f, 3.1f, -0.03f), new Vector3(0.3f, 0.18f, 0.02f), Gold, false, default(Vector3), 0.6f, 0.2f);
        Box("Tail L", b, new Vector3(-side * 0.35f - 0.2f, 2.08f, 0f), new Vector3(0.3f, 0.3f, 0.04f), Royal, false, new Vector3(0f, 0f, 45f));
        Box("Tail R", b, new Vector3(-side * 0.35f + 0.2f, 2.08f, 0f), new Vector3(0.3f, 0.3f, 0.04f), Royal, false, new Vector3(0f, 0f, 45f));
    }

    // A castle tower far away from the road - in the fog it looks like a silhouette on the horizon.
    static void AddCastle(Transform chunk, float side, System.Random rnd)
    {
        Transform c = new GameObject("Castle").transform;
        c.SetParent(chunk, false);
        c.localPosition = new Vector3(side * (21.5f + (float)rnd.NextDouble() * 3.5f), 0f, 5f);
        float h = 7f + (float)rnd.NextDouble() * 4f;
        Cyl("Tower", c, new Vector3(0f, h * 0.5f, 0f), new Vector3(3.2f, h * 0.5f, 3.2f), StoneDark);
        for (int i = 0; i < 8; i++)
        {
            float a = i * Mathf.PI / 4f;
            Box("Merlon", c, new Vector3(Mathf.Sin(a) * 1.45f, h + 0.3f, Mathf.Cos(a) * 1.45f), new Vector3(0.5f, 0.6f, 0.5f), StoneDark, false, new Vector3(0f, a * Mathf.Rad2Deg, 0f));
        }
        float[] roof = { 2.6f, 2.0f, 1.4f, 0.8f, 0.3f };
        for (int i = 0; i < roof.Length; i++)
            Cyl("Roof", c, new Vector3(0f, h + 0.9f + i * 0.7f, 0f), new Vector3(roof[i], 0.35f, roof[i]), RoofBlue);
        Cyl("Flag Pole", c, new Vector3(0f, h + 4.9f, 0f), new Vector3(0.08f, 0.8f, 0.08f), Iron);
        Box("Flag", c, new Vector3(0.5f, h + 5.3f, 0f), new Vector3(1f, 0.5f, 0.05f), FenceRed);
        for (int i = 0; i < 3; i++)
            Box("Window", c, new Vector3(-side * 1.55f, h * (0.35f + i * 0.2f), 0f), new Vector3(0.1f, 0.6f, 0.35f), LampLight, false, default(Vector3), 0.3f, 1.2f);

        // a piece of the wall next to the tower
        Box("Wall", c, new Vector3(0f, 2.2f, -4f), new Vector3(1.6f, 4.4f, 6f), Stone);
    }

    static void AddTree(Transform chunk, Vector3 pos, float v)
    {
        Transform tree = new GameObject("Tree").transform;
        tree.SetParent(chunk, false);
        tree.localPosition = pos;
        tree.localScale = Vector3.one * (0.85f + v * 0.5f);
        tree.localRotation = Quaternion.Euler(0f, v * 360f, 0f);
        Cyl("Trunk", tree, new Vector3(0f, 0.7f, 0f), new Vector3(0.28f, 0.7f, 0.28f), B.trunk);
        Color leaf = Color.Lerp(B.leaves, B.leaves2, v);
        Ball("Crown", tree, new Vector3(0f, 2.0f, 0f), new Vector3(1.7f, 1.5f, 1.7f), leaf, surf: Surface.Leaves);
        Ball("Crown Top", tree, new Vector3(0.2f, 2.7f, -0.15f), new Vector3(1.1f, 1.0f, 1.1f), Color.Lerp(leaf, Color.white, 0.08f), surf: Surface.Leaves);
        Ball("Crown Side", tree, new Vector3(-0.55f, 1.85f, 0.3f), new Vector3(0.9f, 0.8f, 0.9f), Color.Lerp(leaf, B.leaves2, 0.5f), surf: Surface.Leaves);
        if (v > 0.5f && !B.snow && !B.fallenLeaves)
            for (int i = 0; i < 3; i++)
                Ball("Apple", tree, new Vector3(Mathf.Sin(i * 2.1f) * 0.75f, 1.8f + i * 0.25f, Mathf.Cos(i * 2.1f) * 0.75f), Vector3.one * 0.16f, new Color(0.85f, 0.12f, 0.12f), 0.6f);
    }

    static void AddPine(Transform chunk, Vector3 pos, float v)
    {
        Transform tree = new GameObject("Pine").transform;
        tree.SetParent(chunk, false);
        tree.localPosition = pos;
        tree.localScale = Vector3.one * (0.9f + v * 0.6f);
        Cyl("Trunk", tree, new Vector3(0f, 0.4f, 0f), new Vector3(0.25f, 0.4f, 0.25f), B.trunk);
        float[] r = { 1.7f, 1.35f, 1.0f, 0.65f, 0.3f };
        for (int i = 0; i < r.Length; i++)
        {
            Cyl("Needles", tree, new Vector3(0f, 1.0f + i * 0.55f, 0f), new Vector3(r[i], 0.3f, r[i]), B.pine);
            // snow lies on every tier of a winter fir
            if (B.snow) Cyl("Snow", tree, new Vector3(0f, 1.27f + i * 0.55f, 0f), new Vector3(r[i] * 0.8f, 0.06f, r[i] * 0.8f), Color.white, default(Vector3), 0.4f);
        }
    }

    static void AddBush(Transform chunk, Vector3 pos, float v)
    {
        float s = 0.8f + v * 0.5f;
        Ball("Bush", chunk, pos + Vector3.up * 0.3f, new Vector3(1.3f, 0.8f, 1.1f) * s, B.grassDark);
        Ball("Bush", chunk, pos + new Vector3(0.5f, 0.25f, 0.3f) * s, new Vector3(0.8f, 0.6f, 0.8f) * s, B.leaves);
        if (v > 0.4f && !B.snow)
            for (int i = 0; i < 4; i++)
                Ball("Berry", chunk, pos + new Vector3(Mathf.Sin(i * 1.7f) * 0.5f, 0.55f, Mathf.Cos(i * 1.7f) * 0.4f) * s, Vector3.one * 0.1f, B.flowers[1 % B.flowers.Length], 0.5f, 0.1f);
    }

    static void AddRock(Transform chunk, Vector3 pos, float v)
    {
        Ball("Rock", chunk, pos + Vector3.up * 0.15f, new Vector3(1.0f, 0.6f, 0.8f) * (0.7f + v), StoneDark);
        Ball("Rock", chunk, pos + new Vector3(0.5f, 0.08f, 0.2f), new Vector3(0.5f, 0.35f, 0.4f) * (0.7f + v), Stone);
        if (B.snow) Ball("Snow Cap", chunk, pos + Vector3.up * 0.38f * (0.7f + v), new Vector3(0.8f, 0.2f, 0.65f) * (0.7f + v), Color.white, 0.4f);
    }

    // The end of a corner piece: a castle wall across the road (running into it ends the run),
    // gold arrows on the road and on the wall pointing where the road goes, and ground behind the wall.
    static void AddCornerEnd(Transform chunk, int dir)
    {
        const float z = 10.25f;
        GameObject wall = new GameObject("Dead End");
        wall.transform.SetParent(chunk, false);
        wall.transform.localPosition = new Vector3(0f, 0f, z);
        BoxCollider box = wall.AddComponent<BoxCollider>();
        box.center = new Vector3(0f, 1.5f, 0f);
        box.size = new Vector3(RoadWidth, 3f, 0.5f);
        wall.AddComponent<Hazard>().Configure(new Color(0.55f, 0.55f, 0.58f), 3f, HazardKind.TurnBarrier);

        Transform w = wall.transform;
        Box("Wall", w, new Vector3(0f, 1.6f, 0.1f), new Vector3(RoadWidth + 1.2f, 3.2f, 0.7f), Stone);
        for (int i = 0; i < 7; i++)
            Box("Merlon", w, new Vector3(-4.5f + i * 1.5f, 3.45f, 0.1f), new Vector3(0.7f, 0.5f, 0.7f), StoneDark);
        // a big arrow on the wall
        for (int i = 0; i < 3; i++)
        {
            Box("Arrow", w, new Vector3(dir * (i * 0.9f - 0.9f), 1.8f, -0.27f), new Vector3(0.9f, 0.22f, 0.05f), Gold, false, new Vector3(0f, 0f, dir * 35f), 0.7f, 0.6f);
            Box("Arrow", w, new Vector3(dir * (i * 0.9f - 0.9f), 1.4f, -0.27f), new Vector3(0.9f, 0.22f, 0.05f), Gold, false, new Vector3(0f, 0f, -dir * 35f), 0.7f, 0.6f);
        }
        Ball("Torch", w, new Vector3(-3.6f, 2.4f, -0.3f), Vector3.one * 0.3f, new Color(1f, 0.6f, 0.15f), 0.3f, 2f);
        Ball("Torch", w, new Vector3(3.6f, 2.4f, -0.3f), Vector3.one * 0.3f, new Color(1f, 0.6f, 0.15f), 0.3f, 2f);

        // chevrons on the road
        for (int i = 0; i < 3; i++)
        {
            float cz = 2.2f + i * 1.3f;
            Box("Chevron", chunk, new Vector3(dir * 0.35f, 0.008f, cz + 0.3f), new Vector3(1.4f, 0.012f, 0.25f), Gold, false, new Vector3(0f, dir * 40f, 0f), 0.4f, 0.4f);
            Box("Chevron", chunk, new Vector3(dir * 0.35f, 0.008f, cz - 0.3f), new Vector3(1.4f, 0.012f, 0.25f), Gold, false, new Vector3(0f, -dir * 40f, 0f), 0.4f, 0.4f);
        }

        // ground behind the wall (the side road lies on the open side, so only the other side is covered)
        float gx = -dir * 11f;
        Box("Ground Behind", chunk, new Vector3(gx, -0.13f, z + 10.3f), new Vector3(31f, 0.2f, 20f), B.grass);
        AddTree(chunk, new Vector3(-dir * 2f, 0f, z + 4f), 0.3f);
        AddPine(chunk, new Vector3(-dir * 6.5f, 0f, z + 6f), 0.6f);
        AddTree(chunk, new Vector3(dir * 1.5f, 0f, z + 9f), 0.8f);
    }

    // A log across one lane at head height: slide under it (jumping over is impossible, running into it ends the run).
    static GameObject BuildBeam(Transform parent)
    {
        GameObject root = new GameObject("Beam");
        root.transform.SetParent(parent, false);
        BoxCollider box = root.AddComponent<BoxCollider>();
        box.center = new Vector3(0f, 2.0f, 0f);
        box.size = new Vector3(2.3f, 1.2f, 0.45f);
        root.AddComponent<Hazard>().Configure(new Color(0.5f, 0.32f, 0.16f), 2f, HazardKind.Fatal);

        Transform t = root.transform;
        Cyl("Post L", t, new Vector3(-1.18f, 1.35f, 0f), new Vector3(0.16f, 1.35f, 0.16f), WoodDark);
        Cyl("Post R", t, new Vector3(1.18f, 1.35f, 0f), new Vector3(0.16f, 1.35f, 0.16f), WoodDark);
        Cyl("Log", t, new Vector3(0f, 1.75f, 0f), new Vector3(0.36f, 1.25f, 0.36f), Wood, new Vector3(0f, 0f, 90f));
        Cyl("Log 2", t, new Vector3(0f, 2.15f, 0f), new Vector3(0.3f, 1.25f, 0.3f), WoodDark, new Vector3(0f, 0f, 90f));
        Box("Banner", t, new Vector3(0f, 1.65f, -0.2f), new Vector3(1.2f, 0.32f, 0.03f), Royal);
        Box("Stripe", t, new Vector3(0f, 1.65f, -0.22f), new Vector3(1.2f, 0.07f, 0.02f), Gold, false, default(Vector3), 0.6f, 0.4f);
        return root;
    }

    // The arch over the road and the invisible trigger that adds time (the Checkpoint script).
    static void AddCheckpointArch(Transform chunk)
    {
        const float z = 2f;
        float px = RoadWidth * 0.5f + 0.5f;

        for (int side = -1; side <= 1; side += 2)
        {
            Transform tower = new GameObject("Arch Tower").transform;
            tower.SetParent(chunk, false);
            tower.localPosition = new Vector3(side * px, 0f, z);
            Box("Pillar", tower, new Vector3(0f, 2.3f, 0f), new Vector3(0.9f, 4.6f, 0.9f), Stone);
            Box("Base", tower, new Vector3(0f, 0.3f, 0f), new Vector3(1.1f, 0.6f, 1.1f), StoneDark);
            Box("Cap", tower, new Vector3(0f, 4.7f, 0f), new Vector3(1.1f, 0.3f, 1.1f), Gold, false, default(Vector3), 0.7f, 0.15f);
            float[] roof = { 0.8f, 0.55f, 0.3f };
            for (int i = 0; i < roof.Length; i++)
                Cyl("Roof", tower, new Vector3(0f, 5.05f + i * 0.35f, 0f), new Vector3(roof[i], 0.18f, roof[i]), FenceRed);
            Cyl("Flag Pole", tower, new Vector3(0f, 6.2f, 0f), new Vector3(0.05f, 0.5f, 0.05f), Iron);
            Box("Flag", tower, new Vector3(side * 0.3f, 6.45f, 0f), new Vector3(0.6f, 0.3f, 0.04f), Gold, false, default(Vector3), 0.6f, 0.3f);
            Ball("Torch", tower, new Vector3(-side * 0.5f, 3.2f, -0.3f), Vector3.one * 0.25f, new Color(1f, 0.6f, 0.15f), 0.3f, 2f);
        }

        Box("Beam", chunk, new Vector3(0f, 4.45f, z), new Vector3(px * 2f, 0.6f, 0.7f), Gold, false, default(Vector3), 0.7f, 0.15f);

        // a chequered finish banner
        for (int i = 0; i < 12; i++)
        {
            for (int row = 0; row < 2; row++)
            {
                bool dark = (i + row) % 2 == 0;
                Box("Banner", chunk, new Vector3(-3.3f + i * 0.6f, 3.75f - row * 0.4f, z), new Vector3(0.6f, 0.4f, 0.08f),
                    dark ? new Color(0.1f, 0.08f, 0.14f) : Color.white);
            }
        }
        // glowing gate line on the road
        Box("Gate Line", chunk, new Vector3(0f, 0.008f, z), new Vector3(RoadWidth, 0.015f, 0.25f), new Color(0.5f, 1f, 0.6f), false, default(Vector3), 0.3f, 1.2f);

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

    // A low fence: it slows you down, but you can JUMP over it.
    static GameObject BuildFence(Transform parent)
    {
        GameObject root = new GameObject("Fence");
        root.transform.SetParent(parent, false);
        BoxCollider box = root.AddComponent<BoxCollider>();
        box.center = new Vector3(0f, 0.5f, 0f);
        box.size = new Vector3(2.0f, 1.0f, 0.3f);
        root.AddComponent<Hazard>().Configure(new Color(0.8f, 0.35f, 0.25f), 2f);

        Transform t = root.transform;
        Box("Post L", t, new Vector3(-0.9f, 0.55f, 0f), new Vector3(0.14f, 1.1f, 0.2f), WoodDark);
        Box("Post R", t, new Vector3(0.9f, 0.55f, 0f), new Vector3(0.14f, 1.1f, 0.2f), WoodDark);
        Ball("Knob L", t, new Vector3(-0.9f, 1.12f, 0f), Vector3.one * 0.16f, Gold, 0.7f, 0.1f);
        Ball("Knob R", t, new Vector3(0.9f, 1.12f, 0f), Vector3.one * 0.16f, Gold, 0.7f, 0.1f);
        for (int i = 0; i < 5; i++)
        {
            Color c = i % 2 == 0 ? FenceRed : Color.white;
            Box("Plank", t, new Vector3(-0.72f + i * 0.36f, 0.78f, 0.02f), new Vector3(0.36f, 0.26f, 0.1f), c, surf: Surface.Wood);
        }
        Box("Rail", t, new Vector3(0f, 0.38f, 0.02f), new Vector3(1.8f, 0.1f, 0.08f), WoodDark);
        Box("Foot L", t, new Vector3(-0.9f, 0.05f, 0f), new Vector3(0.2f, 0.1f, 0.5f), WoodDark);
        Box("Foot R", t, new Vector3(0.9f, 0.05f, 0f), new Vector3(0.2f, 0.1f, 0.5f), WoodDark);
        return root;
    }

    // A tall stone wall with a banner: it CANNOT be jumped over - only avoided.
    static GameObject BuildWall(Transform parent)
    {
        GameObject root = new GameObject("Wall");
        root.transform.SetParent(parent, false);
        BoxCollider box = root.AddComponent<BoxCollider>();
        box.center = new Vector3(0f, 1.3f, 0f);
        box.size = new Vector3(2.1f, 2.6f, 0.5f);
        root.AddComponent<Hazard>().Configure(new Color(0.55f, 0.55f, 0.58f), 3f, HazardKind.Fatal);

        Transform t = root.transform;
        for (int row = 0; row < 4; row++)
        {
            float off = row % 2 == 0 ? 0f : 0.26f;
            for (int i = 0; i < 4; i++)
            {
                float x = -0.79f + i * 0.52f + off;
                if (x > 0.9f) continue;
                Box("Brick", t, new Vector3(x, 0.3f + row * 0.6f, 0f), new Vector3(0.5f, 0.56f, 0.5f), (row + i) % 3 == 0 ? StoneDark : Stone);
            }
        }
        Box("Fill", t, new Vector3(0f, 1.2f, 0f), new Vector3(2.0f, 2.4f, 0.44f), StoneDark);
        for (int i = 0; i < 3; i++)
            Box("Merlon", t, new Vector3(-0.75f + i * 0.75f, 2.6f, 0f), new Vector3(0.45f, 0.4f, 0.5f), Stone);
        Box("Banner", t, new Vector3(0f, 1.4f, -0.27f), new Vector3(0.7f, 1.3f, 0.03f), Royal);
        Box("Banner Crown", t, new Vector3(0f, 1.6f, -0.29f), new Vector3(0.3f, 0.2f, 0.02f), Gold, false, default(Vector3), 0.6f, 0.2f);
        Box("Warning", t, new Vector3(0f, 0.15f, -0.27f), new Vector3(2.0f, 0.12f, 0.03f), Gold, false, default(Vector3), 0.6f, 0.4f);
        return root;
    }

    static GameObject BuildCoin(Transform parent, bool gem)
    {
        GameObject root = new GameObject(gem ? "Gem Pickup" : "Coin Pickup");
        root.transform.SetParent(parent, false);
        SphereCollider sc = root.AddComponent<SphereCollider>();
        sc.center = new Vector3(0f, 1f, 0f);
        sc.radius = 0.5f;
        sc.isTrigger = true;
        Coin coin = root.AddComponent<Coin>();
        Transform t = root.transform;

        if (!gem)
        {
            coin.Configure(100, false);
            Cyl("Disc", t, new Vector3(0f, 1f, 0f), new Vector3(0.62f, 0.05f, 0.62f), Gold, new Vector3(90f, 0f, 0f), 0.85f, 0.35f);
            Cyl("Inner", t, new Vector3(0f, 1f, 0f), new Vector3(0.44f, 0.06f, 0.44f), new Color(1f, 0.9f, 0.4f), new Vector3(90f, 0f, 0f), 0.85f, 0.4f);
            Box("Star", t, new Vector3(0f, 1f, 0f), new Vector3(0.14f, 0.14f, 0.08f), Gold, false, new Vector3(0f, 0f, 45f), 0.85f, 0.5f);
        }
        else
        {
            coin.Configure(500, true);
            Color g = new Color(0.75f, 0.35f, 1f);
            Box("Gem Top", t, new Vector3(0f, 1.12f, 0f), new Vector3(0.4f, 0.4f, 0.4f), g, false, new Vector3(45f, 0f, 45f), 0.95f, 0.8f);
            Box("Gem Core", t, new Vector3(0f, 1f, 0f), new Vector3(0.3f, 0.5f, 0.3f), Color.Lerp(g, Color.white, 0.4f), false, new Vector3(0f, 45f, 0f), 0.95f, 1.2f);
            Cyl("Halo", t, new Vector3(0f, 1f, 0f), new Vector3(0.8f, 0.01f, 0.8f), Color.Lerp(g, Color.white, 0.6f), default(Vector3), 0.5f, 1f);
        }
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
        Ball("Apple", t, new Vector3(0f, 0.9f, 0f), new Vector3(0.55f, 0.5f, 0.55f), new Color(0.88f, 0.12f, 0.12f), 0.7f, 0.15f);
        Ball("Shine", t, new Vector3(-0.12f, 1.02f, 0.18f), Vector3.one * 0.1f, new Color(1f, 0.7f, 0.7f), 0.9f, 0.3f);
        Cyl("Stem", t, new Vector3(0f, 1.18f, 0f), new Vector3(0.04f, 0.07f, 0.04f), WoodDark);
        Box("Leaf", t, new Vector3(0.08f, 1.2f, 0f), new Vector3(0.16f, 0.02f, 0.08f), new Color(0.3f, 0.75f, 0.25f), false, new Vector3(0f, 0f, 25f));
        return root;
    }

    static GameObject BuildPowerUp(Transform parent, PowerUpType type)
    {
        GameObject root = new GameObject(type + " PowerUp");
        root.transform.SetParent(parent, false);
        SphereCollider sc = root.AddComponent<SphereCollider>();
        sc.center = new Vector3(0f, 1.1f, 0f);
        sc.radius = 0.6f;
        sc.isTrigger = true;
        root.AddComponent<PowerUp>().Configure(type);
        Transform t = root.transform;

        // a glowing ring on the ground under every bonus
        Color ring = type == PowerUpType.Shield ? new Color(0.3f, 0.85f, 1f)
                   : type == PowerUpType.Magnet ? new Color(1f, 0.35f, 0.35f)
                   : new Color(1f, 0.85f, 0.3f);
        Cyl("Ring", t, new Vector3(0f, 0.02f, 0f), new Vector3(1.1f, 0.01f, 1.1f), ring, default(Vector3), 0.5f, 1.2f);

        switch (type)
        {
            case PowerUpType.Shield:
                Cyl("Shield", t, new Vector3(0f, 1.1f, 0f), new Vector3(0.7f, 0.06f, 0.8f), ring, new Vector3(90f, 0f, 0f), 0.9f, 0.6f);
                Cyl("Rim", t, new Vector3(0f, 1.1f, 0f), new Vector3(0.78f, 0.05f, 0.88f), Color.white, new Vector3(90f, 0f, 0f), 0.9f, 0.3f);
                Box("Cross V", t, new Vector3(0f, 1.1f, 0.05f), new Vector3(0.1f, 0.5f, 0.04f), Color.white, false, default(Vector3), 0.9f, 0.5f);
                Box("Cross H", t, new Vector3(0f, 1.18f, 0.05f), new Vector3(0.36f, 0.1f, 0.04f), Color.white, false, default(Vector3), 0.9f, 0.5f);
                break;
            case PowerUpType.Magnet:
                Box("Arm L", t, new Vector3(-0.22f, 1.15f, 0f), new Vector3(0.18f, 0.5f, 0.18f), ring, false, default(Vector3), 0.7f, 0.4f);
                Box("Arm R", t, new Vector3(0.22f, 1.15f, 0f), new Vector3(0.18f, 0.5f, 0.18f), ring, false, default(Vector3), 0.7f, 0.4f);
                Box("Bend", t, new Vector3(0f, 0.86f, 0f), new Vector3(0.62f, 0.18f, 0.18f), ring, false, default(Vector3), 0.7f, 0.4f);
                Box("Tip L", t, new Vector3(-0.22f, 1.47f, 0f), new Vector3(0.2f, 0.16f, 0.2f), Color.white, false, default(Vector3), 0.9f, 0.4f);
                Box("Tip R", t, new Vector3(0.22f, 1.47f, 0f), new Vector3(0.2f, 0.16f, 0.2f), Color.white, false, default(Vector3), 0.9f, 0.4f);
                break;
            default:
                Cyl("Top", t, new Vector3(0f, 1.48f, 0f), new Vector3(0.5f, 0.04f, 0.5f), WoodDark);
                Cyl("Bottom", t, new Vector3(0f, 0.72f, 0f), new Vector3(0.5f, 0.04f, 0.5f), WoodDark);
                for (int i = 0; i < 3; i++)
                {
                    float a = i * Mathf.PI * 2f / 3f;
                    Cyl("Post", t, new Vector3(Mathf.Sin(a) * 0.2f, 1.1f, Mathf.Cos(a) * 0.2f), new Vector3(0.05f, 0.38f, 0.05f), WoodDark);
                }
                Ball("Glass Top", t, new Vector3(0f, 1.28f, 0f), new Vector3(0.3f, 0.36f, 0.3f), new Color(0.8f, 0.95f, 1f), 0.95f, 0.3f);
                Ball("Glass Bottom", t, new Vector3(0f, 0.92f, 0f), new Vector3(0.3f, 0.36f, 0.3f), new Color(0.8f, 0.95f, 1f), 0.95f, 0.3f);
                Ball("Sand", t, new Vector3(0f, 0.88f, 0f), new Vector3(0.22f, 0.18f, 0.22f), ring, 0.4f, 0.6f);
                break;
        }
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
        root.AddComponent<Hazard>().Configure(new Color(0.55f, 0.4f, 0.25f), 2f);

        AudioSource src = root.AddComponent<AudioSource>();
        src.playOnAwake = false;
        src.spatialBlend = 0f;
        src.volume = 0.16f;
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
        Cyl("Body", t, Vector3.zero, new Vector3(0.9f, 0.56f, 0.9f), Wood);
        Cyl("Belly", t, Vector3.zero, new Vector3(0.98f, 0.3f, 0.98f), Wood);
        Cyl("Band Top", t, new Vector3(0f, 0.36f, 0f), new Vector3(0.94f, 0.04f, 0.94f), Iron, default(Vector3), 0.5f);
        Cyl("Band Bottom", t, new Vector3(0f, -0.36f, 0f), new Vector3(0.94f, 0.04f, 0.94f), Iron, default(Vector3), 0.5f);
        Cyl("Lid", t, new Vector3(0f, 0.56f, 0f), new Vector3(0.8f, 0.01f, 0.8f), WoodLight);
        return root;
    }

    static GameObject BuildBench(Transform parent)
    {
        GameObject root = ObstacleRoot("Bench", parent, 1.2f);
        BoxCollider c = root.AddComponent<BoxCollider>();
        c.size = new Vector3(1.6f, 0.75f, 0.55f);
        Transform t = root.transform;
        for (int i = 0; i < 3; i++)
            Box("Slat", t, new Vector3(0f, 0.03f, -0.14f + i * 0.16f), new Vector3(1.6f, 0.08f, 0.14f), WoodLight);
        Box("Back", t, new Vector3(0f, 0.27f, -0.22f), new Vector3(1.6f, 0.3f, 0.07f), WoodLight);
        for (int i = 0; i < 4; i++)
        {
            float x = i < 2 ? -0.68f : 0.68f;
            float z = i % 2 == 0 ? -0.16f : 0.2f;
            Box("Leg", t, new Vector3(x, -0.18f, z), new Vector3(0.08f, 0.36f, 0.08f), Iron);
        }
        return root;
    }

    static GameObject BuildBox(Transform parent)
    {
        GameObject root = ObstacleRoot("Box", parent, 1.3f);
        BoxCollider c = root.AddComponent<BoxCollider>();
        c.size = Vector3.one * 1.05f;
        Transform t = root.transform;
        Box("Crate", t, Vector3.zero, Vector3.one * 1.0f, WoodLight);
        Box("Strap 1", t, new Vector3(0f, 0.43f, 0f), new Vector3(1.04f, 0.12f, 1.04f), Wood);
        Box("Strap 2", t, new Vector3(0f, -0.43f, 0f), new Vector3(1.04f, 0.12f, 1.04f), Wood);
        Box("Strap 3", t, Vector3.zero, new Vector3(0.12f, 1.04f, 1.04f), Wood);
        Box("Diagonal", t, Vector3.zero, new Vector3(1.04f, 0.1f, 1.3f), Wood, false, new Vector3(45f, 0f, 0f));
        return root;
    }

    static GameObject BuildCannon(Transform parent)
    {
        GameObject root = ObstacleRoot("Cannon", parent, 2.5f);
        CapsuleCollider c = root.AddComponent<CapsuleCollider>();
        c.radius = 0.38f; c.height = 1.7f; c.direction = 2;
        Transform t = root.transform;
        Cyl("Barrel", t, Vector3.zero, new Vector3(0.5f, 0.8f, 0.5f), Iron, new Vector3(90f, 0f, 0f), 0.6f);
        Cyl("Muzzle", t, new Vector3(0f, 0f, 0.78f), new Vector3(0.6f, 0.05f, 0.6f), Iron, new Vector3(90f, 0f, 0f), 0.6f);
        Cyl("Band", t, new Vector3(0f, 0f, 0.2f), new Vector3(0.56f, 0.04f, 0.56f), Gold, new Vector3(90f, 0f, 0f), 0.8f, 0.1f);
        Ball("Breech", t, new Vector3(0f, 0f, -0.8f), Vector3.one * 0.5f, Iron, 0.6f);
        Cyl("Wheel L", t, new Vector3(-0.36f, -0.18f, -0.25f), new Vector3(0.75f, 0.06f, 0.75f), Wood, new Vector3(0f, 0f, 90f));
        Cyl("Wheel R", t, new Vector3(0.36f, -0.18f, -0.25f), new Vector3(0.75f, 0.06f, 0.75f), Wood, new Vector3(0f, 0f, 90f));
        Cyl("Hub L", t, new Vector3(-0.4f, -0.18f, -0.25f), new Vector3(0.18f, 0.04f, 0.18f), Iron, new Vector3(0f, 0f, 90f));
        Cyl("Hub R", t, new Vector3(0.4f, -0.18f, -0.25f), new Vector3(0.18f, 0.04f, 0.18f), Iron, new Vector3(0f, 0f, 90f));
        return root;
    }

    static GameObject BuildCart(Transform parent)
    {
        GameObject root = ObstacleRoot("Cart", parent, 2f);
        BoxCollider c = root.AddComponent<BoxCollider>();
        c.size = new Vector3(1.3f, 0.95f, 1.6f);
        Transform t = root.transform;
        Box("Bed", t, new Vector3(0f, 0.08f, 0f), new Vector3(1.1f, 0.45f, 1.5f), Wood);
        Box("Rim", t, new Vector3(0f, 0.32f, 0f), new Vector3(1.14f, 0.06f, 1.54f), WoodDark);
        Ball("Hay", t, new Vector3(0f, 0.32f, 0f), new Vector3(0.9f, 0.35f, 1.2f), new Color(0.93f, 0.8f, 0.35f));
        Ball("Pumpkin", t, new Vector3(0.2f, 0.45f, 0.3f), new Vector3(0.35f, 0.28f, 0.35f), new Color(1f, 0.55f, 0.1f));
        for (int i = 0; i < 4; i++)
        {
            float x = i < 2 ? -0.6f : 0.6f;
            float z = i % 2 == 0 ? -0.5f : 0.5f;
            Cyl("Wheel", t, new Vector3(x, -0.25f, z), new Vector3(0.55f, 0.05f, 0.55f), Iron, new Vector3(0f, 0f, 90f));
        }
        return root;
    }

    // A runaway cart that drives from side to side across the road (LaneMover). Low enough to jump over.
    static GameObject BuildMovingCart(Transform parent)
    {
        GameObject root = new GameObject("Moving Cart");
        root.transform.SetParent(parent, false);
        BoxCollider c = root.AddComponent<BoxCollider>();
        c.center = new Vector3(0f, 0.55f, 0f);
        c.size = new Vector3(1.2f, 1.0f, 1.7f);
        root.AddComponent<Hazard>().Configure(new Color(0.6f, 0.4f, 0.2f), 2f);
        Transform t = root.transform;
        Box("Bed", t, new Vector3(0f, 0.6f, 0f), new Vector3(1.1f, 0.45f, 1.5f), Wood);
        Box("Rim", t, new Vector3(0f, 0.85f, 0f), new Vector3(1.14f, 0.06f, 1.54f), Gold, false, default(Vector3), 0.7f, 0.15f);
        Ball("Apples", t, new Vector3(0f, 0.86f, 0f), new Vector3(0.9f, 0.3f, 1.2f), new Color(0.85f, 0.15f, 0.12f), 0.6f);
        Box("Shaft L", t, new Vector3(-0.35f, 0.45f, 1.1f), new Vector3(0.06f, 0.06f, 0.9f), WoodDark);
        Box("Shaft R", t, new Vector3(0.35f, 0.45f, 1.1f), new Vector3(0.06f, 0.06f, 0.9f), WoodDark);
        Box("Flag", t, new Vector3(0.5f, 1.35f, -0.6f), new Vector3(0.04f, 0.35f, 0.4f), FenceRed);
        Cyl("Flag Pole", t, new Vector3(0.5f, 1.15f, -0.75f), new Vector3(0.03f, 0.35f, 0.03f), WoodDark);
        for (int i = 0; i < 4; i++)
        {
            float x = i < 2 ? -0.62f : 0.62f;
            float z = i % 2 == 0 ? -0.5f : 0.5f;
            Cyl("Wheel", t, new Vector3(x, 0.3f, z), new Vector3(0.6f, 0.05f, 0.6f), Wood, new Vector3(0f, 0f, 90f));
            Cyl("Hub", t, new Vector3(x * 1.05f, 0.3f, z), new Vector3(0.15f, 0.04f, 0.15f), Iron, new Vector3(0f, 0f, 90f));
        }
        root.AddComponent<LaneMover>();
        return Bake(root);
    }

    static GameObject BuildRock(Transform parent)
    {
        GameObject root = ObstacleRoot("Rock", parent, 3f);
        SphereCollider c = root.AddComponent<SphereCollider>();
        c.radius = 0.58f;
        Transform t = root.transform;
        MatLib.Prim(PrimitiveType.Sphere, "Stone", t, Vector3.zero, new Vector3(1.25f, 1.0f, 1.1f), Stone, false, new Vector3(10f, 20f, 0f));
        Ball("Bump", t, new Vector3(0.25f, 0.25f, 0.1f), new Vector3(0.6f, 0.5f, 0.6f), StoneDark);
        Ball("Bump 2", t, new Vector3(-0.3f, -0.1f, 0.25f), new Vector3(0.5f, 0.4f, 0.5f), StoneDark);
        Ball("Moss", t, new Vector3(0f, 0.38f, -0.1f), new Vector3(0.6f, 0.2f, 0.5f), GrassDark);
        return root;
    }
}
