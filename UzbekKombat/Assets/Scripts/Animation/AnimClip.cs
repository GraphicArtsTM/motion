using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Kalit kadrli protsedural animatsiya klipi.</summary>
    public class AnimClip
    {
        public struct Key
        {
            public float time;
            public Pose pose;
            public Ease ease;
        }

        public string name;
        public bool loop;
        public bool grounded = true;     // oyoqlarni yerga "yopishtirish"
        public AnimClip next;            // tugagach avtomatik o'tish
        public readonly List<Key> keys = new List<Key>();

        public AnimClip(string name, bool loop = false, bool grounded = true)
        {
            this.name = name;
            this.loop = loop;
            this.grounded = grounded;
        }

        public float Length => keys.Count == 0 ? 0 : keys[keys.Count - 1].time;

        /// <summary>Kalit qo'shish (vaqt soniyada). ease — oldingi kalitdan shu kalitga o'tish egri chizig'i.</summary>
        public AnimClip K(float time, Pose pose, Ease ease = Ease.InOutQuad)
        {
            keys.Add(new Key { time = time, pose = pose, ease = ease });
            return this;
        }

        /// <summary>Kadrlarda (60 fps) kalit qo'shish.</summary>
        public AnimClip F(float frame, Pose pose, Ease ease = Ease.InOutQuad) => K(frame / 60f, pose, ease);

        public void Sample(float t, Quaternion[] outRot, out Vector3 outHip)
        {
            outHip = Vector3.zero;
            if (keys.Count == 0)
            {
                for (int i = 0; i < outRot.Length; i++) outRot[i] = Quaternion.identity;
                return;
            }
            float len = Length;
            if (loop && len > 0) t = Mathf.Repeat(t, len);
            if (t <= keys[0].time || keys.Count == 1)
            {
                Copy(keys[0].pose, outRot, out outHip);
                return;
            }
            if (t >= len)
            {
                Copy(keys[keys.Count - 1].pose, outRot, out outHip);
                return;
            }
            int k = 1;
            while (k < keys.Count && keys[k].time < t) k++;
            var a = keys[k - 1];
            var b = keys[k];
            float span = Mathf.Max(0.0001f, b.time - a.time);
            float u = EaseUtil.Apply(b.ease, (t - a.time) / span);
            var qa = a.pose.Quats;
            var qb = b.pose.Quats;
            for (int i = 0; i < outRot.Length; i++) outRot[i] = Quaternion.SlerpUnclamped(qa[i], qb[i], u);
            outHip = Vector3.LerpUnclamped(a.pose.hip, b.pose.hip, u);
        }

        static void Copy(Pose p, Quaternion[] outRot, out Vector3 hip)
        {
            var q = p.Quats;
            for (int i = 0; i < outRot.Length; i++) outRot[i] = q[i];
            hip = p.hip;
        }

        /// <summary>
        /// Zarba klipi: tayyor turish → siltash (windup) → zarba (strike) → ushlab turish → qaytish.
        /// Kadrlar zarba ma'lumotlariga (startup/active/recovery) sinxronlanadi.
        /// </summary>
        public static AnimClip Attack(string name, Pose ready, Pose windup, Pose strike, int startup, int active, int recovery, Pose follow = null, bool grounded = true)
        {
            var c = new AnimClip(name, false, grounded);
            float s = Mathf.Max(1, startup);
            c.F(0, ready);
            c.F(s * 0.62f, windup, Ease.OutCubic);                 // tayyorgarlik (anticipation)
            c.F(s, strike, Ease.OutExpo);                          // keskin zarba
            Pose f = follow ?? strike;
            c.F(s + active, f, Ease.OutQuad);                      // davomi (follow-through)
            c.F(s + active + recovery * 0.4f, Pose.Lerp(f, ready, 0.55f), Ease.OutCubic); // og'irlik bilan qaytish
            c.F(s + active + recovery, ready, Ease.InOutQuad);     // o'rnashish
            return c;
        }
    }
}
