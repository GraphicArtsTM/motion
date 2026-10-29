using System.Collections;
using UnityEngine;

/// <summary>
/// Everything the player touches goes through here, sorted by TAG:
///   "Hazard"  - laser beam, spikes, drone: lose a life, get pushed back, blink for a while;
///   "Crystal" - collect it;
///   "Pickup"  - bonus (extra life or extra time);
///   "Finish"  - the exit portal.
/// </summary>
[RequireComponent(typeof(Rigidbody))]
public class PlayerCollision : MonoBehaviour
{
    const string HazardTag = "Hazard";
    const string CrystalTag = "Crystal";
    const string PickupTag = "Pickup";
    const string PortalTag = "Finish";

    [SerializeField] float invulnerableTime = 1.5f;
    [SerializeField] float knockbackSpeed = 9f;
    [SerializeField] float fallLimitY = -5f;
    [SerializeField] Renderer bodyRenderer;
    [SerializeField] ParticleSystem hitEffectPrefab;

    Rigidbody body;
    Vector3 spawnPosition;
    float invulnerableUntil;

    public bool IsInvulnerable => Time.time < invulnerableUntil;

    void Awake()
    {
        body = GetComponent<Rigidbody>();
        spawnPosition = transform.position;
        if (bodyRenderer == null) bodyRenderer = GetComponentInChildren<Renderer>();
    }

    void Update()
    {
        // Fell off the level (for example after a very strong dash): lose a life and come back.
        if (transform.position.y < fallLimitY)
        {
            body.linearVelocity = Vector3.zero;
            body.angularVelocity = Vector3.zero;
            transform.position = spawnPosition;
            TakeHit(transform.position, false);
        }
    }

    // Solid obstacles (drones) use normal collisions.
    void OnCollisionEnter(Collision collision)
    {
        if (collision.gameObject.CompareTag(HazardTag))
        {
            TakeHit(ContactPoint(collision), true);
        }
    }

    void OnCollisionStay(Collision collision)
    {
        if (collision.gameObject.CompareTag(HazardTag))
        {
            TakeHit(ContactPoint(collision), true);
        }
    }

    // Lasers, spikes, crystals, bonuses and the portal are triggers.
    void OnTriggerEnter(Collider other)
    {
        if (other.CompareTag(HazardTag))
        {
            TakeHit(other.ClosestPoint(transform.position), true);
        }
        else if (other.CompareTag(CrystalTag))
        {
            if (other.TryGetComponent(out Crystal crystal)) crystal.Collect();
        }
        else if (other.CompareTag(PickupTag))
        {
            if (other.TryGetComponent(out Pickup pickup)) pickup.Collect();
        }
        else if (other.CompareTag(PortalTag))
        {
            if (other.TryGetComponent(out ExitPortal portal)) portal.TryEnter();
        }
    }

    // A laser can switch on while the player is already inside it.
    void OnTriggerStay(Collider other)
    {
        if (other.CompareTag(HazardTag))
        {
            TakeHit(other.ClosestPoint(transform.position), true);
        }
    }

    static Vector3 ContactPoint(Collision collision)
    {
        return collision.contactCount > 0 ? collision.GetContact(0).point : collision.transform.position;
    }

    void TakeHit(Vector3 hitPoint, bool pushBack)
    {
        GameManager game = GameManager.Instance;
        if (IsInvulnerable || game == null || game.State != GameState.Playing) return;

        invulnerableUntil = Time.time + invulnerableTime;
        game.LoseLife();

        if (pushBack)
        {
            Vector3 away = transform.position - hitPoint;
            away.y = 0f;
            if (away.sqrMagnitude < 0.001f) away = -body.linearVelocity;
            away.y = 0f;
            away = away.sqrMagnitude < 0.001f ? Vector3.back : away.normalized;
            body.linearVelocity = away * knockbackSpeed;
        }

        if (hitEffectPrefab != null) Instantiate(hitEffectPrefab, transform.position, Quaternion.identity);
        AudioManager.Play(Sfx.Hit);
        CameraFollow.Shake(0.25f, 0.35f);
        StartCoroutine(Blink());
    }

    IEnumerator Blink()
    {
        if (bodyRenderer == null) yield break;
        while (IsInvulnerable)
        {
            bodyRenderer.enabled = !bodyRenderer.enabled;
            yield return new WaitForSeconds(0.1f);
        }
        bodyRenderer.enabled = true;
    }
}
