using UnityEngine;

public class Apple : Pickup
{
    [SerializeField] float adjustChangeMoveSpeedAmount = 3f;

    protected override void OnPickup(PlayerWorld world)
    {
        world.ChangeSpeed(adjustChangeMoveSpeedAmount);
        Sfx.Play(SynthAudio.PowerUp, 0.6f);
    }
}
