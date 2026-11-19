using UnityEngine;

// A list of references to prefabs and sounds. It lives on the GameBootstrap object in the Game scene.
//
// In this project all fields may stay EMPTY: the missing models, road pieces, obstacles and music
// are created by code (ProceduralAssets + SynthAudio) when the game starts.
// If you drag your own prefabs or music in here, they are used instead.
public class GameAssets : MonoBehaviour
{
    [Header("Character")]
    public GameObject kingPrefab;
    [Tooltip("Optional: custom models. Index = character number in CharacterCatalog. Empty slot = King.")]
    public GameObject[] characterModels;

    [Header("Road")]
    public GameObject[] chunkPrefabs;
    public GameObject checkpointChunkPrefab;

    [Header("Obstacles")]
    public GameObject[] obstaclePrefabs;

    [Header("Audio")]
    public AudioClip music;

    // Filled by ProceduralAssets: road pieces for every zone (meadows, autumn forest, winter peaks).
    // Empty when you use your own chunk prefabs - then chunkPrefabs are used everywhere.
    [System.NonSerialized] public GameObject[][] biomeChunks;
    [System.NonSerialized] public GameObject[] biomeCheckpoints;

    bool prepared;

    // Fills the empty fields with templates built from code.
    public void EnsureDefaults()
    {
        if (prepared) return;
        prepared = true;

        SynthAudio.Init();

        chunkPrefabs = WithoutNulls(chunkPrefabs);
        obstaclePrefabs = WithoutNulls(obstaclePrefabs);

        bool needTemplates = kingPrefab == null
                             || chunkPrefabs.Length == 0
                             || checkpointChunkPrefab == null
                             || obstaclePrefabs.Length == 0;

        if (needTemplates)
        {
            // The templates lie under an inactive object: their scripts do not run, they are only copied.
            GameObject holder = new GameObject("Templates (built by code)");
            holder.SetActive(false);
            holder.transform.SetParent(transform, false);
            ProceduralAssets.Fill(this, holder.transform);
        }

        if (music == null) music = SynthAudio.Music;
    }

    static GameObject[] WithoutNulls(GameObject[] arr)
    {
        if (arr == null) return new GameObject[0];
        System.Collections.Generic.List<GameObject> list = new System.Collections.Generic.List<GameObject>();
        foreach (GameObject g in arr) if (g != null) list.Add(g);
        return list.ToArray();
    }

    public GameObject ModelFor(int characterIndex)
    {
        if (characterModels != null && characterIndex >= 0 && characterIndex < characterModels.Length
            && characterModels[characterIndex] != null)
            return characterModels[characterIndex];
        return kingPrefab;
    }
}
