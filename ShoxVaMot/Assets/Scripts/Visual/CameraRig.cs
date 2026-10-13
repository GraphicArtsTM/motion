using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Visual
{
    /// <summary>
    /// Орбитальная камера: вид за белых/чёрных, облёт в меню, наезд на поединок,
    /// тряска от удара. Автоматически вписывает доску в экран (портрет и альбом).
    /// </summary>
    public class CameraRig : MonoBehaviour
    {
        public Camera Cam;
        public bool MenuOrbit;

        float yaw, pitch = DefaultPitch, yawT, pitchT = DefaultPitch;
        float userZoom = 1f, userZoomT = 1f;
        Vector3 focusPoint;
        float focusW, focusWT, focusZoom = 1f;
        float shakeAmp, shakeTime, shakeDur;
        Vector3 center = new Vector3(0, -0.1f, 0);

        public const float MinPitch = 28f, MaxPitch = 84f, DefaultPitch = 46f;

        public static CameraRig Create()
        {
            var go = new GameObject("Main Camera");
            go.tag = "MainCamera";
            var cam = go.AddComponent<Camera>();
            cam.fieldOfView = 46f;
            cam.nearClipPlane = 0.1f;
            cam.farClipPlane = 450f;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.12f, 0.08f, 0.05f);
            cam.cullingMask = ~(1 << IconRenderer.Layer);
            cam.allowHDR = false;
            cam.allowMSAA = true;
            go.AddComponent<AudioListener>();
            var rig = go.AddComponent<CameraRig>();
            rig.Cam = cam;
            return rig;
        }

        public float Yaw { get { return yawT; } }

        public void SetView(Side side, bool instant)
        {
            yawT = side == Side.White ? 0f : 180f;
            pitchT = DefaultPitch;
            userZoomT = 1f;
            if (instant) { yaw = yawT; pitch = pitchT; userZoom = userZoomT; }
        }

        public void SetYaw(float y, bool instant)
        {
            yawT = y;
            if (instant) yaw = y;
        }

        public void Orbit(float dYaw, float dPitch)
        {
            yawT += dYaw;
            pitchT = Mathf.Clamp(pitchT + dPitch, MinPitch, MaxPitch);
        }

        public void Zoom(float factor)
        {
            userZoomT = Mathf.Clamp(userZoomT * factor, 0.45f, 1.15f);
        }

        public void FocusOn(Vector3 p, float zoom)
        {
            focusPoint = p;
            focusZoom = zoom;
            focusWT = 1f;
        }

        public void ReleaseFocus() { focusWT = 0f; }

        public void Shake(float amp, float dur)
        {
            shakeAmp = Mathf.Max(shakeAmp, amp);
            shakeTime = dur;
            shakeDur = dur;
        }

        float FitDistance()
        {
            float aspect = Mathf.Max(0.3f, Cam.aspect);
            float vHalf = Cam.fieldOfView * 0.5f * Mathf.Deg2Rad;
            float hHalf = Mathf.Atan(Mathf.Tan(vHalf) * aspect);
            const float halfBoard = 4.8f;
            float dW = halfBoard / Mathf.Tan(hHalf) + halfBoard * 0.3f;
            float depth = halfBoard * Mathf.Sin(pitch * Mathf.Deg2Rad) + 1.0f * Mathf.Cos(pitch * Mathf.Deg2Rad);
            // в портрете оставляем место для панелей игроков сверху и снизу
            float marginV = aspect < 1f ? 1.45f : 1.15f;
            float dH = depth * marginV / Mathf.Tan(vHalf) + halfBoard * 0.4f;
            return Mathf.Max(dW, dH);
        }

        /// <summary>Камера не выходит за стены и не упирается в потолочные балки мехмонхоны.</summary>
        static Vector3 KeepInsideRoom(Vector3 target, Vector3 pos)
        {
            Vector3 off = pos - target;
            float k = 1f;
            float lim = InteriorBuilder.Half - 1.8f;
            float top = InteriorBuilder.CeilingY - 2.6f;
            if (off.y > 0.01f && target.y + off.y > top) k = Mathf.Min(k, (top - target.y) / off.y);
            if (Mathf.Abs(target.x + off.x) > lim) k = Mathf.Min(k, (lim - Mathf.Abs(target.x)) / Mathf.Abs(off.x));
            if (Mathf.Abs(target.z + off.z) > lim) k = Mathf.Min(k, (lim - Mathf.Abs(target.z)) / Mathf.Abs(off.z));
            return target + off * Mathf.Max(0.2f, k);
        }

        void LateUpdate()
        {
            float dt = Time.unscaledDeltaTime;
            if (MenuOrbit) yawT += 5f * dt;
            float k = 1f - Mathf.Exp(-dt * 5f);
            yaw = Mathf.LerpAngle(yaw, yawT, k);
            pitch = Mathf.Lerp(pitch, pitchT, k);
            userZoom = Mathf.Lerp(userZoom, userZoomT, k);
            focusW = Mathf.Lerp(focusW, focusWT, 1f - Mathf.Exp(-dt * 3.5f));

            Vector3 target = Vector3.Lerp(center, focusPoint, focusW);
            float dist = FitDistance() * userZoom * Mathf.Lerp(1f, focusZoom, focusW);
            Quaternion rot = Quaternion.Euler(Mathf.Lerp(pitch, 38f, focusW * 0.6f), yaw, 0);
            Vector3 pos = target + rot * new Vector3(0, 0, -dist);

            if (shakeTime > 0f)
            {
                shakeTime -= dt;
                float a = shakeAmp * Mathf.Clamp01(shakeTime / Mathf.Max(shakeDur, 0.01f));
                pos += new Vector3(Mathf.PerlinNoise(Time.unscaledTime * 40f, 0) - 0.5f, Mathf.PerlinNoise(0, Time.unscaledTime * 40f) - 0.5f, 0) * a * 2f;
                if (shakeTime <= 0f) shakeAmp = 0f;
            }

            pos = KeepInsideRoom(target, pos);
            Quaternion look = Quaternion.LookRotation(target - pos, Vector3.up);
            // в портрете нижняя панель HUD выше верхней — приподнимаем доску в кадре
            if (Cam.aspect < 1f)
            {
                float viewH = 2f * dist * Mathf.Tan(Cam.fieldOfView * 0.5f * Mathf.Deg2Rad);
                pos += look * Vector3.down * (viewH * 0.035f * (1f - focusW));
            }
            transform.position = pos;
            transform.rotation = look;
        }
    }
}
