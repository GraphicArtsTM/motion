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
        public bool footIK;              // oyoqlarni yerga "mixlash" (foot locking + 2 suyakli IK)

        struct FootLock { public bool locked; public Vector3 pos; public float w; public Vector3 prevModel; }
        readonly FootLock[] feet = new FootLock[2];
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
            SolveFeet(dt);
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

        // ======================= Oyoq IK =======================
        Quaternion ModelRot(int bone)
        {
            Quaternion q = Quaternion.identity;
            var chain = rig.bones;
            int i = bone;
            // ota-onalar zanjiri (chanoqqacha)
            Quaternion acc = chain[i].localRotation;
            while (Rig.Parent[i] >= 0) { i = Rig.Parent[i]; acc = chain[i].localRotation * acc; }
            return acc;
        }

        void SolveFeet(float dt)
        {
            for (int side = 0; side < 2; side++)
            {
                int th = side == 0 ? (int)Bone.ThighL : (int)Bone.ThighR;
                int sh = th + 1, ft = th + 2;
                var b = rig.bones;
                var model = rig.model;
                Vector3 ankle = b[ft].position;
                Vector3 ankleModel = model.InverseTransformPoint(ankle);
                float animSpeed = dt > 0 ? (ankleModel - feet[side].prevModel).magnitude / dt : 0;
                feet[side].prevModel = ankleModel;
                float s = rig.scale;
                float h = ankle.y - groundY - 0.08f * s;
                ref FootLock fl = ref feet[side];
                bool can = footIK && groundLock && Current != null && Current.grounded;
                if (!fl.locked && can && h < 0.035f * s && animSpeed < 0.7f)
                {
                    fl.locked = true;
                    fl.pos = ankle;
                }
                if (fl.locked)
                {
                    Vector3 d = fl.pos - ankle; d.y = 0;
                    if (!can || h > 0.07f * s || d.magnitude > 0.32f * s) fl.locked = false;
                }
                fl.w = Mathf.MoveTowards(fl.w, fl.locked ? 1f : 0f, dt * (fl.locked ? 12f : 7f));
                if (fl.w <= 0.001f) continue;
                Vector3 targetW = new Vector3(fl.pos.x, ankle.y, fl.pos.z);
                targetW = Vector3.Lerp(ankle, targetW, fl.w);
                if ((targetW - ankle).sqrMagnitude < 1e-7f) continue;
                TwoBoneIK(th, sh, ft, model.InverseTransformPoint(targetW));
            }
        }

        void TwoBoneIK(int ia, int ib, int ic, Vector3 t)
        {
            var b = rig.bones;
            var model = rig.model;
            Vector3 a = model.InverseTransformPoint(b[ia].position);
            Vector3 bb = model.InverseTransformPoint(b[ib].position);
            Vector3 c = model.InverseTransformPoint(b[ic].position);
            Quaternion aG = ModelRot(ia), bG = ModelRot(ib), cG = ModelRot(ic);
            const float eps = 0.001f;
            float lab = (bb - a).magnitude, lcb = (bb - c).magnitude;
            float lat = Mathf.Clamp((t - a).magnitude, eps, lab + lcb - eps);
            float acab0 = Mathf.Acos(Mathf.Clamp(Vector3.Dot((c - a).normalized, (bb - a).normalized), -1f, 1f));
            float babc0 = Mathf.Acos(Mathf.Clamp(Vector3.Dot((a - bb).normalized, (c - bb).normalized), -1f, 1f));
            float acat0 = Mathf.Acos(Mathf.Clamp(Vector3.Dot((c - a).normalized, (t - a).normalized), -1f, 1f));
            float acab1 = Mathf.Acos(Mathf.Clamp((lcb * lcb - lab * lab - lat * lat) / (-2f * lab * lat), -1f, 1f));
            float babc1 = Mathf.Acos(Mathf.Clamp((lat * lat - lab * lab - lcb * lcb) / (-2f * lab * lcb), -1f, 1f));
            Vector3 axis0 = Vector3.Cross(c - a, bb - a);
            if (axis0.sqrMagnitude < 1e-8f) axis0 = aG * Vector3.left;
            axis0.Normalize();
            Vector3 axis1 = Vector3.Cross(c - a, t - a);
            bool hasAxis1 = axis1.sqrMagnitude > 1e-10f;
            axis1 = hasAxis1 ? axis1.normalized : axis0;
            Quaternion r0 = Quaternion.AngleAxis((acab1 - acab0) * Mathf.Rad2Deg, Quaternion.Inverse(aG) * axis0);
            Quaternion r1 = Quaternion.AngleAxis((babc1 - babc0) * Mathf.Rad2Deg, Quaternion.Inverse(bG) * axis0);
            Quaternion r2 = hasAxis1 ? Quaternion.AngleAxis(acat0 * Mathf.Rad2Deg, Quaternion.Inverse(aG) * axis1) : Quaternion.identity;
            b[ia].localRotation = b[ia].localRotation * r0 * r2;
            b[ib].localRotation = b[ib].localRotation * r1;
            // Oyoq panjasi yo'nalishini saqlash
            b[ic].localRotation = Quaternion.Inverse(ModelRot(ib)) * cG;
        }

        public void ResetFeet() { feet[0] = default; feet[1] = default; }

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
