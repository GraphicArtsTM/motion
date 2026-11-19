using UnityEngine;

public enum PowerUpType { Shield, Magnet, Hourglass }

// A rare bonus on the road:
//   Shield    - the next hit (or 10 seconds) does no harm;
//   Magnet    - coins fly to the player for 8 seconds;
//   Hourglass - +4 seconds on the timer.
public class PowerUp : Pickup
{
    [SerializeField] PowerUpType type;

    public void Configure(PowerUpType t)
    {
        type = t;
    }

    protected override void OnPickup(PlayerWorld world)
    {
        world.ActivatePowerUp(type);
        Sfx.Play(SynthAudio.Checkpoint, 0.55f);
    }
}
