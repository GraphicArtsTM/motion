using System.Collections.Generic;
using System.Globalization;
using System.Text;
using UnityEngine;

// A whole "personal world" for one player: their own road, obstacles, timer, score and camera.
// It combines the former LevelGenerator + ObstacleSpawner + GameManager + ScoreManager + CameraController.
// The worlds stand side by side in the scene (each 100 metres to the right of the previous one) and do not interfere with each other.
public class PlayerWorld : MonoBehaviour
{
    public const float WorldSpacing = 100f;

    // --- settings (values taken from the original MainLevel scene) ---
    const float StartTime = 30f;
    const int StartingChunks = 14;
    const int ChunksBehindPlayer = 2;
    const int CheckpointChunkInterval = 8;
    const float ChunkLength = 10f;
    const float MinMoveSpeed = 2f;
    const float MaxMoveSpeed = 20f;
    const float MinGravityZ = -22f;
    const float MaxGravityZ = -8f;
    const float MinObstacleSpawnTime = 0.2f;
    const float SpawnWidth = 4f;
    const float ObstacleSpawnHeight = 5f;
    const float ObstacleSpawnDistance = 40f;
    const float BaseFov = 75f;
    const float MinFov = 20f;
    const float MaxFov = 120f;
    const float FovPerSpeed = 5f;
    const float TimeBarMax = 40f;

    // --- state ---
    public int Index { get; private set; }
    public PhonePlayer Owner { get; private set; }
    public CharacterDef Character { get; private set; }
    public Camera Cam { get; private set; }
    public bool Finished { get; private set; }
    public int Score { get; private set; }
    public float TimeLeft { get; private set; }
    public float GravityZ { get { return gravityZ; } }
    public float MoveSpeed { get { return moveSpeed; } }
    public float OriginX { get { return originX; } }

    GameAssets assets;
    PhoneHub hub;
    ColumnHud hud;
    PlayerAvatar avatar;
    Transform chunkParent;
    Transform obstacleParent;

    readonly List<GameObject> chunks = new List<GameObject>();
    int chunkIndex = -ChunksBehindPlayer;

    float originX;
    float moveSpeed = 6f;
    float gravityZ = -12f;
    float obstacleSpawnTime = 3f;
    float spawnTimer;
    float targetFov = BaseFov;
    float currentFov = BaseFov;
    float shakeAmplitude;
    float shakeTimeLeft;
    float phoneTimer;
    float toastTimeLeft;

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

        for (int i = 0; i < StartingChunks; i++) SpawnChunk();

        GameObject model = assets.ModelFor(owner.character);
        avatar = PlayerAvatar.Create(this, owner, model, Character, new Vector3(originX, 0f, 0f));

        UpdateCamera(0f);
        UpdateHud();
        PushToPhone(false);
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
        }

        UpdateHud();

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

        // freeze everything still rolling along the road
        foreach (Rigidbody rb in obstacleParent.GetComponentsInChildren<Rigidbody>())
        {
            rb.linearVelocity = Vector3.zero;
            rb.angularVelocity = Vector3.zero;
            rb.isKinematic = true;
        }

        PushToPhone(true);
    }

    public void AddCoinScore(int baseAmount)
    {
        if (Finished) return;
        Score += Mathf.RoundToInt(baseAmount * Character.coinMult);
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
        chunks.Add(chunk);
        chunkIndex++;
    }

    GameObject ChooseChunkPrefab()
    {
        if (chunkIndex % CheckpointChunkInterval == 0 && chunkIndex != 0)
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

        Vector3 pos = new Vector3(camX, height, -back);

        if (shakeTimeLeft > 0f)
        {
            shakeTimeLeft -= dt;
            float k = Mathf.Clamp01(shakeTimeLeft / 0.5f);
            pos += Random.insideUnitSphere * (shakeAmplitude * k);
            if (shakeTimeLeft <= 0f) shakeAmplitude = 0f;
        }

        Cam.transform.position = pos;
        Cam.transform.rotation = Quaternion.LookRotation(new Vector3(camX, 0.8f, 0.5f) - new Vector3(camX, height, -back));

        // smooth field-of-view change when speeding up / slowing down
        currentFov = Mathf.Lerp(currentFov, targetFov, 1f - Mathf.Exp(-3f * dt));
        Cam.fieldOfView = currentFov;
    }

    // ================= UI and phone =================

    void UpdateHud()
    {
        if (hud == null) return;

        hud.time.text = Loc.F("hud.seconds", TimeLeft.ToString("F1", CultureInfo.InvariantCulture));
        hud.score.text = Score.ToString();

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
        if (hud == null) return;
        hud.toast.text = text;
        hud.toast.color = color;
        toastTimeLeft = 1.4f;
    }

    void PushToPhone(bool over)
    {
        if (hub == null || Owner == null) return;
        StringBuilder sb = new StringBuilder();
        sb.Append("{\"t\":\"play\",\"time\":").Append(TimeLeft.ToString("F1", CultureInfo.InvariantCulture));
        sb.Append(",\"score\":").Append(Score);
        sb.Append(",\"over\":").Append((over || Finished) ? "true" : "false").Append('}');
        hub.SendTo(Owner, sb.ToString());
    }

    public void ForcePush()
    {
        PushToPhone(false);
    }
}
