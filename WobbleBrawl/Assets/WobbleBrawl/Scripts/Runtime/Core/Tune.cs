using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Every gameplay number in one place, so feel can be tuned without hunting through systems.
    /// Units: metres, seconds, degrees, m/s, m/s^2.
    /// </summary>
    public static class Tune
    {
        // --- Physics world ---
        public const float FixedStep = 1f / 90f;
        public const int SolverIterations = 14;
        public const int SolverVelocityIterations = 4;

        // --- Body ---
        public const float StandHeight = 0.95f;       // pelvis centre above ground when standing
        public const float GroundProbe = 1.3f;        // sphere-cast length from the pelvis
        public const float GroundProbeRadius = 0.2f;
        public const float HoverSpring = 320f;
        public const float HoverDamper = 34f;
        public const float UprightSpring = 260f;
        public const float UprightDamper = 26f;
        public const float ChestUprightSpring = 200f;
        public const float ChestUprightDamper = 20f;

        // --- Locomotion ---
        public const float WalkSpeed = 3.6f;
        public const float GroundAccel = 12f;
        public const float AirAccel = 2.5f;
        public const float TurnRate = 9f;             // rad/s
        public const float JumpVelocity = 5.4f;
        public const float JumpCooldown = 0.35f;
        public const float CarrySpeedFactor = 0.72f;

        // --- Arms ---
        public const float ReachLength = 0.72f;
        public const float ReachForce = 70f;
        public const float ReachDamping = 9f;
        public const float HoldingArmBoost = 2.6f;
        public const float GripBreakForce = 9000f;
        public const float GrabRadius = 0.17f;
        public const float PitchMin = -60f;
        public const float PitchMax = 88f;

        // --- Climbing / carrying ---
        public const float ClimbLift = 17f;
        public const float ClimbForward = 6f;
        public const float CarryGravityCompUnconscious = 0.8f;
        public const float CarryGravityCompConscious = 0.35f;
        public const float ThrowForward = 6.5f;
        public const float ThrowUp = 4.0f;

        // --- Combat ---
        public const float PunchWindup = 0.07f, PunchStrike = 0.15f, PunchRecover = 0.14f;
        public const float KickWindup = 0.12f, KickStrike = 0.2f, KickRecover = 0.25f;
        public const float HeadbuttWindup = 0.13f, HeadbuttStrike = 0.16f, HeadbuttRecover = 0.3f;
        public const float DropKickTime = 0.45f, DropKickFlop = 1.0f;
        public const float PunchSpeed = 9f, KickSpeed = 8.5f, HeadbuttSpeed = 6.5f;
        public const float PunchDamage = 14f, KickDamage = 20f, HeadbuttDamage = 27f, DropKickDamage = 30f;
        public const float HeadMultiplier = 1.7f, LimbMultiplier = 0.6f;
        public const float AutoAimRange = 2.1f;

        // --- Consciousness ---
        public const float MaxConsciousness = 100f;
        public const float RegenDelay = 2f;
        public const float RegenRate = 10f;
        public const float KnockoutBase = 3.4f;
        public const float WakeConsciousness = 45f;
        public const float GetUpTime = 0.9f;
        public const float StaggerTime = 0.35f;
        public const int StruggleToBreak = 6;

        // --- Muscle strengths (spring, damper) ---
        public static readonly Vector2 Spine = new Vector2(1700f, 70f);
        public static readonly Vector2 Neck = new Vector2(380f, 16f);
        public static readonly Vector2 Shoulder = new Vector2(480f, 20f);
        public static readonly Vector2 Elbow = new Vector2(280f, 11f);
        public static readonly Vector2 Hip = new Vector2(950f, 42f);
        public static readonly Vector2 Knee = new Vector2(750f, 32f);
        public const float KnockedOutStrength = 0.05f;

        // --- Match ---
        public const float SuddenDeathTime = 120f;
        public const float KothScoreToWin = 30f;
        public const float KothMoveInterval = 22f;
        public const float RespawnDelay = 2.5f;
    }
}
