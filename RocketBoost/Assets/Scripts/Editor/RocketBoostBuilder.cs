using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using Unity.Cinemachine;
using Object = UnityEngine.Object;

// Builds the whole game in the editor: materials, prefabs (Player Rocket, GameManager, AdManager),
// the scenes MainMenu, Over, Tunnel, Pistons and the Build Settings list.
//
// It runs by itself the first time the project is opened (when Assets/Scenes/MainMenu.unity does not exist).
// You can run it again from the menu: Rocket Boost → Rebuild scenes and prefabs.
// Everything it makes is normal Unity objects: after the build you can open the scenes and edit them by hand,
// exactly as in the book.
[InitializeOnLoad]
public static class RocketBoostBuilder
{
    const string ScenesDir = "Assets/Scenes";
    const string PrefabsDir = "Assets/Prefabs";
    const string MaterialsDir = "Assets/Materials";
    const string AudioDir = "Assets/Audio";
    const string TexturesDir = "Assets/Textures";

    static readonly string[] SceneNames = { "MainMenu", "Over", "Tunnel", "Pistons" };

    const float Depth = 2f;        // the thickness of level blocks along Z
    const float PadTop = 0.5f;     // the top of the launch/landing pads above their base

    static string ScenePath(string name) => ScenesDir + "/" + name + ".unity";

    static RocketBoostBuilder()
    {
        EditorApplication.delayCall += AutoBuild;
    }

    static void AutoBuild()
    {
        if (EditorApplication.isPlayingOrWillChangePlaymode) return;
        if (EditorApplication.isCompiling || EditorApplication.isUpdating)
        {
            EditorApplication.delayCall += AutoBuild;
            return;
        }
        if (File.Exists(ScenePath("MainMenu"))) return;

        Debug.Log("[Rocket Boost] First start: building materials, prefabs and scenes...");
        BuildEverything();
    }

    [MenuItem("Rocket Boost/Rebuild scenes and prefabs")]
    static void RebuildFromMenu()
    {
        bool ok = EditorUtility.DisplayDialog("Rocket Boost",
            "Пересоздать сцены MainMenu, Over, Tunnel, Pistons и префабы?\n" +
            "Ручные изменения в этих файлах будут потеряны.\n\n" +
            "Rebuild the scenes and prefabs? Manual changes in these files will be lost.",
            "OK", "Cancel");
        if (!ok) return;
        if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
        BuildEverything();
    }

    [MenuItem("Rocket Boost/Open main menu scene")]
    static void OpenMenuScene()
    {
        if (!File.Exists(ScenePath("MainMenu"))) { BuildEverything(); return; }
        if (EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())
            EditorSceneManager.OpenScene(ScenePath("MainMenu"));
    }

    // ------------------------------------------------------------------ the main sequence

    static void BuildEverything()
    {
        try
        {
            EditorUtility.DisplayProgressBar("Rocket Boost", "Materials...", 0.1f);
            EnsureFolder(ScenesDir);
            EnsureFolder(PrefabsDir);
            EnsureFolder(MaterialsDir);
            EnsureTag("Friendly");
            ConfigureTexture(TexturesDir + "/Particle.png", true);
            ConfigureTexture(TexturesDir + "/AdFlag.png", false);

            Mats mats = CreateMaterials();

            // An empty scene to build the prefabs in
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            EditorUtility.DisplayProgressBar("Rocket Boost", "Prefabs...", 0.3f);
            GameObject rocketPrefab = BuildRocketPrefab(mats);
            GameObject gameManagerPrefab = BuildGameManagerPrefab();
            GameObject adManagerPrefab = BuildAdManagerPrefab();
            Prefabs prefabs = new Prefabs { rocket = rocketPrefab, gameManager = gameManagerPrefab, adManager = adManagerPrefab };

            EditorUtility.DisplayProgressBar("Rocket Boost", "Scenes...", 0.5f);
            BuildMainMenu(mats, prefabs);
            BuildLevelOver(mats, prefabs);
            BuildLevelTunnel(mats, prefabs);
            BuildLevelPistons(mats, prefabs);

            EditorBuildSettings.scenes = SceneNames
                .Select(n => new EditorBuildSettingsScene(ScenePath(n), true))
                .ToArray();

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();

            EditorSceneManager.OpenScene(ScenePath("MainMenu"));
            Debug.Log("[Rocket Boost] Done! Scenes: MainMenu (0), Over (1), Tunnel (2), Pistons (3). Press ▶ Play.");
        }
        catch (Exception e)
        {
            Debug.LogError("[Rocket Boost] Build failed: " + e);
        }
        finally
        {
            EditorUtility.ClearProgressBar();
        }
    }

    // ------------------------------------------------------------------ materials

    class Mats
    {
        public Material launchPad, landingPad, ground, rock, boundary, moving, piston;
        public Material rocketBody, rocketRed, rocketWindow, rocketDark;
        public Material mountain, star, flag;
        public Material flame, puff, sparkle, explosion;
    }

