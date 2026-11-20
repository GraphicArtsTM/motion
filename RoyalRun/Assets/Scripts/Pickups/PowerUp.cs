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
        Color c = type == PowerUpType.Shield ? new Color(0.4f, 0.9f, 1f) : type == PowerUpType.Magnet ? new Color(1f, 0.45f, 0.45f) : new Color(1f, 0.85f, 0.35f);
        DebrisBurst.Sparkle(transform.position + Vector3.up, c, world.transform, 16);
    }
}
