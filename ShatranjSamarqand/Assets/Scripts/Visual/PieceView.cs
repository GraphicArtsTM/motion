using System;
using System.Collections;
using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Visual
{
    /// <summary>
    /// Живая деревянная фигура: дыхание в покое, походка, прыжок коня, удар саблей,
    /// защита щитом, ликование, падение. Все анимации — на Time.deltaTime (замедление работает).
    /// </summary>
    public class PieceView : MonoBehaviour
    {
        public int Id;
        public PieceType Type;
        public Side Side;

        public Transform Model;
        public Transform Mount;
        public Transform Body;
        public Transform Head;
        public Transform ArmR;
        public Transform ArmL;
        public Transform Sword;
        public Transform SwordTip;
        public float Height = 1f;

        public Vector3 ArmRIdle = new Vector3(-22, 0, 10);
        public Vector3 ArmLIdle = new Vector3(-30, 0, -10);
        public const float SwordIdleX = 60f;

        public int Kills;
        public bool IsHero { get; private set; }
        public bool Busy { get; private set; }
        public Action OnFootstep;

        TrailRenderer trail;
        static Material trailMat;
        Transform heroAura;
        ParticleSystem heroSparks;
        bool selected;
        bool frozen;
        float lift;
        float phase;
        Vector3 bodyBasePos;
        Vector3 modelBasePos;
        float armRx, armRy, armRz, armLx, armLy, armLz, swordX;
        float bodyLean;

        public float DefaultYaw { get { return Side == Side.White ? 0f : 180f; } }

        public void Init()
        {
            phase = UnityEngine.Random.value * 10f;
            if (Body != null) bodyBasePos = Body.localPosition;
            modelBasePos = Model != null ? Model.localPosition : Vector3.zero;
            armRx = ArmRIdle.x; armRy = ArmRIdle.y; armRz = ArmRIdle.z;
            armLx = ArmLIdle.x; armLy = ArmLIdle.y; armLz = ArmLIdle.z;
            swordX = SwordIdleX;
            ApplyPose();

            if (SwordTip != null)
            {
                trail = SwordTip.gameObject.AddComponent<TrailRenderer>();
                trail.time = 0.16f;
                trail.minVertexDistance = 0.01f;
                trail.widthCurve = new AnimationCurve(new Keyframe(0, 0.07f), new Keyframe(1, 0f));
                var g = new Gradient();
                Color glow = MaterialLib.For(Side).Glow;
                g.SetKeys(new[] { new GradientColorKey(Color.white, 0), new GradientColorKey(glow, 1) },
                          new[] { new GradientAlphaKey(0.85f, 0), new GradientAlphaKey(0f, 1) });
                trail.colorGradient = g;
                if (trailMat == null) trailMat = MaterialLib.Unlit(Color.white);
                trail.sharedMaterial = trailMat;
                trail.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                trail.emitting = false;
            }
        }

        // ------------------------------------------------------------------ Поза

        void ApplyPose()
        {
            if (ArmR != null) ArmR.localRotation = Quaternion.Euler(armRx, armRy, armRz);
            if (ArmL != null) ArmL.localRotation = Quaternion.Euler(armLx, armLy, armLz);
            if (Sword != null) Sword.localRotation = Quaternion.Euler(swordX, 0, 0);
            if (Body != null) Body.localRotation = Quaternion.Euler(bodyLean, 0, 0);
        }

        void Update()
        {
            float t = Time.time + phase;
            float targetLift = selected ? 0.12f : 0f;
            lift = Mathf.Lerp(lift, targetLift, 1f - Mathf.Exp(-Time.deltaTime * 12f));
            if (Model != null && !frozen)
            {
                float bounce = selected ? Mathf.Sin(Time.time * 5f) * 0.015f : 0f;
                Model.localPosition = modelBasePos + new Vector3(0, lift + bounce, 0);
            }
            if (!Busy)
            {
                if (Body != null) Body.localPosition = bodyBasePos + new Vector3(0, Mathf.Sin(t * 1.8f) * 0.0035f, 0);
                if (Head != null) Head.localRotation = Quaternion.Euler(Mathf.Sin(t * 0.7f) * 3f, Mathf.Sin(t * 0.45f) * 12f, 0);
                if (Mount != null) Mount.localRotation = Quaternion.Euler(Mathf.Sin(t * 1.3f) * 0.8f, 0, 0);
            }
            if (heroAura != null) heroAura.Rotate(0, 60f * Time.deltaTime, 0, Space.Self);
        }

        public void SetSelected(bool on) { selected = on; }

        // ------------------------------------------------------------------ Повороты

        public IEnumerator TurnToYaw(float yaw, float dur)
        {
            Quaternion from = transform.rotation;
            Quaternion to = Quaternion.Euler(0, yaw, 0);
            if (Quaternion.Angle(from, to) < 1f) { transform.rotation = to; yield break; }
            for (float t = 0; t < 1f; t += Time.deltaTime / dur)
            {
                transform.rotation = Quaternion.Slerp(from, to, Ease.InOut(t));
                yield return null;
            }
            transform.rotation = to;
        }

        public IEnumerator FaceTowards(Vector3 worldPos, float dur)
        {
            Vector3 d = worldPos - transform.position;
            d.y = 0;
            if (d.sqrMagnitude < 1e-4f) yield break;
            yield return TurnToYaw(Quaternion.LookRotation(d).eulerAngles.y, dur);
        }

        public IEnumerator FaceDefault(float dur) { yield return TurnToYaw(DefaultYaw, dur); }

        // ------------------------------------------------------------------ Перемещение

        /// <summary>Шаг (подпрыгивающая походка) или прыжок (конь) к точке.</summary>
        public IEnumerator MoveTo(Vector3 target, bool leap, float speed = 2.6f)
        {
            Busy = true;
            Vector3 start = transform.position;
            float dist = Vector3.Distance(new Vector3(start.x, 0, start.z), new Vector3(target.x, 0, target.z));
            if (dist < 0.01f) { Busy = false; yield break; }

            yield return FaceTowards(target, 0.16f);

            float dur = leap ? Mathf.Clamp(dist / 3.2f, 0.45f, 0.75f) : Mathf.Clamp(dist / speed, 0.25f, 1.6f);
            int steps = Mathf.Max(2, Mathf.RoundToInt(dist * 2.2f));
            int lastStep = -1;
            float lean = leap ? -12f : 6f;
            for (float t = 0; t < 1f; t += Time.deltaTime / dur)
            {
                float e = leap ? Ease.InOut(t) : t;
                Vector3 p = Vector3.Lerp(start, target, e);
                if (leap)
                {
                    p.y += Mathf.Sin(t * Mathf.PI) * (0.45f + dist * 0.12f);
                    if (Mount != null) Mount.localRotation = Quaternion.Euler(Mathf.Lerp(-18f, 14f, t), 0, 0);
                }
                else
                {
                    float s = t * steps;
                    p.y += Mathf.Abs(Mathf.Sin(s * Mathf.PI)) * 0.045f;
                    int si = Mathf.FloorToInt(s);
                    if (si != lastStep) { lastStep = si; if (OnFootstep != null && si > 0) OnFootstep(); }
                    bodyLean = Mathf.Lerp(bodyLean, lean, 0.2f);
                    ApplyPose();
                }
                transform.position = p;
                yield return null;
            }
            transform.position = target;
            if (Mount != null) Mount.localRotation = Quaternion.identity;
            if (leap && OnFootstep != null) OnFootstep();
            float bl = bodyLean;
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.15f)
            {
                bodyLean = Mathf.Lerp(bl, 0, t);
                ApplyPose();
                yield return null;
            }
            bodyLean = 0;
            ApplyPose();
            Busy = false;
        }

        // ------------------------------------------------------------------ Бой

        /// <summary>
        /// Удар саблей сверху: замах над головой → рубящий удар (onImpact в момент попадания) → возврат.
        /// </summary>
        public IEnumerator Strike(Action onWindup, Action onImpact)
        {
            Busy = true;
            float r0x = armRx, r0z = armRz, s0 = swordX, l0 = bodyLean;

            // Замах
            if (onWindup != null) onWindup();
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.34f)
            {
                float e = Ease.Out(t);
                armRx = Mathf.Lerp(r0x, -200f, e);
                armRz = Mathf.Lerp(r0z, 18f, e);
                swordX = Mathf.Lerp(s0, 55f, e);
                bodyLean = Mathf.Lerp(l0, -10f, e);
                ApplyPose();
                yield return null;
            }
            yield return Wait(0.06f);

            // Удар
            if (trail != null) { trail.Clear(); trail.emitting = true; }
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.12f)
            {
                float e = Ease.In(t);
                armRx = Mathf.Lerp(-200f, -45f, e);
                armRz = Mathf.Lerp(18f, -6f, e);
                swordX = Mathf.Lerp(55f, 170f, e);
                bodyLean = Mathf.Lerp(-10f, 16f, e);
                modelBasePos = new Vector3(0, 0, Mathf.Lerp(0f, 0.1f, e));
                ApplyPose();
                yield return null;
            }
            armRx = -45f; swordX = 170f; bodyLean = 16f;
            ApplyPose();
            if (onImpact != null) onImpact();
            yield return Wait(0.2f);
            if (trail != null) trail.emitting = false;

            // Возврат
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.35f)
            {
                float e = Ease.InOut(t);
                armRx = Mathf.Lerp(-45f, ArmRIdle.x, e);
                armRz = Mathf.Lerp(-6f, ArmRIdle.z, e);
                swordX = Mathf.Lerp(170f, SwordIdleX, e);
                bodyLean = Mathf.Lerp(16f, 0f, e);
                modelBasePos = new Vector3(0, 0, Mathf.Lerp(0.1f, 0f, e));
                ApplyPose();
                yield return null;
            }
            ResetPose();
            Busy = false;
        }

        /// <summary>Защитная стойка: щит (или сабля) вперёд.</summary>
        public IEnumerator Defend(float dur = 0.25f)
        {
            Busy = true;
            float l0x = armLx, r0x = armRx, b0 = bodyLean;
            for (float t = 0; t < 1f; t += Time.deltaTime / dur)
            {
                float e = Ease.Out(t);
                armLx = Mathf.Lerp(l0x, -80f, e);
                armLz = Mathf.Lerp(ArmLIdle.z, -18f, e);
                armRx = Mathf.Lerp(r0x, -70f, e);
                bodyLean = Mathf.Lerp(b0, -8f, e);
                ApplyPose();
                yield return null;
            }
        }

        /// <summary>Ликование победителей: сабля вверх и подпрыгивание.</summary>
        public IEnumerator Cheer(float delay)
        {
            yield return Wait(delay);
            Busy = true;
            for (float t = 0; t < 1f; t += Time.deltaTime / 0.35f)
            {
                armRx = Mathf.Lerp(ArmRIdle.x, -175f, Ease.Out(t));
                swordX = Mathf.Lerp(SwordIdleX, 175f, Ease.Out(t));
                ApplyPose();
                yield return null;
            }
            Vector3 basePos = transform.position;
            for (int j = 0; j < 3; j++)
            {
                for (float t = 0; t < 1f; t += Time.deltaTime / 0.32f)
                {
                    transform.position = basePos + Vector3.up * Mathf.Sin(t * Mathf.PI) * 0.12f;
                    yield return null;
                }
            }
            transform.position = basePos;
        }

        /// <summary>Поверженный Шох падает.</summary>
        public IEnumerator Topple(Vector3 awayDir, float dur = 0.9f)
        {
            Busy = true;
            frozen = true;
            awayDir.y = 0;
            if (awayDir.sqrMagnitude < 1e-4f) awayDir = Vector3.right;
            Vector3 axis = Vector3.Cross(Vector3.up, awayDir.normalized);
            Quaternion from = Model.rotation;
            Vector3 pivot = transform.position;
            Vector3 offset = Model.position - pivot;
            for (float t = 0; t < 1f; t += Time.deltaTime / dur)
            {
                float a = Mathf.Lerp(0, 82f, Ease.In(t));
                Quaternion q = Quaternion.AngleAxis(a, axis);
                Model.rotation = q * from;
                Model.position = pivot + q * offset;
                yield return null;
            }
        }

        public void ResetPose()
        {
            armRx = ArmRIdle.x; armRy = ArmRIdle.y; armRz = ArmRIdle.z;
            armLx = ArmLIdle.x; armLy = ArmLIdle.y; armLz = ArmLIdle.z;
            swordX = SwordIdleX;
            bodyLean = 0f;
            modelBasePos = Vector3.zero;
            ApplyPose();
            Busy = false;
        }

        static IEnumerator Wait(float s)
        {
            for (float t = 0; t < s; t += Time.deltaTime) yield return null;
        }

        // ------------------------------------------------------------------ Пахлавон

        /// <summary>Звание «Пахлавон» (3+ победы): вращающееся золотое кольцо и искры.</summary>
        public void SetHero(bool on)
        {
            IsHero = on;
            if (!on)
            {
                if (heroAura != null) Destroy(heroAura.gameObject);
                if (heroSparks != null) Destroy(heroSparks.gameObject);
                heroAura = null; heroSparks = null;
                return;
            }
            if (heroAura != null) return;

            var go = new GameObject("HeroAura");
            heroAura = go.transform;
            heroAura.SetParent(transform, false);
            heroAura.localPosition = new Vector3(0, 0.015f, 0);
            heroAura.localScale = new Vector3(0.95f, 1, 0.95f);
            go.AddComponent<MeshFilter>().sharedMesh = MeshBuilder.QuadXZ;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = Fx.HeroRingMaterial;
            mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            go.layer = gameObject.layer;

            heroSparks = Fx.CreateHeroSparks(transform, Height);
        }
    }

    public static class Ease
    {
        public static float In(float t) { t = Mathf.Clamp01(t); return t * t * t; }
        public static float Out(float t) { t = Mathf.Clamp01(t); float u = 1f - t; return 1f - u * u * u; }
        public static float InOut(float t) { t = Mathf.Clamp01(t); return t < 0.5f ? 4f * t * t * t : 1f - Mathf.Pow(-2f * t + 2f, 3f) / 2f; }
        public static float OutBack(float t)
        {
            t = Mathf.Clamp01(t);
            const float c1 = 1.70158f, c3 = c1 + 1f;
            return 1f + c3 * Mathf.Pow(t - 1f, 3f) + c1 * Mathf.Pow(t - 1f, 2f);
        }
    }
}
