using UnityEngine;
using Shatranj.Chess;

namespace Shatranj.Visual
{
    /// <summary>Набор материалов одной стороны: из какого дерева вырезаны фигуры и чем расписаны.</summary>
    public sealed class SideStyle
    {
        public Material Wood;       // основная древесина
        public Material WoodAlt;    // тон потемнее (волосы, борода, копыта)
        public Material Robe;       // расписной чапан (адрас)
        public Material Accent;     // основная краска (ляпис / гранат)
        public Material Accent2;    // вторая краска (бирюза / изумруд)
        public Material Metal;      // золото / латунь
        public Material Cloth;      // чалма
        public Material Cap;        // тюбетейка
        public Material Fur;        // тельпак
        public Material Shield;     // расписной щит
        public Color Glow;          // цвет подсветки
    }

    /// <summary>
    /// Все материалы игры. Текстуры генерируются один раз при запуске.
    /// Резные поверхности получают карту нормалей (базовый материал с _NORMALMAP из Resources).
    /// </summary>
    public static class MaterialLib
    {
        public static SideStyle White, Black;
        public static Material Steel, Ivory, EyeBlack, Gem, GemBlue;

        // доска
        public static Material BoardLight, BoardDark, BoardGroove, FrameCarved, FrameSide, FrameWood, Inlay;
        // стол и утварь
        public static Material TableWood, Frame, Carpet, Kurpacha, Porcelain, Bread, Brass, Glaze, GlazeCobalt, Pomegranate, Grape, Sugar;
        public static Material[] Quilts;
        // зал
        public static Material Palos, Ganch, GanchDeep, PanelWood, DoorWood, ColumnWood, BeamPaint, CeilingPaint, Planks, Gilam, DarkWood, Lattice, NicheDark;
        public static Material Rishtan0, Rishtan1, Leather, Skin;
        public static Material TileBlue, TileTurquoise;

        static Material baseStd, baseBump;
        static Shader unlitShader;
        static bool ready;

        public static SideStyle For(Side s) { return s == Side.White ? White : Black; }

