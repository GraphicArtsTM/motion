using UnityEngine;

namespace UzbekKombat
{
    /// <summary>
    /// Klip ijrochisi: crossfade, tezlik, qo'shimcha (additive) qatlamlar — nafas olish,
    /// zarbadan silkinish (spring), salto aylanishi, oyoqlarni yerga moslash (grounding).
    /// </summary>
    public class ProceduralAnimator : MonoBehaviour
    {
        public Rig rig;
        public AnimClip Current { get; private set; }
        public float time;
        public float speed = 1f;
        public bool paused;

        // Crossfade
        readonly Quaternion[] fromRot = new Quaternion[Rig.BoneCount];
        Vector3 fromHip;
        float fadeT, fadeDur;

        readonly Quaternion[] sampleRot = new Quaternion[Rig.BoneCount];
        readonly Quaternion[] outRot = new Quaternion[Rig.BoneCount];
        Vector3 outHip;

        // Qo'shimcha qatlamlar
        public Quaternion spin = Quaternion.identity;   // salto / havoda aylanish
        public Vector3 spinPivot = new Vector3(0, 0.15f, 0);
        public bool groundLock = true;
        public float groundY = 0f;
        public float groundBlend = 1f;
        public bool breathing = true;
        public float breathAmount = 1f;

        // Xarakter "jonliligi": jang turishidagi tebranish (har bir qahramonda o'z ritmi)
        public float bounceAmp = 0.015f, bounceRate = 4.5f;
        public float bounceTarget;       // 0..1 — Fighter belgilaydi (idle/walk holatida 1)
        float bounceW, bouncePhase;
        public float fatigue;            // 0..1 — sog'liq kam bo'lsa charchoq
        Vector3 flinch, flinchVel;   // zarba silkinishi (spring)
        float shake;                  // titrash (zarba olganda)

        public bool IsFinished => Current == null || (!Current.loop && time >= Current.Length);
        public float NormalizedTime => Current == null || Current.Length <= 0 ? 1 : Mathf.Clamp01(time / Current.Length);

        void Awake()
        {
            for (int i = 0; i < Rig.BoneCount; i++) { fromRot[i] = Quaternion.identity; outRot[i] = Quaternion.identity; }
        }

        public void Play(AnimClip clip, float fade = 0.08f, float startTime = 0f, float playSpeed = 1f, bool restartIfSame = true)
        {
            if (clip == null) return;
            if (clip == Current && !restartIfSame) { speed = playSpeed; return; }
            // Joriy natijani crossfade boshlanishi sifatida saqlash
            for (int i = 0; i < Rig.BoneCount; i++) fromRot[i] = outRot[i];
            fromHip = outHip;
            fadeDur = Current == null ? 0 : fade;
            fadeT = 0;
            Current = clip;
            time = startTime;
            speed = playSpeed;
        }

        public void Flinch(Vector3 euler, float strength = 1f)
        {
            flinchVel += euler * strength * 14f;
            shake = Mathf.Max(shake, 0.12f * strength);
        }

        /// <summary>Animatsiyani qo'lda yangilash (fighter tomonidan har kadr chaqiriladi).</summary>
        public void Tick(float dt)
        {
            if (rig == null || Current == null) return;
            if (!paused)
            {
                time += dt * speed;
                if (Current.next != null && !Current.loop && time >= Current.Length)
                {
                    float over = time - Current.Length;
                    Play(Current.next, 0.12f, 0, 1f);
                    time = over;
                }
                if (fadeT < fadeDur) fadeT += dt * Mathf.Max(0.5f, speed);
            }

            Current.Sample(time, sampleRot, out Vector3 hip);
            float w = fadeDur <= 0 ? 1 : Mathf.Clamp01(fadeT / fadeDur);
            w = w * w * (3 - 2 * w);
            for (int i = 0; i < Rig.BoneCount; i++) outRot[i] = w >= 1 ? sampleRot[i] : Quaternion.Slerp(fromRot[i], sampleRot[i], w);
            outHip = w >= 1 ? hip : Vector3.Lerp(fromHip, hip, w);

            // Spring: zarba silkinishi
            float k = 180f, d = 18f;
            flinchVel += (-flinch * k - flinchVel * d) * dt;
            flinch += flinchVel * dt;
            shake = Mathf.MoveTowards(shake, 0, dt);

            ApplyToBones(dt);
        }

