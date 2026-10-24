using System.Collections.Generic;
using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>
    /// Builds a jelly-bean fighter: 11 rigid bodies joined by ConfigurableJoint muscles.
    /// The fighter is assembled facing +Z with its feet at the root, every body at identity
    /// rotation relative to the root (this makes muscle targets trivial, see <see cref="Muscle"/>).
    /// </summary>
    public static class BrawlerBuilder
    {
        // rest-pose layout (metres, root space)
        static readonly Vector3 PelvisPos = new Vector3(0, 0.95f, 0);
        static readonly Vector3 ChestPos = new Vector3(0, 1.36f, 0);
        static readonly Vector3 HeadPos = new Vector3(0, 1.86f, 0);
        const float ShoulderX = 0.36f, ArmX = 0.41f, ShoulderY = 1.56f;
        const float UpperArmY = 1.38f, ForeArmY = 1.05f;
        const float HipX = 0.14f, HipY = 0.80f, ThighY = 0.61f, ShinY = 0.24f;

        public static Brawler Build(Transform parent, Participant p, Vector3 feet, Quaternion facing)
        {
            var root = new GameObject("Brawler_" + p.name);
            root.transform.SetParent(parent, false);
            root.transform.SetPositionAndRotation(feet, facing);
            var b = root.AddComponent<Brawler>();
            b.participant = p;

            Color skin = p.color;
            Color pants = p.PantsColor;
            var bodies = new List<Rigidbody>();
            var parts = new List<BodyPart>();
            var massOf = new Dictionary<BodyPart, float>();

            BodyPart Part(string name, PartKind kind, Vector3 pos, float mass)
            {
                var go = new GameObject(name);
                go.transform.SetParent(root.transform, false);
                go.transform.localPosition = pos;
                var bp = go.AddComponent<BodyPart>();
                bp.kind = kind;
                bp.owner = b;
                parts.Add(bp);
                massOf[bp] = mass;
                return bp;
            }

            // --- torso & head ---
            var pelvis = Part("Pelvis", PartKind.Pelvis, PelvisPos, 9f);
            Capsule(pelvis.gameObject, 0.25f, 0.6f, 0, Vector3.zero);
            Kit.Deco(PrimitiveType.Sphere, pelvis.transform, new Vector3(0, -0.02f, 0), new Vector3(0.6f, 0.52f, 0.5f), pants, null, true, 0.25f);

            var chest = Part("Chest", PartKind.Chest, ChestPos, 9f);
            Capsule(chest.gameObject, 0.29f, 0.64f, 1, Vector3.zero);
            Kit.Deco(PrimitiveType.Sphere, chest.transform, Vector3.zero, new Vector3(0.64f, 0.7f, 0.54f), skin, null, true, 0.3f);
            // belly button & shirt stripe for a touch of character
            Kit.Deco(PrimitiveType.Sphere, chest.transform, new Vector3(0, -0.2f, 0.06f), new Vector3(0.58f, 0.24f, 0.46f), Palette.Darken(skin, 0.85f), null, false, 0.3f);

            var head = Part("Head", PartKind.Head, HeadPos, 3f);
            var hs = head.gameObject.AddComponent<SphereCollider>();
            hs.radius = 0.23f;
            hs.sharedMaterial = Kit.BodyMat;
            Kit.Deco(PrimitiveType.Sphere, head.transform, Vector3.zero, new Vector3(0.5f, 0.5f, 0.48f), skin, null, true, 0.35f);

            // --- arms ---
            var upperL = Part("UpperArm_L", PartKind.UpperArm, new Vector3(-ArmX, UpperArmY, 0), 1.6f);
            var upperR = Part("UpperArm_R", PartKind.UpperArm, new Vector3(ArmX, UpperArmY, 0), 1.6f);
            var foreL = Part("ForeArm_L", PartKind.ForeArm, new Vector3(-ArmX, ForeArmY, 0), 1.4f);
            var foreR = Part("ForeArm_R", PartKind.ForeArm, new Vector3(ArmX, ForeArmY, 0), 1.4f);
            foreach (var u in new[] { upperL, upperR })
            {
                Capsule(u.gameObject, 0.095f, 0.4f, 1, Vector3.zero);
                Kit.Deco(PrimitiveType.Capsule, u.transform, Vector3.zero, new Vector3(0.2f, 0.21f, 0.2f), skin, null, true, 0.3f);
            }
            foreach (var f in new[] { foreL, foreR })
            {
                Capsule(f.gameObject, 0.09f, 0.34f, 1, new Vector3(0, 0.02f, 0));
                var fist = f.gameObject.AddComponent<SphereCollider>();
                fist.center = new Vector3(0, -0.19f, 0);
                fist.radius = 0.115f;
                fist.sharedMaterial = Kit.BodyMat;
                Kit.Deco(PrimitiveType.Capsule, f.transform, new Vector3(0, 0.02f, 0), new Vector3(0.18f, 0.18f, 0.18f), skin, null, true, 0.3f);
                Kit.Deco(PrimitiveType.Sphere, f.transform, new Vector3(0, -0.19f, 0), Vector3.one * 0.25f, Palette.Darken(skin, 0.92f), null, true, 0.3f);
            }

            // --- legs ---
            var thighL = Part("Thigh_L", PartKind.Thigh, new Vector3(-HipX, ThighY, 0), 2.6f);
            var thighR = Part("Thigh_R", PartKind.Thigh, new Vector3(HipX, ThighY, 0), 2.6f);
            var shinL = Part("Shin_L", PartKind.Shin, new Vector3(-HipX, ShinY, 0), 2.2f);
            var shinR = Part("Shin_R", PartKind.Shin, new Vector3(HipX, ShinY, 0), 2.2f);
            foreach (var t in new[] { thighL, thighR })
            {
                Capsule(t.gameObject, 0.115f, 0.42f, 1, Vector3.zero);
                Kit.Deco(PrimitiveType.Capsule, t.transform, Vector3.zero, new Vector3(0.24f, 0.22f, 0.24f), pants, null, true, 0.25f);
            }
            foreach (var s in new[] { shinL, shinR })
            {
                Capsule(s.gameObject, 0.1f, 0.34f, 1, new Vector3(0, 0.02f, 0));
                var foot = s.gameObject.AddComponent<BoxCollider>();
                foot.center = new Vector3(0, -0.18f, 0.06f);
                foot.size = new Vector3(0.18f, 0.12f, 0.3f);
                foot.sharedMaterial = Kit.BodyMat;
                Kit.Deco(PrimitiveType.Capsule, s.transform, new Vector3(0, 0.02f, 0), new Vector3(0.2f, 0.18f, 0.2f), pants, null, true, 0.25f);
                Kit.Deco(PrimitiveType.Sphere, s.transform, new Vector3(0, -0.17f, 0.06f), new Vector3(0.22f, 0.15f, 0.34f), new Color(0.15f, 0.13f, 0.12f), null, true, 0.4f);
            }

            // --- rigidbodies ---
            foreach (var part in parts)
            {
                var rb = part.gameObject.AddComponent<Rigidbody>();
                rb.mass = massOf[part];
                rb.linearDamping = 0.05f;
                rb.angularDamping = 0.6f;
                rb.maxAngularVelocity = 25f;
                rb.solverIterations = Tune.SolverIterations;
                rb.solverVelocityIterations = Tune.SolverVelocityIterations;
                rb.interpolation = RigidbodyInterpolation.Interpolate;
                rb.collisionDetectionMode = part.kind == PartKind.ForeArm || part.kind == PartKind.Head || part.kind == PartKind.Shin
                    ? CollisionDetectionMode.ContinuousDynamic
                    : CollisionDetectionMode.ContinuousSpeculative;
                part.rb = rb;
                bodies.Add(rb);
            }

            Vector3 W(Vector3 local) => root.transform.TransformPoint(local);

            // --- muscles ---
            // Joint-space X angles are the NEGATIVE of transform rotations about +X (same convention as
            // Unity's Ragdoll Wizard: knee limits -80..0 for a backward bend). So "forward flex" of a hip
            // is a positive limit, a backward knee bend a negative one.
            b.spine = new Muscle(Joint(chest.rb, pelvis.rb, W(new Vector3(0, 1.13f, 0)), -40, 25, 40, 25), Tune.Spine);
            b.neck = new Muscle(Joint(head.rb, chest.rb, W(new Vector3(0, 1.64f, 0)), -45, 40, 50, 30), Tune.Neck);
            b.shoulderL = new Muscle(Joint(upperL.rb, chest.rb, W(new Vector3(-ShoulderX, ShoulderY, 0)), 0, 0, 0, 0, true), Tune.Shoulder);
            b.shoulderR = new Muscle(Joint(upperR.rb, chest.rb, W(new Vector3(ShoulderX, ShoulderY, 0)), 0, 0, 0, 0, true), Tune.Shoulder);
            b.elbowL = new Muscle(Joint(foreL.rb, upperL.rb, W(new Vector3(-ArmX, 1.21f, 0)), -5, 150, 20, 10), Tune.Elbow);
            b.elbowR = new Muscle(Joint(foreR.rb, upperR.rb, W(new Vector3(ArmX, 1.21f, 0)), -5, 150, 20, 10), Tune.Elbow);
            b.hipL = new Muscle(Joint(thighL.rb, pelvis.rb, W(new Vector3(-HipX, HipY, 0)), -45, 120, 25, 40), Tune.Hip);
            b.hipR = new Muscle(Joint(thighR.rb, pelvis.rb, W(new Vector3(HipX, HipY, 0)), -45, 120, 25, 40), Tune.Hip);
            b.kneeL = new Muscle(Joint(shinL.rb, thighL.rb, W(new Vector3(-HipX, 0.42f, 0)), -145, 2, 5, 5), Tune.Knee);
            b.kneeR = new Muscle(Joint(shinR.rb, thighR.rb, W(new Vector3(HipX, 0.42f, 0)), -145, 2, 5, 5), Tune.Knee);

            // --- hands ---
            b.handL = MakeHand(b, foreL.rb, true);
            b.handR = MakeHand(b, foreR.rb, false);

            b.pelvis = pelvis.rb; b.chest = chest.rb; b.head = head.rb;
            b.upperArmL = upperL.rb; b.upperArmR = upperR.rb; b.foreArmL = foreL.rb; b.foreArmR = foreR.rb;
            b.thighL = thighL.rb; b.thighR = thighR.rb; b.shinL = shinL.rb; b.shinR = shinR.rb;
            b.shoulderLocalL = chest.transform.InverseTransformPoint(W(new Vector3(-ShoulderX, ShoulderY, 0)));
            b.shoulderLocalR = chest.transform.InverseTransformPoint(W(new Vector3(ShoulderX, ShoulderY, 0)));

            // --- cosmetics ---
            b.face = BrawlerFace.Create(b, head.transform, skin);
            Hats.Put(head.transform, p.hat, skin);

            b.Initialise(parts.ToArray(), bodies.ToArray());
            return b;
        }

        static void Capsule(GameObject go, float radius, float height, int direction, Vector3 center)
        {
            var c = go.AddComponent<CapsuleCollider>();
            c.radius = radius;
            c.height = height;
            c.direction = direction;
            c.center = center;
            c.sharedMaterial = Kit.BodyMat;
        }

        static Hand MakeHand(Brawler b, Rigidbody fore, bool left)
        {
            var h = fore.gameObject.AddComponent<Hand>();
            h.owner = b;
            h.rb = fore;
            h.isLeft = left;
            h.fistLocal = new Vector3(0, -0.19f, 0);
            return h;
        }

        static ConfigurableJoint Joint(Rigidbody child, Rigidbody parent, Vector3 anchorWorld,
            float lowX, float highX, float y, float z, bool free = false)
        {
            var j = child.gameObject.AddComponent<ConfigurableJoint>();
            j.connectedBody = parent;
            j.autoConfigureConnectedAnchor = true;
            j.anchor = child.transform.InverseTransformPoint(anchorWorld);
            j.axis = Vector3.right;
            j.secondaryAxis = Vector3.up;
            j.xMotion = j.yMotion = j.zMotion = ConfigurableJointMotion.Locked;
            if (free)
            {
                j.angularXMotion = j.angularYMotion = j.angularZMotion = ConfigurableJointMotion.Free;
            }
            else
            {
                j.angularXMotion = j.angularYMotion = j.angularZMotion = ConfigurableJointMotion.Limited;
                j.lowAngularXLimit = new SoftJointLimit { limit = lowX };
                j.highAngularXLimit = new SoftJointLimit { limit = highX };
                j.angularYLimit = new SoftJointLimit { limit = y };
                j.angularZLimit = new SoftJointLimit { limit = z };
            }
            j.rotationDriveMode = RotationDriveMode.Slerp;
            j.projectionMode = JointProjectionMode.PositionAndRotation;
            j.projectionDistance = 0.03f;
            j.projectionAngle = 8f;
            j.enablePreprocessing = false;
            j.enableCollision = false;
            return j;
        }
    }
}