    class Prefabs
    {
        public GameObject rocket, gameManager, adManager;
    }

    static Mats CreateMaterials()
    {
        Mats m = new Mats();
        m.launchPad = LitMat("LaunchPad", new Color(0.2f, 0.8f, 0.3f), 0.3f, new Color(0.02f, 0.15f, 0.04f));
        m.landingPad = LitMat("LandingPad", new Color(0.2f, 0.5f, 1f), 0.3f, new Color(0.03f, 0.12f, 0.35f));
        m.ground = LitMat("Ground", new Color(0.33f, 0.3f, 0.36f), 0.05f);
        m.rock = LitMat("Rock", new Color(0.5f, 0.5f, 0.56f), 0.1f);
        m.boundary = LitMat("Boundary", new Color(0.18f, 0.18f, 0.24f), 0.05f);
        m.moving = LitMat("MovingObstacle", new Color(1f, 0.55f, 0.1f), 0.4f, new Color(0.25f, 0.1f, 0f));
        m.piston = LitMat("Piston", new Color(0.85f, 0.35f, 0.1f), 0.6f);
        m.rocketBody = LitMat("RocketBody", new Color(0.92f, 0.92f, 0.96f), 0.6f);
        m.rocketRed = LitMat("RocketRed", new Color(0.85f, 0.15f, 0.15f), 0.5f);
        m.rocketWindow = LitMat("RocketWindow", new Color(0.3f, 0.7f, 1f), 0.9f, new Color(0.1f, 0.3f, 0.6f));
        m.rocketDark = LitMat("RocketNozzle", new Color(0.2f, 0.2f, 0.22f), 0.4f);
        m.mountain = LitMat("Mountain", new Color(0.16f, 0.14f, 0.28f), 0f);
        m.star = UnlitMat("Star", new Color(1f, 1f, 0.9f), null);
        m.flag = UnlitMat("AdFlagMaterial", Color.white, AssetDatabase.LoadAssetAtPath<Texture2D>(TexturesDir + "/AdFlag.png"));
        m.flame = ParticleMat("ParticleFlame", true);
        m.puff = ParticleMat("ParticlePuff", false);
        m.sparkle = ParticleMat("ParticleSparkle", true);
        m.explosion = ParticleMat("ParticleExplosion", true);
        return m;
    }

    static Shader FindShader(params string[] names)
    {
        foreach (string n in names)
        {
            Shader s = Shader.Find(n);
            if (s != null) return s;
        }
        return Shader.Find("Hidden/InternalErrorShader");
    }

    static Material GetOrCreateMaterial(string name, Shader shader, Material template = null)
    {
        string path = MaterialsDir + "/" + name + ".mat";
        Material m = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (m == null)
        {
            m = template != null ? new Material(template) : new Material(shader);
            if (template == null || m.shader != shader) m.shader = shader;
            AssetDatabase.CreateAsset(m, path);
        }
        else if (m.shader != shader)
        {
            m.shader = shader;
        }
        return m;
    }

    static Material LitMat(string name, Color color, float smoothness, Color? emission = null)
    {
        Shader sh = FindShader("Universal Render Pipeline/Lit", "Standard");
        Material m = GetOrCreateMaterial(name, sh);
        SetColor(m, color);
        if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", smoothness);
        if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", smoothness);
        if (emission.HasValue)
        {
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", emission.Value);
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
        }
        EditorUtility.SetDirty(m);
        return m;
    }

    static Material UnlitMat(string name, Color color, Texture texture)
    {
        Shader sh = FindShader("Universal Render Pipeline/Unlit", "Unlit/Texture", "Unlit/Color");
        Material m = GetOrCreateMaterial(name, sh);
        SetColor(m, color);
        if (texture != null) SetTexture(m, texture);
        EditorUtility.SetDirty(m);
        return m;
    }

