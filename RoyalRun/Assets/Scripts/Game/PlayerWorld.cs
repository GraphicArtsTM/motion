using System.Collections.Generic;
using System.Globalization;
using System.Text;
using UnityEngine;

// A whole "personal world" for one player: their own road, obstacles, timer, score and camera.
// It combines the former LevelGenerator + ObstacleSpawner + GameManager + ScoreManager + CameraController.
// The worlds stand side by side in the scene (each 100 metres to the right of the previous one) and do not interfere with each other.
//
// Score = coins (x combo multiplier) + 1 point per metre run.
// Combo: every 10 coins in a row without a hit raise the multiplier (x2 ... x5); a hit resets it.
// Power-ups: shield (absorbs one hit), magnet (pulls coins), hourglass (+time).
public class PlayerWorld : MonoBehaviour
{
    public const float WorldSpacing = 100f;
    public const float MagnetRadius = 7f;

    // --- settings (values taken from the original MainLevel scene) ---
    const float StartTime = 30f;
    const int StartingChunks = 14;
    const int ChunksBehindPlayer = 2;
    const int CheckpointChunkInterval = 8;
    const float ChunkLength = 10f;
    const float SafeStartZ = 12f;            // no fences closer than this at the start
    const float MinMoveSpeed = 2f;
    const float MaxMoveSpeed = 20f;
    const float MinGravityZ = -22f;
    const float MaxGravityZ = -8f;
    const float MinObstacleSpawnTime = 0.2f;
    const float FirstObstacleDelay = 2.5f;
    const float SpawnWidth = 4f;
    const float ObstacleSpawnHeight = 5f;
    const float ObstacleSpawnDistance = 40f;
    const float BaseFov = 70f;
    const float MinFov = 62f;
    const float MaxFov = 84f;
    const float FovPerSpeed = 1.2f;       // was 5: at top speed the hero became tiny
    const float TimeBarMax = 40f;
    const int CoinsPerComboStep = 10;
    const int MaxMultiplier = 5;
    const float ShieldDuration = 10f;
    const float MagnetDuration = 8f;
    const float HourglassSeconds = 4f;
    const int SpeedLineCount = 18;
    const float IntroDuration = 1.5f;        // the camera flies around the hero before the start
    const float CheckpointSpeedUp = 0.5f;    // the road gets a little faster at every checkpoint

    // --- state ---
    public int Index { get; private set; }
    public PhonePlayer Owner { get; private set; }
    public CharacterDef Character { get; private set; }
    public Camera Cam { get; private set; }
    public bool Finished { get; private set; }
    // true while the road is moving: not during the intro fly-around and not after the time is up
    public bool Running { get { return !Finished && introTimer <= 0f; } }
    public int CoinsCollected { get; private set; }
    public int BestMultiplier { get; private set; }
    public int Score { get { return coinScore + Mathf.FloorToInt(distance); } }
    public int Distance { get { return Mathf.FloorToInt(distance); } }
    public float TimeLeft { get; private set; }
    public float GravityZ { get { return gravityZ; } }
    public float MoveSpeed { get { return moveSpeed; } }
    public float OriginX { get { return originX; } }
    public int Multiplier { get { return Mathf.Min(MaxMultiplier, 1 + comboCoins / CoinsPerComboStep); } }
    public bool ShieldActive { get { return shieldTime > 0f && !Finished; } }
    public float ShieldTimeLeft { get { return shieldTime; } }
    public bool MagnetActive { get { return magnetTime > 0f && !Finished; } }
    public Transform AvatarTransform { get { return avatar != null ? avatar.transform : null; } }
    public List<Hazard> Hazards { get { return hazards; } }

    public void RegisterHazard(Hazard h) { if (!hazards.Contains(h)) hazards.Add(h); }
    public void UnregisterHazard(Hazard h) { hazards.Remove(h); }

    // 1 normally, much less right after a hit
    float StumbleFactor { get { return stumbleTimer > 0f ? Mathf.Lerp(1f, 0.15f, stumbleTimer / StumbleDuration) : 1f; } }

    GameAssets assets;
    PhoneHub hub;
    ColumnHud hud;
    PlayerAvatar avatar;
    Transform chunkParent;
    Transform obstacleParent;

    readonly List<GameObject> chunks = new List<GameObject>();
    readonly List<Hazard> hazards = new List<Hazard>();
    float stumbleTimer;                    // after a hit the road almost stops, then speeds up again
    const float StumbleDuration = 0.8f;
    int chunkIndex = -ChunksBehindPlayer;
    bool settingUp;

