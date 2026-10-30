using UnityEngine;

// Moves an object smoothly back and forth between two points (a moving obstacle).
// From the book, Part 7.2.
public class Oscillator : MonoBehaviour
{
    [SerializeField] Vector3 movementVector;
    [SerializeField] float speed;

    Vector3 startPosition;
    Vector3 endPosition;
    float movementFactor;

    void Start()
    {
        startPosition = transform.position;
        endPosition = startPosition + movementVector;
    }

    void Update()
    {
        movementFactor = Mathf.PingPong(Time.time * speed, 1f);
        transform.position = Vector3.Lerp(startPosition, endPosition, movementFactor);
    }

    // A line in the Scene window: shows where the obstacle will travel
    void OnDrawGizmosSelected()
    {
        Vector3 from = Application.isPlaying ? startPosition : transform.position;
        Gizmos.color = Color.yellow;
        Gizmos.DrawLine(from, from + movementVector);
        Gizmos.DrawWireCube(from + movementVector, transform.lossyScale);
    }
}
