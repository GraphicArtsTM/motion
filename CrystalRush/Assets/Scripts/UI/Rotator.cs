using UnityEngine;

/// <summary>Slowly spins an object. Used for the decorations of the main menu.</summary>
public class Rotator : MonoBehaviour
{
    [SerializeField] Vector3 degreesPerSecond = new Vector3(0f, 30f, 0f);

    void Update()
    {
        transform.Rotate(degreesPerSecond * Time.deltaTime, Space.World);
    }
}
