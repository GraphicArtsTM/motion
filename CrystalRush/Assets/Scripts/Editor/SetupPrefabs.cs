using UnityEditor;
using UnityEngine;

/// <summary>
/// Setup step: game prefabs (Assets/Prefabs). Each one is built from primitives and our meshes,
/// gets its colliders, tag and script, and its script fields are filled in.
/// </summary>
public static partial class CrystalRushSetup
{
    const float PortalRingHeight = 1.3f;
    const float PortalRingRadius = 1.1f;

    static GameObject playerPrefab, crystalPrefab, extraLifePrefab, extraTimePrefab;
    static GameObject laserPrefab, dronePrefab, spikePrefab, portalPrefab;
    static GameObject wallPrefab, floorTilePrefab, audioManagerPrefab, adManagerPrefab;

    static void CreatePrefabs()
    {
        playerPrefab = CreatePlayer();
        crystalPrefab = CreateCrystal();
        extraLifePrefab = CreateExtraLife();
        extraTimePrefab = CreateExtraTime();
        laserPrefab = CreateLaser();
        dronePrefab = CreateDrone();
        spikePrefab = CreateSpikeTrap();
        portalPrefab = CreatePortal();
        wallPrefab = CreateWall();
        floorTilePrefab = CreateFloorTile();
        audioManagerPrefab = CreateAudioManager();
        adManagerPrefab = CreateAdManager();
    }

    // ---------------------------------------------------------------- player

    static GameObject CreatePlayer()
    {
        GameObject root = new GameObject("Player");
        root.tag = "Player";

        SphereCollider collider = root.AddComponent<SphereCollider>();
        collider.radius = 0.5f;

        Rigidbody body = root.AddComponent<Rigidbody>();
        body.mass = 1f;
        body.linearDamping = 0.3f;
        body.angularDamping = 0.5f;
        body.interpolation = RigidbodyInterpolation.Interpolate;
        body.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic; // fast dash must not go through walls

        GameObject ball = Primitive(PrimitiveType.Sphere, "Body", root.transform, materials["Player"], false);
        GameObject band = MeshObject("Band", ball.transform, ringMesh, materials["PlayerBand"]);
        band.transform.localScale = Vector3.one * 0.5f;
        band.transform.localRotation = Quaternion.Euler(0f, 0f, 90f); // shows that the ball is rolling

        AddPointLight(root.transform, "Glow", new Color(0.3f, 0.85f, 1f), 2f, 4f, new Vector3(0f, 0.6f, 0f));

        GameObject trailObject = new GameObject("DashTrail");
        trailObject.transform.SetParent(root.transform, false);
        TrailRenderer trail = trailObject.AddComponent<TrailRenderer>();
        trail.time = 0.3f;
        trail.widthMultiplier = 0.9f;
        trail.widthCurve = AnimationCurve.Linear(0f, 1f, 1f, 0f);
        trail.sharedMaterial = materials["Particle"];
        trail.colorGradient = TwoColorFade(new Color(0.4f, 0.95f, 1f), new Color(1f, 0.4f, 0.9f));
        trail.emitting = false;

        PlayerController controller = root.AddComponent<PlayerController>();
        Set(controller, "dashTrail", trail);

        PlayerCollision collision = root.AddComponent<PlayerCollision>();
        Set(collision, "bodyRenderer", ball.GetComponent<Renderer>());
        Set(collision, "hitEffectPrefab", hitSparks);

        return SavePrefab(root, "Player");
    }

    static Gradient TwoColorFade(Color from, Color to)
    {
        Gradient gradient = new Gradient();
        gradient.SetKeys(
            new[] { new GradientColorKey(from, 0f), new GradientColorKey(to, 1f) },
            new[] { new GradientAlphaKey(0.9f, 0f), new GradientAlphaKey(0f, 1f) });
        return gradient;
    }

    // ---------------------------------------------------------------- collectibles

