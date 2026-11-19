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
    const float BaseFov = 75f;
    const float MinFov = 20f;
    const float MaxFov = 120f;
    const float FovPerSpeed = 5f;
    const float TimeBarMax = 40f;
    const int CoinsPerComboStep = 10;
    const int MaxMultiplier = 5;
    const float ShieldDuration = 10f;
    const float MagnetDuration = 8f;
    const float HourglassSeconds = 4f;
    const int SpeedLineCount = 18;

    // --- state ---
    public int Index { get; private set; }
    public PhonePlayer Owner { get; private set; }
    public CharacterDef Character { get; private set; }
    public Camera Cam { get; private set; }
    public bool Finished { get; private set; }
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

    GameAssets assets;
    PhoneHub hub;
    ColumnHud hud;
    PlayerAvatar avatar;
    Transform chunkParent;
    Transform obstacleParent;

    readonly List<GameObject> chunks = new List<GameObject>();
    int chunkIndex = -ChunksBehindPlayer;
    bool settingUp;

    float originX;
    float moveSpeed = 6f;
    float gravityZ = -12f;
    float obstacleSpawnTime = 3f;
    float spawnTimer = -FirstObstacleDelay;
    float targetFov = BaseFov;
    float currentFov = BaseFov;
    float shakeAmplitude;
    float shakeTimeLeft;
    float phoneTimer;
    float toastTimeLeft;
    float camHeightFollow;

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
        Cam.farClipPlane = 130f;
        Cam.clearFlags = CameraClearFlags.SolidColor;
        Cam.backgroundColor = new Color(0.10f, 0.06f, 0.20f, 1f);   // fog colour from the original scene
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
        UpdateCamera(0f);
        UpdateHud();
        PushToPhone(false);

        // a reminder how to jump
        string jumpHint = owner.isKeyboard ? Loc.F("hud.jumpKey", KeyName(owner.keyboardScheme)) : Loc.T("hud.jumpTap");
        ShowToast(jumpHint, new Color(0.7f, 0.9f, 1f), 3f);
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

        if (!Finished)
        {
            TickTime(dt);
            TickObstacleSpawner(dt);
            MoveChunks(dt);
            distance += moveSpeed * dt;
            if (shieldTime > 0f) shieldTime -= dt;
            if (magnetTime > 0f) magnetTime -= dt;
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
        int mult = Multiplier;
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
        ShowToast(Loc.F("hud.checkpoint", Mathf.RoundToInt(added)), new Color(0.5f, 1f, 0.6f));
        Sfx.Play(SynthAudio.Checkpoint, 0.6f);
        obstacleSpawnTime = Mathf.Max(MinObstacleSpawnTime, obstacleSpawnTime - obstacleDecrease);
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
        comboCoins = 0;
        Shake(0.6f);
        NotifyHit();
    }

    // ================= speed (apples and hits) =================

    public void ChangeSpeed(float amount)
    {
        if (Finished) return;
        if (amount < 0f) amount *= Character.hitSlowMult;

        float newSpeed = Mathf.Clamp(moveSpeed + amount, MinMoveSpeed, MaxMoveSpeed);
        if (Mathf.Approximately(newSpeed, moveSpeed)) return;

        moveSpeed = newSpeed;
        if (amount > 0f) ShowToast(Loc.T("hud.speedUp"), new Color(1f, 0.9f, 0.3f));
        else ShowToast(Loc.T("hud.hit"), new Color(1f, 0.45f, 0.4f));
        gravityZ = Mathf.Clamp(gravityZ - amount, MinGravityZ, MaxGravityZ);
        targetFov = Mathf.Clamp(targetFov + amount * FovPerSpeed, MinFov, MaxFov);
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
        if (chunkIndex % CheckpointChunkInterval == 0 && chunkIndex != 0 && assets.checkpointChunkPrefab != null)
            return assets.checkpointChunkPrefab;
        return assets.chunkPrefabs[Random.Range(0, assets.chunkPrefabs.Length)];
    }

    void MoveChunks(float dt)
    {
        Vector3 step = Vector3.back * (moveSpeed * dt);
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

    public void Shake(float intensity)
    {
        shakeAmplitude = Mathf.Max(shakeAmplitude, Mathf.Clamp01(intensity) * 0.35f);
        shakeTimeLeft = 0.5f;
    }

    void UpdateCamera(float dt)
    {
        if (Cam == null || avatar == null) return;

        // A narrow strip of the screen sees less road, so for 2-3 players we move the camera back and up.
        float aspect = Mathf.Max(0.3f, Cam.aspect);
        float tanHalfV = Mathf.Tan(BaseFov * 0.5f * Mathf.Deg2Rad);
        float back = Mathf.Clamp(4.6f / (tanHalfV * aspect), 3.8f, 11f);
        float height = 2.25f + (back - 3.8f) * 0.5f;

        float avatarX = avatar.transform.position.x;
        float camX = originX + (avatarX - originX) * 0.6f;

        // the camera rises a little with a jump (smoothly, so it does not jerk)
        camHeightFollow = Mathf.Lerp(camHeightFollow, avatar.Height * 0.4f, 1f - Mathf.Exp(-8f * dt));
        Vector3 pos = new Vector3(camX, height + camHeightFollow, -back);
        Vector3 look = new Vector3(camX, 0.8f + camHeightFollow * 0.5f, 0.5f);

        if (shakeTimeLeft > 0f)
        {
            shakeTimeLeft -= dt;
            float k = Mathf.Clamp01(shakeTimeLeft / 0.5f);
            pos += Random.insideUnitSphere * (shakeAmplitude * k);
            if (shakeTimeLeft <= 0f) shakeAmplitude = 0f;
        }

        Cam.transform.position = pos;
        Cam.transform.rotation = Quaternion.LookRotation(look - pos);

        // smooth field-of-view change when speeding up / slowing down
        currentFov = Mathf.Lerp(currentFov, targetFov, 1f - Mathf.Exp(-3f * dt));
        Cam.fieldOfView = currentFov;
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

        hud.big.text = Finished ? Loc.F("hud.timeUp", Score) : "";

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
