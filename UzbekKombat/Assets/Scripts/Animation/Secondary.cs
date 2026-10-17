using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// "Dinamik suyak": plashch, chopon etagi, salla dumi, pat, o'rilgan soch kabi qismlarni
    /// inersiya va og'irlik bilan tebratadi (verlet + bahor). Animatsiyadan keyin ishlaydi.
    /// Hisob ota-ona lokal fazosida — ko'zgu (mirror) masshtabda ham to'g'ri.
    /// </summary>
    public class SpringBone : MonoBehaviour
    {
        public Vector3 tipLocal = new Vector3(0, -0.5f, 0);
        public float stiffness = 0.08f;   // dam olish holatiga tortilish
        public float damping = 0.18f;
        public float gravity = 2.5f;
        public float maxAngle = 55f;
        public float windAmount = 0.15f;

        Quaternion restLocal;
        Vector3 tip, prevTip;
        bool init;
        float seed;

        void Awake()
        {
            restLocal = transform.localRotation;
            seed = Random.value * 10f;
        }

        public void ResetSim() { init = false; }

        void LateUpdate()
        {
            float dt = Time.deltaTime;
            var parent = transform.parent;
            if (dt <= 0f || parent == null) return;
            transform.localRotation = restLocal;
            Vector3 pivot = transform.position;
            Vector3 restTip = transform.TransformPoint(tipLocal);
            float len = (restTip - pivot).magnitude;
            if (len < 1e-4f) return;
            if (!init || (tip - restTip).magnitude > len * 2.5f)
            {
                tip = prevTip = restTip;
                init = true;
            }
            float k = Mathf.Clamp01(dt * 60f);
            Vector3 velocity = (tip - prevTip) * (1f - damping);
            prevTip = tip;
            Vector3 wind = new Vector3(Mathf.Sin(Time.time * 1.7f + seed), 0, Mathf.Sin(Time.time * 1.1f + seed * 2f)) * windAmount;
            tip += velocity + (Vector3.down * gravity + wind) * dt * dt * 60f;
            tip = Vector3.Lerp(tip, restTip, stiffness * k);
            Vector3 dir = (tip - pivot);
            if (dir.sqrMagnitude < 1e-8f) dir = restTip - pivot;
            dir = dir.normalized;
            Vector3 restDir = (restTip - pivot) / len;
            float ang = Vector3.Angle(restDir, dir);
            if (ang > maxAngle) dir = Vector3.Slerp(restDir, dir, maxAngle / ang).normalized;
            tip = pivot + dir * len;
            // Ota-ona lokal fazosida burish
            Vector3 a = parent.InverseTransformDirection(restDir);
            Vector3 b = parent.InverseTransformDirection(dir);
            transform.localRotation = Quaternion.FromToRotation(a, b) * restLocal;
        }
    }

    /// <summary>Yuz jonliligi: ko'z qisish (blink), zarbada ko'zni yumish, raqibga qarash.</summary>
    public class FaceRig : MonoBehaviour
    {
        public Transform eyes;
        public Rig rig;
        public Transform lookTarget;
        public float lookWeight = 1f;
        float nextBlink;
        float blinkT = -1;
        float squeeze;
        float lookPitch;

        void Start() { nextBlink = Time.time + Random.Range(1.5f, 4f); }

        public void Squeeze(float seconds) { squeeze = Mathf.Max(squeeze, seconds); }

        void LateUpdate()
        {
            if (rig == null) return;
            // Raqibga qarash: bo'yin va bosh egilishi (yuqoriga/pastga)
            if (lookTarget != null && lookWeight > 0.01f)
            {
                Vector3 head = rig[Bone.Head].position + Vector3.up * 0.12f;
                Vector3 to = lookTarget.position - head;
                float horiz = Mathf.Max(0.4f, Mathf.Abs(to.x));
                float target = Mathf.Clamp(Mathf.Atan2(to.y, horiz) * Mathf.Rad2Deg, -35f, 40f);
                lookPitch = Mathf.Lerp(lookPitch, target * lookWeight, 1f - Mathf.Exp(-Time.deltaTime * 8f));
                rig[Bone.Neck].localRotation *= Quaternion.Euler(-lookPitch * 0.4f, 0, 0);
                rig[Bone.Head].localRotation *= Quaternion.Euler(-lookPitch * 0.6f, 0, 0);
            }
            if (eyes == null) return;
            if (Time.time >= nextBlink) { blinkT = 0; nextBlink = Time.time + Random.Range(2f, 5.5f); }
            float open = 1f;
            if (blinkT >= 0)
            {
                blinkT += Time.deltaTime;
                float t = blinkT / 0.14f;
                open = t < 0.5f ? 1 - t * 2 : (t - 0.5f) * 2;
                if (t >= 1) { blinkT = -1; open = 1; }
            }
            if (squeeze > 0) { squeeze -= Time.deltaTime; open = 0.12f; }
            eyes.localScale = new Vector3(1, Mathf.Clamp(open, 0.1f, 1f), 1);
        }
    }
}
