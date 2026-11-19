using UnityEngine;

public class Apple : Pickup
{
    [SerializeField] float adjustChangeMoveSpeedAmount = 3f;

    protected override void OnPickup(PlayerWorld world)
    {
        world.ChangeSpeed(adjustChangeMoveSpeedAmount);
        DebrisBurst.Sparkle(transform.position + Vector3.up * 0.9f, new Color(1f, 0.3f, 0.3f), world.transform, 8);
        Sfx.Play(SynthAudio.PowerUp, 0.6f);
    }
}
