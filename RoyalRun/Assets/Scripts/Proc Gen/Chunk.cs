using System.Collections.Generic;
using UnityEngine;

public class Chunk : MonoBehaviour
{
    [SerializeField] GameObject fencePrefab;
    [SerializeField] GameObject applePrefab;
    [SerializeField] GameObject coinPrefab;

    [SerializeField] float appleSpawnChance = .3f;
    [SerializeField] float coinSpawnChance = .5f;
    [SerializeField] float coinSeperationLength = 2f;

    // Lanes are now measured from the centre of THIS chunk's road (each player has their own road at their own X).
    [SerializeField] float[] lanes = { -2.5f, 0f, 2.5f };

    List<int> availableLanes = new List<int> { 0, 1, 2 };

    // Used when the chunk template is built from code (ProceduralAssets).
    public void Configure(GameObject fence, GameObject apple, GameObject coin)
    {
        fencePrefab = fence;
        applePrefab = apple;
        coinPrefab = coin;
    }

    void Start()
    {
        SpawnFences();
        SpawnApple();
        SpawnCoins();
    }

    Vector3 LanePosition(int lane, float z)
    {
        return new Vector3(transform.position.x + lanes[lane], transform.position.y, z);
    }

    void SpawnFences()
    {
        int fencesToSpawn = Random.Range(0, lanes.Length);

        for (int i = 0; i < fencesToSpawn; i++)
        {
            if (availableLanes.Count <= 0) break;

            int selectedLane = SelectLane();
            Instantiate(fencePrefab, LanePosition(selectedLane, transform.position.z), Quaternion.identity, this.transform);
        }
    }

    void SpawnApple()
    {
        if (Random.value > appleSpawnChance || availableLanes.Count <= 0 ) return;

        int selectedLane = SelectLane();
        Instantiate(applePrefab, LanePosition(selectedLane, transform.position.z), Quaternion.identity, this.transform);
    }

    void SpawnCoins()
    {
        if (Random.value > coinSpawnChance || availableLanes.Count <= 0) return;

        int selectedLane = SelectLane();

        int maxCoinsToSpawn = 6;
        int coinsToSpawn = Random.Range(1, maxCoinsToSpawn);

        float topOfChunkZPos = transform.position.z + (coinSeperationLength * 2f);

        for (int i = 0; i < coinsToSpawn; i++)
        {
            float spawnPositionZ = topOfChunkZPos - (i * coinSeperationLength);
            Instantiate(coinPrefab, LanePosition(selectedLane, spawnPositionZ), Quaternion.identity, this.transform);
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
