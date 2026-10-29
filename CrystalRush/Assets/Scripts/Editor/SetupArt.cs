using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Setup step: textures, materials, 3D models (meshes) and particle effects.
/// Everything is drawn by code, so the project needs no downloaded assets.
/// </summary>
public static partial class CrystalRushSetup
{
    // Textures and sprites
    static Texture2D floorTexture;
    static Texture2D softDotTexture;
    static Sprite circleSprite;
    static Sprite roundedSprite;

    // Materials
    static readonly Dictionary<string, Material> materials = new Dictionary<string, Material>();

    // Meshes
    static Mesh crystalMesh;
    static Mesh spikeMesh;
    static Mesh ringMesh;

    // Particles
    static ParticleSystem collectBurst;
    static ParticleSystem pickupBurst;
    static ParticleSystem hitSparks;
    static ParticleSystem victoryConfetti;
    static GameObject ambientSparkles;

    // ================================================================ textures

    static void CreateTextures()
    {
        floorTexture = SaveTexture("FloorGrid", 256, 256, (x, y) =>
        {
            // 4 x 4 cells per floor tile (1 cell = 1 Unity unit), bright border lines.
            int cell = 64;
            int lx = x % cell, ly = y % cell;
            bool line = lx < 2 || ly < 2 || lx > cell - 3 || ly > cell - 3;
            bool tileEdge = x < 3 || y < 3 || x > 252 || y > 252;
            Color baseColor = ((x / cell + y / cell) % 2 == 0) ? new Color(0.12f, 0.13f, 0.25f) : new Color(0.10f, 0.11f, 0.21f);
            if (tileEdge) return new Color(0.35f, 0.55f, 0.95f);
            if (line) return new Color(0.2f, 0.28f, 0.5f);
            return baseColor;
        }, TextureImporterType.Default, TextureWrapMode.Repeat);

        softDotTexture = SaveTexture("SoftDot", 64, 64, (x, y) =>
        {
            float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(32f, 32f)) / 32f;
            float a = Mathf.Clamp01(1f - d);
            return new Color(1f, 1f, 1f, a * a);
        }, TextureImporterType.Sprite, TextureWrapMode.Clamp);

