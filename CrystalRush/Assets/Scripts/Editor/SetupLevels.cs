using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

/// <summary>
/// Setup step: the scenes. Level layouts are plain data below - change a number, run
/// "Crystal Rush > Build Game" again, and the level is rebuilt.
/// Coordinates: X = left/right, Z = forward (up on the screen). The level center is (0, 0).
/// </summary>
public static partial class CrystalRushSetup
{
    struct WallData
    {
        public float x, z, sizeX, sizeZ;
        public WallData(float x, float z, float sizeX, float sizeZ) { this.x = x; this.z = z; this.sizeX = sizeX; this.sizeZ = sizeZ; }
    }

    struct LaserData
    {
        public float x, z, length, rotationY, offTime, warningTime, onTime, startOffset;
        public LaserData(float x, float z, float length, float rotationY, float offTime, float warningTime, float onTime, float startOffset)
        {
            this.x = x; this.z = z; this.length = length; this.rotationY = rotationY;
            this.offTime = offTime; this.warningTime = warningTime; this.onTime = onTime; this.startOffset = startOffset;
        }
    }

    struct DroneData
    {
        public float x, z, moveX, moveZ, speed;
        public DroneData(float x, float z, float moveX, float moveZ, float speed) { this.x = x; this.z = z; this.moveX = moveX; this.moveZ = moveZ; this.speed = speed; }
    }

    struct SpikeData
    {
        public float x, z, hiddenTime, warningTime, upTime, startOffset;
        public SpikeData(float x, float z, float hiddenTime, float warningTime, float upTime, float startOffset)
        {
            this.x = x; this.z = z; this.hiddenTime = hiddenTime; this.warningTime = warningTime; this.upTime = upTime; this.startOffset = startOffset;
        }
    }

    class LevelData
    {
        public int number, size, lives;
        public float timeLimit;
        public Vector2 playerStart, portal;
        public Vector2[] crystals, extraLives, extraTime;
        public WallData[] walls;
        public LaserData[] lasers;
        public DroneData[] drones;
        public SpikeData[] spikes;
    }

    static Vector2 V(float x, float z) => new Vector2(x, z);

