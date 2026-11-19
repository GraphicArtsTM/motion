using UnityEngine;

// A trigger slightly smaller than the hero, which reports touching a Hazard.
// Why it is needed: the hero has a KINEMATIC Rigidbody, and Unity does not report collisions
// (OnCollisionEnter) between a kinematic body and static colliders such as fences.
// Trigger events, however, always arrive - so fences are detected through this sensor.
// The sensor has no "Player" tag, so coins, apples and checkpoints ignore it.
public class HitSensor : MonoBehaviour
{
    [System.NonSerialized] public PlayerAvatar owner;

    void OnTriggerEnter(Collider other)
    {
        if (owner != null) owner.OnSensorTouch(other);
    }
}