    // A transparent particle material (URP Particles/Unlit). additive = glowing fire/sparks.
    static Material ParticleMat(string name, bool additive)
    {
        Shader sh = FindShader("Universal Render Pipeline/Particles/Unlit", "Particles/Standard Unlit",
                               "Legacy Shaders/Particles/Alpha Blended");
        Material template = AssetDatabase.LoadAssetAtPath<Material>(
            "Packages/com.unity.render-pipelines.universal/Runtime/Materials/ParticlesUnlit.mat");
        Material m = GetOrCreateMaterial(name, sh, template);
        SetColor(m, Color.white);
        SetTexture(m, AssetDatabase.LoadAssetAtPath<Texture2D>(TexturesDir + "/Particle.png"));

        m.SetFloat("_Surface", 1f);                 // Transparent
        m.SetFloat("_Blend", additive ? 2f : 0f);   // 2 = Additive, 0 = Alpha
        m.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
        m.SetFloat("_DstBlend", additive ? (float)UnityEngine.Rendering.BlendMode.One
                                         : (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
        m.SetFloat("_SrcBlendAlpha", (float)UnityEngine.Rendering.BlendMode.One);
        m.SetFloat("_DstBlendAlpha", additive ? (float)UnityEngine.Rendering.BlendMode.One
                                              : (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
        m.SetFloat("_ZWrite", 0f);
        m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
        m.SetOverrideTag("RenderType", "Transparent");
        m.renderQueue = (int)RenderQueue.Transparent;
        EditorUtility.SetDirty(m);
        return m;
    }

    static void SetColor(Material m, Color c)
    {
        if (m.HasProperty("_BaseColor")) m.SetColor("_BaseColor", c);
        if (m.HasProperty("_Color")) m.SetColor("_Color", c);
    }

    static void SetTexture(Material m, Texture t)
    {
        if (t == null) return;
        if (m.HasProperty("_BaseMap")) m.SetTexture("_BaseMap", t);
        if (m.HasProperty("_MainTex")) m.SetTexture("_MainTex", t);
    }

    // ------------------------------------------------------------------ prefabs

    static GameObject BuildRocketPrefab(Mats mats)
    {
        GameObject root = new GameObject("Player Rocket");

        Rigidbody rb = root.AddComponent<Rigidbody>();
        rb.mass = 1f;
        rb.linearDamping = 0.1f;
        rb.angularDamping = 0.5f;
        rb.constraints = RigidbodyConstraints.FreezePositionZ |
                         RigidbodyConstraints.FreezeRotationX |
                         RigidbodyConstraints.FreezeRotationY;
        rb.collisionDetectionMode = CollisionDetectionMode.Continuous;

        CapsuleCollider col = root.AddComponent<CapsuleCollider>();
        col.direction = 1; // Y axis
        col.radius = 0.35f;
        col.height = 2.5f;
        col.center = new Vector3(0f, 0.13f, 0f); // from y = -1.12 (nozzle) to y = 1.38 (nose tip)

        AudioSource audio = root.AddComponent<AudioSource>();
        audio.playOnAwake = false;
        audio.spatialBlend = 0f;

        // The look: everything is made of primitives, the colliders of the parts are removed
        Part(root.transform, PrimitiveType.Cylinder, "Body", new Vector3(0f, 0f, 0f), new Vector3(0.6f, 1f, 0.6f), Vector3.zero, mats.rocketBody);
        Part(root.transform, PrimitiveType.Sphere, "Nose", new Vector3(0f, 1f, 0f), new Vector3(0.6f, 0.8f, 0.6f), Vector3.zero, mats.rocketRed);
        Part(root.transform, PrimitiveType.Sphere, "Window", new Vector3(0f, 0.4f, -0.26f), new Vector3(0.3f, 0.3f, 0.12f), Vector3.zero, mats.rocketWindow);
        Part(root.transform, PrimitiveType.Cube, "Fin Left", new Vector3(-0.38f, -0.72f, 0f), new Vector3(0.22f, 0.55f, 0.08f), new Vector3(0f, 0f, -12f), mats.rocketRed);
        Part(root.transform, PrimitiveType.Cube, "Fin Right", new Vector3(0.38f, -0.72f, 0f), new Vector3(0.22f, 0.55f, 0.08f), new Vector3(0f, 0f, 12f), mats.rocketRed);
        Part(root.transform, PrimitiveType.Cylinder, "Nozzle", new Vector3(0f, -1.05f, 0f), new Vector3(0.38f, 0.08f, 0.38f), Vector3.zero, mats.rocketDark);

        // Particles (the book, Part 5 and 8.2)
        ParticleSystem mainEngine = MakeParticles(root.transform, "Main Engine Particles",
            new Vector3(0f, -1.15f, 0f), new Vector3(90f, 0f, 0f), mats.flame, SetupFlame);
        ParticleSystem rightThrust = MakeParticles(root.transform, "Right Thrust Particles",
            new Vector3(0.3f, 0.85f, 0f), new Vector3(0f, 90f, 0f), mats.puff, SetupPuff);
        ParticleSystem leftThrust = MakeParticles(root.transform, "Left Thrust Particles",
            new Vector3(-0.3f, 0.85f, 0f), new Vector3(0f, -90f, 0f), mats.puff, SetupPuff);
        ParticleSystem success = MakeParticles(root.transform, "Success Particles",
            Vector3.zero, Vector3.zero, mats.sparkle, SetupSparkle);
        ParticleSystem crash = MakeParticles(root.transform, "Crash Particles",
            Vector3.zero, Vector3.zero, mats.explosion, SetupExplosion);

        // The ad flag (the ads guide, Part 12). It hangs behind the rocket (Z = 1.2), so it does not cover the flame.
        GameObject flagGo = new GameObject("AdFlag");
        flagGo.transform.SetParent(root.transform, false);
        flagGo.transform.localPosition = new Vector3(0f, -1.0f, 1.2f);
        AdFlag flag = flagGo.AddComponent<AdFlag>();
        SetRef(flag, "adTexture", AssetDatabase.LoadAssetAtPath<Texture2D>(TexturesDir + "/AdFlag.png"));
        SetRef(flag, "flagMaterial", mats.flag);

        AudioClip engine = AssetDatabase.LoadAssetAtPath<AudioClip>(AudioDir + "/Engine.wav");
        AudioClip crashSfx = AssetDatabase.LoadAssetAtPath<AudioClip>(AudioDir + "/Crash.wav");
        AudioClip successSfx = AssetDatabase.LoadAssetAtPath<AudioClip>(AudioDir + "/Success.wav");

        Movement movement = root.AddComponent<Movement>();
        movement.ResetBindingsToDefault();
        SetRef(movement, "mainEngineSFX", engine);
        SetRef(movement, "mainEngineParticles", mainEngine);
        SetRef(movement, "rightThrustParticles", rightThrust);
        SetRef(movement, "leftThrustParticles", leftThrust);

        CollisionHandler handler = root.AddComponent<CollisionHandler>();
        SetRef(handler, "successSFX", successSfx);
        SetRef(handler, "crashSFX", crashSfx);
        SetRef(handler, "successParticles", success);
        SetRef(handler, "crashParticles", crash);

        return SavePrefab(root, "Player Rocket");
    }

    static GameObject BuildGameManagerPrefab()
    {
        GameObject go = new GameObject("GameManager");
        go.AddComponent<GameManager>();
        go.AddComponent<GameUI>();
        go.AddComponent<TouchControls>();
        return SavePrefab(go, "GameManager");
    }

    static GameObject BuildAdManagerPrefab()
    {
        // The name must be exactly "AdManager": JavaScript calls SendMessage('AdManager', ...)
        GameObject go = new GameObject("AdManager");
        go.AddComponent<AdManager>();
        return SavePrefab(go, "AdManager");
    }

    static GameObject SavePrefab(GameObject go, string name)
    {
        string path = PrefabsDir + "/" + name + ".prefab";
        GameObject prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
        Object.DestroyImmediate(go);
        return prefab;
    }

    static GameObject Part(Transform parent, PrimitiveType type, string name, Vector3 pos, Vector3 scale, Vector3 euler, Material mat)
    {
        GameObject go = GameObject.CreatePrimitive(type);
        go.name = name;
        Object.DestroyImmediate(go.GetComponent<Collider>());
        go.transform.SetParent(parent, false);
        go.transform.localPosition = pos;
        go.transform.localScale = scale;
        go.transform.localEulerAngles = euler;
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        return go;
    }

    // ------------------------------------------------------------------ particle systems

    static ParticleSystem MakeParticles(Transform parent, string name, Vector3 pos, Vector3 euler, Material mat, Action<ParticleSystem> setup)
    {
        GameObject go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.transform.localPosition = pos;
        go.transform.localEulerAngles = euler;
        ParticleSystem ps = go.AddComponent<ParticleSystem>();
        ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

        ParticleSystem.MainModule main = ps.main;
        main.playOnAwake = false; // the scripts turn the particles on and off
        main.simulationSpace = ParticleSystemSimulationSpace.World;

        ParticleSystemRenderer r = go.GetComponent<ParticleSystemRenderer>();
        r.sharedMaterial = mat;
        r.renderMode = ParticleSystemRenderMode.Billboard;
        r.shadowCastingMode = ShadowCastingMode.Off;
        r.receiveShadows = false;

        setup(ps);
        return ps;
    }

    static Gradient FadeGradient(Color from, Color to)
    {
        Gradient g = new Gradient();
        g.SetKeys(
            new[] { new GradientColorKey(from, 0f), new GradientColorKey(to, 1f) },
            new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(0.8f, 0.5f), new GradientAlphaKey(0f, 1f) });
        return g;
    }

    static void SetupFlame(ParticleSystem ps)
    {
        ParticleSystem.MainModule main = ps.main;
        main.loop = true;
        main.duration = 1f;
        main.startLifetime = new ParticleSystem.MinMaxCurve(0.25f, 0.45f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(5f, 8f);
        main.startSize = new ParticleSystem.MinMaxCurve(0.25f, 0.45f);
        main.startColor = new ParticleSystem.MinMaxGradient(new Color(1f, 0.9f, 0.4f), new Color(1f, 0.45f, 0.1f));
        main.maxParticles = 300;

        ParticleSystem.EmissionModule emission = ps.emission;
        emission.rateOverTime = 80f;

        ParticleSystem.ShapeModule shape = ps.shape;
        shape.shapeType = ParticleSystemShapeType.Cone;
        shape.angle = 10f;
        shape.radius = 0.12f;

        ParticleSystem.ColorOverLifetimeModule col = ps.colorOverLifetime;
        col.enabled = true;
        col.color = new ParticleSystem.MinMaxGradient(FadeGradient(Color.white, new Color(1f, 0.25f, 0.05f)));

        ParticleSystem.SizeOverLifetimeModule size = ps.sizeOverLifetime;
        size.enabled = true;
        size.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0f, 1f, 1f, 0.3f));
    }

    static void SetupPuff(ParticleSystem ps)
    {
        ParticleSystem.MainModule main = ps.main;
        main.loop = true;
        main.duration = 1f;
        main.startLifetime = new ParticleSystem.MinMaxCurve(0.15f, 0.3f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(2.5f, 4f);
        main.startSize = new ParticleSystem.MinMaxCurve(0.12f, 0.22f);
        main.startColor = new ParticleSystem.MinMaxGradient(new Color(0.85f, 0.92f, 1f, 0.9f));
        main.maxParticles = 100;

        ParticleSystem.EmissionModule emission = ps.emission;
        emission.rateOverTime = 50f;

        ParticleSystem.ShapeModule shape = ps.shape;
        shape.shapeType = ParticleSystemShapeType.Cone;
        shape.angle = 15f;
        shape.radius = 0.05f;

        ParticleSystem.ColorOverLifetimeModule col = ps.colorOverLifetime;
        col.enabled = true;
        col.color = new ParticleSystem.MinMaxGradient(FadeGradient(Color.white, new Color(0.7f, 0.8f, 1f)));
    }

    static void SetupSparkle(ParticleSystem ps)
    {
        ParticleSystem.MainModule main = ps.main;
        main.loop = false;
        main.duration = 1.5f;
        main.startLifetime = new ParticleSystem.MinMaxCurve(0.8f, 1.6f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(3f, 8f);
        main.startSize = new ParticleSystem.MinMaxCurve(0.15f, 0.3f);
        main.gravityModifier = 0.3f;
        main.maxParticles = 300;

        Gradient rainbow = new Gradient();
        rainbow.SetKeys(
            new[]
            {
                new GradientColorKey(new Color(1f, 0.3f, 0.3f), 0f),
                new GradientColorKey(new Color(1f, 0.9f, 0.2f), 0.25f),
                new GradientColorKey(new Color(0.3f, 1f, 0.4f), 0.5f),
                new GradientColorKey(new Color(0.3f, 0.7f, 1f), 0.75f),
                new GradientColorKey(new Color(0.9f, 0.4f, 1f), 1f),
            },
            new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) });
        ParticleSystem.MinMaxGradient startColor = new ParticleSystem.MinMaxGradient(rainbow);
        startColor.mode = ParticleSystemGradientMode.RandomColor;
        main.startColor = startColor;

        ParticleSystem.EmissionModule emission = ps.emission;
        emission.rateOverTime = 0f;
        emission.SetBursts(new[] { new ParticleSystem.Burst(0f, (short)120) });

        ParticleSystem.ShapeModule shape = ps.shape;
        shape.shapeType = ParticleSystemShapeType.Sphere;
        shape.radius = 0.5f;

        ParticleSystem.ColorOverLifetimeModule col = ps.colorOverLifetime;
        col.enabled = true;
        col.color = new ParticleSystem.MinMaxGradient(FadeGradient(Color.white, Color.white));
    }

    static void SetupExplosion(ParticleSystem ps)
    {
        ParticleSystem.MainModule main = ps.main;
        main.loop = false;
        main.duration = 1f;
        main.startLifetime = new ParticleSystem.MinMaxCurve(0.5f, 1.2f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(4f, 10f);
        main.startSize = new ParticleSystem.MinMaxCurve(0.3f, 0.8f);
        main.startColor = new ParticleSystem.MinMaxGradient(new Color(1f, 0.75f, 0.2f), new Color(1f, 0.2f, 0.05f));
        main.gravityModifier = 0.5f;
        main.maxParticles = 300;

        ParticleSystem.EmissionModule emission = ps.emission;
        emission.rateOverTime = 0f;
        emission.SetBursts(new[] { new ParticleSystem.Burst(0f, (short)150) });

        ParticleSystem.ShapeModule shape = ps.shape;
        shape.shapeType = ParticleSystemShapeType.Sphere;
        shape.radius = 0.4f;

        ParticleSystem.ColorOverLifetimeModule col = ps.colorOverLifetime;
        col.enabled = true;
        col.color = new ParticleSystem.MinMaxGradient(FadeGradient(Color.white, new Color(0.3f, 0.3f, 0.3f)));

        ParticleSystem.SizeOverLifetimeModule size = ps.sizeOverLifetime;
        size.enabled = true;
        size.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0f, 0.6f, 1f, 1.4f));
    }

    // ------------------------------------------------------------------ scenes

    static Scene NewScene(Color background, Vector3 cameraPos, out Camera camera)
    {
        Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

        RenderSettings.skybox = null;
        RenderSettings.ambientMode = AmbientMode.Flat;
        RenderSettings.ambientLight = new Color(0.36f, 0.38f, 0.5f);
        RenderSettings.fog = false;

        GameObject lightGo = new GameObject("Directional Light");
        Light light = lightGo.AddComponent<Light>();
        light.type = LightType.Directional;
        light.intensity = 1.3f;
        light.color = new Color(1f, 0.96f, 0.9f);
        light.shadows = LightShadows.Soft;
        lightGo.transform.rotation = Quaternion.Euler(45f, -30f, 0f);

        GameObject camGo = new GameObject("Main Camera");
        camGo.tag = "MainCamera";
        camera = camGo.AddComponent<Camera>();
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = background;
        camera.fieldOfView = 45f;
        camera.nearClipPlane = 0.3f;
        camera.farClipPlane = 300f;
        camGo.AddComponent<AudioListener>();
        camGo.transform.position = cameraPos;

        return scene;
    }

    // The common part of every level: camera, Cinemachine, the rocket on the launch pad, managers, decorations
    static GameObject SetupLevel(Mats mats, Prefabs prefabs, Vector2 launchPad, float minX, float maxX, float ceilingY, int seed)
    {
        Vector3 rocketPos = new Vector3(launchPad.x, launchPad.y + PadTop / 2f + 1.14f, 0f);
        Vector3 offset = new Vector3(0f, 2.5f, -22f);

        Camera cam;
        NewScene(new Color(0.04f, 0.06f, 0.14f), rocketPos + offset, out cam);
        cam.gameObject.AddComponent<CinemachineBrain>();

        // The launch pad (tag Friendly)
        Box("Launch Pad", launchPad, new Vector2(3f, PadTop), mats.launchPad, "Friendly");

        // The rocket (a prefab instance)
        GameObject rocket = (GameObject)PrefabUtility.InstantiatePrefab(prefabs.rocket);
        rocket.transform.position = rocketPos;

        // The follow camera (the book, Part 6)
        GameObject vcamGo = new GameObject("CinemachineCamera");
        vcamGo.transform.position = rocketPos + offset;
        CinemachineCamera vcam = vcamGo.AddComponent<CinemachineCamera>();
        vcam.Follow = rocket.transform;
        vcam.Lens.FieldOfView = 45f;
        vcam.Lens.NearClipPlane = 0.3f;
        vcam.Lens.FarClipPlane = 300f;
        CinemachineFollow follow = vcamGo.AddComponent<CinemachineFollow>();
        follow.FollowOffset = offset;
        Unity.Cinemachine.TargetTracking.TrackerSettings tracker = follow.TrackerSettings;
        tracker.BindingMode = Unity.Cinemachine.TargetTracking.BindingMode.WorldSpace;
        tracker.PositionDamping = new Vector3(0.6f, 0.6f, 0f);
        follow.TrackerSettings = tracker;

        // Managers (prefabs: the same objects in every scene)
        PrefabUtility.InstantiatePrefab(prefabs.gameManager);
        PrefabUtility.InstantiatePrefab(prefabs.adManager);

        // Borders: walls on the left and right, a ceiling (touching them is a crash)
        float midX = (minX + maxX) / 2f;
        float width = maxX - minX;
        Box("Wall Left", new Vector2(minX - 1f, ceilingY / 2f), new Vector2(2f, ceilingY + 12f), mats.boundary);
        Box("Wall Right", new Vector2(maxX + 1f, ceilingY / 2f), new Vector2(2f, ceilingY + 12f), mats.boundary);
        Box("Ceiling", new Vector2(midX, ceilingY + 1f), new Vector2(width + 4f, 2f), mats.boundary);

        Decorations(mats, minX, maxX, ceilingY, seed);
        return rocket;
    }

    static GameObject Box(string name, Vector2 center, Vector2 size, Material mat, string tag = null, float depth = Depth)
    {
        GameObject go = GameObject.CreatePrimitive(PrimitiveType.Cube);
        go.name = name;
        go.transform.position = new Vector3(center.x, center.y, 0f);
        go.transform.localScale = new Vector3(size.x, size.y, depth);
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        if (!string.IsNullOrEmpty(tag)) go.tag = tag;
        return go;
    }

    // A pad standing on the ground: base is the ground height, the pad top is base + PadTop
    static Vector2 PadCenter(float x, float baseY) => new Vector2(x, baseY + PadTop / 2f);

    static GameObject Moving(string name, Vector2 center, Vector2 size, Material mat, Vector3 movement, float speed, float depth = 1.8f)
    {
        GameObject go = Box(name, center, size, mat, null, depth);
        Oscillator osc = go.AddComponent<Oscillator>();
        SetVector3(osc, "movementVector", movement);
        SetFloat(osc, "speed", speed);
        return go;
    }

    // Background mountains and stars, without colliders: they do not touch the game
    static void Decorations(Mats mats, float minX, float maxX, float ceilingY, int seed)
    {
        GameObject parent = new GameObject("Decorations");
        System.Random rnd = new System.Random(seed);

        for (float x = minX - 6f; x < maxX + 6f; x += 7f + (float)rnd.NextDouble() * 4f)
        {
            float s = 6f + (float)rnd.NextDouble() * 8f;
            GameObject m = Part(parent.transform, PrimitiveType.Cube, "Mountain",
                new Vector3(x, -1f, 6f + (float)rnd.NextDouble() * 3f), new Vector3(s, s, 1f), new Vector3(0f, 0f, 45f), mats.mountain);
            m.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
        }

        for (int i = 0; i < 70; i++)
        {
            float x = Mathf.Lerp(minX - 25f, maxX + 25f, (float)rnd.NextDouble());
            float y = Mathf.Lerp(2f, ceilingY + 20f, (float)rnd.NextDouble());
            float s = 0.08f + (float)rnd.NextDouble() * 0.18f;
            GameObject star = Part(parent.transform, PrimitiveType.Sphere, "Star",
                new Vector3(x, y, 25f + (float)rnd.NextDouble() * 10f), Vector3.one * s, Vector3.zero, mats.star);
            star.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
        }
    }

    static void SaveScene(string name)
    {
        Scene scene = SceneManager.GetActiveScene();
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene, ScenePath(name));
    }