    float originX;
    float moveSpeed = 6f;
    float gravityZ = -12f;
    float obstacleSpawnTime = 3f;
    float spawnTimer = -FirstObstacleDelay;
    float targetFov = BaseFov;
    float currentFov = BaseFov;
    float phoneTimer;
    float toastTimeLeft;
    float camHeightFollow;

    // camera state
    float camX;
    float camXVelocity;
    float camRoll;
    float trauma;              // 0..1, shake strength (decays by itself)
    float punch;               // a short push of the camera on a hit
    float dip;                 // a small dip on landing
    float fovKick;             // a short widening of the view on a speed-up
    float introTimer = IntroDuration;
    float finishTimer;
    float goTimer;
    float flashAlpha;

    // zones: every checkpoint leads into the next one
    int biome;
    readonly Queue<int> pendingZones = new Queue<int>();

    int coinScore;
    float distance;
    int comboCoins;
    float shieldTime;
    float magnetTime;
    float comboPulse;

    Transform[] speedLines;
    float[] speedLineZ;

    public static PlayerWorld Create(int index, int total, PhonePlayer owner, GameAssets assets, PhoneHub hub)
    {
        GameObject root = new GameObject("World " + (index + 1) + " (" + owner.name + ")");
        root.transform.position = new Vector3(index * WorldSpacing, 0f, 0f);

        PlayerWorld w = root.AddComponent<PlayerWorld>();
        w.Setup(index, total, owner, assets, hub);
        return w;
    }

    void Setup(int index, int total, PhonePlayer owner, GameAssets assets, PhoneHub hub)
    {
        Index = index;
        Owner = owner;
        this.assets = assets;
        this.hub = hub;
        originX = index * WorldSpacing;
        Character = CharacterCatalog.All[Mathf.Clamp(owner.character, 0, CharacterCatalog.Count - 1)];
        TimeLeft = StartTime + Character.startTimeBonus;

        chunkParent = new GameObject("Chunk Parent").transform;
        chunkParent.SetParent(transform, false);
        obstacleParent = new GameObject("Obstacle Parent").transform;
        obstacleParent.SetParent(transform, false);

        // the camera takes its own vertical strip of the screen
        GameObject camGo = new GameObject("Camera P" + (index + 1));
        camGo.transform.SetParent(transform, false);
        Cam = camGo.AddComponent<Camera>();
        Cam.rect = new Rect(index / (float)total, 0f, 1f / total, 1f);
        Cam.fieldOfView = BaseFov;
        Cam.nearClipPlane = 0.3f;
        Cam.farClipPlane = 135f;
        // the daytime sky; without a skybox material - a plain background of the horizon colour
        Cam.clearFlags = RenderSettings.skybox != null ? CameraClearFlags.Skybox : CameraClearFlags.SolidColor;
        Cam.backgroundColor = GameBootstrap.HorizonColor;
        Cam.depth = index;

        // The player's UI lives on its own canvas attached to their camera.
        // (A shared Overlay canvas in URP gets clipped to one camera's area and disappeared for the second player.)
        hud = GameUI.CreateColumnHud(Cam, index, total, owner.name, Character.Name,
                                     PhoneHub.SlotColors[owner.slot], transform);

        settingUp = true;
        for (int i = 0; i < StartingChunks; i++) SpawnChunk();
        settingUp = false;

        GameObject model = assets.ModelFor(owner.character);
        avatar = PlayerAvatar.Create(this, owner, model, Character, new Vector3(originX, 0f, 0f));

        BuildSpeedLines();
        camX = originX;
        BestMultiplier = 1;
        UpdateCamera(0f);
        UpdateHud();
        PushToPhone(false);
    }

    static string KeyName(int scheme)
    {
        switch (scheme)
        {
            case 1: return "Right Shift";
            case 2: return "Num 0";
            default: return Loc.T("key.space");
        }
    }

    // ================= every frame =================

