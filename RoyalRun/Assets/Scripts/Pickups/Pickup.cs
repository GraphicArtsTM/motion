using UnityEngine;

public abstract class Pickup : MonoBehaviour
{
    [SerializeField] float rotationSpeed = 100f;

    const string playerString = "Player";

    bool taken;     // protection against a double pickup in the same physics step

    void Update()
    {
        transform.Rotate(0f, rotationSpeed * Time.deltaTime, 0f);
    }

    void OnTriggerEnter(Collider other)
    {
        if (taken || !other.CompareTag(playerString)) return;
        taken = true;

        // The pickup lies inside a specific player's world - we ask that world who gets the credit.
        PlayerWorld world = GetComponentInParent<PlayerWorld>();
        if (world != null) OnPickup(world);

        Destroy(gameObject);
    }

    protected abstract void OnPickup(PlayerWorld world);
}