    static GameObject CreateCrystal()
    {
        GameObject root = new GameObject("Crystal");
        root.tag = "Crystal";
        SphereCollider trigger = root.AddComponent<SphereCollider>();
        trigger.isTrigger = true;
        trigger.radius = 0.6f;

        GameObject gem = MeshObject("Gem", root.transform, crystalMesh, materials["Crystal"]);
        gem.transform.localScale = new Vector3(1.1f, 1.2f, 1.1f);

        Crystal crystal = root.AddComponent<Crystal>();
        Set(crystal, "collectEffectPrefab", collectBurst);
        return SavePrefab(root, "Crystal");
    }

    static GameObject CreateExtraLife()
    {
        GameObject root = PickupRoot("ExtraLife", Pickup.PickupType.ExtraLife);
        Material material = materials["PickupLife"];
        // A green "plus" sign.
        Primitive(PrimitiveType.Cube, "Horizontal", root.transform, material, false).transform.localScale = new Vector3(0.7f, 0.22f, 0.22f);
        Primitive(PrimitiveType.Cube, "Vertical", root.transform, material, false).transform.localScale = new Vector3(0.22f, 0.7f, 0.22f);
        return SavePrefab(root, "ExtraLife");
    }

    static GameObject CreateExtraTime()
    {
        GameObject root = PickupRoot("ExtraTime", Pickup.PickupType.ExtraTime);
        // A yellow clock: a disc with two hands.
        GameObject face = Primitive(PrimitiveType.Cylinder, "Face", root.transform, materials["PickupTime"], false);
        face.transform.localScale = new Vector3(0.75f, 0.06f, 0.75f);
        face.transform.localRotation = Quaternion.Euler(90f, 0f, 0f);
        GameObject hourHand = Primitive(PrimitiveType.Cube, "HandShort", root.transform, materials["Metal"], false);
        hourHand.transform.localScale = new Vector3(0.06f, 0.22f, 0.04f);
        hourHand.transform.localPosition = new Vector3(0f, 0.09f, -0.08f);
        GameObject minuteHand = Primitive(PrimitiveType.Cube, "HandLong", root.transform, materials["Metal"], false);
        minuteHand.transform.localScale = new Vector3(0.28f, 0.05f, 0.04f);
        minuteHand.transform.localPosition = new Vector3(0.12f, 0f, -0.08f);
        return SavePrefab(root, "ExtraTime");
    }

    static GameObject PickupRoot(string name, Pickup.PickupType type)
    {
        GameObject root = new GameObject(name);
        root.tag = "Pickup";
        SphereCollider trigger = root.AddComponent<SphereCollider>();
        trigger.isTrigger = true;
        trigger.radius = 0.6f;
        Pickup pickup = root.AddComponent<Pickup>();
        Set(pickup, "type", type);
        Set(pickup, "collectEffectPrefab", pickupBurst);
        return root;
    }

    // ---------------------------------------------------------------- hazards

    static GameObject CreateLaser()
    {
        GameObject root = new GameObject("LaserBarrier");

        // Two solid posts (normal colliders - you bump into them, they do not hurt).
        GameObject postA = Primitive(PrimitiveType.Cylinder, "PostA", root.transform, materials["Metal"], true);
        GameObject postB = Primitive(PrimitiveType.Cylinder, "PostB", root.transform, materials["Metal"], true);
        foreach (GameObject post in new[] { postA, postB })
        {
            post.transform.localScale = new Vector3(0.35f, 0.6f, 0.35f);
            post.transform.localPosition = new Vector3(0f, 0.6f, 0f);
            GameObject emitter = Primitive(PrimitiveType.Sphere, "Emitter", post.transform, materials["LaserEmitter"], false);
            emitter.transform.localScale = new Vector3(1.1f, 0.55f, 1.1f);
            emitter.transform.localPosition = new Vector3(0f, 1f, 0f);
        }

        // The beam: a trigger with the "Hazard" tag, switched on and off by LaserBarrier.
        GameObject beam = Primitive(PrimitiveType.Cube, "Beam", root.transform, materials["LaserBeam"], true);
        beam.tag = "Hazard";
        beam.transform.localPosition = new Vector3(0f, 0.5f, 0f);
        BoxCollider beamCollider = beam.GetComponent<BoxCollider>();
        beamCollider.isTrigger = true;
        beamCollider.size = new Vector3(1f, 2.5f, 2.5f); // a bit thicker than the visible beam - fair but readable
        beam.GetComponent<Renderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;

        LaserBarrier laser = root.AddComponent<LaserBarrier>();
        Set(laser, "beam", beam.transform);
        Set(laser, "beamCollider", beamCollider);
        Set(laser, "beamRenderer", beam.GetComponent<Renderer>());
        Set(laser, "postA", postA.transform);
        Set(laser, "postB", postB.transform);
        laser.ApplyLength();
        return SavePrefab(root, "LaserBarrier");
    }