    // Each level is bigger, has more crystals and more (and faster) dangers.
    static readonly LevelData[] Levels =
    {
        new LevelData
        {
            number = 1, size = 20, timeLimit = 80f, lives = 3,
            playerStart = V(0f, -8f), portal = V(0f, 7.5f),
            crystals = new[] { V(-7f, -6f), V(7f, -6f), V(-7.5f, 0.5f), V(7.5f, 0.5f), V(-3f, 4f), V(3f, 4f), V(0f, -1f), V(0f, 2.5f) },
            walls = new[] { new WallData(-4.5f, -6.5f, 0.5f, 3f), new WallData(4.5f, -6.5f, 0.5f, 3f) },
            lasers = new[]
            {
                new LaserData(0f, -4f, 6f, 0f, 2.2f, 0.8f, 1.4f, 0f),
                new LaserData(0f, 6f, 5f, 0f, 2f, 0.8f, 1.4f, 1.6f)
            },
            drones = new[]
            {
                new DroneData(-6f, -1.8f, 12f, 0f, 2.5f)
            },
            spikes = new[]
            {
                new SpikeData(-4f, 1.5f, 2.2f, 0.9f, 1.3f, 0f),
                new SpikeData(4f, 1.5f, 2.2f, 0.9f, 1.3f, 1.8f)
            },
            extraLives = new[] { V(-8f, 8f) },
            extraTime = new[] { V(8f, -8.5f) },
        },
        new LevelData
        {
            number = 2, size = 24, timeLimit = 95f, lives = 3,
            playerStart = V(0f, -10f), portal = V(0f, 9.5f),
            crystals = new[] { V(-9.5f, -9.5f), V(9.5f, -9.5f), V(-9.5f, -1f), V(9.5f, -5.5f), V(-5f, -6f), V(5f, -1f), V(-2f, 2.5f), V(2.5f, 6.5f), V(-9.5f, 6f), V(9.5f, 6f), V(-6f, 9.5f), V(6f, 10f) },
            walls = new[] { new WallData(-5f, -3.5f, 6f, 0.5f), new WallData(5f, 3.5f, 6f, 0.5f), new WallData(0f, -1f, 0.5f, 3f), new WallData(-7f, 3.5f, 0.5f, 4f) },
            lasers = new[]
            {
                new LaserData(0f, -6.5f, 6f, 0f, 1.8f, 0.6f, 1.6f, 0f),
                new LaserData(-9.5f, 3.5f, 4.5f, 0f, 1.8f, 0.6f, 1.6f, 1f),
                new LaserData(6f, 7.5f, 5f, 0f, 1.6f, 0.6f, 1.8f, 2f)
            },
            drones = new[]
            {
                new DroneData(-10f, -7.8f, 8f, 0f, 3f),
                new DroneData(10f, 0.8f, -8f, 0f, 3f),
                new DroneData(-3f, 4.8f, 0f, 5f, 2.6f)
            },
            spikes = new[]
            {
                new SpikeData(5f, -9f, 2f, 0.8f, 1.4f, 0f),
                new SpikeData(-5f, -0.5f, 2f, 0.8f, 1.4f, 1f),
                new SpikeData(2.5f, 1.2f, 2f, 0.8f, 1.4f, 2f),
                new SpikeData(-6.5f, 7.5f, 2f, 0.8f, 1.4f, 0.5f)
            },
            extraLives = new[] { V(10.5f, 10.5f) },
            extraTime = new[] { V(-10.5f, -5.5f) },
        },
        new LevelData
        {
            number = 3, size = 28, timeLimit = 110f, lives = 3,
            playerStart = V(0f, -12f), portal = V(0f, 11.5f),
            crystals = new[] { V(-12f, -12f), V(12f, -12f), V(-6f, -9f), V(6f, -9f), V(-12f, -4f), V(12f, -4f), V(-3f, -4.5f), V(3f, -1f), V(-8f, 1f), V(8f, 2f), V(-12f, 6f), V(12f, 7f), V(-4f, 6f), V(4f, 9f), V(-9f, 12f), V(9f, 12f) },
            walls = new[] { new WallData(-7.5f, -6.5f, 7f, 0.5f), new WallData(7.5f, -6.5f, 7f, 0.5f), new WallData(-2f, -2f, 8f, 0.5f), new WallData(0f, 4.5f, 0.5f, 5f), new WallData(-8f, 8.5f, 6f, 0.5f), new WallData(8f, 4.5f, 6f, 0.5f), new WallData(-11f, -1f, 0.5f, 4f), new WallData(11f, 1f, 0.5f, 4f) },
            lasers = new[]
            {
                new LaserData(0f, -9.5f, 6f, 0f, 1.5f, 0.6f, 1.7f, 0f),
                new LaserData(-12.4f, -6.5f, 2.8f, 0f, 1.5f, 0.6f, 1.7f, 0.8f),
                new LaserData(12.4f, -6.5f, 2.8f, 0f, 1.5f, 0.6f, 1.7f, 1.6f),
                new LaserData(4.5f, -2f, 5f, 0f, 1.4f, 0.5f, 1.8f, 0.4f),
                new LaserData(-4f, 10.5f, 5f, 0f, 1.4f, 0.5f, 1.8f, 1.2f),
                new LaserData(4f, 10.5f, 5f, 0f, 1.4f, 0.5f, 1.8f, 2.2f)
            },
            drones = new[]
            {
                new DroneData(-11f, -10f, 9f, 0f, 3.6f),
                new DroneData(10.5f, -3.5f, -9f, 0f, 3.6f),
                new DroneData(-12.5f, 3.5f, 9f, 0f, 3.4f),
                new DroneData(2.5f, 1f, 0f, 6.5f, 3f),
                new DroneData(12.5f, 9.5f, -8f, 0f, 3.8f)
            },
            spikes = new[]
            {
                new SpikeData(-3f, -12f, 1.8f, 0.7f, 1.5f, 0f),
                new SpikeData(3f, -12f, 1.8f, 0.7f, 1.5f, 1f),
                new SpikeData(-8f, -2.5f, 1.8f, 0.7f, 1.5f, 0.5f),
                new SpikeData(7f, -1f, 1.8f, 0.7f, 1.5f, 1.5f),
                new SpikeData(-5f, 3f, 1.8f, 0.7f, 1.5f, 2f),
                new SpikeData(-4f, 12.3f, 1.8f, 0.7f, 1.5f, 0.8f),
                new SpikeData(8f, 11.5f, 1.8f, 0.7f, 1.5f, 0.3f)
            },
            extraLives = new[] { V(-12.5f, -12.5f), V(12.5f, 12.5f) },
            extraTime = new[] { V(-12.5f, 11.5f) },
        }
    };