    void Update()
    {
        float dt = Time.deltaTime;

        if (introTimer > 0f && !Finished)
        {
            introTimer -= dt;
            if (introTimer <= 0f) OnStart();
        }
        else if (!Finished)
        {
            TickTime(dt);
            TickObstacleSpawner(dt);
            if (stumbleTimer > 0f) stumbleTimer -= dt;
            MoveChunks(dt);
            distance += moveSpeed * StumbleFactor * dt;
            if (shieldTime > 0f) shieldTime -= dt;
            if (magnetTime > 0f) magnetTime -= dt;
        }
        else
        {
            finishTimer += dt;
        }

        UpdateHud();
        UpdateSpeedLines(dt);

        phoneTimer += dt;
        if (phoneTimer >= 0.2f)
        {
            phoneTimer = 0f;
            PushToPhone(false);
        }
    }

    void LateUpdate()
    {
        UpdateCamera(Time.deltaTime);
    }

    // The camera has flown around the hero: GO!
    void OnStart()
    {
        goTimer = 0.9f;
        Sfx.Play(SynthAudio.Go, 0.6f);
        string jumpHint = Owner.isKeyboard ? Loc.F("hud.jumpKey", KeyName(Owner.keyboardScheme)) : Loc.T("hud.jumpTap");
        ShowToast(jumpHint, new Color(0.7f, 0.9f, 1f), 3f);
    }

    // ================= time and score =================

    void TickTime(float dt)
    {
        TimeLeft -= dt;
        if (TimeLeft <= 0f)
        {
            TimeLeft = 0f;
            Finish();
        }
    }

    void Finish()
    {
        Finished = true;
        shieldTime = 0f;
        magnetTime = 0f;

        // freeze everything still rolling along the road
        foreach (Rigidbody rb in obstacleParent.GetComponentsInChildren<Rigidbody>())
        {
            rb.linearVelocity = Vector3.zero;
            rb.angularVelocity = Vector3.zero;
            rb.isKinematic = true;
        }

        PushToPhone(true);
    }

    // Kept for compatibility with the guide's Coin script.
    public void AddCoinScore(int baseAmount)
    {
        AddCoinScore(baseAmount, false);
    }

    public void AddCoinScore(int baseAmount, bool gem)
    {
        if (Finished) return;
        int before = Multiplier;
        comboCoins += gem ? 3 : 1;
        CoinsCollected++;
        int mult = Multiplier;
        if (mult > BestMultiplier) BestMultiplier = mult;
        int gained = Mathf.RoundToInt(baseAmount * Character.coinMult * mult);
        coinScore += gained;

        if (gem) ShowToast(Loc.F("hud.gem", gained), new Color(0.85f, 0.6f, 1f));
        if (mult > before)
        {
            comboPulse = 1f;
            ShowToast(Loc.F("hud.combo", mult), new Color(1f, 0.85f, 0.3f));
            Sfx.Play(SynthAudio.Combo, 0.5f);
        }
    }

    public void OnCheckpoint(float timeExtension, float obstacleDecrease)
    {
        if (Finished) return;
        float added = timeExtension + Character.checkpointBonus;
        TimeLeft += added;

        // the next zone begins right behind the arch
        string text = Loc.F("hud.checkpoint", Mathf.RoundToInt(added));
        if (pendingZones.Count > 0) text += "\n<size=30>" + Loc.T("zone." + pendingZones.Dequeue()) + "</size>";
        ShowToast(text, new Color(0.5f, 1f, 0.6f), 2.2f);
        Sfx.Play(SynthAudio.Checkpoint, 0.6f);
        obstacleSpawnTime = Mathf.Max(MinObstacleSpawnTime, obstacleSpawnTime - obstacleDecrease);

        // a little faster after every checkpoint (quietly, without "SPEED UP!")
        SetSpeed(moveSpeed + CheckpointSpeedUp);
        trauma = Mathf.Max(trauma, 0.25f);
    }

    public void ActivatePowerUp(PowerUpType type)
    {
        if (Finished) return;
        switch (type)
        {
            case PowerUpType.Shield:
                shieldTime = ShieldDuration;
                ShowToast(Loc.T("hud.shield"), new Color(0.4f, 0.9f, 1f));
                break;
            case PowerUpType.Magnet:
                magnetTime = MagnetDuration;
                ShowToast(Loc.T("hud.magnet"), new Color(1f, 0.55f, 0.5f));
                break;
            default:
                TimeLeft += HourglassSeconds;
                ShowToast(Loc.F("hud.hourglass", Mathf.RoundToInt(HourglassSeconds)), new Color(1f, 0.85f, 0.35f));
                break;
        }
    }

