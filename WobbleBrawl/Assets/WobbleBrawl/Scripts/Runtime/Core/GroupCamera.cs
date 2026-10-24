using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Shared couch-multiplayer camera: frames every fighter still in play, zooms out as they spread,
    /// lingers on fighters as they fall, and shakes on heavy hits.
    /// </summary>
    public sealed class GroupCamera : MonoBehaviour
    {
        public Camera cam;
        public float yaw, pitch = 50f, minDist = 9f, maxDist = 30f;
        public bool orbit;
        public Brawler focusOverride;

        Vector3 focus, focusVel;
        float dist = 14f, distVel;
        float shake;
        readonly List<Vector3> points = new List<Vector3>();

        public void Configure(Arena arena)
        {
            yaw = arena.CameraYaw;
            pitch = arena.CameraPitch;
            minDist = arena.CameraMinDist;
            maxDist = arena.CameraMaxDist;
            focusOverride = null;
        }

        public void AddShake(float amount) => shake = Mathf.Min(1.2f, shake + amount);

        public void Snap()
        {
            ComputeTarget(out focus, out dist);
            focusVel = Vector3.zero;
            distVel = 0f;
            Apply(0f);
        }

        void ComputeTarget(out Vector3 targetFocus, out float targetDist)
        {
            points.Clear();
            if (focusOverride != null && focusOverride.pelvis != null)
            {
                points.Add(focusOverride.VisualPosition);
            }
            else
            {
                foreach (var b in Brawler.All)
                {
                    if (b == null || b.pelvis == null) continue;
                    if (b.IsOut && Time.time - b.OutTime > 1.2f) continue;
                    var p = b.VisualPosition;
                    if (b.IsOut) p.y = Mathf.Max(p.y, GameManager.KillHeight);
                    points.Add(p);
                }
            }

            var arena = GameManager.I != null ? GameManager.I.Arena : null;
            if (points.Count == 0)
            {
                targetFocus = arena != null ? arena.Center + Vector3.up : Vector3.up;
                targetDist = arena != null ? Mathf.Lerp(minDist, maxDist, 0.4f) : 14f;
                return;
            }

            var bounds = new Bounds(points[0], Vector3.zero);
            for (int i = 1; i < points.Count; i++) bounds.Encapsulate(points[i]);
            targetFocus = bounds.center + Vector3.up * 0.6f;
            float spread = Mathf.Max(bounds.size.x, bounds.size.z * 1.2f, bounds.size.y * 1.6f);
            targetDist = Mathf.Clamp(spread * 1.25f + minDist * 0.75f, minDist, maxDist);
            if (focusOverride != null) targetDist = minDist * 0.7f;
        }

        void LateUpdate()
        {
            float dt = Time.unscaledDeltaTime;
            if (orbit) yaw += dt * 6f;
            ComputeTarget(out var tf, out var td);
            focus = Vector3.SmoothDamp(focus, tf, ref focusVel, 0.35f, Mathf.Infinity, dt);
            dist = Mathf.SmoothDamp(dist, td, ref distVel, 0.6f, Mathf.Infinity, dt);
            Apply(dt);
        }

        void Apply(float dt)
        {
            var rot = Quaternion.Euler(pitch, yaw, 0f);
            Vector3 pos = focus - rot * Vector3.forward * dist;
            if (shake > 0f)
            {
                float t = Time.unscaledTime * 35f;
                Vector3 offset = new Vector3(Mathf.PerlinNoise(t, 0f) - 0.5f, Mathf.PerlinNoise(0f, t) - 0.5f, 0f) * shake * 0.9f;
                pos += rot * offset;
                shake = Mathf.MoveTowards(shake, 0f, dt * 2.2f);
            }
            transform.SetPositionAndRotation(pos, rot);
        }
    }
}