    // ================================================================ level scene

    static void CreateLevelScene(LevelData data)
    {
        Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        SetupLighting();

        float half = data.size * 0.5f;

        // ---------- environment ----------
        Transform environment = new GameObject("Environment").transform;
        BuildFloor(environment, data.size);
        Transform walls = new GameObject("Walls").transform;
        walls.SetParent(environment, false);
        // Outer walls
        PlaceWall(walls, 0f, half + 0.25f, data.size + 1f, 0.5f, "Wall_North");
        PlaceWall(walls, 0f, -half - 0.25f, data.size + 1f, 0.5f, "Wall_South");
        PlaceWall(walls, half + 0.25f, 0f, 0.5f, data.size, "Wall_East");
        PlaceWall(walls, -half - 0.25f, 0f, 0.5f, data.size, "Wall_West");
        // Inner walls
        for (int i = 0; i < data.walls.Length; i++)
        {
            WallData w = data.walls[i];
            PlaceWall(walls, w.x, w.z, w.sizeX, w.sizeZ, "Wall_Inner_" + (i + 1));
        }
        GameObject sparkles = Place(ambientSparkles, environment, Vector3.zero);
        sparkles.transform.localScale = Vector3.one * (data.size / 30f);

        // ---------- crystals and bonuses ----------
        Transform crystals = new GameObject("Crystals").transform;
        for (int i = 0; i < data.crystals.Length; i++)
            Place(crystalPrefab, crystals, OnFloor(data.crystals[i], 0.8f), "Crystal_" + (i + 1));

        Transform pickups = new GameObject("Pickups").transform;
        foreach (Vector2 p in data.extraLives) Place(extraLifePrefab, pickups, OnFloor(p, 0.8f));
        foreach (Vector2 p in data.extraTime) Place(extraTimePrefab, pickups, OnFloor(p, 0.8f));

        // ---------- dangers ----------
        Transform hazards = new GameObject("Hazards").transform;
        for (int i = 0; i < data.lasers.Length; i++)
        {
            LaserData l = data.lasers[i];
            GameObject laser = Place(laserPrefab, hazards, OnFloor(V(l.x, l.z), 0f), "LaserBarrier_" + (i + 1));
            laser.transform.rotation = Quaternion.Euler(0f, l.rotationY, 0f);
            LaserBarrier component = laser.GetComponent<LaserBarrier>();
            Set(component, "length", l.length);
            Set(component, "offTime", l.offTime);
            Set(component, "warningTime", l.warningTime);
            Set(component, "onTime", l.onTime);
            Set(component, "startOffset", l.startOffset);
            component.ApplyLength(); // so the scene view shows the right length
        }
        for (int i = 0; i < data.drones.Length; i++)
        {
            DroneData d = data.drones[i];
            GameObject drone = Place(dronePrefab, hazards, OnFloor(V(d.x, d.z), 0.6f), "PatrolDrone_" + (i + 1));
            PatrolDrone component = drone.GetComponent<PatrolDrone>();
            Set(component, "patrolOffset", new Vector3(d.moveX, 0f, d.moveZ));
            Set(component, "speed", d.speed);
        }
        for (int i = 0; i < data.spikes.Length; i++)
        {
            SpikeData s = data.spikes[i];
            GameObject spike = Place(spikePrefab, hazards, OnFloor(V(s.x, s.z), 0f), "SpikeTrap_" + (i + 1));
            SpikeTrap component = spike.GetComponent<SpikeTrap>();
            Set(component, "hiddenTime", s.hiddenTime);
            Set(component, "warningTime", s.warningTime);
            Set(component, "upTime", s.upTime);
            Set(component, "startOffset", s.startOffset);
        }

        // ---------- portal, player, camera ----------
        Place(portalPrefab, null, OnFloor(data.portal, 0f));
        GameObject player = Place(playerPrefab, null, OnFloor(data.playerStart, 0.5f));
        CreateGameCamera(player.transform);

        // ---------- managers and UI ----------
        GameObject managerObject = new GameObject("GameManager");
        GameManager manager = managerObject.AddComponent<GameManager>();
        Set(manager, "levelNumber", data.number);
        Set(manager, "timeLimit", data.timeLimit);
        Set(manager, "startLives", data.lives);
        Set(manager, "victoryEffectPrefab", victoryConfetti);

        Place(audioManagerPrefab, null, Vector3.zero);
        Place(adManagerPrefab, null, Vector3.zero);
        Place(gameUIPrefab, null, Vector3.zero);

        SaveScene(scene, "Level" + data.number);
    }

