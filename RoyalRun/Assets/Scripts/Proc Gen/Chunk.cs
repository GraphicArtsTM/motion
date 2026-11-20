using System.Collections.Generic;
using UnityEngine;

// One road piece and its contents. Everything is placed in the piece's OWN coordinates
// (lanes across, distance along), so a piece can stand rotated - after a corner the road goes sideways.
public class Chunk : MonoBehaviour
{
    [SerializeField] GameObject fencePrefab;
    [SerializeField] GameObject applePrefab;
    [SerializeField] GameObject coinPrefab;

    [Header("Extras (optional)")]
    [Tooltip("A tall wall that cannot be jumped over.")]
    [SerializeField] GameObject tallFencePrefab;
    [Tooltip("A beam at head height: slide under it.")]
    [SerializeField] GameObject beamPrefab;
    [SerializeField] GameObject gemPrefab;
    [SerializeField] GameObject[] powerUpPrefabs;
    [Tooltip("A hazard that drives across the road (LaneMover).")]
    [SerializeField] GameObject moverPrefab;

    [SerializeField] float appleSpawnChance = .3f;
    [SerializeField] float coinSpawnChance = .55f;
    [SerializeField] float coinSeperationLength = 2f;
    [SerializeField] float tallFenceChance = .25f;
    [SerializeField] float beamChance = .25f;
    [SerializeField] float gemChance = .15f;
    [SerializeField] float powerUpChance = .08f;
    [SerializeField] float coinArcChance = .45f;
    [SerializeField] float moverChance = .1f;

    [Header("Corner (junction pieces only)")]
    [SerializeField] int turn;                                   // -1 = the road turns left, 1 = right, 0 = straight
    [SerializeField] Vector3 pivot = new Vector3(0f, 0f, 5.5f);  // the centre of the turning square
    [SerializeField] Vector3 exitPosition = new Vector3(0f, 0f, 10f);
    [SerializeField] float exitYaw;

    // Lanes are measured from the centre of THIS chunk's road.
    [SerializeField] float[] lanes = { -2.5f, 0f, 2.5f };

    List<int> availableLanes = new List<int> { 0, 1, 2 };
    bool safe;
    System.Random rnd;

    // Where this piece starts along the road (metres from the first piece); set by PlayerWorld.
    [System.NonSerialized] public float PathStart;

    // The contents come from this seed, so every device in a Wi-Fi race gets the same road.
    public void SetSeed(int seed)
    {
        rnd = new System.Random(seed);
    }

    float Value() { return (float)rnd.NextDouble(); }
    int Range(int min, int maxExclusive) { return rnd.Next(min, maxExclusive); }

    public int Turn { get { return turn; } }
    public bool IsCorner { get { return turn != 0; } }
    public Vector3 PivotWorld { get { return transform.TransformPoint(pivot); } }
    public Vector3 ExitPosition { get { return transform.TransformPoint(exitPosition); } }
    public Quaternion ExitRotation { get { return transform.rotation * Quaternion.Euler(0f, exitYaw, 0f); } }

    // Used when the chunk template is built from code (ProceduralAssets).
    public void Configure(GameObject fence, GameObject apple, GameObject coin)
    {
        fencePrefab = fence;
        applePrefab = apple;
        coinPrefab = coin;
    }

    public void ConfigureExtras(GameObject tallFence, GameObject gem, GameObject[] powerUps)
    {
        tallFencePrefab = tallFence;
        gemPrefab = gem;
        powerUpPrefabs = powerUps;
    }

    public void ConfigureMover(GameObject mover)
    {
        moverPrefab = mover;
    }

    public void ConfigureBeam(GameObject beam)
    {
        beamPrefab = beam;
    }

    public void ConfigureCorner(int direction)
    {
        turn = direction;
        pivot = new Vector3(0f, 0f, 5.5f);
        exitPosition = new Vector3(direction * 4.5f, 0f, 5.5f);
        exitYaw = direction * 90f;
    }

    // The pieces around the start (and corners) get no obstacles.
    public void MakeSafe()
    {
        safe = true;
    }