        public static void Init()
        {
            if (ready) return;
            ready = true;

            baseStd = Resources.Load<Material>("ShatranjStandard");
            if (baseStd == null)
            {
                var sh = Shader.Find("Standard");
                if (sh == null) sh = Shader.Find("Legacy Shaders/Diffuse");
                baseStd = new Material(sh);
            }
            baseBump = Resources.Load<Material>("ShatranjStandardBump");
            if (baseBump == null)
            {
                baseBump = new Material(baseStd);
                baseBump.EnableKeyword("_NORMALMAP");
            }
            unlitShader = Shader.Find("Sprites/Default");

            Color lapis = TextureFactory.Hex("#1D4C9A"), turq = TextureFactory.Hex("#25A7A6"), gold = TextureFactory.Hex("#D7A43A");
            Color ivory = TextureFactory.Hex("#F3E8CF"), crimson = TextureFactory.Hex("#A01C26"), emerald = TextureFactory.Hex("#1F7A4D");
            Color brass = TextureFactory.Hex("#B8873A"), ink = TextureFactory.Hex("#1A1410");

            var grainFine = TextureFactory.NormalMap("grain.fine", 256, 256, TextureFactory.WoodGrainHeight(11, 9), 2.2f);
            var grainBoard = TextureFactory.NormalMap("grain.board", 256, 256, TextureFactory.WoodGrainHeight(51, 7), 1.6f);

            // ---------------------------------------------------------- Белые: светлая чинара + ляпис и золото
            var wLight = TextureFactory.Hex("#EED9AE"); var wDark = TextureFactory.Hex("#C9A46A");
            White = new SideStyle
            {
                Wood = StdN("w.wood", Color.white, TextureFactory.Wood("chinor", wLight, wDark, 11), grainFine, 0.5f, 0f, null, 0.6f),
                WoodAlt = StdN("w.woodalt", Color.white, TextureFactory.Wood("chinor2", TextureFactory.Hex("#9B7346"), TextureFactory.Hex("#6B4A2A"), 12), grainFine, 0.4f, 0f, null, 0.6f),
                Robe = Std("w.robe", Color.white, TextureFactory.Ikat("white", new[] { lapis, ivory, turq, gold, TextureFactory.Hex("#7FB3E0") }, 5), 0.42f, 0f),
                Accent = Std("w.accent", lapis, null, 0.6f, 0f),
                Accent2 = Std("w.accent2", turq, null, 0.6f, 0f),
                Metal = Std("w.gold", gold, null, 0.78f, 0.9f),
                Cloth = Std("w.cloth", ivory, TextureFactory.Wood("cloth.w", ivory, TextureFactory.Hex("#DCCFB0"), 21, 14), 0.3f, 0f),
                Cap = Std("w.cap", Color.white, TextureFactory.Doppi("white", TextureFactory.Hex("#1E3E7A"), ivory, 3), 0.35f, 0f),
                Fur = Std("w.fur", Color.white, TextureFactory.Fur("white", TextureFactory.Hex("#CDBFA5"), TextureFactory.Hex("#F6EEDC"), 4), 0.1f, 0f),
                Shield = Std("w.shield", Color.white, TextureFactory.Majolica("shield.w", lapis, turq, ivory, gold, 2, 128), 0.6f, 0.1f),
                Glow = new Color(0.45f, 0.75f, 1f)
            };

            // ---------------------------------------------------------- Чёрные: грецкий орех + гранат и латунь
            var bLight = TextureFactory.Hex("#5A3820"); var bDark = TextureFactory.Hex("#24140A");
            Black = new SideStyle
            {
                Wood = StdN("b.wood", Color.white, TextureFactory.Wood("yongoq", bLight, bDark, 31), grainFine, 0.58f, 0f, null, 0.6f),
                WoodAlt = StdN("b.woodalt", Color.white, TextureFactory.Wood("yongoq2", TextureFactory.Hex("#1C110A"), TextureFactory.Hex("#0C0704"), 32), grainFine, 0.5f, 0f, null, 0.6f),
                Robe = Std("b.robe", Color.white, TextureFactory.Ikat("black", new[] { crimson, ink, emerald, gold, TextureFactory.Hex("#5B1A4A") }, 9), 0.45f, 0f),
                Accent = Std("b.accent", crimson, null, 0.6f, 0f),
                Accent2 = Std("b.accent2", emerald, null, 0.6f, 0f),
                Metal = Std("b.brass", brass, null, 0.72f, 0.85f),
                Cloth = Std("b.cloth", Color.white, TextureFactory.Wood("cloth.b", TextureFactory.Hex("#8E1C24"), TextureFactory.Hex("#5E0F16"), 41, 14), 0.3f, 0f),
                Cap = Std("b.cap", Color.white, TextureFactory.Doppi("black", TextureFactory.Hex("#121212"), TextureFactory.Hex("#EDE6D6"), 6), 0.35f, 0f),
                Fur = Std("b.fur", Color.white, TextureFactory.Fur("black", TextureFactory.Hex("#0E0B09"), TextureFactory.Hex("#3A2E25"), 8), 0.1f, 0f),
                Shield = Std("b.shield", Color.white, TextureFactory.Majolica("shield.b", crimson, emerald, ivory, gold, 2, 128), 0.6f, 0.1f),
                Glow = new Color(1f, 0.55f, 0.3f)
            };

            Steel = Std("steel", TextureFactory.Hex("#D8DDE2"), null, 0.88f, 0.95f);
            Ivory = Std("ivory", TextureFactory.Hex("#F4EEDD"), null, 0.65f, 0f);
            EyeBlack = Std("eye", TextureFactory.Hex("#0B0806"), null, 0.9f, 0f);
            Gem = Std("gem", TextureFactory.Hex("#C8102E"), null, 0.95f, 0.2f);
            GemBlue = Std("gemblue", TextureFactory.Hex("#2E7FD9"), null, 0.95f, 0.2f);

            // ---------------------------------------------------------- Доска: паркет, резная рама с позолотой
            BoardLight = StdN("board.light", Color.white, TextureFactory.Wood("board.light", TextureFactory.Hex("#EBD5A6"), TextureFactory.Hex("#CDA972"), 51, 7), grainBoard, 0.62f, 0f, null, 0.5f);
            BoardDark = StdN("board.dark", Color.white, TextureFactory.Wood("board.dark", TextureFactory.Hex("#7A4526"), TextureFactory.Hex("#43230F"), 52, 7), grainBoard, 0.62f, 0f, null, 0.5f);
            BoardGroove = Std("board.groove", TextureFactory.Hex("#1A0E06"), null, 0.3f, 0f);
            Texture2D islimiN;
            var islimi = TextureFactory.CarvedIslimi("frame", TextureFactory.Hex("#2A140A"), TextureFactory.Hex("#6B3C1E"), TextureFactory.Hex("#E0B04A"), TextureFactory.Hex("#2AAFA9"), out islimiN);
            FrameCarved = StdN("frame.carved", Color.white, islimi, islimiN, 0.6f, 0.25f, null, 1.2f);
            Texture2D girihN;
            var girih = TextureFactory.GirihCarved("side", TextureFactory.Hex("#2A160A"), TextureFactory.Hex("#7A4824"), 2, out girihN);
            FrameSide = StdN("frame.side", Color.white, girih, girihN, 0.5f, 0f, null, 1.1f);
            var darkWoodTex = TextureFactory.Wood("frame.wood", TextureFactory.Hex("#5C3418"), TextureFactory.Hex("#2E180A"), 53, 6);
            FrameWood = StdN("frame.wood", Color.white, darkWoodTex, grainBoard, 0.55f, 0f, null, 0.7f);
            Inlay = Std("inlay", gold, null, 0.8f, 0.9f);

            // ---------------------------------------------------------- Хонтахта, текстиль и утварь
            TableWood = StdN("table", Color.white, TextureFactory.Wood("table", TextureFactory.Hex("#7B4B26"), TextureFactory.Hex("#4B2912"), 61, 12), grainFine, 0.5f, 0f, null, 0.6f);
            Frame = Std("frame", Color.white, TextureFactory.Islimi("frame", TextureFactory.Hex("#173A78"), gold, TextureFactory.Hex("#2BB0AE")), 0.55f, 0.15f);
            Carpet = Std("carpet", Color.white, TextureFactory.Suzani(), 0.12f, 0f);
            Kurpacha = Std("kurpacha", Color.white, TextureFactory.Ikat("kurpacha", new[] { crimson, gold, emerald, lapis, ivory }, 17, 8), 0.2f, 0f);
            Quilts = new[]
            {
                Kurpacha,
                Std("quilt1", Color.white, TextureFactory.Ikat("quilt1", new[] { lapis, ivory, turq, gold }, 23, 7), 0.2f, 0f),
                Std("quilt2", Color.white, TextureFactory.Ikat("quilt2", new[] { TextureFactory.Hex("#6B1E5A"), gold, crimson, ivory }, 29, 9), 0.2f, 0f),
                Std("quilt3", Color.white, TextureFactory.Ikat("quilt3", new[] { emerald, gold, ink, ivory }, 37, 6), 0.2f, 0f),
                Std("quilt4", Color.white, TextureFactory.Ikat("quilt4", new[] { TextureFactory.Hex("#D9682B"), lapis, ivory, crimson }, 41, 8), 0.2f, 0f),
            };
            Porcelain = Std("porcelain", Color.white, TextureFactory.Paxta(), 0.88f, 0f);
            Bread = Std("bread", TextureFactory.Hex("#C98A45"), TextureFactory.Wood("bread", TextureFactory.Hex("#E2A65C"), TextureFactory.Hex("#A6662E"), 81, 20), 0.25f, 0f);
            Brass = Std("brass", TextureFactory.Hex("#C59A45"), null, 0.75f, 0.9f);
            Glaze = Std("glaze", TextureFactory.Hex("#1E9BB0"), null, 0.85f, 0f);
            GlazeCobalt = Std("glaze.cobalt", TextureFactory.Hex("#1F3E8C"), null, 0.85f, 0f);
            Pomegranate = Std("anor", TextureFactory.Hex("#9E1622"), null, 0.65f, 0f);
            Grape = Std("uzum", TextureFactory.Hex("#5C2A4E"), null, 0.7f, 0f);
            Sugar = Std("navvot", TextureFactory.Hex("#E8C27A"), null, 0.9f, 0f);

            // ---------------------------------------------------------- Мехмонхона: ганч, резное дерево, роспись
            Texture2D n;
            var ganch = TextureFactory.Ganch(out n);
            Ganch = StdN("ganch", Color.white, ganch, n, 0.15f, 0f, new Vector2(10f, 6f), 1f);
            GanchDeep = StdN("ganch.deep", TextureFactory.Hex("#CDBFA4"), ganch, n, 0.12f, 0f, new Vector2(2f, 3f), 1f);
            var panel = TextureFactory.CarvedPanel("dado", TextureFactory.Hex("#3A2010"), TextureFactory.Hex("#8A5A30"), 1.4f, out n);
            PanelWood = StdN("panel", Color.white, panel, n, 0.5f, 0f, null, 1.2f);
            var door = TextureFactory.CarvedPanel("door", TextureFactory.Hex("#2E180B"), TextureFactory.Hex("#7A4A26"), 1.15f, out n);
            DoorWood = StdN("door", Color.white, door, n, 0.5f, 0f, null, 1.3f);
            var col = TextureFactory.ColumnCarving(TextureFactory.Hex("#3E2312"), TextureFactory.Hex("#9A6A3C"), out n);
            ColumnWood = StdN("column", Color.white, col, n, 0.45f, 0f, new Vector2(1f, 1f), 1.2f);
            BeamPaint = Std("beam", Color.white, TextureFactory.Islimi("beam", TextureFactory.Hex("#8E2024"), gold, TextureFactory.Hex("#2E7D4F")), 0.4f, 0f);
            CeilingPaint = Std("ceiling", Color.white, TextureFactory.CeilingPaint(), 0.3f, 0f, new Vector2(10f, 10f));
            var planks = TextureFactory.Planks(TextureFactory.Hex("#8A5A33"), TextureFactory.Hex("#4A2A14"), out n);
            Planks = StdN("planks", Color.white, planks, n, 0.45f, 0f, new Vector2(7f, 7f), 1f);
            Gilam = Std("gilam", Color.white, TextureFactory.Gilam(), 0.08f, 0f);
            Palos = Std("palos", Color.white, TextureFactory.Palos(), 0.08f, 0f, new Vector2(3f, 1f));
            DarkWood = StdN("darkwood", Color.white, darkWoodTex, grainFine, 0.5f, 0f, null, 0.6f);
            Lattice = Std("lattice", TextureFactory.Hex("#3A2414"), null, 0.35f, 0f);
            NicheDark = Std("niche", TextureFactory.Hex("#B8A889"), null, 0.1f, 0f);
            Rishtan0 = Std("rishtan0", Color.white, TextureFactory.Rishtan(0), 0.85f, 0f);
            Rishtan1 = Std("rishtan1", Color.white, TextureFactory.Rishtan(1), 0.85f, 0f);
            Leather = Std("leather", TextureFactory.Hex("#E9D7B0"), null, 0.3f, 0f);
            Skin = Std("skin", TextureFactory.Hex("#E5CFA3"), null, 0.25f, 0f);

            TileBlue = Std("tile.blue", Color.white, TextureFactory.Majolica("blue", TextureFactory.Hex("#173C8C"), TextureFactory.Hex("#27A9B0"), TextureFactory.Hex("#F2EBDA"), gold), 0.6f, 0f, new Vector2(3, 3));
            TileTurquoise = Std("tile.turq", Color.white, TextureFactory.Majolica("turq", TextureFactory.Hex("#1F9AA6"), TextureFactory.Hex("#123E8A"), TextureFactory.Hex("#E9F3EE"), TextureFactory.Hex("#E9C25A")), 0.65f, 0f, new Vector2(2, 2));
        }