    // Scene 0: the main menu
    static void BuildMainMenu(Mats mats, Prefabs prefabs)
    {
        Camera cam;
        NewScene(new Color(0.04f, 0.06f, 0.14f), new Vector3(0f, 0.6f, -8f), out cam);

        GameObject rocket = (GameObject)PrefabUtility.InstantiatePrefab(prefabs.rocket);
        rocket.transform.position = new Vector3(3.6f, -0.2f, 0f);
        rocket.transform.rotation = Quaternion.Euler(0f, 0f, -12f);
        Rigidbody rb = rocket.GetComponent<Rigidbody>();
        rb.isKinematic = true;
        rocket.GetComponent<Movement>().enabled = false;
        rocket.GetComponent<CollisionHandler>().enabled = false;
        PrefabUtility.RecordPrefabInstancePropertyModifications(rb);
        PrefabUtility.RecordPrefabInstancePropertyModifications(rocket.GetComponent<Movement>());
        PrefabUtility.RecordPrefabInstancePropertyModifications(rocket.GetComponent<CollisionHandler>());
        PrefabUtility.RecordPrefabInstancePropertyModifications(rocket.transform);

        GameObject menu = new GameObject("Main Menu");
        MainMenu mainMenu = menu.AddComponent<MainMenu>();
        SetRef(mainMenu, "showcase", rocket.transform);
        menu.AddComponent<QuitApplication>();

        PrefabUtility.InstantiatePrefab(prefabs.adManager);
        Decorations(mats, -12f, 12f, 6f, 1);

        SaveScene("MainMenu");
    }