    // Called by PlayerAvatar before a hit: true = the shield took it.
    public bool TryAbsorbHit()
    {
        if (!ShieldActive) return false;
        shieldTime = 0f;
        ShowToast(Loc.T("hud.shieldSaved"), new Color(0.4f, 0.9f, 1f));
        Shake(0.4f);
        return true;
    }

    // A real hit: the combo is lost, the phone vibrates.
    public void OnHit()
    {
        OnHit(2f);
    }

    // A real hit: time is taken away, the combo is lost, the road stumbles, the screen flashes and shakes.
    public void OnHit(float timePenalty)
    {
        if (Finished) return;
        int lostCombo = Multiplier;
        comboCoins = 0;
        float penalty = timePenalty * Character.hitSlowMult;
        TimeLeft = Mathf.Max(0f, TimeLeft - penalty);
        stumbleTimer = StumbleDuration;
        trauma = 1f;
        punch = 1f;
        flashAlpha = 0.65f;

        string text = Loc.F("hud.hitPenalty", penalty.ToString("0.#", CultureInfo.InvariantCulture));
        if (lostCombo > 1) text += "\n<size=28>" + Loc.T("hud.comboLost") + "</size>";
        ShowToast(text, new Color(1f, 0.4f, 0.35f), 1.6f);
        NotifyHit();
        if (TimeLeft <= 0f) Finish();
    }

    // Called by PlayerAvatar: the camera follows the jump and dips a little on landing.
    public void OnLanded()
    {
        dip = 0.18f;
    }

    // ================= speed (apples and hits) =================

    public void ChangeSpeed(float amount)
    {
        ChangeSpeed(amount, false);
    }

    public void ChangeSpeed(float amount, bool silent)
    {
        if (Finished) return;
        if (amount < 0f) amount *= Character.hitSlowMult;

        float before = moveSpeed;
        if (!SetSpeed(moveSpeed + amount)) return;

        if (silent) return;
        if (moveSpeed > before)
        {
            ShowToast(Loc.T("hud.speedUp"), new Color(1f, 0.9f, 0.3f));
            fovKick = 1f;
        }
        else ShowToast(Loc.T("hud.hit"), new Color(1f, 0.45f, 0.4f));
    }

    // The road speed, the "gravity" of the obstacles and the field of view change together.
    bool SetSpeed(float newSpeed)
    {
        newSpeed = Mathf.Clamp(newSpeed, MinMoveSpeed, MaxMoveSpeed);
        float amount = newSpeed - moveSpeed;
        if (Mathf.Approximately(amount, 0f)) return false;
        moveSpeed = newSpeed;
        gravityZ = Mathf.Clamp(gravityZ - amount, MinGravityZ, MaxGravityZ);
        targetFov = Mathf.Clamp(targetFov + amount * FovPerSpeed, MinFov, MaxFov);
        return true;
    }

    public void NotifyHit()
    {
        if (hub != null) hub.SendTo(Owner, "{\"t\":\"hit\"}");
    }

    // ================= road =================

    void SpawnChunk()
    {
        float z = chunks.Count == 0
            ? -ChunksBehindPlayer * ChunkLength
            : chunks[chunks.Count - 1].transform.position.z + ChunkLength;

        GameObject prefab = ChooseChunkPrefab();
        GameObject chunk = Instantiate(prefab, new Vector3(originX, 0f, z), Quaternion.identity, chunkParent);

        // the pieces around the start get no fences, so nothing hits the player in the first second
        if (settingUp && z < SafeStartZ)
        {
            Chunk c = chunk.GetComponent<Chunk>();
            if (c != null) c.MakeSafe();
        }

        chunks.Add(chunk);
        chunkIndex++;
    }

    GameObject ChooseChunkPrefab()
    {
        GameObject[][] zones = assets.biomeChunks;
        bool hasZones = zones != null && zones.Length > 0;

        if (chunkIndex % CheckpointChunkInterval == 0 && chunkIndex != 0 && assets.checkpointChunkPrefab != null)
        {
            GameObject cp = assets.biomeCheckpoints != null && biome < assets.biomeCheckpoints.Length && assets.biomeCheckpoints[biome] != null
                ? assets.biomeCheckpoints[biome]
                : assets.checkpointChunkPrefab;
            if (hasZones)
            {
                biome = (biome + 1) % zones.Length;     // after the arch the road enters the next zone
                pendingZones.Enqueue(biome);
            }
            return cp;
        }

        GameObject[] set = hasZones && zones[biome] != null && zones[biome].Length > 0 ? zones[biome] : assets.chunkPrefabs;
        return set[Random.Range(0, set.Length)];
    }

