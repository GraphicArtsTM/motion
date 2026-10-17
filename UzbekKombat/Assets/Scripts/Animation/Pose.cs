using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Skelet pozasi: har bir suyak uchun lokal Euler burchaklar + chanoq siljishi.</summary>
    public class Pose
    {
        public readonly Vector3[] euler = new Vector3[Rig.BoneCount];
        public Vector3 hip;   // chanoq ofseti (lokal, metr)
        Quaternion[] q;

        public Pose() { }

        public Pose(Pose src)
        {
            System.Array.Copy(src.euler, euler, Rig.BoneCount);
            hip = src.hip;
        }

        public Pose Clone() => new Pose(this);

        public Pose S(Bone b, float x, float y = 0, float z = 0) { euler[(int)b] = new Vector3(x, y, z); q = null; return this; }

        /// <summary>Mavjud burchakka qo'shish.</summary>
        public Pose A(Bone b, float x, float y = 0, float z = 0) { euler[(int)b] += new Vector3(x, y, z); q = null; return this; }

        public Pose H(float x, float y, float z) { hip = new Vector3(x, y, z); return this; }
        public Pose HA(float x, float y, float z) { hip += new Vector3(x, y, z); return this; }

        /// <summary>Boshqa pozadan faqat ko'rsatilgan suyaklarni ko'chirish.</summary>
        public Pose Copy(Pose src, params Bone[] list)
        {
            foreach (var b in list) euler[(int)b] = src.euler[(int)b];
            q = null;
            return this;
        }

        public Pose CopyArms(Pose src) => Copy(src, Bone.UpperArmL, Bone.ForeArmL, Bone.HandL, Bone.UpperArmR, Bone.ForeArmR, Bone.HandR);
        public Pose CopyLegs(Pose src)
        {
            hip.y = src.hip.y;
            return Copy(src, Bone.ThighL, Bone.ShinL, Bone.FootL, Bone.ThighR, Bone.ShinR, Bone.FootR);
        }
        public Pose CopyTorso(Pose src) => Copy(src, Bone.Hips, Bone.Spine, Bone.Chest, Bone.Neck, Bone.Head);

        public Quaternion[] Quats
        {
            get
            {
                if (q == null)
                {
                    q = new Quaternion[Rig.BoneCount];
                    for (int i = 0; i < Rig.BoneCount; i++) q[i] = Quaternion.Euler(euler[i]);
                }
                return q;
            }
        }

        /// <summary>Ikki pozani aralashtirish (yangi poza).</summary>
        public static Pose Lerp(Pose a, Pose b, float t)
        {
            var p = new Pose();
            for (int i = 0; i < Rig.BoneCount; i++) p.euler[i] = Vector3.Lerp(a.euler[i], b.euler[i], t);
            p.hip = Vector3.Lerp(a.hip, b.hip, t);
            return p;
        }
    }
}
