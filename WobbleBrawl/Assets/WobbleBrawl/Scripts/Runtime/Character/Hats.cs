using UnityEngine;

namespace WobbleBrawl
{
    /// <summary>Cosmetic headwear built from primitives. The round winner also gets a crown.</summary>
    public static class Hats
    {
        public static string Name(HatKind k)
        {
            switch (k)
            {
                case HatKind.TopHat: return "Цилиндр";
                case HatKind.Beanie: return "Шапка";
                case HatKind.Cap: return "Кепка";
                case HatKind.Viking: return "Викинг";
                case HatKind.Chef: return "Повар";
                default: return "Без шляпы";
            }
        }

        public static void Put(Transform head, HatKind kind, Color skin)
        {
            var root = new GameObject("Hat_" + kind).transform;
            root.SetParent(head, false);
            root.localPosition = new Vector3(0, 0.18f, 0);
            switch (kind)
            {
                case HatKind.TopHat:
                {
                    var c = new Color(0.1f, 0.1f, 0.12f);
                    Kit.Deco(PrimitiveType.Cylinder, root, new Vector3(0, 0.02f, 0), new Vector3(0.48f, 0.015f, 0.48f), c, null, true, 0.5f);
                    Kit.Deco(PrimitiveType.Cylinder, root, new Vector3(0, 0.17f, 0), new Vector3(0.3f, 0.15f, 0.3f), c, null, true, 0.5f);
                    Kit.Deco(PrimitiveType.Cylinder, root, new Vector3(0, 0.07f, 0), new Vector3(0.31f, 0.03f, 0.31f), new Color(0.7f, 0.1f, 0.1f), null, false);
                    break;
                }
                case HatKind.Beanie:
                {
                    var c = new Color(0.95f, 0.3f, 0.25f);
                    if (Mathf.Abs(c.r - skin.r) < 0.1f) c = new Color(0.2f, 0.4f, 0.9f);
                    Kit.Deco(PrimitiveType.Sphere, root, new Vector3(0, -0.02f, 0), new Vector3(0.5f, 0.32f, 0.5f), c, null, true, 0.1f);
                    Kit.Deco(PrimitiveType.Cylinder, root, new Vector3(0, -0.08f, 0), new Vector3(0.52f, 0.04f, 0.52f), Color.white, null, false);
                    Kit.Deco(PrimitiveType.Sphere, root, new Vector3(0, 0.16f, 0), Vector3.one * 0.13f, Color.white, null, false, 0.05f);
                    break;
                }
                case HatKind.Cap:
                {
                    var c = new Color(0.15f, 0.5f, 0.95f);
                    if (Mathf.Abs(c.b - skin.b) < 0.1f) c = new Color(0.95f, 0.85f, 0.2f);
                    Kit.Deco(PrimitiveType.Sphere, root, new Vector3(0, -0.03f, 0), new Vector3(0.49f, 0.28f, 0.49f), c, null, true, 0.2f);
                    Kit.Deco(PrimitiveType.Cube, root, new Vector3(0, -0.06f, 0.27f), new Vector3(0.34f, 0.025f, 0.2f), c, Quaternion.Euler(-8, 0, 0), true);
                    break;
                }
                case HatKind.Viking:
                {
                    var metal = new Color(0.62f, 0.62f, 0.66f);
                    var horn = new Color(0.95f, 0.9f, 0.78f);
                    Kit.Deco(PrimitiveType.Sphere, root, new Vector3(0, -0.04f, 0), new Vector3(0.5f, 0.32f, 0.5f), metal, null, true, 0.7f);
                    Kit.Deco(PrimitiveType.Cylinder, root, new Vector3(0, -0.1f, 0), new Vector3(0.52f, 0.03f, 0.52f), new Color(0.55f, 0.4f, 0.2f), null, false);
                    Kit.Deco(PrimitiveType.Capsule, root, new Vector3(-0.24f, 0.06f, 0), new Vector3(0.07f, 0.13f, 0.07f), horn, Quaternion.Euler(0, 0, 40), true);
                    Kit.Deco(PrimitiveType.Capsule, root, new Vector3(0.24f, 0.06f, 0), new Vector3(0.07f, 0.13f, 0.07f), horn, Quaternion.Euler(0, 0, -40), true);
                    break;
                }
                case HatKind.Chef:
                {
                    Kit.Deco(PrimitiveType.Cylinder, root, new Vector3(0, 0.06f, 0), new Vector3(0.36f, 0.09f, 0.36f), Color.white, null, true, 0.1f);
                    Kit.Deco(PrimitiveType.Sphere, root, new Vector3(0, 0.2f, 0), new Vector3(0.46f, 0.26f, 0.46f), Color.white, null, true, 0.1f);
                    break;
                }
            }
        }

        public static GameObject Crown(Transform head)
        {
            var root = new GameObject("Crown").transform;
            root.SetParent(head, false);
            root.localPosition = new Vector3(0, 0.25f, 0);
            var gold = new Color(1f, 0.8f, 0.2f);
            Kit.Deco(PrimitiveType.Cylinder, root, Vector3.zero, new Vector3(0.34f, 0.05f, 0.34f), gold, null, true, 0.85f, 0.3f);
            for (int i = 0; i < 6; i++)
            {
                float a = i * Mathf.PI / 3f;
                var p = new Vector3(Mathf.Cos(a) * 0.15f, 0.08f, Mathf.Sin(a) * 0.15f);
                Kit.Deco(PrimitiveType.Cube, root, p, new Vector3(0.05f, 0.1f, 0.05f), gold, Quaternion.Euler(0, -a * Mathf.Rad2Deg, 0), false, 0.85f, 0.3f);
                Kit.Deco(PrimitiveType.Sphere, root, p + Vector3.up * 0.06f, Vector3.one * 0.04f, new Color(0.9f, 0.1f, 0.3f), null, false, 0.9f);
            }
            return root.gameObject;
        }
    }
}
