using System.Collections.Generic;
using UnityEngine;

public class Chunk : MonoBehaviour
{
    [SerializeField] GameObject fencePrefab;
    [SerializeField] GameObject applePrefab;
    [SerializeField] GameObject coinPrefab;

    [Header("Extras (optional)")]
    [Tooltip("A tall wall that cannot be jumped over.")]
    [SerializeField] GameObject tallFencePrefab;
    [SerializeField] GameObject gemPrefab;
    [SerializeField] GameObject[] powerUpPrefabs;
    [Tooltip("A hazard that drives across the road (LaneMover).")]
    [SerializeField] GameObject moverPrefab;

    [SerializeField] float appleSpawnChance = .3f;
    [SerializeField] float coinSpawnChance = .5f;
    [SerializeField] float coinSeperationLength = 2f;
    [SerializeField] float tallFenceChance = .3f;
    [SerializeField] float gemChance = .15f;
    [SerializeField] float powerUpChance = .08f;
    [SerializeField] float coinArcChance = .45f;
    [SerializeField] float moverChance = .12f;

    // Lanes are measured from the centre of THIS chunk's road (each player has their own road at their own X).
    [SerializeField] float[] lanes = { -2.5f, 0f, 2.5f };

    List<int> availableLanes = new List<int> { 0, 1, 2 };
    bool safe;

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

    // The pieces around the start get no fences, so nothing hits the player in the first second.
    public void MakeSafe()
    {
        safe = true;
    }

    void Start()
    {
        if (!safe)
        {
            SpawnFences();
            SpawnApple();
            SpawnPowerUp();
            SpawnMover();
        }
        SpawnCoins();
    }

    Vector3 LanePosition(int lane, float z)
    {
        return new Vector3(transform.position.x + lanes[lane], transform.position.y, z);
    }

    void SpawnFences()
    {
        if (fencePrefab == null) return;
        int fencesToSpawn = Random.Range(0, lanes.Length);

        for (int i = 0; i < fencesToSpawn; i++)
        {
            if (availableLanes.Count <= 0) break;

            int selectedLane = SelectLane();
            bool tall = tallFencePrefab != null && Random.value < tallFenceChance;
            GameObject prefab = tall ? tallFencePrefab : fencePrefab;
            Instantiate(prefab, LanePosition(selectedLane, transform.position.z), Quaternion.identity, this.transform);

            // a low fence sometimes has an arc of coins over it - you only get them by jumping
            if (!tall && coinPrefab != null && Random.value < coinArcChance) SpawnCoinArc(selectedLane);
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
            Vector3 p = LanePosition(lane, transform.position.z + dz);
            p.y += 0.2f + h;
            Instantiate(coinPrefab, p, Quaternion.identity, this.transform);
        }
    }

    void SpawnMover()
    {
        if (moverPrefab == null || Random.value > moverChance) return;
        // it drives across all lanes in the middle of the piece, away from the fences at its start
        Vector3 p = new Vector3(transform.position.x, transform.position.y, transform.position.z + 6.5f);
        Instantiate(moverPrefab, p, Quaternion.identity, this.transform);
    }

    void SpawnApple()
    {
        if (applePrefab == null || Random.value > appleSpawnChance || availableLanes.Count <= 0) return;

        int selectedLane = SelectLane();
        Instantiate(applePrefab, LanePosition(selectedLane, transform.position.z), Quaternion.identity, this.transform);
    }

    void SpawnPowerUp()
    {
        if (powerUpPrefabs == null || powerUpPrefabs.Length == 0) return;
        if (Random.value > powerUpChance || availableLanes.Count <= 0) return;

        GameObject prefab = powerUpPrefabs[Random.Range(0, powerUpPrefabs.Length)];
        if (prefab == null) return;
        int selectedLane = SelectLane();
        Instantiate(prefab, LanePosition(selectedLane, transform.position.z + 5f), Quaternion.identity, this.transform);
    }

    void SpawnCoins()
    {
        if (coinPrefab == null || Random.value > coinSpawnChance || availableLanes.Count <= 0) return;

        int selectedLane = SelectLane();

        int maxCoinsToSpawn = 6;
        int coinsToSpawn = Random.Range(1, maxCoinsToSpawn);
        bool gemAtEnd = gemPrefab != null && coinsToSpawn >= 3 && Random.value < gemChance;

        float topOfChunkZPos = transform.position.z + (coinSeperationLength * 2f);

        for (int i = 0; i < coinsToSpawn; i++)
        {
            float spawnPositionZ = topOfChunkZPos - (i * coinSeperationLength);
            // the farthest coin of a long chain may be a gem
            GameObject prefab = (gemAtEnd && i == 0) ? gemPrefab : coinPrefab;
            Instantiate(prefab, LanePosition(selectedLane, spawnPositionZ), Quaternion.identity, this.transform);
        }
    }

    int SelectLane()
    {
        int randomLaneIndex = Random.Range(0, availableLanes.Count);
        int selectedLane = availableLanes[randomLaneIndex];
        availableLanes.RemoveAt(randomLaneIndex);
        return selectedLane;
    }
}
