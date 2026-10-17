namespace UzbekKombat
{
    public static partial class PoseLib
    {
        /// <summary>Jaloliddin Manguberdi — qo'sh qilich, tezkor va chaqqon.</summary>
        public static CharPoses Jaloliddin()
        {
            var c = new CharPoses();
            Pose body = StanceBody(0.95f, 0.02f).S(Bone.Spine, 8, 4, 0);
            c.stance = body.Clone().ArmR(-70, -60, -45, -10, 16).ArmL(-25, -70, 25, 10, -14);
            c.stance2 = c.stance.Clone().HA(0, -0.03f, 0).A(Bone.ShinL, 6).A(Bone.ShinR, 6).A(Bone.ForeArmR, -6).A(Bone.ForeArmL, -6);
            c.crouch = CrouchBody().ArmR(-60, -70, -30, -10, 16).ArmL(-40, -80, 10, 10, -14);
            c.block = BlockBody().ArmR(-85, -70, -120, -30, 22).ArmL(-80, -70, -60, 30, -22);
            c.crouchBlock = CrouchBody().ArmR(-85, -70, -120, -30, 22).ArmL(-80, -70, -60, 30, -22);
            c["jumpArms"] = P().ArmR(-90, -40, -60, 0, 40).ArmL(-60, -40, -20, 0, -40);
            c["flipArms"] = P().ArmR(-60, -100, -60, 0, 20).ArmL(-60, -100, -60, 0, -20);

            Pose st = c.stance, cr = c.crouch;
            c["LP_w"] = st.Clone().A(Bone.Chest, 0, 14, 0).ArmR(-80, -115, -170, 20, 30);
            c["LP_s"] = st.Clone().H(0, -0.08f, 0.07f).S(Bone.Hips, 0, 16, 0).S(Bone.Chest, 6, -12, 0).ArmR(-92, -6, -5, -40, 10).S(Bone.ThighL, -40, -28, -4).S(Bone.ShinL, 40);
            c["LP2_w"] = c["LP_s"].Clone().ArmL(-70, -110, -160, -20, -30);
            c["LP2_s"] = st.Clone().H(0, -0.09f, 0.1f).S(Bone.Hips, 0, 44, 0).S(Bone.Chest, 6, 16, 0).ArmL(-92, -6, 5, 25, -10).ArmR(-40, -90, -60, 0, 20)
                .S(Bone.ThighL, -44, -28, -4).S(Bone.ShinL, 44);
            c["HP_w"] = st.Clone().H(0, -0.02f, -0.03f).S(Bone.Spine, -10, 4, 0).S(Bone.Chest, -8, 10, 0)
                .ArmR(-185, -40, -230, 0, 20).ArmL(-175, -40, -225, 0, -20);
            c["HP_s"] = st.Clone().H(0, -0.15f, 0.13f).S(Bone.Spine, 26, 0, 0).S(Bone.Chest, 12, 0, 0).S(Bone.Head, -20, -14, 0)
                .ArmR(-95, -5, 25, -30, 14).ArmL(-95, -5, 35, 30, -14)
                .S(Bone.ThighL, -56, -28, -4).S(Bone.ShinL, 60).S(Bone.ThighR, 24, -14, 6).S(Bone.ShinR, 26);
            c["HP_f"] = c["HP_s"].Clone().ArmR(-60, -5, 60, -30, 14).ArmL(-60, -5, 65, 30, -14);
            c["cLP_w"] = cr.Clone().ArmR(-40, -100, -150, 0, 20);
            c["cLP_s"] = cr.Clone().HA(0, 0, 0.06f).S(Bone.Chest, 14, -12, 0).ArmR(-82, -8, 25, -32, 14);
            c["cHP_w"] = cr.Clone().ArmR(10, -40, 110, -10, 20).ArmL(10, -40, 110, 10, -20);
            c["cHP_s"] = st.Clone().H(0, 0.04f, 0.06f).S(Bone.Spine, -10, 0, 0).S(Bone.Chest, -12, 0, 0).S(Bone.Head, -26, -14, 0)
                .ArmR(-165, -10, -95, -16, 16).ArmL(-160, -10, -85, 16, -16)
                .S(Bone.ThighL, -30, -28, -4).S(Bone.ShinL, 20).S(Bone.ThighR, 10, -14, 6).S(Bone.ShinR, 6).S(Bone.FootR, 20);
            c["LK_w"] = KickLowChamber(st); c["LK_s"] = KickLow(st);
            c["HK_w"] = KickHighChamber(st); c["HK_s"] = KickHigh(st).S(Bone.ThighR, -128, -48, 18);
            c["cLK_s"] = CrouchKick(cr);
            c["cHK_w"] = SweepWind(cr); c["cHK_s"] = Sweep(cr);
            Pose jt = JumpTuck(st);
            c["jP_w"] = jt.Clone().CopyArms(c["HP_w"]);
            c["jP_s"] = jt.Clone().S(Bone.Spine, 24, 0, 0).S(Bone.Chest, 12, 0, 0).ArmR(-100, -5, 30, -20, 14).ArmL(-100, -5, 40, 20, -14);
            c["jK_s"] = AirKick(jt).CopyArms(st);
            c["jHK_s"] = AirKickH(jt).CopyArms(st);
            // Xanjar otish
            c["dagger_w"] = st.Clone().S(Bone.Hips, 0, 40, 0).S(Bone.Chest, -8, 20, 0).ArmR(-160, -90, -230, 20, 30);
            c["dagger_s"] = st.Clone().H(0, -0.1f, 0.1f).S(Bone.Hips, 0, 10, 0).S(Bone.Spine, 14, -10, 0).S(Bone.Chest, 10, -14, 0).ArmR(-95, -4, 0, -30, 10)
                .S(Bone.ThighL, -48, -28, -4).S(Bone.ShinL, 48);
            // Qo'sh qilich girdobi — qo'llar yonga, aylanish kodda (spin)
            c["whirl_s"] = st.Clone().H(0, -0.06f, 0).S(Bone.Hips, 0, 0, 0).S(Bone.Spine, 4, 0, 0).S(Bone.Chest, 0, 0, 0).S(Bone.Head, -6, 0, 0)
                .S(Bone.UpperArmR, -8, 0, 88).S(Bone.ForeArmR, -10).S(Bone.HandR, -40)
                .S(Bone.UpperArmL, -8, 0, -88).S(Bone.ForeArmL, -10).S(Bone.HandL, -40)
                .S(Bone.ThighL, -24, 0, -8).S(Bone.ShinL, 30).S(Bone.FootL, -6).S(Bone.ThighR, 10, 0, 8).S(Bone.ShinR, 30).S(Bone.FootR, -30);
            // Sind sakrashi
            c["leap_w"] = cr.Clone().H(0, -0.5f, -0.05f).S(Bone.Spine, 30, 4, 0).ArmR(20, -40, 100, 0, 30).ArmL(20, -40, 100, 0, -30);
            c["leap_air"] = JumpTuck(st).S(Bone.Spine, -10, 0, 0).S(Bone.Chest, -12, 0, 0).S(Bone.Head, -20, -14, 0)
                .ArmR(-190, -30, -240, 0, 24).ArmL(-185, -30, -235, 0, -24);
            c["leap_s"] = P().H(0, 0, 0.1f).S(Bone.Hips, 30, 20, 0).S(Bone.Spine, 20, 0, 0).S(Bone.Chest, 10, 0, 0).S(Bone.Head, -40, -16, 0)
                .ArmR(-110, -5, 50, -20, 14).ArmL(-110, -5, 60, 20, -14)
                .S(Bone.ThighL, -80, -10, -4).S(Bone.ShinL, 100).S(Bone.ThighR, 10, -10, 6).S(Bone.ShinR, 60);
            // Shamol qadami (teleport)
            c["step_s"] = cr.Clone().H(0, -0.45f, 0).S(Bone.Spine, 34, 0, 0).S(Bone.Chest, 16, 0, 0).S(Bone.Head, -30, -20, 0)
                .ArmR(30, -20, 150, 0, 30).ArmL(30, -20, 150, 0, -30);
            // Fidget: qilichni aylantiradi
            c["fidget"] = st.Clone().ArmR(-95, -40, 40, 30, 40).S(Bone.Head, 4, -10, 0);
            c["fidget2"] = st.Clone().ArmR(-90, -60, -170, 40, 40).S(Bone.Head, 2, -14, 0);
            // G'alaba / kirish
            c.victoryA = st.Clone().H(0, 0.0f, 0).S(Bone.Spine, -4, 0, 0).S(Bone.Chest, -8, 16, 0).S(Bone.Head, -14, -20, 0)
                .ArmR(-170, -10, -110, -10, 30).ArmL(-170, -10, -70, 10, -30)
                .S(Bone.ThighL, -16, -28, -4).S(Bone.ShinL, 12).S(Bone.ThighR, 8, -14, 5).S(Bone.ShinR, 10).S(Bone.FootR, -14);
            c.victoryB = st.Clone().H(0, 0.0f, 0).S(Bone.Spine, -2, 0, 0).S(Bone.Chest, -6, 20, 0).S(Bone.Head, -6, -30, 0)
                .ArmR(-20, -10, 75, 0, 30).ArmL(-20, -10, 75, 0, -30)
                .S(Bone.ThighL, -12, -28, -4).S(Bone.ShinL, 8).S(Bone.ThighR, 6, -14, 5).S(Bone.ShinR, 8).S(Bone.FootR, -12);
            c.introA = Kneel(cr).S(Bone.Head, 20, -20, 0).ArmR(-60, -80, -100, 30, 10).ArmL(-60, -80, -80, -30, -10);
            c.introB = st.Clone().S(Bone.Chest, -6, 20, 0).ArmR(-100, -10, -10, 40, 50).ArmL(-60, -10, 40, -40, -50);
            return c;
        }

        /// <summary>Mirzo Ulug'bek — olim-podshoh, hassa va yulduz sehri.</summary>
        public static CharPoses Ulugbek()
        {
            var c = new CharPoses();
            const float M = 0f; // hassa mount burchagi
            Pose body = StanceBody(0.85f, -0.01f).S(Bone.Spine, 3, 4, 0).S(Bone.Chest, 2, 10, 0);
            c.stance = body.Clone().ArmR(-30, -60, -92, -10, 14, M).FistL(-55, -95, 10, -15);
            c.stance2 = c.stance.Clone().HA(0, -0.012f, 0).A(Bone.ForeArmL, -6).A(Bone.Chest, 2);
            c.crouch = CrouchBody().ArmR(-40, -60, -80, -10, 14, M).FistL(-55, -95, 10, -15);
            c.block = BlockBody().ArmR(-70, -60, -95, -30, 18, M).FistL(-75, -95, 25, -10);
            c.crouchBlock = CrouchBody().ArmR(-70, -60, -95, -30, 18, M).FistL(-75, -95, 25, -10);
            c["jumpArms"] = P().ArmR(-60, -60, -90, 0, 20, M).FistL(-90, -60, 0, -40);
            c["flipArms"] = P().ArmR(-50, -90, -80, 0, 15, M).FistL(-50, -110, 0, -15);

            Pose st = c.stance, cr = c.crouch;
            c["LP_w"] = st.Clone().A(Bone.Chest, 0, 10, 0).ArmR(-50, -100, -60, 10, 20, M);
            c["LP_s"] = st.Clone().H(0, -0.08f, 0.08f).S(Bone.Hips, 0, 16, 0).S(Bone.Chest, 6, -10, 0).ArmR(-88, -6, 0, -36, 8, M).FistL(-70, -100, 10, -15)
                .S(Bone.ThighL, -42, -28, -4).S(Bone.ShinL, 42);
            c["LP2_w"] = c["LP_s"].Clone().ArmR(-70, -60, -130, -20, 20, M);
            c["LP2_s"] = st.Clone().H(0, -0.1f, 0.1f).S(Bone.Hips, 0, 22, 0).S(Bone.Spine, 10, 4, 0).S(Bone.Chest, 6, 6, 0).ArmR(-100, -10, 30, -10, 20, M)
                .S(Bone.ThighL, -46, -28, -4).S(Bone.ShinL, 46);
            c["HP_w"] = st.Clone().S(Bone.Spine, -10, 14, 0).S(Bone.Chest, -8, 16, 0).ArmR(-175, -30, -200, 0, 14, M).FistL(-120, -60, 10, -20);
            c["HP_s"] = st.Clone().H(0, -0.14f, 0.12f).S(Bone.Hips, 4, 16, 0).S(Bone.Spine, 24, -6, 0).S(Bone.Chest, 12, -10, 0).S(Bone.Head, -18, -10, 0)
                .ArmR(-100, -6, 15, -30, 8, M).FistL(-60, -70, 10, -30)
                .S(Bone.ThighL, -56, -28, -4).S(Bone.ShinL, 60).S(Bone.ThighR, 24, -14, 6).S(Bone.ShinR, 26);
            c["HP_f"] = c["HP_s"].Clone().ArmR(-80, -6, 40, -30, 8, M);
            c["cLP_w"] = cr.Clone().ArmR(-50, -90, -60, 0, 20, M);
            c["cLP_s"] = cr.Clone().HA(0, 0, 0.06f).S(Bone.Chest, 14, -12, 0).ArmR(-82, -6, 22, -30, 12, M);
            c["cHP_w"] = cr.Clone().ArmR(-10, -40, 60, -10, 20, M);
            c["cHP_s"] = st.Clone().H(0, 0.0f, 0.06f).S(Bone.Spine, -8, -6, 0).S(Bone.Chest, -12, -10, 0).S(Bone.Head, -24, -10, 0)
                .ArmR(-160, -10, -115, -20, 14, M).FistL(-130, -40, 10, -30)
                .S(Bone.ThighL, -36, -28, -4).S(Bone.ShinL, 26).S(Bone.ThighR, 10, -14, 6).S(Bone.ShinR, 8).S(Bone.FootR, 10);
            c["LK_w"] = KickLowChamber(st); c["LK_s"] = KickLow(st);
            c["HK_w"] = KickHighChamber(st); c["HK_s"] = KickHigh(st);
            c["cLK_s"] = CrouchKick(cr);
            c["cHK_w"] = SweepWind(cr); c["cHK_s"] = Sweep(cr).ArmR(-60, -10, 30, -30, 20, M);
            Pose jt = JumpTuck(st);
            c["jP_w"] = jt.Clone().CopyArms(c["HP_w"]);
            c["jP_s"] = jt.Clone().S(Bone.Spine, 22, -6, 0).S(Bone.Chest, 12, -10, 0).ArmR(-100, -6, 25, -20, 10, M).FistL(-60, -70, 10, -30);
            c["jK_s"] = AirKick(jt).CopyArms(st);
            c["jHK_s"] = AirKickH(jt).CopyArms(st);
            // Yulduz shari — chap kaft oldinga
            c["orb_w"] = st.Clone().S(Bone.Hips, 0, 40, 0).S(Bone.Chest, -6, 20, 0).FistL(-30, -120, 30, -20).ArmR(-60, -60, -110, 0, 20, M);
            c["orb_s"] = st.Clone().H(0, -0.08f, 0.08f).S(Bone.Hips, 0, 6, 0).S(Bone.Spine, 8, -14, 0).S(Bone.Chest, 6, -18, 0)
                .FistL(-92, -4, 30, -6).S(Bone.HandL, -60).ArmR(-120, -40, -120, 0, 30, M)
                .S(Bone.ThighL, -44, -28, -4).S(Bone.ShinL, 44);
            // Sekstant yoyi (anti-air)
            c["sextant_w"] = cr.Clone().ArmR(30, -30, 90, 0, 30, M).FistL(10, -40, 0, -30);
            c["sextant_s"] = st.Clone().H(0, 0.06f, 0.04f).S(Bone.Spine, -14, 0, 0).S(Bone.Chest, -14, 0, 0).S(Bone.Head, -30, -14, 0)
                .ArmR(-178, -6, -95, -10, 14, M).FistL(-150, -20, 10, -30)
                .S(Bone.ThighL, -20, -28, -4).S(Bone.ShinL, 10).S(Bone.ThighR, 14, -14, 6).S(Bone.ShinR, 6).S(Bone.FootR, 30);
            // Yulduzlar yomg'iri — ikki qo'l osmonga
            c["rain_s"] = st.Clone().H(0, 0.0f, 0).S(Bone.Spine, -10, 0, 0).S(Bone.Chest, -14, 10, 0).S(Bone.Neck, -10, 0, 0).S(Bone.Head, -30, -14, 0)
                .ArmR(-170, -10, -95, -10, 24, M).FistL(-170, -10, 10, -24)
                .S(Bone.ThighL, -16, -28, -4).S(Bone.ShinL, 12).S(Bone.ThighR, 10, -14, 5).S(Bone.ShinR, 12);
            // Zij halqasi (qaytaruvchi)
            c["ring_s"] = BlockBody().S(Bone.Hips, 0, 30, 0).ArmR(-50, -40, -80, -20, 20, M).FistL(-95, -4, 20, -8).S(Bone.HandL, -60);
            // Fidget: osmonga qaraydi, hassani yerga uradi
            c["fidget"] = st.Clone().S(Bone.Neck, -12, 0, 0).S(Bone.Head, -24, -10, 0).FistL(-40, -110, 30, -10);
            c["fidget2"] = st.Clone().HA(0, 0.01f, 0).ArmR(-20, -50, -92, -10, 14, M).S(Bone.Head, -10, -20, 0);
            // G'alaba / kirish
            c.victoryA = st.Clone().S(Bone.Spine, -6, 4, 0).S(Bone.Chest, -10, 16, 0).S(Bone.Neck, -10, 0, 0).S(Bone.Head, -26, -20, 0)
                .ArmR(-170, -6, -92, -10, 20, M).FistL(-40, -120, 30, -10)
                .S(Bone.ThighL, -14, -28, -4).S(Bone.ShinL, 10).S(Bone.ThighR, 8, -14, 5).S(Bone.ShinR, 10);
            c.victoryB = st.Clone().S(Bone.Spine, -2, 4, 0).S(Bone.Chest, -4, 20, 0).S(Bone.Head, -6, -30, 0)
                .ArmR(-25, -50, -90, -10, 14, M).FistL(20, -110, 0, -20)
                .S(Bone.ThighL, -12, -28, -4).S(Bone.ShinL, 8).S(Bone.ThighR, 6, -14, 5).S(Bone.ShinR, 8);
            c.introA = st.Clone().S(Bone.Hips, 0, 60, 0).S(Bone.Chest, 10, 0, 0).S(Bone.Head, 26, -40, 0).ArmR(-20, -60, -90, -10, 14, M).FistL(-50, -110, 40, -10)
                .S(Bone.ThighL, -8, -60, -4).S(Bone.ShinL, 6).S(Bone.ThighR, 6, -50, 5).S(Bone.ShinR, 6);
            c.introB = c["rain_s"];
            return c;
        }

        /// <summary>Chingizxon — mo'g'ul qilichi, kamon, kurash (grappler).</summary>
        public static CharPoses Chingiz()
        {
            var c = new CharPoses();
            Pose body = StanceBody(1.15f, 0.08f).S(Bone.Spine, 12, 4, 0).S(Bone.Chest, 8, 10, 0).S(Bone.Head, -14, -24, 0);
            c.stance = body.Clone().ArmR(-40, -70, -25, -10, 18).FistL(-70, -105, 15, -14);
            c.stance2 = c.stance.Clone().HA(0, -0.02f, 0).A(Bone.ShinL, 5).A(Bone.ShinR, 5).A(Bone.Chest, 3);
            c.crouch = CrouchBody().ArmR(-50, -70, -20, -10, 18).FistL(-60, -110, 15, -14);
            c.block = BlockBody().ArmR(-80, -60, -100, -30, 20).FistL(-80, -115, 25, -15);
            c.crouchBlock = CrouchBody().ArmR(-80, -60, -100, -30, 20).FistL(-80, -115, 25, -15);
            c["jumpArms"] = P().ArmR(-70, -60, -60, 0, 30).FistL(-70, -80, 0, -30);
            c["flipArms"] = P().ArmR(-50, -100, -60, 0, 15).FistL(-50, -110, 0, -15);

            Pose st = c.stance, cr = c.crouch;
            c["LP_w"] = st.Clone().A(Bone.Chest, 0, 10, 0).ArmR(-60, -105, -150, 0, 24);
            c["LP_s"] = st.Clone().H(0, -0.08f, 0.08f).S(Bone.Hips, 0, 14, 0).S(Bone.Chest, 8, -14, 0).ArmR(-84, -8, -10, -34, 8)
                .S(Bone.ThighL, -44, -28, -4).S(Bone.ShinL, 50);
            // LP2 — chap musht (jab-xuk)
            c["LP2_w"] = c["LP_s"].Clone().FistL(-60, -120, 30, -30);
            c["LP2_s"] = st.Clone().H(0, -0.1f, 0.1f).S(Bone.Hips, 0, 44, 0).S(Bone.Chest, 8, 16, 0).FistL(-92, -6, 30, -8).ArmR(-40, -90, -60, 0, 20)
                .S(Bone.ThighL, -46, -28, -4).S(Bone.ShinL, 46);
            // HP — keng gorizontal kesish
            c["HP_w"] = st.Clone().S(Bone.Hips, 0, 60, 0).S(Bone.Chest, -6, 30, 0).ArmR(-110, -70, -190, 50, 30);
            c["HP_s"] = st.Clone().H(0, -0.12f, 0.12f).S(Bone.Hips, 0, 4, 0).S(Bone.Spine, 18, -14, 0).S(Bone.Chest, 10, -22, 0).S(Bone.Head, -20, 10, 0)
                .ArmR(-95, -6, 5, -55, 12).FistL(-50, -90, 20, -30)
                .S(Bone.ThighL, -58, -28, -4).S(Bone.ShinL, 62).S(Bone.ThighR, 26, -14, 6).S(Bone.ShinR, 26);
            c["HP_f"] = c["HP_s"].Clone().ArmR(-80, -6, 25, -70, 12);
            c["cLP_w"] = cr.Clone().ArmR(-40, -100, -150, 0, 20);
            c["cLP_s"] = cr.Clone().HA(0, 0, 0.06f).S(Bone.Chest, 14, -12, 0).ArmR(-80, -8, 25, -32, 14);
            // cHP — chap aperkot (musht)
            c["cHP_w"] = cr.Clone().FistL(0, -110, 10, -10);
            c["cHP_s"] = st.Clone().H(0, 0.0f, 0.08f).S(Bone.Hips, 0, 30, 0).S(Bone.Spine, -6, 6, 0).S(Bone.Chest, -12, 14, 0).S(Bone.Head, -18, -20, 0)
                .FistL(-160, -40, 10, -10)
                .S(Bone.ThighL, -40, -28, -4).S(Bone.ShinL, 30).S(Bone.ThighR, 10, -14, 6).S(Bone.ShinR, 10).S(Bone.FootR, 10);
            c["LK_w"] = KickLowChamber(st); c["LK_s"] = KickLow(st);
            // HK — tizza zarbasi
            c["HK_w"] = st.Clone().S(Bone.Spine, -4, 4, 0).ArmR(-80, -60, -40, 0, 30).FistL(-80, -60, 0, -30);
            c["HK_s"] = st.Clone().H(0, 0.06f, 0.1f).S(Bone.Hips, -6, 20, 0).S(Bone.Spine, 0, 4, 0).S(Bone.Chest, 4, 6, 0)
                .S(Bone.ThighR, -112, -20, 6).S(Bone.ShinR, 124).S(Bone.FootR, 20)
                .S(Bone.ThighL, -4, -28, -4).S(Bone.ShinL, 10).S(Bone.FootL, -6)
                .ArmR(-70, -50, -20, 0, 30).FistL(-60, -120, 0, -30);
            c["cLK_s"] = CrouchKick(cr);
            c["cHK_w"] = SweepWind(cr); c["cHK_s"] = Sweep(cr);
            Pose jt = JumpTuck(st);
            c["jP_w"] = jt.Clone().CopyArms(c["HP_w"]);
            c["jP_s"] = jt.Clone().S(Bone.Spine, 22, -6, 0).S(Bone.Chest, 12, -10, 0).ArmR(-100, -6, 25, -20, 10).FistL(-60, -80, 10, -30);
            c["jK_s"] = AirKick(jt).CopyArms(st);
            c["jHK_s"] = AirKickH(jt).CopyArms(st);
            // Mo'g'ul o'qi — kamon tortish
            c["arrow_w"] = st.Clone().S(Bone.Hips, 0, 50, 0).S(Bone.Spine, 0, 10, 0).S(Bone.Chest, -4, 20, 0).S(Bone.Head, -6, -70, 0)
                .FistL(-90, -4, -70, -8).FistR(-95, -150, -70, 30);
            c["arrow_s"] = c["arrow_w"].Clone().FistR(-85, -110, -60, 40).A(Bone.Chest, -2, 4, 0);
            // Arqon (lasso)
            c["lasso_w"] = st.Clone().S(Bone.Chest, -8, 20, 0).FistR(-175, -40, 0, 30).FistL(-60, -100, 15, -14);
            c["lasso_s"] = st.Clone().H(0, -0.1f, 0.1f).S(Bone.Hips, 0, 10, 0).S(Bone.Spine, 16, -10, 0).S(Bone.Chest, 10, -14, 0).FistR(-100, -6, -30, 10).FistL(-60, -100, 15, -14)
                .S(Bone.ThighL, -50, -28, -4).S(Bone.ShinL, 50);
            c["lasso_pull"] = st.Clone().H(0, -0.1f, -0.08f).S(Bone.Spine, -12, 0, 0).S(Bone.Chest, -10, 10, 0).FistR(-60, -120, -10, 20).FistL(-60, -120, 15, -14)
                .S(Bone.ThighL, -30, -28, -4).S(Bone.ShinL, 50).S(Bone.ThighR, 30, -14, 6).S(Bone.ShinR, 40);
            // Ko'k bo'ri hamlasi — yuguruvchi tizza
            c["wolf_w"] = cr.Clone().H(0, -0.3f, -0.05f).S(Bone.Spine, 30, 0, 0).ArmR(30, -30, 100, 0, 20).FistL(30, -30, 0, -20);
            c["wolf_s"] = st.Clone().H(0, 0.05f, 0.12f).S(Bone.Hips, -10, 10, 0).S(Bone.Spine, 22, 0, 0).S(Bone.Chest, 12, 0, 0).S(Bone.Head, -30, -10, 0)
                .S(Bone.ThighR, -100, -10, 6).S(Bone.ShinR, 120).S(Bone.ThighL, 30, -20, -4).S(Bone.ShinL, 50)
                .ArmR(30, -40, 100, 0, 20).FistL(10, -60, 0, -20);
            // Fidget: bo'ynini qisirlatadi, mushtini tugadi
            c["fidget"] = st.Clone().S(Bone.Neck, 0, 0, 16).S(Bone.Head, -10, -20, 18).FistL(-80, -125, 20, -14);
            c["fidget2"] = st.Clone().S(Bone.Neck, 0, 0, -16).S(Bone.Head, -10, -28, -18).FistL(-85, -120, 10, -14);
            // G'alaba / kirish
            c.victoryA = st.Clone().H(0, -0.02f, 0).S(Bone.Spine, -6, 4, 0).S(Bone.Chest, -12, 20, 0).S(Bone.Neck, -8, 0, 0).S(Bone.Head, -26, -20, 0)
                .FistL(-170, -20, 10, -20).ArmR(-30, -40, 20, 0, 30)
                .S(Bone.ThighL, -24, -28, -4).S(Bone.ShinL, 20).S(Bone.ThighR, 14, -14, 5).S(Bone.ShinR, 20);
            c.victoryB = c.victoryA.Clone().A(Bone.Head, -6, 10, 0).A(Bone.Chest, -3);
            c.introA = st.Clone().S(Bone.Spine, -2, 4, 0).S(Bone.Chest, -6, 10, 0).S(Bone.Head, -8, -24, 0)
                .FistL(-70, -120, 50, -6).FistR(-70, -120, -50, 6)
                .S(Bone.ThighL, -16, -28, -4).S(Bone.ShinL, 16).S(Bone.ThighR, 12, -14, 5).S(Bone.ShinR, 14);
            c.introB = st.Clone().S(Bone.Chest, -6, 20, 0).ArmR(-95, -6, 0, 20, 30);
            return c;
        }
    }
}
