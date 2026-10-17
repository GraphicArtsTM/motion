namespace UzbekKombat
{
    /// <summary>
    /// Pozalashni intuitiv qiluvchi yordamchilar: qo'l va qurolni tana egilishidan qat'i nazar
    /// "dunyo" burchaklarida beradi.
    ///   armWorld: 0 — pastga, -90 — oldinga gorizontal, -180 — tepaga.
    ///   bladeWorld: 0 — oldinga, -90 — tepaga, 90 — pastga.
    /// </summary>
    public static class PoseHelpers
    {
        public static float TorsoPitch(this Pose p) =>
            p.euler[(int)Bone.Hips].x + p.euler[(int)Bone.Spine].x + p.euler[(int)Bone.Chest].x;

        public static Pose ArmR(this Pose p, float armWorld, float fore, float bladeWorld, float yaw = 0, float abduct = 12, float mount = 50)
        {
            float t = p.TorsoPitch();
            p.S(Bone.UpperArmR, armWorld - t, yaw, abduct);
            p.S(Bone.ForeArmR, fore);
            p.S(Bone.HandR, bladeWorld - mount - armWorld - fore);
            return p;
        }

        public static Pose ArmL(this Pose p, float armWorld, float fore, float bladeWorld, float yaw = 0, float abduct = -12, float mount = 50)
        {
            float t = p.TorsoPitch();
            p.S(Bone.UpperArmL, armWorld - t, yaw, abduct);
            p.S(Bone.ForeArmL, fore);
            p.S(Bone.HandL, bladeWorld - mount - armWorld - fore);
            return p;
        }

        /// <summary>Qurolsiz qo'l (musht): qo'l va bilak burchaklari, bilakuzuk neytral.</summary>
        public static Pose FistL(this Pose p, float armWorld, float fore, float yaw = 0, float abduct = -12)
        {
            float t = p.TorsoPitch();
            p.S(Bone.UpperArmL, armWorld - t, yaw, abduct);
            p.S(Bone.ForeArmL, fore);
            p.S(Bone.HandL, 0);
            return p;
        }

        public static Pose FistR(this Pose p, float armWorld, float fore, float yaw = 0, float abduct = 12)
        {
            float t = p.TorsoPitch();
            p.S(Bone.UpperArmR, armWorld - t, yaw, abduct);
            p.S(Bone.ForeArmR, fore);
            p.S(Bone.HandR, 0);
            return p;
        }

        /// <summary>Son (oyoq) dunyo burchagida: 0 — pastga, -90 — oldinga gorizontal.</summary>
        public static Pose LegL(this Pose p, float thighWorld, float knee, float footFlat = 1f, float yaw = -28, float abduct = -4)
        {
            float hp = p.euler[(int)Bone.Hips].x;
            p.S(Bone.ThighL, thighWorld - hp, yaw, abduct);
            p.S(Bone.ShinL, knee);
            p.S(Bone.FootL, -(thighWorld + knee) * footFlat);
            return p;
        }

        public static Pose LegR(this Pose p, float thighWorld, float knee, float footFlat = 1f, float yaw = -14, float abduct = 5)
        {
            float hp = p.euler[(int)Bone.Hips].x;
            p.S(Bone.ThighR, thighWorld - hp, yaw, abduct);
            p.S(Bone.ShinR, knee);
            p.S(Bone.FootR, -(thighWorld + knee) * footFlat);
            return p;
        }
    }
}
