using System.Collections.Generic;
using System.Globalization;
using System.Text;
using UnityEngine;

// The rules of a run.
public enum GameRules
{
    Endless,   // run as far as you can: the road gets faster, a crash ends the run, two stumbles - the golem catches you
    Classic,   // the guide's rules: a timer, checkpoints add time, hits take time away
}

// Why an endless run ended.
public enum CrashCause { None, Obstacle, MissedTurn, Caught, TimeUp }

// A whole "personal world" for one player: their own road, obstacles, score and camera.
// It combines the former LevelGenerator + ObstacleSpawner + GameManager + ScoreManager + CameraController.
// The worlds stand side by side in the scene (each 1000 metres apart) and do not interfere with each other.
//
// The road is made of 10 m pieces that move towards the player. Some pieces are CORNERS: the road turns
// 90 degrees left or right. Swipe in that direction while standing in the turning square and the whole
// road swings around the hero (the pieces' parent is rotated), so the new direction is "forward" again.
//
// Score = coins (x combo multiplier) + 1 point per metre run.
public class PlayerWorld : MonoBehaviour
{
    public const float WorldSpacing = 1000f;   // corners send the road sideways, so the worlds stand far apart
    public const float MagnetRadius = 7f;

    // --- settings ---
    const float StartTime = 30f;
    const int ChunksBehindPlayer = 2;
    const int CheckpointChunkInterval = 8;
    const float ChunkLength = 10f;
    const float SafeStartZ = 15f;            // no obstacles closer than this at the start
    const int FirstCornerIndex = 9;          // no corners in the first pieces
    const float MinMoveSpeed = 2f;
    const float MaxMoveSpeedClassic = 20f;
    const float EndlessStartSpeed = 8f;
    const float EndlessMaxSpeed = 24f;
    const float EndlessAcceleration = 0.075f;  // metres per second, every second
    const float MinGravityZ = -26f;
    const float MaxGravityZ = -8f;
    const float MinObstacleSpawnTime = 0.6f;
    const float FirstObstacleDelay = 3f;
    const float ObstacleSpawnHeight = 5f;
    const float ObstacleSpawnDistance = 40f;
    const float MinFov = 60f;
    const float MaxFov = 88f;
    const float FovPerSpeed = 0.6f;
    const float TimeBarMax = 40f;
    const int CoinsPerComboStep = 10;
    const int MaxMultiplier = 5;
    const float ShieldDuration = 10f;
    const float MagnetDuration = 8f;
    const float HourglassSeconds = 4f;
    const float IntroDuration = 1.4f;        // the camera flies around the hero before the start
    const float CheckpointSpeedUp = 0.5f;
    const float StumbleDuration = 0.7f;
    const float ChaseTime = 7f;              // the golem stays close this long after a stumble
    const float TurnDuration = 0.22f;
    const float TurnWindowAhead = 4.8f;      // you may turn when the corner's centre is this close ahead...
    const float TurnWindowBehind = -3.2f;    // ...or this far behind

    // --- state ---
    public int Index { get; private set; }
    public PhonePlayer Owner { get; private set; }
    public CharacterDef Character { get; private set; }
    public GameRules Rules { get; private set; }
    public Camera Cam { get; private set; }
    public bool Finished { get; private set; }
    public CrashCause Cause { get; private set; }
    // true while the road is moving: not during the intro and not after the end
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
    public MenuButton PauseButton { get { return hud != null ? hud.pause : null; } }
    // the road is swinging around a corner right now (obstacles are not checked meanwhile)
    public bool Turning { get { return turnT >= 0f; } }

    public void RegisterHazard(Hazard h) { if (!hazards.Contains(h)) hazards.Add(h); }
    public void UnregisterHazard(Hazard h) { hazards.Remove(h); }

    // 1 normally, much less right after a hit
    float StumbleFactor { get { return stumbleTimer > 0f ? Mathf.Lerp(1f, 0.2f, stumbleTimer / StumbleDuration) : 1f; } }