    static GameObject CreateDrone()
    {
        GameObject root = new GameObject("PatrolDrone");
        root.tag = "Hazard";
        SphereCollider collider = root.AddComponent<SphereCollider>();
        collider.radius = 0.55f;
        Rigidbody body = root.AddComponent<Rigidbody>();
        body.isKinematic = true;
        body.useGravity = false;
        body.interpolation = RigidbodyInterpolation.Interpolate;

        GameObject shell = Primitive(PrimitiveType.Sphere, "Body", root.transform, materials["DroneBody"], false);
        shell.transform.localScale = Vector3.one * 0.85f;
        GameObject eye = Primitive(PrimitiveType.Sphere, "Eye", root.transform, materials["DroneEye"], false);
        eye.transform.localScale = new Vector3(0.35f, 0.25f, 0.2f);
        eye.transform.localPosition = new Vector3(0f, 0.12f, -0.38f);
        GameObject ring = MeshObject("Ring", root.transform, ringMesh, materials["Metal"]);
        ring.transform.localScale = Vector3.one * 0.62f;
        GameObject spike = MeshObject("Antenna", ring.transform, spikeMesh, materials["LaserEmitter"]);
        spike.transform.localPosition = new Vector3(1f, 0f, 0f);
        spike.transform.localScale = Vector3.one * 0.6f;

        Light warning = AddPointLight(root.transform, "WarningLight", new Color(1f, 0.3f, 0.1f), 1.5f, 3f, new Vector3(0f, 0.4f, 0f));

        PatrolDrone drone = root.AddComponent<PatrolDrone>();
        Set(drone, "spinningRing", ring.transform);
        Set(drone, "warningLight", warning);
        return SavePrefab(root, "PatrolDrone");
    }

    static GameObject CreateSpikeTrap()
    {
        GameObject root = new GameObject("SpikeTrap");
        root.tag = "Hazard";
        BoxCollider trigger = root.AddComponent<BoxCollider>();
        trigger.isTrigger = true;
        trigger.size = new Vector3(1.8f, 1f, 1.8f);
        trigger.center = new Vector3(0f, 0.5f, 0f);

        GameObject plate = Primitive(PrimitiveType.Cube, "Plate", root.transform, materials["SpikePlate"], false);
        plate.transform.localScale = new Vector3(2f, 0.04f, 2f);
        plate.transform.localPosition = new Vector3(0f, 0.01f, 0f);

        GameObject spikes = new GameObject("Spikes");
        spikes.transform.SetParent(root.transform, false);
        spikes.transform.localPosition = new Vector3(0f, -0.6f, 0f);
        for (int x = -1; x <= 1; x++)
        {
            for (int z = -1; z <= 1; z++)
            {
                GameObject spike = MeshObject("Spike", spikes.transform, spikeMesh, materials["SpikeMetal"]);
                spike.transform.localPosition = new Vector3(x * 0.6f, 0f, z * 0.6f);
            }
        }

        SpikeTrap trap = root.AddComponent<SpikeTrap>();
        Set(trap, "spikes", spikes.transform);
        Set(trap, "damageTrigger", trigger);
        Set(trap, "plateRenderer", plate.GetComponent<Renderer>());
        return SavePrefab(root, "SpikeTrap");
    }

