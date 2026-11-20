using UnityEngine;

public class Apple : Pickup
{
    [SerializeField] float adjustChangeMoveSpeedAmount = 3f;

    protected override void OnPickup(PlayerWorld world)
    {
        world.OnApple(adjustChangeMoveSpeedAmount);
        DebrisBurst.Sparkle(transform.position + Vector3.up * 0.9f, new Color(1f, 0.3f, 0.3f), world.transform, 8);
        Sfx.Play(SynthAudio.Apple, 0.65f);
    }
}