    GameAssets assets;
    PhoneHub hub;
    ColumnHud hud;
    PlayerAvatar avatar;
    Chaser golem;
    Transform chunkParent;
    Transform obstacleParent;
    int startingChunks = 14;

    readonly List<Chunk> chunks = new List<Chunk>();
    readonly List<Hazard> hazards = new List<Hazard>();
    int chunkIndex = -ChunksBehindPlayer;
    bool settingUp;

    float originX;
    float moveSpeed = 6f;
    float gravityZ = -12f;
    float obstacleSpawnTime = 3f;
    float spawnTimer = -FirstObstacleDelay;
    float baseFov = 70f;
    float speedFov;
    float currentFov = 70f;
    float phoneTimer;
    float toastTimeLeft;
    float hintTimer;
    float camHeightFollow;
    float stumbleTimer;
    float chaseTimer;

    // corners
    Chunk nextCorner;               // the first corner ahead that has not been turned yet
    int chunksSinceCorner;
    int cornerGap = 8;
    int lastCornerDir;
    bool justTurnedSpawn;           // the piece right after a corner gets no obstacles
    float turnT = -1f;
    Vector3 turnFromPos, turnToPos;
    Quaternion turnFromRot, turnToRot;
    float turnKick;

    // camera state
    float camX;
    float camXVelocity;
    float camRoll;
    float trauma;
    float punch;
    float dip;
    float fovKick;
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

    // Fewer pieces ahead and fewer effects (phones). Set by GameBootstrap.
    public static bool Lite;

    public static PlayerWorld Create(int index, int total, PhonePlayer owner, GameAssets assets, PhoneHub hub, GameRules rules)
    {
        GameObject root = new GameObject("World " + (index + 1) + " (" + owner.name + ")");
        root.transform.position = new Vector3(index * WorldSpacing, 0f, 0f);

        PlayerWorld w = root.AddComponent<PlayerWorld>();
        w.Setup(index, total, owner, assets, hub, rules);
        return w;
    }

    void Setup(int index, int total, PhonePlayer owner, GameAssets assets, PhoneHub hub, GameRules rules)
    {
        Index = index;
        Owner = owner;
        Rules = rules;
        this.assets = assets;
        this.hub = hub;
        originX = index * WorldSpacing;
        Character = CharacterCatalog.All[Mathf.Clamp(owner.character, 0, CharacterCatalog.Count - 1)];
        TimeLeft = StartTime + Character.startTimeBonus;
        moveSpeed = rules == GameRules.Endless ? EndlessStartSpeed : 6f;
        startingChunks = Lite ? 12 : 14;
        cornerGap = Random.Range(6, 10);

        chunkParent = new GameObject("Chunk Parent").transform;
        chunkParent.SetParent(transform, false);
        obstacleParent = new GameObject("Obstacle Parent").transform;
        obstacleParent.SetParent(transform, false);

        // the camera takes its own vertical strip of the screen
        GameObject camGo = new GameObject("Camera P" + (index + 1));
        camGo.transform.SetParent(transform, false);
        Cam = camGo.AddComponent<Camera>();
        Cam.rect = new Rect(index / (float)total, 0f, 1f / total, 1f);
        Cam.nearClipPlane = 0.3f;
        Cam.farClipPlane = Lite ? 115f : 135f;
        // the daytime sky; without a skybox material - a plain background of the horizon colour
        Cam.clearFlags = RenderSettings.skybox != null ? CameraClearFlags.Skybox : CameraClearFlags.SolidColor;
        Cam.backgroundColor = GameBootstrap.HorizonColor;
        Cam.depth = index;
        Cam.fieldOfView = baseFov;

        // The player's UI lives on its own canvas attached to their camera.
        hud = GameUI.CreateColumnHud(Cam, index, total, owner.name, Character.Name,
                                     PhoneHub.SlotColors[owner.slot], transform, rules == GameRules.Classic);

        settingUp = true;
        for (int i = 0; i < startingChunks; i++) SpawnChunk();
        settingUp = false;

        GameObject model = assets.ModelFor(owner.character);
        avatar = PlayerAvatar.Create(this, owner, model, Character, new Vector3(originX, 0f, 0f));
        golem = Chaser.Create(transform);

        BuildSpeedLines();
        camX = originX;
        BestMultiplier = 1;
        UpdateCamera(0f);
        UpdateHud();
        PushToPhone(false);
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
            if (Rules == GameRules.Classic) TickTime(dt);
            else
            {
                // the endless road keeps getting faster
                SetSpeed(moveSpeed + EndlessAcceleration * dt);
            }
            if (stumbleTimer > 0f) stumbleTimer -= dt;
            if (chaseTimer > 0f) chaseTimer -= dt;
            if (shieldTime > 0f) shieldTime -= dt;
            if (magnetTime > 0f) magnetTime -= dt;

            if (turnT >= 0f) TickTurn(dt);
            else
            {
                TickObstacleSpawner(dt);
                MoveChunks(dt);
                distance += moveSpeed * StumbleFactor * dt;
            }
        }
        else
        {
            finishTimer += dt;
        }

