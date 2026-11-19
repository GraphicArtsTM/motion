using UnityEngine;

public abstract class Pickup : MonoBehaviour
{
    [SerializeField] float rotationSpeed = 100f;
    [SerializeField] float bobHeight = 0.12f;

    const string playerString = "Player";

    protected PlayerWorld world;
    bool taken;          // protection against a double pickup in the same physics step
    float bobPhase;
    float baseY;

    // Coins return true: the magnet pulls them to the player.
    protected virtual bool Attractable { get { return false; } }

    protected virtual void Start()
    {
        world = GetComponentInParent<PlayerWorld>();
        baseY = transform.localPosition.y;
        bobPhase = transform.position.z * 0.7f;    // neighbouring coins bob like a wave
    }

    void Update()
    {
        transform.Rotate(0f, rotationSpeed * Time.deltaTime, 0f);

        bobPhase += Time.deltaTime * 3f;
        Vector3 lp = transform.localPosition;
        lp.y = baseY + Mathf.Sin(bobPhase) * bobHeight;
        transform.localPosition = lp;

        // the magnet: fly to the player
        if (Attractable && world != null && world.MagnetActive && world.AvatarTransform != null)
        {
            Vector3 target = world.AvatarTransform.position + Vector3.up * 0.2f;
            Vector3 to = target - transform.position;
            if (to.sqrMagnitude < PlayerWorld.MagnetRadius * PlayerWorld.MagnetRadius)
            {
                transform.position += to.normalized * Mathf.Min(to.magnitude, 22f * Time.deltaTime);
                baseY = transform.localPosition.y;
                bobHeight = 0f;
            }
        }
    }

    void OnTriggerEnter(Collider other)
    {
        if (taken || !other.CompareTag(playerString)) return;
        taken = true;

        // The pickup lies inside a specific player's world - we ask that world who gets the credit.
        if (world == null) world = GetComponentInParent<PlayerWorld>();
        if (world != null && !world.Finished) OnPickup(world);

        Destroy(gameObject);
    }

    protected abstract void OnPickup(PlayerWorld world);
}