    // Level 1 "Over the Hill": fly over a mountain
    static void BuildLevelOver(Mats mats, Prefabs prefabs)
    {
        SetupLevel(mats, prefabs, PadCenter(0f, 0f), -10f, 34f, 22f, 11);

        Box("Ground", new Vector2(12f, -5f), new Vector2(60f, 10f), mats.ground);
        Box("Hill", new Vector2(11f, 3f), new Vector2(5f, 6f), mats.rock);
        Box("Hill Top", new Vector2(11f, 7f), new Vector2(3f, 2f), mats.rock);
        Box("Rock", new Vector2(16.5f, 1.5f), new Vector2(2.5f, 3f), mats.rock);
        Moving("Floating Block", new Vector2(6f, 9f), new Vector2(1.5f, 1.5f), mats.moving, new Vector3(0f, 4f, 0f), 0.3f);
        Box("Landing Pad", PadCenter(24f, 0f), new Vector2(3.5f, PadTop), mats.landingPad, "Finish");

        SaveScene("Over");
    }

    // Level 2 "Tunnel": through a low tunnel with a moving block, to a pad on a pillar
    static void BuildLevelTunnel(Mats mats, Prefabs prefabs)
    {
        SetupLevel(mats, prefabs, PadCenter(0f, 0f), -10f, 40f, 22f, 22);

        Box("Ground", new Vector2(15f, -5f), new Vector2(66f, 10f), mats.ground);
        Box("Tunnel Roof", new Vector2(16f, 15f), new Vector2(20f, 14f), mats.rock);     // from y = 8 up to the ceiling
        Box("Stalagmite", new Vector2(11f, 1.75f), new Vector2(1.5f, 3.5f), mats.rock);
        Box("Stalactite", new Vector2(17f, 6.25f), new Vector2(1.5f, 3.5f), mats.rock);
        Moving("Moving Block", new Vector2(22.5f, 1.5f), new Vector2(1.5f, 3f), mats.moving, new Vector3(0f, 3.5f, 0f), 0.4f);
        Box("Pillar", new Vector2(32f, 2f), new Vector2(3f, 4f), mats.rock);
        Box("Landing Pad", PadCenter(32f, 4f), new Vector2(3.5f, PadTop), mats.landingPad, "Finish");

        SaveScene("Tunnel");
    }

