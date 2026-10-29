using UnityEngine;

/// <summary>
/// A bonus on the level: an extra life or extra time.
/// </summary>
public class Pickup : MonoBehaviour
{
    public enum PickupType { ExtraLife, ExtraTime }

    [SerializeField] PickupType type = PickupType.ExtraLife;
    [SerializeField] int lives = 1;
    [SerializeField] float seconds = 10f;
    [SerializeField] float spinSpeed = 120f;
    [SerializeField] ParticleSystem collectEffectPrefab;

    bool collected;

    void Update()
    {
        transform.Rotate(0f, spinSpeed * Time.deltaTime, 0f, Space.World);
    }

    public void Collect()
    {
        GameManager game = GameManager.Instance;
        if (collected || game == null || game.State != GameState.Playing) return;
        collected = true;

        if (type == PickupType.ExtraLife) game.AddLife(lives);
        else game.AddTime(seconds);

        if (collectEffectPrefab != null) Instantiate(collectEffectPrefab, transform.position, Quaternion.identity);
        AudioManager.Play(Sfx.Pickup);
        Destroy(gameObject);
    }
}
