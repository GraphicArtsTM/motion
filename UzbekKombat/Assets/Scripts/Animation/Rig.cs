using UnityEngine;

namespace UzbekKombat
{
    /// <summary>Tana proporsiyalari — har bir qahramon uchun alohida.</summary>
    public class BodyShape
    {
        public float height = 1f;      // umumiy masshtab
        public float shoulders = 1f;   // yelka kengligi
        public float bulk = 1f;        // gavda yo'g'onligi
        public float legLength = 1f;
        public float armLength = 1f;
    }

    /// <summary>
    /// Protsedural skelet. Dam olish holati: qo'llar pastga osilgan, oyoqlar tik, yuz +Z ga.
    /// Konventsiya (Euler, gradus):
    ///   Qo'l/son X manfiy = oldinga ko'tarish, Y = gorizontal burish, Z (+ o'ng qo'l uchun) = yon tomonga.
    ///   Bilak X manfiy = tirsak bukish; Boldir X musbat = tizza bukish.
    ///   Umurtqa X musbat = oldinga egilish, Y musbat = kamera tomon burilish.
    /// </summary>
    public class Rig : MonoBehaviour
    {
        public const int BoneCount = 17;
        public static readonly int[] Parent =
        {
            -1, 0, 1, 2, 3,
            2, 5, 6,
            2, 8, 9,
            0, 11, 12,
            0, 14, 15
        };

        public Transform model;          // ko'zgu (mirror) va masshtab uchun
        public Transform[] bones = new Transform[BoneCount];
        public Vector3[] restPos = new Vector3[BoneCount];
        public BodyShape shape;
        public float scale = 1f;

        // Qurol o'rnatish nuqtalari
        public Transform mountR, mountL, mountBack;
        public Transform weaponTipR, weaponTipL, weaponBaseR, weaponBaseL;

        public Transform this[Bone b] => bones[(int)b];

        public static Rig Create(Transform parent, BodyShape shape, string name = "Rig")
        {
            var root = new GameObject(name);
            root.transform.SetParent(parent, false);
            var rig = root.AddComponent<Rig>();
            rig.shape = shape;
            rig.scale = shape.height;

            var model = new GameObject("Model").transform;
            model.SetParent(root.transform, false);
            model.localScale = Vector3.one * shape.height;
            rig.model = model;

            float sw = shape.shoulders, ll = shape.legLength, al = shape.armLength;
            float thigh = 0.45f * ll, shin = 0.43f * ll, foot = 0.08f;
            float hipsY = thigh + shin + foot + 0.04f;

            Vector3[] offsets =
            {
                new Vector3(0, hipsY, 0),            // Hips
                new Vector3(0, 0.10f, 0),            // Spine
                new Vector3(0, 0.20f, 0),            // Chest
                new Vector3(0, 0.26f, 0),            // Neck
                new Vector3(0, 0.09f, 0),            // Head
                new Vector3(-0.20f * sw, 0.20f, 0),  // UpperArmL
                new Vector3(0, -0.29f * al, 0),      // ForeArmL
                new Vector3(0, -0.26f * al, 0),      // HandL
                new Vector3(0.20f * sw, 0.20f, 0),   // UpperArmR
                new Vector3(0, -0.29f * al, 0),      // ForeArmR
                new Vector3(0, -0.26f * al, 0),      // HandR
                new Vector3(-0.10f, -0.04f, 0),      // ThighL
                new Vector3(0, -thigh, 0),           // ShinL
                new Vector3(0, -shin, 0),            // FootL
                new Vector3(0.10f, -0.04f, 0),       // ThighR
                new Vector3(0, -thigh, 0),           // ShinR
                new Vector3(0, -shin, 0),            // FootR
            };

            for (int i = 0; i < BoneCount; i++)
            {
                var t = new GameObject(((Bone)i).ToString()).transform;
                t.SetParent(Parent[i] < 0 ? model : rig.bones[Parent[i]], false);
                t.localPosition = offsets[i];
                rig.bones[i] = t;
                rig.restPos[i] = offsets[i];
            }

            rig.mountR = MakeMount(rig[Bone.HandR], "MountR", new Vector3(0, -0.07f, 0.0f));
            rig.mountL = MakeMount(rig[Bone.HandL], "MountL", new Vector3(0, -0.07f, 0.0f));
            rig.mountBack = MakeMount(rig[Bone.Chest], "MountBack", new Vector3(0, 0.12f, -0.17f));
            return rig;
        }

        static Transform MakeMount(Transform parent, string name, Vector3 pos)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.localPosition = pos;
            return t;
        }

        public Vector3 Pos(Bone b) => bones[(int)b].position;

        /// <summary>Yerga tegish nuqtalari: (suyak, lokal ofset). Grounding uchun.</summary>
        public static readonly (Bone bone, Vector3 offset)[] ContactPoints =
        {
            (Bone.FootL, new Vector3(0, -0.075f, 0.15f)), (Bone.FootL, new Vector3(0, -0.075f, -0.05f)),
            (Bone.FootR, new Vector3(0, -0.075f, 0.15f)), (Bone.FootR, new Vector3(0, -0.075f, -0.05f)),
            (Bone.ShinL, new Vector3(0, 0f, 0.06f)), (Bone.ShinR, new Vector3(0, 0f, 0.06f)),
            (Bone.Hips, new Vector3(0, -0.02f, -0.12f)), (Bone.Chest, new Vector3(0, 0.1f, -0.16f)),
            (Bone.Chest, new Vector3(0, 0.1f, 0.16f)), (Bone.Head, new Vector3(0, 0.12f, 0f)),
            (Bone.HandL, new Vector3(0, -0.06f, 0)), (Bone.HandR, new Vector3(0, -0.06f, 0)),
        };
    }
}