    // Level 3 "Pistons": pistons go up and down and block the way
    static void BuildLevelPistons(Mats mats, Prefabs prefabs)
    {
        SetupLevel(mats, prefabs, PadCenter(0f, 0f), -8f, 38f, 14f, 33);

        Box("Ground", new Vector2(15f, -5f), new Vector2(62f, 10f), mats.ground);
        Box("Ceiling Block", new Vector2(15f, 19.5f), new Vector2(50f, 9f), mats.boundary);   // hides the tops of the pistons
        // Floor pistons go up, ceiling pistons go down. The hidden ends stay inside the ground / the ceiling.
        Moving("Piston 1", new Vector2(7f, -3f), new Vector2(2f, 12f), mats.piston, new Vector3(0f, 6f, 0f), 0.35f);
        Moving("Piston 2", new Vector2(13f, 17f), new Vector2(2f, 14f), mats.piston, new Vector3(0f, -6f, 0f), 0.3f);
        Moving("Piston 3", new Vector2(19f, -3f), new Vector2(2f, 12f), mats.piston, new Vector3(0f, 7f, 0f), 0.45f);
        Moving("Piston 4", new Vector2(25f, 17f), new Vector2(2f, 14f), mats.piston, new Vector3(0f, -7f, 0f), 0.4f);
        Box("Landing Pad", PadCenter(31f, 0f), new Vector2(3.5f, PadTop), mats.landingPad, "Finish");

        SaveScene("Pistons");
    }

