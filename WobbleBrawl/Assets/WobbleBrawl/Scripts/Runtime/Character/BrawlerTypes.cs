using UnityEngine;

namespace WobbleBrawl
{
    public enum AttackKind { None, Punch, Kick, Headbutt, DropKick }

    public enum PartKind { Pelvis, Chest, Head, UpperArm, ForeArm, Thigh, Shin }

    public enum HatKind { None, TopHat, Beanie, Cap, Viking, Chef, Count }

    /// <summary>What a brain (player or bot) wants the body to do. Movement is in world space.</summary>
    public struct BrawlerCommand
    {
        public Vector3 move;
        public float pitch;
        public bool jump, grabL, grabR, punch, kick;
        public bool jumpPressed, punchPressed, kickPressed;

        public void ClearEdges()
        {
            jumpPressed = punchPressed = kickPressed = false;
        }
    }

    public interface IBrain
    {
        void Think(Brawler self, ref BrawlerCommand cmd, float dt);
    }

    /// <summary>Anything that moves the surface it carries (conveyors, moving platforms, wheels).</summary>
    public interface ISurfaceVelocity
    {
        Vector3 SurfaceVelocityAt(Vector3 worldPoint);
    }

    /// <summary>A player or bot taking part in a match. Survives across rounds.</summary>
    public sealed class Participant
    {
        public int index;
        public string name;
        public Color color;
        public HatKind hat;
        public bool isBot;
        public InputSlot slot;
        public int wins;
        public float score;
        public int knockouts;
        public int eliminations;
        public Brawler brawler;

        public Color PantsColor => Palette.Darken(color, 0.55f);
    }
}
