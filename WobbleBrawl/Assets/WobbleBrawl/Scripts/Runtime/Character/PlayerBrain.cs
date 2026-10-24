using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Turns a device's raw input into a camera-relative command.</summary>
    public sealed class PlayerBrain : IBrain
    {
        readonly InputSlot slot;

        public PlayerBrain(InputSlot slot) { this.slot = slot; }

        public void Think(Brawler self, ref BrawlerCommand cmd, float dt)
        {
            if (GameManager.InputLocked)
            {
                cmd.move = Vector3.zero;
                cmd.grabL = cmd.grabR = cmd.jump = cmd.punch = cmd.kick = false;
                return;
            }

            var raw = slot.Read(dt);
            var cam = GameManager.I != null ? GameManager.I.MainCamera : Camera.main;
            Vector3 fwd = Vector3.forward, right = Vector3.right;
            if (cam != null)
            {
                fwd = cam.transform.forward; fwd.y = 0f;
                if (fwd.sqrMagnitude < 0.001f) fwd = cam.transform.up;
                fwd.y = 0f; fwd.Normalize();
                right = Vector3.Cross(Vector3.up, fwd);
            }
            cmd.move = fwd * raw.move.y + right * raw.move.x;
            cmd.pitch = raw.pitch;
            cmd.jump = raw.jump;
            cmd.grabL = raw.grabL;
            cmd.grabR = raw.grabR;
            cmd.punch = raw.punch;
            cmd.kick = raw.kick;
            cmd.jumpPressed |= raw.jumpDown;
            cmd.punchPressed |= raw.punchDown;
            cmd.kickPressed |= raw.kickDown;
        }
    }
}
