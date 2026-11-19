using UnityEngine;

// A falling obstacle: particles, hit sound and camera shake.
// Shaking used to go through Cinemachine Impulse to the single camera. Now there are several cameras,
// so we shake only the camera of the player in whose world the object fell.
public class Rock : MonoBehaviour
{
    [SerializeField] ParticleSystem collisionParticleSystem;
    [SerializeField] AudioSource boulderSmashAudioSource;
    [SerializeField] float shakeModifer = 10f;
    [SerializeField] float collisionCooldown = 1f;

    PlayerWorld world;
    float collisionTimer = 1f;

    void Awake()
    {
        world = GetComponentInParent<PlayerWorld>();
    }

    // Used when the obstacle template is built from code (ProceduralAssets).
    public void Configure(ParticleSystem particles, AudioSource smashSound)
    {
        collisionParticleSystem = particles;
        boulderSmashAudioSource = smashSound;
    }

    void Update()
    {
        collisionTimer += Time.deltaTime;
    }

    void OnCollisionEnter(Collision other)
    {
        if (collisionTimer < collisionCooldown) return;

        FireImpulse();
        CollisionFX(other);
        collisionTimer = 0f;
    }

    void FireImpulse()
    {
        if (world == null || world.Cam == null) return;

        float distance = Vector3.Distance(transform.position, world.Cam.transform.position);
        float shakeIntensity = (1f / Mathf.Max(distance, 0.1f)) * shakeModifer;
        world.Shake(Mathf.Min(shakeIntensity, 1f));
    }

    void CollisionFX(Collision other)
    {
        if (other.contactCount == 0) return;

        ContactPoint contactPoint = other.GetContact(0);
        if (collisionParticleSystem != null)
        {
            collisionParticleSystem.transform.position = contactPoint.point;
            collisionParticleSystem.Play();
        }
        else if (world != null)
        {
            // no particle system - a small burst of splinters made of cubes
            DebrisBurst.Spawn(contactPoint.point, new Color(0.55f, 0.47f, 0.38f), world.transform);
        }
        if (boulderSmashAudioSource != null) boulderSmashAudioSource.Play();
    }
}
