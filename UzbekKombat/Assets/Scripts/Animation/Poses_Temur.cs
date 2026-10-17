namespace UzbekKombat
{
    public static partial class PoseLib
    {
        /// <summary>Amir Temur — og'ir qilich ustasi: keng turish, kuchli chopishlar.</summary>
        public static CharPoses Temur()
        {
            var c = new CharPoses();
            Pose armsGuard = P()
                .S(Bone.UpperArmR, -28, -10, 16).S(Bone.ForeArmR, -82).S(Bone.HandR, 12)
                .S(Bone.UpperArmL, -42, 10, -12).S(Bone.ForeArmL, -98).S(Bone.HandL, 0);
            c.stance = StanceBody(1.08f, 0.03f).CopyArms(armsGuard);
            c.stance2 = c.stance.Clone().HA(0, -0.018f, 0).A(Bone.ForeArmR, -5).A(Bone.ShinL, 4).A(Bone.ShinR, 4).A(Bone.Chest, 2);
            c.crouch = CrouchBody().CopyArms(armsGuard).S(Bone.UpperArmR, -40, -10, 16).S(Bone.ForeArmR, -70).S(Bone.HandR, 20);
            Pose armsBlock = P()
                .S(Bone.UpperArmR, -78, -35, 22).S(Bone.ForeArmR, -62).S(Bone.HandR, -10)
                .S(Bone.UpperArmL, -72, 25, -18).S(Bone.ForeArmL, -112);
            c.block = BlockBody().CopyArms(armsBlock);
            c.crouchBlock = CrouchBody().CopyArms(armsBlock);
            c["jumpArms"] = P().S(Bone.UpperArmR, -60, 0, 30).S(Bone.ForeArmR, -70).S(Bone.HandR, 10).S(Bone.UpperArmL, -60, 0, -30).S(Bone.ForeArmL, -70);
            c["flipArms"] = P().S(Bone.UpperArmR, -50, 0, 15).S(Bone.ForeArmR, -110).S(Bone.UpperArmL, -50, 0, -15).S(Bone.ForeArmL, -110);

            Pose st = c.stance;
            // LP — tez kesish
            c["LP_w"] = st.Clone().A(Bone.Chest, 0, 10, 0).ArmR(-60, -105, -150, 0, 24);
            c["LP_s"] = st.Clone().H(0, -0.09f, 0.08f).S(Bone.Hips, 0, 14, 0).S(Bone.Spine, 8, -8, 0).S(Bone.Chest, 6, -14, 0)
                .ArmR(-88, -8, -20, -36, 8)
                .S(Bone.ThighL, -42, -28, -4).S(Bone.ShinL, 42);
            // LP2 — teskari kesish
            c["LP2_w"] = c["LP_s"].Clone().S(Bone.Chest, 6, -24, 0).ArmR(-110, -100, -170, -50, 20);
            c["LP2_s"] = st.Clone().H(0, -0.1f, 0.1f).S(Bone.Hips, 0, 22, 0).S(Bone.Spine, 8, 6, 0).S(Bone.Chest, 6, 8, 0)
                .ArmR(-78, -12, 12, -10, 30)
                .S(Bone.ThighL, -46, -28, -4).S(Bone.ShinL, 46);
            // HP — og'ir yuqoridan chopish (overhead)
            c["HP_w"] = st.Clone().H(0, -0.03f, -0.04f).S(Bone.Spine, -12, 14, 0).S(Bone.Chest, -10, 16, 0)
                .ArmR(-190, -50, -230, 0, 14)
                .FistL(-120, -60, 10, -20);
            c["HP_s"] = st.Clone().H(0, -0.16f, 0.14f).S(Bone.Hips, 6, 18, 0).S(Bone.Spine, 26, -8, 0).S(Bone.Chest, 14, -12, 0).S(Bone.Head, -20, -10, 0)
                .ArmR(-98, -4, 14, -30, 8)
                .FistL(-60, -60, 10, -30)
                .S(Bone.ThighL, -58, -28, -4).S(Bone.ShinL, 62).S(Bone.ThighR, 26, -14, 6).S(Bone.ShinR, 26);
            c["HP_f"] = c["HP_s"].Clone().A(Bone.Spine, 4).ArmR(-70, -4, 45, -30, 8);
            // Cho'kkalab
            Pose cr = c.crouch;
            c["cLP_w"] = cr.Clone().ArmR(-40, -100, -150, 0, 20);
            c["cLP_s"] = cr.Clone().HA(0, 0, 0.06f).S(Bone.Chest, 14, -12, 0).ArmR(-80, -8, 25, -32, 14);
            c["cHP_w"] = cr.Clone().S(Bone.Chest, 14, 20, 0).ArmR(20, -30, 120, -10, 20);
            c["cHP_s"] = st.Clone().H(0, -0.02f, 0.08f).S(Bone.Hips, 0, 16, 0).S(Bone.Spine, -8, -8, 0).S(Bone.Chest, -14, -12, 0).S(Bone.Head, -24, -10, 0)
                .ArmR(-160, -12, -95, -22, 14)
                .S(Bone.ThighL, -40, -28, -4).S(Bone.ShinL, 30).S(Bone.ThighR, 10, -14, 6).S(Bone.ShinR, 10).S(Bone.FootR, -10);
            // Oyoqlar
            c["LK_w"] = KickLowChamber(st); c["LK_s"] = KickLow(st);
            c["HK_w"] = KickHighChamber(st); c["HK_s"] = KickHigh(st);
            c["cLK_s"] = CrouchKick(cr);
            c["cHK_w"] = SweepWind(cr); c["cHK_s"] = Sweep(cr);
            // Havoda
            Pose jt = JumpTuck(st);
            c["jP_w"] = jt.Clone().CopyArms(c["HP_w"]);
            c["jP_s"] = jt.Clone().S(Bone.Spine, 24, -8, 0).S(Bone.Chest, 14, -10, 0).ArmR(-100, -4, 25, -20, 10).FistL(-60, -60, 10, -30);
            c["jK_s"] = AirKick(jt).CopyArms(armsGuard);
            c["jHK_s"] = AirKickH(jt).CopyArms(armsGuard);
            // Maxsus: Qilich to'lqini
            c["wave_w"] = c["HP_w"].Clone().S(Bone.Hips, 0, 50, 0).S(Bone.Chest, -10, 30, 0);
            c["wave_s"] = st.Clone().H(0, -0.22f, 0.12f).S(Bone.Hips, 6, 10, 0).S(Bone.Spine, 32, -14, 0).S(Bone.Chest, 16, -16, 0).S(Bone.Head, -30, -6, 0)
                .ArmR(-60, -6, 30, -40, 10)
                .FistL(-20, -30, 10, -40)
                .S(Bone.ThighL, -70, -28, -4).S(Bone.ShinL, 80).S(Bone.ThighR, 30, -14, 6).S(Bone.ShinR, 30);
            // Hamla (yelka bilan urish)
            c["charge_w"] = st.Clone().H(0, -0.14f, -0.04f).S(Bone.Hips, 0, -20, 0).S(Bone.Spine, 14, -14, 0).S(Bone.Chest, 10, -16, 0).S(Bone.Head, -10, 10, 0)
                .S(Bone.UpperArmL, -30, 0, -6).S(Bone.ForeArmL, -125).S(Bone.UpperArmR, 30, 0, 20).S(Bone.ForeArmR, -40).S(Bone.HandR, 30)
                .S(Bone.ThighL, -50, 10, -4).S(Bone.ShinL, 70).S(Bone.ThighR, 20, 0, 6).S(Bone.ShinR, 60);
            c["charge_s"] = c["charge_w"].Clone().H(0, -0.1f, 0.12f).S(Bone.Spine, 24, -20, 0).S(Bone.ThighL, -62, 10, -4).S(Bone.ShinL, 50).S(Bone.ThighR, 38, 0, 6).S(Bone.ShinR, 40);
            // Yer titrashi (qilichni yerga sanchish)
            c["quake_w"] = st.Clone().H(0, 0.02f, 0).S(Bone.Spine, -14, 0, 0).S(Bone.Chest, -12, 0, 0).S(Bone.Head, -20, -20, 0)
                .ArmR(-176, -16, -95, -10, 6)
                .FistL(-170, -20, 18, -6)
                .S(Bone.ThighL, -10, -28, -4).S(Bone.ShinL, 10).S(Bone.ThighR, 8, -14, 5).S(Bone.ShinR, 10);
            c["quake_s"] = cr.Clone().H(0, -0.5f, 0.05f).S(Bone.Spine, 26, 0, 0).S(Bone.Chest, 10, 0, 0).S(Bone.Head, -30, -20, 0)
                .ArmR(-42, -6, 88, -20, 8)
                .FistL(-46, -10, 24, -8);
            // Adolat qalqoni (parry)
            c["counter_s"] = BlockBody().S(Bone.Hips, 0, 40, 0).S(Bone.Chest, -4, 10, 0)
                .S(Bone.UpperArmR, -60, -45, 14).S(Bone.ForeArmR, -48).S(Bone.HandR, -24)
                .S(Bone.UpperArmL, -30, 20, -40).S(Bone.ForeArmL, -20).S(Bone.HandL, -40);
            // G'alaba
            c.victoryA = st.Clone().H(0, -0.02f, 0).S(Bone.Spine, -4, 10, 0).S(Bone.Chest, -10, 20, 0).S(Bone.Head, -18, -16, 0)
                .S(Bone.UpperArmR, -176, 0, 14).S(Bone.ForeArmR, -6).S(Bone.HandR, 34)
                .S(Bone.UpperArmL, 12, 0, -34).S(Bone.ForeArmL, -95).S(Bone.HandL, 20)
                .S(Bone.ThighL, -18, -28, -4).S(Bone.ShinL, 14).S(Bone.ThighR, 10, -14, 5).S(Bone.ShinR, 12).S(Bone.FootR, -16);
            c.victoryB = c.victoryA.Clone().A(Bone.Chest, -3).A(Bone.Head, -4, 6, 0);
            c.introA = st.Clone().H(0, -0.01f, 0).S(Bone.Hips, 0, 50, 0).S(Bone.Spine, 0, 0, 0).S(Bone.Chest, -4, 10, 0).S(Bone.Head, -4, -50, 0)
                .S(Bone.UpperArmR, -36, -40, 4).S(Bone.ForeArmR, -50).S(Bone.HandR, 76)
                .S(Bone.UpperArmL, -40, 30, -4).S(Bone.ForeArmL, -55)
                .S(Bone.ThighL, -6, -50, -6).S(Bone.ShinL, 6).S(Bone.ThighR, 6, -40, 6).S(Bone.ShinR, 6).S(Bone.FootR, -10);
            c.introB = st.Clone().S(Bone.UpperArmR, -100, 40, 40).S(Bone.ForeArmR, -12).S(Bone.HandR, 0).S(Bone.Chest, -6, 24, 0);
            return c;
        }
    }
}
