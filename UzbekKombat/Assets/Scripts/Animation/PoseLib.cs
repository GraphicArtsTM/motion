using System.Collections.Generic;
using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Bitta qahramonning poza to'plami: asosiy holatlar + nomlangan zarba pozalari.</summary>
    public class CharPoses
    {
        public Pose stance, stance2, crouch, block, crouchBlock;
        public Pose walkA, walkB, walkC;
        public Pose victoryA, victoryB, introA, introB;
        public readonly Dictionary<string, Pose> named = new Dictionary<string, Pose>();

        public Pose this[string key]
        {
            get => named.TryGetValue(key, out var p) ? p : stance;
            set => named[key] = value;
        }

        /// <summary>Qo'llarni boshqa pozadan olib, oyoq/torsni turish pozasidan qoldiradi.</summary>
        public Pose ArmsOn(Pose body, Pose arms) => body.Clone().CopyArms(arms);
    }

    /// <summary>
    /// Barcha qahramonlar uchun umumiy pozalar va klip yasovchi.
    /// Konventsiya: personaj +Z ga qaraydi, o'ng tomoni kameraga (o'yinda profil ko'rinishi).
    /// </summary>
    public static partial class PoseLib
    {
        public static Pose P() => new Pose();

        // ---------------- Oyoq va tana asoslari ----------------
        public static Pose StanceBody(float width = 1f, float low = 0f)
        {
            return P().H(0, -0.06f - low, 0)
                .S(Bone.Hips, 0, 28, 0)
                .S(Bone.Spine, 5, 4, 0)
                .S(Bone.Chest, 6, 10, 0)
                .S(Bone.Neck, -4, -14, 0)
                .S(Bone.Head, -6, -24, 0)
                .S(Bone.ThighL, -30 * width - low * 60, -28, -4)
                .S(Bone.ShinL, 36 + low * 80, 0, 0)
                .S(Bone.FootL, -6 - low * 20, 0, 0)
                .S(Bone.ThighR, 16 * width - low * 30, -14, 5)
                .S(Bone.ShinR, 30 + low * 70, 0, 0)
                .S(Bone.FootR, -34 - low * 30, 0, 0);
        }

        public static Pose CrouchBody()
        {
            return P().H(0, -0.42f, 0)
                .S(Bone.Hips, 8, 28, 0)
                .S(Bone.Spine, 16, 4, 0)
                .S(Bone.Chest, 10, 10, 0)
                .S(Bone.Neck, -12, -14, 0)
                .S(Bone.Head, -16, -24, 0)
                .S(Bone.ThighL, -100, -28, -6)
                .S(Bone.ShinL, 122, 0, 0)
                .S(Bone.FootL, -22, 0, 0)
                .S(Bone.ThighR, -52, -14, 12)
                .S(Bone.ShinR, 132, 0, 0)
                .S(Bone.FootR, -62, 0, 0);
        }

        public static Pose BlockBody() => StanceBody(0.9f, 0.04f).S(Bone.Spine, 0, 2, 0).S(Bone.Chest, -3, 4, 0).S(Bone.Head, 2, -20, 0).HA(-0.0f, 0, -0.04f);

        // ---------------- Umumiy (qurolsiz) holatlar ----------------
        public static Pose HitHigh(Pose stance)
        {
            return stance.Clone().H(0, -0.07f, -0.1f)
                .S(Bone.Spine, -12, 10, 0).S(Bone.Chest, -18, 18, 6).S(Bone.Neck, -14, 0, 0).S(Bone.Head, -22, -12, 4)
                .S(Bone.UpperArmR, 20, 0, 42).S(Bone.ForeArmR, -40).S(Bone.HandR, 10)
                .S(Bone.UpperArmL, 15, 0, -38).S(Bone.ForeArmL, -40)
                .S(Bone.ThighL, -22, -28, -4).S(Bone.ShinL, 28).S(Bone.FootL, -6)
                .S(Bone.ThighR, 22, -14, 5).S(Bone.ShinR, 34).S(Bone.FootR, -40);
        }

        public static Pose HitMid(Pose stance)
        {
            return stance.Clone().H(0, -0.12f, -0.06f)
                .S(Bone.Spine, 24, 10, 0).S(Bone.Chest, 20, 14, 0).S(Bone.Neck, 6, 0, 0).S(Bone.Head, 10, -18, 0)
                .S(Bone.UpperArmR, -20, -10, 12).S(Bone.ForeArmR, -70).S(Bone.HandR, 0)
                .S(Bone.UpperArmL, -25, 10, -12).S(Bone.ForeArmL, -70)
                .S(Bone.ThighL, -34, -28, -4).S(Bone.ShinL, 50).S(Bone.FootL, -14)
                .S(Bone.ThighR, 8, -14, 5).S(Bone.ShinR, 46).S(Bone.FootR, -40);
        }

        public static Pose HitLow(Pose stance)
        {
            return stance.Clone().H(0, -0.1f, -0.04f)
                .S(Bone.Spine, 12, 10, 0).S(Bone.Chest, -6, 14, 0).S(Bone.Head, -8, -16, 0)
                .S(Bone.ThighL, -5, -28, -4).S(Bone.ShinL, 50).S(Bone.FootL, -20)
                .S(Bone.ThighR, 26, -14, 5).S(Bone.ShinR, 42).S(Bone.FootR, -50)
                .S(Bone.UpperArmR, -10, 0, 35).S(Bone.ForeArmR, -50)
                .S(Bone.UpperArmL, -5, 0, -30).S(Bone.ForeArmL, -50);
        }

        public static Pose HitCrouch(Pose crouch)
        {
            return crouch.Clone().S(Bone.Spine, -6, 4, 0).S(Bone.Chest, -16, 14, 4).S(Bone.Head, -24, -16, 0)
                .S(Bone.UpperArmR, 10, 0, 40).S(Bone.ForeArmR, -40)
                .S(Bone.UpperArmL, 10, 0, -40).S(Bone.ForeArmL, -40);
        }

        public static Pose Juggle()
        {
            return P().S(Bone.Hips, 0, 20, 0).S(Bone.Spine, -24, 0, 0).S(Bone.Chest, -20, 10, 0).S(Bone.Neck, -10).S(Bone.Head, -26)
                .S(Bone.UpperArmR, -150, 0, 50).S(Bone.ForeArmR, -30).S(Bone.UpperArmL, -140, 0, -50).S(Bone.ForeArmL, -35)
                .S(Bone.ThighL, -45, 0, -8).S(Bone.ShinL, 70).S(Bone.ThighR, -10, 0, 8).S(Bone.ShinR, 55).S(Bone.FootR, -10);
        }

        public static Pose Lying()
        {
            return P().H(0, -0.7f, -0.1f)
                .S(Bone.Hips, -88, 20, 0).S(Bone.Spine, 2, 0, 0).S(Bone.Chest, -4, 0, 0).S(Bone.Neck, 6).S(Bone.Head, 10, -30, 0)
                .S(Bone.UpperArmR, -20, 0, 70).S(Bone.ForeArmR, -30).S(Bone.UpperArmL, -10, 0, -60).S(Bone.ForeArmL, -20)
                .S(Bone.ThighL, -8, 0, -8).S(Bone.ShinL, 18).S(Bone.FootL, 30)
                .S(Bone.ThighR, -30, 0, 10).S(Bone.ShinR, 60).S(Bone.FootR, 10);
        }

        public static Pose SitUp()
        {
            return P().H(0, -0.6f, 0)
                .S(Bone.Hips, -45, 20, 0).S(Bone.Spine, 30, 0, 0).S(Bone.Chest, 20, 6, 0).S(Bone.Neck, 6).S(Bone.Head, 10, -20, 0)
                .S(Bone.UpperArmR, 35, 0, 25).S(Bone.ForeArmR, -10).S(Bone.UpperArmL, 35, 0, -25).S(Bone.ForeArmL, -10)
                .S(Bone.ThighL, -80, -10, -6).S(Bone.ShinL, 120).S(Bone.FootL, -30)
                .S(Bone.ThighR, -40, -10, 10).S(Bone.ShinR, 40).S(Bone.FootR, 0);
        }

        public static Pose Kneel(Pose crouch)
        {
            return crouch.Clone().S(Bone.Spine, 26, 4, 0).S(Bone.Chest, 14, 8, 0).S(Bone.Head, -10, -20, 0)
                .S(Bone.UpperArmR, -30, 0, 20).S(Bone.ForeArmR, -30).S(Bone.UpperArmL, -40, 0, -20).S(Bone.ForeArmL, -20);
        }

        public static Pose Dizzy(float side)
        {
            return P().H(0.02f * side, -0.08f, 0)
                .S(Bone.Hips, 0, 18, -5 * side).S(Bone.Spine, 12, 0, -8 * side).S(Bone.Chest, 8, 4, -6 * side).S(Bone.Neck, 10, 0, -8 * side).S(Bone.Head, 22, -10, -16 * side)
                .S(Bone.UpperArmR, -8, 0, 8).S(Bone.ForeArmR, -18).S(Bone.HandR, 20)
                .S(Bone.UpperArmL, -8, 0, -8).S(Bone.ForeArmL, -18)
                .S(Bone.ThighL, -14, -18, -6).S(Bone.ShinL, 22).S(Bone.FootL, -8)
                .S(Bone.ThighR, 6, -10, 6).S(Bone.ShinR, 20).S(Bone.FootR, -26);
        }

        public static Pose Thrown()
        {
            return Juggle().S(Bone.Spine, -10).S(Bone.Chest, -10).S(Bone.ThighL, -70).S(Bone.ShinL, 90).S(Bone.ThighR, -40).S(Bone.ShinR, 100)
                .S(Bone.UpperArmR, -90, 0, 70).S(Bone.UpperArmL, -90, 0, -70);
        }

        // Oyoq zarbalari (umumiy)
        public static Pose KickLowChamber(Pose s) => s.Clone().S(Bone.ThighL, -70, -28, -4).S(Bone.ShinL, 110).S(Bone.FootL, 10).S(Bone.Spine, -2, 4, 0).HA(0, 0.02f, -0.03f);
        public static Pose KickLow(Pose s) => s.Clone().S(Bone.ThighL, -72, -30, -2).S(Bone.ShinL, 6).S(Bone.FootL, 30).S(Bone.Spine, -10, 4, 0).S(Bone.Chest, -4, 10, 0)
            .S(Bone.ThighR, 14, -14, 5).S(Bone.ShinR, 22).HA(0, 0.03f, -0.05f);

        public static Pose KickHighChamber(Pose s) => s.Clone().S(Bone.Hips, 0, 40, 0).S(Bone.ThighR, -80, -40, 28).S(Bone.ShinR, 120).S(Bone.FootR, 20)
            .S(Bone.Spine, -8, 6, 0).S(Bone.ThighL, -10, -30, -4).S(Bone.ShinL, 20).S(Bone.FootL, -10).HA(0, 0.02f, 0);
        public static Pose KickHigh(Pose s) => s.Clone().S(Bone.Hips, 0, 46, -6).S(Bone.ThighR, -118, -48, 18).S(Bone.ShinR, 6).S(Bone.FootR, 30)
            .S(Bone.Spine, -18, 4, 8).S(Bone.Chest, -12, 6, 4).S(Bone.Head, 10, -40, 0)
            .S(Bone.ThighL, -6, -34, -4).S(Bone.ShinL, 14).S(Bone.FootL, -8).HA(0, 0.04f, -0.06f);

        public static Pose CrouchKick(Pose c) => c.Clone().S(Bone.ThighL, -82, -30, -2).S(Bone.ShinL, 6).S(Bone.FootL, 40).S(Bone.Spine, 8, 4, 0).HA(0, 0.02f, -0.04f);

        public static Pose SweepWind(Pose c) => c.Clone().S(Bone.Hips, 10, -10, 0).S(Bone.ThighR, -60, 30, 30).S(Bone.ShinR, 100);
        public static Pose Sweep(Pose c) => c.Clone().H(0, -0.55f, 0).S(Bone.Hips, 10, 60, 0).S(Bone.Spine, 28, -10, 0).S(Bone.Chest, 10, -10, 0).S(Bone.Head, -30, 10, 0)
            .S(Bone.ThighR, -86, -62, 4).S(Bone.ShinR, 4).S(Bone.FootR, 30)
            .S(Bone.ThighL, -100, -40, -10).S(Bone.ShinL, 135).S(Bone.FootL, -30);

        public static Pose AirKick(Pose j) => j.Clone().S(Bone.ThighL, -88, -20, -2).S(Bone.ShinL, 4).S(Bone.FootL, 20).S(Bone.ThighR, 10, 0, 6).S(Bone.ShinR, 100).S(Bone.Spine, -14).S(Bone.Chest, -6);
        public static Pose AirKickH(Pose j) => j.Clone().S(Bone.Hips, -20, 40, 0).S(Bone.ThighR, -96, -40, 10).S(Bone.ShinR, 4).S(Bone.FootR, 20).S(Bone.ThighL, -60, 0, -4).S(Bone.ShinL, 110).S(Bone.Spine, -12).S(Bone.Chest, -10);

        public static Pose JumpTuck(Pose s) => s.Clone().H(0, 0.05f, 0).S(Bone.Hips, 0, 20, 0).S(Bone.Spine, 18, 4, 0).S(Bone.Chest, 12, 8, 0)
            .S(Bone.ThighL, -95, -20, -6).S(Bone.ShinL, 120).S(Bone.FootL, -10)
            .S(Bone.ThighR, -70, -10, 8).S(Bone.ShinR, 120).S(Bone.FootR, -10);

        public static Pose JumpFlip(Pose s) => s.Clone().H(0, 0.1f, 0).S(Bone.Hips, 10, 10, 0).S(Bone.Spine, 32, 0, 0).S(Bone.Chest, 22, 4, 0).S(Bone.Head, 10, -14, 0)
            .S(Bone.ThighL, -120, -10, -6).S(Bone.ShinL, 135).S(Bone.FootL, -20)
            .S(Bone.ThighR, -112, -6, 6).S(Bone.ShinR, 135).S(Bone.FootR, -20);

        public static Pose Fall(Pose s) => s.Clone().H(0, 0, 0).S(Bone.ThighL, -38, -28, -4).S(Bone.ShinL, 34).S(Bone.ThighR, -6, -14, 6).S(Bone.ShinR, 50).S(Bone.FootR, -20);

        public static Pose Land(Pose s) => s.Clone().H(0, -0.25f, 0).S(Bone.Spine, 16, 4, 0).S(Bone.ThighL, -60, -28, -4).S(Bone.ShinL, 80).S(Bone.FootL, -20).S(Bone.ThighR, -20, -14, 6).S(Bone.ShinR, 80).S(Bone.FootR, -60);

        // ---------------- Klip yasash ----------------
        public static AnimSet BuildBase(CharPoses c)
        {
            var a = new AnimSet();
            Pose st = c.stance, st2 = c.stance2 ?? c.stance;
            a.idle = new AnimClip("idle", true).K(0, st).K(0.75f, st2, Ease.InOutQuad).K(1.5f, st, Ease.InOutQuad);

            Pose wA = c.walkA ?? st.Clone().S(Bone.ThighL, -44, -28, -4).S(Bone.ShinL, 26).S(Bone.FootL, 14).S(Bone.ThighR, 24, -14, 5).S(Bone.ShinR, 30).S(Bone.FootR, -44).HA(0, 0.02f, 0);
            Pose wB = c.walkB ?? st.Clone().S(Bone.ThighL, -22, -28, -4).S(Bone.ShinL, 34).S(Bone.FootL, -10).S(Bone.ThighR, -12, -14, 5).S(Bone.ShinR, 70).S(Bone.FootR, -30).HA(0, -0.02f, 0);
            Pose wC = c.walkC ?? st.Clone().S(Bone.ThighL, -28, -28, -4).S(Bone.ShinL, 40).S(Bone.ThighR, 8, -14, 5).S(Bone.ShinR, 40).S(Bone.FootR, -46);
            a.walkF = new AnimClip("walkF", true).K(0, st).K(0.17f, wA, Ease.OutQuad).K(0.34f, wB, Ease.InOutQuad).K(0.51f, wC, Ease.InOutQuad).K(0.68f, st, Ease.InOutQuad);
            a.walkB = new AnimClip("walkB", true).K(0, st).K(0.18f, wC, Ease.OutQuad).K(0.36f, wB, Ease.InOutQuad).K(0.54f, wA, Ease.InOutQuad).K(0.74f, st, Ease.InOutQuad);

            a.crouch = new AnimClip("crouch", true).K(0, c.crouch).K(0.8f, c.crouch.Clone().HA(0, -0.015f, 0).A(Bone.Chest, 2), Ease.InOutQuad).K(1.6f, c.crouch, Ease.InOutQuad);
            a.crouchDown = new AnimClip("crouchDown").K(0, st).K(0.09f, c.crouch, Ease.OutCubic);
            a.crouchDown.next = a.crouch;
            a.standUp = new AnimClip("standUp").K(0, c.crouch).K(0.1f, st, Ease.OutCubic);
            a.standUp.next = a.idle;
            a.block = new AnimClip("block", true).K(0, c.block).K(0.6f, c.block.Clone().HA(0, -0.01f, 0), Ease.InOutQuad).K(1.2f, c.block, Ease.InOutQuad);
            a.crouchBlock = new AnimClip("crouchBlock", true).K(0, c.crouchBlock);
            a.blockHit = new AnimClip("blockHit").K(0, c.block.Clone().HA(0, 0, -0.06f).A(Bone.Chest, -8).A(Bone.Head, -8), Ease.OutQuad).K(0.2f, c.block, Ease.InOutQuad);
            a.blockHit.next = a.block;
            a.crouchBlockHit = new AnimClip("crouchBlockHit").K(0, c.crouchBlock.Clone().HA(0, 0, -0.05f).A(Bone.Chest, -8), Ease.OutQuad).K(0.2f, c.crouchBlock, Ease.InOutQuad);
            a.crouchBlockHit.next = a.crouchBlock;

            Pose tuck = JumpTuck(st).CopyArms(c["jumpArms"]);
            a.jumpSquat = new AnimClip("jumpSquat").K(0, st).K(0.05f, Land(st), Ease.OutQuad);
            a.jumpUp = new AnimClip("jumpUp", false, false).K(0, Fall(st).CopyArms(c["jumpArms"])).K(0.18f, tuck, Ease.OutQuad).K(0.5f, tuck, Ease.Linear).K(0.75f, Fall(st), Ease.InOutQuad);
            Pose flip = JumpFlip(st).CopyArms(c["flipArms"]);
            a.jumpF = new AnimClip("jumpF", false, false).K(0, Fall(st)).K(0.12f, flip, Ease.OutQuad).K(0.5f, flip, Ease.Linear).K(0.72f, Fall(st), Ease.InOutQuad);
            a.fall = new AnimClip("fall", false, false).K(0, Fall(st));
            a.land = new AnimClip("land").K(0, Land(st)).K(0.12f, st, Ease.OutQuad);
            a.land.next = a.idle;

            Pose dashF = st.Clone().S(Bone.Spine, 20, 4, 0).S(Bone.Chest, 12, 8, 0).S(Bone.ThighL, -55, -28, -4).S(Bone.ShinL, 50).S(Bone.ThighR, 30, -14, 5).S(Bone.ShinR, 70).S(Bone.FootR, -40);
            Pose dashB = st.Clone().S(Bone.Spine, -10, 4, 0).S(Bone.Chest, -6, 10, 0).S(Bone.ThighL, -15, -28, -4).S(Bone.ShinL, 50).S(Bone.ThighR, 10, -14, 5).S(Bone.ShinR, 70).HA(0, 0.05f, -0.05f);
            a.dashF = new AnimClip("dashF").K(0, st).K(0.08f, dashF, Ease.OutQuad).K(0.23f, st, Ease.InOutQuad);
            a.dashB = new AnimClip("dashB", false, false).K(0, st).K(0.08f, dashB, Ease.OutQuad).K(0.26f, st, Ease.InOutQuad);

            Pose hh = HitHigh(st), hm = HitMid(st), hl = HitLow(st), hc = HitCrouch(c.crouch);
            a.hitHigh = new AnimClip("hitHigh").K(0, st).K(0.05f, hh, Ease.OutExpo).K(0.18f, hh.Clone().A(Bone.Chest, 4), Ease.Linear).K(0.4f, st, Ease.InOutQuad);
            a.hitMid = new AnimClip("hitMid").K(0, st).K(0.05f, hm, Ease.OutExpo).K(0.18f, hm.Clone().A(Bone.Spine, -4), Ease.Linear).K(0.4f, st, Ease.InOutQuad);
            a.hitLow = new AnimClip("hitLow").K(0, st).K(0.05f, hl, Ease.OutExpo).K(0.18f, hl, Ease.Linear).K(0.4f, st, Ease.InOutQuad);
            a.hitCrouch = new AnimClip("hitCrouch").K(0, c.crouch).K(0.05f, hc, Ease.OutExpo).K(0.18f, hc, Ease.Linear).K(0.4f, c.crouch, Ease.InOutQuad);

            Pose jg = Juggle();
            a.juggle = new AnimClip("juggle", true, false).K(0, jg).K(0.3f, jg.Clone().A(Bone.ThighL, 30).A(Bone.ThighR, -30).A(Bone.UpperArmR, 30).A(Bone.UpperArmL, -20), Ease.InOutQuad).K(0.6f, jg, Ease.InOutQuad);
            Pose fallBack = st.Clone().S(Bone.Hips, -50, 20, 0).S(Bone.Spine, -10).S(Bone.Chest, -10).S(Bone.ThighL, -70).S(Bone.ShinL, 40).S(Bone.ThighR, -50).S(Bone.ShinR, 60)
                .S(Bone.UpperArmR, -120, 0, 50).S(Bone.UpperArmL, -110, 0, -50);
            a.knockFall = new AnimClip("knockFall", false, false).K(0, st).K(0.15f, fallBack, Ease.OutQuad).K(0.5f, Lying(), Ease.InQuad);
            Pose ly = Lying();
            a.lying = new AnimClip("lying", true).K(0, ly).K(0.8f, ly.Clone().A(Bone.Chest, -3).A(Bone.Head, 4), Ease.InOutQuad).K(1.6f, ly, Ease.InOutQuad);
            Pose kn = Kneel(c.crouch);
            a.getUp = new AnimClip("getUp").K(0, ly).K(0.16f, SitUp(), Ease.OutQuad).K(0.3f, kn, Ease.InOutQuad).K(0.43f, st, Ease.OutQuad);
            a.getUp.next = a.idle;
            a.dizzy = new AnimClip("dizzy", true).K(0, Dizzy(-1)).K(0.9f, Dizzy(1), Ease.InOutQuad).K(1.8f, Dizzy(-1), Ease.InOutQuad);
            a.defeat = new AnimClip("defeat").K(0, st).K(0.4f, kn, Ease.InOutQuad).K(1.0f, kn.Clone().A(Bone.Head, 20).A(Bone.Spine, 10), Ease.InOutQuad);

            Pose grab = st.Clone().S(Bone.Hips, 0, 10, 0).S(Bone.Spine, 12, 0, 0).S(Bone.Chest, 8, 0, 0).S(Bone.Head, -10, -10, 0)
                .S(Bone.UpperArmR, -80, -20, 10).S(Bone.ForeArmR, -30).S(Bone.UpperArmL, -80, 20, -10).S(Bone.ForeArmL, -30);
            Pose lift = st.Clone().S(Bone.Hips, 0, 10, 0).S(Bone.Spine, -14, 0, 0).S(Bone.Chest, -12, 0, 0).S(Bone.Head, -16, -10, 0)
                .S(Bone.UpperArmR, -165, -10, 10).S(Bone.ForeArmR, -20).S(Bone.UpperArmL, -165, 10, -10).S(Bone.ForeArmL, -20);
            Pose slam = st.Clone().H(0, -0.2f, 0.08f).S(Bone.Hips, 10, 10, 0).S(Bone.Spine, 34, 0, 0).S(Bone.Chest, 18, 0, 0).S(Bone.Head, -14, -10, 0)
                .S(Bone.UpperArmR, -50, -10, 10).S(Bone.ForeArmR, -10).S(Bone.UpperArmL, -50, 10, -10).S(Bone.ForeArmL, -10)
                .S(Bone.ThighL, -60, -28, -4).S(Bone.ShinL, 70);
            a.throwGrab = new AnimClip("throwGrab").K(0, st).K(0.08f, grab, Ease.OutQuad).K(0.24f, grab, Ease.Linear).K(0.4f, lift, Ease.InOutQuad).K(0.53f, slam, Ease.InQuad).K(0.65f, slam, Ease.Linear).K(0.85f, st, Ease.InOutQuad);
            a.thrown = new AnimClip("thrown", false, false).K(0, HitMid(st)).K(0.2f, Thrown(), Ease.OutQuad).K(0.55f, Thrown(), Ease.Linear);

            a.victory = new AnimClip("victory", false).K(0, st).K(0.35f, c.victoryA ?? st, Ease.OutCubic).K(0.9f, c.victoryB ?? c.victoryA ?? st, Ease.InOutQuad);
            var victoryLoop = new AnimClip("victoryLoop", true).K(0, c.victoryB ?? c.victoryA ?? st).K(1f, (c.victoryB ?? c.victoryA ?? st).Clone().HA(0, -0.015f, 0).A(Bone.Chest, -2), Ease.InOutQuad).K(2f, c.victoryB ?? c.victoryA ?? st, Ease.InOutQuad);
            a.victory.next = victoryLoop;
            a.intro = new AnimClip("intro").K(0, c.introA ?? st).K(0.7f, c.introA ?? st, Ease.Linear).K(1.2f, c.introB ?? st, Ease.InOutCubic).K(1.9f, c.introB ?? st, Ease.Linear).K(2.4f, st, Ease.InOutQuad);
            a.intro.next = a.idle;
            a.cinematicHold = new AnimClip("hold", true).K(0, st);
            a.taunt = a.victory;
            return a;
        }
    }
}