        void ApplyToBones(float dt)
        {
            var b = rig.bones;
            for (int i = 0; i < Rig.BoneCount; i++) b[i].localRotation = outRot[i];

            // Nafas olish (charchaganda chuqurroq va tezroq)
            if (breathing)
            {
                float rate = 2.4f + fatigue * 2.2f;
                float br = Mathf.Sin(Time.time * rate) * (1.6f + fatigue * 3f) * breathAmount;
                b[(int)Bone.Chest].localRotation *= Quaternion.Euler(br + fatigue * 6f, 0, 0);
                b[(int)Bone.Head].localRotation *= Quaternion.Euler(-br * 0.6f - fatigue * 3f, 0, 0);
            }
            // Jang turishidagi "prujina" — ritmik tebranish
            bounceW = Mathf.MoveTowards(bounceW, bounceTarget, dt * 4f);
            bouncePhase += dt * bounceRate;
            float bob = 0;
            if (bounceW > 0.001f)
            {
                float sN = Mathf.Sin(bouncePhase);
                bob = -(sN * sN) * 2f * bounceAmp * bounceW * (1f - fatigue * 0.5f);
                b[(int)Bone.Spine].localRotation *= Quaternion.Euler(sN * 1.5f * bounceW, 0, Mathf.Sin(bouncePhase * 0.5f) * 1.2f * bounceW);
                b[(int)Bone.UpperArmR].localRotation *= Quaternion.Euler(sN * 3f * bounceW, 0, 0);
                b[(int)Bone.UpperArmL].localRotation *= Quaternion.Euler(-sN * 3f * bounceW, 0, 0);
            }

            // Silkinish
            if (flinch.sqrMagnitude > 0.0001f)
            {
                b[(int)Bone.Spine].localRotation *= Quaternion.Euler(flinch * 0.35f);
                b[(int)Bone.Chest].localRotation *= Quaternion.Euler(flinch * 0.45f);
                b[(int)Bone.Head].localRotation *= Quaternion.Euler(flinch * 0.6f);
            }

            Vector3 hipLocal = rig.restPos[(int)Bone.Hips] + outHip;
            if (shake > 0) hipLocal += Random.insideUnitSphere * shake * 0.08f;
            // Salto: chanoqni pivot atrofida aylantirish
            Quaternion hipRot = outRot[(int)Bone.Hips];
            if (spin != Quaternion.identity)
            {
                Vector3 pivot = rig.restPos[(int)Bone.Hips] + spinPivot;
                hipLocal = pivot + spin * (hipLocal - pivot);
                hipRot = spin * hipRot;
            }
            b[(int)Bone.Hips].localPosition = hipLocal;
            b[(int)Bone.Hips].localRotation = hipRot;

            if (groundLock && Current.grounded && groundBlend > 0) GroundAdjust();
            // Tebranish yer moslashuvidan keyin: tizzalar bukiladi, chanoq pasayadi
            float drop = Mathf.Min(0f, bob) - fatigue * 0.025f;
            if (drop < -0.0005f)
            {
                b[(int)Bone.Hips].position += Vector3.up * drop * rig.scale;
                float kneeDeg = -drop * 260f;
                b[(int)Bone.ThighL].localRotation *= Quaternion.Euler(-kneeDeg * 0.5f, 0, 0);
                b[(int)Bone.ShinL].localRotation *= Quaternion.Euler(kneeDeg, 0, 0);
                b[(int)Bone.ThighR].localRotation *= Quaternion.Euler(-kneeDeg * 0.5f, 0, 0);
                b[(int)Bone.ShinR].localRotation *= Quaternion.Euler(kneeDeg, 0, 0);
            }
        }

        /// <summary>Eng past kontakt nuqtasini yer sathiga moslash (oyoq "suzib" yurmasligi uchun).</summary>
        void GroundAdjust()
        {
            float minY = float.MaxValue;
            foreach (var cp in Rig.ContactPoints)
            {
                if (cp.bone == Bone.HandL || cp.bone == Bone.HandR) continue;
                Vector3 p = rig[cp.bone].TransformPoint(cp.offset);
                if (p.y < minY) minY = p.y;
            }
            if (minY == float.MaxValue) return;
            float delta = (groundY - minY) * groundBlend;
            delta = Mathf.Clamp(delta, -0.6f, 0.6f);
            var hips = rig[Bone.Hips];
            hips.position += Vector3.up * delta;
        }
    }
}
