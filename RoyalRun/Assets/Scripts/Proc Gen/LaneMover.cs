using UnityEngine;

// Moves a hazard from side to side across the road (for example, a runaway cart).
// The movement is measured from the centre of the road piece it stands on.
public class LaneMover : MonoBehaviour
{
    [SerializeField] float range = 2.6f;      // metres to each side of the road centre
    [SerializeField] float period = 3.2f;     // seconds for a full left-right-left trip
    [SerializeField] Transform wheels;        // optional: spun while moving

    float phase;
    float lastX;

    public void Configure(Transform spinningPart)
    {
        wheels = spinningPart;
    }

    void Start()
    {
        phase = Random.value * Mathf.PI * 2f;
        lastX = transform.localPosition.x;
    }

    void Update()
    {
        phase += Time.deltaTime * Mathf.PI * 2f / period;
        Vector3 p = transform.localPosition;
        p.x = Mathf.Sin(phase) * range;
        transform.localPosition = p;

        // face the direction of travel and spin the wheels
        float dx = p.x - lastX;
        lastX = p.x;
        if (Mathf.Abs(dx) > 0.0001f)
        {
            transform.localRotation = Quaternion.Slerp(transform.localRotation,
                Quaternion.Euler(0f, dx > 0f ? 90f : -90f, 0f), 1f - Mathf.Exp(-8f * Time.deltaTime));
            if (wheels != null) wheels.Rotate(Mathf.Abs(dx) * 220f, 0f, 0f, Space.Self);
        }
    }
}
