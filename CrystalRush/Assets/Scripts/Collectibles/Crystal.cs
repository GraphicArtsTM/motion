using UnityEngine;

/// <summary>
/// A crystal to collect. It floats and spins so the player can notice it.
/// GameManager counts all crystals in the scene at the start; when every one is collected the portal opens.
/// </summary>
public class Crystal : MonoBehaviour
{
    [SerializeField] float spinSpeed = 90f;
    [SerializeField] float bobHeight = 0.18f;
    [SerializeField] float bobSpeed = 2.2f;
    [SerializeField] ParticleSystem collectEffectPrefab;

    Vector3 startPosition;
    float bobPhase;
    bool collected;

    void Start()
    {
        startPosition = transform.position;
        bobPhase = Random.Range(0f, Mathf.PI * 2f); // crystals do not move in sync
    }

    void Update()
    {
        transform.Rotate(0f, spinSpeed * Time.deltaTime, 0f, Space.World);
        float offset = Mathf.Sin(Time.time * bobSpeed + bobPhase) * bobHeight;
        transform.position = startPosition + Vector3.up * offset;
    }

    public void Collect()
    {
        if (collected) return; // protection from two triggers in one frame
        collected = true;

        if (GameManager.Instance != null) GameManager.Instance.AddCrystal();
        if (collectEffectPrefab != null) Instantiate(collectEffectPrefab, transform.position, Quaternion.identity);
        AudioManager.Play(Sfx.Collect);
        Destroy(gameObject);
    }
}
