using UnityEngine;

// Obstacles used to fall and roll towards the player thanks to the shared Physics.gravity.
// But every player now has their own speed, so shared gravity no longer works:
// we turn it off on the obstacle and apply the player's world's "personal" gravity.
[RequireComponent(typeof(Rigidbody))]
public class ObstacleMotion : MonoBehaviour
{
    Rigidbody body;
    PlayerWorld world;

    void Awake()
    {
        body = GetComponent<Rigidbody>();
        body.useGravity = false;
        world = GetComponentInParent<PlayerWorld>();
    }

    void FixedUpdate()
    {
        if (world == null || body.isKinematic) return;

        body.AddForce(new Vector3(0f, Physics.gravity.y, world.GravityZ), ForceMode.Acceleration);

        // flew far behind the player or fell off the road
        if (transform.position.z < -15f || transform.position.y < -25f)
        {
            Destroy(gameObject);
        }
    }
}