    static Vector3 OnFloor(Vector2 point, float height) => new Vector3(point.x, height, point.y);

    static void BuildFloor(Transform parent, int size)
    {
        GameObject floor = new GameObject("Floor");
        floor.transform.SetParent(parent, false);
        // One big collider for the whole floor: the ball rolls smoothly, no bumps between tiles.
        BoxCollider collider = floor.AddComponent<BoxCollider>();
        collider.size = new Vector3(size, 1f, size);
        collider.center = new Vector3(0f, -0.5f, 0f);

        int tiles = size / 4;
        float start = -size * 0.5f + 2f;
        for (int x = 0; x < tiles; x++)
            for (int z = 0; z < tiles; z++)
                Place(floorTilePrefab, floor.transform, new Vector3(start + x * 4f, -0.25f, start + z * 4f), $"FloorTile_{x}_{z}");

        // Dark ground around the arena, so the camera never looks into emptiness.
        GameObject outer = Primitive(PrimitiveType.Cube, "OuterGround", parent, materials["OuterGround"], false);
        outer.transform.localScale = new Vector3(size * 4f, 0.1f, size * 4f);
        outer.transform.localPosition = new Vector3(0f, -0.6f, 0f);
    }

    static void PlaceWall(Transform parent, float x, float z, float sizeX, float sizeZ, string name)
    {
        GameObject wall = Place(wallPrefab, parent, new Vector3(x, 0.6f, z), name);
        wall.transform.localScale = new Vector3(sizeX, 1.2f, sizeZ);
    }

    static void CreateGameCamera(Transform target)
    {
        GameObject cameraObject = new GameObject("Main Camera");
        cameraObject.tag = "MainCamera";
        Camera camera = cameraObject.AddComponent<Camera>();
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0.03f, 0.03f, 0.08f);
        camera.fieldOfView = 50f;
        camera.nearClipPlane = 0.3f;
        camera.farClipPlane = 120f;
        cameraObject.AddComponent<AudioListener>();
        EnablePostProcessing(cameraObject);