    void MoveChunks(float dt)
    {
        Vector3 step = Vector3.back * (moveSpeed * StumbleFactor * dt);
        for (int i = 0; i < chunks.Count; i++) chunks[i].transform.position += step;

        float recycleZ = Cam.transform.position.z - ChunkLength;
        while (chunks.Count > 0 && chunks[0].transform.position.z <= recycleZ)
        {
            Destroy(chunks[0]);
            chunks.RemoveAt(0);
            SpawnChunk();
        }
    }

    // ================= falling obstacles =================

    void TickObstacleSpawner(float dt)
    {
        spawnTimer += dt;
        if (spawnTimer < obstacleSpawnTime) return;
        spawnTimer = 0f;

        if (assets.obstaclePrefabs == null || assets.obstaclePrefabs.Length == 0) return;
        GameObject prefab = assets.obstaclePrefabs[Random.Range(0, assets.obstaclePrefabs.Length)];
        if (prefab == null) return;
        Vector3 pos = new Vector3(originX + Random.Range(-SpawnWidth, SpawnWidth),
                                  ObstacleSpawnHeight, ObstacleSpawnDistance);
        GameObject obstacle = Instantiate(prefab, pos, Random.rotation, obstacleParent);
        if (obstacle.GetComponent<ObstacleMotion>() == null) obstacle.AddComponent<ObstacleMotion>();
    }

    // ================= camera =================

    // Camera shake uses "trauma": every impact adds some, it decays by itself,
    // and the shake strength is trauma squared - small knocks are subtle, big ones are strong.
    public void Shake(float intensity)
    {
        trauma = Mathf.Clamp01(trauma + Mathf.Clamp01(intensity) * 0.7f);
    }

    void UpdateCamera(float dt)
    {
        if (Cam == null || avatar == null) return;
        float t = Time.time;

        // A narrow strip of the screen sees less road, so for 2-3 players we move the camera back and up.
        float aspect = Mathf.Max(0.3f, Cam.aspect);
        float tanHalfV = Mathf.Tan(BaseFov * 0.5f * Mathf.Deg2Rad);
        float back = Mathf.Clamp(4.4f / (tanHalfV * aspect), 3.5f, 8f);
        float height = 2.1f + (back - 3.5f) * 0.45f;
        float speed01 = Mathf.Clamp01((moveSpeed - 6f) / 14f);

        Vector3 hero = avatar.transform.position;

        // ---- gameplay camera: smooth follow, lean into turns, look ahead ----
        if (dt > 0f)
        {
            float targetX = originX + (hero.x - originX) * 0.65f;
            camX = Mathf.SmoothDamp(camX, targetX, ref camXVelocity, 0.12f, Mathf.Infinity, dt);
            camRoll = Mathf.Lerp(camRoll, Mathf.Clamp(-camXVelocity * 1.4f, -5f, 5f), 1f - Mathf.Exp(-6f * dt));
            camHeightFollow = Mathf.Lerp(camHeightFollow, avatar.Height * 0.45f, 1f - Mathf.Exp(-8f * dt));
            dip = Mathf.MoveTowards(dip, 0f, dt * 0.9f);
            punch = Mathf.MoveTowards(punch, 0f, dt * 4f);
            fovKick = Mathf.MoveTowards(fovKick, 0f, dt * 1.5f);
            trauma = Mathf.MoveTowards(trauma, 0f, dt * 1.4f);
        }

        Vector3 gPos = new Vector3(camX, height + camHeightFollow - dip - punch * 0.15f, -back + punch * 0.5f);
        Vector3 gLook = new Vector3(Mathf.Lerp(camX, hero.x, 0.35f), 0.8f + camHeightFollow * 0.5f, 0.5f + speed01 * 2f);
        Quaternion gRot = Quaternion.LookRotation(gLook - gPos) * Quaternion.Euler(0f, 0f, camRoll);

        Vector3 pos = gPos;
        Quaternion rot = gRot;

        // ---- intro: the camera flies around from the hero's face to behind the back ----
        if (introTimer > 0f && !Finished)
        {
            float k = Mathf.SmoothStep(0f, 1f, 1f - introTimer / IntroDuration);
            Vector3 oPos; Quaternion oRot;
            Orbit(hero, Mathf.PI * (1f - k) * (Index % 2 == 0 ? 1f : -1f), 4.2f, out oPos, out oRot);
            pos = Vector3.Lerp(oPos, gPos, k * k);
            rot = Quaternion.Slerp(oRot, gRot, k * k);
        }
        // ---- finish: a slow orbit to the tired hero's face ----
        else if (Finished)
        {
            float w = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(finishTimer / 1.2f));
            Vector3 oPos; Quaternion oRot;
            Orbit(hero, Mathf.Min(Mathf.PI * 0.8f, finishTimer * 0.9f), 4.6f, out oPos, out oRot);
            pos = Vector3.Lerp(gPos, oPos, w);
            rot = Quaternion.Slerp(gRot, oRot, w);
        }