        Texture2D circle = SaveTexture("Circle", 128, 128, (x, y) =>
        {
            float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(64f, 64f));
            return new Color(1f, 1f, 1f, Mathf.Clamp01(63f - d));
        }, TextureImporterType.Sprite, TextureWrapMode.Clamp);
        circleSprite = AssetDatabase.LoadAssetAtPath<Sprite>(AssetDatabase.GetAssetPath(circle));

        const int size = 64, radius = 20;
        Texture2D rounded = SaveTexture("RoundedRect", size, size, (x, y) =>
        {
            // Distance to the rounded rectangle edge, with a soft (anti-aliased) border.
            float cx = Mathf.Clamp(x + 0.5f, radius, size - radius);
            float cy = Mathf.Clamp(y + 0.5f, radius, size - radius);
            float d = Vector2.Distance(new Vector2(x + 0.5f, y + 0.5f), new Vector2(cx, cy));
            return new Color(1f, 1f, 1f, Mathf.Clamp01(radius - d));
        }, TextureImporterType.Sprite, TextureWrapMode.Clamp, new Vector4(radius + 2, radius + 2, radius + 2, radius + 2));
        roundedSprite = AssetDatabase.LoadAssetAtPath<Sprite>(AssetDatabase.GetAssetPath(rounded));

        SaveTexture("AppIcon", 512, 512, DrawIcon, TextureImporterType.Default, TextureWrapMode.Clamp);
    }

    static Color DrawIcon(int x, int y)
    {
        // Purple-blue background and a glowing crystal (a diamond shape) in the middle.
        float u = x / 511f, v = y / 511f;
        Color background = Color.Lerp(new Color(0.08f, 0.06f, 0.25f), new Color(0.2f, 0.1f, 0.45f), v);
        float dx = Mathf.Abs(u - 0.5f), dy = v - 0.5f;
        float diamond = dx / 0.26f + Mathf.Abs(dy) / (dy > 0 ? 0.36f : 0.3f);
        if (diamond < 1f)
        {
            Color left = new Color(1f, 0.35f, 0.85f), right = new Color(0.45f, 0.9f, 1f);
            Color gem = u < 0.5f ? left : right;
            if (dy > 0.08f) gem = Color.Lerp(gem, Color.white, 0.35f);
            return Color.Lerp(gem, Color.white, Mathf.Pow(1f - diamond, 6f));
        }
        float glow = Mathf.Clamp01(1.4f - diamond) * 0.5f;
        return Color.Lerp(background, new Color(0.7f, 0.5f, 1f), glow);
    }

    static Texture2D SaveTexture(string name, int width, int height, System.Func<int, int, Color> pixel,
        TextureImporterType type, TextureWrapMode wrap, Vector4 spriteBorder = default)
    {
        Texture2D texture = new Texture2D(width, height, TextureFormat.RGBA32, false);
        Color[] pixels = new Color[width * height];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++)
                pixels[y * width + x] = pixel(x, y);
        texture.SetPixels(pixels);
        texture.Apply();

        string path = TexturesFolder + "/" + name + ".png";
        File.WriteAllBytes(path, texture.EncodeToPNG());
        Object.DestroyImmediate(texture);
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);

        TextureImporter importer = (TextureImporter)AssetImporter.GetAtPath(path);
        importer.textureType = type;
        importer.wrapMode = wrap;
        importer.alphaIsTransparency = true;
        importer.mipmapEnabled = type == TextureImporterType.Default;
        importer.anisoLevel = type == TextureImporterType.Default ? 4 : 1;
        if (type == TextureImporterType.Sprite)
        {
            importer.spriteImportMode = SpriteImportMode.Single;
            importer.spriteBorder = spriteBorder;
        }
        importer.SaveAndReimport();
        return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }

    // ================================================================ materials

    static Shader LitShader
    {
        get
        {
            Shader shader = Shader.Find("Universal Render Pipeline/Lit");
            return shader != null ? shader : Shader.Find("Standard");
        }
    }

    static void CreateMaterials()
    {
        materials.Clear();
        Lit("Floor", Color.white, 0.1f, 0.35f, Color.black, floorTexture);
        Lit("OuterGround", new Color(0.05f, 0.05f, 0.1f), 0f, 0.1f, Color.black);
        Lit("Wall", new Color(0.32f, 0.22f, 0.62f), 0.2f, 0.55f, Color.black);
        Lit("WallGlow", new Color(0.3f, 0.9f, 1f), 0f, 0.8f, new Color(0.2f, 0.8f, 1f) * 2f);
        Lit("Player", new Color(0.25f, 0.9f, 1f), 0.3f, 0.9f, new Color(0.05f, 0.45f, 0.7f));
        Lit("PlayerBand", new Color(0.05f, 0.1f, 0.2f), 0.6f, 0.8f, new Color(1f, 0.9f, 0.3f) * 1.5f);
        Lit("Crystal", new Color(1f, 0.35f, 0.85f), 0.2f, 0.95f, new Color(0.9f, 0.15f, 0.65f) * 1.6f);
        Lit("LaserBeam", new Color(1f, 0.1f, 0.1f), 0f, 0.5f, new Color(1f, 0.05f, 0.05f) * 5f);
        Lit("Metal", new Color(0.22f, 0.23f, 0.3f), 0.85f, 0.65f, Color.black);
        Lit("LaserEmitter", new Color(1f, 0.3f, 0.2f), 0f, 0.6f, new Color(1f, 0.2f, 0.1f) * 2.5f);
        Lit("DroneBody", new Color(1f, 0.5f, 0.12f), 0.4f, 0.7f, new Color(0.6f, 0.2f, 0f) * 0.6f);
        Lit("DroneEye", new Color(1f, 0.1f, 0.1f), 0f, 1f, new Color(1f, 0f, 0f) * 4f);
        Lit("SpikePlate", new Color(0.25f, 0.27f, 0.35f), 0.5f, 0.5f, new Color(0f, 0f, 0f, 1f), null, true);
        Lit("SpikeMetal", new Color(0.8f, 0.82f, 0.9f), 1f, 0.75f, Color.black);
        Lit("PickupLife", new Color(0.2f, 1f, 0.45f), 0f, 0.8f, new Color(0.1f, 0.9f, 0.3f) * 2f);
        Lit("PickupTime", new Color(1f, 0.85f, 0.2f), 0f, 0.8f, new Color(1f, 0.7f, 0.1f) * 2f);
        Lit("PortalClosed", new Color(0.4f, 0.4f, 0.48f), 0.7f, 0.5f, Color.black);
        Lit("PortalOpen", new Color(0.3f, 1f, 0.85f), 0.2f, 0.9f, new Color(0.1f, 1f, 0.7f) * 3f);

        // Particles and trails: "Sprites/Default" is unlit, uses vertex colors and works in URP and Built-in.
        Material particle = new Material(Shader.Find("Sprites/Default"));
        particle.mainTexture = softDotTexture;
        materials["Particle"] = SaveAsset(particle, MaterialsFolder + "/Particle.mat");
    }

    static Material Lit(string name, Color color, float metallic, float smoothness, Color emission,
        Texture2D texture = null, bool forceEmission = false)
    {
        Material material = new Material(LitShader);
        material.color = color;
        if (material.HasProperty("_BaseColor")) material.SetColor("_BaseColor", color);
        if (material.HasProperty("_Metallic")) material.SetFloat("_Metallic", metallic);
        if (material.HasProperty("_Smoothness")) material.SetFloat("_Smoothness", smoothness);  // URP
        if (material.HasProperty("_Glossiness")) material.SetFloat("_Glossiness", smoothness);  // Built-in
        if (texture != null)
        {
            material.mainTexture = texture;
            if (material.HasProperty("_BaseMap")) material.SetTexture("_BaseMap", texture);
        }
        if (emission.maxColorComponent > 0f || forceEmission)
        {
            material.EnableKeyword("_EMISSION");
            material.SetColor("_EmissionColor", emission);
            material.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
        }
        Material saved = SaveAsset(material, MaterialsFolder + "/" + name + ".mat");
        materials[name] = saved;
        return saved;
    }

    // ================================================================ meshes

    static void CreateMeshes()
    {
        crystalMesh = SaveAsset(BuildCrystalMesh(), ModelsFolder + "/CrystalGem.asset");
        spikeMesh = SaveAsset(BuildSpikeMesh(), ModelsFolder + "/Spike.asset");
        ringMesh = SaveAsset(BuildRingMesh(1f, 0.11f, 40, 10), ModelsFolder + "/Ring.asset");
    }

    /// <summary>A gem: 6 sides, pointed top and bottom, flat shaded.</summary>
    static Mesh BuildCrystalMesh()
    {
        const int sides = 6;
        Vector3 top = new Vector3(0f, 0.55f, 0f), bottom = new Vector3(0f, -0.45f, 0f);
        var vertices = new List<Vector3>();
        var triangles = new List<int>();
        for (int i = 0; i < sides; i++)
        {
            float a0 = i * Mathf.PI * 2f / sides, a1 = (i + 1) * Mathf.PI * 2f / sides;
            Vector3 p0 = new Vector3(Mathf.Cos(a0) * 0.32f, 0.1f, Mathf.Sin(a0) * 0.32f);
            Vector3 p1 = new Vector3(Mathf.Cos(a1) * 0.32f, 0.1f, Mathf.Sin(a1) * 0.32f);
            AddTriangle(vertices, triangles, top, p1, p0);
            AddTriangle(vertices, triangles, bottom, p0, p1);
        }
        return FinishMesh(vertices, triangles);
    }

    /// <summary>A square pyramid (one spike).</summary>
    static Mesh BuildSpikeMesh()
    {
        const float half = 0.16f, height = 0.6f;
        Vector3 apex = new Vector3(0f, height, 0f);
        Vector3 a = new Vector3(-half, 0f, -half), b = new Vector3(half, 0f, -half);
        Vector3 c = new Vector3(half, 0f, half), d = new Vector3(-half, 0f, half);
        var vertices = new List<Vector3>();
        var triangles = new List<int>();
        AddTriangle(vertices, triangles, apex, b, a);
        AddTriangle(vertices, triangles, apex, c, b);
        AddTriangle(vertices, triangles, apex, d, c);
        AddTriangle(vertices, triangles, apex, a, d);
        AddTriangle(vertices, triangles, a, b, c);
        AddTriangle(vertices, triangles, a, c, d);
        return FinishMesh(vertices, triangles);
    }

    /// <summary>A torus (ring) lying in the XZ plane.</summary>
    static Mesh BuildRingMesh(float radius, float thickness, int segments, int sides)
    {
        var vertices = new List<Vector3>();
        var normals = new List<Vector3>();
        var triangles = new List<int>();
        for (int s = 0; s <= segments; s++)
        {
            float a = s * Mathf.PI * 2f / segments;
            Vector3 center = new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a)) * radius;
            for (int k = 0; k <= sides; k++)
            {
                float b = k * Mathf.PI * 2f / sides;
                Vector3 normal = new Vector3(Mathf.Cos(a) * Mathf.Cos(b), Mathf.Sin(b), Mathf.Sin(a) * Mathf.Cos(b));
                vertices.Add(center + normal * thickness);
                normals.Add(normal);
            }
        }
        int row = sides + 1;
        for (int s = 0; s < segments; s++)
        {
            for (int k = 0; k < sides; k++)
            {
                int i0 = s * row + k, i1 = (s + 1) * row + k;
                triangles.Add(i0); triangles.Add(i0 + 1); triangles.Add(i1);
                triangles.Add(i1); triangles.Add(i0 + 1); triangles.Add(i1 + 1);
            }
        }
        Mesh mesh = new Mesh();
        mesh.SetVertices(vertices);
        mesh.SetNormals(normals);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateBounds();
        return mesh;
    }

    static void AddTriangle(List<Vector3> vertices, List<int> triangles, Vector3 a, Vector3 b, Vector3 c)
    {
        // Own vertices for every triangle = sharp, faceted look.
        int start = vertices.Count;
        vertices.Add(a); vertices.Add(b); vertices.Add(c);
        triangles.Add(start); triangles.Add(start + 1); triangles.Add(start + 2);
    }

    static Mesh FinishMesh(List<Vector3> vertices, List<int> triangles)
    {
        Mesh mesh = new Mesh();
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
        return mesh;
    }

    // ================================================================ particles

    static void CreateParticles()
    {
        collectBurst = SaveParticlePrefab(Burst("CollectBurst", new Color(1f, 0.4f, 0.9f), Color.white, 30, 2f, 5f, 0.08f, 0.2f, 0.4f, 0.8f, 0.3f, false));
        pickupBurst = SaveParticlePrefab(Burst("PickupBurst", new Color(0.3f, 1f, 0.5f), new Color(1f, 0.9f, 0.3f), 30, 2f, 5f, 0.1f, 0.22f, 0.4f, 0.9f, 0.2f, false));
        hitSparks = SaveParticlePrefab(Burst("HitSparks", new Color(1f, 0.55f, 0.1f), new Color(1f, 0.15f, 0.1f), 40, 3f, 8f, 0.05f, 0.16f, 0.25f, 0.6f, 1.2f, false));

        // Confetti is shown when the game is already paused (Time.timeScale = 0), so it uses unscaled time.
        GameObject confetti = Burst("VictoryConfetti", new Color(1f, 0.85f, 0.2f), new Color(0.3f, 0.9f, 1f), 180, 4f, 10f, 0.08f, 0.2f, 1.8f, 3f, 0.9f, true);
        ParticleSystem.MainModule confettiMain = confetti.GetComponent<ParticleSystem>().main;
        confettiMain.startColor = new ParticleSystem.MinMaxGradient(RainbowGradient()) { mode = ParticleSystemGradientMode.RandomColor };
        victoryConfetti = SaveParticlePrefab(confetti);

        ambientSparkles = CreateAmbientSparkles();
    }

    static Gradient RainbowGradient()
    {
        Gradient gradient = new Gradient();
        gradient.SetKeys(
            new[]
            {
                new GradientColorKey(new Color(1f, 0.3f, 0.5f), 0f),
                new GradientColorKey(new Color(1f, 0.85f, 0.2f), 0.33f),
                new GradientColorKey(new Color(0.3f, 1f, 0.6f), 0.66f),
                new GradientColorKey(new Color(0.3f, 0.7f, 1f), 1f)
            },
            new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) });
        return gradient;
    }

    static GameObject Burst(string name, Color colorA, Color colorB, int count, float speedMin, float speedMax,
        float sizeMin, float sizeMax, float lifeMin, float lifeMax, float gravity, bool unscaledTime)
    {
        GameObject go = new GameObject(name);
        ParticleSystem system = go.AddComponent<ParticleSystem>();
        system.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

        ParticleSystem.MainModule main = system.main;
        main.duration = 1f;
        main.loop = false;
        main.playOnAwake = true;
        main.startLifetime = new ParticleSystem.MinMaxCurve(lifeMin, lifeMax);
        main.startSpeed = new ParticleSystem.MinMaxCurve(speedMin, speedMax);
        main.startSize = new ParticleSystem.MinMaxCurve(sizeMin, sizeMax);
        main.startColor = new ParticleSystem.MinMaxGradient(colorA, colorB);
        main.gravityModifier = gravity;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.maxParticles = count + 20;
        main.useUnscaledTime = unscaledTime;
        main.stopAction = ParticleSystemStopAction.Destroy; // the object removes itself when done

        ParticleSystem.EmissionModule emission = system.emission;
        emission.rateOverTime = 0f;
        emission.SetBursts(new[] { new ParticleSystem.Burst(0f, (short)count) });

        ParticleSystem.ShapeModule shape = system.shape;
        shape.shapeType = ParticleSystemShapeType.Sphere;
        shape.radius = 0.25f;

        FadeOut(system);
        SetParticleRenderer(go);
        return go;
    }

    static void FadeOut(ParticleSystem system)
    {
        ParticleSystem.ColorOverLifetimeModule colorOverLifetime = system.colorOverLifetime;
        colorOverLifetime.enabled = true;
        Gradient fade = new Gradient();
        fade.SetKeys(
            new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
            new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 0.6f), new GradientAlphaKey(0f, 1f) });
        colorOverLifetime.color = fade;

        ParticleSystem.SizeOverLifetimeModule sizeOverLifetime = system.sizeOverLifetime;
        sizeOverLifetime.enabled = true;
        sizeOverLifetime.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0f, 1f, 1f, 0.2f));
    }

    static void SetParticleRenderer(GameObject go)
    {
        ParticleSystemRenderer renderer = go.GetComponent<ParticleSystemRenderer>();
        renderer.sharedMaterial = materials["Particle"];
        renderer.renderMode = ParticleSystemRenderMode.Billboard;
    }

    static ParticleSystem SaveParticlePrefab(GameObject go)
    {
        string path = ParticlesFolder + "/" + go.name + ".prefab";
        GameObject prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
        Object.DestroyImmediate(go);
        return prefab.GetComponent<ParticleSystem>();
    }

    /// <summary>Slow floating dots over the whole level - makes the scene feel alive.</summary>
    static GameObject CreateAmbientSparkles()
    {
        GameObject go = new GameObject("AmbientSparkles");
        ParticleSystem system = go.AddComponent<ParticleSystem>();
        system.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

        ParticleSystem.MainModule main = system.main;
        main.duration = 5f;
        main.loop = true;
        main.prewarm = true;
        main.startLifetime = new ParticleSystem.MinMaxCurve(5f, 8f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(0.1f, 0.4f);
        main.startSize = new ParticleSystem.MinMaxCurve(0.05f, 0.14f);
        main.startColor = new ParticleSystem.MinMaxGradient(new Color(0.5f, 0.7f, 1f, 0.8f), new Color(1f, 0.6f, 0.9f, 0.8f));
        main.gravityModifier = -0.02f;
        main.maxParticles = 300;

        ParticleSystem.EmissionModule emission = system.emission;
        emission.rateOverTime = 30f;

        ParticleSystem.ShapeModule shape = system.shape;
        shape.shapeType = ParticleSystemShapeType.Box;
        shape.scale = new Vector3(30f, 3f, 30f);
        shape.position = new Vector3(0f, 1.5f, 0f);

        FadeOut(system);
        SetParticleRenderer(go);

        string path = ParticlesFolder + "/AmbientSparkles.prefab";
        GameObject prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
        Object.DestroyImmediate(go);
        return prefab;
    }

    /// <summary>The swirl of the open portal (a looping effect inside the portal prefab).</summary>
    static ParticleSystem CreatePortalSwirl(Transform parent)
    {
        GameObject go = new GameObject("OpenEffect");
        go.transform.SetParent(parent, false);
        go.transform.localPosition = new Vector3(0f, PortalRingHeight, 0f);
        ParticleSystem system = go.AddComponent<ParticleSystem>();
        system.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

        ParticleSystem.MainModule main = system.main;
        main.duration = 2f;
        main.loop = true;
        main.playOnAwake = false; // ExitPortal starts it when the portal opens
        main.startLifetime = new ParticleSystem.MinMaxCurve(1f, 1.4f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(-1f, -0.6f); // negative = fly inwards, into the portal
        main.startSize = new ParticleSystem.MinMaxCurve(0.08f, 0.2f);
        main.startColor = new ParticleSystem.MinMaxGradient(new Color(0.3f, 1f, 0.85f), Color.white);
        main.maxParticles = 200;

        ParticleSystem.EmissionModule emission = system.emission;
        emission.rateOverTime = 40f;

        ParticleSystem.ShapeModule shape = system.shape;
        shape.shapeType = ParticleSystemShapeType.Circle; // a circle in the XY plane = the plane of the ring
        shape.radius = PortalRingRadius;
        shape.radiusThickness = 0f; // emit only from the edge

        FadeOut(system);
        SetParticleRenderer(go);
        return system;
    }
}
