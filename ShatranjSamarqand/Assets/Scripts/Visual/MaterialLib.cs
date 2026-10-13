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

    /// <summary>Все материалы игры. Текстуры генерируются один раз при запуске.</summary>
    public static class MaterialLib
    {
        public static SideStyle White, Black;
        public static Material Steel, Ivory, EyeBlack, Gem, GemBlue;
        public static Material BoardLight, BoardDark, Frame, FrameWood, Inlay, TableWood, Carpet;
        public static Material Paving, Brick, Plaster, TileBlue, TileTurquoise, Dome, NicheDark, Foliage, Trunk;
        public static Material Porcelain, Bread, Kurpacha;
        public static Material SkyMat;

        static Material baseStd;
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
            unlitShader = Shader.Find("Sprites/Default");

            Color lapis = TextureFactory.Hex("#1D4C9A"), turq = TextureFactory.Hex("#25A7A6"), gold = TextureFactory.Hex("#D7A43A");
            Color ivory = TextureFactory.Hex("#F3E8CF"), crimson = TextureFactory.Hex("#A01C26"), emerald = TextureFactory.Hex("#1F7A4D");
            Color brass = TextureFactory.Hex("#B8873A"), ink = TextureFactory.Hex("#1A1410");

            // ---------------------------------------------------------- Белые: светлая чинара + ляпис и золото
            var wLight = TextureFactory.Hex("#EED9AE"); var wDark = TextureFactory.Hex("#C9A46A");
            White = new SideStyle
            {
                Wood = Std("w.wood", Color.white, TextureFactory.Wood("chinor", wLight, wDark, 11), 0.42f, 0f),
                WoodAlt = Std("w.woodalt", Color.white, TextureFactory.Wood("chinor2", TextureFactory.Hex("#9B7346"), TextureFactory.Hex("#6B4A2A"), 12), 0.35f, 0f),
                Robe = Std("w.robe", Color.white, TextureFactory.Ikat("white", new[] { lapis, ivory, turq, gold, TextureFactory.Hex("#7FB3E0") }, 5), 0.38f, 0f),
                Accent = Std("w.accent", lapis, null, 0.55f, 0f),
                Accent2 = Std("w.accent2", turq, null, 0.55f, 0f),
                Metal = Std("w.gold", gold, null, 0.72f, 0.85f),
                Cloth = Std("w.cloth", ivory, TextureFactory.Wood("cloth.w", ivory, TextureFactory.Hex("#DCCFB0"), 21, 14), 0.3f, 0f),
                Cap = Std("w.cap", Color.white, TextureFactory.Doppi("white", TextureFactory.Hex("#1E3E7A"), ivory, 3), 0.35f, 0f),
                Fur = Std("w.fur", Color.white, TextureFactory.Fur("white", TextureFactory.Hex("#CDBFA5"), TextureFactory.Hex("#F6EEDC"), 4), 0.1f, 0f),
                Shield = Std("w.shield", Color.white, TextureFactory.Majolica("shield.w", lapis, turq, ivory, gold, 2, 128), 0.5f, 0.1f),
                Glow = new Color(0.45f, 0.75f, 1f)
            };

            // ---------------------------------------------------------- Чёрные: грецкий орех + гранат и латунь
            var bLight = TextureFactory.Hex("#5A3820"); var bDark = TextureFactory.Hex("#24140A");
            Black = new SideStyle
            {
                Wood = Std("b.wood", Color.white, TextureFactory.Wood("yongoq", bLight, bDark, 31), 0.5f, 0f),
                WoodAlt = Std("b.woodalt", Color.white, TextureFactory.Wood("yongoq2", TextureFactory.Hex("#1C110A"), TextureFactory.Hex("#0C0704"), 32), 0.45f, 0f),
                Robe = Std("b.robe", Color.white, TextureFactory.Ikat("black", new[] { crimson, ink, emerald, gold, TextureFactory.Hex("#5B1A4A") }, 9), 0.42f, 0f),
                Accent = Std("b.accent", crimson, null, 0.55f, 0f),
                Accent2 = Std("b.accent2", emerald, null, 0.55f, 0f),
                Metal = Std("b.brass", brass, null, 0.68f, 0.8f),
                Cloth = Std("b.cloth", Color.white, TextureFactory.Wood("cloth.b", TextureFactory.Hex("#8E1C24"), TextureFactory.Hex("#5E0F16"), 41, 14), 0.3f, 0f),
                Cap = Std("b.cap", Color.white, TextureFactory.Doppi("black", TextureFactory.Hex("#121212"), TextureFactory.Hex("#EDE6D6"), 6), 0.35f, 0f),
                Fur = Std("b.fur", Color.white, TextureFactory.Fur("black", TextureFactory.Hex("#0E0B09"), TextureFactory.Hex("#3A2E25"), 8), 0.1f, 0f),
                Shield = Std("b.shield", Color.white, TextureFactory.Majolica("shield.b", crimson, emerald, ivory, gold, 2, 128), 0.5f, 0.1f),
                Glow = new Color(1f, 0.55f, 0.3f)
            };

            Steel = Std("steel", TextureFactory.Hex("#D8DDE2"), null, 0.86f, 0.92f);
            Ivory = Std("ivory", TextureFactory.Hex("#F4EEDD"), null, 0.6f, 0f);
            EyeBlack = Std("eye", TextureFactory.Hex("#0B0806"), null, 0.9f, 0f);
            Gem = Std("gem", TextureFactory.Hex("#C8102E"), null, 0.95f, 0.2f);
            GemBlue = Std("gemblue", TextureFactory.Hex("#2E7FD9"), null, 0.95f, 0.2f);

            // ---------------------------------------------------------- Доска
            BoardLight = Std("board.light", Color.white, TextureFactory.Wood("board.light", TextureFactory.Hex("#E9D2A2"), TextureFactory.Hex("#CFAE78"), 51, 7), 0.55f, 0f);
            BoardDark = Std("board.dark", Color.white, TextureFactory.Wood("board.dark", TextureFactory.Hex("#7A4A2A"), TextureFactory.Hex("#4A2A16"), 52, 7), 0.55f, 0f);
            Frame = Std("frame", Color.white, TextureFactory.Islimi("frame", TextureFactory.Hex("#173A78"), gold, TextureFactory.Hex("#2BB0AE")), 0.6f, 0.15f);
            FrameWood = Std("frame.wood", Color.white, TextureFactory.Wood("frame.wood", TextureFactory.Hex("#5C3418"), TextureFactory.Hex("#2E180A"), 53, 6), 0.55f, 0f);
            Inlay = Std("inlay", gold, null, 0.7f, 0.8f);
            TableWood = Std("table", Color.white, TextureFactory.Wood("table", TextureFactory.Hex("#7B4B26"), TextureFactory.Hex("#4B2912"), 61, 12), 0.45f, 0f);
            Carpet = Std("carpet", Color.white, TextureFactory.Suzani(), 0.12f, 0f);
            Kurpacha = Std("kurpacha", Color.white, TextureFactory.Ikat("kurpacha", new[] { crimson, gold, emerald, lapis, ivory }, 17, 8), 0.2f, 0f);

            // ---------------------------------------------------------- Окружение
            Paving = Std("paving", Color.white, TextureFactory.Brick("paving", TextureFactory.Hex("#C9A57A"), TextureFactory.Hex("#9C8466"), 71), 0.15f, 0f, new Vector2(18, 18));
            Brick = Std("brick", Color.white, TextureFactory.Brick("wall", TextureFactory.Hex("#D2AD7E"), TextureFactory.Hex("#E8D7BB"), 72, 16, 6), 0.12f, 0f, new Vector2(4, 4));
            Plaster = Std("plaster", TextureFactory.Hex("#E2C9A0"), null, 0.1f, 0f);
            TileBlue = Std("tile.blue", Color.white, TextureFactory.Majolica("blue", TextureFactory.Hex("#173C8C"), TextureFactory.Hex("#27A9B0"), TextureFactory.Hex("#F2EBDA"), gold), 0.55f, 0f, new Vector2(3, 3));
            TileTurquoise = Std("tile.turq", Color.white, TextureFactory.Majolica("turq", TextureFactory.Hex("#1F9AA6"), TextureFactory.Hex("#123E8A"), TextureFactory.Hex("#E9F3EE"), TextureFactory.Hex("#E9C25A")), 0.6f, 0f, new Vector2(2, 2));
            Dome = Std("dome", Color.white, TextureFactory.Majolica("dome", TextureFactory.Hex("#1FA3AE"), TextureFactory.Hex("#2BB8BD"), TextureFactory.Hex("#11507F"), TextureFactory.Hex("#E7F2EE"), 8), 0.7f, 0f, new Vector2(6, 3));
            NicheDark = Std("niche", TextureFactory.Hex("#0F2350"), TextureFactory.Majolica("niche", TextureFactory.Hex("#0E2A62"), TextureFactory.Hex("#163E85"), TextureFactory.Hex("#C9A54B"), TextureFactory.Hex("#2196A0"), 6), 0.4f, 0f, new Vector2(2, 3));
            Foliage = Std("foliage", TextureFactory.Hex("#2F5A2A"), null, 0.15f, 0f);
            Trunk = Std("trunk", TextureFactory.Hex("#5B4030"), null, 0.1f, 0f);
            Porcelain = Std("porcelain", Color.white, TextureFactory.Paxta(), 0.85f, 0f);
            Bread = Std("bread", TextureFactory.Hex("#C98A45"), TextureFactory.Wood("bread", TextureFactory.Hex("#E2A65C"), TextureFactory.Hex("#A6662E"), 81, 20), 0.25f, 0f);

            SkyMat = Unlit(Color.white);
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

        /// <summary>Неосвещаемый прозрачный материал (подсветки, частицы, небо).</summary>
        public static Material Unlit(Color color, Texture tex = null)
        {
            var m = new Material(unlitShader != null ? unlitShader : Shader.Find("Sprites/Default"));
            m.color = color;
            if (tex != null) m.mainTexture = tex;
            return m;
        }
    }
}