        CameraFollow follow = cameraObject.AddComponent<CameraFollow>();
        Set(follow, "target", target);
        Vector3 offset = new Vector3(0f, 14f, -9.5f);
        cameraObject.transform.position = target.position + offset;
        cameraObject.transform.rotation = Quaternion.LookRotation(-offset.normalized, Vector3.up);
    }

    static void SetupLighting()
    {
        RenderSettings.ambientMode = AmbientMode.Flat;
        RenderSettings.ambientLight = new Color(0.32f, 0.33f, 0.45f);
        RenderSettings.fog = true;
        RenderSettings.fogMode = FogMode.Linear;
        RenderSettings.fogColor = new Color(0.03f, 0.03f, 0.08f);
        RenderSettings.fogStartDistance = 30f;
        RenderSettings.fogEndDistance = 70f;
        RenderSettings.skybox = null;

        GameObject sun = new GameObject("Directional Light");
        sun.transform.rotation = Quaternion.Euler(55f, -35f, 0f);
        Light light = sun.AddComponent<Light>();
        light.type = LightType.Directional;
        light.color = new Color(1f, 0.95f, 0.88f);
        light.intensity = 1.2f;
        light.shadows = LightShadows.Soft;

        // A soft blue light from the other side, so the shadows are not black.
        GameObject fill = new GameObject("Fill Light");
        fill.transform.rotation = Quaternion.Euler(35f, 145f, 0f);
        Light fillLight = fill.AddComponent<Light>();
        fillLight.type = LightType.Directional;
        fillLight.color = new Color(0.5f, 0.6f, 1f);
        fillLight.intensity = 0.35f;
        fillLight.shadows = LightShadows.None;

        AddGlobalVolume();
    }

    static void SaveScene(Scene scene, string name)
    {
        RecordPrefabInstanceChanges(scene);
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene, ScenesFolder + "/" + name + ".unity");
    }

    // ================================================================ main menu scene

    static void CreateMainMenuScene()
    {
        Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        SetupLighting();

        // A small 3D stage behind the menu: floor, a big spinning crystal and a few small ones.
        Transform stage = new GameObject("MenuStage").transform;
        BuildFloor(stage, 20);
        GameObject bigGem = MeshObject("BigCrystal", stage, crystalMesh, materials["Crystal"]);
        bigGem.transform.position = new Vector3(0f, 2.2f, 0f);
        bigGem.transform.localScale = Vector3.one * 3f;
        bigGem.AddComponent<Rotator>();
        AddPointLight(stage, "CrystalLight", new Color(1f, 0.4f, 0.85f), 4f, 9f, new Vector3(0f, 2.5f, -1.5f));

        Vector2[] small = { V(-5f, -1f), V(5f, -1f), V(-3.5f, 3f), V(3.5f, 3f), V(-7f, 4f), V(7f, 4f) };
        foreach (Vector2 p in small) Place(crystalPrefab, stage, OnFloor(p, 1f));
        Place(portalPrefab, stage, OnFloor(V(0f, 6f), 0f));
        Place(dronePrefab, stage, OnFloor(V(-6f, 1.5f), 0.6f));
        Place(ambientSparkles, stage, Vector3.zero);

        GameObject cameraObject = new GameObject("Main Camera");
        cameraObject.tag = "MainCamera";
        Camera camera = cameraObject.AddComponent<Camera>();
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0.03f, 0.03f, 0.08f);
        camera.fieldOfView = 50f;
        cameraObject.AddComponent<AudioListener>();
        EnablePostProcessing(cameraObject);
        cameraObject.transform.position = new Vector3(0f, 5.5f, -11f);
        cameraObject.transform.rotation = Quaternion.Euler(18f, 0f, 0f);

        Place(audioManagerPrefab, null, Vector3.zero);
        Place(adManagerPrefab, null, Vector3.zero);
        CreateMainMenuCanvas();

        SaveScene(scene, GameScenes.MainMenu);
    }
}