    // ------------------------------------------------------------------ helpers

    static void SetRef(Object target, string field, Object value)
    {
        SerializedObject so = new SerializedObject(target);
        SerializedProperty p = so.FindProperty(field);
        if (p == null) { Debug.LogWarning("[Rocket Boost] Field not found: " + target.GetType().Name + "." + field); return; }
        p.objectReferenceValue = value;
        so.ApplyModifiedPropertiesWithoutUndo();
    }

    static void SetFloat(Object target, string field, float value)
    {
        SerializedObject so = new SerializedObject(target);
        SerializedProperty p = so.FindProperty(field);
        if (p == null) { Debug.LogWarning("[Rocket Boost] Field not found: " + field); return; }
        p.floatValue = value;
        so.ApplyModifiedPropertiesWithoutUndo();
    }

    static void SetVector3(Object target, string field, Vector3 value)
    {
        SerializedObject so = new SerializedObject(target);
        SerializedProperty p = so.FindProperty(field);
        if (p == null) { Debug.LogWarning("[Rocket Boost] Field not found: " + field); return; }
        p.vector3Value = value;
        so.ApplyModifiedPropertiesWithoutUndo();
    }

    static void EnsureFolder(string path)
    {
        if (AssetDatabase.IsValidFolder(path)) return;
        string parent = Path.GetDirectoryName(path).Replace('\\', '/');
        string leaf = Path.GetFileName(path);
        if (!AssetDatabase.IsValidFolder(parent)) EnsureFolder(parent);
        AssetDatabase.CreateFolder(parent, leaf);
    }

    static void EnsureTag(string tag)
    {
        Object[] assets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TagManager.asset");
        if (assets == null || assets.Length == 0) return;
        SerializedObject tagManager = new SerializedObject(assets[0]);
        SerializedProperty tags = tagManager.FindProperty("tags");
        for (int i = 0; i < tags.arraySize; i++)
        {
            if (tags.GetArrayElementAtIndex(i).stringValue == tag) return;
        }
        tags.InsertArrayElementAtIndex(tags.arraySize);
        tags.GetArrayElementAtIndex(tags.arraySize - 1).stringValue = tag;
        tagManager.ApplyModifiedPropertiesWithoutUndo();
    }

    static void ConfigureTexture(string path, bool transparent)
    {
        TextureImporter ti = AssetImporter.GetAtPath(path) as TextureImporter;
        if (ti == null) return;
        bool changed = false;
        if (ti.wrapMode != TextureWrapMode.Clamp) { ti.wrapMode = TextureWrapMode.Clamp; changed = true; }
        if (transparent && !ti.alphaIsTransparency) { ti.alphaIsTransparency = true; changed = true; }
        if (changed) ti.SaveAndReimport();
    }
}
