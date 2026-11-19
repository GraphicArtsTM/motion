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

    [SerializeField] float appleSpawnChance = .3f;
    [SerializeField] float coinSpawnChance = .5f;
    [SerializeField] float coinSeperationLength = 2f;
    [SerializeField] float tallFenceChance = .3f;
    [SerializeField] float gemChance = .15f;
    [SerializeField] float powerUpChance = .08f;

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
            GameObject prefab = (tallFencePrefab != null && Random.value < tallFenceChance) ? tallFencePrefab : fencePrefab;
            Instantiate(prefab, LanePosition(selectedLane, transform.position.z), Quaternion.identity, this.transform);
        }
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