    void Start()
    {
        if (rnd == null) rnd = new System.Random(UnityEngine.Random.Range(0, int.MaxValue));
        if (!safe && !IsCorner)
        {
            SpawnFences();
            SpawnApple();
            SpawnPowerUp();
            SpawnMover();
        }
        if (!IsCorner) SpawnCoins();
    }

    // A point on this piece: lane index, distance along the piece, height.
    Vector3 LanePoint(int lane, float along, float up = 0f)
    {
        return transform.TransformPoint(new Vector3(lanes[lane], up, along));
    }

    GameObject Place(GameObject prefab, Vector3 worldPos)
    {
        return Instantiate(prefab, worldPos, transform.rotation, transform);
    }

    void SpawnFences()
    {
        if (fencePrefab == null) return;
        int fencesToSpawn = Range(0, lanes.Length);   // never all three lanes

        for (int i = 0; i < fencesToSpawn; i++)
        {
            if (availableLanes.Count <= 0) break;

            int selectedLane = SelectLane();
            float r = Value();
            if (tallFencePrefab != null && r < tallFenceChance)
            {
                Place(tallFencePrefab, LanePoint(selectedLane, 0f));
            }
            else if (beamPrefab != null && r < tallFenceChance + beamChance)
            {
                // a beam to slide under, with coins along the floor under it
                Place(beamPrefab, LanePoint(selectedLane, 0f));
                if (coinPrefab != null)
                    for (int c = -1; c <= 1; c++) Place(coinPrefab, LanePoint(selectedLane, c * 1.6f));
            }
            else
            {
                Place(fencePrefab, LanePoint(selectedLane, 0f));
                // a low fence sometimes has an arc of coins over it - you only get them by jumping
                if (coinPrefab != null && Value() < coinArcChance) SpawnCoinArc(selectedLane);
            }
        }
    }

    void SpawnCoinArc(int lane)
    {
        const int count = 5;
        for (int i = 0; i < count; i++)
        {
            float t = i / (float)(count - 1);          // 0..1 along the arc
            float dz = Mathf.Lerp(-2.6f, 2.6f, t);
            float h = 1.5f * (1f - (2f * t - 1f) * (2f * t - 1f));
            Place(coinPrefab, LanePoint(lane, dz, 0.2f + h));
        }
    }

    void SpawnApple()
    {
        if (applePrefab == null || Value() > appleSpawnChance || availableLanes.Count <= 0) return;
        Place(applePrefab, LanePoint(SelectLane(), 0f));
    }

    void SpawnPowerUp()
    {
        if (powerUpPrefabs == null || powerUpPrefabs.Length == 0) return;
        if (Value() > powerUpChance || availableLanes.Count <= 0) return;

        GameObject prefab = powerUpPrefabs[Range(0, powerUpPrefabs.Length)];
        if (prefab == null) return;
        Place(prefab, LanePoint(SelectLane(), 5f));
    }

    void SpawnMover()
    {
        if (moverPrefab == null || Value() > moverChance) return;
        // it drives across all lanes in the middle of the piece, away from the fences at its start
        Place(moverPrefab, transform.TransformPoint(new Vector3(0f, 0f, 6.5f)));
    }

    void SpawnCoins()
    {
        if (coinPrefab == null || Value() > coinSpawnChance || availableLanes.Count <= 0) return;

        int selectedLane = SelectLane();
        int coinsToSpawn = Range(2, 7);
        bool gemAtEnd = gemPrefab != null && coinsToSpawn >= 3 && Value() < gemChance;

        // a line of coins in the second half of the piece (away from the obstacles at its start)
        for (int i = 0; i < coinsToSpawn; i++)
        {
            float along = 9.5f - i * coinSeperationLength * 0.7f;
            if (along < 1.5f) break;
            GameObject prefab = (gemAtEnd && i == 0) ? gemPrefab : coinPrefab;
            Place(prefab, LanePoint(selectedLane, along));
        }
    }

    int SelectLane()
    {
        int randomLaneIndex = Range(0, availableLanes.Count);
        int selectedLane = availableLanes[randomLaneIndex];
        availableLanes.RemoveAt(randomLaneIndex);
        return selectedLane;
    }
}