        public static Material Std(string name, Color color, Texture tex, float smooth, float metal, Vector2? tiling = null)
        {
            var m = new Material(baseStd) { name = name };
            m.color = color;
            if (m.HasProperty("_MainTex"))
            {
                m.mainTexture = tex;
                if (tiling.HasValue) m.mainTextureScale = tiling.Value;
            }
            if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", smooth);
            if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", metal);
            m.enableInstancing = true;
            return m;
        }

        /// <summary>Материал с картой нормалей (резьба, волокна дерева).</summary>
        public static Material StdN(string name, Color color, Texture tex, Texture normal, float smooth, float metal, Vector2? tiling = null, float bump = 1f)
        {
            var m = new Material(baseBump) { name = name };
            m.color = color;
            if (m.HasProperty("_MainTex"))
            {
                m.mainTexture = tex;
                if (tiling.HasValue) m.mainTextureScale = tiling.Value;
            }
            if (normal != null && m.HasProperty("_BumpMap"))
            {
                m.SetTexture("_BumpMap", normal);
                if (m.HasProperty("_BumpScale")) m.SetFloat("_BumpScale", bump);
                m.EnableKeyword("_NORMALMAP");
            }
            if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", smooth);
            if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", metal);
            m.enableInstancing = true;
            return m;
        }

        /// <summary>Копия материала с другим тайлингом (тайлинг общий для _MainTex и _BumpMap).</summary>
        public static Material Tiled(Material src, Vector2 tiling)
        {
            var m = new Material(src) { name = src.name + "." + tiling.x + "x" + tiling.y };
            m.mainTextureScale = tiling;
            return m;
        }

        /// <summary>Неосвещаемый прозрачный материал (подсветки, частицы, свечение окон).</summary>
        public static Material Unlit(Color color, Texture tex = null)
        {
            var m = new Material(unlitShader != null ? unlitShader : Shader.Find("Sprites/Default"));
            m.color = color;
            if (tex != null) m.mainTexture = tex;
            return m;
        }
    }
}