    // ---------------------------------------------------------------- portal, level pieces

    static GameObject CreatePortal()
    {
        GameObject root = new GameObject("ExitPortal");
        root.tag = "Finish";
        BoxCollider trigger = root.AddComponent<BoxCollider>();
        trigger.isTrigger = true;
        trigger.size = new Vector3(2f, 2.6f, 1.2f);
        trigger.center = new Vector3(0f, 1.3f, 0f);

        GameObject pad = Primitive(PrimitiveType.Cylinder, "Pad", root.transform, materials["Metal"], false);
        pad.transform.localScale = new Vector3(2.6f, 0.05f, 2.6f);
        pad.transform.localPosition = new Vector3(0f, 0.03f, 0f);

        // The ring mesh lies flat, so we stand it up (rotate 90 degrees around X).
        GameObject ring = MeshObject("Ring", root.transform, ringMesh, materials["PortalClosed"]);
        ring.transform.localPosition = new Vector3(0f, PortalRingHeight, 0f);
        ring.transform.localRotation = Quaternion.Euler(90f, 0f, 0f);
        ring.transform.localScale = Vector3.one * PortalRingRadius;

        ParticleSystem swirl = CreatePortalSwirl(root.transform);
        Light light = AddPointLight(root.transform, "PortalLight", new Color(0.3f, 1f, 0.85f), 3f, 6f, new Vector3(0f, PortalRingHeight, -0.5f));
        light.enabled = false;

        ExitPortal portal = root.AddComponent<ExitPortal>();
        Set(portal, "ringRenderer", ring.GetComponent<Renderer>());
        Set(portal, "closedMaterial", materials["PortalClosed"]);
        Set(portal, "openMaterial", materials["PortalOpen"]);
        Set(portal, "openEffect", swirl);
        Set(portal, "portalLight", light);
        Set(portal, "ring", ring.transform);
        return SavePrefab(root, "ExitPortal");
    }

    static GameObject CreateWall()
    {
        // A 1x1x1 block; every wall in a level is this prefab with its own scale.
        GameObject root = Primitive(PrimitiveType.Cube, "Wall", null, materials["Wall"], true);
        GameObject cap = Primitive(PrimitiveType.Cube, "GlowCap", root.transform, materials["WallGlow"], false);
        cap.transform.localScale = new Vector3(1.02f, 0.05f, 1.02f);
        cap.transform.localPosition = new Vector3(0f, 0.5f, 0f);
        return SavePrefab(root, "Wall");
    }

    static GameObject CreateFloorTile()
    {
        // Only the look: the level floor has one big collider (no bumps between tiles).
        GameObject tile = Primitive(PrimitiveType.Cube, "FloorTile", null, materials["Floor"], false);
        tile.transform.localScale = new Vector3(4f, 0.5f, 4f);
        return SavePrefab(tile, "FloorTile");
    }

    // ---------------------------------------------------------------- managers

    static GameObject CreateAudioManager()
    {
        GameObject root = new GameObject("AudioManager");
        AudioManager audio = root.AddComponent<AudioManager>();
        Set(audio, "music", musicClip);
        Set(audio, "collect", collectClip);
        Set(audio, "hit", hitClip);
        Set(audio, "dash", dashClip);
        Set(audio, "pickup", pickupClip);
        Set(audio, "portalOpen", portalClip);
        Set(audio, "win", winClip);
        Set(audio, "lose", loseClip);
        Set(audio, "click", clickClip);
        return SavePrefab(root, "AudioManager");
    }

    static GameObject CreateAdManager()
    {
        GameObject root = new GameObject("AdManager");
        AdManager ads = root.AddComponent<AdManager>();
        Set(ads, "stubFont", uiFont);
        return SavePrefab(root, "AdManager");
    }
}
