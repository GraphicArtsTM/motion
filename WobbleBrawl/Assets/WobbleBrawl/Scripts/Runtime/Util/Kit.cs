using UnityEngine;
using UnityEngine.Rendering;

namespace WobbleBrawl
{
    /// <summary>Procedural construction helpers: every mesh in the game is built from primitives.</summary>
    public static class Kit
    {
        static PhysicsMaterial ground, ice, body, prop, bouncy;

        public static PhysicsMaterial GroundMat => ground ??= Make("WB_Ground", 0.8f, 0.9f, 0f, PhysicsMaterialCombine.Average);
        public static PhysicsMaterial IceMat => ice ??= Make("WB_Ice", 0.04f, 0.06f, 0f, PhysicsMaterialCombine.Minimum);
        public static PhysicsMaterial BodyMat => body ??= Make("WB_Body", 0.65f, 0.7f, 0.05f, PhysicsMaterialCombine.Average);
        public static PhysicsMaterial PropMat => prop ??= Make("WB_Prop", 0.55f, 0.6f, 0.1f, PhysicsMaterialCombine.Average);
        public static PhysicsMaterial BouncyMat => bouncy ??= Make("WB_Bouncy", 0.4f, 0.4f, 0.9f, PhysicsMaterialCombine.Average, PhysicsMaterialCombine.Maximum);

        static PhysicsMaterial Make(string name, float dyn, float stat, float bounce, PhysicsMaterialCombine friction,
            PhysicsMaterialCombine bounceCombine = PhysicsMaterialCombine.Average)
        {
            return new PhysicsMaterial(name)
            {
                dynamicFriction = dyn,
                staticFriction = stat,
                bounciness = bounce,
                frictionCombine = friction,
                bounceCombine = bounceCombine,
            };
        }

        /// <summary>Visual-only primitive (no collider).</summary>
        public static GameObject Deco(PrimitiveType type, Transform parent, Vector3 localPos, Vector3 scale, Color color,
            Quaternion? localRot = null, bool shadows = true, float smooth = 0.2f, float emission = 0f)
        {
            var go = new GameObject(type.ToString());
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            go.transform.localRotation = localRot ?? Quaternion.identity;
            go.transform.localScale = scale;
            go.AddComponent<MeshFilter>().sharedMesh = MatFactory.Mesh(type);
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = MatFactory.Lit(color, smooth, emission);
            mr.shadowCastingMode = shadows ? ShadowCastingMode.On : ShadowCastingMode.Off;
            return go;
        }

        /// <summary>Static, solid box (no rigidbody).</summary>
        public static GameObject Box(Transform parent, Vector3 pos, Vector3 size, Color color, Quaternion? rot = null,
            PhysicsMaterial mat = null, float smooth = 0.15f)
        {
            var go = Deco(PrimitiveType.Cube, parent, pos, size, color, rot, true, smooth);
            go.name = "Box";
            var col = go.AddComponent<BoxCollider>();
            col.sharedMaterial = mat ?? GroundMat;
            return go;
        }

        public static GameObject Cylinder(Transform parent, Vector3 pos, float radius, float height, Color color,
            Quaternion? rot = null, bool collider = true)
        {
            var go = Deco(PrimitiveType.Cylinder, parent, pos, new Vector3(radius * 2f, height * 0.5f, radius * 2f), color, rot);
            go.name = "Cylinder";
            if (collider)
            {
                var c = go.AddComponent<MeshCollider>();
                c.sharedMesh = MatFactory.Mesh(PrimitiveType.Cylinder);
                c.convex = true;
                c.sharedMaterial = GroundMat;
            }
            return go;
        }

        /// <summary>Dynamic, grabbable physics prop.</summary>
        public static Rigidbody Crate(Transform parent, Vector3 pos, Vector3 size, Color color, float mass, Quaternion? rot = null)
        {
            var go = Deco(PrimitiveType.Cube, parent, pos, size, color, rot);
            go.name = "Crate";
            var col = go.AddComponent<BoxCollider>();
            col.sharedMaterial = PropMat;
            // darker edge bands make crates read as crates
            var dark = Palette.Darken(color, 0.65f);
            Deco(PrimitiveType.Cube, go.transform, Vector3.zero, new Vector3(1.02f, 0.18f, 1.02f), dark, null, false);
            Deco(PrimitiveType.Cube, go.transform, Vector3.zero, new Vector3(0.18f, 1.02f, 1.02f), dark, null, false);
            return AddBody(go, mass);
        }

        public static Rigidbody Barrel(Transform parent, Vector3 pos, float radius, float height, Color color, float mass)
        {
            var go = Deco(PrimitiveType.Cylinder, parent, pos, new Vector3(radius * 2f, height * 0.5f, radius * 2f), color);
            go.name = "Barrel";
            var c = go.AddComponent<MeshCollider>();
            c.sharedMesh = MatFactory.Mesh(PrimitiveType.Cylinder);
            c.convex = true;
            c.sharedMaterial = PropMat;
            var band = Palette.Darken(color, 0.6f);
            Deco(PrimitiveType.Cylinder, go.transform, new Vector3(0, 0.55f, 0), new Vector3(1.04f, 0.06f, 1.04f), band, null, false);
            Deco(PrimitiveType.Cylinder, go.transform, new Vector3(0, -0.55f, 0), new Vector3(1.04f, 0.06f, 1.04f), band, null, false);
            return AddBody(go, mass);
        }

        public static Rigidbody Ball(Transform parent, Vector3 pos, float radius, Color color, float mass)
        {
            var go = Deco(PrimitiveType.Sphere, parent, pos, Vector3.one * radius * 2f, color, null, true, 0.5f);
            go.name = "Ball";
            go.AddComponent<SphereCollider>().sharedMaterial = BouncyMat;
            return AddBody(go, mass);
        }

        public static Rigidbody AddBody(GameObject go, float mass, bool kinematic = false)
        {
            var rb = go.AddComponent<Rigidbody>();
            rb.mass = mass;
            rb.isKinematic = kinematic;
            rb.interpolation = RigidbodyInterpolation.Interpolate;
            rb.collisionDetectionMode = kinematic ? CollisionDetectionMode.ContinuousSpeculative : CollisionDetectionMode.ContinuousDynamic;
            rb.linearDamping = 0.05f;
            rb.angularDamping = 0.2f;
            return rb;
        }

        public static GameObject Group(Transform parent, string name, Vector3 pos = default)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            return go;
        }

        /// <summary>Simple stylised tree / lamp / props used for decoration.</summary>
        public static void Lamp(Transform parent, Vector3 pos, Color glow, float height = 3f, bool light = false)
        {
            Deco(PrimitiveType.Cylinder, parent, pos + Vector3.up * height * 0.5f, new Vector3(0.12f, height * 0.5f, 0.12f), new Color(0.2f, 0.2f, 0.24f));
            Deco(PrimitiveType.Sphere, parent, pos + Vector3.up * (height + 0.15f), Vector3.one * 0.45f, glow, null, false, 0.8f, 2.5f);
            if (light)
            {
                var l = new GameObject("LampLight").AddComponent<Light>();
                l.transform.SetParent(parent, false);
                l.transform.localPosition = pos + Vector3.up * (height + 0.1f);
                l.type = LightType.Point;
                l.range = 9f;
                l.intensity = 1.6f;
                l.color = glow;
                l.shadows = LightShadows.None;
            }
        }
    }
}
