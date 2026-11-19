using UnityEngine;

// A coin (or a gem - the same script with a bigger reward).
public class Coin : Pickup
{
    [SerializeField] int scoreAmount = 100;
    [SerializeField] bool isGem;

    protected override bool Attractable { get { return true; } }

    // Used when the template is built from code (ProceduralAssets).
    public void Configure(int score, bool gem)
    {
        scoreAmount = score;
        isGem = gem;
    }

    protected override void OnPickup(PlayerWorld world)
    {
        world.AddCoinScore(scoreAmount, isGem);
        DebrisBurst.Sparkle(transform.position + Vector3.up, isGem ? new Color(0.8f, 0.5f, 1f) : new Color(1f, 0.85f, 0.3f), world.transform, isGem ? 14 : 6);
        Sfx.Play(isGem ? SynthAudio.Gem : SynthAudio.Coin, isGem ? 0.7f : 0.45f);
    }
}