        // ---- shake: smooth Perlin noise instead of random jumps ----
        float shake = trauma * trauma;
        if (shake > 0.0001f)
        {
            float seed = Index * 31.7f;
            pos += new Vector3(Mathf.PerlinNoise(seed, t * 22f) - 0.5f, Mathf.PerlinNoise(seed + 5f, t * 22f) - 0.5f, 0f) * (shake * 0.9f);
            rot *= Quaternion.Euler(0f, 0f, (Mathf.PerlinNoise(seed + 9f, t * 18f) - 0.5f) * shake * 10f);
        }

        Cam.transform.position = pos;
        Cam.transform.rotation = rot;

        // smooth field-of-view change when speeding up / slowing down (+ a short "kick" on an apple)
        currentFov = Mathf.Lerp(currentFov, targetFov, 1f - Mathf.Exp(-3f * dt));
        Cam.fieldOfView = Mathf.Clamp(currentFov + fovKick * 4f, MinFov, MaxFov);
    }

    // A point on a circle around the hero (angle 0 = behind, PI = in front) looking at the chest.
    void Orbit(Vector3 hero, float angle, float distance, out Vector3 pos, out Quaternion rot)
    {
        Vector3 target = hero + Vector3.up * 1.2f;
        pos = target + new Vector3(Mathf.Sin(angle) * distance, 0.6f, -Mathf.Cos(angle) * distance);
        rot = Quaternion.LookRotation(target - pos);
    }

    // Thin glowing streaks that rush past the camera at high speed.
    void BuildSpeedLines()
    {
        speedLines = new Transform[SpeedLineCount];
        speedLineZ = new float[SpeedLineCount];
        for (int i = 0; i < SpeedLineCount; i++)
        {
            GameObject g = MatLib.Prim(PrimitiveType.Cube, "Speed Line", Cam.transform, Vector3.zero, new Vector3(0.025f, 0.025f, 1f),
                                       new Color(0.85f, 0.9f, 1f), false, default(Vector3), 0.2f, 1.5f);
            Renderer r = g.GetComponent<Renderer>();
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            speedLines[i] = g.transform;
            speedLineZ[i] = Random.Range(2f, 30f);
            PlaceSpeedLine(i);
        }
    }

    void PlaceSpeedLine(int i)
    {
        float a = Random.Range(0f, Mathf.PI * 2f);
        float r = Random.Range(1.6f, 3.2f);
        speedLines[i].localPosition = new Vector3(Mathf.Cos(a) * r * 1.4f, Mathf.Sin(a) * r * 0.8f, speedLineZ[i]);
    }

    void UpdateSpeedLines(float dt)
    {
        if (speedLines == null) return;
        float k = Finished ? 0f : Mathf.Clamp01((moveSpeed - 8.5f) / 6f);
        for (int i = 0; i < speedLines.Length; i++)
        {
            Transform t = speedLines[i];
            bool on = k > 0f;
            if (t.gameObject.activeSelf != on) t.gameObject.SetActive(on);
            if (!on) continue;

            speedLineZ[i] -= moveSpeed * 2.2f * dt;
            if (speedLineZ[i] < 0.5f)
            {
                speedLineZ[i] = Random.Range(18f, 30f);
                PlaceSpeedLine(i);
            }
            Vector3 lp = t.localPosition;
            lp.z = speedLineZ[i];
            t.localPosition = lp;
            t.localScale = new Vector3(0.025f, 0.025f, 0.5f + 2.5f * k);
        }
    }

    // ================= UI and phone =================

    // The pause and the results screens hide the player strips (see GameBootstrap.ShowCleanBackground).
    public void SetViewVisible(bool visible)
    {
        if (Cam != null) Cam.enabled = visible;
        if (hud != null && hud.root != null)
        {
            Canvas c = hud.root.GetComponentInParent<Canvas>();
            if (c != null) c.enabled = visible;
        }
    }

    void UpdateHud()
    {
        if (hud == null) return;

        hud.time.text = Loc.F("hud.seconds", TimeLeft.ToString("F1", CultureInfo.InvariantCulture));
        hud.score.text = Score.ToString();
        hud.distance.text = Loc.F("hud.distance", Distance);

        // combo multiplier: "x3" with a little pop when it grows
        int mult = Multiplier;
        hud.combo.text = mult > 1 ? Loc.F("hud.comboShort", mult) : "";
        comboPulse = Mathf.Max(0f, comboPulse - Time.deltaTime * 3f);
        hud.combo.transform.localScale = Vector3.one * (1f + 0.5f * comboPulse);

        // active power-ups with their remaining time
        StringBuilder st = new StringBuilder();
        if (ShieldActive) st.Append("<color=#66e6ff>").Append(Loc.T("hud.shieldShort")).Append(' ').Append(Mathf.CeilToInt(shieldTime)).Append("</color>   ");
        if (MagnetActive) st.Append("<color=#ff8a80>").Append(Loc.T("hud.magnetShort")).Append(' ').Append(Mathf.CeilToInt(magnetTime)).Append("</color>");
        hud.status.text = st.ToString();

        // time bar: green -> yellow -> red, blinks at the end
        float ratio = Mathf.Clamp01(TimeLeft / TimeBarMax);
        hud.timeFill.anchorMax = new Vector2(Mathf.Lerp(0.01f, 0.99f, ratio), 0.88f);
        Color c = ratio > 0.4f ? new Color(0.30f, 0.80f, 0.35f)
                : ratio > 0.2f ? new Color(1f, 0.75f, 0.1f)
                : new Color(1f, 0.30f, 0.30f);
        if (!Finished && TimeLeft < 8f) c.a = 0.6f + 0.4f * Mathf.Abs(Mathf.Sin(Time.time * 6f));
        hud.timeFillImage.color = c;

        if (Finished) hud.big.text = Loc.F("hud.timeUp", Score);
        else if (goTimer > 0f)
        {
            goTimer -= Time.deltaTime;
            hud.big.text = "<color=#ffd54f>" + Loc.T("hud.go") + "</color>";
            hud.big.transform.localScale = Vector3.one * (1f + 0.6f * Mathf.Clamp01(goTimer - 0.5f));
            if (goTimer <= 0f) { hud.big.text = ""; hud.big.transform.localScale = Vector3.one; }
        }
        else hud.big.text = "";

        // a red flash along the screen on a hit
        flashAlpha = Mathf.MoveTowards(flashAlpha, 0f, Time.deltaTime * 1.6f);
        if (hud.flash != null)
        {
            hud.flash.color = new Color(1f, 0.1f, 0.1f, flashAlpha);
            hud.flash.enabled = flashAlpha > 0.001f;
        }

        // the pop-up text fades out smoothly
        if (toastTimeLeft > 0f)
        {
            toastTimeLeft -= Time.deltaTime;
            Color tc = hud.toast.color;
            tc.a = Mathf.Clamp01(toastTimeLeft / 0.5f);
            hud.toast.color = tc;
            if (toastTimeLeft <= 0f) hud.toast.text = "";
        }
    }

    public void ShowToast(string text, Color color)
    {
        ShowToast(text, color, 1.4f);
    }

    public void ShowToast(string text, Color color, float seconds)
    {
        if (hud == null) return;
        hud.toast.text = text;
        hud.toast.color = color;
        toastTimeLeft = seconds;
    }

    void PushToPhone(bool over)
    {
        if (hub == null || Owner == null) return;
        StringBuilder sb = new StringBuilder();
        sb.Append("{\"t\":\"play\",\"time\":").Append(TimeLeft.ToString("F1", CultureInfo.InvariantCulture));
        sb.Append(",\"score\":").Append(Score);
        sb.Append(",\"mult\":").Append(Multiplier);
        sb.Append(",\"shield\":").Append(ShieldActive ? "true" : "false");
        sb.Append(",\"magnet\":").Append(MagnetActive ? "true" : "false");
        sb.Append(",\"over\":").Append((over || Finished) ? "true" : "false").Append('}');
        hub.SendTo(Owner, sb.ToString());
    }

    public void ForcePush()
    {
        PushToPhone(false);
    }
}
