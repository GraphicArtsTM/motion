using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Visual
{
    /// <summary>
    /// «Резчик по дереву»: собирает деревянных узбекских персонажей из процедурных деталей.
    ///  Shoh   — Амир в короне поверх чалмы, с плащом и саблей;
    ///  Farzin — Визирь-полководец в чалме с джигой (пером), с бородой и большой саблей;
    ///  Rux    — Страж крепости в шлеме на башне с изразцовым поясом;
    ///  Fil    — Боевой слон с бирюзовым куполом-кажавой и погонщиком-воином;
    ///  Ot     — Чавандоз в тельпаке верхом на коне;
    ///  Piyoda — Сарбоз в чустской тюбетейке, со щитом и саблей.
    /// Все фигуры смотрят вдоль +Z. Размер клетки = 1.
    /// </summary>
    public static class PieceFactory
    {
        const float PedestalTop = 0.105f;

        struct Ctx
        {
            public SideStyle S;
            public PieceView V;
        }

        public static PieceView Create(PieceType type, Side side, Transform parent, int layer = 0)
        {
            var root = new GameObject(side + "_" + type);
            root.transform.SetParent(parent, false);
            var view = root.AddComponent<PieceView>();
            view.Type = type;
            view.Side = side;

            var model = new GameObject("Model").transform;
            model.SetParent(root.transform, false);
            view.Model = model;

            var c = new Ctx { S = MaterialLib.For(side), V = view };

            switch (type)
            {
                case PieceType.Pawn: BuildPawn(c, model); break;
                case PieceType.Knight: BuildKnight(c, model); break;
                case PieceType.Bishop: BuildBishop(c, model); break;
                case PieceType.Rook: BuildRook(c, model); break;
                case PieceType.Queen: BuildQueen(c, model); break;
                case PieceType.King: BuildKing(c, model); break;
            }

            var col = root.AddComponent<CapsuleCollider>();
            col.radius = 0.34f;
            col.height = Mathf.Max(view.Height, 0.7f);
            col.center = new Vector3(0, col.height * 0.5f, 0);

            SetLayer(root, layer);
            view.Init();
            return view;
        }

        public static void SetLayer(GameObject go, int layer)
        {
            go.layer = layer;
            foreach (Transform t in go.transform) SetLayer(t.gameObject, layer);
        }

        // =================================================================== Примитивы

        static Transform Node(Transform parent, string name, Vector3 pos, Vector3 euler = default(Vector3), float scale = 1f)
        {
            var t = new GameObject(name).transform;
            t.SetParent(parent, false);
            t.localPosition = pos;
            t.localRotation = Quaternion.Euler(euler);
            t.localScale = Vector3.one * scale;
            return t;
        }

        static Transform Part(Transform parent, string name, Mesh mesh, Material mat, Vector3 pos, Vector3 euler, Vector3 scale)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = pos;
            go.transform.localRotation = Quaternion.Euler(euler);
            go.transform.localScale = scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterial = mat;
            return go.transform;
        }

        static Transform Ball(Transform p, Material m, Vector3 c, Vector3 radii, Vector3 euler = default(Vector3))
        {
            return Part(p, "ball", MeshBuilder.Sphere, m, c, euler, radii);
        }

        static Transform Ball(Transform p, Material m, Vector3 c, float r)
        {
            return Part(p, "ball", MeshBuilder.Sphere, m, c, Vector3.zero, Vector3.one * r);
        }

        static Transform Cyl(Transform p, Material m, Vector3 basePos, float r, float h, Vector3 euler = default(Vector3))
        {
            return Part(p, "cyl", MeshBuilder.Cylinder, m, basePos, euler, new Vector3(r, h, r));
        }

        static Transform Box(Transform p, Material m, Vector3 c, Vector3 size, Vector3 euler = default(Vector3))
        {
            return Part(p, "box", MeshBuilder.Cube, m, c, euler, size);
        }

        static Transform Ring(Transform p, Material m, Vector3 c, float R, float r, Vector3 euler = default(Vector3))
        {
            return Part(p, "ring", MeshBuilder.Torus(R, r, 28, 8), m, c, euler, Vector3.one);
        }

        static Transform Turned(Transform p, string key, Material m, Vector3 pos, Vector2[] profile, int seg = 24, float start = 0f, float sweep = 360f, bool flat = false, float uRepeat = 1f)
        {
            var mesh = MeshBuilder.Cached("lathe." + key, () => MeshBuilder.Lathe(key, profile, seg, start, sweep, flat, uRepeat));
            return Part(p, key, mesh, m, pos, Vector3.zero, Vector3.one);
        }

        /// <summary>Конечность-капсула от a до b.</summary>
        static Transform Limb(Transform p, Material m, Vector3 a, Vector3 b, float r)
        {
            float len = Vector3.Distance(a, b) + 2f * r;
            string key = "limb." + Mathf.Round(r * 1000f) + "." + Mathf.Round(len * 1000f);
            var mesh = MeshBuilder.Cached(key, () => MeshBuilder.Lathe(key, MeshBuilder.CapsuleProfile(r, len, 4), 12));
            Vector3 dir = (b - a).normalized;
            var t = Part(p, "limb", mesh, m, a - dir * r, Vector3.zero, Vector3.one);
            t.localRotation = Quaternion.FromToRotation(Vector3.up, dir);
            return t;
        }

        static Transform Cone(Transform p, Material m, Vector3 basePos, float r, float h, Vector3 euler = default(Vector3))
        {
            var mesh = MeshBuilder.Cached("cone", () => MeshBuilder.Lathe("cone", new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 0), new Vector2(0, 1) }, 12));
            return Part(p, "cone", mesh, m, basePos, euler, new Vector3(r, h, r));
        }

        // =================================================================== Общие детали

        static void Pedestal(Ctx c, Transform p, float scale = 1f)
        {
            var n = Node(p, "Pedestal", Vector3.zero, Vector3.zero, scale);
            Turned(n, "pedestal", c.S.Wood, Vector3.zero, new[]
            {
                new Vector2(0, 0), new Vector2(0.33f, 0), new Vector2(0.345f, 0.012f), new Vector2(0.345f, 0.03f),
                new Vector2(0.325f, 0.042f), new Vector2(0.30f, 0.05f), new Vector2(0.29f, 0.07f), new Vector2(0.305f, 0.085f),
                new Vector2(0.30f, 0.095f), new Vector2(0.27f, 0.105f), new Vector2(0, 0.105f)
            }, 32);
            Ring(n, c.S.Accent, new Vector3(0, 0.021f, 0), 0.343f, 0.012f);
            Ring(n, c.S.Metal, new Vector3(0, 0.072f, 0), 0.292f, 0.008f);
        }

        /// <summary>Сабля (қилич): начало координат — центр рукояти, клинок вдоль +Y.</summary>
        static Transform Sword(Ctx c, Transform hand, float scale)
        {
            var s = Node(hand, "Sword", Vector3.zero, new Vector3(60, 0, 0), scale);
            Limb(s, c.S.WoodAlt, new Vector3(0, -0.04f, 0), new Vector3(0, 0.03f, 0), 0.012f);
            Ball(s, c.S.Metal, new Vector3(0, -0.055f, 0), 0.018f);
            Box(s, c.S.Metal, new Vector3(0, 0.04f, 0), new Vector3(0.022f, 0.016f, 0.095f));
            Part(s, "blade", MeshBuilder.SabreBlade(0.34f, 0.034f, -0.05f), MaterialLib.Steel, new Vector3(0, 0.046f, 0), Vector3.zero, Vector3.one);
            var tip = Node(s, "Tip", new Vector3(0, 0.046f + 0.33f, -0.048f));
            c.V.SwordTip = tip;
            c.V.Sword = s;
            return s;
        }

        static void Shield(Ctx c, Transform armL)
        {
            var sh = Node(armL, "Shield", new Vector3(-0.01f, -0.19f, 0.055f));
            Part(sh, "disc", MeshBuilder.Cylinder, c.S.Shield, Vector3.zero, new Vector3(90, 0, 0), new Vector3(0.105f, 0.022f, 0.105f));
            Ring(sh, c.S.Metal, new Vector3(0, 0, 0.012f), 0.104f, 0.011f, new Vector3(90, 0, 0));
            Ball(sh, c.S.Metal, new Vector3(0, 0, 0.024f), new Vector3(0.026f, 0.026f, 0.018f));
        }

        public struct HumanOpts
        {
            public bool Seated;
            public float LegSpread;
            public bool Beard;
            public bool LongBeard;
            public bool Cape;
            public bool Shield;
            public float SwordScale;
        }

        /// <summary>
        /// Фигура в чапане. Единицы «человека»: пояс на 0.40, макушка ≈ 0.765.
        /// Возвращает узел тела (для наклонов в бою).
        /// </summary>
        static Transform Human(Ctx c, Transform parent, Vector3 pos, float scale, HumanOpts o)
        {
            var body = Node(parent, "Body", pos, Vector3.zero, scale);
            c.V.Body = body;
            var S = c.S;

            if (!o.Seated)
            {
                Turned(body, "robe", S.Robe, Vector3.zero, new[]
                {
                    new Vector2(0, 0), new Vector2(0.19f, 0), new Vector2(0.195f, 0.015f), new Vector2(0.185f, 0.05f),
                    new Vector2(0.165f, 0.16f), new Vector2(0.148f, 0.27f), new Vector2(0.136f, 0.36f), new Vector2(0.13f, 0.40f), new Vector2(0, 0.40f)
                }, 24, 0, 360, false, 2f);
                Ring(body, S.Metal, new Vector3(0, 0.018f, 0), 0.19f, 0.012f);
                Box(body, S.Metal, new Vector3(0, 0.2f, 0.163f), new Vector3(0.024f, 0.38f, 0.012f), new Vector3(-8.5f, 0, 0));
            }
            else
            {
                Turned(body, "robe.seated", S.Robe, Vector3.zero, new[]
                {
                    new Vector2(0, 0.28f), new Vector2(0.21f, 0.28f), new Vector2(0.2f, 0.3f), new Vector2(0.16f, 0.36f), new Vector2(0.135f, 0.40f), new Vector2(0, 0.40f)
                }, 24, 0, 360, false, 2f);
                float sx = o.LegSpread;
                Limb(body, S.Robe, new Vector3(sx * 0.6f, 0.36f, 0.02f), new Vector3(sx, 0.26f, 0.10f), 0.045f);
                Limb(body, S.Robe, new Vector3(-sx * 0.6f, 0.36f, 0.02f), new Vector3(-sx, 0.26f, 0.10f), 0.045f);
                Limb(body, S.WoodAlt, new Vector3(sx, 0.26f, 0.10f), new Vector3(sx * 1.04f, 0.07f, 0.05f), 0.038f);
                Limb(body, S.WoodAlt, new Vector3(-sx, 0.26f, 0.10f), new Vector3(-sx * 1.04f, 0.07f, 0.05f), 0.038f);
                Ball(body, S.WoodAlt, new Vector3(sx * 1.05f, 0.05f, 0.08f), new Vector3(0.035f, 0.03f, 0.06f));
                Ball(body, S.WoodAlt, new Vector3(-sx * 1.05f, 0.05f, 0.08f), new Vector3(0.035f, 0.03f, 0.06f));
            }

            // Пояс-белбог с узлом
            Ring(body, S.Accent2, new Vector3(0, 0.40f, 0), 0.135f, 0.022f);
            Ball(body, S.Accent2, new Vector3(-0.055f, 0.385f, 0.125f), new Vector3(0.032f, 0.03f, 0.022f));

            // Торс
            Turned(body, "torso", S.Robe, Vector3.zero, new[]
            {
                new Vector2(0, 0.40f), new Vector2(0.135f, 0.40f), new Vector2(0.145f, 0.46f), new Vector2(0.14f, 0.52f),
                new Vector2(0.115f, 0.575f), new Vector2(0.06f, 0.605f), new Vector2(0, 0.61f)
            }, 24, 0, 360, false, 2f);
            Ring(body, S.Metal, new Vector3(0, 0.598f, 0), 0.058f, 0.015f);

            if (o.Cape)
            {
                Turned(body, "cape", S.Accent, Vector3.zero, new[]
                {
                    new Vector2(0.215f, 0.01f), new Vector2(0.205f, 0.15f), new Vector2(0.18f, 0.32f), new Vector2(0.16f, 0.46f),
                    new Vector2(0.15f, 0.56f), new Vector2(0.11f, 0.6f)
                }, 18, 205f, 130f);
                Ring(body, S.Metal, new Vector3(0, 0.56f, 0), 0.15f, 0.012f);
            }

            // Голова
            var head = Node(body, "Head", new Vector3(0, 0.61f, 0));
            c.V.Head = head;
            Cyl(head, S.Wood, new Vector3(0, -0.015f, 0), 0.036f, 0.05f);
            Ball(head, S.Wood, new Vector3(0, 0.075f, 0), new Vector3(0.072f, 0.08f, 0.072f));
            Ball(head, S.Wood, new Vector3(0, 0.07f, 0.07f), new Vector3(0.014f, 0.022f, 0.018f));
            Ball(head, MaterialLib.EyeBlack, new Vector3(0.026f, 0.087f, 0.062f), 0.011f);
            Ball(head, MaterialLib.EyeBlack, new Vector3(-0.026f, 0.087f, 0.062f), 0.011f);
            Box(head, S.WoodAlt, new Vector3(0.027f, 0.104f, 0.064f), new Vector3(0.03f, 0.007f, 0.01f), new Vector3(0, 0, -8));
            Box(head, S.WoodAlt, new Vector3(-0.027f, 0.104f, 0.064f), new Vector3(0.03f, 0.007f, 0.01f), new Vector3(0, 0, 8));
            Ball(head, S.WoodAlt, new Vector3(0, 0.05f, 0.066f), new Vector3(0.036f, 0.009f, 0.013f));
            if (o.LongBeard)
            {
                // длинная борода ложится на грудь
                Ball(head, S.WoodAlt, new Vector3(0, 0.03f, 0.045f), new Vector3(0.056f, 0.05f, 0.042f));
                Ball(head, S.WoodAlt, new Vector3(0, -0.03f, 0.1f), new Vector3(0.05f, 0.07f, 0.036f), new Vector3(-15, 0, 0));
                Cone(head, S.WoodAlt, new Vector3(0, -0.07f, 0.122f), 0.034f, 0.06f, new Vector3(160, 0, 0));
            }
            else if (o.Beard)
            {
                Ball(head, S.WoodAlt, new Vector3(0, 0.03f, 0.045f), new Vector3(0.055f, 0.05f, 0.04f));
            }

            // Плечи и руки
            Ball(body, S.Robe, new Vector3(0.135f, 0.545f, 0), 0.05f);
            Ball(body, S.Robe, new Vector3(-0.135f, 0.545f, 0), 0.05f);

            var armR = Node(body, "ArmR", new Vector3(0.15f, 0.55f, 0));
            Limb(armR, S.Robe, Vector3.zero, new Vector3(0, -0.2f, 0), 0.036f);
            Ring(armR, S.Metal, new Vector3(0, -0.195f, 0), 0.034f, 0.01f);
            var handR = Node(armR, "HandR", new Vector3(0, -0.235f, 0));
            Ball(handR, S.Wood, Vector3.zero, 0.033f);
            Sword(c, handR, o.SwordScale <= 0f ? 1f : o.SwordScale);
            c.V.ArmR = armR;

            var armL = Node(body, "ArmL", new Vector3(-0.15f, 0.55f, 0));
            Limb(armL, S.Robe, Vector3.zero, new Vector3(0, -0.2f, 0), 0.036f);
            Ring(armL, S.Metal, new Vector3(0, -0.195f, 0), 0.034f, 0.01f);
            Ball(armL, S.Wood, new Vector3(0, -0.235f, 0), 0.033f);
            if (o.Shield) Shield(c, armL);
            c.V.ArmL = armL;

            c.V.ArmRIdle = new Vector3(-22, 0, 10);
            c.V.ArmLIdle = o.Shield ? new Vector3(-32, 0, -10) : new Vector3(-12, 0, -16);
            return body;
        }

        // =================================================================== Головные уборы

        static void Doppi(Ctx c, Transform head)
        {
            var mesh = MeshBuilder.Cached("lathe.doppi", () => MeshBuilder.Lathe("doppi", new[]
            {
                new Vector2(0, 0), new Vector2(0.076f, 0), new Vector2(0.079f, 0.032f), new Vector2(0.07f, 0.05f),
                new Vector2(0.042f, 0.06f), new Vector2(0, 0.062f)
            }, 4, 45f, 360f, true, 2f));
            Part(head, "doppi", mesh, c.S.Cap, new Vector3(0, 0.112f, 0), Vector3.zero, Vector3.one);
        }

        static void Turban(Ctx c, Transform head, float k, bool plume)
        {
            // чалма начинается над бровями, чтобы лицо оставалось открытым
            var t = Node(head, "Turban", new Vector3(0, 0.13f, 0), Vector3.zero, k);
            Ring(t, c.S.Cloth, Vector3.zero, 0.06f, 0.028f);
            Ring(t, c.S.Cloth, new Vector3(0, 0.033f, -0.004f), 0.054f, 0.027f, new Vector3(8, 30, 0));
            Ring(t, c.S.Cloth, new Vector3(0, 0.062f, -0.006f), 0.043f, 0.025f, new Vector3(-8, 60, 0));
            Ball(t, c.S.Cloth, new Vector3(0, 0.08f, -0.006f), new Vector3(0.046f, 0.038f, 0.046f));
            Ball(t, MaterialLib.Gem, new Vector3(0, 0.036f, 0.08f), new Vector3(0.016f, 0.019f, 0.012f));
            Ring(t, c.S.Metal, new Vector3(0, 0.036f, 0.077f), 0.019f, 0.005f, new Vector3(90, 0, 0));
            if (plume)
            {
                Ball(t, c.S.Metal, new Vector3(0, 0.07f, 0.068f), 0.014f);
                Ball(t, MaterialLib.Ivory, new Vector3(0, 0.13f, 0.055f), new Vector3(0.013f, 0.065f, 0.022f), new Vector3(-18, 0, 0));
            }
        }

        static void Crown(Ctx c, Transform head)
        {
            var t = Node(head, "Crown", new Vector3(0, 0.122f, 0));
            Ring(t, c.S.Cloth, new Vector3(0, 0.006f, 0), 0.06f, 0.027f);
            Turned(t, "crown.band", c.S.Metal, new Vector3(0, 0.0f, 0), new[]
            {
                new Vector2(0, 0.02f), new Vector2(0.074f, 0.02f), new Vector2(0.079f, 0.026f), new Vector2(0.079f, 0.066f),
                new Vector2(0.084f, 0.072f), new Vector2(0.078f, 0.078f), new Vector2(0.06f, 0.08f), new Vector2(0, 0.08f)
            }, 24);
            Turned(t, "crown.dome", c.S.Accent, new Vector3(0, 0.0f, 0), new[]
            {
                new Vector2(0, 0.075f), new Vector2(0.066f, 0.075f), new Vector2(0.062f, 0.11f), new Vector2(0.045f, 0.145f),
                new Vector2(0.022f, 0.17f), new Vector2(0.008f, 0.19f), new Vector2(0, 0.195f)
            }, 16, 0, 360, true);
            Ball(t, c.S.Metal, new Vector3(0, 0.205f, 0), 0.017f);
            for (int i = 0; i < 8; i++)
            {
                float a = i * Mathf.PI / 4f + Mathf.PI / 2f;
                var pos = new Vector3(Mathf.Cos(a) * 0.076f, 0.078f, Mathf.Sin(a) * 0.076f);
                Cone(t, c.S.Metal, pos, 0.014f, 0.045f);
                if (i % 2 == 0) Ball(t, i % 4 == 0 ? MaterialLib.Gem : MaterialLib.GemBlue, new Vector3(Mathf.Cos(a) * 0.081f, 0.045f, Mathf.Sin(a) * 0.081f), 0.012f);
            }
        }

        static void Helmet(Ctx c, Transform head)
        {
            var t = Node(head, "Helmet", new Vector3(0, 0.1f, 0));
            Turned(t, "helmet", MaterialLib.Steel, Vector3.zero, new[]
            {
                new Vector2(0, 0), new Vector2(0.08f, 0), new Vector2(0.083f, 0.02f), new Vector2(0.076f, 0.055f),
                new Vector2(0.056f, 0.09f), new Vector2(0.03f, 0.115f), new Vector2(0.012f, 0.14f), new Vector2(0.004f, 0.175f), new Vector2(0, 0.18f)
            }, 20);
            Ring(t, c.S.Metal, new Vector3(0, 0.004f, 0), 0.081f, 0.01f);
            Box(t, MaterialLib.Steel, new Vector3(0, -0.03f, 0.08f), new Vector3(0.013f, 0.06f, 0.008f));
            Ball(t, c.S.Accent, new Vector3(0, 0.18f, 0), 0.012f);
            Turned(t, "aventail", c.S.Metal, Vector3.zero, new[]
            {
                new Vector2(0.092f, -0.07f), new Vector2(0.088f, -0.03f), new Vector2(0.084f, 0.0f)
            }, 14, 200f, 140f);
        }

        static void Telpak(Ctx c, Transform head)
        {
            Turned(head, "telpak", c.S.Fur, new Vector3(0, 0.1f, 0), new[]
            {
                new Vector2(0, 0), new Vector2(0.086f, 0), new Vector2(0.102f, 0.022f), new Vector2(0.11f, 0.062f),
                new Vector2(0.102f, 0.1f), new Vector2(0.072f, 0.116f), new Vector2(0, 0.122f)
            }, 20, 0, 360, false, 3f);
        }

        // =================================================================== Фигуры

        static void BuildPawn(Ctx c, Transform m)
        {
            Pedestal(c, m);
            Human(c, m, new Vector3(0, PedestalTop, 0), 0.72f, new HumanOpts { Shield = true, SwordScale = 0.9f });
            Doppi(c, c.V.Head);
            c.V.Height = PedestalTop + 0.72f * 0.83f;
        }

        static void BuildQueen(Ctx c, Transform m)
        {
            Pedestal(c, m);
            Human(c, m, new Vector3(0, PedestalTop, 0), 1.0f, new HumanOpts { LongBeard = true, Cape = true, SwordScale = 1.12f });
            Turban(c, c.V.Head, 1.15f, true);
            c.V.Height = PedestalTop + 1.0f * 0.95f;
        }

        static void BuildKing(Ctx c, Transform m)
        {
            Pedestal(c, m, 1.03f);
            Human(c, m, new Vector3(0, PedestalTop * 1.03f, 0), 1.08f, new HumanOpts { LongBeard = true, Cape = true, SwordScale = 1.15f });
            Crown(c, c.V.Head);
            c.V.Height = PedestalTop + 1.08f * 1.0f;
        }

        static void BuildRook(Ctx c, Transform m)
        {
            var S = c.S;
            var tower = Node(m, "Tower", Vector3.zero);
            Turned(tower, "tower", S.Wood, Vector3.zero, new[]
            {
                new Vector2(0, 0), new Vector2(0.35f, 0), new Vector2(0.362f, 0.015f), new Vector2(0.362f, 0.035f),
                new Vector2(0.33f, 0.05f), new Vector2(0.30f, 0.06f), new Vector2(0.28f, 0.08f), new Vector2(0.268f, 0.3f),
                new Vector2(0.29f, 0.32f), new Vector2(0.3f, 0.36f), new Vector2(0, 0.36f)
            }, 32, 0, 360, false, 3f);
            Ring(tower, S.Accent, new Vector3(0, 0.025f, 0), 0.36f, 0.012f);
            Turned(tower, "tower.tiles", S.Shield, Vector3.zero, new[]
            {
                new Vector2(0.27f, 0.13f), new Vector2(0.278f, 0.136f), new Vector2(0.276f, 0.214f), new Vector2(0.268f, 0.22f)
            }, 32, 0, 360, false, 6f);
            Ring(tower, S.Metal, new Vector3(0, 0.35f, 0), 0.3f, 0.01f);
            for (int i = 0; i < 8; i++)
            {
                float a = i * 45f + 22.5f;
                float rad = a * Mathf.Deg2Rad;
                Box(tower, S.Wood, new Vector3(Mathf.Cos(rad) * 0.265f, 0.395f, Mathf.Sin(rad) * 0.265f), new Vector3(0.085f, 0.075f, 0.06f), new Vector3(0, 90f - a, 0));
            }
            // ворота с арочным верхом и окна-бойницы
            Box(tower, S.WoodAlt, new Vector3(0, 0.1f, 0.276f), new Vector3(0.09f, 0.12f, 0.02f));
            Ball(tower, S.WoodAlt, new Vector3(0, 0.16f, 0.276f), new Vector3(0.045f, 0.045f, 0.01f));
            Box(tower, S.WoodAlt, new Vector3(0.27f, 0.27f, 0), new Vector3(0.02f, 0.05f, 0.025f));
            Box(tower, S.WoodAlt, new Vector3(-0.27f, 0.27f, 0), new Vector3(0.02f, 0.05f, 0.025f));
            Box(tower, S.WoodAlt, new Vector3(0, 0.27f, -0.27f), new Vector3(0.025f, 0.05f, 0.02f));

            Human(c, m, new Vector3(0, 0.36f, 0.0f), 0.62f, new HumanOpts { Beard = true, Shield = true, SwordScale = 1.05f });
            Helmet(c, c.V.Head);
            c.V.Height = 0.36f + 0.62f * 0.94f;
        }

        static void BuildKnight(Ctx c, Transform m)
        {
            var S = c.S;
            Pedestal(c, m);
            var horse = Node(m, "Horse", new Vector3(0, PedestalTop, 0));
            c.V.Mount = horse;
            var wood = S.Wood;

            Ball(horse, wood, new Vector3(0, 0.29f, -0.02f), new Vector3(0.115f, 0.115f, 0.2f));
            Ball(horse, wood, new Vector3(0, 0.305f, 0.12f), new Vector3(0.1f, 0.11f, 0.1f));
            Ball(horse, wood, new Vector3(0, 0.3f, -0.15f), new Vector3(0.108f, 0.11f, 0.11f));
            // ноги
            float[] lz = { 0.13f, 0.13f, -0.16f, -0.16f };
            float[] lx = { 0.06f, -0.06f, 0.06f, -0.06f };
            for (int i = 0; i < 4; i++)
            {
                bool lifted = i == 0;
                Vector3 top = new Vector3(lx[i], 0.24f, lz[i]);
                Vector3 knee = lifted ? new Vector3(lx[i], 0.16f, lz[i] + 0.07f) : new Vector3(lx[i], 0.12f, lz[i] + 0.01f);
                Vector3 hoof = lifted ? new Vector3(lx[i], 0.09f, lz[i] + 0.05f) : new Vector3(lx[i], 0.02f, lz[i] + 0.015f);
                Limb(horse, wood, top, knee, 0.03f);
                Limb(horse, wood, knee, hoof, 0.024f);
                Cyl(horse, S.WoodAlt, hoof + new Vector3(0, -0.02f, 0), 0.03f, 0.03f);
            }
            // шея и голова
            Part(horse, "neck", MeshBuilder.Tube("horse.neck", new[]
            {
                new Vector3(0, 0.32f, 0.12f), new Vector3(0, 0.40f, 0.19f), new Vector3(0, 0.48f, 0.23f), new Vector3(0, 0.53f, 0.25f)
            }, new[] { 0.08f, 0.066f, 0.056f, 0.05f }, 12), wood, Vector3.zero, Vector3.zero, Vector3.one);
            var head = Node(horse, "HorseHead", new Vector3(0, 0.53f, 0.27f), new Vector3(38, 0, 0));
            Ball(head, wood, new Vector3(0, 0, 0.03f), new Vector3(0.052f, 0.058f, 0.095f));
            Ball(head, wood, new Vector3(0, -0.01f, 0.11f), new Vector3(0.044f, 0.046f, 0.05f));
            Ball(head, MaterialLib.EyeBlack, new Vector3(0.046f, 0.02f, 0.03f), 0.01f);
            Ball(head, MaterialLib.EyeBlack, new Vector3(-0.046f, 0.02f, 0.03f), 0.01f);
            Ball(head, S.WoodAlt, new Vector3(0.022f, -0.015f, 0.155f), 0.008f);
            Ball(head, S.WoodAlt, new Vector3(-0.022f, -0.015f, 0.155f), 0.008f);
            Ring(head, S.Metal, new Vector3(0, -0.005f, 0.1f), 0.05f, 0.006f, new Vector3(90, 0, 0));
            Ring(head, S.Accent, new Vector3(0, 0.0f, 0.03f), 0.058f, 0.006f, new Vector3(90, 0, 0));
            Cone(head, wood, new Vector3(0.025f, 0.05f, -0.03f), 0.015f, 0.045f, new Vector3(-20, 0, -10));
            Cone(head, wood, new Vector3(-0.025f, 0.05f, -0.03f), 0.015f, 0.045f, new Vector3(-20, 0, 10));
            // грива и чёлка
            for (int i = 0; i < 6; i++)
            {
                float t = i / 5f;
                var p = Vector3.Lerp(new Vector3(0, 0.585f, 0.25f), new Vector3(0, 0.40f, 0.11f), t);
                Ball(horse, S.WoodAlt, p, new Vector3(0.016f, 0.036f, 0.03f), new Vector3(-35, 0, 0));
            }
            // хвост
            Part(horse, "tail", MeshBuilder.Tube("horse.tail", new[]
            {
                new Vector3(0, 0.34f, -0.24f), new Vector3(0, 0.33f, -0.31f), new Vector3(0, 0.24f, -0.34f), new Vector3(0, 0.12f, -0.33f)
            }, new[] { 0.028f, 0.036f, 0.03f, 0.014f }, 10), S.WoodAlt, Vector3.zero, Vector3.zero, Vector3.one);
            // попона-адрас и седло
            Ball(horse, S.Robe, new Vector3(0, 0.33f, -0.03f), new Vector3(0.124f, 0.075f, 0.15f));
            Ball(horse, S.Accent, new Vector3(0, 0.39f, -0.03f), new Vector3(0.075f, 0.03f, 0.09f));
            Ball(horse, S.Metal, new Vector3(0, 0.41f, 0.05f), 0.016f);

            // всадник
            Human(c, m, new Vector3(0, PedestalTop + 0.155f, -0.04f), 0.6f, new HumanOpts { Seated = true, LegSpread = 0.2f, Beard = true, SwordScale = 1.1f });
            Telpak(c, c.V.Head);
            c.V.Height = PedestalTop + 0.155f + 0.6f * 0.88f;
        }

        static void BuildBishop(Ctx c, Transform m)
        {
            var S = c.S;
            Pedestal(c, m);
            var el = Node(m, "Elephant", new Vector3(0, PedestalTop, 0), Vector3.zero, 1.08f);
            c.V.Mount = el;
            var wood = S.Wood;

            Ball(el, wood, new Vector3(0, 0.27f, -0.03f), new Vector3(0.15f, 0.14f, 0.2f));
            float[] lz = { 0.1f, 0.1f, -0.13f, -0.13f };
            float[] lx = { 0.085f, -0.085f, 0.085f, -0.085f };
            for (int i = 0; i < 4; i++)
            {
                Limb(el, wood, new Vector3(lx[i], 0.21f, lz[i]), new Vector3(lx[i], 0.02f, lz[i]), 0.046f);
                if (i < 2) Ball(el, MaterialLib.Ivory, new Vector3(lx[i], 0.015f, lz[i] + 0.04f), new Vector3(0.022f, 0.012f, 0.012f));
            }
            Ball(el, wood, new Vector3(0, 0.33f, 0.16f), new Vector3(0.1f, 0.1f, 0.09f));
            for (int sgn = -1; sgn <= 1; sgn += 2)
            {
                Ball(el, wood, new Vector3(sgn * 0.1f, 0.33f, 0.13f), new Vector3(0.022f, 0.088f, 0.078f), new Vector3(0, sgn * 25f, 0));
                Ball(el, S.Accent2, new Vector3(sgn * 0.113f, 0.335f, 0.13f), new Vector3(0.012f, 0.062f, 0.052f), new Vector3(0, sgn * 25f, 0));
                Ball(el, MaterialLib.EyeBlack, new Vector3(sgn * 0.072f, 0.355f, 0.22f), 0.01f);
                string key = sgn < 0 ? "tuskL" : "tuskR";
                Part(el, key, MeshBuilder.Tube("el." + key, new[]
                {
                    new Vector3(sgn * 0.045f, 0.28f, 0.22f), new Vector3(sgn * 0.05f, 0.235f, 0.27f),
                    new Vector3(sgn * 0.054f, 0.235f, 0.32f), new Vector3(sgn * 0.05f, 0.27f, 0.36f)
                }, new[] { 0.016f, 0.013f, 0.009f, 0.003f }, 8), MaterialLib.Ivory, Vector3.zero, Vector3.zero, Vector3.one);
            }
            Part(el, "trunk", MeshBuilder.Tube("el.trunk", new[]
            {
                new Vector3(0, 0.31f, 0.23f), new Vector3(0, 0.25f, 0.28f), new Vector3(0, 0.17f, 0.29f),
                new Vector3(0, 0.1f, 0.3f), new Vector3(0, 0.07f, 0.34f), new Vector3(0, 0.08f, 0.37f)
            }, new[] { 0.042f, 0.034f, 0.028f, 0.023f, 0.019f, 0.016f }, 10), wood, Vector3.zero, Vector3.zero, Vector3.one);
            // налобное украшение
            Ball(el, S.Accent, new Vector3(0, 0.405f, 0.19f), new Vector3(0.06f, 0.016f, 0.05f), new Vector3(-30, 0, 0));
            Ball(el, S.Metal, new Vector3(0, 0.39f, 0.235f), 0.018f);
            // попона, кисти
            Ball(el, S.Robe, new Vector3(0, 0.325f, -0.03f), new Vector3(0.157f, 0.085f, 0.19f));
            Ball(el, S.Metal, new Vector3(0.155f, 0.25f, -0.03f), new Vector3(0.012f, 0.025f, 0.012f));
            Ball(el, S.Metal, new Vector3(-0.155f, 0.25f, -0.03f), new Vector3(0.012f, 0.025f, 0.012f));
            Part(el, "tail", MeshBuilder.Tube("el.tail", new[]
            {
                new Vector3(0, 0.3f, -0.22f), new Vector3(0, 0.24f, -0.25f), new Vector3(0, 0.17f, -0.25f)
            }, new[] { 0.014f, 0.01f, 0.008f }, 6), wood, Vector3.zero, Vector3.zero, Vector3.one);

            // кажава с бирюзовым рёбристым куполом
            Cyl(el, S.Accent, new Vector3(0, 0.395f, -0.1f), 0.1f, 0.03f);
            Ring(el, S.Metal, new Vector3(0, 0.425f, -0.1f), 0.1f, 0.008f);
            var dome = MeshBuilder.Cached("lathe.howdah", () => MeshBuilder.Lathe("howdah", new[]
            {
                new Vector2(0, 0), new Vector2(0.09f, 0), new Vector2(0.095f, 0.02f), new Vector2(0.088f, 0.06f),
                new Vector2(0.062f, 0.1f), new Vector2(0.032f, 0.126f), new Vector2(0.01f, 0.142f), new Vector2(0, 0.15f)
            }, 12, 0, 360, true));
            Part(el, "dome", dome, S.Accent2, new Vector3(0, 0.425f, -0.1f), Vector3.zero, Vector3.one);
            Ball(el, S.Metal, new Vector3(0, 0.585f, -0.1f), 0.014f);
            Cone(el, S.Metal, new Vector3(0, 0.595f, -0.1f), 0.006f, 0.04f);

            // погонщик-воин
            Human(c, m, new Vector3(0, PedestalTop + 0.21f, 0.06f), 0.5f, new HumanOpts { Seated = true, LegSpread = 0.33f, Beard = true, SwordScale = 1.2f });
            Turban(c, c.V.Head, 1.0f, false);
            c.V.Height = PedestalTop + 0.21f + 0.5f * 0.95f;
        }
    }
}
