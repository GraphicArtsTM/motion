using UnityEngine;

/// <summary>
/// Danger type 2 - PATROL DRONE.
/// A solid flying robot that goes back and forth between its start point and a second point,
/// waits a little at each end and spins its ring. It is a kinematic Rigidbody moved with MovePosition,
/// so it pushes the player physically; the hit itself is detected by PlayerCollision (tag "Hazard").
/// </summary>
[RequireComponent(typeof(Rigidbody))]
public class PatrolDrone : MonoBehaviour
{
    [SerializeField] Vector3 patrolOffset = new Vector3(6f, 0f, 0f);
    [SerializeField] float speed = 3f;
    [SerializeField] float waitAtEnds = 0.4f;
    [SerializeField] Transform spinningRing;
    [SerializeField] float ringSpinSpeed = 220f;
    [SerializeField] Light warningLight;

    Rigidbody body;
    Vector3 pointA;
    Vector3 pointB;
    bool goingToB = true;
    float waitTimer;

    void Awake()
    {
        body = GetComponent<Rigidbody>();
        body.isKinematic = true;
        body.interpolation = RigidbodyInterpolation.Interpolate;
        pointA = transform.position;
        pointB = pointA + patrolOffset;
    }

    void FixedUpdate()
    {
        if (waitTimer > 0f)
        {
            waitTimer -= Time.fixedDeltaTime;
            return;
        }

        Vector3 target = goingToB ? pointB : pointA;
        Vector3 next = Vector3.MoveTowards(body.position, target, speed * Time.fixedDeltaTime);
        body.MovePosition(next);

        if ((next - target).sqrMagnitude < 0.0001f)
        {
            goingToB = !goingToB;
            waitTimer = waitAtEnds;
        }
    }

    void Update()
    {
        if (spinningRing != null) spinningRing.Rotate(0f, ringSpinSpeed * Time.deltaTime, 0f, Space.Self);
        if (warningLight != null) warningLight.intensity = 1.5f + Mathf.Sin(Time.time * 6f) * 0.7f;
    }

    // Shows the patrol path in the Scene view.
    void OnDrawGizmosSelected()
    {
        Vector3 start = Application.isPlaying ? pointA : transform.position;
        Gizmos.color = Color.red;
        Gizmos.DrawLine(start, start + patrolOffset);
        Gizmos.DrawWireSphere(start + patrolOffset, 0.4f);
    }
}
