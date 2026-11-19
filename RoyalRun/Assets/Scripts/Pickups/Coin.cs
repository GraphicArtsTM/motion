using UnityEngine;

public class Coin : Pickup
{
    [SerializeField] int scoreAmount = 100;

    protected override void OnPickup(PlayerWorld world)
    {
        world.AddCoinScore(scoreAmount);
        Sfx.Play(SynthAudio.Coin, 0.5f);
    }
}
