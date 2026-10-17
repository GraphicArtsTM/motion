using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Jang kamerasi: ikki jangchini kuzatadi, masofaga qarab zoom, silkinish (shake),
    /// kinematik kadrlar (Shot) va orbit rejimi (menyu/g'alaba).
    /// </summary>
    public class FightCamera : MonoBehaviour
    {
        public Camera cam;
        public Fighter a, b;
        public enum Mode { Fight, Shot, Orbit, Free }
        public Mode mode = Mode.Orbit;

        Vector3 pos, look;
        float fov = 34f;
        Vector3 shotPos, shotLook;
        float shotFov, shotBlend, shotT;
        Vector3 shotFromPos, shotFromLook;
        float shotFromFov;

        float shake;
        float shakeSeed;
        public Vector3 orbitCenter = new Vector3(0, 1.2f, 0);
        public float orbitRadius = 9f, orbitHeight = 2.4f, orbitSpeed = 6f, orbitAngle = -90f;
        public float orbitFov = 40f;
        public float zoomPunch;

        public static FightCamera Create()
        {
            var go = new GameObject("FightCamera");
            var c = go.AddComponent<Camera>();
            c.fieldOfView = 34;
            c.nearClipPlane = 0.1f;
            c.farClipPlane = 400f;
            c.clearFlags = CameraClearFlags.Skybox;
            c.allowHDR = true;
            c.allowMSAA = true;
            go.tag = "MainCamera";
            go.AddComponent<AudioListener>();
            var fc = go.AddComponent<FightCamera>();
            fc.cam = c;
            fc.pos = new Vector3(0, 2, -9);
            fc.look = new Vector3(0, 1.2f, 0);
            return fc;
        }

        public void Shake(float amount) { shake = Mathf.Min(1.2f, Mathf.Max(shake, amount)); }

        public void Shot(Vector3 p, Vector3 l, float f, float blend)
        {
            shotFromPos = pos; shotFromLook = look; shotFromFov = fov;
            shotPos = p; shotLook = l; shotFov = f; shotBlend = Mathf.Max(0.001f, blend); shotT = 0;
            mode = Mode.Shot;
        }

        public void FightMode() { mode = Mode.Fight; }

        /// <summary>Darhol kesish (blend'siz) — keyingi Shot shu nuqtadan boshlanadi.</summary>
        public void Cut(Vector3 p, Vector3 l, float f)
        {
            pos = p; look = l; fov = f;
            shotFromPos = shotPos = p; shotFromLook = shotLook = l; shotFromFov = shotFov = f; shotT = 1; shotBlend = 0.001f;
            mode = Mode.Shot;
        }

        public void Orbit(Vector3 center, float radius, float height, float speed, float startAngle, float fieldOfView = 40f)
        {
            orbitCenter = center; orbitRadius = radius; orbitHeight = height; orbitSpeed = speed; orbitAngle = startAngle; orbitFov = fieldOfView;
            mode = Mode.Orbit;
        }

        void LateUpdate()
        {
            float dt = Time.unscaledDeltaTime;
            switch (mode)
            {
                case Mode.Fight:
                    if (a == null || b == null) break;
                    {
                        Vector3 pa = a.transform.position, pb = b.transform.position;
                        float midX = (pa.x + pb.x) * 0.5f;
                        float sep = Mathf.Abs(pa.x - pb.x);
                        float maxY = Mathf.Max(pa.y, pb.y);
                        float dist = Mathf.Clamp(5.6f + sep * 0.62f, 6.4f, 10.5f) - zoomPunch;
                        float y = 1.55f + maxY * 0.45f;
                        Vector3 tp = new Vector3(midX, y + 0.35f, -dist);
                        Vector3 tl = new Vector3(midX, y - 0.05f + maxY * 0.15f, 0);
                        float k = 1f - Mathf.Exp(-dt * 7f);
                        pos = Vector3.Lerp(pos, tp, k);
                        look = Vector3.Lerp(look, tl, k);
                        fov = Mathf.Lerp(fov, 34f, k);
                    }
                    break;
                case Mode.Shot:
                    {
                        shotT += dt;
                        float t = Mathf.Clamp01(shotT / shotBlend);
                        t = t * t * (3 - 2 * t);
                        pos = Vector3.Lerp(shotFromPos, shotPos, t);
                        look = Vector3.Lerp(shotFromLook, shotLook, t);
                        fov = Mathf.Lerp(shotFromFov, shotFov, t);
                        // sekin "dolly" harakati
                        pos += (shotPos - shotLook).normalized * -0.04f * shotT;
                    }
                    break;
                case Mode.Orbit:
                    {
                        orbitAngle += orbitSpeed * dt;
                        float r = orbitAngle * Mathf.Deg2Rad;
                        Vector3 tp = orbitCenter + new Vector3(Mathf.Cos(r) * orbitRadius, orbitHeight, Mathf.Sin(r) * orbitRadius);
                        float k = 1f - Mathf.Exp(-dt * 2.5f);
                        pos = Vector3.Lerp(pos, tp, k);
                        look = Vector3.Lerp(look, orbitCenter, k);
                        fov = Mathf.Lerp(fov, orbitFov, k);
                    }
                    break;
            }
            zoomPunch = Mathf.MoveTowards(zoomPunch, 0, dt * 2f);
            shake = Mathf.MoveTowards(shake, 0, dt * 1.8f);
            shakeSeed += dt * 40f;
            Vector3 off = Vector3.zero;
            if (shake > 0.001f)
            {
                float s = shake * shake * 0.35f;
                off = new Vector3(Mathf.PerlinNoise(shakeSeed, 0) - 0.5f, Mathf.PerlinNoise(0, shakeSeed) - 0.5f, 0) * 2f * s;
            }
            transform.position = pos + off;
            transform.rotation = Quaternion.LookRotation((look + off * 0.5f) - pos, Vector3.up) * Quaternion.Euler(0, 0, (Mathf.PerlinNoise(shakeSeed * 0.7f, 3) - 0.5f) * shake * 3f);
            cam.fieldOfView = fov;
        }

        public void SnapFight()
        {
            if (a == null || b == null) return;
            float midX = (a.pos.x + b.pos.x) * 0.5f;
            pos = new Vector3(midX, 1.9f, -8f);
            look = new Vector3(midX, 1.5f, 0);
            fov = 34;
            mode = Mode.Fight;
        }
    }
}
