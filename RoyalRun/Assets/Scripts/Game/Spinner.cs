using UnityEngine;

// Turns its object around the local forward axis (windmill sails, banners on poles...).
public class Spinner : MonoBehaviour
{
    public float degreesPerSecond = 40f;

    void Update()
    {
        transform.Rotate(0f, 0f, degreesPerSecond * Time.deltaTime, Space.Self);
    }
}
