using UnityEngine;

/// <summary>
/// A top-down camera that smoothly follows the player from above and behind.
/// It can also shake when the player is hit: CameraFollow.Shake(time, strength).
/// </summary>
public class CameraFollow : MonoBehaviour
{
    [SerializeField] Transform target;
    [SerializeField] Vector3 offset = new Vector3(0f, 14f, -9.5f);
    [SerializeField] float smoothTime = 0.18f;
    [SerializeField] float lookAheadDistance = 1.2f;

    static CameraFollow current;

    Vector3 velocity;
    Vector3 lookAhead;
    Rigidbody targetBody;
    float shakeTimeLeft;
    float shakeDuration;
    float shakeStrength;

    void Awake()
    {
        current = this;
        if (target == null)
        {
            GameObject player = GameObject.FindGameObjectWithTag("Player");
            if (player != null) target = player.transform;
        }
        if (target != null)
        {
            targetBody = target.GetComponent<Rigidbody>();
            // Start already in place, without flying in from the scene origin.
            transform.position = target.position + offset;
            transform.LookAt(target.position);
        }
    }

    void OnDestroy()
    {
        if (current == this) current = null;
    }

    void LateUpdate()
    {
        if (target == null) return;

        // Look a little in the direction the ball is rolling.
        Vector3 wantedLookAhead = Vector3.zero;
        if (targetBody != null)
        {
            Vector3 flatVelocity = targetBody.linearVelocity;
            flatVelocity.y = 0f;
            wantedLookAhead = Vector3.ClampMagnitude(flatVelocity * 0.2f, lookAheadDistance);
        }
        lookAhead = Vector3.Lerp(lookAhead, wantedLookAhead, 3f * Time.deltaTime);

        Vector3 focus = target.position + lookAhead;
        Vector3 wanted = focus + offset;
        transform.position = Vector3.SmoothDamp(transform.position, wanted, ref velocity, smoothTime);
        transform.rotation = Quaternion.LookRotation(-offset.normalized, Vector3.up);

        if (shakeTimeLeft > 0f)
        {
            shakeTimeLeft -= Time.deltaTime;
            float strength = shakeStrength * (shakeTimeLeft / shakeDuration);
            transform.position += Random.insideUnitSphere * strength;
        }
    }

    public static void Shake(float duration, float strength)
    {
        if (current == null) return;
        current.shakeDuration = duration;
        current.shakeTimeLeft = duration;
        current.shakeStrength = strength;
    }
}