        if (golem != null && avatar != null && golem.gameObject.activeSelf)
            golem.Follow(avatar.transform.position, Running ? moveSpeed : 0f, dt);

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
        hintTimer = 5f;
        if (Owner.isKeyboard && GameInput.HasTouch && Owner.keyboardScheme == GameInput.SchemeSolo && Application.isMobilePlatform)
            hud.hint.text = Loc.T("hint.touch");
        else if (Owner.isKeyboard)
            hud.hint.text = Loc.T(KeyHintKey(Owner.keyboardScheme));
        else
            hud.hint.text = Loc.T("hint.phone");
    }

    static string KeyHintKey(int scheme)
    {
        switch (scheme)
        {
            case 1: return "hint.arrows";
            case 2: return "hint.numpad";
            case 0: return "hint.wasd";
            default: return GameInput.HasTouch && Application.isMobilePlatform ? "hint.touch" : "hint.keys";
        }
    }

    // ================= time and score =================

    void TickTime(float dt)
    {
        TimeLeft -= dt;
        if (TimeLeft <= 0f)
        {
            TimeLeft = 0f;
            Finish(CrashCause.TimeUp);
        }
    }

    void Finish(CrashCause cause)
    {
        if (Finished) return;
        Finished = true;
        Cause = cause;
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

    // Endless mode: the run is over (a wall, a beam, a missed corner, or the golem).
    public void Crash(CrashCause cause)
    {
        if (Finished) return;
        trauma = 1f;
        punch = 1f;
        flashAlpha = 0.7f;
        NotifyHit();
        if (cause == CrashCause.Caught && golem != null) golem.Grab();
        Finish(cause);
    }

    // Endless mode: a stumble over a fence, a cart or a falling object. Twice while the golem is near - caught.
    public void OnStumble()
    {
        if (Finished) return;
        comboCoins = 0;
        if (chaseTimer > 0f)
        {
            Crash(CrashCause.Caught);
            return;
        }
        chaseTimer = ChaseTime;
        stumbleTimer = StumbleDuration;
        trauma = Mathf.Max(trauma, 0.6f);
        punch = 0.6f;
        flashAlpha = 0.45f;
        if (golem != null) golem.Approach(ChaseTime);
        ShowToast(Loc.T("hud.stumble"), new Color(1f, 0.6f, 0.3f), 1.6f);
        NotifyHit();
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
        CoinsCollected += gem ? 5 : 1;
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

    // An apple: classic - faster road; endless - bonus points (the road speeds up by itself there).
    public void OnApple(float speedAmount)
    {
        if (Finished) return;
        if (Rules == GameRules.Classic) { ChangeSpeed(speedAmount); return; }
        coinScore += 150;
        ShowToast("+150", new Color(1f, 0.5f, 0.45f));
    }

    public void OnCheckpoint(float timeExtension, float obstacleDecrease)
    {
        if (Finished) return;

        string text;
        if (Rules == GameRules.Classic)
        {
            float added = timeExtension + Character.checkpointBonus;
            TimeLeft += added;
            text = Loc.F("hud.checkpoint", Mathf.RoundToInt(added));
            SetSpeed(moveSpeed + CheckpointSpeedUp);
        }
        else
        {
            coinScore += 500;
            text = Loc.T("hud.checkpointScore");
        }

        // the next zone begins right behind the arch
        if (pendingZones.Count > 0) text += "\n<size=32>" + Loc.T("zone." + pendingZones.Dequeue()) + "</size>";
        ShowToast(text, new Color(0.5f, 1f, 0.6f), 2.2f);
        Sfx.Play(SynthAudio.Checkpoint, 0.6f);
        obstacleSpawnTime = Mathf.Max(MinObstacleSpawnTime, obstacleSpawnTime - obstacleDecrease);
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
                if (Rules == GameRules.Classic)
                {
                    TimeLeft += HourglassSeconds;
                    ShowToast(Loc.F("hud.hourglass", Mathf.RoundToInt(HourglassSeconds)), new Color(1f, 0.85f, 0.35f));
                }
                else
                {
                    coinScore += 300;
                    ShowToast("+300", new Color(1f, 0.85f, 0.35f));
                }
                break;
        }
    }

    // Called by PlayerAvatar before a hit: true = the shield took it.
    public bool TryAbsorbHit()
    {
        if (!ShieldActive) return false;
        shieldTime = 0f;
        ShowToast(Loc.T("hud.shieldSaved"), new Color(0.4f, 0.9f, 1f));
        trauma = Mathf.Max(trauma, 0.4f);
        return true;
    }

    public void OnHit()
    {
        OnHit(2f);
    }

    // Classic mode: a hit takes time away, the combo is lost, the road stumbles, the screen flashes and shakes.
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
        if (TimeLeft <= 0f) Finish(CrashCause.TimeUp);
    }

    // Called by PlayerAvatar: the camera follows the jump and dips a little on landing.
    public void OnLanded()
    {
        dip = 0.18f;
    }

    // ================= speed =================

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

    // The road speed, the "gravity" of the falling obstacles and the field of view change together.
    bool SetSpeed(float newSpeed)
    {
        float max = Rules == GameRules.Endless ? EndlessMaxSpeed : MaxMoveSpeedClassic;
        newSpeed = Mathf.Clamp(newSpeed, MinMoveSpeed, max);
        float amount = newSpeed - moveSpeed;
        if (Mathf.Approximately(amount, 0f)) return false;
        moveSpeed = newSpeed;
        gravityZ = Mathf.Clamp(gravityZ - amount, MinGravityZ, MaxGravityZ);
        return true;
    }

    public void NotifyHit()
    {
        if (hub != null) hub.SendTo(Owner, "{\"t\":\"hit\"}");
    }

    // ================= road =================

    void SpawnChunk()
    {
        Vector3 pos;
        Quaternion rot;
        if (chunks.Count == 0)
        {
            pos = new Vector3(originX, 0f, -ChunksBehindPlayer * ChunkLength);
            rot = Quaternion.identity;
        }
        else
        {
            Chunk last = chunks[chunks.Count - 1];
            pos = last.ExitPosition;
            rot = last.ExitRotation;
        }

        GameObject prefab = ChooseChunkPrefab();
        GameObject go = Instantiate(prefab, pos, rot, chunkParent);
        Chunk chunk = go.GetComponent<Chunk>();
        if (chunk == null) chunk = go.AddComponent<Chunk>();

        // the pieces around the start and right after a corner get no obstacles
        if ((settingUp && pos.z < SafeStartZ) || justTurnedSpawn) chunk.MakeSafe();
        justTurnedSpawn = chunk.IsCorner;

        if (chunk.IsCorner && nextCorner == null) nextCorner = chunk;
        chunks.Add(chunk);
        chunkIndex++;
    }

    GameObject ChooseChunkPrefab()
    {
        GameObject[][] zones = assets.biomeChunks;
        bool hasZones = zones != null && zones.Length > 0;
        chunksSinceCorner++;

        // a corner every few pieces (not at the very start)
        GameObject[][] corners = assets.biomeCorners;
        if (corners != null && corners.Length > biome && corners[biome] != null
            && chunkIndex >= FirstCornerIndex && chunksSinceCorner >= cornerGap)
        {
            int dir = lastCornerDir == 0 ? (Random.value < 0.5f ? -1 : 1)
                    : (Random.value < 0.7f ? -lastCornerDir : lastCornerDir);
            lastCornerDir = dir;
            chunksSinceCorner = 0;
            cornerGap = Random.Range(6, 10);
            GameObject c = corners[biome][dir < 0 ? 0 : 1];
            if (c != null) return c;
        }

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

        // pieces far behind the camera are removed, new ones are added at the end of the road
        float recycleZ = Cam.transform.position.z - 14f;
        for (int i = chunks.Count - 1; i >= 0; i--)
        {
            Chunk c = chunks[i];
            if (c == nextCorner) continue;
            Vector3 centre = c.transform.TransformPoint(new Vector3(0f, 0f, 5f));
            if (centre.z < recycleZ && c.ExitPosition.z < recycleZ + 5f)
            {
                chunks.RemoveAt(i);
                Destroy(c.gameObject);
            }
        }
        while (chunks.Count < startingChunks) SpawnChunk();
    }

    // ================= corners =================

    // Left / right pressed: if we are standing at a corner that turns that way - turn.
    public bool TryTurn(int dir)
    {
        if (!Running || nextCorner == null || turnT >= 0f) return false;
        float z = nextCorner.PivotWorld.z;
        if (z > TurnWindowAhead || z < TurnWindowBehind) return false;
        if (dir != nextCorner.Turn) return false;
        StartTurn();
        return true;
    }

    // Ran into the dead end with a shield (or in classic mode): the road turns by itself.
    public void ForceTurn()
    {
        if (nextCorner != null && turnT < 0f) StartTurn();
    }

    void StartTurn()
    {
        Chunk corner = nextCorner;
        Vector3 pivot = corner.PivotWorld;
        Quaternion delta = Quaternion.Euler(0f, -corner.Turn * 90f, 0f);

        // the pivot ends up where the hero is (x = road centre, z = 0) and the new road points forward
        Vector3 pivotInParent = Quaternion.Inverse(chunkParent.rotation) * (pivot - chunkParent.position);
        turnFromPos = chunkParent.position;
        turnFromRot = chunkParent.rotation;
        turnToRot = delta * chunkParent.rotation;
        turnToPos = new Vector3(originX, 0f, 0f) - turnToRot * pivotInParent;
        turnT = 0f;
        turnKick = corner.Turn;

        // falling obstacles belong to the old direction
        foreach (Transform t in obstacleParent) Destroy(t.gameObject);

        // the next corner further along the road
        nextCorner = null;
        int idx = chunks.IndexOf(corner);
        for (int i = idx + 1; i < chunks.Count; i++)
            if (chunks[i].IsCorner) { nextCorner = chunks[i]; break; }

        Sfx.Play(SynthAudio.Jump, 0.35f);
        coinScore += 50;
    }

    void TickTurn(float dt)
    {
        turnT += dt / TurnDuration;
        float k = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(turnT));
        chunkParent.position = Vector3.Lerp(turnFromPos, turnToPos, k);
        chunkParent.rotation = Quaternion.Slerp(turnFromRot, turnToRot, k);
        if (turnT >= 1f)
        {
            turnT = -1f;
            chunkParent.position = turnToPos;
            chunkParent.rotation = turnToRot;
        }
    }

    // ================= falling obstacles =================

    void TickObstacleSpawner(float dt)
    {
        spawnTimer += dt;
        if (spawnTimer < obstacleSpawnTime) return;
        spawnTimer = 0f;

        // only on a straight road: before a corner they would fall where there is no road
        if (nextCorner != null && nextCorner.PivotWorld.z < ObstacleSpawnDistance + 12f) return;
        if (assets.obstaclePrefabs == null || assets.obstaclePrefabs.Length == 0) return;
        GameObject prefab = assets.obstaclePrefabs[Random.Range(0, assets.obstaclePrefabs.Length)];
        if (prefab == null) return;
        Vector3 pos = new Vector3(originX + PlayerAvatar.Lanes[Random.Range(0, PlayerAvatar.Lanes.Length)] + Random.Range(-0.6f, 0.6f),
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

        // An upright screen (a phone, or a narrow strip of a split screen) needs a higher camera
        // further back to see all three lanes; a wide screen - a low camera close behind the hero.
        float aspect = Mathf.Max(0.3f, Cam.aspect);
        float back, height, lookZ;
        if (aspect < 0.9f)
        {
            baseFov = 74f;
            back = 6.4f;
            height = 4.3f;
            lookZ = 5f;
        }
        else
        {
            baseFov = 66f;
            float tanHalfV = Mathf.Tan(baseFov * 0.5f * Mathf.Deg2Rad);
            back = Mathf.Clamp(4.4f / (tanHalfV * aspect), 3.6f, 6f);
            height = 2.3f + (back - 3.6f) * 0.45f;
            lookZ = 1.5f;
        }
        float speed01 = Mathf.Clamp01((moveSpeed - 7f) / 16f);

        Vector3 hero = avatar.transform.position;

        if (dt > 0f)
        {
            float targetX = originX + (hero.x - originX) * 0.7f;
            camX = Mathf.SmoothDamp(camX, targetX, ref camXVelocity, 0.1f, Mathf.Infinity, dt);
            camRoll = Mathf.Lerp(camRoll, Mathf.Clamp(-camXVelocity * 1.2f, -4f, 4f), 1f - Mathf.Exp(-6f * dt));
            camHeightFollow = Mathf.Lerp(camHeightFollow, avatar.Height * 0.4f, 1f - Mathf.Exp(-8f * dt));
            dip = Mathf.MoveTowards(dip, 0f, dt * 0.9f);
            punch = Mathf.MoveTowards(punch, 0f, dt * 4f);
            fovKick = Mathf.MoveTowards(fovKick, 0f, dt * 1.5f);
            trauma = Mathf.MoveTowards(trauma, 0f, dt * 1.4f);
            turnKick = Mathf.MoveTowards(turnKick, 0f, dt * 3f);
        }

        Vector3 gPos = new Vector3(camX, height + camHeightFollow - dip - punch * 0.15f, -back + punch * 0.5f);
        Vector3 gLook = new Vector3(Mathf.Lerp(camX, hero.x, 0.4f), 0.8f + camHeightFollow * 0.5f, lookZ + speed01 * 2f);
        // a corner: the camera swings a little with the road
        Quaternion gRot = Quaternion.LookRotation(gLook - gPos) * Quaternion.Euler(0f, turnKick * 14f, camRoll - turnKick * 6f);

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
        // ---- the end: a slow orbit to the hero's face ----
        else if (Finished)
        {
            float w = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(finishTimer / 1.2f));
            Vector3 oPos; Quaternion oRot;
            Orbit(hero, Mathf.Min(Mathf.PI * 0.8f, finishTimer * 0.9f), 4.6f, out oPos, out oRot);
            pos = Vector3.Lerp(gPos, oPos, w);
            rot = Quaternion.Slerp(gRot, oRot, w);
        }

        // ---- shake: smooth Perlin noise ----
        float shake = trauma * trauma;
        if (shake > 0.0001f)
        {
            float seed = Index * 31.7f;
            pos += new Vector3(Mathf.PerlinNoise(seed, t * 22f) - 0.5f, Mathf.PerlinNoise(seed + 5f, t * 22f) - 0.5f, 0f) * (shake * 0.8f);
            rot *= Quaternion.Euler(0f, 0f, (Mathf.PerlinNoise(seed + 9f, t * 18f) - 0.5f) * shake * 10f);
        }

        Cam.transform.position = pos;
        Cam.transform.rotation = rot;

        // the view widens only a little with speed (the hero must stay big on the screen)
        speedFov = Mathf.Lerp(speedFov, speed01 * 10f, 1f - Mathf.Exp(-2f * dt));
        currentFov = baseFov + speedFov + fovKick * 4f;
        Cam.fieldOfView = Mathf.Clamp(currentFov, MinFov, MaxFov);
    }

    // A point on a circle around the hero (angle 0 = behind, PI = in front) looking at the chest.
    void Orbit(Vector3 hero, float angle, float dist, out Vector3 pos, out Quaternion rot)
    {
        Vector3 target = hero + Vector3.up * 1.2f;
        pos = target + new Vector3(Mathf.Sin(angle) * dist, 0.6f, -Mathf.Cos(angle) * dist);
        rot = Quaternion.LookRotation(target - pos);
    }

    // Thin glowing streaks that rush past the camera at high speed.
    void BuildSpeedLines()
    {
        int count = Lite ? 8 : 18;
        speedLines = new Transform[count];
        speedLineZ = new float[count];
        for (int i = 0; i < count; i++)
        {
            GameObject g = MatLib.Prim(PrimitiveType.Cube, "Speed Line", Cam.transform, Vector3.zero, new Vector3(0.025f, 0.025f, 1f),
                                       new Color(0.9f, 0.95f, 1f), false, default(Vector3), 0.2f, 1.5f, Surface.Plain);
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
        float k = Running ? Mathf.Clamp01((moveSpeed - 12f) / 8f) : 0f;
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

    public string CauseText()
    {
        switch (Cause)
        {
            case CrashCause.MissedTurn: return Loc.T("end.missedTurn");
            case CrashCause.Caught: return Loc.T("end.caught");
            case CrashCause.Obstacle: return Loc.T("end.crashed");
            case CrashCause.TimeUp: return Loc.T("end.timeUp");
            default: return "";
        }
    }

    void UpdateHud()
    {
        if (hud == null) return;
        float dt = Time.deltaTime;

        hud.score.text = Score.ToString("N0", CultureInfo.InvariantCulture).Replace(',', ' ');
        hud.distance.text = Loc.F("hud.distance", Distance);
        hud.coins.text = CoinsCollected.ToString();

        // combo multiplier: "x3" with a little pop when it grows
        int mult = Multiplier;
        hud.combo.text = mult > 1 ? Loc.F("hud.comboShort", mult) : "";
        comboPulse = Mathf.Max(0f, comboPulse - dt * 3f);
        hud.combo.transform.localScale = Vector3.one * (1f + 0.5f * comboPulse);

        // active power-ups with their remaining time; the golem's warning
        StringBuilder st = new StringBuilder();
        if (ShieldActive) st.Append("<color=#66e6ff>").Append(Loc.T("hud.shieldShort")).Append(' ').Append(Mathf.CeilToInt(shieldTime)).Append("</color>   ");
        if (MagnetActive) st.Append("<color=#ff8a80>").Append(Loc.T("hud.magnetShort")).Append(' ').Append(Mathf.CeilToInt(magnetTime)).Append("</color>   ");
        if (chaseTimer > 0f && !Finished) st.Append("<color=#ffb74d>").Append(Loc.T("hud.golemNear")).Append("</color>");
        hud.status.text = st.ToString();

        // time bar (classic): green -> yellow -> red, blinks at the end
        if (Rules == GameRules.Classic)
        {
            hud.time.text = Loc.F("hud.seconds", TimeLeft.ToString("F1", CultureInfo.InvariantCulture));
            float ratio = Mathf.Clamp01(TimeLeft / TimeBarMax);
            hud.timeFill.anchorMax = new Vector2(Mathf.Lerp(0.01f, 0.99f, ratio), 0.88f);
            Color c = ratio > 0.4f ? new Color(0.30f, 0.80f, 0.35f)
                    : ratio > 0.2f ? new Color(1f, 0.75f, 0.1f)
                    : new Color(1f, 0.30f, 0.30f);
            if (!Finished && TimeLeft < 8f) c.a = 0.6f + 0.4f * Mathf.Abs(Mathf.Sin(Time.time * 6f));
            hud.timeFillImage.color = c;
        }

        // "turn!" arrows when a corner is near
        bool cornerNear = Running && nextCorner != null && turnT < 0f && nextCorner.PivotWorld.z < 22f && nextCorner.PivotWorld.z > TurnWindowBehind;

        if (Finished)
        {
            hud.big.text = Rules == GameRules.Classic ? Loc.F("hud.timeUp", Score) : CauseText() + "\n<size=48>" + Score + "</size>";
            hud.big.color = new Color(1f, 0.55f, 0.5f);
            hud.big.transform.localScale = Vector3.one;
        }
        else if (goTimer > 0f)
        {
            goTimer -= dt;
            hud.big.text = "<color=#ffd54f>" + Loc.T("hud.go") + "</color>";
            hud.big.color = Color.white;
            hud.big.transform.localScale = Vector3.one * (1f + 0.6f * Mathf.Clamp01(goTimer - 0.5f));
            if (goTimer <= 0f) { hud.big.text = ""; hud.big.transform.localScale = Vector3.one; }
        }
        else if (cornerNear)
        {
            string arrow = nextCorner.Turn < 0 ? "◄◄◄" : "►►►";
            float blink = Mathf.Repeat(Time.time * 4f, 1f) < 0.6f ? 1f : 0.35f;
            hud.big.text = "<color=#ffd54f>" + arrow + "</color>";
            hud.big.color = new Color(1f, 1f, 1f, blink);
            hud.big.transform.localScale = Vector3.one;
        }
        else
        {
            hud.big.text = "";
            hud.big.color = new Color(1f, 0.55f, 0.5f);
        }

        // the control hint fades out
        if (hintTimer > 0f)
        {
            hintTimer -= dt;
            Color hc = hud.hint.color;
            hc.a = Mathf.Clamp01(hintTimer);
            hud.hint.color = hc;
            if (hintTimer <= 0f) hud.hint.text = "";
        }

        // a red flash along the screen on a hit
        flashAlpha = Mathf.MoveTowards(flashAlpha, 0f, dt * 1.6f);
        if (hud.flash != null)
        {
            hud.flash.color = new Color(1f, 0.1f, 0.1f, flashAlpha);
            hud.flash.enabled = flashAlpha > 0.001f;
        }

        // the pop-up text fades out smoothly
        if (toastTimeLeft > 0f)
        {
            toastTimeLeft -= dt;
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
        float shownTime = Rules == GameRules.Classic ? TimeLeft : -1f;
        sb.Append("{\"t\":\"play\",\"time\":").Append(shownTime.ToString("F1", CultureInfo.InvariantCulture));
        sb.Append(",\"score\":").Append(Score);
        sb.Append(",\"dist\":").Append(Distance);
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
