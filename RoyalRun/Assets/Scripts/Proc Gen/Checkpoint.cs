using UnityEngine;

public class Checkpoint : MonoBehaviour
{
    [SerializeField] float checkpointTimeExtension = 5f;
    [SerializeField] float obstacleDecreaseTimeAmount = .2f;

    const string playerString = "Player";

    void OnTriggerEnter(Collider other)
    {
        if (!other.CompareTag(playerString)) return;

        PlayerWorld world = GetComponentInParent<PlayerWorld>();
        if (world != null) world.OnCheckpoint(checkpointTimeExtension, obstacleDecreaseTimeAmount);
    }
}
